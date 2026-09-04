function circular_fpc_plot(result)
%CIRCULAR_FPC_PLOT Show the generated FPC coil in a MATLAB figure window.
%   CIRCULAR_FPC_PLOT(RESULT) draws an overview with all layers overlaid plus
%   one subplot per physical layer (board outline, coil, connection paths,
%   pads on layer 1, and vias connected to that layer).
%
%   The window can be saved manually via File > Save As (PNG/SVG/PDF/...).
%   It is shown automatically after circular_fpc_main when
%   cfg.enableFigure is true and a MATLAB desktop is available.

if nargin < 1
    error('CircularFPC:Plot', 'circular_fpc_plot requires a result struct from circular_fpc_engine.');
end

% 复用同名窗口，避免重复调用时堆积多个窗口。
fig = findobj('Type', 'figure', 'Name', 'Circular FPC Coil');
if isempty(fig)
    fig = figure('Name', 'Circular FPC Coil', 'NumberTitle', 'off', ...
        'Color', 'w', 'Position', [80 80 960 720]);
else
    figure(fig(1));
    clf(fig(1));
end

nL = numel(result.layerPaths);
nSub = nL + 1; % 总览 + 每层
cols = min(3, nSub);
rows = ceil(nSub / cols);
baseColors = [0.90 0.10 0.10; ... % top: red
              0.95 0.45 0.05; ... % inner1: orange
              0.10 0.60 0.20; ... % inner2: green
              0.10 0.30 0.90];    % bottom: blue
colors = baseColors(mod((0:max(nL, 1) - 1), size(baseColors, 1)) + 1, :);

% --- 总览：所有层叠放 ---
subplot(rows, cols, 1);
hold on;
axis equal;
grid on;
box on;
plotBoardOutline(result);
for li = 1:nL
    lp = result.layerPaths(li);
    if ~isempty(lp.coilXY)
        plot(lp.coilXY(:, 1), lp.coilXY(:, 2), 'Color', colors(li, :), 'LineWidth', 1.0);
    end
end
plotPads(result);
plotVias(result, []);
title('Overview (all layers)', 'FontSize', 10);
xlabel('mm');
ylabel('mm');

% --- 每层单独视图 ---
for li = 1:nL
    subplot(rows, cols, li + 1);
    hold on;
    axis equal;
    grid on;
    box on;
    plotBoardOutline(result);
    lp = result.layerPaths(li);
    if ~isempty(lp.coilXY)
        plot(lp.coilXY(:, 1), lp.coilXY(:, 2), 'Color', colors(li, :), 'LineWidth', 1.0);
    end
    paths = lp.connectionPaths;
    for k = 1:numel(paths)
        if ~isempty(paths{k})
            plot(paths{k}(:, 1), paths{k}(:, 2), 'Color', colors(li, :), ...
                'LineWidth', 1.0, 'LineStyle', '-');
        end
    end
    if li == 1
        plotPads(result);
    end
    plotVias(result, li);
    role = layerRole(result, li);
    title(sprintf('Layer %d (%s)', li, role), 'FontSize', 10);
end

drawnow;

end

function plotBoardOutline(result)
% 板框实体为极淡黄色；槽为稍深的透明玻璃色填充且黑色描边；
% 外圆板框单独使用紫色描边。
slotGlassColor = [0.55 0.80 0.86];
boardYellow = [1.00 0.82 0.05];
boardPurple = [0.55 0.10 0.75];
for j = 1:numel(result.boardLoops)
    loop = result.boardLoops(j);
    xy = loop.xy;
    if loop.isHole
        patch(xy(:, 1), xy(:, 2), [1 1 1], ...
            'FaceAlpha', 1.0, 'EdgeColor', 'none');
        patch(xy(:, 1), xy(:, 2), slotGlassColor, ...
            'FaceAlpha', 0.32, 'EdgeColor', 'k', 'LineWidth', 1.0);
    else
        patch(xy(:, 1), xy(:, 2), boardYellow, ...
            'FaceAlpha', 1.0, 'EdgeColor', 'none');
        plot(xy(:, 1), xy(:, 2), 'Color', boardPurple, 'LineWidth', 1.3);
    end
end
end

% ----------------------------------------------------------------------
function plotPads(result)
th = linspace(0, 2 * pi, 65);
for k = 1:numel(result.pads)
    xy = result.pads(k).xy;
    r = result.pads(k).diameter / 2;
    patch(xy(1) + r * cos(th), xy(2) + r * sin(th), [0.90 0.10 0.10], ...
        'FaceColor', [0.90 0.10 0.10], 'EdgeColor', 'k', 'LineWidth', 1.2);
    text(xy(1), xy(2) + r + 0.25, result.pads(k).name, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', 8, 'Color', 'k');
end
end

% ----------------------------------------------------------------------
function plotVias(result, layerNumber)
% 所有过孔都是同规格贯通过孔：每个物理层均显示 0.55 mm 深灰焊环和
% 0.31 mm 钻孔，不按连接层改变大小或颜色。
 %#ok<INUSD>
th = linspace(0, 2 * pi, 65);
for k = 1:numel(result.vias)
    v = result.vias(k);
    xy = v.xy;
    rDrill = v.drillDiameter / 2;
    rOuter = v.padDiameter / 2;
    outerColor = [0.28 0.28 0.28];
    patch(xy(1) + rOuter * cos(th), xy(2) + rOuter * sin(th), outerColor, ...
        'FaceColor', outerColor, ...
        'EdgeColor', 'k', 'LineWidth', 1.0, 'LineStyle', '-');
    patch(xy(1) + rDrill * cos(th), xy(2) + rDrill * sin(th), [1 1 1], ...
        'FaceColor', [1 1 1], 'EdgeColor', 'k', 'LineWidth', 0.9, 'LineStyle', '-');
    text(xy(1), xy(2) + rOuter + 0.25, v.name, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', 7, 'Color', 'k');
end
end

% ----------------------------------------------------------------------
function role = layerRole(result, li)
if li == 1
    role = 'top';
elseif li == numel(result.layerPaths)
    role = 'bottom';
else
    role = sprintf('inner%d', li - 1);
end
end
