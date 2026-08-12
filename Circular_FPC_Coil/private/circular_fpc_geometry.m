function varargout = circular_fpc_geometry(operation, varargin)
% 板框、线圈与端子几何构造（R2-R3），三个子操作：
%   'effective'  : 由 cfg 计算缩放后的有效尺寸（eff 结构体）
%   'board'      : 构造板框（外圆 + 内孔环区 + 中央平台 + 4 条连接桥）与布局参考系
%   'network'    : 构造线圈螺旋线、连接路径、焊盘、过孔与完整串联路由
switch operation
    case 'effective'
        varargout{1} = buildEffectiveDimensions(varargin{1});
    case 'board'
        [varargout{1}, varargout{2}, varargout{3}] = buildBoardGeometry(varargin{1}, varargin{2});
    case 'network'
        [varargout{1}, varargout{2}, varargout{3}, varargout{4}, varargout{5}, varargout{6}] = ...
            buildNetwork(varargin{:});
    otherwise
        error('CircularFPC:InvalidOperation', 'Unknown geometry operation: %s', operation);
end
end

function eff = buildEffectiveDimensions(cfg)
% 有效尺寸：宏观几何（板径/线圈内径/平台/桥宽）乘以 geometryScale；
% coilPitch（螺旋节距）由制造参数计算，不随缩放变化。
eff = struct();
eff.boardOuterDiameter = cfg.boardOuterDiameter * cfg.geometryScale;
eff.coilInnerDiameter = cfg.coilInnerDiameter * cfg.geometryScale;
eff.centerPlatformWidth = cfg.centerPlatformWidth * cfg.geometryScale;
eff.centerPlatformHeight = cfg.centerPlatformHeight * cfg.geometryScale;
eff.bridgeTargetWidth = cfg.bridgeTargetWidth * cfg.geometryScale;
eff.coilPitch = cfg.traceWidth + cfg.traceSpacing + cfg.pitchMargin; % 螺旋节距 = 线宽 + 净距 + 余量
eff.turnsPerCoilLayer = cfg.turnsPerCoilLayer;
eff.actualBridgeWidth = NaN; % 由 buildBoardGeometry 回填
end

function [boardLoops, actualBridgeWidth, layoutRegions] = buildBoardGeometry(cfg, eff)
% 板框 = 圆环区（外圆减内圆）+ 中央平台 + 四条连接桥（入口桥/回流桥交替）。
% 结果板框有 5 个闭环：1 个外边界 + 4 个孔槽（hole），孔槽即平台与桥之外的空隙。
nCircle = 720;
outerR = eff.boardOuterDiameter / 2;
innerR = eff.coilInnerDiameter / 2 - cfg.edgeClearance;
outerP = polyshape(sampleCircle(0, 0, outerR, nCircle));
innerP = polyshape(sampleCircle(0, 0, innerR, nCircle));
annulus = subtract(outerP, innerP); % 线圈所在的圆环区域
cornerR = min(0.25 * min(eff.centerPlatformWidth, eff.centerPlatformHeight), 2.0);
platP = polyshape(sampleRoundedRect(eff.centerPlatformWidth, eff.centerPlatformHeight, cornerR, nCircle));
polys = [annulus, platP]; % 中央平台：焊盘与进出线所在的连接区
% 四条桥臂：沿 connectionAngleDeg ± 90° 与 ±180° 方向连接平台与外部环区。
% 入口/回流桥（0°/180°）加宽，保证双通道走线 + 过孔净距。
bridgeWide = max(eff.bridgeTargetWidth + 2 * (cfg.edgeClearance + cfg.traceWidth / 2 + cfg.pitchMargin), ...
    cfg.viaPadDiameter + 2 * cfg.edgeClearance);
anglesDeg = mod(cfg.connectionAngleDeg + [-90 0 90 180], 360);
bridgeWidths = [eff.bridgeTargetWidth, bridgeWide, eff.bridgeTargetWidth, bridgeWide];
for k = 1:4
    polys(end + 1) = capsulePolyshape(deg2rad(anglesDeg(k)), ...
        0.6 * min(eff.centerPlatformWidth, eff.centerPlatformHeight) / 2, ...
        outerR + 0.5, bridgeWidths(k), 360); %#ok<AGROW>
end
shape = intersect(union(polys), outerP);
nBoundaries = numboundaries(shape);
bnd = cell(nBoundaries, 1);
for boundaryIndex = 1:nBoundaries
    [boundaryX, boundaryY] = boundary(shape, boundaryIndex);
    bnd{boundaryIndex} = [boundaryX, boundaryY];
end
areas = zeros(numel(bnd), 1);
for i = 1:numel(bnd)
    areas(i) = signedArea(bnd{i});
end
[~, outerIdx] = max(abs(areas)); % 面积最大的边界即外轮廓
outerXY = bnd{outerIdx};
holeIdx = setdiff(1:numel(bnd), outerIdx);
cents = zeros(numel(holeIdx), 2);
for j = 1:numel(holeIdx)
    cents(j, :) = mean(bnd{holeIdx(j)}(1:end - 1, :), 1);
end
angs = atan2d(cents(:, 2), cents(:, 1));
[~, ord] = sort(angs); % 孔槽按方位角排序，保证 hole_1..hole_4 命名稳定
boardLoops = struct('name', {}, 'isHole', {}, 'xy', {}, 'orientation', {});
boardLoops(1).name = 'outer';
boardLoops(1).isHole = false;
boardLoops(1).xy = outerXY;
boardLoops(1).orientation = signedArea(outerXY);
for j = 1:numel(holeIdx)
    h = holeIdx(ord(j));
    boardLoops(j + 1).name = sprintf('hole_%d', j);
    boardLoops(j + 1).isHole = true;
    boardLoops(j + 1).xy = bnd{h};
    boardLoops(j + 1).orientation = signedArea(bnd{h});
end
% 实际桥宽 = 相邻孔槽之间的最窄距离（连接桥咽喉宽度）。
actualBridgeWidth = inf;
for j = 1:4
    d = polylineDistance(boardLoops(j + 1).xy, boardLoops(mod(j, 4) + 2).xy, 8);
    actualBridgeWidth = min(actualBridgeWidth, d);
end
% 布局参考系：以连接角 theta 为径向，u 为径向单位向量，t 为切向单位向量；
% 入口桥双通道的半通道宽 = (traceWidth + traceSpacing) / 2。
layoutRegions = struct();
layoutRegions.theta = cfg.connectionAngleDeg;
layoutRegions.u = [cosd(layoutRegions.theta), sind(layoutRegions.theta)];
layoutRegions.t = [-sind(layoutRegions.theta), cosd(layoutRegions.theta)];
layoutRegions.laneOffset = (cfg.traceWidth + cfg.traceSpacing) / 2;
layoutRegions.wideBridgeWidth = bridgeWide;
rBridge1 = 0.6 * min(eff.centerPlatformWidth, eff.centerPlatformHeight) / 2;
layoutRegions.entrySpan = [rBridge1, outerR + 0.5]; % 入口桥上端子可搜索的径向范围
layoutRegions.returnSpan = layoutRegions.entrySpan;
layoutRegions.holeLoops = {boardLoops(2:end).xy};
layoutRegions.outerRadius = outerR;
layoutRegions.rStart = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2; % 线圈最内圈中心半径
layoutRegions.boardShape = shape;
layoutRegions.platformShape = platP;
[platformX, platformY] = boundary(platP);
platformLoop = [platformX, platformY];
if norm(platformLoop(1, :) - platformLoop(end, :)) > 1e-12
    platformLoop(end + 1, :) = platformLoop(1, :);
end
layoutRegions.platformLoop = platformLoop;
end

function xy = sampleCircle(cx, cy, r, n)
th = linspace(0, 2 * pi, n + 1);
th = th(1:end - 1);
xy = [cx + r * cos(th); cy + r * sin(th)].';
end

function xy = sampleRoundedRect(w, h, r, n)
halfW = w / 2;
halfH = h / 2;
r = min(r, min(halfW, halfH));
nq = max(8, round(n / 8));
c1 = [halfW - r, halfH - r];
c2 = [halfW - r, -halfH + r];
c3 = [-halfW + r, -halfH + r];
c4 = [-halfW + r, halfH - r];
a1 = linspace(pi / 2, pi, nq).';
arcTL = c4 + r * [cos(a1), sin(a1)];
a2 = linspace(pi, 3 * pi / 2, nq).';
arcBL = c3 + r * [cos(a2), sin(a2)];
a3 = linspace(3 * pi / 2, 2 * pi, nq).';
arcBR = c2 + r * [cos(a3), sin(a3)];
a4 = linspace(0, pi / 2, nq).';
arcTR = c1 + r * [cos(a4), sin(a4)];
xy = [c1 + [0, r]; arcTL; arcBL; arcBR; arcTR(1:end - 1, :)];
end

function ps = capsulePolyshape(theta, r1, r2, width, nArc)
p1 = r1 * [cos(theta), sin(theta)];
p2 = r2 * [cos(theta), sin(theta)];
hw = width / 2;
perp = [-sin(theta), cos(theta)];
nq = max(8, round(nArc / 4));
aFar = linspace(theta + pi / 2, theta + 3 * pi / 2, nq).';
arcFar = p2 + hw * [cos(aFar), sin(aFar)];
aNear = linspace(theta - pi / 2, theta + pi / 2, nq).';
arcNear = p1 + hw * [cos(aNear), sin(aNear)];
xy = [p1 + hw * perp; arcFar; arcNear(1:end - 1, :)];
ps = polyshape(xy);
end

function a = signedArea(xy)
a = 0.5 * sum(xy(1:end - 1, 1) .* xy(2:end, 2) - xy(1:end - 1, 2) .* xy(2:end, 1));
end

function d = polylineDistance(A, B, stride)
A2 = A(1:stride:end, :);
B2 = B(1:stride:end, :);
if size(A2, 1) < 2
    A2 = A([1, min(size(A, 1), 2)], :);
end
if size(B2, 1) < 2
    B2 = B([1, min(size(B, 1), 2)], :);
end
d1 = min(pointSegDistanceMatrix(A2, B2(1:end - 1, :), B2(2:end, :)));
d2 = min(pointSegDistanceMatrix(B2, A2(1:end - 1, :), A2(2:end, :)));
d = min(d1, d2);
end

function dMin = pointSegDistanceMatrix(P, A, B)
len2 = sum((B - A).^2, 2);
ax = P(:, 1) - A(:, 1).';
ay = P(:, 2) - A(:, 2).';
dx = (B(:, 1) - A(:, 1)).';
dy = (B(:, 2) - A(:, 2)).';
t = (ax .* dx + ay .* dy) ./ max(len2.', eps);
t = max(0, min(1, t));
qx = A(:, 1).' + t .* dx;
qy = A(:, 2).' + t .* dy;
d = sqrt((P(:, 1) - qx).^2 + (P(:, 2) - qy).^2);
dMin = min(d, [], 2);
end

function coils = buildCoils(cfg, eff, activeLayers, directions)
% 生成阿基米德螺旋线圈：r = rStart + coilPitch * theta/(2π)。
% 奇数序号活动层从 connectionAngleDeg 相位起绕（CCW），偶数层相位 +180° 起绕（CW）。
coils = cell(1, cfg.boardLayerCount);
rStart = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2;
span = 2 * pi * (cfg.turnsPerCoilLayer - 1); % 匝数-1 圈（首点在内圈起点）
n = cfg.samplePointsPerTurn * (cfg.turnsPerCoilLayer - 1) + 1;
for p = 1:numel(activeLayers)
    li = activeLayers(p);
    phaseDeg = cfg.connectionAngleDeg + 180 * floor((p - 1) / 2); % 相邻线圈对相位相差 180°
    th = linspace(0, span, n);
    ang = deg2rad(phaseDeg) + th;
    r = rStart + eff.coilPitch * th / (2 * pi);
    xy = [r .* cos(ang); r .* sin(ang)].';
    if directions(p) < 0
        xy = flipud(xy); % CW：翻转点序，使起点在半径大的一端
    end
    coils{li} = xy;
end
end

function [coils, connectionPaths, pads, vias, seriesRoute, returnLayer] = ...
    buildNetwork(cfg, eff, activeLayers, directions, layoutRegions)
% 构建完整串联网络：PAD_A → 线圈(各活动层串联) → 过孔层间转移 → PAD_B，
% 并生成每段连接路径（connectionPaths 按物理层存放）。
coils = buildCoils(cfg, eff, activeLayers, directions);
connectionPaths = cell(1, cfg.boardLayerCount);
for li = 1:cfg.boardLayerCount
    connectionPaths{li} = {};
end

[pads, vias, returnLayer, routeInfo] = buildTerminals(cfg, eff, activeLayers, coils, layoutRegions);
seriesRoute = struct('name', {}, 'kind', {}, 'startXY', {}, 'endXY', {}, ...
    'startLayer', {}, 'endLayer', {});
seriesRoute = addRouteComponent(seriesRoute, 'PAD_A', 'PAD', pads(1).xy, pads(1).xy, 1, 1);
coil1 = coils{activeLayers(1)};
[seriesRoute, connectionPaths] = addTraceIfNeeded(seriesRoute, connectionPaths, 1, ...
    'TRACE_L1_ENTRY', pads(1).xy, coil1(1, :), [], coil1(2, :) - coil1(1, :), cfg, false, routeInfo);
if numel(activeLayers) == 1
    % 单线圈组合：线圈外端经 VRET 到最高物理层 → 该层 RETURN 铜线回中央 VOUT → 回 L1 接 PAD_B
    seriesRoute = addRouteComponent(seriesRoute, sprintf('COIL_L%d', activeLayers(1)), 'COIL', ...
        coil1(1, :), coil1(end, :), activeLayers(1), activeLayers(1));
    vret = vias(strcmp({vias.name}, 'VRET'));
    seriesRoute = addRouteComponent(seriesRoute, 'VRET', 'VIA', vret.xy, vret.xy, ...
        vret.fromLayer, vret.toLayer);
    vout = vias(strcmp({vias.name}, 'VOUT'));
    retLayer = vret.toLayer;
    [seriesRoute, connectionPaths] = addTraceIfNeeded(seriesRoute, connectionPaths, retLayer, ...
        sprintf('RETURN_L%d', retLayer), vret.xy, vout.xy, [], [], cfg, false, routeInfo);
    seriesRoute = addRouteComponent(seriesRoute, 'VOUT', 'VIA', vout.xy, vout.xy, ...
        vout.fromLayer, vout.toLayer);
    [seriesRoute, connectionPaths] = addTraceIfNeeded(seriesRoute, connectionPaths, 1, ...
        'TRACE_L1_EXIT', vout.xy, pads(2).xy, [], [], cfg, false, routeInfo);
else
    % 多线圈组合：COIL_Lx → Vxy → COIL_Ly 依次串联，最后经 VOUT 回 L1 接 PAD_B
    for p = 1:numel(activeLayers)
        li = activeLayers(p);
        coil = coils{li};
        seriesRoute = addRouteComponent(seriesRoute, sprintf('COIL_L%d', li), 'COIL', ...
            coil(1, :), coil(end, :), li, li);
        if p < numel(activeLayers)
            vName = sprintf('V%d%d', activeLayers(p), activeLayers(p + 1));
            v = vias(strcmp({vias.name}, vName));
            if norm(coil(end, :) - v.xy) > 1e-9
                [seriesRoute, connectionPaths] = addTraceIfNeeded(seriesRoute, connectionPaths, li, ...
                    sprintf('TRACE_L%d_OUT', li), coil(end, :), v.xy, ...
                    coil(end, :) - coil(end - 1, :), [], cfg, false, routeInfo);
            end
            seriesRoute = addRouteComponent(seriesRoute, vName, 'VIA', v.xy, v.xy, ...
                v.fromLayer, v.toLayer);
            nextCoil = coils{activeLayers(p + 1)};
            if norm(v.xy - nextCoil(1, :)) > 1e-9
                [seriesRoute, connectionPaths] = addTraceIfNeeded(seriesRoute, connectionPaths, ...
                    activeLayers(p + 1), sprintf('TRACE_L%d_IN', activeLayers(p + 1)), ...
                    v.xy, nextCoil(1, :), [], nextCoil(2, :) - nextCoil(1, :), cfg, false, routeInfo);
            end
        end
    end
    lastLi = activeLayers(end);
    lastCoil = coils{lastLi};
    vout = vias(strcmp({vias.name}, 'VOUT'));
    if norm(lastCoil(end, :) - vout.xy) > 1e-9
        [seriesRoute, connectionPaths] = addTraceIfNeeded(seriesRoute, connectionPaths, lastLi, ...
            sprintf('TRACE_L%d_OUT', lastLi), lastCoil(end, :), vout.xy, ...
            lastCoil(end, :) - lastCoil(end - 1, :), [], cfg, false, routeInfo);
    end
    seriesRoute = addRouteComponent(seriesRoute, 'VOUT', 'VIA', vout.xy, vout.xy, ...
        vout.fromLayer, vout.toLayer);
    [seriesRoute, connectionPaths] = addTraceIfNeeded(seriesRoute, connectionPaths, 1, ...
        'TRACE_L1_EXIT', vout.xy, pads(2).xy, [], [], cfg, false, routeInfo);
end
seriesRoute = addRouteComponent(seriesRoute, 'PAD_B', 'PAD', pads(2).xy, pads(2).xy, 1, 1);
end

function route = addRouteComponent(route, name, kind, startXY, endXY, startLayer, endLayer)
route(end + 1).name = name; %#ok<AGROW>
route(end).kind = kind;
route(end).startXY = startXY;
route(end).endXY = endXY;
route(end).startLayer = startLayer;
route(end).endLayer = endLayer;
end

function [route, connectionPaths] = addTraceIfNeeded(route, connectionPaths, layer, name, ...
    p0, p3, tan0, tan1, cfg, straightFlag, routeInfo)
if norm(p3 - p0) <= 1e-9
    return;
end
if straightFlag
    path = [p0; p3];
elseif ~isempty(routeInfo)
    path = buildConstrainedTracePath(name, p0, p3, cfg, routeInfo.layoutRegions, routeInfo);
elseif strcmp(name, 'TRACE_L1_EXIT') || strncmp(name, 'RETURN_', 7)
    path = [p0; p3];
else
    path = smoothLead(p0, p3, tan0, tan1, cfg);
end
connectionPaths{layer}{end + 1} = path; %#ok<AGROW>
route = addRouteComponent(route, name, 'TRACE', p0, p3, layer, layer);
end

function path = smoothLead(p0, p3, tan0, tan1, cfg)
nPts = 129;
ctrlLen = min(norm(p3 - p0) / 3, 1.5);
d0 = tan0;
if norm(d0) <= 1e-12
    d0 = p3 - p0;
end
d1 = tan1;
if norm(d1) <= 1e-12
    d1 = p3 - p0;
end
if norm(d0) <= 1e-12 || norm(d1) <= 1e-12
    path = [p0; p3];
    return;
end
d0 = d0 / norm(d0);
d1 = d1 / norm(d1);
c1 = p0 + ctrlLen * d0;
c2 = p3 - ctrlLen * d1;
t = linspace(0, 1, nPts).';
w0 = (1 - t).^3;
w1 = 3 * (1 - t).^2 .* t;
w2 = 3 * (1 - t) .* t.^2;
w3 = t.^3;
path = w0 * p0 + w1 * c1 + w2 * c2 + w3 * p3;
end

function [pads, vias, returnLayer, routeInfo] = buildTerminals(cfg, eff, activeLayers, coils, layoutRegions)
% 构造全部端子（焊盘 + 过孔）：
%   - auto 模式：在入口桥轴上自动搜索 PAD_A/PAD_B 位置、VOUT 与内端过渡过孔位置；
%   - manual 模式：直接采用 cfg.manualPadAXY/manualPadBXY/manualSeriesViaXY。
% 过孔命名与角色（2/1、4/1: VRET, VOUT；2/2: V12, VOUT；4/2: V14, VOUT；4/4: V12, V23, V34, VOUT）。
manual = strcmp(cfg.terminalPlacementMode, 'manual');
theta = layoutRegions.theta;
u = layoutRegions.u;
t = layoutRegions.t;
if manual
    padA = cfg.manualPadAXY;
    padB = cfg.manualPadBXY;
    rPad = NaN;
    rVout = NaN;
    rV23 = NaN;
else
    rPad = searchPadCenterRadius(cfg, layoutRegions); % 焊盘对中心沿入口桥轴的半径
    pairCenter = rPad * u;
    padA = pairCenter - (cfg.padPairSpacing / 2) * t; % 切向负侧为 PAD_A
    padB = pairCenter + (cfg.padPairSpacing / 2) * t; % 切向正侧为 PAD_B
    rVout = searchSafeRadiusOnAxis(cfg, layoutRegions, layoutRegions.laneOffset, ...
        cfg.viaPadDiameter / 2, layoutRegions.rStart - 0.36, rPad + 1.0);
    rV23 = NaN;
    if numel(activeLayers) == 4 && activeLayers(end) == 4
        % 4/4 组合才有 V23：在回流桥轴（-u 方向）上搜索位置
        rV23 = searchSafeRadiusOnAxis(cfg, layoutRegions, 0.0, ...
            cfg.viaPadDiameter / 2, layoutRegions.rStart - 1.5, layoutRegions.entrySpan(1) + 0.5);
    end
end
pads = struct('name', {}, 'xy', {}, 'diameter', {}, 'layer', {}, 'removable', {}, ...
    'placementRegion', {}, 'bridgeAngleDeg', {});
pads(1).name = 'PAD_A';
pads(1).xy = padA;
pads(1).diameter = cfg.padDiameter;
pads(1).layer = 1;
pads(1).removable = true;
pads(2).name = 'PAD_B';
pads(2).xy = padB;
pads(2).diameter = cfg.padDiameter;
pads(2).layer = 1;
pads(2).removable = true;
if manual
    pads(1).placementRegion = 'MANUAL';
    pads(1).bridgeAngleDeg = NaN;
    pads(2).placementRegion = 'MANUAL';
    pads(2).bridgeAngleDeg = NaN;
else
    pads(1).placementRegion = 'CENTER_PLATFORM_NEAR_ENTRY_BRIDGE';
    pads(1).bridgeAngleDeg = theta;
    pads(2).placementRegion = 'CENTER_PLATFORM_NEAR_ENTRY_BRIDGE';
    pads(2).bridgeAngleDeg = theta;
end
if numel(activeLayers) == 1
    returnLayer = cfg.boardLayerCount;
    viaNames = {'VRET', 'VOUT'};
    viaLayers = [1, returnLayer; returnLayer, 1];
    viaRoles = {'RETURN_OUTER', 'OUTPUT_RETURN'};
    viaXY = [coils{activeLayers(1)}(end, :); ...
        rVout * u + layoutRegions.laneOffset * t];
    viaRegions = {'OUTER_COIL_ENDPOINT', 'ENTRY_BRIDGE'};
    viaAngles = [theta, theta];
else
    returnLayer = NaN;
    viaNames = {};
    viaLayers = zeros(0, 2);
    viaRoles = {};
    viaXY = zeros(0, 2);
    viaRegions = {};
    viaAngles = [];
    for p = 1:numel(activeLayers) - 1
        viaNames{end + 1} = sprintf('V%d%d', activeLayers(p), activeLayers(p + 1)); %#ok<AGROW>
        viaLayers(end + 1, :) = [activeLayers(p), activeLayers(p + 1)]; %#ok<AGROW>
        if mod(p, 2) == 1
            viaRoles{end + 1} = 'OUTER_TRANSITION'; %#ok<AGROW>
            viaXY(end + 1, :) = coils{activeLayers(p)}(end, :); %#ok<AGROW>
            viaRegions{end + 1} = 'OUTER_COIL_ENDPOINT'; %#ok<AGROW>
            if strcmp(viaNames{end}, 'V34')
                viaAngles(end + 1) = theta + 180; %#ok<AGROW>
            else
                viaAngles(end + 1) = theta; %#ok<AGROW>
            end
        else
            viaRoles{end + 1} = 'INNER_TRANSITION'; %#ok<AGROW>
            viaXY(end + 1, :) = -rV23 * u; %#ok<AGROW>
            viaRegions{end + 1} = 'RETURN_BRIDGE'; %#ok<AGROW>
            viaAngles(end + 1) = theta + 180; %#ok<AGROW>
        end
    end
    viaNames{end + 1} = 'VOUT'; %#ok<AGROW>
    viaLayers(end + 1, :) = [activeLayers(end), 1]; %#ok<AGROW>
    viaRoles{end + 1} = 'OUTPUT_RETURN'; %#ok<AGROW>
    viaXY(end + 1, :) = rVout * u + layoutRegions.laneOffset * t; %#ok<AGROW>
    viaRegions{end + 1} = 'ENTRY_BRIDGE'; %#ok<AGROW>
    viaAngles(end + 1) = theta; %#ok<AGROW>
end
nVias = numel(viaNames);
if manual
    if size(cfg.manualSeriesViaXY, 1) ~= nVias
        error('CircularFPC:TerminalPlacementInvalid', ...
            'manualSeriesViaXY must have exactly %d rows for this layer combination.', nVias);
    end
    viaXY = cfg.manualSeriesViaXY;
end
vias = struct('name', {}, 'xy', {}, 'drillDiameter', {}, 'padDiameter', {}, ...
    'fromLayer', {}, 'toLayer', {}, 'isOutputReturn', {}, 'role', {}, ...
    'placementRegion', {}, 'bridgeAngleDeg', {});
for k = 1:nVias
    vias(k).name = viaNames{k};
    vias(k).xy = viaXY(k, :);
    vias(k).drillDiameter = cfg.viaDrillDiameter;
    vias(k).padDiameter = cfg.viaPadDiameter;
    vias(k).fromLayer = viaLayers(k, 1);
    vias(k).toLayer = viaLayers(k, 2);
    vias(k).isOutputReturn = strcmp(viaNames{k}, 'VOUT');
    vias(k).role = viaRoles{k};
    if manual
        vias(k).placementRegion = 'MANUAL';
        vias(k).bridgeAngleDeg = NaN;
    else
        vias(k).placementRegion = viaRegions{k};
        vias(k).bridgeAngleDeg = viaAngles(k);
    end
end
validateTerminals(cfg, layoutRegions, pads, vias);
if manual
    routeInfo = [];
else
    routeInfo = struct();
    routeInfo.layoutRegions = layoutRegions;
    routeInfo.padA = pads(1).xy;
    routeInfo.padB = pads(2).xy;
    routeInfo.rPad = rPad;
    routeInfo.rVout = rVout;
    routeInfo.rV23 = rV23;
    vout = vias(strcmp({vias.name}, 'VOUT'));
    routeInfo.voutXY = vout(1).xy;
    v23 = vias(strcmp({vias.name}, 'V23'));
    if isempty(v23)
        routeInfo.v23XY = [];
    else
        routeInfo.v23XY = v23(1).xy;
    end
end
end

function validateTerminals(cfg, layoutRegions, pads, vias)
outerR = layoutRegions.outerRadius;
holes = layoutRegions.holeLoops;
[names, xy, radii] = terminalArrays(pads, vias);
for i = 1:numel(names)
    pxy = xy(i, :);
    r = radii(i);
    if ~isnumeric(pxy) || numel(pxy) ~= 2 || ~all(isfinite(pxy))
        error('CircularFPC:TerminalPlacementInvalid', 'Terminal %s has invalid coordinates.', names{i});
    end
    if norm(pxy) + r > outerR - 0.05
        error('CircularFPC:TerminalPlacementInvalid', ...
            'Terminal %s is outside the outer board circle.', names{i});
    end
    if minDistanceToHolesLocal(pxy, holes) - r < cfg.edgeClearance - 1e-9
        error('CircularFPC:TerminalPlacementInvalid', ...
            'Terminal %s violates copper-to-slot clearance.', names{i});
    end
end
for i = 1:numel(names)
    for j = i + 1:numel(names)
        d = norm(xy(i, :) - xy(j, :));
        req = radii(i) + radii(j) + cfg.terminalClearance;
        if d < req - 1e-9
            error('CircularFPC:TerminalPlacementInvalid', ...
                'Terminals %s and %s are too close.', names{i}, names{j});
        end
    end
end
if ~strcmp(pads(1).placementRegion, 'MANUAL')
    u = layoutRegions.u;
    t = layoutRegions.t;
    center = (pads(1).xy + pads(2).xy) / 2;
    if abs(dot(center, t)) > 1e-6 || dot(center, u) <= 0 || ...
            abs(norm(pads(2).xy - pads(1).xy) - cfg.padPairSpacing) > 1e-6
        error('CircularFPC:TerminalPlacementInvalid', ...
            'Automatic pad pair violates the entry bridge layout contract.');
    end
    vout = vias(strcmp({vias.name}, 'VOUT'));
    if numel(vout) ~= 1 || abs(dot(vout(1).xy, t) - layoutRegions.laneOffset) > 1e-6
        error('CircularFPC:TerminalPlacementInvalid', ...
            'Automatic VOUT violates the entry bridge positive lane contract.');
    end
    v23 = vias(strcmp({vias.name}, 'V23'));
    if ~isempty(v23)
        tRet = [-sind(layoutRegions.theta + 180), cosd(layoutRegions.theta + 180)];
        if numel(v23) ~= 1 || abs(dot(v23(1).xy, tRet)) > 1e-6
            error('CircularFPC:TerminalPlacementInvalid', ...
                'Automatic V23 violates the return bridge axis contract.');
        end
    end
end
end

function r = terminalRadius(t)
if isfield(t, 'diameter')
    r = t.diameter / 2;
else
    r = t.padDiameter / 2;
end
end

function [names, xy, radii] = terminalArrays(pads, vias)
count = numel(pads) + numel(vias);
names = cell(count, 1);
xy = zeros(count, 2);
radii = zeros(count, 1);
index = 0;
for padIndex = 1:numel(pads)
    index = index + 1;
    names{index} = pads(padIndex).name;
    xy(index, :) = pads(padIndex).xy;
    radii(index) = pads(padIndex).diameter / 2;
end
for viaIndex = 1:numel(vias)
    index = index + 1;
    names{index} = vias(viaIndex).name;
    xy(index, :) = vias(viaIndex).xy;
    radii(index) = vias(viaIndex).padDiameter / 2;
end
end

function path = buildConstrainedTracePath(name, p0, p3, cfg, lr, ri)
% 按路径名构造约束走线：入口/出口桥走线沿双通道（laneOffset）布设，
% 内外端过渡走线用贝塞尔样条平滑连接；普通连接走线退回 smoothLead。
u = lr.u;
t = lr.t;
lane = lr.laneOffset;
rStart = lr.rStart;
if strcmp(name, 'TRACE_L1_ENTRY')
    % 入口走线：PAD_A → 沿负切向通道 → 圆弧转弯 → 径向段 → 进入线圈内端
    rPad = ri.rPad;
    R1 = 0.4;
    R3 = 0.175;
    S1 = rPad * u - (lane + R1) * t;
    seg1 = sampleSegment(ri.padA, S1, 0.05);
    arc1 = sampleArc(S1, t, R1, -1, u, t, 45);
    laneEnd = (rStart - R3) * u - lane * t;
    lanePts = sampleSegment(arc1(end, :), laneEnd, 0.05);
    arc2 = sampleArc(laneEnd, u, R3, +1, u, t, 45);
    path = [seg1; arc1(2:end, :); lanePts(2:end, :); arc2(2:end, :)];
elseif strcmp(name, 'TRACE_L1_EXIT')
    % 出口走线：VOUT → 沿正切向通道 → 圆弧转弯 → 接到 PAD_B
    rPad = ri.rPad;
    R2 = 0.2;
    laneStart = (rPad + R2) * u + lane * t;
    lanePts = sampleSegment(ri.voutXY, laneStart, 0.05);
    arc2x = sampleArc(laneStart, -u, R2, -1, u, t, 45);
    seg2 = sampleSegment(arc2x(end, :), ri.padB, 0.05);
    path = [lanePts; arc2x(2:end, :); seg2(2:end, :)];
elseif strncmp(name, 'RETURN_', 7)
    % 回流走线：单线圈组合最高物理层上 VRET → VOUT 的直线段
    path = sampleSegment(p0, p3, 0.1);
elseif strcmp(name, 'TRACE_L3_IN')
    path = sampleBezier(-ri.rV23 * u, u, -rStart * u, -t, 0.6, 0.6, 257);
elseif strcmp(name, 'TRACE_L4_OUT')
    if dot(p0, u) < 0
        path = sampleBezier(-rStart * u, t, ri.voutXY, u, 1.5, 1.5, 257);
    else
        path = sampleBezier(rStart * u, -t, ri.voutXY, -u, 0.15, 0.15, 129);
    end
elseif strcmp(name, 'TRACE_L2_OUT')
    if ~isempty(ri.v23XY) && norm(p3 - ri.v23XY) <= 1e-9
        % 4/4 的 L2 外端 → V23：先折向回流桥轴再转出
        transitionEnd = (rStart - 1.5) * u;
        bend = sampleBezier(p0, -t, transitionEnd, -u, 0.5, 0.5, 129);
        if norm(transitionEnd - p3) <= 1e-9
            path = bend;
        else
            trunk = sampleSegment(transitionEnd, p3, 0.05);
            path = [bend; trunk(2:end, :)];
        end
    else
        path = sampleBezier(rStart * u, -t, ri.voutXY, -u, 0.15, 0.15, 129);
    end
else
    path = smoothLead(p0, p3, [], [], cfg);
end
end

function pts = sampleSegment(p0, p3, spacing)
d = norm(p3 - p0);
n = max(2, ceil(d / spacing) + 1);
s = linspace(0, 1, n).';
pts = p0 + s * (p3 - p0);
end

function pts = sampleArc(S, a, R, turn, u, t, n)
if turn > 0
    C = S + R * [-a(2), a(1)];
else
    C = S + R * [a(2), -a(1)];
end
v = S - C;
phi0 = atan2(dot(v, t), dot(v, u));
phi = phi0 + deg2rad(90 * (0:n - 1).' / (n - 1) * turn);
pts = C + R * (cos(phi) * u + sin(phi) * t);
end

function pts = sampleBezier(p0, d0, p3, d1, L1, L2, n)
n0 = norm(d0);
if n0 > 0
    d0 = d0 / n0;
else
    d0 = [1, 0];
end
n1 = norm(d1);
if n1 > 0
    d1 = d1 / n1;
else
    d1 = [1, 0];
end
c1 = p0 + L1 * d0;
c2 = p3 - L2 * d1;
s = linspace(0, 1, n).';
w0 = (1 - s).^3;
w1 = 3 * (1 - s).^2 .* s;
w2 = 3 * (1 - s) .* s.^2;
w3 = s.^3;
pts = w0 * p0 + w1 * c1 + w2 * c2 + w3 * p3;
end

function dMin = minDistanceToHolesLocal(points, holeLoops)
dMin = inf;
nPts = size(points, 1);
first = 1;
while first <= nPts
    last = min(first + 256 - 1, nPts);
    P = points(first:last, :);
    for h = 1:numel(holeLoops)
        xy = holeLoops{h};
        nSeg = size(xy, 1) - 1;
        if nSeg < 1
            continue;
        end
        A = xy(1:nSeg, :);
        B = xy(2:nSeg + 1, :);
        len2 = sum((B - A).^2, 2);
        keep = len2 > eps;
        A = A(keep, :);
        B = B(keep, :);
        if isempty(A)
            continue;
        end
        ax = P(:, 1) - A(:, 1).';
        ay = P(:, 2) - A(:, 2).';
        dx = (B(:, 1) - A(:, 1)).';
        dy = (B(:, 2) - A(:, 2)).';
        len2k = sum((B - A).^2, 2).';
        tt = (ax .* dx + ay .* dy) ./ len2k;
        tt = max(0, min(1, tt));
        qx = A(:, 1).' + tt .* dx;
        qy = A(:, 2).' + tt .* dy;
        d = sqrt((P(:, 1) - qx).^2 + (P(:, 2) - qy).^2);
        dMin = min(dMin, min(d(:)));
    end
    first = last + 1;
end
end

function rPad = searchPadCenterRadius(cfg, lr)
u = lr.u;
t = lr.t;
holes = lr.holeLoops;
half = cfg.padPairSpacing / 2;
req = cfg.padDiameter / 2 + cfg.edgeClearance + 0.02;
reqPlatform = cfg.padDiameter / 2 + 0.05;
outerLimit = lr.outerRadius - 0.05;
found = NaN;
for r = lr.entrySpan(2):-0.02:1.0
    pA = r * u - half * t;
    pB = r * u + half * t;
    if norm(pA) > outerLimit || norm(pB) > outerLimit
        continue;
    end
    if ~isinterior(lr.platformShape, pA(1), pA(2)) || ~isinterior(lr.platformShape, pB(1), pB(2))
        continue;
    end
    if minDistanceToHolesLocal(pA, {lr.platformLoop}) < reqPlatform - 1e-9 || ...
            minDistanceToHolesLocal(pB, {lr.platformLoop}) < reqPlatform - 1e-9
        continue;
    end
    if minDistanceToHolesLocal(pA, holes) >= req && ...
            minDistanceToHolesLocal(pB, holes) >= req
        found = r;
        break;
    end
end
if isnan(found)
    error('CircularFPC:TerminalPlacementInvalid', ...
        'No safe automatic pad pair position on the entry bridge (pad pair/entry bridge).');
end
rPad = found;
end

function r = searchSafeRadiusOnAxis(cfg, lr, tOffset, radius, rHigh, rLow)
u = lr.u;
t = lr.t;
holes = lr.holeLoops;
req = radius + cfg.edgeClearance + 0.02;
outerLimit = lr.outerRadius - 0.05;
found = NaN;
for rr = rHigh:-0.02:rLow
    p = rr * u + tOffset * t;
    if norm(p) > outerLimit
        continue;
    end
    if minDistanceToHolesLocal(p, holes) >= req
        found = rr;
        break;
    end
end
if isnan(found)
    error('CircularFPC:TerminalPlacementInvalid', ...
        'No safe via position on the bridge axis (entry/return bridge).');
end
r = found;
end
