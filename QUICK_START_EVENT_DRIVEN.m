% QUICK START: Event-Driven Gate Signal Logging
% ============================================================
%
% TL;DR: Capture MOSFET gate signals at voltage transitions.
%
% 3 simple steps:
% 1. Configure Simulink model (5 min)
% 2. Run batch logger (10 min)
% 3. Analyze results in Python (2 min)

%% STEP 1: SIMULINK SETUP (Do this once)

% A. Add tunable parameters to CHB_Model.slx
%    Simulink → Model Properties → InitFcn callback
%    Paste this code:

refAmp = 20;      % Peak voltage (V)
refFreq = 50;     % Frequency (Hz)

% B. Set Sine Wave Generator to use variables:
%    Amplitude: refAmp (NOT a number)
%    Frequency: refFreq (NOT a number)

% C. Enable signal logging for all gates:
%    Right-click signal line → Log Signal
%    Do this for: s1g1, s1g2, s1g3, s1g4,
%                 s2g1, s2g2, s2g3, s2g4,
%                 s3g1, s3g2, s3g3, s3g4,
%                 s4g1, s4g2, s4g3, s4g4

% D. Enable signal logging for output voltage:
%    Right-click V_actual (or V_output) → Log Signal

% E. Save your model

%% STEP 2: RUN BATCH LOGGER (Automatically simulates 16 times)

clear; clc;
CHB_Batch_Event_Logger

% This will:
% - Run 4 amplitudes (5, 10, 15, 20 V) × 4 frequencies (30, 50, 70, 90 Hz)
% - Create gate_logs/ folder
% - Generate 16 CSV files (one per simulation)
% - Take ~10 minutes total

% Output files:
% gate_logs/gate_logs_index.csv                  (master summary)
% gate_logs/gate_logs_refAmp=10_refFreq=50.csv   (example data)
% ... (15 more files)

%% STEP 3: ANALYZE IN PYTHON

% Run this in command line:
% python CHB_Analyze_Gate_Logs.py

% This will:
% - Load all 16 CSV files
% - Detect SM states (which submodule outputs what)
% - Create visualizations
% - Export statistics

% Output files:
% gate_logs_analysis.png                 (6 plots)
% gate_logs_combined_with_states.csv     (all data merged + SM states)
% gate_usage_statistics.csv              (gate statistics)

%% UNDERSTANDING YOUR DATA

% CSV Example:
% Timestamp_s,refAmp_V,refFreq_Hz,V_output_V,s1g1,s1g2,s1g3,s1g4,...
% 0.000000,10,50,0.0,0,1,0,1,...
% 0.000115,10,50,5.0,1,0,1,0,...
% 0.000230,10,50,10.0,1,0,1,0,...
%
% Each row = ONE MOMENT when output voltage changed
% Columns = time, parameters, output voltage, all 16 gate signals

%% CUSTOMIZE PARAMETER RANGES

% Want to test different amplitudes/frequencies?
% Edit CHB_Batch_Event_Logger.m, line ~30:

% For more data points:
% amplitudes = 5:2:20;     % Every 2V (8 values instead of 4)
% frequencies = 20:10:100; % Every 10Hz (9 values instead of 4)

% For quick test:
% amplitudes = 10:10:20;   % Only 2 values
% frequencies = 50;         % Only 1 value
% total_runs = length(amplitudes) * length(frequencies);  % 2 runs total

%% COMMON ISSUES

% Issue: "logsout not found"
% Fix: Right-click signals → Log Signal BEFORE running sim()

% Issue: "No voltage signal found"
% Fix: Make sure your voltage signal is logged and named:
%      V_actual, V_output, or V_ref

% Issue: "CSV is mostly zeros"
% Fix: Gates might use different values (5V instead of 1, or True/False)
%      Check this line in processor:
%      gate_signal.Values.Data > 0.5  ← Try > 2.5 if gates are 5V

% Issue: "No transitions detected"
% Fix: Increase simulation time or lower threshold:
%      t_sim = 0.5;              % More time
%      change_threshold = 0.05;  % More sensitive

%% WHAT TO DO WITH THE DATA

% Option 1: Analyze gate switching patterns
% → Use Python visualization, learn about SM sequencing

% Option 2: Train ML models
% → Load CSV, train classifier to predict gate states
% → See CHB_Analyze_Gate_Logs.py for examples

% Option 3: Combine with hardware data
% → Log gates in actual hardware
% → Compare simulation vs real behavior

% Option 4: Look for anomalies
% → Find unusual switching sequences
% → Detect faults or inefficiencies

%% FILES YOU'LL USE

% MATLAB:
% - CHB_Batch_Event_Logger.m          (RUN THIS FIRST)
% - CHB_Process_Event_Driven_Logs.m   (For single simulations)
% - SETUP_EVENT_DRIVEN_LOGGING.m      (Detailed help)

% Python:
% - CHB_Analyze_Gate_Logs.py          (RUN AFTER batch logger)

% Output CSVs:
% - gate_logs/gate_logs_index.csv
% - gate_logs/gate_logs_refAmp=*.csv
% - gate_logs_combined_with_states.csv
% - gate_usage_statistics.csv

%% EXAMPLE WORKFLOW

% Time: 30 minutes total

% 00:00 - Configure Simulink model (5 min)
%         - Add parameters to InitFcn
%         - Enable signal logging
%         - Save

% 05:00 - Run batch logger (10 min)
%         >> CHB_Batch_Event_Logger
%         - Generates 16 CSV files

% 15:00 - Analyze in Python (2 min)
%         >> python CHB_Analyze_Gate_Logs.py
%         - Creates plots and statistics

% 17:00 - Done!
%         - View gate_logs_analysis.png
%         - Check gate_logs_combined_with_states.csv
%         - Train models if desired

%% NEXT STEPS

% 1. ✓ Setup Simulink (this guide)
% 2. ✓ Run batch logger (CHB_Batch_Event_Logger)
% 3. ✓ Analyze results (python CHB_Analyze_Gate_Logs.py)
% 4. Combine multiple runs (merge CSVs)
% 5. Train ML models (optional)
% 6. Compare with hardware data (if available)

fprintf('\n');
fprintf('========== EVENT-DRIVEN LOGGING QUICK START ==========\n');
fprintf('\n');
fprintf('Step 1: Configure your Simulink model (see above)\n');
fprintf('Step 2: Run this command:\n');
fprintf('        >> CHB_Batch_Event_Logger\n');
fprintf('Step 3: Run Python analysis:\n');
fprintf('        >> python CHB_Analyze_Gate_Logs.py\n');
fprintf('\n');
fprintf('Done! Check gate_logs/ folder for your data.\n');
fprintf('\n');
fprintf('=====================================================\n');
fprintf('\n');

