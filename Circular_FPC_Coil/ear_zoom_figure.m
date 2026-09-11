function ear_zoom_figure(outPng, outSvg, overrides)
% EAR_ZOOM_FIGURE 单个耳朵的局部放大图，标注三段弧与三个参数。
%   EAR_ZOOM_FIGURE(PNG, SVG) 使用默认配置（4L/2C）生成 0° 耳朵的放大图。
%   EAR_ZOOM_FIGURE(PNG, SVG, OVERRIDES) 用 OVERRIDES 覆盖配置。
%
%   图中标注：内侧弧（主体外径圆重合段）、中间弧（外凸）、最外侧弧（等距外偏）、
%   槽口跨度 mountingSlotSpan、外凸高度 mountingSlotRise、槽到板边距离
%   mountingSlotEdgeClearance，并用虚线画出参数基准（主体外径圆与耳朵径向轴）。
if nargin < 1 || isempty(outPng)
    outPng = 'ear_zoom.png';
end
if nargin < 2 || isempty(outSvg)
    outSvg = 'ear_zoom.svg';
end
if nargin < 3 || isempty(overrides)
    overrides = struct();
end
% The documented helper default is the 4-layer/2-coil variant, while the
% public generator default remains 4/4. Preserve explicit caller overrides,
% but fill only the omitted layer fields so the title and geometry always
% describe the same variant.
if ~isfield(overrides, 'boardLayerCount')
    overrides.boardLayerCount = 4;
end
if ~isfield(overrides, 'coilLayerCount')
    overrides.coilLayerCount = 2;
end
result = circular_fpc_analyze(overrides);
lr = result.layoutRegions;
cfg = result.config;
angleDeg = lr.mountingAnglesDeg(1);
theta = deg2rad(angleDeg);
u = [cos(theta), sin(theta)];
t = [-sin(theta), cos(theta)];

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1100 950]);
ax = axes(fig);
hold(ax, 'on');
axis(ax, 'equal');
grid(ax, 'on');
box(ax, 'on');

boardColor = [1.00 0.82 0.05];
slotColor = [0.55 0.80 0.86];

% 1) 板框实体与挖槽（与正式预览相同的配色）
for j = 1:numel(result.boardLoops)
    loop = result.boardLoops(j);
    xy = loop.xy;
    if loop.isHole
        patch(ax, xy(:, 1), xy(:, 2), [1 1 1], 'FaceAlpha', 1.0, 'EdgeColor', 'none');
        patch(ax, xy(:, 1), xy(:, 2), slotColor, 'FaceAlpha', 0.32, ...
            'EdgeColor', 'k', 'LineWidth', 1.0);
    else
        patch(ax, xy(:, 1), xy(:, 2), boardColor, 'FaceAlpha', 1.0, 'EdgeColor', 'none');
        plot(ax, xy(:, 1), xy(:, 2), 'Color', [0.55 0.10 0.75], 'LineWidth', 1.3);
    end
end

% 2) 三段弧叠加。每段弧的角范围必须相对各自的圆心计算：内侧弧以板中心为
%    基准（±halfSpan），中间弧与最外侧弧以耳朵圆心 midCenterR 为基准。
th = linspace(0, 2 * pi, 721);
plot(ax, lr.mountingSlotInnerArcRadius * cos(th), lr.mountingSlotInnerArcRadius * sin(th), ...
    ':', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.9);
P1 = lr.mountingSlotEndpoints(1, :);
P2 = lr.mountingSlotEndpoints(2, :);
J1 = lr.mountingEarRootPoints(1, :);
J2 = lr.mountingEarRootPoints(2, :);
halfInner = lr.mountingSlotHalfSpanDeg;
angInner = linspace(-halfInner, halfInner, 200);
plot(ax, lr.mountingSlotInnerArcRadius * cosd(angInner), ...
    lr.mountingSlotInnerArcRadius * sind(angInner), '-', 'Color', [0.00 0.35 0.85], 'LineWidth', 3.0);
midC = lr.mountingSlotMiddleArcCenterRadius * u;
% 端点相对耳朵圆心的角（局部 u/t 坐标系），中间弧与最外侧弧共用同一角域。
thetaMid = atan2d(dot(P1 - midC, t), dot(P1 - midC, u));
angMid = linspace(-abs(thetaMid), abs(thetaMid), 240);
midXY = midC + lr.mountingSlotMiddleArcRadius * (cosd(angMid).' * u + sind(angMid).' * t);
plot(ax, midXY(:, 1), midXY(:, 2), '-', 'Color', [0.00 0.60 0.00], 'LineWidth', 3.0);
thetaOuter = atan2d(dot(J1 - midC, t), dot(J1 - midC, u));
angOuter = linspace(-abs(thetaOuter), abs(thetaOuter), 240);
outerEarXY = midC + lr.mountingSlotOuterArcRadius * (cosd(angOuter).' * u + sind(angOuter).' * t);
plot(ax, outerEarXY(:, 1), outerEarXY(:, 2), '-', 'Color', [0.85 0.10 0.10], 'LineWidth', 3.0);

% 3) 端点与根部标记：证明内侧弧与中间弧共享端点（P± 严格在主体圆上），
%    以及耳朵外弧与主体圆的连接点 J±。
% P1/P2/J1/J2 均为 1x2 单点（P+ / P- / J+ / J-）。
plot(ax, P1(1), P1(2), 'o', 'MarkerSize', 8, ...
    'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k', 'LineWidth', 1.6);
plot(ax, P2(1), P2(2), 's', 'MarkerSize', 8, ...
    'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k', 'LineWidth', 1.6);
plot(ax, J1(1), J1(2), 'd', 'MarkerSize', 7, ...
    'MarkerFaceColor', [0.85 0.10 0.10], 'MarkerEdgeColor', 'k');
plot(ax, J2(1), J2(2), 'd', 'MarkerSize', 7, ...
    'MarkerFaceColor', [0.85 0.10 0.10], 'MarkerEdgeColor', 'k');
text(ax, P1(1) - 0.32, P1(2) + 0.34, 'P_+  (shared endpoint, on main circle)', ...
    'FontSize', 9, 'Color', 'k', 'HorizontalAlignment', 'right', 'BackgroundColor', 'w', 'Margin', 1);
text(ax, P2(1) - 0.32, P2(2) - 0.34, 'P_-  (shared endpoint, on main circle)', ...
    'FontSize', 9, 'Color', 'k', 'HorizontalAlignment', 'right', 'BackgroundColor', 'w', 'Margin', 1);
text(ax, J1(1) + 0.45, J1(2) + 0.38, 'J_\pm  (ear root on main circle)', ...
    'FontSize', 9, 'Color', [0.70 0.05 0.05], 'BackgroundColor', 'w', 'Margin', 1);

% 4) 参数标注。跨度尺寸线画在端点外侧、标签再向外偏一格，与外凸高度标注错开。
drawDimLine(ax, P1, P2, u, -0.62, ...
    sprintf('mountingSlotSpan = %.2f mm (chord)', lr.mountingSlotSpan), [0.10 0.10 0.10], ...
    -1.05);
C = lr.mountingSlotInnerArcRadius * u;
Q = lr.mountingSlotApexRadius * u;
plot(ax, [C(1) Q(1)], [C(2) Q(2)], '-', 'Color', [0.90 0.50 0.00], 'LineWidth', 2.2);
plot(ax, C(1), C(2), 'o', 'MarkerSize', 5, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', [0.90 0.50 0.00]);
plot(ax, Q(1), Q(2), 'o', 'MarkerSize', 5, 'MarkerFaceColor', [0.90 0.50 0.00], 'MarkerEdgeColor', 'k');
text(ax, C(1) - 0.20, 0.30 * lr.mountingSlotRise + 0.72, ...
    sprintf('mountingSlotRise = %.2f mm', lr.mountingSlotRise), ...
    'Color', [0.75 0.40 0.00], 'FontWeight', 'bold', 'FontSize', 10, ...
    'HorizontalAlignment', 'right', 'BackgroundColor', 'w', 'Margin', 1);
E = lr.mountingEarApexRadius * u;
plot(ax, [Q(1) E(1)], [Q(2) E(2)], '-', 'Color', [0.55 0.10 0.75], 'LineWidth', 2.2);
text(ax, E(1) + 0.30, E(2) - 0.55, ...
    sprintf('mountingSlotEdgeClearance = %.2f mm', lr.mountingSlotEdgeClearance), ...
    'Color', [0.45 0.05 0.65], 'FontWeight', 'bold', 'FontSize', 10, ...
    'HorizontalAlignment', 'left', 'BackgroundColor', 'w', 'Margin', 1);

% 4) 三段弧图例
plot(ax, nan, nan, '-', 'Color', [0.00 0.35 0.85], 'LineWidth', 3.0);
plot(ax, nan, nan, '-', 'Color', [0.00 0.60 0.00], 'LineWidth', 3.0);
plot(ax, nan, nan, '-', 'Color', [0.85 0.10 0.10], 'LineWidth', 3.0);
legend(ax, {sprintf('inner arc = main body circle (r = %.3f mm)', lr.mountingSlotInnerArcRadius), ...
    sprintf('middle arc (R = %.3f mm, centre r = %.3f mm)', lr.mountingSlotMiddleArcRadius, ...
    lr.mountingSlotMiddleArcCenterRadius), ...
    sprintf('outer arc = middle arc + %.2f mm (R = %.3f mm)', lr.mountingSlotEdgeClearance, lr.mountingSlotOuterArcRadius)}, ...
    'Location', 'northwest', 'FontSize', 9);

viewR = lr.mountingEarApexRadius;
xlim(ax, [lr.mountingSlotInnerArcRadius - 3.9, viewR + 4.4]);
ylim(ax, [-viewR * 0.62, viewR * 0.62]);
title(ax, sprintf(['Mounting ear at %g deg: three-arc definition ' ...
    '(%dL/%dC, main circle d = %.3f mm)'], angleDeg, ...
    result.boardLayerCount, result.coilLayerCount, ...
    2 * lr.mountingSlotInnerArcRadius), ...
    'FontSize', 11);
xlabel(ax, 'X [mm]');
ylabel(ax, 'Y [mm]');

exportgraphics(fig, outPng, 'Resolution', 190);
exportgraphics(fig, outSvg, 'ContentType', 'vector');
close(fig);
fprintf('wrote %s and %s\n', outPng, outSvg);
end

function drawDimLine(ax, p1, p2, lateral, offset, label, color, labelOffset)
% 在 p1、p2 之间画带双向箭头的尺寸线；lateral 给偏移方向（正负号决定内外侧），
% offset 给尺寸线偏移量，labelOffset 给标签相对尺寸线的额外偏移（默认 0）。
% 尺寸线位于连线外侧 offset 处，两端用细引线接到被测点。
mid = (p1 + p2) / 2;
a1 = p1 + offset * lateral;
a2 = p2 + offset * lateral;
plot(ax, [a1(1) a2(1)], [a1(2) a2(2)], '-', 'Color', color, 'LineWidth', 1.2);
plot(ax, [p1(1) a1(1)], [p1(2) a1(2)], ':', 'Color', color, 'LineWidth', 0.9);
plot(ax, [p2(1) a2(1)], [p2(2) a2(2)], ':', 'Color', color, 'LineWidth', 0.9);
arrow(ax, a1, a2, color);
arrow(ax, a2, a1, color);
if nargin < 8
    labelOffset = 0;
end
text(ax, mid(1) + (offset + labelOffset) * lateral(1), ...
    mid(2) + (offset + labelOffset) * lateral(2), label, ...
    'Color', color, 'FontWeight', 'bold', 'FontSize', 10, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', 'w', 'Margin', 2);
end

function arrow(ax, from, to, color)
% 在 to 端画一个指向 to 的小箭头。
d = (to - from) / max(norm(to - from), eps);
n = [-d(2), d(1)];
L = 0.22;
plot(ax, [to(1), to(1) - L * d(1) + 0.5 * L * n(1)], ...
    [to(2), to(2) - L * d(2) + 0.5 * L * n(2)], '-', 'Color', color, 'LineWidth', 1.2);
plot(ax, [to(1), to(1) - L * d(1) - 0.5 * L * n(1)], ...
    [to(2), to(2) - L * d(2) - 0.5 * L * n(2)], '-', 'Color', color, 'LineWidth', 1.2);
end
