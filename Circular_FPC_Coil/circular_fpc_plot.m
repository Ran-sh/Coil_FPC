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
colors = lines(max(nL, 1));

% --- 总览：所有层叠放 ---
subplot(rows, cols, 1);
hold on;
axis equal;
grid on;
box on;
plotBoardLoops(result, 'k');
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
    plotBoardLoops(result, [0.55 0.55 0.55]);
    lp = result.layerPaths(li);
    if ~isempty(lp.coilXY)
        plot(lp.coilXY(:, 1), lp.coilXY(:, 2), 'Color', colors(li, :), 'LineWidth', 1.0);
    end
    paths = lp.connectionPaths;
    for k = 1:numel(paths)
        if ~isempty(paths{k})
            plot(paths{k}(:, 1), paths{k}(:, 2), 'Color', colors(li, :), ...
                'LineWidth', 1.0, 'LineStyle', '--');
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

% ----------------------------------------------------------------------
function plotBoardLoops(result, color)
for j = 1:numel(result.boardLoops)
    xy = result.boardLoops(j).xy;
    plot(xy(:, 1), xy(:, 2), 'Color', color, 'LineWidth', 1.0);
end
end

% ----------------------------------------------------------------------
function plotPads(result)
th = linspace(0, 2 * pi, 65);
for k = 1:numel(result.pads)
    xy = result.pads(k).xy;
    r = result.pads(k).diameter / 2;
    plot(xy(1) + r * cos(th), xy(2) + r * sin(th), 'k-', 'LineWidth', 1.2);
    text(xy(1), xy(2) + r + 0.25, result.pads(k).name, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
end
end

% ----------------------------------------------------------------------
function plotVias(result, layerNumber)
th = linspace(0, 2 * pi, 65);
for k = 1:numel(result.vias)
    v = result.vias(k);
    if ~isempty(layerNumber) && ...
            ~ismember(layerNumber, [v.fromLayer, v.toLayer])
        continue;
    end
    xy = v.xy;
    rPad = v.padDiameter / 2;
    rDrill = v.drillDiameter / 2;
    plot(xy(1) + rPad * cos(th), xy(2) + rPad * sin(th), 'Color', [0.2 0.2 0.2], ...
        'LineWidth', 0.8);
    plot(xy(1) + rDrill * cos(th), xy(2) + rDrill * sin(th), 'Color', [0.6 0.6 0.6], ...
        'LineWidth', 0.8, 'LineStyle', '--');
    text(xy(1), xy(2) + rPad + 0.25, v.name, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7);
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
