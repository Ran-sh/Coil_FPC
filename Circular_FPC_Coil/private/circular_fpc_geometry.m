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
% 平台矩形不做圆角，保持精确的 13 x 14 mm 正向矩形。
% 平台是全局坐标系中的固定基准面：13 x 14 mm 必须保持正向矩形，
% 不随 connectionAngleDeg 旋转。四个挖槽由该平台、内圆环和连接桥的布尔
% 并集自然形成；端子走线仍在自己的 u/t 局部坐标系中随 connectionAngleDeg 旋转。
platformXY = sampleRectangle(eff.centerPlatformWidth, eff.centerPlatformHeight);
platP = polyshape(platformXY);
% 可行性校验保证平台四角连同 platformSlotMargin 完全位于内圆环以内，
% 因此平台不会自行粘到环区；板框只通过下面四条显式等宽桥相连。
polys = [annulus, platP]; % 中央平台：焊盘与进出线所在的连接区
% 四条桥臂随 connectionAngleDeg 旋转，连接固定正向平台与外部环区。
% 四条桥使用同一个统一宽度；该宽度必须同时容纳目标桥宽、过孔净距、
% PAD_A/PAD_B 与 d 的端子包络及相应净距规则。
% 这里不再使用独立的解析桥宽上限；桥宽上限由下面的最终布尔结果决定。
terminalBoundaryMargin = max([cfg.edgeClearance, cfg.terminalClearance, cfg.traceSpacing]) + 0.03;
terminalEnvelopeWidth = cfg.terminalLeadSpacing + cfg.padDiameter + 2 * terminalBoundaryMargin;
bridgeWidth = max([eff.bridgeTargetWidth + 2 * (cfg.edgeClearance + cfg.traceWidth / 2 + cfg.pitchMargin), ...
    cfg.viaPadDiameter + 2 * cfg.edgeClearance, ...
    terminalEnvelopeWidth]);
anglesDeg = mod(cfg.connectionAngleDeg + [-90 0 90 180], 360);
bridgeWidths = repmat(bridgeWidth, 1, 4);
for k = 1:4
    polys(end + 1) = capsulePolyshape(deg2rad(anglesDeg(k)), ...
        0.6 * min(eff.centerPlatformWidth, eff.centerPlatformHeight) / 2, ...
        outerR + 0.5, bridgeWidths(k), 360); %#ok<AGROW>
end
shape = intersect(union(polys), outerP);
nBoundaries = numboundaries(shape);
% 桥宽上限由最终布尔几何定义：板框必须恰好 5 个闭环（1 外边界 + 4 孔槽）。
% 槽实际消失、合并或被分裂时，numboundaries 会偏离 5，此处明确失败；
% 不静默截断桥宽，也不使用与最终图形脱节的先验上限。
if nBoundaries ~= 5
    error('CircularFPC:GeometryInfeasible', ...
        ['Board outline must contain exactly 5 loops (1 outer + 4 slots), got %d. ', ...
         'The final Boolean geometry has reached the bridge-width/d/platform ', ...
         'topology limit: one or more slots disappeared, merged, or split for ', ...
         'd=%.6f mm. Reduce d/bridgeTargetWidth or increase coilInnerDiameter.'], ...
        nBoundaries, cfg.terminalLeadSpacing);
end
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
    hxy = bnd{h};
    % 自动识别槽边界（圆环弧 × 平台边 × 桥侧）的尖角，并用 0.3 mm
    % 相切圆弧轻微圆角化；中央平台本身仍保持正向矩形。
    hxy = filletHoleCorners(hxy, 0.3, ...
        cfg.minBoardInteriorAngleDeg + cfg.angleToleranceDeg, 10);
    boardLoops(j + 1).name = sprintf('hole_%d', j);
    boardLoops(j + 1).isHole = true;
    boardLoops(j + 1).xy = hxy;
    boardLoops(j + 1).orientation = signedArea(hxy);
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
layoutRegions.bridgeWidth = bridgeWidth;
rBridge1 = 0.6 * min(eff.centerPlatformWidth, eff.centerPlatformHeight) / 2;
layoutRegions.entrySpan = [rBridge1, outerR + 0.5]; % 入口桥上端子可搜索的径向范围
layoutRegions.returnSpan = layoutRegions.entrySpan;
layoutRegions.bridgeWidths = bridgeWidths;
layoutRegions.bridgeAnglesDeg = anglesDeg;
layoutRegions.terminalEnvelopeWidth = terminalEnvelopeWidth;
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

function xy = sampleRectangle(w, h)
% 采样全局坐标系中的正向矩形（顺时针从右上角开始，首尾不重复）。
halfW = w / 2;
halfH = h / 2;
xy = [halfW, halfH; -halfW, halfH; -halfW, -halfH; halfW, -halfH];
end

function ps = capsulePolyshape(theta, r1, r2, width, nArc)
p1 = r1 * [cos(theta), sin(theta)];
p2 = r2 * [cos(theta), sin(theta)];
hw = width / 2;
perp = [-sin(theta), cos(theta)];
nq = max(8, round(nArc / 4));
aFar = linspace(theta + pi / 2, theta - pi / 2, nq).';
arcFar = p2 + hw * [cos(aFar), sin(aFar)];
aNear = linspace(theta - pi / 2, theta - 3 * pi / 2, nq).';
arcNear = p1 + hw * [cos(aNear), sin(aNear)];
xy = [p1 + hw * perp; arcFar; arcNear(1:end - 1, :)];
ps = polyshape(xy);
end

function xy = filletHoleCorners(xy, maxR, angleLimitDeg, nArc)
% 圆角化闭合折线（孔槽边界）：把内角 <= angleLimitDeg 的尖角替换为与两边相切的
% 圆弧（圆角），保证板框不存在 <= 90° 内角。xy 为首尾重复的闭合折线。
n = size(xy, 1) - 1;
if n < 3
    return;
end
ccw = signedArea(xy) > 0;
dirs = zeros(n, 2);
for i = 1:n
    dirs(i, :) = xy(mod(i, n) + 1, :) - xy(i, :);
end
out = zeros(0, 2);
for i = 1:n
    cur = xy(i, :);
    u1 = dirs(mod(i - 2, n) + 1, :); % 入边方向（顶点 i-1 -> i）
    u2 = dirs(i, :); % 出边方向（顶点 i -> i+1）
    len1 = norm(u1);
    len2 = norm(u2);
    if len1 <= 1e-12 || len2 <= 1e-12
        out = [out; cur]; %#ok<AGROW>
        continue;
    end
    u1 = u1 / len1;
    u2 = u2 / len2;
    dev = acosd(max(-1, min(1, dot(u1, u2))));
    interior = 180 - dev;
    if interior > angleLimitDeg + 1e-9
        out = [out; cur]; %#ok<AGROW>
        continue;
    end
    R = min([maxR, len1 / 2, len2 / 2]);
    if R <= 1e-3
        out = [out; cur]; %#ok<AGROW>
        continue;
    end
    % 内法向（指向环内侧）：CCW 环内侧在边左侧，CW 环在右侧
    if ccw
        n1 = [-u1(2), u1(1)];
        n2 = [-u2(2), u2(1)];
    else
        n1 = [u1(2), -u1(1)];
        n2 = [u2(2), -u2(1)];
    end
    t1 = cur - R * u1; % 切点（入边）
    t2 = cur + R * u2; % 切点（出边）
    % 圆心 = 两条偏移线交点：t1 + R*n1 + s*u1 = t2 + R*n2 + t*u2
    M = [u1(1), -u2(1); u1(2), -u2(2)];
    rhs = (t2 - t1 + R * (n2 - n1)).';
    st = M \ rhs;
    C = t1 + R * n1 + st(1) * u1;
    % 圆弧从 t1 到 t2（短弧）
    a1 = atan2(t1(2) - C(2), t1(1) - C(1));
    a2 = atan2(t2(2) - C(2), t2(1) - C(1));
    dAng = a2 - a1;
    while dAng > pi
        dAng = dAng - 2 * pi;
    end
    while dAng < -pi
        dAng = dAng + 2 * pi;
    end
    angs = a1 + dAng * (0:nArc).' / nArc;
    arc = C + R * [cos(angs), sin(angs)];
    out = [out; arc]; %#ok<AGROW>  % 圆弧包含 t1..t2，替代尖角顶点
end
out = [out; out(1, :)]; % 闭合
xy = out;
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
% 奇数序号活动层从 connectionAngleDeg 相位起绕（CCW），偶数层相近相位反向绕（CW），
% 俯视电流同向叠加；4/4 采用分数匝（L2 +0.25、L4 -0.25 圈跨度）使内端落在过孔轴线。
% 外端过孔延伸区：线圈最外圈沿径向向外延伸 eff.viaEndExtension，过孔落在延伸端，
% 焊环避开相邻匝（不影响线距/匝数），板框自动计入延伸区。
coils = cell(1, cfg.boardLayerCount);
rStart = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2;
% 4/4 分数匝（用户设计约定）：L2 多绕 1/4 圈使内端直接落到 225° 的 V23，
% L4 少绕 1/4 圈使内端直接落到 135° 的 VOUT——内端无任何过渡走线，
% 全部铜箔均为同心螺旋，且四层平均匝数恰为 turnsPerCoilLayer（8 匝）。
is44 = cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4;
spanExtra = [0, 0.25, 0, -0.25];
phaseExtra = [0, 90, 90, 0];
for p = 1:numel(activeLayers)
    li = activeLayers(p);
    spanTurns = cfg.turnsPerCoilLayer - 1 + spanExtra(p) * is44;
    phaseDeg = cfg.connectionAngleDeg + phaseExtra(p) * is44 ...
        + 90 * floor((p - 1) / 2) * (~is44);
    span = 2 * pi * spanTurns; % 角跨度（分数匝时含 +90°）
    n = round(cfg.samplePointsPerTurn * spanTurns) + 1;
    th = linspace(0, span, n);
    if directions(p) < 0
        % 偶数层镜像绕制（角度随半径增大而减小）：翻转点序后电流从外端流向内端时
        % 俯视仍为 CCW，与奇数层磁场叠加；直接 flipud 会使电流反向环绕、磁场相消。
        ang = deg2rad(phaseDeg) - th;
    else
        ang = deg2rad(phaseDeg) + th;
    end
    r = rStart + eff.coilPitch * th / (2 * pi);
    xy = [r .* cos(ang); r .* sin(ang)].';
    if directions(p) < 0
        xy = flipud(xy); % 翻转点序，使起点在半径大的一端（接外层过渡过孔）
    end
    % 外端延伸：用 110° 外向圆弧从线圈切线平滑转向板外，过孔落在圆弧终点。
    % 转角严格大于 90°，同时明显小于旧 180° 回头弧，形成连续的切向/泪滴式接入。
    % 奇数层外端为末点，偶数层外端为首点。
    E = eff.viaEndExtension;
    % 每个外端通孔由串联方向上游的奇数序号线圈直接形成接触弧；下游偶数序号层
    % 从同一过孔接到其原始螺旋外端。若两层都各做一条外伸弧，反向绕制会令两条
    % 接触弧分居过孔两侧，并迫使下游连接再次向外回钩。
    if E > 0 && directions(p) > 0
        nArc = 45;
        outerEnd = xy(end, :);
        a = xy(end, :) - xy(end - 1, :);
        ext = smoothOutwardArc(outerEnd, a / norm(a), E, nArc);
        xy = [xy; ext(2:end, :)];
    end
    coils{li} = xy;
end
end

function xy = smoothOutwardArc(S, a, E, n)
% 平滑外伸接触弧：从线圈外端 S 沿切线方向 a 出发，以 110° 圆弧转向板外。
% 圆弧终点就是过孔中心；径向外移量严格为 E。110° 满足全局“内角必须
% 严格大于 90°”的接触要求，又避免旧 180° 方案在钻孔旁形成回头钩。
uLoc = S / norm(S);
a = a / norm(a);
n1 = [-a(2), a(1)];
n2 = [a(2), -a(1)];
if dot(n1, uLoc) >= dot(n2, uLoc)
    nOut = n1;
    turn = 1;
else
    nOut = n2;
    turn = -1;
end
sweep = deg2rad(110);
% 任意扫角 phi 的总位移为 R*((1-cos(phi))*nOut + sin(phi)*a)；
% 按径向投影反求 R，使外移量恰为 E。
unitDisplacement = (1 - cos(sweep)) * nOut + sin(sweep) * a;
radialGain = dot(unitDisplacement, uLoc);
if radialGain <= 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        'Outer via contact arc cannot obtain a positive radial extension.');
end
R = E / radialGain;
C = S + R * nOut;
v0 = S - C;
alpha = turn * linspace(0, sweep, n).';
ca = cos(alpha);
sa = sin(alpha);
v = [ca * v0(1) - sa * v0(2), sa * v0(1) + ca * v0(2)];
xy = C + v;
xy(1, :) = S; % 起点精确 = 线圈外端
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
% 外端通孔的下游层也从同一孔中心离开，并以单一圆弧切向并入下一层螺旋。
% 自动选择 90°~150° 内最接近 120° 的圆弧，保证接触角严格大于 90°，
% 且不再用直线弦或贝塞尔微调段制造锐角/回头钩。
[coils, vias] = attachDownstreamOuterViaArcs(cfg, activeLayers, coils, vias);
% 4/4 内端延伸（用户设计约定）：L2/L4 的内端经 180° 内弯弧直接延伸到
% V23/VOUT 中心，L3 的起点前置同样的内弯弧——过孔落在线圈端点上，
% 无任何过渡走线（全部铜箔为同心螺旋 + 过孔处的径向微连接）。
coils = applyInnerExtensions(cfg, activeLayers, coils, vias);
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

function [coils, vias] = attachDownstreamOuterViaArcs(cfg, activeLayers, coils, vias)
angleFloor = cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg;
for p = 1:numel(activeLayers) - 1
    if mod(p, 2) ~= 1
        continue;
    end
    fromLayer = activeLayers(p);
    toLayer = activeLayers(p + 1);
    name = sprintf('V%d%d', fromLayer, toLayer);
    v = vias(strcmp({vias.name}, name));
    if isempty(v)
        continue;
    end
    q = coils{toLayer};
    if size(q, 1) < 6
        continue;
    end
    maxIndex = min(size(q, 1) - 1, 24);
    bestScore = inf;
    bestIndex = 0;
    bestArc = zeros(0, 2);
    bestSweepDeg = NaN;
    for i = 2:maxIndex
        tangent = q(i + 1, :) - q(i, :);
        [arc, sweepDeg] = tangentCircularArc(v.xy, q(i, :), tangent, 73);
        if isempty(arc)
            continue;
        end
        score = abs(sweepDeg - 120) + 0.02 * i;
        if sweepDeg <= angleFloor || sweepDeg > 150
            % 自动板径/过孔外移迭代的早期轮次可能暂时没有严格可行弧；
            % 保留一个候选让引擎测量并继续增大 E，但优先级远低于 90.1°~150° 弧。
            score = score + 1e4;
        end
        if score < bestScore
            bestScore = score;
            bestIndex = i;
            bestArc = arc;
            bestSweepDeg = sweepDeg;
        end
    end
    if bestIndex == 0
        error('CircularFPC:GeometryInfeasible', ...
            'No >90-degree circular via contact can join %s to layer %d.', name, toLayer);
    end
    coils{toLayer} = [bestArc(1:end - 1, :); q(bestIndex:end, :)];
    viaIndex = find(strcmp({vias.name}, name), 1);
    vias(viaIndex).contactSweepDeg = bestSweepDeg;
end
end

function [xy, sweepDeg] = tangentCircularArc(p0, p1, tangentAtEnd, n)
% 过 p0/p1 且在 p1 与给定切线同向的唯一圆弧。圆心位于 p1 的法线上；
% 扫角方向由终点切向决定，因此接到螺旋时具有一阶方向连续性。
xy = zeros(0, 2);
sweepDeg = NaN;
if norm(p1 - p0) <= 1e-12 || norm(tangentAtEnd) <= 1e-12
    return;
end
tangentAtEnd = tangentAtEnd / norm(tangentAtEnd);
normal = [-tangentAtEnd(2), tangentAtEnd(1)];
d = p0 - p1;
denom = 2 * dot(d, normal);
if abs(denom) <= 1e-12
    return;
end
lambda = dot(d, d) / denom;
center = p1 + lambda * normal;
v0 = p0 - center;
v1 = p1 - center;
ccwSweep = atan2(v0(1) * v1(2) - v0(2) * v1(1), dot(v0, v1));
if ccwSweep < 0
    ccwSweep = ccwSweep + 2 * pi;
end
ccwEndTangent = [-v1(2), v1(1)];
if dot(ccwEndTangent, tangentAtEnd) >= 0
    turn = 1;
    sweep = ccwSweep;
else
    turn = -1;
    sweep = 2 * pi - ccwSweep;
end
sweepDeg = rad2deg(sweep);
alpha = turn * linspace(0, sweep, n).';
ca = cos(alpha);
sa = sin(alpha);
rotated = [ca * v0(1) - sa * v0(2), sa * v0(1) + ca * v0(2)];
xy = center + rotated;
xy(1, :) = p0;
xy(end, :) = p1;
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
    path = buildConstrainedTracePath(name, p0, p3, tan0, tan1, cfg, ...
        routeInfo.layoutRegions, routeInfo);
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
    rPad = searchPadCenterRadius(cfg, layoutRegions, coils); % 焊盘对中心沿入口桥轴搜索
    pairCenter = rPad * u;
    padA = pairCenter - (cfg.terminalLeadSpacing / 2) * t; % 切向负侧为 PAD_A
    padB = pairCenter + (cfg.terminalLeadSpacing / 2) * t; % 切向正侧为 PAD_B
    % VOUT 位于焊盘对与线圈之间：下限 = rPad + 与 PAD_B 的净距约束
    deltaVout = sqrt(max(0, (cfg.padDiameter / 2 + cfg.viaPadDiameter / 2 + cfg.terminalClearance)^2 - ...
        (cfg.terminalLeadSpacing / 2 - layoutRegions.laneOffset)^2));
    rVout = searchSafeRadiusOnAxis(cfg, layoutRegions, u, t, layoutRegions.laneOffset, ...
        cfg.viaPadDiameter / 2, layoutRegions.rStart - 0.36, rPad + deltaVout + 0.02, coils);
    rV23 = NaN;
    if numel(activeLayers) == 4 && activeLayers(end) == 4
        % 4/4 的 V23 位于 theta+90 桥轴上、L1 在该角度相邻匝的内切位置：
        % 焊环边缘距 L1 铜边 = viaCoilSpacing（与 VOUT 同款约束）；
        % L2 的内端延伸弧直接落到 V23 中心（无过渡走线，用户设计约定）。
        % clamp 下限：禁止公式在极端参数下为负（负值会让过孔跑到对侧轴线）。
        % V23 also drills through the unconnected L1/L4 copper.  Its radial
        % offset must therefore satisfy the larger of the connected-layer
        % via-pad clearance and the unconnected-layer antipad envelope.
        keepoutR = max(cfg.viaCoilSpacing + cfg.viaPadDiameter / 2, ...
            cfg.antipadDiameter / 2);
        rV23 = max(0.1, layoutRegions.rStart - (keepoutR + ...
            cfg.traceWidth / 2 + 1e-3) + 0.25 * eff.coilPitch);
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
    pads(1).placementRegion = 'ENTRY_BRIDGE'; % 焊盘位于入口桥（外围圆环与中央矩形之间的连接区）
    pads(1).bridgeAngleDeg = theta;
    pads(2).placementRegion = 'ENTRY_BRIDGE';
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
                viaAngles(end + 1) = theta + 90; %#ok<AGROW> % V34 位于 theta+90 桥侧（L3/L4 相位组）
            else
                viaAngles(end + 1) = theta; %#ok<AGROW>
            end
        else
            viaRoles{end + 1} = 'INNER_TRANSITION'; %#ok<AGROW>
            viaXY(end + 1, :) = rV23 * t; %#ok<AGROW> % theta+90（默认 225°）桥轴
            viaRegions{end + 1} = 'RETURN_BRIDGE'; %#ok<AGROW>
            viaAngles(end + 1) = theta + 90; %#ok<AGROW>
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
    'placementRegion', {}, 'bridgeAngleDeg', {}, 'contactSweepDeg', {});
for k = 1:nVias
    vias(k).name = viaNames{k};
    vias(k).xy = viaXY(k, :);
    vias(k).drillDiameter = cfg.viaDrillDiameter;
    vias(k).padDiameter = cfg.viaPadDiameter;
    vias(k).fromLayer = viaLayers(k, 1);
    vias(k).toLayer = viaLayers(k, 2);
    vias(k).isOutputReturn = strcmp(viaNames{k}, 'VOUT');
    vias(k).role = viaRoles{k};
    vias(k).contactSweepDeg = NaN;
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
boardEdgeInnerR = outerR - cfg.boardOutlineLineWidth / 2;
holes = layoutRegions.holeLoops;
[names, xy, radii] = terminalArrays(pads, vias);
for i = 1:numel(names)
    pxy = xy(i, :);
    r = radii(i);
    if ~isnumeric(pxy) || numel(pxy) ~= 2 || ~all(isfinite(pxy))
        error('CircularFPC:TerminalPlacementInvalid', 'Terminal %s has invalid coordinates.', names{i});
    end
    % 这里只拒绝真正越过板框实体；具体 0.30 mm 工艺净距由
    % validate_result 的切线测量统一判定，避免 fixed 模式在构造阶段
    % 抢先抛出与最终验证不同的错误类型。
    if norm(pxy) + r > boardEdgeInnerR + 1e-9
        error('CircularFPC:TerminalPlacementInvalid', ...
            'Terminal %s violates tangent-to-board clearance.', names{i});
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
            abs(norm(pads(2).xy - pads(1).xy) - cfg.terminalLeadSpacing) > 1e-6
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
        % V23 位于 theta+90 桥轴（+t 方向）：垂直分量（u 投影）必须为零
        if numel(v23) ~= 1 || abs(dot(v23(1).xy, layoutRegions.u)) > 1e-6
            error('CircularFPC:TerminalPlacementInvalid', ...
                'Automatic V23 violates the theta+90 bridge axis contract.');
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

function path = buildConstrainedTracePath(name, p0, p3, tan0, tan1, cfg, lr, ri)
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
    R3 = lane; % 终弧半径 = 通道半距，保证弧线终点精确落在线圈内端（硬编码值在通道变宽时会偏离）
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
    % V23(theta+90 轴) → L3 内端(theta+90)：同轴径向局部连接，末端切向对齐线圈 CCW 切向
    path = sampleBezier(ri.rV23 * t, t, rStart * t, -u, 0.6, 0.6, 257);
elseif strcmp(name, 'TRACE_L2_IN') || strcmp(name, 'TRACE_L4_IN')
    % 外端配对层接入：终点必须沿 nextCoil 的实际首段切向进入。
    % 自动圆弧会改变首段方向，不能再按旧 180° 方案硬编码为顺时针切向。
    % 控制长度取 0.35·弦长（刻意偏小，收紧横向摆幅，避免侵入外层匝间走廊——
    % 0.55·弦长在极限档小过孔下实测铜间距 0.1383 < traceSpacing）。
    chord = norm(p3 - p0);
    if isempty(tan1) || norm(tan1) <= 1e-12
        tan1 = p3 - p0;
    end
    Lc = 0.35 * chord;
    path = sampleBezier(p0, p3 - p0, p3, tan1, Lc, Lc, 129);
elseif strcmp(name, 'TRACE_L4_OUT')
    % 分数匝方案下 L4 的内端延伸弧已并入线圈折线、直接落在 VOUT 中心，
    % 本分支仅作兜底（2/2 等组合的本地短贝塞尔，控制长度随弦长自适应）。
    chord = norm(ri.voutXY - p0);
    Lc = 0.8 * min(chord, 1.0);
    path = sampleBezier(p0, t, ri.voutXY, -u, Lc, Lc, 129);
elseif strcmp(name, 'TRACE_L2_OUT')
    % 分数匝方案下 L2 的内端延伸弧已并入线圈折线、直接落在 V23 中心，
    % 本分支仅作兜底（起点切向对齐线圈到达切向，避免接头折角）。
    chord = norm(p3 - p0);
    Lc = 0.8 * min(chord, 1.0);
    path = sampleBezier(p0, t, p3, -u, Lc, Lc, 129);
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

function coils = applyInnerExtensions(cfg, activeLayers, coils, vias)
% 4/4 内端延伸（用户设计约定）：L2 多绕 1/4 圈后内端落在 225°，经 180° 内弯
% 弧延伸到 V23 中心；L3 的起点前置反向内弯弧从 V23 出发；L4 少绕 1/4 圈后
% 内端落在 135°，经短贝塞尔延伸到 VOUT——过孔直接落在线圈端点上，
% 无任何过渡走线（全部铜箔为同心螺旋 + 过孔处的径向微连接）。
if ~(cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4)
    return;
end
v23 = vias(strcmp({vias.name}, 'V23'));
vout = vias(strcmp({vias.name}, 'VOUT'));
L2 = activeLayers(2);
L3 = activeLayers(3);
L4 = activeLayers(end);
% L2 内端 → V23（180° 内弯弧，镜像外端延伸区；E 已含 clamp 保证 >0）
S = coils{L2}(end, :);
a = S - coils{L2}(end - 1, :);
a = a / norm(a);
E = norm(v23.xy - S);
ext = smoothInwardArc(S, a, max(E, 1e-6), 61);
coils{L2} = [coils{L2}; ext(2:end, :)];
% L3 起点 ← V23（前置反向内弯弧）：弧以 CW 切向离开 S3，反转后到达 S3 的
% 方向恰为 CCW 切向 a3，与螺旋起点切向对齐（直接用 a3 会反转 180°）
S3 = coils{L3}(1, :);
a3 = coils{L3}(2, :) - coils{L3}(1, :);
a3 = a3 / norm(a3);
E3 = norm(S3 - v23.xy);
arc3 = smoothInwardArc(S3, -a3, max(E3, 1e-6), 61);
coils{L3} = [flipud(arc3); coils{L3}(2:end, :)];
% L4 内端 → VOUT（短贝塞尔：VOUT 带 lane 侧偏，终点切向取自然趋近方向）
S4 = coils{L4}(end, :);
a4 = S4 - coils{L4}(end - 1, :);
a4 = a4 / norm(a4);
dBack = vout.xy - S4;
dBack = dBack / norm(dBack);
stub = sampleBezier(S4, a4, vout.xy, dBack, 0.3, 0.3, 97);
coils{L4} = [coils{L4}; stub(2:end, :)];
end

function xy = smoothInwardArc(S, a, E, n)
% 内端延伸弧（镜像 smoothOutwardArc）：从线圈内端 S 沿切向 a 经 180° 圆弧
% 过渡到径向向内，终点位于 S - E·uLoc（uLoc 为 S 的径向单位向量），
% 内端过孔（V23/VOUT）落在弧终点。180° 弧采样密度保证逐点偏转角 < 10°。
uLoc = S / norm(S);
tLoc = [-uLoc(2), uLoc(1)];
R = E / 2;
n1 = [-a(2), a(1)];
n2 = [a(2), -a(1)];
if dot(n1, -uLoc) >= dot(n2, -uLoc)
    C = S + R * n1; turn = 1;
else
    C = S + R * n2; turn = -1;
end
v = S - C;
phi0 = atan2(dot(v, tLoc), dot(v, uLoc));
phis = phi0 + deg2rad(180) * turn * (0:n - 1).' / (n - 1);
xy = C + R * (cos(phis) * uLoc + sin(phis) * tLoc);
xy(1, :) = S;
xy(end, :) = S - E * uLoc;
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

function rPad = searchPadCenterRadius(cfg, lr, coils)
% 焊盘对中心沿入口桥轴搜索，两阶段：
%   第一优先（经典布局）：平台外沿、贴近平台角部的桥区，自内向外扫描；
%   回退（大平台吞没桥轴内侧区段，如 13 x 14）：在平台板面上自外向内取位，
%   并额外为 VOUT 预留 delta+0.04 径向窗口。
% 两阶段共用同一合法性检查：焊盘位于板内（不在挖空槽中）、与孔槽保持
% edgeClearance + 0.02 净距、与线圈保持 DRC 焊盘-走线净距；铜-槽净距
% 最终由 validate_result 实测把关。旧版"必须在平台外"硬约束会误杀大平台配置。
u = lr.u;
t = lr.t;
holes = lr.holeLoops;
half = cfg.terminalLeadSpacing / 2;
req = cfg.padDiameter / 2 + cfg.edgeClearance + 0.02;
reqCoilPad = cfg.padDiameter / 2 + cfg.traceWidth / 2 + cfg.viaCoilSpacing; % 焊盘边到线圈铜边
outerLimit = lr.outerRadius - cfg.boardOutlineLineWidth / 2 - cfg.edgeClearance - cfg.padDiameter / 2;
% VOUT 需位于焊盘对（±half·t）与线圈之间：rPad + delta <= rStart - reqCoil
delta = sqrt(max(0, (cfg.padDiameter / 2 + cfg.viaPadDiameter / 2 + cfg.terminalClearance)^2 - ...
    (half - lr.laneOffset)^2));
reqCoilV = max(cfg.traceWidth + cfg.traceSpacing, ...
    cfg.viaPadDiameter / 2 + cfg.traceWidth / 2 + cfg.viaCoilSpacing) + 0.02;
rHigh = lr.rStart - reqCoilV - delta - 0.02;
% 平台沿入口桥轴方向的延伸半径（platformLoop 包围盒反推），决定第一阶段的起点。
xyP = lr.platformLoop;
halfW = max(abs(xyP(:, 1)));
halfH = max(abs(xyP(:, 2)));
platExtent = Inf;
if abs(u(1)) > 1e-9
    platExtent = min(platExtent, halfW / abs(u(1)));
end
if abs(u(2)) > 1e-9
    platExtent = min(platExtent, halfH / abs(u(2)));
end
found = NaN;
for r = (platExtent + 0.02):0.02:rHigh % 阶段一：平台外、自内向外（贴近平台角部）
    if padFeasible(r, lr, coils, u, t, half, req, reqCoilPad, outerLimit, holes)
        found = r;
        break;
    end
end
if isnan(found)
    % 阶段二回退：平台上自外向内。额外预留 0.44 = delta + 0.04 + 0.4（入口弧
    % 半径 R1）：焊盘下移让 VOUT 半径落在入口走线负通道的直线段内，
    % 否则 TRACE_L1_ENTRY 的过渡弧会顶到 VOUT 半径处、破坏双通道契约。
    for r = (rHigh - delta - 0.44):-0.02:1.0
        if padFeasible(r, lr, coils, u, t, half, req, reqCoilPad, outerLimit, holes)
            found = r;
            break;
        end
    end
end
if isnan(found)
    error('CircularFPC:TerminalPlacementInvalid', ...
        'No safe automatic pad pair position on the entry bridge (pad pair/entry bridge).');
end
rPad = found;
end

function tf = padFeasible(r, lr, coils, u, t, half, req, reqCoilPad, outerLimit, holes)
% 单个焊盘对中心候选半径的合法性检查（PAD_A/PAD_B 对称取 ±half·t）。
pA = r * u - half * t;
pB = r * u + half * t;
tf = false;
if norm(pA) > outerLimit || norm(pB) > outerLimit
    return;
end
if ~isinterior(lr.boardShape, pA(1), pA(2)) || ~isinterior(lr.boardShape, pB(1), pB(2))
    return; % 焊盘必须位于板内（不能落在挖空槽中）
end
if minDistanceToHolesLocal(pA, holes) < req || minDistanceToHolesLocal(pB, holes) < req
    return;
end
if minDistanceToHolesLocal(pA, coils) < reqCoilPad || minDistanceToHolesLocal(pB, coils) < reqCoilPad
    return; % 焊盘不得压到线圈走线（含线圈匝间无法容纳焊盘的情形）
end
tf = true;
end

function r = searchSafeRadiusOnAxis(cfg, lr, axisDir, latDir, tOffset, radius, rHigh, rLow, coils)
% 沿 axisDir 方向的桥轴搜索安全半径：候选点 p = rr*axisDir + tOffset*latDir。
% VOUT 沿 u 轴（lat=t），V23 沿 t 轴（lat=u，tOffset=0）。
u = lr.u;
t = lr.t;
holes = lr.holeLoops;
req = radius + cfg.edgeClearance + 0.02; % 到孔槽/板边净距
% 到线圈走线净距（铜对铜）：取 过孔规则(viaCoilSpacing) 与 走线规则(traceSpacing) 的较大者，
% 保证 VOUT 引出路径起点与线圈的走线净距检查也能通过。
reqCoil = max(cfg.traceWidth + cfg.traceSpacing, ...
    radius + cfg.traceWidth / 2 + cfg.viaCoilSpacing) + 0.02;
outerLimit = lr.outerRadius - cfg.boardOutlineLineWidth / 2 - cfg.edgeClearance - radius;
found = NaN;
for rr = rHigh:-0.02:rLow
    p = rr * axisDir + tOffset * latDir;
    if norm(p) > outerLimit
        continue;
    end
    if minDistanceToHolesLocal(p, holes) < req
        continue;
    end
    if ~isempty(coils) && minDistanceToHolesLocal(p, coils) < reqCoil
        continue; % 过孔焊环距线圈走线过近
    end
    found = rr;
    break;
end
if isnan(found)
    error('CircularFPC:TerminalPlacementInvalid', ...
        'No safe via position on the bridge axis (entry/return bridge).');
end
r = found;
end
