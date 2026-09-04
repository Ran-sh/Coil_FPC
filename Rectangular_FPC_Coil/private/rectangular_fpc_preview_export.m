function varargout = rectangular_fpc_preview_export(operation, varargin)
%RECTANGULAR_FPC_PREVIEW_EXPORT Write and describe vector SVG previews.

switch operation
    case 'write'
        writePreviews(varargin{:});
    case 'expected_names'
        varargout{1} = expectedPreviewNames(varargin{:});
    otherwise
        error('RectangularFPC:UnknownExportOperation', ...
            'Unknown preview export operation: %s', operation);
end

end

%% =========================================================
function names = expectedPreviewNames(cfg)

if ~cfg.enablePreview
    names = strings(0, 1);
    return;
end
names = strings(cfg.layerCount + 3, 1);
names(1:3) = ["01_preview_full.svg"; ...
    "02_preview_right_tab.svg"; "03_preview_pads_vias.svg"];
for layerIndex = 1:cfg.layerCount
    names(layerIndex + 3) = sprintf( ...
        '%02d_preview_layer_L%d_%s.svg', layerIndex + 3, ...
        layerIndex, layerRole(cfg, layerIndex));
end

end

%% =========================================================
function writePreviews(cfg, boardXY, layerPaths, padA, padB, vias, previewFolder)
% 生成两张隐藏图窗的纯矢量 SVG 预览并立即关闭图窗；
% 导出异常时也必须关闭对应图窗后再抛出。

if ~exist(previewFolder, 'dir')
    mkdir(previewFolder);
end

priorFigures = double(findall(0, 'Type', 'figure'));

try
    fig = plotFullPreview(cfg, boardXY, layerPaths, padA, padB, vias);
    exportFigureAndClose(fig, fullfile(previewFolder, '01_preview_full.svg'));

    fig = plotRightTabPreview(cfg, boardXY, layerPaths, padA, padB, vias);
    exportFigureAndClose(fig, fullfile(previewFolder, '02_preview_right_tab.svg'));

    fig = plotPadsViasPreview(cfg, boardXY, padA, padB, vias);
    exportFigureAndClose(fig, fullfile(previewFolder, '03_preview_pads_vias.svg'));

    for k = 1:numel(layerPaths)
        fig = plotLayerPreview(cfg, boardXY, layerPaths, padA, padB, vias, k);
        fileName = sprintf('%02d_preview_layer_L%d_%s.svg', k + 3, k, layerRole(cfg, k));
        exportFigureAndClose(fig, fullfile(previewFolder, fileName));
    end
catch ME
    closeCreatedFigures(priorFigures);
    rethrow(ME);
end

end

%% =========================================================
function fig = plotFullPreview( ...
    cfg, boardXY, layerPaths, padA, padB, vias)

titleText = sprintf( ...
    '%d-layer FPC coil | body %.0fx%.0f mm | tab %.0fx%.0f mm | %d turns/layer | %.2f/%.2f mm', ...
    cfg.layerCount, cfg.plateLength, cfg.plateWidth, ...
    cfg.tabLength, cfg.tabWidth, cfg.turnsPerLayer, ...
    cfg.traceWidth, cfg.traceSpacing);

fig = plotLayout( ...
    cfg, boardXY, layerPaths, padA, padB, vias, titleText, true, []);

end

%% =========================================================
function fig = plotRightTabPreview( ...
    cfg, boardXY, layerPaths, padA, padB, vias)

titleText = sprintf( ...
    'Right tab detail | body %.0f mm + tab %.0f mm | %d turns/layer', ...
    cfg.plateLength, cfg.tabLength, cfg.turnsPerLayer);

fig = plotLayout( ...
    cfg, boardXY, layerPaths, padA, padB, vias, titleText, true, ...
    [cfg.plateLength/2 - 8, cfg.plateLength/2 + cfg.tabLength + 2]);

ylim([-cfg.plateWidth/2 - 1, cfg.plateWidth/2 + 1]);

end

%% =========================================================
function fig = plotLayout( ...
    cfg, boardXY, layerPaths, padA, padB, vias, titleText, addLegend, xRange)

fig = figure('Name', titleText, 'Color', 'w', 'Visible', 'off');

hold on;
axis equal;
grid on;
box on;

plot([boardXY(:,1); boardXY(1,1)], ...
     [boardXY(:,2); boardXY(1,2)], ...
     '--', 'LineWidth', 1.0, 'DisplayName', 'Board outline');

for k = 1:numel(layerPaths)
    for pathIndex = 1:numel(layerPaths{k})
        path = layerPaths{k}{pathIndex};
        if pathIndex == 1
            displayName = sprintf('L%d coil', k);
        else
            displayName = sprintf('L%d output return', k);
        end
        plot(path(:,1), path(:,2), ...
            'LineWidth', 0.8, 'DisplayName', displayName);
    end
end

plot(padA(1), padA(2), 'o', ...
    'MarkerSize', 7, 'LineWidth', 1.2, 'DisplayName', 'PAD A');
text(padA(1), padA(2) + 0.6, 'PAD_A', ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', [0.85 0.33 0.10], 'Clipping', 'on');

for k = 1:numel(vias)
    plot(vias(k).xy(1), vias(k).xy(2), 's', ...
        'MarkerSize', 6, 'LineWidth', 1.0, ...
        'DisplayName', vias(k).name);
    text(vias(k).xy(1), vias(k).xy(2) + 0.45, vias(k).name, ...
        'FontSize', 7, 'HorizontalAlignment', 'center', ...
        'Color', [0.2 0.35 0.6], 'Clipping', 'on');
end

plot(padB(1), padB(2), 'o', ...
    'MarkerSize', 7, 'LineWidth', 1.2, 'DisplayName', 'PAD B');
text(padB(1), padB(2) - 0.8, 'PAD_B', ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', [0.85 0.33 0.10], 'Clipping', 'on');

% 主体左下角原点标记（内部坐标系下的主体左下角，对应用户坐标 (0,0)）
originXY = [-cfg.plateLength/2, -cfg.plateWidth/2];
plot(originXY(1), originXY(2), 'k+', 'MarkerSize', 9, 'LineWidth', 1.2);
text(originXY(1), originXY(2) - 1.1, 'body lower-left (0,0)', ...
    'FontSize', 7, 'HorizontalAlignment', 'left', 'Color', 'k', 'Clipping', 'on');

xlabel('X / mm');
ylabel('Y / mm');
title(titleText);

if ~isempty(xRange)
    xlim(xRange);
end

if addLegend
    legend('Location', 'bestoutside');
end

end

%% =========================================================
function fig = plotPadsViasPreview(cfg, boardXY, padA, padB, vias)
% Right-side placement view of external pads and vias, to scale.
% Coil paths are intentionally not drawn in this preview.
fig = figure('Name', 'Pad and via placement', 'Color', 'w', 'Visible', 'off');

try
hold on;
axis equal;
grid on;
box on;

drawBoardOutline(boardXY);

drawCircle(padA(1), padA(2), cfg.padDiameter, [0.85 0.33 0.10], 1.2, 'PAD_A');
text(padA(1), padA(2) + cfg.padDiameter/2 + 0.45, 'PAD_A', ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', [0.85 0.33 0.10], ...
    'Clipping', 'on', 'Interpreter', 'none');

drawCircle(padB(1), padB(2), cfg.padDiameter, [0.85 0.33 0.10], 1.2, 'PAD_B');
text(padB(1), padB(2) - cfg.padDiameter/2 - 0.45, 'PAD_B', ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', [0.85 0.33 0.10], ...
    'Clipping', 'on', 'Interpreter', 'none');

viaColors = lines(numel(vias));
annotationX = cfg.plateLength/2 + cfg.tabLength - 4;
annotationY = linspace(cfg.plateWidth/2 - 2, -cfg.plateWidth/2 + 1.5, numel(vias));

for v = 1:numel(vias)
    via = vias(v);
    drawCircle(via.xy(1), via.xy(2), via.padDiameter, viaColors(v, :), 1.2, via.name);
    drawCircle(via.xy(1), via.xy(2), via.drillDiameter, 'k', 0.8, sprintf('%s drill', via.name));
    if via.antipadDiameter > 0
        drawCircle(via.xy(1), via.xy(2), via.antipadDiameter, ...
            [0.6 0.2 0.2], 1.0, sprintf('%s antipad', via.name), '--');
    end
    labelText = sprintf('%s (L%d-L%d)', via.name, ...
        via.connectedLayers(1), via.connectedLayers(2));
    if via.antipadDiameter > 0 && ...
            ~isempty(setdiff(1:cfg.layerCount, via.connectedLayers))
        labelText = sprintf('%s | %s antipad', labelText, via.name);
    end
    text(annotationX, annotationY(v), labelText, ...
        'FontSize', 7, 'HorizontalAlignment', 'right', 'Interpreter', 'none', ...
        'Color', viaColors(v, :), 'Clipping', 'on');
end

xlabel('X / mm');
ylabel('Y / mm');
title('Pad / via placement (right tab)');
xlim([cfg.plateLength/2 - 8, cfg.plateLength/2 + cfg.tabLength + 2]);
ylim([-cfg.plateWidth/2 - 1, cfg.plateWidth/2 + 1]);
text(cfg.plateLength/2 - 7.5, cfg.plateWidth/2 - 0.7, ...
    'Outer: via pad | Inner: drill | Dashed: non-connected-layer antipad', ...
    'FontSize', 7, 'HorizontalAlignment', 'left', 'Interpreter', 'none', ...
    'Color', [0.2 0.2 0.2], 'Clipping', 'on');

catch ME
    close(fig);
    rethrow(ME);
end

end

%% =========================================================
function fig = plotLayerPreview(cfg, boardXY, layerPaths, padA, padB, vias, k)
% Standalone preview for one copper layer. Plated through holes appear on
% every layer: connected layers show the pad and non-connected layers show
% the antipad keepout.
role = layerRole(cfg, k);
titleText = sprintf('Layer L%d (%s)', k, role);

fig = figure('Name', titleText, 'Color', 'w', 'Visible', 'off');

try
hold on;
axis equal;
grid on;
box on;

drawBoardOutline(boardXY);

for pathIndex = 1:numel(layerPaths{k})
    path = layerPaths{k}{pathIndex};
    if pathIndex == 1
        displayName = sprintf('L%d coil', k);
    else
        displayName = sprintf('L%d output return', k);
    end
    plot(path(:, 1), path(:, 2), 'LineWidth', 0.8, 'DisplayName', displayName);
end

if k == 1
    drawCircle(padA(1), padA(2), cfg.padDiameter, [0.85 0.33 0.10], 1.2, 'PAD_A');
    drawCircle(padB(1), padB(2), cfg.padDiameter, [0.85 0.33 0.10], 1.2, 'PAD_B');
end

for v = 1:numel(vias)
    via = vias(v);
    connected = any(via.connectedLayers == k);
    if connected
        drawCircle(via.xy(1), via.xy(2), via.padDiameter, ...
            [0.2 0.35 0.6], 1.2, via.name);
    elseif strcmp(via.type, 'through_via') && via.antipadDiameter > 0
        drawCircle(via.xy(1), via.xy(2), via.antipadDiameter, ...
            [0.6 0.2 0.2], 1.0, sprintf('%s antipad', via.name), '--');
    else
        continue
    end
    drawCircle(via.xy(1), via.xy(2), via.drillDiameter, ...
        'k', 0.8, sprintf('%s drill', via.name));
end

xlabel('X / mm');
ylabel('Y / mm');
title(titleText);
xlim([min(boardXY(:, 1)) - 1, max(boardXY(:, 1)) + 1]);
ylim([min(boardXY(:, 2)) - 1, max(boardXY(:, 2)) + 1]);
legend('Location', 'bestoutside', 'Interpreter', 'none');

catch ME
    close(fig);
    rethrow(ME);
end

end

%% =========================================================
function role = layerRole(cfg, k)
% ASCII role suffix for layer preview file names.
if k == 1
    role = 'top';
elseif k == cfg.layerCount
    role = 'bottom';
else
    role = sprintf('inner%d', k - 1);
end

end

%% =========================================================
function exportFigureAndClose(fig, filename)
% Export one hidden figure as a white-background vector SVG and close it.
% The original exception is rethrown so the caller can close sibling figures.
try
    exportgraphics(fig, filename, ...
        'ContentType', 'vector', 'BackgroundColor', 'white');
catch ME
    close(fig);
    rethrow(ME);
end
close(fig);

end

%% =========================================================
function closeCreatedFigures(priorFigures)
% Close all figures that did not exist before this writePreviews call.
currentFigures = double(findall(0, 'Type', 'figure'));
newFigures = setdiff(currentFigures, priorFigures);
for k = 1:numel(newFigures)
    h = newFigures(k);
    if isgraphics(h, 'figure')
        close(h);
    end
end

end

%% =========================================================
function drawBoardOutline(boardXY)
% Dashed board outline, same visual style as the existing previews.
plot([boardXY(:, 1); boardXY(1, 1)], ...
     [boardXY(:, 2); boardXY(1, 2)], ...
     '--', 'LineWidth', 1.0, 'DisplayName', 'Board outline');

end

%% =========================================================
function drawCircle(x, y, diameter, lineColor, lineWidth, displayName, lineStyle)
% Unfilled circle of the given true diameter using only basic MATLAB graphics.
if nargin < 6
    displayName = '';
end
if nargin < 7
    lineStyle = '-';
end
radius = diameter / 2;
theta = linspace(0, 2*pi, 121);
cx = x + radius * cos(theta);
cy = y + radius * sin(theta);
if isempty(displayName)
    plot(cx, cy, 'Color', lineColor, 'LineWidth', lineWidth, 'LineStyle', lineStyle, ...
        'HandleVisibility', 'off');
else
    plot(cx, cy, 'Color', lineColor, 'LineWidth', lineWidth, 'LineStyle', lineStyle, ...
        'DisplayName', displayName);
end

end
