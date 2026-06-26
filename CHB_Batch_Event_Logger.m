%% CHB_Batch_Event_Logger.m
% Batch version: Runs multiple Simulink simulations with varying amplitude/frequency
% and logs gate signals at voltage change points for each run.
%
% Creates individual CSV files for each simulation, plus a master index.
%
% PREREQUISITES:
%   - Simulink model: CHB_Model.slx (with signal logging enabled)
%   - Model parameters: refAmp, refFreq (tunable)
%   - Logged signals: V_actual (or similar), s1g1-s4g4
%
% OUTPUT:
%   - gate_logs/ folder containing:
%     - gate_logs_refAmp=10_refFreq=50.csv (per simulation)
%     - gate_logs_index.csv (summary of all runs)
%
% =========================================================================

clear; clc;

fprintf('========== CHB BATCH EVENT LOGGER ==========\n\n');

%% --- Configuration ---

model_name = 'CHB_Model';
output_dir = 'gate_logs';
t_sim = 0.2;  % Simulation time per run (seconds)

% Parameter ranges
amplitudes = 5:5:20;    % 4 amplitudes
frequencies = 30:20:90; % 4 frequencies
total_runs = length(amplitudes) * length(frequencies);

fprintf('Model: %s.slx\n', model_name);
fprintf('Amplitudes: %d values\n', length(amplitudes));
fprintf('Frequencies: %d values\n', length(frequencies));
fprintf('Total runs: %d\n', total_runs);
fprintf('Output directory: %s/\n\n', output_dir);

% Create output directory
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
    fprintf('✓ Created directory: %s\n\n', output_dir);
end

% Gate signal names
gate_names = {
    's1g1', 's1g2', 's1g3', 's1g4', ...
    's2g1', 's2g2', 's2g3', 's2g4', ...
    's3g1', 's3g2', 's3g3', 's3g4', ...
    's4g1', 's4g2', 's4g3', 's4g4'
};

%% --- Initialize master index ---

master_index = struct();
master_index.run_id = [];
master_index.amplitude_V = [];
master_index.frequency_Hz = [];
master_index.filename = {};
master_index.num_transitions = [];
master_index.sim_status = {};

run_counter = 0;

%% --- Load model ---

try
    load_system(model_name);
    fprintf('✓ Loaded model: %s\n\n', model_name);
catch ME
    error('Cannot load model %s. Error: %s', model_name, ME.message);
end

%% --- BATCH LOOP ---

for amp = amplitudes
    for freq = frequencies
        run_counter = run_counter + 1;
        
        fprintf('[%2d/%2d] Running: refAmp=%.1fV, refFreq=%.0fHz... ', ...
                run_counter, total_runs, amp, freq);

        % Set parameters
        assignin('base', 'refAmp', amp);
        assignin('base', 'refFreq', freq);
        set_param(model_name, 'refAmp', num2str(amp));
        set_param(model_name, 'refFreq', num2str(freq));

        try
            % Run simulation
            simOut = sim(model_name, 'StopTime', num2str(t_sim));

            % ---- Extract and process logged signals ----
            logsout = simOut.logsout;
            
            % Find voltage signal
            logged_signals = logsout.getElementNames;
            voltage_signal_name = '';
            for name = {'V_actual', 'V_output', 'V_ref'}
                if ismember(name{1}, logged_signals)
                    voltage_signal_name = name{1};
                    break;
                end
            end

            if isempty(voltage_signal_name)
                error('No voltage signal found');
            end

            % Extract time and voltage
            V_signal = logsout.getElement(voltage_signal_name);
            t_log = V_signal.Values.Time;
            V_log = V_signal.Values.Data;

            % Extract gate signals
            gate_data = zeros(length(t_log), length(gate_names));
            for i = 1:length(gate_names)
                if ismember(gate_names{i}, logged_signals)
                    gate_signal = logsout.getElement(gate_names{i});
                    gate_data(:, i) = gate_signal.Values.Data;
                end
            end

            % ---- Detect voltage changes ----
            V_changes = diff(V_log);
            change_threshold = 0.1;  % Volts
            change_indices = find(abs(V_changes) > change_threshold) + 1;
            change_indices = unique([1; change_indices(:); length(t_log)]);

            num_changes = length(change_indices);

            % ---- Create output table ----
            time_col = t_log(change_indices);
            amp_col = repmat(amp, num_changes, 1);
            freq_col = repmat(freq, num_changes, 1);
            voltage_col = V_log(change_indices);
            gates_col = gate_data(change_indices, :);

            var_names = {'Timestamp_s', 'refAmp_V', 'refFreq_Hz', ...
                         'V_output_V', gate_names{:}};
            data_array = [time_col, amp_col, freq_col, voltage_col, gates_col];
            T = array2table(data_array, 'VariableNames', var_names);

            % ---- Export to CSV ----
            csv_filename = sprintf('gate_logs_refAmp=%.1f_refFreq=%.0f.csv', ...
                                   amp, freq);
            csv_fullpath = fullfile(output_dir, csv_filename);
            writetable(T, csv_fullpath);

            % ---- Store in master index ----
            master_index.run_id(run_counter) = run_counter;
            master_index.amplitude_V(run_counter) = amp;
            master_index.frequency_Hz(run_counter) = freq;
            master_index.filename{run_counter} = csv_filename;
            master_index.num_transitions(run_counter) = num_changes;
            master_index.sim_status{run_counter} = 'success';

            fprintf('✓ (%d transitions)\n', num_changes);

        catch ME
            fprintf('✗ %s\n', ME.message(1:50));
            
            master_index.run_id(run_counter) = run_counter;
            master_index.amplitude_V(run_counter) = amp;
            master_index.frequency_Hz(run_counter) = freq;
            master_index.filename{run_counter} = '';
            master_index.num_transitions(run_counter) = 0;
            master_index.sim_status{run_counter} = sprintf('failed: %s', ...
                                                           ME.message(1:30));
        end

    end
end

close_system(model_name);

%% --- Create Master Index CSV ---

fprintf('\n--- Creating Master Index ---\n');

master_table = table(...
    master_index.run_id', ...
    master_index.amplitude_V', ...
    master_index.frequency_Hz', ...
    master_index.num_transitions', ...
    'VariableNames', ...
    {'RunID', 'Amplitude_V', 'Frequency_Hz', 'Transitions'});

master_index_path = fullfile(output_dir, 'gate_logs_index.csv');
writetable(master_table, master_index_path);

fprintf('✓ Master index: %s\n', master_index_path);
fprintf('  %d total runs\n', total_runs);
fprintf('  %d successful\n', sum(strcmp(master_index.sim_status, 'success')));
fprintf('  %d failed\n', total_runs - sum(strcmp(master_index.sim_status, 'success')));

%% --- Summary ---

fprintf('\n========== BATCH LOGGING COMPLETE ==========\n\n');

fprintf('Output files in: %s/\n', output_dir);
fprintf('  - gate_logs_index.csv (master summary)\n');
fprintf('  - gate_logs_refAmp=X_refFreq=Y.csv (one per simulation)\n\n');

% Show a sample CSV file
if exist(fullfile(output_dir, master_index.filename{1}), 'file')
    sample_file = fullfile(output_dir, master_index.filename{1});
    fprintf('Sample file preview (%s):\n', master_index.filename{1});
    sample_T = readtable(sample_file);
    disp(sample_T(1:min(5, height(sample_T)), :));
end

fprintf('\n========================================\n');

end
