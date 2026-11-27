%% ========================================================================
%  Small-Signal Modal Analysis & Frequency-Domain Gain Study (Bypass Mode)
%  - Bypass operating mode: (S_r, S_i, S_bp, M_b) = (1, 0, 1, 0)
%    VSI is disconnected (6 active states: E_afe, E_pfc, E_buck, xi_afe, xi_pfc, xi_buck)
%    PSUs connect directly to the grid POI voltage V_g (PSU-Grid feedback active)
%  - Algebraic grid model: V_s, Z_g = R_g + j*X_g (unity PF at POI)
%  - Input w = p_chip,3ph (so DC internal gain & grid coupling gain ~ 1)
%  - Exports vector PDFs:
%      Fig6_Bypass_RootLocus.pdf     : 1x3 complex s-plane root-locus sweeps
%      Fig7_Bypass_Gain_FreqResp.pdf : 2x3 internal & grid coupling gain sweeps
% =========================================================================
clear; clc; close all;

%% 1. Base System Configuration (Aligned Unified Per-Unit Base: S_b = 45 MVA)
cfg.M_ups      = 30;      % Parallel UPS aggregation multiplier
cfg.M_psu      = 10;      % Parallel PSU aggregation multiplier per UPS
cfg.S_ups_MVA  = 1.50;    % Single UPS rated power (MVA)
cfg.S_psu_MVA  = 0.05;    % Single PSU module local power base (MVA)
cfg.f_b        = 60.0;    % Nominal frequency (Hz)

cfg.c_dc_afe_pu  = 10.0;
cfg.r_afe_pu     = 0.003;
cfg.c_dc_pfc_pu  = 10.0;
cfg.r_pfc_pu     = 0.003;
cfg.c_dc_buck_pu = 2.5;

bw.fbw_afe  = 20.0;  bw.zt_afe  = 0.707;
bw.fbw_pfc  = 10.0;  bw.zt_pfc  = 1.0;
bw.fbw_buck = 20.0;  bw.zt_buck = 1.0;

p = build_per_unit_params(cfg);

% Nominal algebraic grid & operating point
V_s_nom      = 1.00;   % Sending-end voltage magnitude (p.u.)
X_g_nom      = 0.35;   % Grid reactance (p.u. on S_b = 45 MVA)
R_g_nom      = 0.035;  % Grid resistance (R_g / X_g = 0.1)
p_chip3_nom  = 0.70;   % Nominal 3-phase chip demand (p.u.)

%% 2. Baseline Modal Table & Participation Factors
ctrl_nom = tune_pi_controllers(p, bw);
res_nom  = solve_bypass_modal(p_chip3_nom, V_s_nom, R_g_nom, X_g_nom, p, ctrl_nom);
print_modal_table(res_nom);

%% 3. Root-Locus Parameter Sweeps
p_vals   = linspace(0.10, 1.20, 45);
xg_vals  = linspace(0.00, 0.63, 45);
fbw_vals = linspace(5.0,  35.0, 45);   % PSU PFC bandwidth (VSI is OFF in bypass)

eigs_p   = nan(6, numel(p_vals));
eigs_xg  = nan(6, numel(xg_vals));
eigs_fbw = nan(6, numel(fbw_vals));

for i = 1:numel(p_vals)
    r = solve_bypass_modal(p_vals(i), V_s_nom, R_g_nom, X_g_nom, p, ctrl_nom);
    if r.ok, eigs_p(:, i) = r.eigs; end
end

for i = 1:numel(xg_vals)
    xg = xg_vals(i);
    r = solve_bypass_modal(p_chip3_nom, V_s_nom, 0.1 * xg, xg, p, ctrl_nom);
    if r.ok, eigs_xg(:, i) = r.eigs; end
end

for i = 1:numel(fbw_vals)
    bw_i = bw;
    bw_i.fbw_pfc = fbw_vals(i);
    ctrl_i = tune_pi_controllers(p, bw_i);
    r = solve_bypass_modal(p_chip3_nom, V_s_nom, R_g_nom, X_g_nom, p, ctrl_i);
    if r.ok, eigs_fbw(:, i) = r.eigs; end
end

%% 4. Figure 6: 1x3 Complex s-Plane Root-Locus (Bypass Mode)
set(0, 'DefaultAxesFontName', 'Times New Roman');
set(0, 'DefaultTextFontName', 'Times New Roman');
set(0, 'DefaultAxesFontSize', 13);
set(0, 'DefaultTextFontSize', 13.5);
set(0, 'DefaultAxesLineWidth', 0.9);

fig6 = figure('Units', 'inches', 'Position', [0.8, 3.2, 7.16, 3.35], 'Color', 'w');
tl6  = tiledlayout(fig6, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
cmap = flipud(parula(256));

ax1 = nexttile(tl6);
plot_root_locus_panel(ax1, p_vals, eigs_p, cmap, ...
    '(a) Varying $\mathrm{p}_{\mathrm{chip},3\phi}$', ...
    '$\mathrm{p}_{\mathrm{chip},3\phi}$ (p.u.)', [-105, 12], [-105, 105], true, [0.1, 0.4, 0.8, 1.2]);

ax2 = nexttile(tl6);
plot_root_locus_panel(ax2, xg_vals, eigs_xg, cmap, ...
    '(b) Varying $X_g$ ($R_g=0.1X_g$)', ...
    '$X_g$ (p.u.)', [-105, 12], [-105, 105], false, [0.0, 0.2, 0.4, 0.6]);

ax3 = nexttile(tl6);
plot_root_locus_panel(ax3, fbw_vals, eigs_fbw, cmap, ...
    '(c) Varying $f_{\mathrm{bw,pfc}}$', ...
    '$f_{\mathrm{bw,pfc}}$ (Hz)', [-105, 12], [-105, 105], false, [5, 15, 25, 35]);

drawnow;  % Finalize tiledlayout positions before placing vector arrows
add_mode_arrow(fig6, ax1, -99,  48, -82,  58, -84,  84, 'AFE (no-load)', [0, 0, 0]);
add_mode_arrow(fig6, ax1, -72, -46, -40, -40, -14, -26, 'PSU--Grid',     [0, 0, 0]);
add_mode_arrow(fig6, ax2, -99,  48, -82,  58, -82,  84, 'AFE (no-load)', [0, 0, 0]);
add_mode_arrow(fig6, ax2, -72, -46, -40, -40, -12, -24, 'PSU--Grid',     [0, 0, 0]);
add_mode_arrow(fig6, ax3, -86,  40, -54,  46, -34,  58, 'PSU--Grid',     [0, 0, 0]);
add_mode_arrow(fig6, ax3, -98, -46, -88, -56, -84, -83, 'AFE',           [0, 0, 0]);

exportgraphics(fig6, 'Fig6_Bypass_RootLocus.pdf', 'ContentType', 'vector');

%% 5. Figure 7: 2x3 Internal Gain |G_w(jw)| & Grid Coupling Gain |1/(1-K*G_u(jw))|
freqs    = logspace(-1, 2, 400);   % 0.1 to 100 Hz
p_list   = [0.1, 0.4, 0.7, 1.0, 1.2];
xg_list  = [0.0, 0.2, 0.4, 0.55, 0.63];
fbw_list = [5, 10, 15, 25, 35];

idx_c = round(linspace(20, 236, 5));
lcols = cmap(idx_c, :);

fig7 = figure('Units', 'inches', 'Position', [0.8, 0.4, 7.16, 4.65], 'Color', 'w');
tl7  = tiledlayout(fig7, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

ax_g = gobjects(2, 3);
for r = 1:2
    for c = 1:3
        ax_g(r, c) = nexttile(tl7); hold(ax_g(r, c), 'on');
    end
end

% (a) Sweep p_chip,3ph
lbl_p = cell(1, numel(p_list));
for i = 1:numel(p_list)
    r = solve_bypass_modal(p_list(i), V_s_nom, R_g_nom, X_g_nom, p, ctrl_nom);
    [gw, gg] = eval_freq_gains(r, freqs);
    semilogx(ax_g(1, 1), freqs, gw, 'Color', lcols(i, :), 'LineWidth', 1.5);
    semilogx(ax_g(2, 1), freqs, gg, 'Color', lcols(i, :), 'LineWidth', 1.5);
    lbl_p{i} = sprintf('%.1f', p_list(i));
end
title(ax_g(1, 1), '(a) Varying $\mathrm{p}_{\mathrm{chip},3\phi}$ (p.u.)', 'Interpreter', 'latex', 'FontSize', 13);
lgd1 = legend(ax_g(2, 1), lbl_p, 'Location', 'northeast', 'Box', 'off', 'FontSize', 10.5);
lgd1.ItemTokenSize = [14, 7];

% (b) Sweep X_g
lbl_xg = cell(1, numel(xg_list));
for i = 1:numel(xg_list)
    xg = xg_list(i);
    r = solve_bypass_modal(p_chip3_nom, V_s_nom, 0.1 * xg, xg, p, ctrl_nom);
    [gw, gg] = eval_freq_gains(r, freqs);
    semilogx(ax_g(1, 2), freqs, gw, 'Color', lcols(i, :), 'LineWidth', 1.5);
    semilogx(ax_g(2, 2), freqs, gg, 'Color', lcols(i, :), 'LineWidth', 1.5);
    lbl_xg{i} = sprintf('%.2f', xg);
end
title(ax_g(1, 2), '(b) Varying $X_g$ (p.u.)', 'Interpreter', 'latex', 'FontSize', 13);
lgd2 = legend(ax_g(2, 2), lbl_xg, 'Location', 'northeast', 'Box', 'off', 'FontSize', 10.5);
lgd2.ItemTokenSize = [14, 7];

% (c) Sweep f_bw,pfc
lbl_fbw = cell(1, numel(fbw_list));
for i = 1:numel(fbw_list)
    bw_i = bw; bw_i.fbw_pfc = fbw_list(i);
    ctrl_i = tune_pi_controllers(p, bw_i);
    r = solve_bypass_modal(p_chip3_nom, V_s_nom, R_g_nom, X_g_nom, p, ctrl_i);
    [gw, gg] = eval_freq_gains(r, freqs);
    semilogx(ax_g(1, 3), freqs, gw, 'Color', lcols(i, :), 'LineWidth', 1.5);
    semilogx(ax_g(2, 3), freqs, gg, 'Color', lcols(i, :), 'LineWidth', 1.5);
    lbl_fbw{i} = sprintf('%d Hz', fbw_list(i));
end
title(ax_g(1, 3), '(c) Varying $f_{\mathrm{bw,pfc}}$ (Hz)', 'Interpreter', 'latex', 'FontSize', 13);
lgd3 = legend(ax_g(1, 3), lbl_fbw, 'Location', 'southwest', 'Box', 'off', 'FontSize', 10.5);
lgd3.ItemTokenSize = [14, 7];

ylims_g = { [0, 1.60], [0, 1.60], [0, 1.60];
            [0.55, 2.30], [0.45, 3.60], [0.70, 1.55] };
for r = 1:2
    for c = 1:3
        ax = ax_g(r, c);
        yline(ax, 1.0, '--', 'Color', [0.45, 0.45, 0.45], 'LineWidth', 0.95, 'HandleVisibility', 'off');
        set(ax, 'XScale', 'log');
        xlim(ax, [0.1, 100]);
        ylim(ax, ylims_g{r, c});
        box(ax, 'on'); grid(ax, 'on');
        ax.GridAlpha = 0.25; ax.GridLineStyle = ':'; ax.TickDir = 'in';
        ax.XTick = [0.1, 1, 10, 100];
        if r == 1
            ax.XTickLabel = [];
        else
            ax.XTickLabel = {'10^{-1}', '10^{0}', '10^{1}', '10^{2}'};
            xlabel(ax, 'Frequency (Hz)');
        end
    end
end
ylabel(ax_g(1, 1), 'Internal Gain $|G_{\mathrm{w}}(\mathrm{j}2\pi f)|$', 'Interpreter', 'latex');
ylabel(ax_g(2, 1), 'Grid Coupling $|1/(1-K G_{\mathrm{u}})|$', 'Interpreter', 'latex');

exportgraphics(fig7, 'Fig7_Bypass_Gain_FreqResp.pdf', 'ContentType', 'vector');
disp('Exported Fig6_Bypass_RootLocus.pdf and Fig7_Bypass_Gain_FreqResp.pdf.');

%% ========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function [gw_mag, ggrid_mag] = eval_freq_gains(res, freqs)
% EVAL_FREQ_GAINS Computes |G_w(j*2*pi*f)| and |1/(1 - K*G_u(j*2*pi*f))|.
    I6 = eye(6);
    nf = numel(freqs);
    gw_mag    = zeros(1, nf);
    ggrid_mag = zeros(1, nf);
    for k = 1:nf
        s  = 1j * 2.0 * pi * freqs(k);
        M  = s * I6 - res.A;
        Gw = res.C * (M \ res.Bw) + res.Dw;
        Gu = res.C * (M \ res.Bu) + res.Du;
        gw_mag(k)    = abs(Gw);
        ggrid_mag(k) = abs(1.0 / (1.0 - res.K * Gu));
    end
end

function res = solve_bypass_modal(p_chip_3ph, V_s, R_g, X_g, p, ctrl)
% SOLVE_BYPASS_MODAL Solves the coupled bypass-mode equilibrium with the
% algebraic grid (V_s, R_g + j*X_g) and forms the 6-state linearized model.
    res.ok  = false;
    p_chip  = p.alpha * p_chip_3ph;
    xi_buck = p_chip / ctrl.ki_v_buck;

    % Coupled PSU + Grid power-flow algebraic equations for [V_g, G_eq]
    opts_fs = optimoptions('fsolve', 'Display', 'off', 'TolFun', 1e-12, 'TolX', 1e-12);
    eq_fun  = @(z) [
        ((z(1)^2 * z(2)) / 3.0) * (1.0 - p.R_pfc * z(2)) - p_chip;
        z(1)^4 + (2.0 * R_g * (z(1)^2 * z(2)) - V_s^2) * z(1)^2 + (R_g^2 + X_g^2) * (z(1)^2 * z(2))^2
    ];
    [z_sol, ~, flag] = fsolve(eq_fun, [0.95; p_chip_3ph], opts_fs);
    if flag <= 0 || z_sol(1) <= 0 || z_sol(2) <= 0, return; end

    Vg0   = z_sol(1);
    Geq0  = z_sol(2);
    pg0   = (Vg0^2) * Geq0;   % i_cv_d = 0 at bypass equilibrium
    denom = Vg0 * (2.0 * Vg0^2 + 2.0 * R_g * pg0 - V_s^2);
    if denom <= 0, return; end

    K = -(R_g * Vg0^2 + (R_g^2 + X_g^2) * pg0) / denom;

    x0 = [
        0.5 * p.C_ups;
        0.5 * p.C_pfc;
        0.5 * p.C_buck;
        0.0;
        Geq0 / ctrl.ki_v_pfc;
        xi_buck
    ];

    eps_fd = 1e-7;
    A  = zeros(6, 6);
    C  = zeros(1, 6);
    I6 = eye(6);
    for j = 1:6
        [dp, pp] = bypass_dae_6(x0 + eps_fd * I6(:, j), Vg0, p_chip_3ph, p, ctrl);
        [dm, pm] = bypass_dae_6(x0 - eps_fd * I6(:, j), Vg0, p_chip_3ph, p, ctrl);
        A(:, j) = (dp - dm) / (2.0 * eps_fd);
        C(1, j) = (pp - pm) / (2.0 * eps_fd);
    end
    [dp, pp] = bypass_dae_6(x0, Vg0 + eps_fd, p_chip_3ph, p, ctrl);
    [dm, pm] = bypass_dae_6(x0, Vg0 - eps_fd, p_chip_3ph, p, ctrl);
    Bu = (dp - dm) / (2.0 * eps_fd);
    Du = (pp - pm) / (2.0 * eps_fd);

    [dp, pp] = bypass_dae_6(x0, Vg0, p_chip_3ph + eps_fd, p, ctrl);
    [dm, pm] = bypass_dae_6(x0, Vg0, p_chip_3ph - eps_fd, p, ctrl);
    Bw = (dp - dm) / (2.0 * eps_fd);
    Dw = (pp - pm) / (2.0 * eps_fd);

    A_cl = A + (K / (1.0 - K * Du)) * (Bu * C);

    [V_r, D_eig] = eig(A_cl);
    lam = diag(D_eig);
    W_l = inv(V_r);
    PF  = abs(V_r .* W_l.');

    res.ok   = true;
    res.Vg0  = Vg0; res.pg0 = pg0; res.K = K;
    res.A    = A;   res.Bu  = Bu;  res.Bw = Bw;
    res.C    = C;   res.Du  = Du;  res.Dw = Dw;
    res.A_cl = A_cl; res.eigs = lam; res.PF = PF;
end

function [dx, p_g] = bypass_dae_6(x, V_g, p_chip_3ph, p, ctrl)
% BYPASS_DAE_6 Active 6-state bypass-mode RMS DAE (VSI & BESS inactive).
% State vector: [E_afe; E_pfc; E_buck; xi_afe; xi_pfc; xi_buck]
    E_afe  = x(1); E_pfc  = x(2); E_buck  = x(3);
    xi_afe = x(4); xi_pfc = x(5); xi_buck = x(6);

    v_dc   = sqrt(max(2.0 * E_afe  / p.C_ups,  1e-8));
    v_pfc  = sqrt(max(2.0 * E_pfc  / p.C_pfc,  1e-8));
    v_buck = sqrt(max(2.0 * E_buck / p.C_buck, 1e-8));

    i_cv_d = ctrl.kp_v_afe  * (1.0 - v_dc)   + ctrl.ki_v_afe  * xi_afe;
    G_eq   = ctrl.kp_v_pfc  * (1.0 - v_pfc)  + ctrl.ki_v_pfc  * xi_pfc;
    i_L    = ctrl.kp_v_buck * (1.0 - v_buck) + ctrl.ki_v_buck * xi_buck;

    p_chip    = p.alpha * p_chip_3ph;
    p_load    = (v_buck^2) * p_chip;
    p_buck_in = v_buck * i_L;
    p_psu     = (V_g^2) * G_eq;
    p_eq      = (p_psu / 3.0) * (1.0 - p.R_pfc * G_eq);
    p_afe     = V_g * i_cv_d - p.R_cv * (i_cv_d^2);
    p_g       = V_g * i_cv_d + p_psu;

    dx = [
        p.w_b * p_afe;
        p.w_b * (p_eq - p_buck_in);
        p.w_b * (p_buck_in - p_load);
        1.0 - v_dc;
        1.0 - v_pfc;
        1.0 - v_buck
    ];
end

function plot_root_locus_panel(ax, param_vals, eigs_mat, cmap, title_str, cb_label, xl, yl, show_ylabel, cb_ticks)
    hold(ax, 'on');
    fill(ax, [0, xl(2), xl(2), 0], [yl(1), yl(1), yl(2), yl(2)], ...
        [0.99, 0.94, 0.94], 'EdgeColor', 'none', 'HandleVisibility', 'off');
    xline(ax, 0, '--', 'Color', [0.75, 0.15, 0.15], 'LineWidth', 1.2);
    yline(ax, 0, ':',  'Color', [0.55, 0.55, 0.55], 'LineWidth', 0.60);

    for zt = [0.2, 0.5]
        ang = acos(zt); r_m = 160;
        plot(ax, [0, -r_m * cos(ang)], [0,  r_m * sin(ang)], ':', 'Color', [0.75, 0.75, 0.75], 'LineWidth', 0.55);
        plot(ax, [0, -r_m * cos(ang)], [0, -r_m * sin(ang)], ':', 'Color', [0.75, 0.75, 0.75], 'LineWidth', 0.55);
    end

    p_min = min(param_vals); p_max = max(param_vals);
    n_c   = size(cmap, 1);
    [n_e, n_p] = size(eigs_mat);
    x_all = nan(n_e * n_p, 1);
    y_all = nan(n_e * n_p, 1);
    c_all = zeros(n_e * n_p, 3);
    ptr = 0;
    for i = 1:n_p
        ev = eigs_mat(:, i);
        if any(isnan(ev)), continue; end
        ci = max(1, min(n_c, round(1 + (n_c - 1) * (param_vals(i) - p_min) / (p_max - p_min))));
        idx_r = ptr + (1:n_e);
        x_all(idx_r)    = real(ev);
        y_all(idx_r)    = imag(ev);
        c_all(idx_r, :) = repmat(cmap(ci, :), n_e, 1);
        ptr = ptr + n_e;
    end
    scatter(ax, x_all(1:ptr), y_all(1:ptr), 18, c_all(1:ptr, :), 'filled');

    scatter(ax, real(eigs_mat(:, 1)),   imag(eigs_mat(:, 1)),   40, 'k', 'o', 'LineWidth', 1.2);
    scatter(ax, real(eigs_mat(:, end)), imag(eigs_mat(:, end)), 44, 'k', 'x', 'LineWidth', 1.3);

    xlim(ax, xl); ylim(ax, yl);
    box(ax, 'on'); grid(ax, 'on');
    ax.GridAlpha = 0.22; ax.GridLineStyle = ':'; ax.TickDir = 'in';
    xlabel(ax, '$\mathrm{Re}(\lambda)\;(\mathrm{s}^{-1})$', 'Interpreter', 'latex');
    if show_ylabel
        ylabel(ax, '$\mathrm{Im}(\lambda)\;(\mathrm{rad/s})$', 'Interpreter', 'latex');
    else
        ax.YTickLabel = [];
    end
    title(ax, title_str, 'Interpreter', 'latex', 'FontSize', 13);

    colormap(ax, cmap);
    caxis(ax, [p_min, p_max]);
    cb = colorbar(ax, 'southoutside');
    cb.Ticks = cb_ticks;
    cb.FontSize = 11.5;
    cb.Label.Interpreter = 'latex';
    cb.Label.String = cb_label;
    cb.Label.FontSize = 12.5;
end

function print_modal_table(res)
    names = {'E_afe','E_pfc','E_buck','xi_afe','xi_pfc','xi_buck'};
    [~, ord] = sort(real(res.eigs), 'descend');
    fprintf('\n============ Bypass-Mode Modal Analysis (V_g=%.4f, p_g=%.4f, K=%.4f) ============\n', ...
        res.Vg0, res.pg0, res.K);
    fprintf('%-22s | %8s | %7s | %s\n', 'Eigenvalue (s^-1)', 'f (Hz)', 'zeta', 'Dominant States (PF)');
    fprintf('----------------------------------------------------------------------------------\n');
    for k = 1:numel(ord)
        idx = ord(k);
        lam = res.eigs(idx);
        f_hz = abs(imag(lam)) / (2 * pi);
        zeta = -real(lam) / abs(lam);
        [~, s_ord] = sort(res.PF(:, idx), 'descend');
        dom_str = sprintf('%s (%.2f), %s (%.2f)', ...
            names{s_ord(1)}, res.PF(s_ord(1), idx), names{s_ord(2)}, res.PF(s_ord(2), idx));
        fprintf('%9.3f %+9.3fj | %8.2f | %7.3f | %s\n', real(lam), imag(lam), f_hz, zeta, dom_str);
    end
    fprintf('==================================================================================\n\n');
end

function p = build_per_unit_params(cfg)
    p.S_b    = cfg.M_ups * cfg.S_ups_MVA;
    p.f_b    = cfg.f_b;
    p.w_b    = 2.0 * pi * cfg.f_b;
    p.alpha  = (cfg.M_psu * cfg.S_psu_MVA) / cfg.S_ups_MVA;
    p.C_ups  = cfg.c_dc_afe_pu;
    p.R_cv   = cfg.r_afe_pu;
    p.C_pfc  = p.alpha * cfg.c_dc_pfc_pu;
    p.R_pfc  = cfg.r_pfc_pu / p.alpha;
    p.C_buck = p.alpha * cfg.c_dc_buck_pu;
    p.c_dc_afe_local  = cfg.c_dc_afe_pu;
    p.c_dc_pfc_local  = cfg.c_dc_pfc_pu;
    p.c_dc_buck_local = cfg.c_dc_buck_pu;
end

function ctrl = tune_pi_controllers(p, bw)
    wb = p.w_b;
    wn_afe = 2.0 * pi * bw.fbw_afe;
    ctrl.kp_v_afe = 2.0 * bw.zt_afe * wn_afe * p.c_dc_afe_local / wb;
    ctrl.ki_v_afe = (wn_afe^2) * p.c_dc_afe_local / wb;

    wn_pfc = 2.0 * pi * bw.fbw_pfc;
    ctrl.kp_v_pfc = p.alpha * (2.0 * bw.zt_pfc * wn_pfc * p.c_dc_pfc_local / wb);
    ctrl.ki_v_pfc = p.alpha * ((wn_pfc^2) * p.c_dc_pfc_local / wb);

    wn_buck = 2.0 * pi * bw.fbw_buck;
    ctrl.kp_v_buck = p.alpha * (2.0 * bw.zt_buck * wn_buck * p.c_dc_buck_local / wb);
    ctrl.ki_v_buck = p.alpha * ((wn_buck^2) * p.c_dc_buck_local / wb);
end

function add_mode_arrow(fig, ax, x_txt, y_txt, x_tail, y_tail, x_tip, y_tip, lbl, col)
% ADD_MODE_ARROW Draws a crisp text label and vector arrow in data coords.
    text(ax, x_txt, y_txt, lbl, 'FontSize', 11.5, 'Color', col, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
    ax_pos = ax.Position;
    xl = ax.XLim; yl = ax.YLim;
    fx = ax_pos(1) + ([x_tail, x_tip] - xl(1)) / diff(xl) * ax_pos(3);
    fy = ax_pos(2) + ([y_tail, y_tip] - yl(1)) / diff(yl) * ax_pos(4);
    annotation(fig, 'arrow', fx, fy, 'Color', col, 'LineWidth', 1.0, ...
        'HeadLength', 6.5, 'HeadWidth', 5.0, 'HeadStyle', 'vback2');
end