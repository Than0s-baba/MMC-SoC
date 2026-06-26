%% CHB_Process_Event_Driven_Logs.m
% Extracts gate signals at timestamps where the output voltage changes.
% Requires Simulink signal logging to be enabled.
%
% PREREQUISITES:
%   1. Simulink model must have signal logging enabled
%   2. These signals must be logged:
%       - V_ref (or V_actual): Reference/output voltage
%       - s1g1, s1g2, s1g3, s1g4 (SM1 gates)
%       - s2g1, s2g2, s2g3, s2g4 (SM2 gates)
%       - s3g1, s3g2, s3g3, s3g4 (SM3 gates)
%       - s4g1, s4g2, s4g3, s4g4 (SM4 gates)
%   3. Model parameters in workspace:
%       - refAmp (amplitude in V)
%       - refFreq (frequency in Hz)
%
% HOW TO ENABLE SIGNAL LOGGING IN SIMULINK:
%   (a) For each signal you want to log:
%       - Right-click on signal line → Log Signals
%       - Signal will appear in Simulink.SimulationOutput after running
%   (b) Or use: set_param(signal_handle, 'DataLoggingNameMode', 'SignalName')
%
% OUTPUT:
%   - gate_transitions.csv (main output)
%     Contains: time, refAmp, refFreq, V_output, all 16 gate signals
%   - gate_log_raw.mat (backup raw data)
%
% =========================================================================

clear; clc;

fprintf('========== EVENT-DRIVEN GATE LOGGING PROCESSOR ==========\n\n');

%% --- Step 1: Check if simulation output exists ---

% After running your Simulink model, the logged data is in 'logsout'
% This is a Simulink.SimulationOutput object

if ~exist('logsout', 'var')
    error(['logsout not found in workspace. \n\n' ...
           'Make sure you:\n' ...
           '1. Have signal logging enabled in your Simulink model\n' ...
           '2. Run the simulation (e.g., sim(''CHB_Model''))\n' ...
           '3. Do NOT clear the workspace before running this script']);
end

fprintf('✓ Found logsout object\n');

%% --- Step 2: Extract logged signals ---

% Get list of all logged signals
logged_signals = logsout.getElementNames;
fprintf('\n--- Logged Signals (%d total) ---\n', length(logged_signals));
for i = 1:length(logged_signals)
    fprintf('  %d. %s\n', i, logged_signals{i});
end

%% --- Step 3: Identify which signals we need ---

% Look for output voltage signal (could be V_actual, V_output, V_ref, etc.)
voltage_signal_name = '';
possible_names = {'V_actual', 'V_output', 'V_ref', 'V_out'};

for name = possible_names
    if ismember(name{1}, logged_signals)
        voltage_signal_name = name{1};
        break;
    end
end

if isempty(voltage_signal_name)
    error('Could not find voltage signal. Expected one of: %s', ...
          strjoin(possible_names, ', '));
end

fprintf('\n✓ Using voltage signal: %s\n', voltage_signal_name);

% Gate signal names (user specified: s1g1, s1g2, ... s4g4)
gate_names = {
    's1g1', 's1g2', 's1g3', 's1g4', ...
    's2g1', 's2g2', 's2g3', 's2g4', ...
    's3g1', 's3g2', 's3g3', 's3g4', ...
    's4g1', 's4g2', 's4g3', 's4g4'
};

% Verify all gate signals exist
fprintf('\n--- Checking for Gate Signals ---\n');
missing_gates = {};
for i = 1:length(gate_names)
    if ismember(gate_names{i}, logged_signals)
        fprintf('  ✓ %s\n', gate_names{i});
    else
        fprintf('  ✗ %s (NOT FOUND)\n', gate_names{i});
        missing_gates = [missing_gates, gate_names{i}];
    end
end

if ~isempty(missing_gates)
    warning('Missing gate signals: %s\n', strjoin(missing_gates, ', '));
    fprintf('Proceeding with available gates...\n\n');
    % Filter to only available gates
    gate_names = gate_names(ismember(gate_names, logged_signals));
end

%% --- Step 4: Extract time and data from logged signals ---

fprintf('\n--- Extracting Data ---\n');

% Get voltage signal
V_signal = logsout.getElement(voltage_signal_name);
t_log = V_signal.Values.Time;
V_log = V_signal.Values.Data;

fprintf('  Time vector: %d samples\n', length(t_log));
fprintf('  Time range: [%.6f, %.6f] s\n', t_log(1), t_log(end));
fprintf('  Voltage range: [%.2f, %.2f] V\n', min(V_log), max(V_log));

% Get gate signals
gate_data = zeros(length(t_log), length(gate_names));
for i = 1:length(gate_names)
    gate_signal = logsout.getElement(gate_names{i});
    gate_data(:, i) = gate_signal.Values.Data;
end

fprintf('  Gate signals: %d × %d matrix\n\n', size(gate_data, 1), size(gate_data, 2));

%% --- Step 5: Detect output voltage change points ---

% Find where voltage changes (allowing for small numerical noise)
V_changes = diff(V_log);
% Mark transitions where voltage change exceeds threshold (e.g., > 0.1V)
change_threshold = 0.1;  % Volts
change_indices = find(abs(V_changes) > change_threshold) + 1;

fprintf('--- Change Point Detection ---\n');
fprintf('  Change threshold: %.2f V\n', change_threshold);
fprintf('  Total change points detected: %d\n', length(change_indices));

if length(change_indices) == 0
    warning('No significant voltage changes detected. Using all time points.');
    change_indices = 1:length(t_log);  % Fall back to all points
end

% Add first and last points
change_indices = unique([1; change_indices(:); length(t_log)]);

fprintf('  Change points (first 10): %s...\n\n', ...
        sprintf('%d ', change_indices(1:min(10, length(change_indices)))));

%% --- Step 6: Get reference parameters from workspace ---

if exist('refAmp', 'var')
    ref_amp = refAmp;
    fprintf('✓ refAmp: %.2f V\n', ref_amp);
else
    ref_amp = NaN;
    fprintf('⚠ refAmp not found, using NaN\n');
end

if exist('refFreq', 'var')
    ref_freq = refFreq;
    fprintf('✓ refFreq: %.2f Hz\n', ref_freq);
else
    ref_freq = NaN;
    fprintf('⚠ refFreq not found, using NaN\n');
end

fprintf('\n');

%% --- Step 7: Create output table ---

n_changes = length(change_indices);

% Initialize table arrays
time_col = t_log(change_indices);
amp_col = repmat(ref_amp, n_changes, 1);
freq_col = repmat(ref_freq, n_changes, 1);
voltage_col = V_log(change_indices);
gates_col = gate_data(change_indices, :);

% Create table with proper column names
var_names = {'Timestamp_s', 'refAmp_V', 'refFreq_Hz', 'V_output_V'};
var_names = [var_names, gate_names];

data_array = [time_col, amp_col, freq_col, voltage_col, gates_col];

T = array2table(data_array, 'VariableNames', var_names);

fprintf('--- Output Table Created ---\n');
fprintf('  Rows: %d (change points)\n', height(T));
fprintf('  Columns: %d\n', width(T));
fprintf('\nFirst 10 rows:\n');
disp(T(1:min(10, height(T)), :));

%% --- Step 8: Export to CSV ---

csv_filename = sprintf('gate_transitions_%s.csv', ...
                        datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
writetable(T, csv_filename);
fprintf('\n✓ Exported: %s\n', csv_filename);

%% --- Step 9: Save backup MAT file ---

mat_filename = 'gate_log_raw.mat';
save(mat_filename, 'T', 't_log', 'V_log', 'gate_data', 'gate_names', ...
     'change_indices', 'ref_amp', 'ref_freq');
fprintf('✓ Saved raw data: %s\n', mat_filename);

%% --- Step 10: Generate statistics ---

fprintf('\n========== SUMMARY STATISTICS ==========\n');

fprintf('\nReference Parameters:\n');
fprintf('  Amplitude: %.2f V\n', ref_amp);
fprintf('  Frequency: %.2f Hz\n', ref_freq);

fprintf('\nOutput Voltage Statistics:\n');
fprintf('  Min: %.4f V\n', min(V_log));
fprintf('  Max: %.4f V\n', max(V_log));
fprintf('  Mean: %.4f V\n', mean(V_log));
fprintf('  Std Dev: %.4f V\n', std(V_log));

fprintf('\nGate Signal Statistics (at change points):\n');
for i = 1:length(gate_names)
    gate_on_count = sum(gates_col(:, i) > 0.5);
    gate_on_pct = 100 * gate_on_count / n_changes;
    fprintf('  %s: ON at %.1f%% of change points (%d/%d)\n', ...
            gate_names{i}, gate_on_pct, gate_on_count, n_changes);
end

fprintf('\nTiming:\n');
fprintf('  Total simulation time: %.4f s\n', t_log(end) - t_log(1));
fprintf('  Number of voltage changes: %d\n', n_changes);
fprintf('  Average time between changes: %.6f s\n', ...
        (t_log(end) - t_log(1)) / (n_changes - 1));
fprintf('  Equivalent switching frequency: %.1f Hz\n', ...
        (n_changes - 1) / (t_log(end) - t_log(1)));

fprintf('\n========== PROCESSING COMPLETE ==========\n\n');

end
