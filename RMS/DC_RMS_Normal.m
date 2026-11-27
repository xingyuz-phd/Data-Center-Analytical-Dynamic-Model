%% ========================================================================
%  EMT vs. RMS Per-Unit Benchmark for Data Center Computing Loads
%  - Modular functions:
%      1. build_per_unit_params()  : Unified per-unit base & plant conversion
%      2. tune_pi_controllers()    : Bandwidth-based PI controller tuning
%      3. rms_datacenter_dae()     : 9-state per-unit RMS DAE formulation
%      4. add_psu_inset()          : Zoomed inset showing 3-phase envelope around RMS
%      5. vrt_envelope_profile()   : VRT ride-through voltage envelope
%      6. estimate_pfc_ripple()    : Second-harmonic PFC ripple consistency check
%  - Reads: Normal_EMT_PerUnit_Data.xlsx (Sheet: 'EMT_PerUnit_Data')
%  - Exports vector PDF figures (4 stacked panels each):
%      Fig1_VRT_1_to_5s.pdf       (1-5 s): Load ramp-up, VRT, and soft recovery
%      Fig2_LoadProp_5_to_10s.pdf (5-10 s): Downstream-to-upstream load propagation
% =========================================================================
clear; clc; close all;

%% 1. Load Unified Per-Unit EMT Dataset
emt_file = 'Normal_EMT_PerUnit_Data.xlsx';
T_emt = readtable(emt_file, 'Sheet', 'EMT_PerUnit_Data');
t_emt = T_emt.Time_s;
dt    = t_emt(2) - t_emt(1);   % 0.0005 s (0.5 ms)

%% 2. System Configuration, Per-Unit Conversion & PI Controller Tuning
cfg.M_ups      = 30;      % Parallel UPS aggregation multiplier
cfg.M_psu      = 10;      % Parallel PSU aggregation multiplier per UPS
cfg.S_ups_MVA  = 1.50;    % Single UPS rated power (MVA)
cfg.S_psu_MVA  = 0.05;    % Single PSU module local power base (MVA)
cfg.V_LL_kV    = 0.48;    % AC line-to-line RMS voltage base (kV)
cfg.V_dc_kV    = 0.80;    % UPS DC-link voltage base (kV)
cfg.V_bat_kV   = 0.40;    % Battery-side DC voltage base (kV)
cfg.V_pfc_kV   = 0.80;    % PSU PFC DC-link voltage base (kV)
cfg.V_buck_kV  = 0.048;   % Downstream Buck load voltage base (kV)
cfg.f_b        = 60.0;    % Nominal frequency (Hz)

% Local per-unit plant parameters from PSCAD panels
cfg.c_dc_afe_pu  = 10.0;
cfg.r_afe_pu     = 0.003;
cfg.c_vsi_pu     = 1.0;
cfg.r_vsi_pu     = 0.003;
cfg.c_dc_pfc_pu  = 10.0;
cfg.r_pfc_pu     = 0.003;
cfg.c_dc_buck_pu = 2.5;
cfg.v_bat_pu     = 1.0;
cfg.p_bat_ref_pu = 0.0;
cfg.ramp_rec_pu  = 0.5;   % Battery soft-recovery ramp rate (pu/s)

% Bandwidth & damping ratio specifications (Hz, -)
bw.fbw_afe  = 20.0;  bw.zt_afe  = 0.707;
bw.fbw_bat  = 20.0;  bw.zt_bat  = 1.0;
bw.fbw_vsi  = 100.0; bw.zt_vsi  = 1.0;
bw.fbw_pfc  = 10.0;  bw.zt_pfc  = 1.0;
bw.fbw_buck = 20.0;  bw.zt_buck = 1.0;

% Convert to unified RMS common per-unit base & tune PI controllers
p    = build_per_unit_params(cfg);
ctrl = tune_pi_controllers(p, bw);

%% 3. Piecewise Integration of the RMS DAE Model (0 to 10 s)
t_trip  = 2.2595;   % VRT trip to battery backup mode (s)
t_recon = 3.5100;   % VRT reconnection to online mode (s)

% Event segments: {t_start, t_end, mode_name}
segments = {
    0.0,    1.0,    'online';
    1.0,    1.5,    'online';
    1.5,    2.0,    'online';
    2.0,    2.055,  'online';
    2.055,  t_trip, 'online';
    t_trip, 2.5,    'backup';
    2.5,    t_recon,'backup';
    t_recon,3.6,    'soft_rec';
    3.6,    6.0,    'soft_rec';
    6.0,    6.3,    'online';
    6.3,    7.7,    'online';
    7.7,    8.3,    'online';
    8.3,    9.7,    'online';
    9.7,    10.0,   'online';
};

% Steady-state initialization at t = 0 (Pload_pu = 0.10)
x_curr = compute_steady_state_ic(p, ctrl, 0.10);

opts = odeset('RelTol', 1e-8, 'AbsTol', 1e-10);
N_tot = numel(t_emt);

t_rms      = zeros(N_tot, 1);
Vg_rms     = zeros(N_tot, 1);
Pg_raw     = zeros(N_tot, 1);
Id_rms     = zeros(N_tot, 1);
Vdc_rms    = zeros(N_tot, 1);
Vpfc_rms   = zeros(N_tot, 1);
Peq_rms    = zeros(N_tot, 1);
Xi_pfc_rms = zeros(N_tot, 1);

cursor = 1;
i_bat_at_recon = 0.0;

for k = 1:size(segments, 1)
    ta   = segments{k, 1};
    tb   = segments{k, 2};
    mode = segments{k, 3};

    % Mode-transition integral resets (Section II-D)
    if k > 1
        prev_mode = segments{k-1, 3};
        if strcmp(prev_mode, 'online') && strcmp(mode, 'backup')
            x_curr(5) = 0.0;  % Reset xi_afe
        elseif strcmp(prev_mode, 'backup') && strcmp(mode, 'soft_rec')
            v_dc_now = sqrt(max(2.0 * x_curr(1) / p.C_ups, 1e-8));
            i_bat_at_recon = -(ctrl.kp_v_bat * (1.0 - v_dc_now) + ctrl.ki_v_bat * x_curr(6));
            x_curr(6) = 0.0;  % Reset xi_bat
            x_curr(5) = 0.0;  % Start xi_afe from 0
        end
    end

    mode_info.mode    = mode;
    mode_info.ta      = ta;
    mode_info.tb      = tb;
    mode_info.t_recon = t_recon;
    mode_info.i_bat0  = i_bat_at_recon;

    n_seg  = round((tb - ta) / dt) + 1;
    t_span = linspace(ta, tb, n_seg)';

    [~, X_seg] = ode15s(@(t, x) rms_ode_wrapper(t, x, p, ctrl, mode_info), t_span, x_curr, opts);
    x_curr = X_seg(end, :)';

    start_idx = 1;
    if k > 1
        start_idx = 2; % Avoid duplicating shared boundary point
    end

    for j = start_idx:n_seg
        [~, alg] = rms_datacenter_dae(t_span(j), X_seg(j, :)', p, ctrl, mode_info);
        t_rms(cursor)      = t_span(j);
        Vg_rms(cursor)     = alg.V_g;
        Pg_raw(cursor)     = alg.p_g;
        Id_rms(cursor)     = alg.i_cv_d;
        Vdc_rms(cursor)    = alg.v_dc;
        Vpfc_rms(cursor)   = alg.v_pfc;
        Peq_rms(cursor)    = alg.p_eq;
        Xi_pfc_rms(cursor) = alg.xi_pfc;
        cursor = cursor + 1;
    end
end

% Apply 20 ms power-meter smoothing filter to RMS grid active power
Pg_rms = first_order_lpf(Pg_raw, dt, 0.020);

%% 3b. Period-Averaging Ripple Consistency Check (PFC 2*omega Ripple)
ripple = estimate_pfc_ripple(t_rms, Peq_rms, Vpfc_rms, Xi_pfc_rms, p, T_emt.Vpsu_a_pu);

%% 4. IEEE Aesthetic Styling Palette & Wider Figure Dimensions
cols.rms      = [0.00, 0.00, 0.00];         % Solid black for RMS
cols.emt      = [0.55, 0.55, 0.55];         % Muted gray dashed for EMT
cols.env      = [0.75, 0.15, 0.75];         % Purple dashed for +/- dv_pfc envelope
cols.vrt_fill = [0.82, 0.90, 0.96];         % Soft ice-blue fill for VRT envelope
cols.vrt_edge = [0.45, 0.65, 0.82];         % Muted steel-blue border for VRT envelope
cols.bat_fill = [0.88, 0.88, 0.88];         % Light gray fill for battery backup mode
cols.bat_edge = [0.65, 0.65, 0.65];         % Subtle gray boundary line for battery backup mode
cols.pa       = [0.23, 0.49, 0.77, 0.72];   % Muted steel blue (Phase a)
cols.pb       = [0.85, 0.37, 0.28, 0.72];   % Soft terracotta coral (Phase b)
cols.pc       = [0.20, 0.63, 0.50, 0.72];   % Muted sage teal (Phase c)
cols.load     = [0.15, 0.15, 0.15];         % Dark charcoal for load command

lws.rms = 1.05;
lws.emt = 1.05;
lws.env = 0.85;
lws.psu = 0.70;

fig_w = 5.2;   % Wider layout (inches)
fig_h = 4.6;   % Clean proportions for 4 stacked panels with zoomed inset

set(0, 'DefaultAxesFontName', 'Times New Roman');
set(0, 'DefaultTextFontName', 'Times New Roman');
set(0, 'DefaultAxesFontSize', 8.5);
set(0, 'DefaultTextFontSize', 9);
set(0, 'DefaultAxesLineWidth', 0.6);

%% 5. Figure 1 (1.0 - 5.0 s): Load Ramp-Up & Voltage Ride-Through
m1 = (t_emt >= 1.0) & (t_emt <= 5.0);
t1 = t_emt(m1) - 1.0;
t_bat_a = t_trip  - 1.0;   % Shifted start of battery backup mode (1.2595 s)
t_bat_b = t_recon - 1.0;   % Shifted end of battery backup mode   (2.5100 s)

fig1 = figure('Units', 'inches', 'Position', [0.8, 0.9, fig_w, fig_h], 'Color', 'w');
tl1 = tiledlayout(fig1, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% (a) Grid Voltage V_g with Light-Gray VRT Envelope
ax1 = nexttile(tl1); hold on;
[v_vrt_low, v_vrt_high] = vrt_envelope_profile(t1, Vg_rms(m1));
h_vrt = fill(ax1, [t1; flipud(t1)], [v_vrt_low; flipud(v_vrt_high)], ...
    cols.vrt_fill, 'EdgeColor', cols.vrt_edge, 'LineWidth', 0.55, 'FaceAlpha', 0.50);
xline(ax1, t_bat_a, ':', 'Color', cols.bat_edge, 'LineWidth', 0.75, 'HandleVisibility', 'off');
xline(ax1, t_bat_b, ':', 'Color', cols.bat_edge, 'LineWidth', 0.75, 'HandleVisibility', 'off');
h_emt = plot(t1, T_emt.Vg_pu(m1), '--', 'Color', cols.emt, 'LineWidth', lws.emt);
h_rms = plot(t1, Vg_rms(m1), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$V_g$ (p.u.)', 'Interpreter', 'latex');
ylim([0.38, 1.32]); xlim([0, 4]);
format_ieee_ax(ax1, false);

% (b) Grid Active Power p_g with Battery Backup Mode shading
ax_pg1 = nexttile(tl1); hold on;
h_bat = fill(ax_pg1, [t_bat_a, t_bat_b, t_bat_b, t_bat_a], [-0.04, -0.04, 0.72, 0.72], ...
    cols.bat_fill, 'EdgeColor', 'none', 'FaceAlpha', 0.35);
xline(ax_pg1, t_bat_a, ':', 'Color', cols.bat_edge, 'LineWidth', 0.75, 'HandleVisibility', 'off');
xline(ax_pg1, t_bat_b, ':', 'Color', cols.bat_edge, 'LineWidth', 0.75, 'HandleVisibility', 'off');
plot(t1, T_emt.Pg_pu(m1), '--', 'Color', cols.emt, 'LineWidth', lws.emt, 'HandleVisibility', 'off');
plot(t1, Pg_rms(m1), '-', 'Color', cols.rms, 'LineWidth', lws.rms, 'HandleVisibility', 'off');
ylabel('$p_g$ (p.u.)', 'Interpreter', 'latex');
ylim([-0.04, 0.72]); xlim([0, 4]);
format_ieee_ax(ax_pg1, false);
lgd_bat = legend(ax_pg1, h_bat, {'Battery backup'}, ...
    'Location', 'southeast', 'Box', 'off', 'FontSize', 7.5, 'AutoUpdate', 'off');
lgd_bat.ItemTokenSize = [12, 6];

% (c) UPS DC-Link Voltage v_{dc}
ax = nexttile(tl1); hold on;
fill(ax, [t_bat_a, t_bat_b, t_bat_b, t_bat_a], [0.92, 0.92, 1.03, 1.03], ...
    cols.bat_fill, 'EdgeColor', 'none', 'FaceAlpha', 0.35, 'HandleVisibility', 'off');
xline(ax, t_bat_a, ':', 'Color', cols.bat_edge, 'LineWidth', 0.75, 'HandleVisibility', 'off');
xline(ax, t_bat_b, ':', 'Color', cols.bat_edge, 'LineWidth', 0.75, 'HandleVisibility', 'off');
plot(t1, T_emt.Vdc_ups_pu(m1), '--', 'Color', cols.emt, 'LineWidth', lws.emt);
plot(t1, Vdc_rms(m1), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$v_{\mathrm{dc}}$ (p.u.)', 'Interpreter', 'latex');
ylim([0.92, 1.03]); xlim([0, 4]);
format_ieee_ax(ax, false);

% (d) PSU DC-Link Voltage (3-Phase EMT + RMS + Analytic +/- dv_pfc Envelope)
ax_pfc1 = nexttile(tl1); hold on;
fill(ax_pfc1, [t_bat_a, t_bat_b, t_bat_b, t_bat_a], [0.92, 0.92, 1.18, 1.18], ...
    cols.bat_fill, 'EdgeColor', 'none', 'FaceAlpha', 0.35, 'HandleVisibility', 'off');
xline(ax_pfc1, t_bat_a, ':', 'Color', cols.bat_edge, 'LineWidth', 0.75, 'HandleVisibility', 'off');
xline(ax_pfc1, t_bat_b, ':', 'Color', cols.bat_edge, 'LineWidth', 0.75, 'HandleVisibility', 'off');
h_pa   = plot(t1, T_emt.Vpsu_a_pu(m1), '-', 'Color', cols.pa, 'LineWidth', lws.psu);
h_pb   = plot(t1, T_emt.Vpsu_b_pu(m1), '-', 'Color', cols.pb, 'LineWidth', lws.psu);
h_pc   = plot(t1, T_emt.Vpsu_c_pu(m1), '-', 'Color', cols.pc, 'LineWidth', lws.psu);
h_env1 = plot(t1, Vpfc_rms(m1) + ripple.dv_pfc(m1), '--', 'Color', cols.env, 'LineWidth', lws.env);
plot(t1, Vpfc_rms(m1) - ripple.dv_pfc(m1), '--', 'Color', cols.env, 'LineWidth', lws.env, 'HandleVisibility', 'off');
plot(t1, Vpfc_rms(m1), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$v_{\mathrm{pfc}}$ (p.u.)', 'Interpreter', 'latex');
xlabel('Time (s)');
ylim([0.92, 1.18]); xlim([0, 4]);   % Upper headroom reserved cleanly for inset
format_ieee_ax(ax_pfc1, true);

% Non-overlapping per-panel legends (AutoUpdate off + compact token size)
lgd1a = legend(ax1, [h_emt, h_rms, h_vrt], {'EMT', 'RMS', 'VRT envelope'}, ...
    'Orientation', 'horizontal', 'Location', 'southeast', 'Box', 'off', ...
    'FontSize', 7.5, 'AutoUpdate', 'off');
lgd1a.ItemTokenSize = [12, 6];
lgd1b = legend(ax_pfc1, [h_pa, h_pb, h_pc, h_env1], ...
    {'Ph. a', 'Ph. b', 'Ph. c', '$\pm\Delta v_{\mathrm{pfc}}$'}, ...
    'Interpreter', 'latex', 'Orientation', 'horizontal', 'Location', 'northwest', ...
    'Box', 'off', 'FontSize', 7.5, 'AutoUpdate', 'off');
lgd1b.ItemTokenSize = [10, 6];

% Add zoomed inset showing 3-phase 120 Hz envelope bounded by +/- dv_pfc around RMS
drawnow;
add_psu_inset(fig1, ax_pfc1, t1, ...
    T_emt.Vpsu_a_pu(m1), T_emt.Vpsu_b_pu(m1), T_emt.Vpsu_c_pu(m1), ...
    Vpfc_rms(m1), ripple.dv_pfc(m1), ...
    [2.00, 2.035], [0.960, 1.040], [2.30, 1.062, 1.55, 0.095], cols, lws);

exportgraphics(fig1, 'Fig1_VRT_1_to_5s.pdf', 'ContentType', 'vector');

%% 6. Figure 2 (5.0 - 10.0 s): Downstream-to-Upstream Load Propagation
m2 = (t_emt >= 5.0) & (t_emt <= 10.0);
t2 = t_emt(m2) - 5.0;

fig2 = figure('Units', 'inches', 'Position', [6.3, 0.9, fig_w, fig_h], 'Color', 'w');
tl2 = tiledlayout(fig2, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% (a) Downstream Computing Load Power (3*p_chip)
ax2_1 = nexttile(tl2); hold on;
plot(t2, T_emt.Pchip_3ph_pu(m2), '-', 'Color', cols.load, 'LineWidth', lws.rms);
h2_emt_leg = plot(ax2_1, NaN, NaN, '--', 'Color', cols.emt, 'LineWidth', lws.emt);
h2_rms_leg = plot(ax2_1, NaN, NaN, '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$3p_{\mathrm{chip}}$ (p.u.)', 'Interpreter', 'latex');
ylim([0.08, 0.96]); xlim([0, 5]);
format_ieee_ax(ax2_1, false);

% (b) PSU DC-Link Voltage (3-Phase EMT + RMS + Analytic +/- dv_pfc Envelope)
ax_pfc2 = nexttile(tl2); hold on;
h2_pa  = plot(t2, T_emt.Vpsu_a_pu(m2), '-', 'Color', cols.pa, 'LineWidth', lws.psu);
h2_pb  = plot(t2, T_emt.Vpsu_b_pu(m2), '-', 'Color', cols.pb, 'LineWidth', lws.psu);
h2_pc  = plot(t2, T_emt.Vpsu_c_pu(m2), '-', 'Color', cols.pc, 'LineWidth', lws.psu);
h2_env = plot(t2, Vpfc_rms(m2) + ripple.dv_pfc(m2), '--', 'Color', cols.env, 'LineWidth', lws.env);
plot(t2, Vpfc_rms(m2) - ripple.dv_pfc(m2), '--', 'Color', cols.env, 'LineWidth', lws.env, 'HandleVisibility', 'off');
plot(t2, Vpfc_rms(m2), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$v_{\mathrm{pfc}}$ (p.u.)', 'Interpreter', 'latex');
ylim([0.56, 1.48]); xlim([0, 5]);
format_ieee_ax(ax_pfc2, false);

% (c) UPS DC-Link Voltage v_{dc}
ax = nexttile(tl2); hold on;
plot(t2, T_emt.Vdc_ups_pu(m2), '--', 'Color', cols.emt, 'LineWidth', lws.emt);
plot(t2, Vdc_rms(m2), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$v_{\mathrm{dc}}$ (p.u.)', 'Interpreter', 'latex');
ylim([0.94, 1.06]); xlim([0, 5]);
format_ieee_ax(ax, false);

% (d) Grid Active Power p_g
ax = nexttile(tl2); hold on;
plot(t2, T_emt.Pg_pu(m2), '--', 'Color', cols.emt, 'LineWidth', lws.emt);
plot(t2, Pg_rms(m2), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$p_g$ (p.u.)', 'Interpreter', 'latex');
xlabel('Time (s)');
ylim([-0.05, 1.00]); xlim([0, 5]);
format_ieee_ax(ax, true);

% Non-overlapping per-panel legends (AutoUpdate off + compact token size)
lgd2a = legend(ax2_1, [h2_emt_leg, h2_rms_leg], {'EMT', 'RMS'}, ...
    'Orientation', 'horizontal', 'Location', 'northwest', 'Box', 'off', ...
    'FontSize', 7.5, 'AutoUpdate', 'off');
lgd2a.ItemTokenSize = [12, 6];
lgd2b = legend(ax_pfc2, [h2_pa, h2_pb, h2_pc, h2_env], ...
    {'Ph. a', 'Ph. b', 'Ph. c', '$\pm\Delta v_{\mathrm{pfc}}$'}, ...
    'Interpreter', 'latex', 'Orientation', 'horizontal', 'Location', 'south', ...
    'Box', 'off', 'FontSize', 7.5, 'AutoUpdate', 'off');
lgd2b.ItemTokenSize = [10, 6];

% Add zoomed inset in empty region above [1.66, 2.56] zooming into [2.00, 2.035] s
drawnow;
add_psu_inset(fig2, ax_pfc2, t2, ...
    T_emt.Vpsu_a_pu(m2), T_emt.Vpsu_b_pu(m2), T_emt.Vpsu_c_pu(m2), ...
    Vpfc_rms(m2), ripple.dv_pfc(m2), ...
    [2.00, 2.035], [0.945, 1.055], [1.66, 1.16, 0.90, 0.255], cols, lws);

exportgraphics(fig2, 'Fig2_LoadProp_5_to_10s.pdf', 'ContentType', 'vector');

disp('Simulation complete. Exported Fig1_VRT_1_to_5s.pdf and Fig2_LoadProp_5_to_10s.pdf.');

%% ========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function ripple = estimate_pfc_ripple(t, p_eq_av, v_pfc_av, xi_pfc_av, p, Vpsu_a_emt)
% ESTIMATE_PFC_RIPPLE Evaluates the second-harmonic (2*omega) PFC DC-link
% voltage and integral-state ripple estimates from the averaged RMS DAE.
    w = p.w_b;  % Nominal grid angular frequency (rad/s)

    ripple.dv_pfc  = (p.w_b .* abs(p_eq_av)) ./ (2.0 * w .* p.C_pfc .* v_pfc_av);
    ripple.dxi_pfc = ripple.dv_pfc ./ (2.0 * w);
    ripple.rel_v   = ripple.dv_pfc ./ abs(v_pfc_av);
    ripple.rel_xi  = ripple.dxi_pfc ./ max(abs(xi_pfc_av), 1e-12);

    windows = {
        'Light load (0.10 p.u.)',      0.50, 0.90;
        'Sq-wave low (0.18 p.u.)',     8.10, 8.28;
        'Nominal load (0.60 p.u.)',    4.50, 5.00;
        'Sq-wave high (0.78 p.u.)',    7.30, 7.65;
    };

    fprintf('\n================ PFC 2*omega Ripple Consistency Check ================\n');
    fprintf('%-26s | %9s | %9s | %9s | %10s\n', ...
        'Operating Point', 'EMT dv', 'Est dv', 'dv/v (%)', 'dxi/|xi|(%)');
    fprintf('----------------------------------------------------------------------\n');

    for i = 1:size(windows, 1)
        m = (t >= windows{i, 2}) & (t <= windows{i, 3});
        dv_emt = 0.5 * (max(Vpsu_a_emt(m)) - min(Vpsu_a_emt(m)));
        dv_est = mean(ripple.dv_pfc(m));
        rv_pct = 100.0 * mean(ripple.rel_v(m));
        rx_pct = 100.0 * mean(ripple.rel_xi(m));
        fprintf('%-26s | %9.5f | %9.5f | %8.2f%% | %9.4f%%\n', ...
            windows{i, 1}, dv_emt, dv_est, rv_pct, rx_pct);
    end

    fprintf('----------------------------------------------------------------------\n');
    fprintf('Full-trajectory max (0-10 s): dv_pfc = %.5f p.u. (%.2f%%), dxi/|xi| = %.4f%%\n', ...
        max(ripple.dv_pfc), 100.0 * max(ripple.rel_v), 100.0 * max(ripple.rel_xi));
    fprintf('======================================================================\n\n');
end

function [v_low, v_high] = vrt_envelope_profile(t, Vg)
% VRT_ENVELOPE_PROFILE Computes the piecewise-constant (sample-and-hold)
% PSCAD VRT ride-through envelope [v_low, v_high].
    N = numel(t);
    v_low  = 0.90 * ones(N, 1);
    v_high = 1.10 * ones(N, 1);

    tau = 0.0;
    for k = 1:N
        if k > 1
            dt_k = t(k) - t(k-1);
        else
            dt_k = 0.0;
        end

        if Vg(k) >= 0.90 && Vg(k) <= 1.10
            tau = 0.0;
            v_low(k)  = 0.90;
            v_high(k) = 1.10;
        else
            tau = min(tau + dt_k, 2.0);
            v_low(k)  = interp1([0.0, 0.5, 1.5, 2.0], [0.5, 0.5, 0.7, 0.9], tau, 'next');
            v_high(k) = interp1([0.0, 1.0, 2.0],      [1.3, 1.2, 1.1],      tau, 'next');
        end
    end
end

function add_psu_inset(fig, ax_parent, t, va, vb, vc, vrms, dv_pfc, z_xlim, z_ylim, inset_data_rect, cols, lws)
% ADD_PSU_INSET Places a clean zoomed inset inside ax_parent using data
% coordinates inset_data_rect = [x0, y0, width, height].
    hold(ax_parent, 'on');
    rectangle(ax_parent, 'Position', [z_xlim(1), z_ylim(1), diff(z_xlim), diff(z_ylim)], ...
        'EdgeColor', [0.25, 0.25, 0.25], 'LineWidth', 0.65, 'LineStyle', '-');

    x_src = z_xlim(1) + 0.5 * diff(z_xlim);
    y_src = z_ylim(2);
    x_dst_l = inset_data_rect(1);
    x_dst_r = inset_data_rect(1) + inset_data_rect(3);
    y_dst_b = inset_data_rect(2);
    plot(ax_parent, [x_src, x_dst_l], [y_src, y_dst_b], ':', 'Color', [0.35, 0.35, 0.35], 'LineWidth', 0.6, 'HandleVisibility', 'off');
    plot(ax_parent, [x_src, x_dst_r], [y_src, y_dst_b], ':', 'Color', [0.35, 0.35, 0.35], 'LineWidth', 0.6, 'HandleVisibility', 'off');

    ax_pos = ax_parent.Position;
    xl = ax_parent.XLim;
    yl = ax_parent.YLim;

    fx = ax_pos(1) + ((inset_data_rect(1) - xl(1)) / diff(xl)) * ax_pos(3);
    fy = ax_pos(2) + ((inset_data_rect(2) - yl(1)) / diff(yl)) * ax_pos(4);
    fw = (inset_data_rect(3) / diff(xl)) * ax_pos(3);
    fh = (inset_data_rect(4) / diff(yl)) * ax_pos(4);

    ax_in = axes(fig, 'Position', [fx, fy, fw, fh], 'Color', 'w');
    hold(ax_in, 'on');

    mz = (t >= z_xlim(1)) & (t <= z_xlim(2));
    plot(ax_in, t(mz), va(mz), '-', 'Color', cols.pa, 'LineWidth', 0.85);
    plot(ax_in, t(mz), vb(mz), '-', 'Color', cols.pb, 'LineWidth', 0.85);
    plot(ax_in, t(mz), vc(mz), '-', 'Color', cols.pc, 'LineWidth', 0.85);
    plot(ax_in, t(mz), vrms(mz) + dv_pfc(mz), '--', 'Color', cols.env, 'LineWidth', 0.90);
    plot(ax_in, t(mz), vrms(mz) - dv_pfc(mz), '--', 'Color', cols.env, 'LineWidth', 0.90);
    plot(ax_in, t(mz), vrms(mz), '-', 'Color', cols.rms, 'LineWidth', 1.15);

    xlim(ax_in, z_xlim);
    ylim(ax_in, z_ylim);
    box(ax_in, 'on');
    grid(ax_in, 'on');
    ax_in.GridAlpha = 0.20;
    ax_in.GridLineStyle = ':';
    ax_in.FontName = 'Times New Roman';
    ax_in.FontSize = 6.5;
    ax_in.LineWidth = 0.55;
    ax_in.TickDir = 'in';
    ax_in.XTick = [z_xlim(1), z_xlim(2)];
    ax_in.YTick = [z_ylim(1), 1.00, z_ylim(2)];
end

function p = build_per_unit_params(cfg)
    p.S_b      = cfg.M_ups * cfg.S_ups_MVA;
    p.f_b      = cfg.f_b;
    p.w_b      = 2.0 * pi * cfg.f_b;
    p.E_b      = p.S_b / p.w_b;
    p.alpha    = (cfg.M_psu * cfg.S_psu_MVA) / cfg.S_ups_MVA;

    p.V_LL_b   = cfg.V_LL_kV;
    p.V_dq_b   = sqrt(2/3) * cfg.V_LL_kV;
    p.I_dq_b   = sqrt(2/3) * p.S_b / cfg.V_LL_kV;
    p.Z_ac_b   = (cfg.V_LL_kV^2) / p.S_b;
    p.V_dc_b   = cfg.V_dc_kV;
    p.V_bat_b  = cfg.V_bat_kV;
    p.V_pfc_b  = cfg.V_pfc_kV;
    p.V_buck_b = cfg.V_buck_kV;

    p.C_ups    = cfg.c_dc_afe_pu;
    p.R_cv     = cfg.r_afe_pu;
    p.C_iv     = cfg.c_vsi_pu;
    p.R_iv     = cfg.r_vsi_pu;
    p.C_pfc    = p.alpha * cfg.c_dc_pfc_pu;
    p.R_pfc    = cfg.r_pfc_pu / p.alpha;
    p.C_buck   = p.alpha * cfg.c_dc_buck_pu;

    p.c_dc_afe_local  = cfg.c_dc_afe_pu;
    p.c_vsi_local     = cfg.c_vsi_pu;
    p.c_dc_pfc_local  = cfg.c_dc_pfc_pu;
    p.c_dc_buck_local = cfg.c_dc_buck_pu;

    p.v_dc_ref    = 1.0;
    p.v_iv_d_ref  = 1.0;
    p.v_pfc_ref   = 1.0;
    p.v_buck_ref  = 1.0;
    p.v_bat       = cfg.v_bat_pu;
    p.p_bat_ref   = cfg.p_bat_ref_pu;
    p.ramp_rec    = cfg.ramp_rec_pu;
end

function ctrl = tune_pi_controllers(p, bw)
    wb = p.w_b;

    wn_afe = 2.0 * pi * bw.fbw_afe;
    ctrl.kp_v_afe = 2.0 * bw.zt_afe * wn_afe * p.c_dc_afe_local / wb;
    ctrl.ki_v_afe = (wn_afe^2) * p.c_dc_afe_local / wb;

    wn_bat = 2.0 * pi * bw.fbw_bat;
    ctrl.kp_v_bat = 2.0 * bw.zt_bat * wn_bat * p.c_dc_afe_local / wb;
    ctrl.ki_v_bat = (wn_bat^2) * p.c_dc_afe_local / wb;

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

function [dx, alg] = rms_datacenter_dae(t, x, p, ctrl, mode_info)
    E_afe   = x(1);  E_vsi   = x(2);  E_pfc   = x(3);  E_buck  = x(4);
    xi_afe  = x(5);  xi_bat  = x(6);  xi_vsi  = x(7);  xi_pfc  = x(8);
    xi_buck = x(9);

    v_dc   = sqrt(max(2.0 * E_afe  / p.C_ups,  1e-8));
    v_iv_d = sqrt(max(2.0 * E_vsi  / p.C_iv,   1e-8));
    v_pfc  = sqrt(max(2.0 * E_pfc  / p.C_pfc,  1e-8));
    v_buck = sqrt(max(2.0 * E_buck / p.C_buck, 1e-8));

    V_g = voltage_dip_profile(t);
    is_backup = strcmp(mode_info.mode, 'backup');
    S_r  = double(~is_backup);
    S_i  = 1.0;
    S_bp = 0.0;
    M_b  = double(is_backup);

    i_cv_d = S_r * (ctrl.kp_v_afe * (p.v_dc_ref - v_dc) + ctrl.ki_v_afe * xi_afe);

    if is_backup
        i_bat = -(ctrl.kp_v_bat * (p.v_dc_ref - v_dc) + ctrl.ki_v_bat * xi_bat);
    elseif strcmp(mode_info.mode, 'soft_rec')
        i_bat = min(0.0, mode_info.i_bat0 + p.ramp_rec * (t - mode_info.t_recon));
    else
        i_bat = 0.0;
    end

    i_iv_d = S_i * (ctrl.kp_v_vsi * (p.v_iv_d_ref - v_iv_d) + ctrl.ki_v_vsi * xi_vsi);
    i_iv_q = S_i * p.C_iv * v_iv_d;
    G_eq   = ctrl.kp_v_pfc  * (p.v_pfc_ref  - v_pfc)  + ctrl.ki_v_pfc  * xi_pfc;
    i_L    = ctrl.kp_v_buck * (p.v_buck_ref - v_buck) + ctrl.ki_v_buck * xi_buck;

    t_eval = t;
    if abs(t - mode_info.ta) < 1e-12
        t_eval = t + 1e-9;
    elseif abs(t - mode_info.tb) < 1e-12
        t_eval = t - 1e-9;
    end
    p_chip = p.alpha * load_square_profile(t_eval);

    p_load    = (v_buck^2) * p_chip;
    p_buck_in = v_buck * i_L;
    p_psu     = (S_i * v_iv_d^2 + S_bp * V_g^2) * G_eq;
    p_eq      = (p_psu / 3.0) * (1.0 - p.R_pfc * G_eq);
    p_iv_ac   = v_iv_d * i_iv_d;
    p_iv_dc   = p_iv_ac + p.R_iv * (i_iv_d^2 + i_iv_q^2);
    p_afe     = V_g * i_cv_d - p.R_cv * (i_cv_d^2);
    p_bat     = p.v_bat * i_bat + (1.0 - M_b) * p.p_bat_ref;
    p_g       = V_g * i_cv_d + S_bp * p_psu;

    dx = [
        p.w_b * (p_afe - p_iv_dc - p_bat);
        p.w_b * (p_iv_ac - S_i * p_psu);
        p.w_b * (p_eq - p_buck_in);
        p.w_b * (p_buck_in - p_load);
        S_r * (p.v_dc_ref - v_dc);
        M_b * (p.v_dc_ref - v_dc);
        S_i * (p.v_iv_d_ref - v_iv_d);
        p.v_pfc_ref - v_pfc;
        p.v_buck_ref - v_buck;
    ];

    alg.V_g    = V_g;
    alg.p_g    = p_g;
    alg.i_cv_d = i_cv_d;
    alg.v_dc   = v_dc;
    alg.v_iv_d = v_iv_d;
    alg.i_iv_d = i_iv_d;
    alg.i_iv_q = i_iv_q;
    alg.v_pfc  = v_pfc;
    alg.v_buck = v_buck;
    alg.p_eq   = p_eq;
    alg.xi_pfc = xi_pfc;
    alg.G_eq   = G_eq;
    alg.i_L    = i_L;
end

function dx = rms_ode_wrapper(t, x, p, ctrl, mode_info)
    [dx, ~] = rms_datacenter_dae(t, x, p, ctrl, mode_info);
end

function x0 = compute_steady_state_ic(p, ctrl, p_load_local_pu)
    p_chip0  = p.alpha * p_load_local_pu;
    xi_buck0 = p_chip0 / ctrl.ki_v_buck;
    G_eq0    = (1.0 - sqrt(1.0 - 12.0 * p.R_pfc * p_chip0)) / (2.0 * p.R_pfc);
    xi_pfc0  = G_eq0 / ctrl.ki_v_pfc;
    i_iv_d0  = G_eq0;
    xi_vsi0  = i_iv_d0 / ctrl.ki_v_vsi;
    p_iv_dc0 = i_iv_d0 + p.R_iv * (i_iv_d0^2 + p.C_iv^2);
    i_cv_d0  = (1.0 - sqrt(1.0 - 4.0 * p.R_cv * p_iv_dc0)) / (2.0 * p.R_cv);
    xi_afe0  = i_cv_d0 / ctrl.ki_v_afe;

    x0 = [
        0.5 * p.C_ups;
        0.5 * p.C_iv;
        0.5 * p.C_pfc;
        0.5 * p.C_buck;
        xi_afe0;
        0.0;
        xi_vsi0;
        xi_pfc0;
        xi_buck0;
    ];
end

function V_g = voltage_dip_profile(t)
    if t <= 2.0
        V_g = 1.0;
    elseif t < 2.055
        V_g = 1.0 - 10.0 * (t - 2.0);
    elseif t <= 2.5
        V_g = 0.45;
    elseif t < 3.6
        V_g = 0.45 + 0.5 * (t - 2.5);
    else
        V_g = 1.0;
    end
end

function p_pu = load_square_profile(t)
    if t <= 1.0
        p_ramp = 0.0;
    elseif t < 1.5
        p_ramp = 0.50 * (t - 1.0) / 0.5;
    else
        p_ramp = 0.50;
    end
    p_base = 0.10 + p_ramp;

    if t <= 6.0
        p_pu = p_base;
    else
        c_val = cos(2.0 * pi * 0.5 * (t - 6.0));
        c_thr = cos(pi * (1.0 - 0.70));
        if c_val > c_thr
            p_pu = p_base - 0.42;
        else
            p_pu = p_base + 0.18;
        end
    end
end

function y = first_order_lpf(x, dt, Tm)
    if Tm <= 0
        y = x;
        return;
    end
    y = zeros(size(x));
    y(1) = x(1);
    a = exp(-dt / Tm);
    for k = 2:numel(x)
        y(k) = a * y(k-1) + (1.0 - a) * 0.5 * (x(k) + x(k-1));
    end
end

function format_ieee_ax(ax, show_xlabel)
    box(ax, 'on');
    grid(ax, 'on');
    ax.GridAlpha = 0.22;
    ax.GridLineStyle = ':';
    ax.TickDir = 'in';
    ax.FontName = 'Times New Roman';
    ax.FontSize = 8.5;
    if ~show_xlabel
        ax.XTickLabel = [];
    end
end