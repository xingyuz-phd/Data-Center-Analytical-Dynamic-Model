%% ========================================================================
%  EMT vs. RMS Per-Unit Benchmark: Normal <-> Bypass Mode Transition Event
%  - Modular functions:
%      1. build_per_unit_params()  : Unified per-unit base & plant conversion
%      2. tune_pi_controllers()    : Bandwidth-based PI controller tuning
%      3. rms_datacenter_dae()     : 9-state per-unit RMS DAE formulation
%      4. add_psu_inset()          : Zoomed inset showing 3-phase envelope around RMS
%      5. estimate_pfc_ripple()    : Second-harmonic PFC ripple consistency check
%  - Reads: Bypass_EMT_PerUnit_Data.xlsx (Sheet: 'EMT_PerUnit_Data')
%  - Exports vector PDF figure (3 stacked panels: p_g, v_dc, v_pfc):
%      Fig3_Bypass_2_to_5s.pdf     (2-5 s, shifted to 0-3 s):
%          Steady 0.7 p.u. load, Normal -> Bypass (0.5 s),
%          and Bypass -> Normal (1.5 s)
% =========================================================================
clear; clc; close all;

%% 1. Load Unified Per-Unit EMT Dataset
emt_file = 'Bypass_EMT_PerUnit_Data.xlsx';
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
% Event segments: {t_start, t_end, mode_name}
segments = {
    0.0,  1.0,  'normal';
    1.0,  1.5,  'normal';
    1.5,  2.5,  'normal';
    2.5,  3.5,  'bypass';
    3.5,  10.0, 'normal';
};

% Steady-state initialization at t = 0 (Pload_pu = 0.10)
x_curr = compute_steady_state_ic(p, ctrl, 0.10);

opts  = odeset('RelTol', 1e-8, 'AbsTol', 1e-10);
N_tot = numel(t_emt);

t_rms      = zeros(N_tot, 1);
Pg_raw     = zeros(N_tot, 1);
Vdc_rms    = zeros(N_tot, 1);
Vpfc_rms   = zeros(N_tot, 1);
Peq_rms    = zeros(N_tot, 1);
Xi_pfc_rms = zeros(N_tot, 1);

cursor = 1;

for k = 1:size(segments, 1)
    ta   = segments{k, 1};
    tb   = segments{k, 2};
    mode = segments{k, 3};

    % Mode-transition integral reset: xi_vsi held at 0 when S_i = 0 (bypass)
    if k > 1
        prev_mode = segments{k-1, 3};
        if ~strcmp(prev_mode, mode)
            x_curr(7) = 0.0;  % Reset xi_vsi on Normal <-> Bypass transition
        end
    end

    mode_info.mode = mode;
    mode_info.ta   = ta;
    mode_info.tb   = tb;

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
        Pg_raw(cursor)     = alg.p_g;
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

%% 4. IEEE Aesthetic Styling Palette & Figure Dimensions
cols.rms     = [0.00, 0.00, 0.00];         % Solid black for RMS
cols.emt     = [0.55, 0.55, 0.55];         % Muted gray dashed for EMT
cols.env     = [0.49, 0.18, 0.56];         % Purple dashed for +/- dv_pfc envelope
cols.bp_fill = [0.88, 0.88, 0.88];         % Light gray shading for Bypass mode
cols.pa      = [0.23, 0.49, 0.77, 0.72];   % Muted steel blue (Phase a)
cols.pb      = [0.85, 0.37, 0.28, 0.72];   % Soft terracotta coral (Phase b)
cols.pc      = [0.20, 0.63, 0.50, 0.72];   % Muted sage teal (Phase c)

lws.rms = 1.05;
lws.emt = 1.05;
lws.env = 0.90;
lws.psu = 0.70;

fig_w = 5.2;   % Wider IEEE layout (inches)
fig_h = 3.45;  % Clean proportions for 3 stacked panels with zoomed inset

set(0, 'DefaultAxesFontName', 'Times New Roman');
set(0, 'DefaultTextFontName', 'Times New Roman');
set(0, 'DefaultAxesFontSize', 8.5);
set(0, 'DefaultTextFontSize', 9);
set(0, 'DefaultAxesLineWidth', 0.6);

%% 5. Figure 3 (2.0 - 5.0 s, shifted to 0 - 3 s): Normal <-> Bypass Switching
m1 = (t_emt >= 2.0) & (t_emt <= 5.0);
t1 = t_emt(m1) - 2.0;

fig3 = figure('Units', 'inches', 'Position', [1.0, 1.2, fig_w, fig_h], 'Color', 'w');
tl3  = tiledlayout(fig3, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% (a) Grid Active Power p_g with Bypass Mode shading
ax1 = nexttile(tl3); hold on;
h_bp  = fill(ax1, [0.5, 1.5, 1.5, 0.5], [0.54, 0.54, 0.86, 0.86], ...
    cols.bp_fill, 'EdgeColor', 'none', 'FaceAlpha', 0.45);
h_emt = plot(t1, T_emt.Pg_pu(m1), '--', 'Color', cols.emt, 'LineWidth', lws.emt);
h_rms = plot(t1, Pg_rms(m1), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$p_g$ (p.u.)', 'Interpreter', 'latex');
ylim([0.54, 0.86]); xlim([0, 3]);
format_ieee_ax(ax1, false);

% (b) UPS DC-Link Voltage v_{dc}
ax2 = nexttile(tl3); hold on;
fill(ax2, [0.5, 1.5, 1.5, 0.5], [0.88, 0.88, 1.12, 1.12], ...
    cols.bp_fill, 'EdgeColor', 'none', 'FaceAlpha', 0.30, 'HandleVisibility', 'off');
plot(t1, T_emt.Vdc_ups_pu(m1), '--', 'Color', cols.emt, 'LineWidth', lws.emt);
plot(t1, Vdc_rms(m1), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$v_{\mathrm{dc}}$ (p.u.)', 'Interpreter', 'latex');
ylim([0.88, 1.12]); xlim([0, 3]);
format_ieee_ax(ax2, false);

% (c) PSU DC-Link Voltage (3-Phase EMT + Purple +/- dv_pfc + RMS) with zoomed inset
ax_pfc = nexttile(tl3); hold on;
fill(ax_pfc, [0.5, 1.5, 1.5, 0.5], [0.91, 0.91, 1.22, 1.22], ...
    cols.bp_fill, 'EdgeColor', 'none', 'FaceAlpha', 0.30, 'HandleVisibility', 'off');
h_pa  = plot(t1, T_emt.Vpsu_a_pu(m1), '-', 'Color', cols.pa, 'LineWidth', lws.psu);
h_pb  = plot(t1, T_emt.Vpsu_b_pu(m1), '-', 'Color', cols.pb, 'LineWidth', lws.psu);
h_pc  = plot(t1, T_emt.Vpsu_c_pu(m1), '-', 'Color', cols.pc, 'LineWidth', lws.psu);
h_env = plot(t1, Vpfc_rms(m1) + ripple.dv_pfc(m1), '--', 'Color', cols.env, 'LineWidth', lws.env);
plot(t1, Vpfc_rms(m1) - ripple.dv_pfc(m1), '--', 'Color', cols.env, 'LineWidth', lws.env, 'HandleVisibility', 'off');
plot(t1, Vpfc_rms(m1), '-', 'Color', cols.rms, 'LineWidth', lws.rms);
ylabel('$v_{\mathrm{pfc}}$ (p.u.)', 'Interpreter', 'latex');
xlabel('Time (s)');
ylim([0.91, 1.22]); xlim([0, 3]);   % Upper headroom reserved cleanly for inset
format_ieee_ax(ax_pfc, true);

% Non-overlapping per-panel legends
lgd_a = legend(ax1, [h_emt, h_rms, h_bp], {'EMT', 'RMS', 'Bypass mode'}, ...
    'Orientation', 'horizontal', 'Location', 'northeast', 'Box', 'off', ...
    'FontSize', 7.5, 'AutoUpdate', 'off');
lgd_a.ItemTokenSize = [12, 6];

lgd_b = legend(ax_pfc, [h_pa, h_pb, h_pc, h_env], ...
    {'Ph. a', 'Ph. b', 'Ph. c', '$\pm\Delta v_{\mathrm{pfc}}$'}, ...
    'Interpreter', 'latex', 'Orientation', 'horizontal', 'Location', 'northwest', ...
    'Box', 'off', 'FontSize', 7.5, 'AutoUpdate', 'off');
lgd_b.ItemTokenSize = [10, 6];

% Add zoomed inset showing 3-phase 120 Hz envelope bounded by +/- dv_pfc around RMS
drawnow;
add_psu_inset(fig3, ax_pfc, t1, ...
    T_emt.Vpsu_a_pu(m1), T_emt.Vpsu_b_pu(m1), T_emt.Vpsu_c_pu(m1), ...
    Vpfc_rms(m1), ripple.dv_pfc(m1), ...
    [2.35, 2.385], [0.955, 1.045], [1.92, 1.095, 0.98, 0.108], cols, lws);

exportgraphics(fig3, 'Fig3_Bypass_2_to_5s.pdf', 'ContentType', 'vector');

disp('Simulation complete. Exported Fig3_Bypass_2_to_5s.pdf.');

%% ========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function ripple = estimate_pfc_ripple(t, p_eq_av, v_pfc_av, xi_pfc_av, p, Vpsu_a_emt)
% ESTIMATE_PFC_RIPPLE Evaluates the second-harmonic (2*omega) PFC DC-link
% voltage and integral-state ripple estimates from the averaged RMS DAE.
    w = p.w_b;
    ripple.dv_pfc  = (p.w_b .* abs(p_eq_av)) ./ (2.0 * w .* p.C_pfc .* v_pfc_av);
    ripple.dxi_pfc = ripple.dv_pfc ./ (2.0 * w);
    ripple.rel_v   = ripple.dv_pfc ./ abs(v_pfc_av);
    ripple.rel_xi  = ripple.dxi_pfc ./ max(abs(xi_pfc_av), 1e-12);

    windows = {
        'Light load (0.10 p.u.)',          0.50, 0.90;
        'Normal mode (0.70 p.u.)',         2.00, 2.40;
        'Bypass mode (0.70 p.u.)',         2.90, 3.40;
        'Post-return normal (0.70 p.u.)',  4.50, 5.00;
    };

    fprintf('\n============= Bypass Event: PFC 2*omega Ripple Check =============\n');
    fprintf('%-30s | %9s | %9s | %9s | %10s\n', ...
        'Operating Point', 'EMT dv', 'Est dv', 'dv/v (%)', 'dxi/|xi|(%)');
    fprintf('------------------------------------------------------------------\n');
    for i = 1:size(windows, 1)
        m = (t >= windows{i, 2}) & (t <= windows{i, 3});
        dv_emt = 0.5 * (max(Vpsu_a_emt(m)) - min(Vpsu_a_emt(m)));
        dv_est = mean(ripple.dv_pfc(m));
        rv_pct = 100.0 * mean(ripple.rel_v(m));
        rx_pct = 100.0 * mean(ripple.rel_xi(m));
        fprintf('%-30s | %9.5f | %9.5f | %8.2f%% | %9.4f%%\n', ...
            windows{i, 1}, dv_emt, dv_est, rv_pct, rx_pct);
    end
    fprintf('==================================================================\n\n');
end

function add_psu_inset(fig, ax_parent, t, va, vb, vc, vrms, dv_pfc, z_xlim, z_ylim, inset_data_rect, cols, lws)
% ADD_PSU_INSET Places a clean zoomed inset inside ax_parent using data
% coordinates inset_data_rect = [x0, y0, width, height].
    hold(ax_parent, 'on');
    rectangle(ax_parent, 'Position', [z_xlim(1), z_ylim(1), diff(z_xlim), diff(z_ylim)], ...
        'EdgeColor', [0.25, 0.25, 0.25], 'LineWidth', 0.65, 'LineStyle', '-');

    x_src   = z_xlim(1) + 0.5 * diff(z_xlim);
    y_src   = z_ylim(2);
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
    plot(ax_in, t(mz), vrms(mz) + dv_pfc(mz), '--', 'Color', cols.env, 'LineWidth', 0.95);
    plot(ax_in, t(mz), vrms(mz) - dv_pfc(mz), '--', 'Color', cols.env, 'LineWidth', 0.95);
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
% BUILD_PER_UNIT_PARAMS Convert PSCAD local plant parameters into the
% unified common three-phase per-unit system (S_b = M_ups * S_ups_MVA).
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
end

function ctrl = tune_pi_controllers(p, bw)
% TUNE_PI_CONTROLLERS Compute outer-loop PI gains from bandwidth (Hz) and
% damping ratio, projected onto the common RMS per-unit base S_b.
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
% RMS_DATACENTER_DAE 9-state per-unit RMS DAE model supporting normal and
% bypass operating modes:
%   normal : (S_r, S_i, S_bp, M_b) = (1, 1, 0, 0)
%   bypass : (S_r, S_i, S_bp, M_b) = (1, 0, 1, 0)
    E_afe   = x(1);  E_vsi   = x(2);  E_pfc   = x(3);  E_buck  = x(4);
    xi_afe  = x(5);  xi_bat  = x(6);  xi_vsi  = x(7);  xi_pfc  = x(8);
    xi_buck = x(9);

    v_dc   = sqrt(max(2.0 * E_afe  / p.C_ups,  1e-8));
    v_iv_d = sqrt(max(2.0 * E_vsi  / p.C_iv,   1e-8));
    v_pfc  = sqrt(max(2.0 * E_pfc  / p.C_pfc,  1e-8));
    v_buck = sqrt(max(2.0 * E_buck / p.C_buck, 1e-8));

    V_g = 1.0;
    is_bypass = strcmp(mode_info.mode, 'bypass');
    S_r  = 1.0;
    S_i  = double(~is_bypass);
    S_bp = double(is_bypass);
    M_b  = 0.0;

    i_cv_d = S_r * (ctrl.kp_v_afe * (p.v_dc_ref - v_dc) + ctrl.ki_v_afe * xi_afe);
    i_bat  = 0.0;
    i_iv_d = S_i * (ctrl.kp_v_vsi * (p.v_iv_d_ref - v_iv_d) + ctrl.ki_v_vsi * xi_vsi);
    i_iv_q = S_i * p.C_iv * v_iv_d;
    G_eq   = ctrl.kp_v_pfc  * (p.v_pfc_ref  - v_pfc)  + ctrl.ki_v_pfc  * xi_pfc;
    i_L    = ctrl.kp_v_buck * (p.v_buck_ref - v_buck) + ctrl.ki_v_buck * xi_buck;

    p_chip    = p.alpha * load_ramp_profile(t);
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

    alg.p_g    = p_g;
    alg.v_dc   = v_dc;
    alg.v_pfc  = v_pfc;
    alg.p_eq   = p_eq;
    alg.xi_pfc = xi_pfc;
end

function dx = rms_ode_wrapper(t, x, p, ctrl, mode_info)
    [dx, ~] = rms_datacenter_dae(t, x, p, ctrl, mode_info);
end

function x0 = compute_steady_state_ic(p, ctrl, p_load_local_pu)
% COMPUTE_STEADY_STATE_IC Exact normal-mode equilibrium at t = 0.
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

function p_pu = load_ramp_profile(t)
% LOAD_RAMP_PROFILE Chip demand ramp from 0.10 to 0.70 p.u. over [1.0, 1.5] s.
    if t <= 1.0
        p_pu = 0.10;
    elseif t < 1.5
        p_pu = 0.10 + 0.60 * (t - 1.0) / 0.5;
    else
        p_pu = 0.70;
    end
end

function y = first_order_lpf(x, dt, Tm)
% FIRST_ORDER_LPF Exact discrete first-order smoothing filter (tau = Tm).
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
% FORMAT_IEEE_AX Clean IEEE axis styling.
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