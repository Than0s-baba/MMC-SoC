%% CHB_Batch_Event_Logger.m
% Batch version: Runs multiple Simulink simulations with varying
% refAmp and refFreq (read from BASE WORKSPACE by the model).
% Logs gate signals at output voltage change points for each run.
%
% PARAMETER SOURCE: Base workspace (assignin)
%   The model reads refAmp and refFreq directly from the MATLAB base
%   workspace. set_param() is NOT used — only assignin('base',...).
%
% PREREQUISITES:
%   - Simulink model file: CHB_Model.slx
%   - Model reads refAmp, refFreq from base workspace
%   - Signal logging enabled for: output voltage + all gate signals
%   - Simulink Configuration: Data Import/Export → logsout enabled
%
% SIGNAL NAMING (edit CONFIGURATION section if your names differ):
%   Voltage output signal  : V_actual  (or V_output / V_ref)
%   Gate signals           : s1g1 ... s4g4
%
% OUTPUT:
%   gate_logs/
%     gate_logs_index.csv                       (master summary)
%     gate_logs_refAmp=10.0_refFreq=50.csv      (one per simulation)
%
% =========================================================================

clear; clc;

fprintf('========== CHB BATCH EVENT LOGGER ==========\n\n');

%% =========================================================================
%% --- CONFIGURATION (edit these to match your model) ---
%% =========================================================================

model_name    = 'CHB_Model';   % Simulink model filename (no .slx)
output_dir    = 'gate_logs';   % Folder to write CSV files into
t_sim         = 0.2;           % Simulation duration per run (seconds)
                               % 0.2s @ 50Hz = 10 full cycles

% ---- Parameter sweep ranges ----
amplitudes  = 5:5:20;          % e.g. [5, 10, 15, 20] V
frequencies = 30:20:90;        % e.g. [30, 50, 70, 90] Hz

% ---- Voltage signal name (as logged by Simulink) ----
% The script searches for the first match in this list.
% Add your actual signal name here if it differs.
voltage_signal_candidates = {'V_actual', 'V_output', 'V_ref', 'Vout', 'v_out'};

% ---- Gate signal names (must match Simulink signal logging names) ----
gate_names = {
    's1g1', 's1g2', 's1g3', 's1g4', ...
    's2g1', 's2g2', 's2g3', 's2g4', ...
    's3g1', 's3g2', 's3g3', 's3g4', ...
    's4g1', 's4g2', 's4g3', 's4g4'
};

% ---- Transition detection sensitivity ----
% A voltage change larger than this threshold counts as a transition.
% 0.1V works well for a ±20V quantized output with 5V steps.
change_threshold = 0.1;  % Volts

%% =========================================================================
%% --- SETUP ---
%% =========================================================================

total_runs = length(amplitudes) * length(frequencies);

fprintf('Model         : %s.slx\n', model_name);
fprintf('Amplitudes    : %s V\n', num2str(amplitudes));
fprintf('Frequencies   : %s Hz\n', num2str(frequencies));
fprintf('Total runs    : %d\n', total_runs);
fprintf('Sim duration  : %.2f s per run\n', t_sim);
fprintf('Output folder : %s/\n\n', output_dir);

% Create output folder
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
    fprintf('✓ Created output folder: %s\n\n', output_dir);
end

% Initialize master index storage
idx_run_id    = zeros(total_runs, 1);
idx_amp       = zeros(total_runs, 1);
idx_freq      = zeros(total_runs, 1);
idx_ntrans    = zeros(total_runs, 1);
idx_status    = cell(total_runs, 1);
idx_filename  = cell(total_runs, 1);

run_counter   = 0;

%% =========================================================================
%% --- LOAD MODEL ---
%% =========================================================================

try
    load_system(model_name);
    fprintf('✓ Model loaded: %s\n\n', model_name);
catch ME
    error(['Cannot load model "%s".\n' ...
           'Make sure the .slx file is on the MATLAB path.\n' ...
           'Error: %s'], model_name, ME.message);
end

%% =========================================================================
%% --- BATCH SIMULATION LOOP ---
%% =========================================================================

for amp = amplitudes
    for freq = frequencies

        run_counter = run_counter + 1;

        fprintf('[%2d/%2d]  refAmp = %5.1f V   refFreq = %4.0f Hz  -->  ', ...
                run_counter, total_runs, amp, freq);

        %% --- Write parameters to base workspace ---
        % This is the ONLY way to pass values when model uses base workspace.
        % set_param() is intentionally NOT used here.
        assignin('base', 'refAmp',  amp);
        assignin('base', 'refFreq', freq);

        try
            %% --- Run simulation ---
            simOut = sim(model_name, ...
                         'StopTime',            num2str(t_sim), ...
                         'SaveOutput',          'on', ...
                         'SignalLoggingName',   'logsout');

            %% --- Retrieve logged signal container ---
            if ~isfield(simOut, 'logsout') && ~isprop(simOut, 'logsout')
                error('logsout not found in simulation output. Enable signal logging in Simulink.');
            end
            logsout_data = simOut.logsout;

            logged_names = logsout_data.getElementNames();

            %% --- Find voltage signal ---
            voltage_signal_name = '';
            for k = 1:length(voltage_signal_candidates)
                if ismember(voltage_signal_candidates{k}, logged_names)
                    voltage_signal_name = voltage_signal_candidates{k};
                    break;
                end
            end

            if isempty(voltage_signal_name)
                error(['Output voltage signal not found in logsout.\n' ...
                       'Logged signals are: %s\n' ...
                       'Add your voltage signal name to voltage_signal_candidates.'], ...
                       strjoin(logged_names, ', '));
            end

            %% --- Extract time and voltage vectors ---
            V_elem   = logsout_data.getElement(voltage_signal_name);
            t_log    = V_elem.Values.Time;       % [N×1] seconds
            V_log    = double(V_elem.Values.Data); % [N×1] volts

            % Flatten in case signal is [N×1×1]
            t_log = t_log(:);
            V_log = V_log(:);
            N     = length(t_log);

            %% --- Extract gate signals (resample to voltage time base) ---
            gate_data = zeros(N, length(gate_names));

            for gi = 1:length(gate_names)
                gname = gate_names{gi};

                if ~ismember(gname, logged_names)
                    % Gate not logged — leave column as zeros, warn once
                    warning('CHB_Batch_Event_Logger:missingGate', ...
                            'Gate signal "%s" not found in logsout. Column will be zero.', gname);
                    continue;
                end

                g_elem  = logsout_data.getElement(gname);
                g_time  = g_elem.Values.Time(:);
                g_data  = double(g_elem.Values.Data(:));

                % Resample gate signal onto the voltage time base
                % (signals may have been logged at different rates)
                if isequal(g_time, t_log)
                    % Same time base — use directly
                    gate_data(:, gi) = g_data;
                else
                    % Interpolate using previous-value (zero-order hold)
                    % appropriate for discrete gate signals
                    gate_data(:, gi) = interp1(g_time, g_data, t_log, ...
                                               'previous', 'extrap');
                end
            end

            %% --- Detect voltage transition indices ---
            dV = diff(V_log);
            trans_idx = find(abs(dV) > change_threshold) + 1;

            % Always include first and last sample
            trans_idx = unique([1; trans_idx(:); N]);
            num_trans = length(trans_idx);

            %% --- Build output table ---
            time_col    = t_log(trans_idx);
            amp_col     = repmat(double(amp),  num_trans, 1);
            freq_col    = repmat(double(freq), num_trans, 1);
            volt_col    = V_log(trans_idx);
            gates_col   = gate_data(trans_idx, :);

            col_names   = [{'Timestamp_s', 'refAmp_V', 'refFreq_Hz', 'V_output_V'}, ...
                            gate_names];
            data_matrix = [time_col, amp_col, freq_col, volt_col, gates_col];

            T = array2table(data_matrix, 'VariableNames', col_names);

            %% --- Write CSV ---
            csv_name     = sprintf('gate_logs_refAmp=%.1f_refFreq=%.0f.csv', amp, freq);
            csv_fullpath = fullfile(output_dir, csv_name);
            writetable(T, csv_fullpath);

            %% --- Log success in master index ---
            idx_run_id(run_counter)   = run_counter;
            idx_amp(run_counter)      = amp;
            idx_freq(run_counter)     = freq;
            idx_ntrans(run_counter)   = num_trans;
            idx_status{run_counter}   = 'success';
            idx_filename{run_counter} = csv_name;

            fprintf('✓  %d transitions  →  %s\n', num_trans, csv_name);

        catch ME
            % Truncate error message safely
            msg_short = ME.message;
            if length(msg_short) > 80
                msg_short = [msg_short(1:80) '...'];
            end

            idx_run_id(run_counter)   = run_counter;
            idx_amp(run_counter)      = amp;
            idx_freq(run_counter)     = freq;
            idx_ntrans(run_counter)   = 0;
            idx_status{run_counter}   = ['failed: ' msg_short];
            idx_filename{run_counter} = '';

            fprintf('✗  %s\n', msg_short);
        end

    end % freq loop
end % amp loop

%% =========================================================================
%% --- CLOSE MODEL ---
%% =========================================================================

try
    close_system(model_name, 0);  % 0 = do not save changes
catch
    % Ignore if already closed
end

%% =========================================================================
%% --- WRITE MASTER INDEX CSV ---
%% =========================================================================

n_success = sum(strcmp(idx_status, 'success'));
n_failed  = total_runs - n_success;

master_table = table( ...
    idx_run_id, idx_amp, idx_freq, idx_ntrans, ...
    'VariableNames', {'RunID', 'Amplitude_V', 'Frequency_Hz', 'Num_Transitions'});

master_path = fullfile(output_dir, 'gate_logs_index.csv');
writetable(master_table, master_path);

fprintf('\n========== BATCH COMPLETE ==========\n');
fprintf('Total runs  : %d\n', total_runs);
fprintf('Successful  : %d\n', n_success);
fprintf('Failed      : %d\n', n_failed);
fprintf('Output dir  : %s/\n', output_dir);
fprintf('Master index: %s\n', master_path);
fprintf('=====================================\n\n');

%% --- Preview first successful CSV ---
first_ok = find(strcmp(idx_status, 'success'), 1);
if ~isempty(first_ok)
    preview_path = fullfile(output_dir, idx_filename{first_ok});
    fprintf('Preview of %s (first 8 rows):\n', idx_filename{first_ok});
    T_preview = readtable(preview_path);
    disp(T_preview(1:min(8, height(T_preview)), :));
end

