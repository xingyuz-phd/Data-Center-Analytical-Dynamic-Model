%% ========================================================================
%  EMT vs. RMS Per-Unit Benchmark: 6 Hz Small-Signal Amplification Test
%  - Operating condition: Normal mode, f_bw,vsi = 25 Hz (zeta_vsi = 1.0)
%  - Thevenin grid (on S_b = 45 MVA): V_s = 1.0, R_g = 0.035, X_g = 0.35 p.u.
%  - Input: p_chip,3ph = 0.70 + 0.02*sin(2*pi*6*(t - 5.0)) p.u. for t >= 5 s
%  - Reads: Normal_Oscillation_EMT_PerUnit_Data.xlsx (Sheet: 'EMT_PerUnit_Data')
%  - Exports vector PDF (single panel, 4.5-7.5 s shifted to 0-3.0 s):
%      Fig8_Normal_Oscillation_6Hz.pdf
% =========================================================================
clear; clc; close all;

%% 1. Load Unified Per-Unit EMT Dataset
emt_file = 'Normal_Oscillation_EMT_PerUnit_Data.xlsx';
T_emt = readtable(emt_file, 'Sheet', 'EMT_PerUnit_Data');
t_emt = T_emt.Time_s;
dt    = t_emt(2) - t_emt(1);   % 0.0005 s (0.5 ms)

%% 2. System Configuration, Per-Unit Conversion & PI Controller Tuning
cfg.M_ups      = 30;      % Parallel UPS aggregation multiplier
cfg.M_psu      = 10;      % Parallel PSU aggregation multiplier per UPS
cfg.S_ups_MVA  = 1.50;    % Single UPS rated power (MVA)
cfg.S_psu_MVA  = 0.05;    % Single PSU module local power base (MVA)
cfg.f_b        = 60.0;    % Nominal frequency (Hz)

cfg.c_dc_afe_pu  = 10.0;
cfg.r_afe_pu     = 0.003;
cfg.c_vsi_pu     = 1.0;
cfg.r_vsi_pu     = 0.003;
cfg.c_dc_pfc_pu  = 10.0;
cfg.r_pfc_pu     = 0.003;
cfg.c_dc_buck_pu = 2.5;

% Thevenin equivalent grid on unified base S_b = 45 MVA
cfg.V_s = 1.00;
cfg.R_g = 0.035;
cfg.X_g = 0.35;

bw.fbw_afe  = 20.0;  bw.zt_afe  = 0.707;
bw.fbw_vsi  = 25.0;  bw.zt_vsi  = 1.0;   % Reduced VSI bandwidth (25 Hz)
bw.fbw_pfc  = 10.0;  bw.zt_pfc  = 1.0;
bw.fbw_buck = 20.0;  bw.zt_buck = 1.0;

p    = build_per_unit_params(cfg);
ctrl = tune_pi_controllers(p, bw);

%% 3. Piecewise Integration of Grid-Coupled Normal-Mode RMS DAE (0 to 10 s)
segments = [
    0.0,  2.0;
    2.0,  3.5;
    3.5,  5.0;
    5.0,  10.0;
];

x_curr = compute_steady_state_ic(p, ctrl, 0.10);
opts   = odeset('RelTol', 1e-8, 'AbsTol', 1e-10);
N_tot  = numel(t_emt);
Pg_rms = zeros(N_tot, 1);

cursor = 1;
for k = 1:size(segments, 1)
    ta = segments(k, 1);
    tb = segments(k, 2);
    n_seg  = round((tb - ta) / dt) + 1;
    t_span = linspace(ta, tb, n_seg)';

    [~, X_seg] = ode15s(@(t, x) rms_ode_wrapper(t, x, p, ctrl), t_span, x_curr, opts);
    x_curr = X_seg(end, :)';

    start_idx = 1;
    if k > 1
        start_idx = 2;
    end
    for j = start_idx:n_seg
        [~, pg] = rms_normal_grid_dae(t_span(j), X_seg(j, :)', p, ctrl);
        Pg_rms(cursor) = pg;
        cursor = cursor + 1;
    end
end

%% 4. Single-Panel IEEE Figure (4.5 - 7.5 s shifted to 0 - 3.0 s)
m  = (t_emt >= 4.5) & (t_emt <= 7.5);
tp = t_emt(m) - 4.5;

cols.pchip = [0.06, 0.42, 0.24];   % Dark ink green for p_chip,3ph
cols.emt   = [0.52, 0.52, 0.52];   % Muted gray dashed for EMT p_g
cols.rms   = [0.00, 0.00, 0.00];   % Solid black for RMS p_g

set(0, 'DefaultAxesFontName', 'Times New Roman');
set(0, 'DefaultTextFontName', 'Times New Roman');
set(0, 'DefaultAxesFontSize', 8.5);
set(0, 'DefaultTextFontSize', 9);
set(0, 'DefaultAxesLineWidth', 0.6);

fig = figure('Units', 'inches', 'Position', [1.2, 2.0, 5.2, 1.35], 'Color', 'w');
ax  = axes(fig); hold(ax, 'on');

h_emt   = plot(ax, tp, T_emt.Pg_pu(m),        '--', 'Color', cols.emt,   'LineWidth', 1.15);
h_rms   = plot(ax, tp, Pg_rms(m),             '-',  'Color', cols.rms,   'LineWidth', 1.00);
h_pchip = plot(ax, tp, T_emt.Pchip_3ph_pu(m), '-',  'Color', cols.pchip, 'LineWidth', 1.15);

xlim(ax, [0.0, 3.0]);
ylim(ax, [0.56, 0.89]);
xlabel(ax, 'Time (s)');
ylabel(ax, 'Active Power (p.u.)');
box(ax, 'on'); grid(ax, 'on');
ax.GridAlpha = 0.25;
ax.GridLineStyle = ':';
ax.TickDir = 'in';

lgd = legend(ax, [h_pchip, h_emt, h_rms], ...
    {'$\mathrm{p}_{\mathrm{chip},3\phi}$', '$\mathrm{p}_g$ (EMT)', '$\mathrm{p}_g$ (RMS)'}, ...
    'Interpreter', 'latex', 'Orientation', 'horizontal', 'Location', 'northwest', ...
    'Box', 'off', 'FontSize', 8.0);
lgd.ItemTokenSize = [14, 6];

exportgraphics(fig, 'Fig8_Normal_Oscillation_6Hz.pdf', 'ContentType', 'vector');

% Print steady-state 6 Hz amplification summary (6.0 - 7.5 s)
m_osc   = (t_emt >= 6.0) & (t_emt <= 7.5);
amp_emt = 0.5 * (max(T_emt.Pg_pu(m_osc)) - min(T_emt.Pg_pu(m_osc)));
amp_rms = 0.5 * (max(Pg_rms(m_osc))      - min(Pg_rms(m_osc)));
fprintf('6 Hz Amplification (6.0-7.5 s): EMT = %.2fx (%.4f pu), RMS = %.2fx (%.4f pu)\n', ...
    amp_emt / 0.02, amp_emt, amp_rms / 0.02, amp_rms);
disp('Exported Fig8_Normal_Oscillation_6Hz.pdf.');

%% ========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function p = build_per_unit_params(cfg)
    p.S_b    = cfg.M_ups * cfg.S_ups_MVA;
    p.f_b    = cfg.f_b;
    p.w_b    = 2.0 * pi * cfg.f_b;
    p.alpha  = (cfg.M_psu * cfg.S_psu_MVA) / cfg.S_ups_MVA;
    p.C_ups  = cfg.c_dc_afe_pu;
    p.R_cv   = cfg.r_afe_pu;
    p.C_iv   = cfg.c_vsi_pu;
    p.R_iv   = cfg.r_vsi_pu;
    p.C_pfc  = p.alpha * cfg.c_dc_pfc_pu;
    p.R_pfc  = cfg.r_pfc_pu / p.alpha;
    p.C_buck = p.alpha * cfg.c_dc_buck_pu;
    p.V_s    = cfg.V_s;
    p.R_g    = cfg.R_g;
    p.X_g    = cfg.X_g;
    p.c_dc_afe_local  = cfg.c_dc_afe_pu;
    p.c_vsi_local     = cfg.c_vsi_pu;
    p.c_dc_pfc_local  = cfg.c_dc_pfc_pu;
    p.c_dc_buck_local = cfg.c_dc_buck_pu;
end

function ctrl = tune_pi_controllers(p, bw)
    wb = p.w_b;
    wn_afe = 2.0 * pi * bw.fbw_afe;
    ctrl.kp_v_afe = 2.0 * bw.zt_afe * wn_afe * p.c_dc_afe_local / wb;
    ctrl.ki_v_afe = (wn_afe^2) * p.c_dc_afe_local / wb;

    wn_vsi = 2.0 * pi * bw.fbw_vsi;
    ctrl.kp_v_vsi = 2.0 * bw.zt_vsi * wn_vsi * p.c_vsi_local / wb;
    ctrl.ki_v_vsi = (wn_vsi^2) * p.c_vsi_local / wb;

    wn_pfc = 2.0 * pi * bw.fbw_pfc;
    ctrl.kp_v_pfc = p.alpha * (2.0 * bw.zt_pfc * wn_pfc * p.c_dc_pfc_local / wb);
    ctrl.ki_v_pfc = p.alpha * ((wn_pfc^2) * p.c_dc_pfc_local / wb);

    wn_buck = 2.0 * pi * bw.fbw_buck;
    ctrl.kp_v_buck = p.alpha * (2.0 * bw.zt_buck * wn_buck * p.c_dc_buck_local / wb);
    ctrl.ki_v_buck = p.alpha * ((wn_buck^2) * p.c_dc_buck_local / wb);
end

function V_g = solve_grid_Vg(i_cv_d, p)
% SOLVE_GRID_VG Exact algebraic POI voltage for unity-PF Thevenin grid:
%   (V_g + R_g*i_cv_d)^2 + (X_g*i_cv_d)^2 = V_s^2
    rad = max(p.V_s^2 - (p.X_g * i_cv_d)^2, 1e-6);
    V_g = sqrt(rad) - p.R_g * i_cv_d;
end

function [dx, p_g] = rms_normal_grid_dae(t, x, p, ctrl)
    E_afe  = x(1); E_vsi  = x(2); E_pfc  = x(3); E_buck  = x(4);
    xi_afe = x(5); xi_vsi = x(6); xi_pfc = x(7); xi_buck = x(8);

    v_dc   = sqrt(max(2.0 * E_afe  / p.C_ups,  1e-8));
    v_iv_d = sqrt(max(2.0 * E_vsi  / p.C_iv,   1e-8));
    v_pfc  = sqrt(max(2.0 * E_pfc  / p.C_pfc,  1e-8));
    v_buck = sqrt(max(2.0 * E_buck / p.C_buck, 1e-8));

    i_cv_d = ctrl.kp_v_afe  * (1.0 - v_dc)   + ctrl.ki_v_afe  * xi_afe;
    V_g    = solve_grid_Vg(i_cv_d, p);
    i_iv_d = ctrl.kp_v_vsi  * (1.0 - v_iv_d) + ctrl.ki_v_vsi  * xi_vsi;
    i_iv_q = p.C_iv * v_iv_d;
    G_eq   = ctrl.kp_v_pfc  * (1.0 - v_pfc)  + ctrl.ki_v_pfc  * xi_pfc;
    i_L    = ctrl.kp_v_buck * (1.0 - v_buck) + ctrl.ki_v_buck * xi_buck;

    p_chip    = p.alpha * load_sine_profile(t);
    p_load    = (v_buck^2) * p_chip;
    p_buck_in = v_buck * i_L;
    p_psu     = (v_iv_d^2) * G_eq;
    p_eq      = (p_psu / 3.0) * (1.0 - p.R_pfc * G_eq);
    p_iv_ac   = v_iv_d * i_iv_d;
    p_iv_dc   = p_iv_ac + p.R_iv * (i_iv_d^2 + i_iv_q^2);
    p_afe     = V_g * i_cv_d - p.R_cv * (i_cv_d^2);
    p_g       = V_g * i_cv_d;

    dx = [
        p.w_b * (p_afe - p_iv_dc);
        p.w_b * (p_iv_ac - p_psu);
        p.w_b * (p_eq - p_buck_in);
        p.w_b * (p_buck_in - p_load);
        1.0 - v_dc;
        1.0 - v_iv_d;
        1.0 - v_pfc;
        1.0 - v_buck
    ];
end

function dx = rms_ode_wrapper(t, x, p, ctrl)
    [dx, ~] = rms_normal_grid_dae(t, x, p, ctrl);
end

function x0 = compute_steady_state_ic(p, ctrl, p_load_pu)
    p_chip0  = p.alpha * p_load_pu;
    xi_buck0 = p_chip0 / ctrl.ki_v_buck;
    G_eq0    = (1.0 - sqrt(1.0 - 12.0 * p.R_pfc * p_chip0)) / (2.0 * p.R_pfc);
    xi_pfc0  = G_eq0 / ctrl.ki_v_pfc;
    i_iv_d0  = G_eq0;
    xi_vsi0  = i_iv_d0 / ctrl.ki_v_vsi;
    p_iv_dc0 = i_iv_d0 + p.R_iv * (i_iv_d0^2 + p.C_iv^2);
    opts_fs  = optimoptions('fsolve', 'Display', 'off', 'TolFun', 1e-12);
    i_cv_d0  = fsolve(@(ic) solve_grid_Vg(ic, p)*ic - p.R_cv*ic^2 - p_iv_dc0, p_iv_dc0, opts_fs);
    xi_afe0  = i_cv_d0 / ctrl.ki_v_afe;

    x0 = [
        0.5 * p.C_ups;
        0.5 * p.C_iv;
        0.5 * p.C_pfc;
        0.5 * p.C_buck;
        xi_afe0;
        xi_vsi0;
        xi_pfc0;
        xi_buck0
    ];
end

function p_pu = load_sine_profile(t)
    if t <= 2.0
        base = 0.10;
    elseif t < 3.5
        base = 0.10 + 0.60 * (t - 2.0) / 1.5;
    else
        base = 0.70;
    end
    if t > 5.0
        p_pu = base + 0.02 * sin(2.0 * pi * 6.0 * (t - 5.0));
    else
        p_pu = base;
    end
end