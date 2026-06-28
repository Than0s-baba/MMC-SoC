%% CHB_Batch_Event_Logger.m
% Batch version: Runs multiple Simulink simulations with varying
% refAmp and refFreq, logging gate signals at voltage transition points.
%
% ROOT CAUSE FIX:
%   assignin('base',...) alone does NOT force Simulink to re-read workspace
%   variables between sim() calls — the compiled model caches them.
%   Fix: use set_param() to directly write the value into the Sine Wave
%   block's 'Amplitude' and 'Frequency' parameters as literal numbers.
%   This bypasses the variable lookup entirely and guarantees each run
%   uses the correct values.
%
%   You must set SINE_WAVE_BLOCK_PATH below to match your model.
%
% PREREQUISITES:
%   - Simulink model file: CHB_Model.slx on MATLAB path
%   - Signal logging enabled for output voltage + all 16 gate signals
%   - Simulink Configuration: Data Import/Export → logsout enabled
%   - SINE_WAVE_BLOCK_PATH must point to your Sine Wave Generator block
%
% OUTPUT:
%   gate_logs/
%     gate_logs_index.csv
%     gate_logs_refAmp=20.0_refFreq=20.5.csv   (one per run)
% =========================================================================

clear; clc;

fprintf('========== CHB BATCH EVENT LOGGER ==========\n\n');

%% =========================================================================
%% --- CONFIGURATION ---
%% =========================================================================

model_name  = 'CHB_Model';
output_dir  = 'gate_logs';
t_sim       = 0.5;           % seconds — covers 10 cycles at 20Hz

% ---- Parameter sweep ----
amplitudes  = 20;            % constant 20V
frequencies = 20:0.5:50;     % 61 values: 20.0, 20.5, 21.0 ... 50.0

% ---- CRITICAL: path to your Sine Wave Generator block ----
% Find this by right-clicking your Sine Wave block → Properties → path
% It is usually: 'ModelName/BlockName'
% Examples:
%   'CHB_Model/Sine Wave'
%   'CHB_Model/Reference Generator/Sine Wave'
% To find it programmatically, run this in MATLAB command window first:
%   load_system('CHB_Model')
%   find_system('CHB_Model','BlockType','Sin')
SINE_WAVE_BLOCK_PATH = 'CHB_Model/Sine Wave2';   % <-- EDIT THIS

% ---- Voltage signal candidates (first match in logsout is used) ----
voltage_signal_candidates = {'V_actual', 'V_output', 'V_ref', 'Vout', 'v_out'};

% ---- Gate signal names ----
gate_names = {
    's1g1', 's1g2', 's1g3', 's1g4', ...
    's2g1', 's2g2', 's2g3', 's2g4', ...
    's3g1', 's3g2', 's3g3', 's3g4', ...
    's4g1', 's4g2', 's4g3', 's4g4'
};

% ---- Transition detection ----
change_threshold = 0.1;   % Volts — change above this = transition event

% ---- Warmup discard ----
% Skip transitions in first N cycles to exclude startup transients.
% At 20Hz, 2 cycles = 0.1s. This ensures only steady-state data is logged.
warmup_cycles = 2;

%% =========================================================================
%% --- SETUP ---
%% =========================================================================

total_runs = length(amplitudes) * length(frequencies);

fprintf('Model           : %s.slx\n', model_name);
fprintf('Sine Wave block : %s\n', SINE_WAVE_BLOCK_PATH);
fprintf('Amplitude       : %g V (constant)\n', amplitudes);
fprintf('Frequency range : %.1f to %.1f Hz (step 0.5)\n', ...
        min(frequencies), max(frequencies));
fprintf('Total runs      : %d\n', total_runs);
fprintf('Stop time       : %.2f s\n', t_sim);
fprintf('Warmup discard  : %d cycles\n', warmup_cycles);
fprintf('Output folder   : %s/\n\n', output_dir);

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
    fprintf('✓ Created output folder: %s\n\n', output_dir);
end

idx_run_id   = zeros(total_runs, 1);
idx_amp      = zeros(total_runs, 1);
idx_freq     = zeros(total_runs, 1);
idx_ntrans   = zeros(total_runs, 1);
idx_status   = cell(total_runs, 1);
idx_filename = cell(total_runs, 1);

run_counter = 0;

%% =========================================================================
%% --- LOAD MODEL ---
%% =========================================================================

try
    load_system(model_name);
    fprintf('✓ Model loaded: %s\n', model_name);
catch ME
    error('Cannot load model "%s": %s', model_name, ME.message);
end

% ---- Verify sine wave block path is valid ----
try
    get_param(SINE_WAVE_BLOCK_PATH, 'BlockType');
    fprintf('✓ Sine Wave block found: %s\n\n', SINE_WAVE_BLOCK_PATH);
catch
    % Block not found — help the user find the right path
    fprintf('\n⚠ Sine Wave block not found at: %s\n', SINE_WAVE_BLOCK_PATH);
    fprintf('  Searching for Sin blocks in model...\n');
    sin_blocks = find_system(model_name, 'BlockType', 'Sin');
    if isempty(sin_blocks)
        sin_blocks = find_system(model_name, 'BlockType', 'SubSystem');
    end
    fprintf('  Found these Sin-type blocks:\n');
    for k = 1:length(sin_blocks)
        fprintf('    → %s\n', sin_blocks{k});
    end
    error(['Set SINE_WAVE_BLOCK_PATH to one of the paths shown above.\n' ...
           'Then re-run this script.']);
end

%% =========================================================================
%% --- BATCH SIMULATION LOOP ---
%% =========================================================================

for amp = amplitudes
    for freq = frequencies

        run_counter = run_counter + 1;

        fprintf('[%3d/%3d]  Amp=%5.1fV  Freq=%5.1fHz  -->  ', ...
                run_counter, total_runs, amp, freq);

        %% --- DIRECTLY SET BLOCK PARAMETERS ---
        % Writing literal numbers (not variable names) into the block.
        % This is the only guaranteed way to change values between sim() calls.
        % assignin is kept as backup for any workspace-reading subsystems.
        try
            set_param(SINE_WAVE_BLOCK_PATH, 'Amplitude',  num2str(amp,  '%.6g'));
            set_param(SINE_WAVE_BLOCK_PATH, 'Frequency',  num2str(freq, '%.6g'));
        catch ME
            fprintf('✗ set_param failed: %s\n', ME.message);
            idx_run_id(run_counter)   = run_counter;
            idx_amp(run_counter)      = amp;
            idx_freq(run_counter)     = freq;
            idx_ntrans(run_counter)   = 0;
            idx_status{run_counter}   = 'failed: set_param error';
            idx_filename{run_counter} = '';
            continue;
        end

        % Also update base workspace (for any other blocks that read variables)
        assignin('base', 'refAmp',  amp);
        assignin('base', 'refFreq', freq);

        try
            %% --- Run simulation ---
            simOut = sim(model_name, ...
                         'StopTime',          num2str(t_sim), ...
                         'SaveOutput',        'on', ...
                         'SignalLoggingName', 'logsout');

            %% --- Retrieve logsout ---
            if ~isfield(simOut, 'logsout') && ~isprop(simOut, 'logsout')
                error('logsout not found. Enable signal logging in Simulink Configuration.');
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
                error('No voltage signal found in logsout. Available: %s', ...
                      strjoin(logged_names, ', '));
            end

            %% --- Extract time and voltage ---
            V_elem = logsout_data.getElement(voltage_signal_name);
            t_log  = V_elem.Values.Time(:);
            V_log  = double(V_elem.Values.Data(:));
            N      = length(t_log);

            %% --- Extract gate signals ---
            gate_data = zeros(N, length(gate_names));
            for gi = 1:length(gate_names)
                gname = gate_names{gi};
                if ~ismember(gname, logged_names)
                    warning('CHB_Batch_Event_Logger:missingGate', ...
                            'Gate "%s" not in logsout — column will be zero.', gname);
                    continue;
                end
                g_elem = logsout_data.getElement(gname);
                g_time = g_elem.Values.Time(:);
                g_data = double(g_elem.Values.Data(:));
                if isequal(g_time, t_log)
                    gate_data(:, gi) = g_data;
                else
                    gate_data(:, gi) = interp1(g_time, g_data, t_log, ...
                                               'previous', 'extrap');
                end
            end

            %% --- Detect transitions ---
            dV        = diff(V_log);
            trans_idx = find(abs(dV) > change_threshold) + 1;
            trans_idx = unique([1; trans_idx(:); N]);

            %% --- Discard warmup transitions ---
            warmup_time = warmup_cycles / freq;
            keep_mask   = t_log(trans_idx) > warmup_time;
            trans_idx   = trans_idx(keep_mask);

            if isempty(trans_idx)
                warning('No transitions found after warmup for freq=%.1f. Lowering warmup.', freq);
                trans_idx = unique([1; find(abs(diff(V_log)) > change_threshold)+1; N]);
            end

            num_trans = length(trans_idx);

            %% --- Build table ---
            time_col  = t_log(trans_idx);
            amp_col   = repmat(double(amp),  num_trans, 1);
            freq_col  = repmat(double(freq), num_trans, 1);
            volt_col  = V_log(trans_idx);
            gates_col = gate_data(trans_idx, :);

            col_names   = [{'Timestamp_s','refAmp_V','refFreq_Hz','V_output_V'}, gate_names];
            data_matrix = [time_col, amp_col, freq_col, volt_col, gates_col];
            T = array2table(data_matrix, 'VariableNames', col_names);

            %% --- Write CSV (use %.1f for freq to preserve 0.5 steps) ---
            csv_name     = sprintf('gate_logs_refAmp=%.1f_refFreq=%.1f.csv', amp, freq);
            csv_fullpath = fullfile(output_dir, csv_name);
            writetable(T, csv_fullpath);

            idx_run_id(run_counter)   = run_counter;
            idx_amp(run_counter)      = amp;
            idx_freq(run_counter)     = freq;
            idx_ntrans(run_counter)   = num_trans;
            idx_status{run_counter}   = 'success';
            idx_filename{run_counter} = csv_name;

            fprintf('✓  %d transitions  →  %s\n', num_trans, csv_name);

        catch ME
            msg = ME.message;
            if length(msg) > 80, msg = [msg(1:80) '...']; end
            idx_run_id(run_counter)   = run_counter;
            idx_amp(run_counter)      = amp;
            idx_freq(run_counter)     = freq;
            idx_ntrans(run_counter)   = 0;
            idx_status{run_counter}   = ['failed: ' msg];
            idx_filename{run_counter} = '';
            fprintf('✗  %s\n', msg);
        end

    end % freq loop
end % amp loop

%% =========================================================================
%% --- RESTORE BLOCK TO VARIABLE NAMES (optional but clean) ---
%% =========================================================================
% Puts the block parameters back to variable names so the model
% works normally when opened manually after the batch run.
try
    set_param(SINE_WAVE_BLOCK_PATH, 'Amplitude', 'refAmp');
    set_param(SINE_WAVE_BLOCK_PATH, 'Frequency', 'refFreq');
    fprintf('\n✓ Block parameters restored to refAmp / refFreq\n');
catch
    fprintf('\n⚠ Could not restore block parameters — set manually if needed\n');
end

%% =========================================================================
%% --- CLOSE MODEL ---
%% =========================================================================
try
    close_system(model_name, 0);
catch
end

%% =========================================================================
%% --- MASTER INDEX ---
%% =========================================================================

n_success = sum(strcmp(idx_status, 'success'));
n_failed  = total_runs - n_success;

master_table = table(idx_run_id, idx_amp, idx_freq, idx_ntrans, ...
    'VariableNames', {'RunID','Amplitude_V','Frequency_Hz','Num_Transitions'});

master_path = fullfile(output_dir, 'gate_logs_index.csv');
writetable(master_table, master_path);

fprintf('\n========== BATCH COMPLETE ==========\n');
fprintf('Total   : %d\n', total_runs);
fprintf('Success : %d\n', n_success);
fprintf('Failed  : %d\n', n_failed);
fprintf('Index   : %s\n', master_path);
fprintf('=====================================\n\n');

%% --- Preview ---
first_ok = find(strcmp(idx_status, 'success'), 1);
if ~isempty(first_ok)
    T_preview = readtable(fullfile(output_dir, idx_filename{first_ok}));
    fprintf('Preview of %s (first 5 rows):\n', idx_filename{first_ok});
    disp(T_preview(1:min(5, height(T_preview)), :));
end