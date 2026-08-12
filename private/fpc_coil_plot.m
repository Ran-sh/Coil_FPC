function fig = fpc_coil_plot(result)
%FPC_COIL_PLOT Private figure viewer for the FPC runtime.
%   FIG = FPC_COIL_PLOT(RESULT) 是 private/ 目录内的内部实现，由
%   fpc_coil_main 在 cfg.enableFigure 为 true（默认）且运行于 MATLAB 桌面
%   环境时自动调用，不作为公共 API。请勿从根目录之外直接调用本函数；
%   MATLAB 的 private 可见性规则也禁止在 private/ 的父目录之外调用。
%
%   根据 fpc_coil_main 返回的 RESULT 结构体弹出 layerCount+1 个图像窗口：
%   1 个全部层叠放总览窗口 + 每层各 1 个独立窗口，与 previews/ 目录中
%   "总览一张 + 每层一张"的 SVG 输出一致。FIG 为所有窗口的 figure 句柄
%   数组（总览在前，其后按层序排列）。
%
%   总览窗口：板框、全部层铜线路径、焊盘（PAD_A/PAD_B）与过孔（V12…VOUT），
%   并附 L1…L4 图例。
%   每层窗口：板框、该层铜线路径，以及与该层相连的过孔；焊盘（PAD_A/PAD_B）
%   仅出现在 L1 窗口（与 SVG 分层预览一致）。
%
%   图像窗口弹出后可直接使用窗口菜单 File > Save As（或工具栏保存按钮）
%   另存为 PNG、JPG、SVG、EMF、PDF 等任意 MATLAB 支持的格式。

narginchk(1, 1);
validateattributes(result, {'struct'}, {'scalar'}, mfilename, 'result', 1);

requiredFields = {'layerCount', 'layers', 'vias', 'pads', 'outputFolder'};
missing = requiredFields(~isfield(result, requiredFields));
if ~isempty(missing)
    error('FPC_Coil:PlotInvalidResult', ...
        'result 缺少字段：%s。请传入 fpc_coil_main 的返回值。', ...
        strjoin(missing, ', '));
end

layerCount = result.layerCount;
[~, designName] = fileparts(result.outputFolder);
colors = layerColors(layerCount);
fig = gobjects(0, 1);

% 1) 总览窗口：全部层叠放
fig(end + 1) = newFigure(sprintf('FPC Coil - %s - Overview', designName), 0);
layerHandles = plotBoardAndCopper(result, [], colors);
plotPads(result.pads, true);
plotVias(result.vias, true);
title(sprintf('All %d layers (stacked view)', layerCount), 'FontWeight', 'bold');
legendEntries = arrayfun(@(k) sprintf('L%d', k), (1:layerCount)', ...
    'UniformOutput', false);
legend(layerHandles, legendEntries, 'Location', 'eastoutside', 'FontSize', 8);

% 2) 每层独立窗口（与 SVG 分层预览一致：焊盘仅 L1，过孔仅显示相连层）
for k = 1:layerCount
    role = layerRole(k, layerCount);
    fig(end + 1) = newFigure( ...
        sprintf('FPC Coil - %s - Layer %d (%s)', designName, k, role), k);
    plotBoardAndCopper(result, k, colors);
    if k == 1
        plotPads(result.pads, false);
    end
    plotVias(viasOnLayer(result.vias, k), false);
    title(sprintf('Layer %d (%s)', k, role), 'FontWeight', 'bold');
end

end

%% =========================================================
% 局部函数
%% =========================================================

function colors = layerColors(layerCount)
% 每层一种颜色，最多 8 层，颜色取自 lines 色图保证可区分。
colors = lines(max(layerCount, 8));
colors = colors(1:layerCount, :);
end

function fig = newFigure(figName, offsetIndex)
% 复用同名窗口（避免重复运行堆积多个窗口），并按序号轻微错开位置，
% 防止多个窗口完全重叠。
oldFig = findobj('Type', 'figure', 'Name', figName);
if ~isempty(oldFig)
    close(oldFig(1));
end
step = 0.02 * mod(offsetIndex, 8);
fig = figure('Name', figName, 'NumberTitle', 'off', 'Color', 'w', ...
    'Units', 'normalized', 'Position', ...
    [0.06 + step, 0.05 + step, 0.6, 0.8]);
end

function role = layerRole(k, layerCount)
% 与 SVG 预览文件名一致的角色后缀：top / innerN / bottom。
if k == 1
    role = 'top';
elseif k == layerCount
    role = 'bottom';
else
    role = sprintf('inner%d', k - 1);
end
end

function sub = viasOnLayer(vias, k)
% 只保留与该层相连的过孔；旧 result 无 connectedLayers 字段时全部返回。
if isempty(vias) || ~isfield(vias, 'connectedLayers')
    sub = vias;
    return;
end
sub = vias(arrayfun(@(v) any(v.connectedLayers == k), vias));
end

function layerHandles = plotBoardAndCopper(result, layerIndex, colors)
% 绘制板框；layerIndex 为空时绘制全部层并返回各层代表线句柄（供图例使用），
% 否则只绘制指定层。
ax = gca;
hold(ax, 'on');

% 板框（闭合折线）
if isfield(result, 'boardXY') && ~isempty(result.boardXY)
    bx = result.boardXY(:, 1);
    by = result.boardXY(:, 2);
    if norm([bx(1) by(1)] - [bx(end) by(end)]) > 1e-9
        bx(end + 1) = bx(1);
        by(end + 1) = by(1);
    end
    plot(ax, bx, by, 'Color', [0.2 0.2 0.2], 'LineWidth', 1.2);
end

% 铜线路径
if isempty(layerIndex)
    layerHandles = gobjects(numel(result.layers), 1);
    for k = 1:numel(result.layers)
        h = plotLayerPaths(ax, result.layers(k).paths, colors(k, :));
        if ~isempty(h)
            layerHandles(k) = h(1);
        end
    end
else
    layerHandles = gobjects(0, 1);
    plotLayerPaths(ax, result.layers(layerIndex).paths, colors(layerIndex, :));
end

axis(ax, 'equal');
grid(ax, 'on');
ax.XAxisLocation = 'origin';
ax.YAxisLocation = 'origin';
xlabel(ax, 'mm');
ylabel(ax, 'mm');
end

function hLines = plotLayerPaths(ax, paths, color)
hLines = gobjects(0, 1);
for p = 1:numel(paths)
    xy = paths{p};
    if isempty(xy) || size(xy, 2) < 2
        continue;
    end
    h = plot(ax, xy(:, 1), xy(:, 2), 'Color', color, 'LineWidth', 0.5);
    hLines(end + 1) = h; %#ok<AGROW>
end
end

function plotPads(pads, withLabel)
ax = gca;
defaultDiameter = 1.5; % mm，兼容无 diameter 字段的旧 result
for k = 1:numel(pads)
    xy = pads(k).xy(:).';   % 归一化为 1×2 行向量
    if isfield(pads, 'diameter')
        r = pads(k).diameter / 2;
    else
        r = defaultDiameter / 2;
    end
    drawCircle(ax, xy(1), xy(2), r, {'Color', 'k', 'LineWidth', 1.2});
    if withLabel
        text(ax, xy(1) + r * 0.7, xy(2) + r * 0.7, pads(k).name, ...
            'FontSize', 8, 'FontWeight', 'bold');
    end
end
end

function plotVias(vias, withLabel)
ax = gca;
for k = 1:numel(vias)
    xy = vias(k).xy;
    padR = vias(k).padDiameter / 2;
    drillR = vias(k).drillDiameter / 2;
    % 焊盘外圈（实线）
    drawCircle(ax, xy(1), xy(2), padR, {'Color', 'k', 'LineWidth', 1.0});
    % 钻孔内圈（虚线）
    drawCircle(ax, xy(1), xy(2), drillR, {'Color', 'k', 'LineWidth', 0.8, ...
        'LineStyle', '--'});
    if withLabel
        text(ax, xy(1) + padR * 0.7, xy(2) + padR * 0.7, vias(k).name, ...
            'FontSize', 7);
    end
end
end

function drawCircle(ax, cx, cy, r, styleArgs)
theta = linspace(0, 2 * pi, 120);
plot(ax, cx + r * cos(theta), cy + r * sin(theta), styleArgs{:});
end
