%% ========================================================================
%  MMC SYSTEM PARAMETERS SCRIPT
%  ========================================================================
%% 1. System & Grid Specifications
V_dc     = 750;      % Nominal DC-link voltage [V] (750V)
P_rated  = 1e3;       % Rated active power [W] (1 kW)
f_grid   = 50;         % Grid AC frequency [Hz]
omega    = 2 * pi * f_grid;

%% 2. MMC Topology & Module Setup
N     = 8;                % Number of submodules per arm
Vc_nom    = V_dc /N;  % Rated Submodule capacitor voltage target [V]

%% 3. Arm Components (Calculated & Defined)
% Arm Resistance (parasitic/filter resistance)
R_arm    = 1208e-3;       % Arm resistance [1.208 Ohms]

% Arm Inductance (Sized based on current ripple / short circuit protection)
% Typical rule of thumb limits circulation current ripple:
L_arm    = 40e-3;     % Arm inductance [H] (40 mH)
L_arm_pow_rat = 14.4; % Power rating of inductor in W
L_arm_res = 0.4;      %(.4 Ohms)
L_arm_satcurrent = 7; %(7A)
L_tolr = 15;          %(15%)


% Submodule Capacitance
% Sized based on allowable cell voltage ripple (usually around 10%)
C_sm     = 220e-6;       % Submodule capacitance [F] (220 uF)
C_series_res = 45e-2;    % ( 0.45 ohms)

%% 4. Control System Parameters 
lambda_i    = 1;
lambda_sw   = 0.1;
lambda_cap  = 0.1;
lambda_circ = 0.3;
Vc_init = Vc_nom;


%% 5. Simulation Control Settings
T_sample = 50e-6;      % Sample time for discrete controllers [s] (50 us)

%% 6. Current Limits 
m        = 1;        % Modulation index
cosphi   = 1;        % Power factor

disp('>>> MMC parameters loaded successfully into Base Workspace! <<<');