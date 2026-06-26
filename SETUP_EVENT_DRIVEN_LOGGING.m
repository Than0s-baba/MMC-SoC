%% SETUP GUIDE: Event-Driven Gate Signal Logging
%  Configure Simulink for direct gate signal capture
%
% =========================================================================
% PART 1: SIMULINK CONFIGURATION
% =========================================================================

% Step 1: Make Amplitude and Frequency Tunable
% ============================================
% (If not already done)
%
% Option A: Using Model Initialization Function
%   1. Simulink → Model Settings → Model Properties
%   2. Go to Callbacks tab → InitFcn
%   3. Add:
%
%       refAmp = 20;    % Default peak voltage (V)
%       refFreq = 50;   % Default frequency (Hz)
%
%   4. Click OK, Save model
%
% Option B: Using Model Workspace
%   1. In Simulink Editor: View → Model Data Editor
%   2. Click "Add" → Variable
%   3. Create refAmp and refFreq with default values

% Step 2: Create Signal Source Using refAmp and refFreq
% =====================================================
% In your Sine Wave Generator block:
%   - Amplitude: refAmp
%   - Frequency: refFreq
%   - (Don't use fixed numbers, use variable names)

% Step 3: Enable Signal Logging for MOSFET Gates
% ==============================================
% For EACH of the 16 gate signals, enable logging:
%
%   Signal Names: s1g1, s1g2, s1g3, s1g4
%                 s2g1, s2g2, s2g3, s2g4
%                 s3g1, s3g2, s3g3, s3g4
%                 s4g1, s4g2, s4g3, s4g4
%
% How to Enable:
%   (a) Right-click on signal line in Simulink
%   (b) Select "Log Signal"
%   (c) Signal will appear in logsout after simulation
%
% Alternative (via MATLAB):
%   set_param(signal_path, 'DataLoggingNameMode', 'SignalName');

% Step 4: Log Output Voltage
% ==========================
% Also log the output voltage signal. Name it one of:
%   - V_actual
%   - V_output
%   - V_ref (if using reference as ground truth)
% 
% This signal is used to detect when transitions occur.

% Step 5: Verify Signal Logging is Enabled
% ========================================
% In Simulink: Simulation → Model Configuration Parameters
%   → Data Import/Export tab
%   → Check "Save as Single Object"  ✓
%   → Variable name: "logsout"
%   (Default is usually correct)

% =========================================================================
% PART 2: RUNNING THE EVENT LOGGER
% =========================================================================

% Once your model is configured, there are 2 options:

% OPTION A: Single Simulation
% ==========================
% Run one simulation manually, then process:
%
%   >> % In Simulink, run simulation
%   >> sim('CHB_Model', 'StopTime', '0.2');
%   >> CHB_Process_Event_Driven_Logs
%
% Output: gate_transitions_YYYY-MM-DD_HH-mm-ss.csv

% OPTION B: Batch Simulations (RECOMMENDED)
% ==========================================
% Automatically run 16 simulations with different amp/freq combinations:
%
%   >> CHB_Batch_Event_Logger
%
% Creates:
%   gate_logs/gate_logs_index.csv (master summary)
%   gate_logs/gate_logs_refAmp=X_refFreq=Y.csv (per simulation)

% =========================================================================
% PART 3: UNDERSTANDING THE OUTPUT CSV
% =========================================================================

% Example CSV structure (from gate_logs_refAmp=10_refFreq=50.csv):
%
% Timestamp_s,refAmp_V,refFreq_Hz,V_output_V,s1g1,s1g2,s1g3,s1g4,s2g1,...
% 0.000000,10,50,0.0,0,0,0,0,0,...
% 0.000115,10,50,5.0,1,0,1,0,0,...
% 0.000230,10,50,10.0,1,0,1,0,1,...
% 0.000345,10,50,5.0,0,1,0,1,1,...
% ...
%
% Columns:
%   - Timestamp_s: Time of voltage transition (seconds)
%   - refAmp_V: Reference amplitude (constant per simulation)
%   - refFreq_Hz: Reference frequency (constant per simulation)
%   - V_output_V: Actual quantized output voltage at transition
%   - s1g1 to s4g4: Gate signals (1=ON, 0=OFF)
%
% Key insight: Each row represents a moment when the output voltage changes
% This captures the switching pattern and gate sequences.

% =========================================================================
% PART 4: ANALYZING THE GATE LOGS
% =========================================================================

% After running CHB_Batch_Event_Logger, you have CSV files.
% Use this script to visualize switching patterns:

clear; clc;

% Load a gate transitions CSV
csv_file = 'gate_logs/gate_logs_refAmp=10_refFreq=50.csv';

if isfile(csv_file)
    fprintf('Loading: %s\n', csv_file);
    T = readtable(csv_file);
    
    % Display first few rows
    fprintf('\nFirst 10 transitions:\n');
    disp(T(1:min(10, height(T)), :));
    
    % Statistics
    fprintf('\nTransition Statistics:\n');
    fprintf('  Total transitions: %d\n', height(T));
    fprintf('  Time span: %.4f s\n', T.Timestamp_s(end) - T.Timestamp_s(1));
    fprintf('  Transition rate: %.1f Hz\n', ...
            (height(T)-1) / (T.Timestamp_s(end) - T.Timestamp_s(1)));
    
    % Gate usage
    fprintf('\nGate ON Statistics:\n');
    gate_cols = T(:, 5:end);  % Columns 5+ are gates
    for i = 1:width(gate_cols)
        col_name = gate_cols.Properties.VariableNames{i};
        on_count = sum(table2array(gate_cols(:, i)) > 0.5);
        on_pct = 100 * on_count / height(T);
        fprintf('  %s: ON %.1f%% (%d/%d)\n', ...
                col_name, on_pct, on_count, height(T));
    end
    
else
    fprintf('File not found: %s\n', csv_file);
    fprintf('Run CHB_Batch_Event_Logger first to generate logs.\n');
end

% =========================================================================
% PART 5: COMBINING MULTIPLE CSV FILES
% =========================================================================

% If you want to merge all gate_logs into one large dataset:
%
% MATLAB CODE:
%
%   gate_dir = 'gate_logs';
%   csv_files = dir(fullfile(gate_dir, 'gate_logs_refAmp=*.csv'));
%   
%   all_data = [];
%   for i = 1:length(csv_files)
%       T = readtable(fullfile(gate_dir, csv_files(i).name));
%       all_data = [all_data; T];
%   end
%   
%   writetable(all_data, 'gate_logs_combined.csv');
%
% This creates a single CSV with all transitions from all simulations.
% Useful for training ML models on switching patterns.

% =========================================================================
% PART 6: TROUBLESHOOTING
% =========================================================================

% Problem: "logsout not found"
% Solution: Make sure signal logging is enabled in Simulink
%   1. Right-click signals → Log Signal
%   2. Run simulation before running processor script
%   3. Don't clear workspace between sim and script

% Problem: "No voltage signal found"
% Solution: Check voltage signal naming
%   Current script looks for: V_actual, V_output, V_ref
%   If your signal is named differently, edit the script:
%   - Find line: for name = {'V_actual', 'V_output', 'V_ref'}
%   - Add your signal name: for name = {'V_actual', 'V_output', 'V_ref', 'your_name'}

% Problem: "CSV is mostly zeros"
% Solution: Gates might be using different value representation
%   Check if gates are: 1/0, True/False, 5V/0V, or PWM signals
%   Script currently checks: gate_signal > 0.5
%   Adjust threshold if needed

% Problem: "No transitions detected"
% Solution: Increase simulation time or lower change_threshold
%   Current threshold: 0.1V
%   Edit line: change_threshold = 0.05;  % Lower threshold

% =========================================================================
% QUICK START
% =========================================================================

% 1. Configure Simulink:
%    - Set refAmp, refFreq as tunable parameters
%    - Enable signal logging for all s1g1-s4g4
%    - Log the output voltage signal
%
% 2. Run batch logger:
%    >> CHB_Batch_Event_Logger
%
% 3. Examine outputs:
%    - gate_logs/gate_logs_index.csv (check all runs completed)
%    - gate_logs/gate_logs_refAmp=10_refFreq=50.csv (sample data)
%
% 4. Combine and analyze:
%    - Use Python/Excel/MATLAB to process CSVs
%    - Train ML models on gate switching patterns
%    - Analyze efficiency/switching losses

fprintf('\n========== EVENT-DRIVEN LOGGING SETUP COMPLETE ==========\n');
fprintf('See comments above for detailed instructions.\n\n');

