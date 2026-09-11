function varargout = circular_fpc_geometry(operation, varargin)
% 板框、线圈与端子几何构造（R2-R3），三个子操作：
%   'effective'  : 由 cfg 计算缩放后的有效尺寸（eff 结构体）
%   'board'      : 构造主体圆、局部过孔/安装/电极凸耳、4 槽与布局参考系
%   'network'    : 构造线圈螺旋线、连接路径、焊盘、过孔与完整串联路由
switch operation
    case 'effective'
        varargout{1} = buildEffectiveDimensions(varargin{1});
    case 'board'
        if numel(varargin) >= 3
            activeLayers = varargin{3};
        else
            activeLayers = [];
        end
        [varargout{1}, varargout{2}, varargout{3}] = ...
            buildBoardGeometry(varargin{1}, varargin{2}, activeLayers);
    case 'network'
        [varargout{1}, varargout{2}, varargout{3}, varargout{4}, varargout{5}, varargout{6}, varargout{7}] = ...
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

function [boardLoops, actualBridgeWidth, layoutRegions] = buildBoardGeometry(cfg, eff, activeLayers)
% 板框 = 圆环区（外圆减内圆）+ 中央平台 + 四条连接桥（入口桥/回流桥交替）。
% 基础主体有 5 个闭环（1 外边界 + 4 平台槽）；最终板框再加 4 个耳朵挖槽闭环。
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
% 平台水平/垂直边与内圆保留 platformSlotMargin；四角允许伸入环区，
% 并与下面同方位的四个等宽连接区共同自然形成四槽。
polys = [annulus, platP]; % 中央平台：焊盘与进出线所在的连接区
% 四条桥臂随 connectionAngleDeg 旋转，连接固定正向平台与外部环区。
% 四条桥使用同一个统一宽度；该宽度必须同时容纳目标桥宽、过孔净距、
% PAD_A/PAD_B 与 d 的端子包络及相应净距规则。
% 这里不再使用独立的解析桥宽上限；桥宽上限由下面的最终布尔结果决定。
terminalBoundaryMargin = max([cfg.edgeClearance, cfg.terminalClearance, cfg.traceSpacing]) + 0.03;
terminalEnvelopeWidth = cfg.terminalLeadSpacing + cfg.padDiameter + 2 * terminalBoundaryMargin;
routingEnvelopeWidth = eff.bridgeTargetWidth + ...
    2 * (cfg.edgeClearance + cfg.traceWidth / 2 + cfg.pitchMargin);
viaEnvelopeWidth = cfg.viaPadDiameter + 2 * cfg.edgeClearance;
constraintWidths = [routingEnvelopeWidth, viaEnvelopeWidth, terminalEnvelopeWidth];
constraintNames = {'routingEnvelope', 'viaEnvelope', 'terminalEnvelope'};
[bridgeWidth, governingIndex] = max(constraintWidths);
anglesDeg = mod(cfg.connectionAngleDeg + [-90 0 90 180], 360);
bridgeWidths = repmat(bridgeWidth, 1, 4);
for k = 1:4
    polys(end + 1) = capsulePolyshape(deg2rad(anglesDeg(k)), ...
        0.6 * min(eff.centerPlatformWidth, eff.centerPlatformHeight) / 2, ...
        outerR + 0.5, bridgeWidths(k), 360); %#ok<AGROW>
end
baseShape = intersect(union(polys), outerP);
nBoundariesBase = numboundaries(baseShape);
if nBoundariesBase ~= 5
    error('CircularFPC:GeometryInfeasible', ...
        'Base board outline must contain exactly 5 loops, got %d.', nBoundariesBase);
end

% The circular body is sized by the coil copper envelope. Local features are
% added after that sizing so a via, mounting notch, or electrode does not
% enlarge the whole circumference.
if isempty(activeLayers)
    activeLayers = defaultActiveLayers(cfg);
end
directions = ones(1, numel(activeLayers));
directions(2:2:end) = -1;
predictedCoils = buildCoils(cfg, eff, activeLayers, directions);
shape = baseShape;
viaLugCenters = zeros(0, 2);
viaLugWidth = cfg.viaPadDiameter + 2 * (cfg.edgeClearance + ...
    cfg.boardOutlineLineWidth / 2 + cfg.geometrySafetyMargin);
for p = 1:2:numel(activeLayers)
    center = predictedCoils{activeLayers(p)}(end, :);
    viaLugCenters(end + 1, :) = center; %#ok<AGROW>
    thetaVia = atan2(center(2), center(1));
    % Keep the capsule's axial length longer than its width. This avoids a
    % self-overlapping sampled stadium when the via sits just inside the
    % base-circle edge while leaving the visible outer lobe unchanged.
    rootR = max(0, min(outerR - cfg.viaLugRootOverlap, ...
        norm(center) - viaLugWidth - 0.05));
    shape = union(shape, capsulePolyshape(thetaVia, rootR, norm(center), viaLugWidth, 180));
end

mountingAnglesDeg = [0, 90, 180, 270];
mountingCount = numel(mountingAnglesDeg);
% ------------------------------------------------------------------
% 四个正方向安装耳朵 = 三段弧 + 等距外偏置外边界：
%   内侧弧：直接取主体外径圆上的一段圆弧，主体定径后自动跟随（无独立半径参数）；
%   中间弧：与内侧弧共享两端点、在耳朵中央径向轴上外凸 mountingSlotRise 的圆弧，
%           与内侧弧共同围成一个闭合挖槽；
%   最外侧弧：中间弧按 mountingSlotEdgeClearance 同心外偏的等距弧（半径 +clearance），
%           形成耳朵外边界；外偏弧与主体圆之间的连接板料自然保留。
% 三段弧仅由「槽口跨度 + 外凸高度 + 槽到板边距离」唯一确定：跨度给出端点半张角，
% 外凸高度（以主体圆中央点为基准）给出中间弧圆心与半径。
mountingSlotSpec = mountingSlotGeometry(outerR, cfg.mountingSlotSpan, ...
    cfg.mountingSlotRise, cfg.mountingSlotEdgeClearance);
mountingSlotEndpoints = zeros(2 * mountingCount, 2);
mountingEarRootPoints = zeros(2 * mountingCount, 2);
mountingRootAnglesDeg = zeros(mountingCount, 2);
for k = 1:mountingCount
    thetaMount = deg2rad(mountingAnglesDeg(k));
    uMount = [cos(thetaMount), sin(thetaMount)];
    tMount = [-sin(thetaMount), cos(thetaMount)];
    localToGlobal = [uMount; tMount];
    slotLocal = mountingSlotLoopLocal(mountingSlotSpec, ...
        cfg.mountingSlotEndFilletRadius, 96);
    earLocal = mountingEarLoopLocal(mountingSlotSpec, 96);
    shape = union(shape, polyshape(earLocal * localToGlobal));
    % 槽口两端已在 mountingSlotLoopLocal 内做相切圆角；此处不再二次圆角，
    % 避免把主体圆弧与中间弧的解析关系再近似一次。
    shape = subtract(shape, polyshape(slotLocal * localToGlobal));
    mountingSlotEndpoints(2 * k - 1:2 * k, :) = ...
        mountingSlotSpec.endpointLocal * localToGlobal;
    mountingEarRootPoints(2 * k - 1:2 * k, :) = ...
        mountingSlotSpec.rootPointLocal * localToGlobal;
    mountingRootAnglesDeg(k, :) = mountingAnglesDeg(k) + ...
        [-mountingSlotSpec.rootHalfSpanDeg, mountingSlotSpec.rootHalfSpanDeg];
end

electrodePads = buildElectrodePads(cfg, outerR);
electrodeOffsets = (cfg.electrodeArmGap + cfg.electrodeArmWidth) / 2 * [-1, 1];
for k = 1:2
    offset = electrodeOffsets(k);
    shape = union(shape, shiftedCapsulePolyshape(deg2rad(cfg.electrodeAngleDeg), ...
        outerR - cfg.electrodeRootOverlap, outerR + cfg.electrodeArmLength, ...
        cfg.electrodeArmWidth, offset, 180));
    padEnvelope = polyshape(sampleCircle(electrodePads(k).xy(1), electrodePads(k).xy(2), ...
        electrodePads(k).diameter / 2 + cfg.edgeClearance + ...
        cfg.boardOutlineLineWidth / 2 + cfg.geometrySafetyMargin, 96));
    shape = union(shape, padEnvelope);
end
nBoundaries = numboundaries(shape);
% 最终板框包含 1 个外边界、4 个平台槽和 4 个耳朵内置挖槽闭环。
% 任一槽实际消失、合并或被分裂时，numboundaries 会偏离 9，此处明确失败；
% 不静默截断桥宽，也不使用与最终图形脱节的先验上限。
if nBoundaries ~= 9
    error('CircularFPC:GeometryInfeasible', ...
        ['Board outline must contain exactly 9 loops (1 outer + 4 slots + 4 ', ...
         'mounting cutouts), got %d. ', ...
         'The final Boolean geometry has reached the bridge-width/d/platform ', ...
         'topology limit: one or more slots/cutouts disappeared, merged, or split for ', ...
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
outerXY = filletHoleCorners(bnd{outerIdx}, 0.3, 170, 20);
holeIdx = setdiff(1:numel(bnd), outerIdx);
cents = zeros(numel(holeIdx), 2);
for j = 1:numel(holeIdx)
    cents(j, :) = mean(bnd{holeIdx(j)}(1:end - 1, :), 1);
end
% The four ear slots reach radially beyond the main body circle (their middle
% arc apex sits at outerR + mountingSlotRise), while the four platform/bridge
% slots stay entirely inside the base circle.  Classifying by the loop's
% farthest radius is independent of slot angle and stays stable when turns or
% connectionAngleDeg change.
holeReach = zeros(numel(holeIdx), 1);
for j = 1:numel(holeIdx)
    holeReach(j) = max(hypot(bnd{holeIdx(j)}(:, 1), bnd{holeIdx(j)}(:, 2)));
end
isMountingCutout = holeReach > outerR + 0.5 * cfg.mountingSlotRise;
slotIdx = holeIdx(~isMountingCutout);
mountingIdx = holeIdx(isMountingCutout);
if numel(slotIdx) ~= 4 || numel(mountingIdx) ~= 4
    error('CircularFPC:GeometryInfeasible', ...
        'Expected 4 platform slots and 4 mounting cutouts, got %d and %d.', ...
        numel(slotIdx), numel(mountingIdx));
end
slotCents = cents(~isMountingCutout, :);
mountingCents = cents(isMountingCutout, :);
[~, slotOrd] = sort(atan2d(slotCents(:, 2), slotCents(:, 1)));
boardLoops = struct('name', {}, 'isHole', {}, 'xy', {}, 'orientation', {});
boardLoops(1).name = 'outer';
boardLoops(1).isHole = false;
boardLoops(1).xy = outerXY;
boardLoops(1).orientation = signedArea(outerXY);
for j = 1:numel(slotIdx)
    h = slotIdx(slotOrd(j));
    hxy = bnd{h};
    % 自动识别槽边界（圆环弧 × 平台边 × 桥侧）的离散硬折角，并用
    % 最大 0.3 mm 的相切圆弧轻微圆角化；中央平台基准仍是正向矩形。
    hxy = filletHoleCorners(hxy, 0.3, 170, 20);
    boardLoops(j + 1).name = sprintf('hole_%d', j);
    boardLoops(j + 1).isHole = true;
    boardLoops(j + 1).xy = hxy;
    boardLoops(j + 1).orientation = signedArea(hxy);
end
% 耳朵挖槽按 mountingAnglesDeg 的 0/90/180/270 顺序命名，使
% mounting_cutout_%d 与 mountingAnglesDeg(k)、mountingSlotEndpoints 一一对应。
% 分类判据是各自顶点方向与 4 个安装角的最小夹角，与布尔输出顺序无关。
mountingSlotApexAngles = zeros(numel(mountingIdx), 1);
for j = 1:numel(mountingIdx)
    hxyProbe = bnd{mountingIdx(j)};
    holeRadius = hypot(hxyProbe(:, 1), hxyProbe(:, 2));
    [~, apexIdx] = max(holeRadius);
    mountingSlotApexAngles(j) = atan2d(hxyProbe(apexIdx, 2), hxyProbe(apexIdx, 1));
end
mountingOrder = zeros(numel(mountingIdx), 1);
for k = 1:numel(mountingAnglesDeg)
    angleError = abs(mod(mountingSlotApexAngles - mountingAnglesDeg(k) + 180, 360) - 180);
    [minError, bestIdx] = min(angleError);
    if minError > 5
        error('CircularFPC:GeometryInfeasible', ...
            ['Mounting cutout for the %.1f deg ear is %.3f deg away from that direction; ', ...
             'the ear cutouts can no longer be mapped to the four mounting angles.'], ...
            mountingAnglesDeg(k), minError);
    end
    mountingOrder(k) = mountingIdx(bestIdx);
    mountingSlotApexAngles(bestIdx) = NaN; % 每个角只匹配一个挖槽
end
for j = 1:numel(mountingOrder)
    h = mountingOrder(j);
    % 耳朵挖槽两端已按 mountingSlotEndFilletRadius 解析相切圆角化，
    % 此处仅作为安全网（无内角 <= 170° 的折角时不做改动）。
    hxy = filletHoleCorners(bnd{h}, cfg.mountingSlotEndFilletRadius, 170, 20);
    boardLoops(j + 5).name = sprintf('mounting_cutout_%d', j);
    boardLoops(j + 5).isHole = true;
    boardLoops(j + 5).xy = hxy;
    boardLoops(j + 5).orientation = signedArea(hxy);
end
% 实际桥宽 = 相邻孔槽之间的最窄距离（连接桥咽喉宽度）。
% stride 必须为 1：稀疏重连的折线是弦近似，而该值是硬验证门槛
% （actualBridgeWidthMm >= bridgeTargetWidth），不允许近似误差。
actualBridgeWidth = inf;
for j = 1:4
    d = polylineDistance(boardLoops(j + 1).xy, boardLoops(mod(j, 4) + 2).xy, 1);
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
layoutRegions.routingEnvelopeWidth = routingEnvelopeWidth;
layoutRegions.viaEnvelopeWidth = viaEnvelopeWidth;
layoutRegions.bridgeGoverningConstraint = constraintNames{governingIndex};
layoutRegions.holeLoops = {boardLoops(2:end).xy};
layoutRegions.outerRadius = outerR;
layoutRegions.baseOuterRadius = outerR;
layoutRegions.baseBoardShape = baseShape;
layoutRegions.rStart = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2; % 线圈最内圈中心半径
layoutRegions.boardShape = shape;
layoutRegions.platformShape = platP;
[platformX, platformY] = boundary(platP);
platformLoop = [platformX, platformY];
if norm(platformLoop(1, :) - platformLoop(end, :)) > 1e-12
    platformLoop(end + 1, :) = platformLoop(1, :);
end
layoutRegions.platformLoop = platformLoop;
layoutRegions.viaLugCenters = viaLugCenters;
layoutRegions.viaLugAnglesDeg = mod(atan2d(viaLugCenters(:, 2), viaLugCenters(:, 1)), 360);
layoutRegions.viaLugWidth = viaLugWidth;
layoutRegions.mountingAnglesDeg = mountingAnglesDeg;
layoutRegions.mountingSlotSpan = mountingSlotSpec.span;
layoutRegions.mountingSlotRise = mountingSlotSpec.rise;
layoutRegions.mountingSlotEdgeClearance = mountingSlotSpec.edgeClearance;
layoutRegions.mountingSlotEndFilletRadius = cfg.mountingSlotEndFilletRadius;
layoutRegions.mountingSlotInnerArcRadius = outerR; % 内侧弧 = 主体外径圆，精确重合
layoutRegions.mountingSlotMiddleArcRadius = mountingSlotSpec.midArcRadius;
layoutRegions.mountingSlotMiddleArcCenterRadius = mountingSlotSpec.midCenterR;
layoutRegions.mountingSlotOuterArcRadius = mountingSlotSpec.outerArcRadius;
layoutRegions.mountingSlotApexRadius = outerR + mountingSlotSpec.rise;
layoutRegions.mountingEarApexRadius = mountingSlotSpec.outerArcRadius + ...
    mountingSlotSpec.midCenterR;
layoutRegions.mountingSlotHalfSpanDeg = mountingSlotSpec.halfSpanDeg;
layoutRegions.mountingRootAnglesDeg = mountingRootAnglesDeg;
layoutRegions.mountingSlotEndpoints = mountingSlotEndpoints; % 8x2：[P-, P+] 按耳朵交替
layoutRegions.mountingEarRootPoints = mountingEarRootPoints; % 8x2：[J-, J+] 按耳朵交替
layoutRegions.electrodePads = electrodePads;
layoutRegions.boardExtent = max(sqrt(sum(outerXY.^2, 2)));
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
xy = xy([true; vecnorm(diff(xy, 1, 1), 2, 2) > 1e-12], :);
ps = polyshape(xy);
end

function ps = shiftedCapsulePolyshape(theta, r1, r2, width, tangentialOffset, nArc)
base = capsulePolyshape(theta, r1, r2, width, nArc);
[x, y] = boundary(base);
xy = [x, y];
t = [-sin(theta), cos(theta)];
xy = xy + tangentialOffset * t;
ps = polyshape(xy);
end

function spec = mountingSlotGeometry(outerR, span, rise, edgeClearance)
% 三段弧安装耳朵的解析几何（全部由「槽口跨度 + 外凸高度 + 槽到板边距离」确定）：
%   内侧弧：半径 = 主体外径圆半径 outerR、圆心 = 板中心。端点 P± 关于耳朵径向轴
%           对称，半张角 A 由弦长约等于跨度确定：2*outerR*sin(A) = span。
%   中间弧：过 P±、且在耳朵径向轴上外凸 rise 的圆弧。外凸高度以主体圆中央点为
%           基准，即外侧顶点 Q = (outerR + rise)*u 在弧上。设圆心 C 位于轴上半径 c
%           处、半径 R，由 |Q - C| = R 与 |P± - C| = R 联立解得
%               c = rise * (2*outerR + rise) / (2 * (rise + outerR * (1 - cos A)))
%               R = outerR + rise - c
%           （恒有 0 < c < outerR + rise，故 R > 0 对任意合法参数成立）。
%   最外侧弧：与中间弧同心、半径 R + edgeClearance 的等距弧，形成耳朵外边界。
% 耳朵区域 = 该等距弧与主体外径圆围成的外凸月牙；耳朵与主体以 J± 处的横切相接，
% 连接板料为正，根部折角由板框统一相切圆角规则平滑（见 mountingEarLoopLocal）。
if ~isscalar(outerR) || ~isscalar(span) || ~isscalar(rise) || ...
        ~isscalar(edgeClearance) || ~all(isfinite([outerR, span, rise, edgeClearance]))
    error('CircularFPC:GeometryInfeasible', ...
        'Mounting slot parameters must be finite scalars.');
end
if outerR <= 0
    error('CircularFPC:GeometryInfeasible', 'Board outer radius must be positive.');
end
if span <= 0
    error('CircularFPC:GeometryInfeasible', ...
        'mountingSlotSpan must be positive (got %.6f mm).', span);
end
if rise <= 0
    error('CircularFPC:GeometryInfeasible', ...
        ['mountingSlotRise must be positive (got %.6f mm): the notch middle arc must ', ...
         'bulge outward from the main body circle, measured on the ear radial axis.'], rise);
end
maxSpan = 2 * outerR * sin(deg2rad(80)); % 半张角上限 80°，避免两端点趋近重合
if span >= maxSpan
    error('CircularFPC:GeometryInfeasible', ...
        ['mountingSlotSpan %.6f mm exceeds what the main body circle can carry: with an ', ...
         'outer diameter of %.6f mm the two slot ends merge at %.6f mm. Reduce ', ...
         'mountingSlotSpan or enlarge the board.'], span, 2 * outerR, maxSpan);
end
sinA = span / (2 * outerR);
cosA = sqrt(max(0, 1 - sinA^2));
halfSpanDeg = asind(sinA);
midCenterR = rise * (2 * outerR + rise) / (2 * (rise + outerR * (1 - cosA)));
midArcRadius = outerR + rise - midCenterR;
if ~(midArcRadius > 0) || ~isfinite(midArcRadius)
    error('CircularFPC:GeometryInfeasible', ...
        'Mounting slot middle arc is not constructible for span %.6f mm and rise %.6f mm.', ...
        span, rise);
end
if edgeClearance <= 1e-6
    error('CircularFPC:GeometryInfeasible', ...
        ['mountingSlotEdgeClearance %.6f mm must be positive: the ear needs a board strip ', ...
         'between the middle arc and the outer edge.'], edgeClearance);
end
spec = struct();
spec.outerRadius = outerR;
spec.span = span;
spec.rise = rise;
spec.edgeClearance = edgeClearance;
spec.halfSpanDeg = halfSpanDeg;
spec.midCenterR = midCenterR;
spec.midArcRadius = midArcRadius;
spec.outerArcRadius = midArcRadius + edgeClearance;
% 局部坐标系（u = 耳朵径向轴、t = 切向，原点在板中心）。
spec.endpointLocal = outerR * [cosA, sinA; cosA, -sinA]; % P+ / P-
% 耳朵外弧与主体外径圆的交点（未圆角时的回接点），仅用于报告与校验。
[spec.rootPointLocal, spec.rootHalfSpanDeg] = earRootPoints(spec);
end

function [rootXY, halfSpanDeg] = earRootPoints(spec)
% 最外侧弧所在圆（圆心在轴上 midCenterR、半径 outerArcRadius）与主体外径圆的
% 两个交点。交点存在即等价于耳朵与主体有真实板料连接。
d = spec.midCenterR;
r1 = spec.outerRadius;
r2 = spec.outerArcRadius;
if d <= 0
    error('CircularFPC:GeometryInfeasible', ...
        'Mounting ear centre radius must be positive; got %.6f mm.', d);
end
if r2 <= 1e-9
    error('CircularFPC:GeometryInfeasible', 'Mounting ear outer arc radius must be positive.');
end
% 两圆相交判据：|r1 - r2| < d < r1 + r2
if ~(abs(r1 - r2) < d && d < r1 + r2)
    error('CircularFPC:GeometryInfeasible', ...
        ['Mounting ear does not reach the main body circle for span %.6f mm, rise %.6f mm, ', ...
         'edge clearance %.6f mm: the outer arc circle (r=%.6f mm, centre r=%.6f mm) and the ', ...
         'main body circle (r=%.6f mm) do not intersect, so no connecting board material ', ...
         'exists. Increase mountingSlotRise or reduce mountingSlotEdgeClearance.'], ...
        spec.span, spec.rise, spec.edgeClearance, r2, d, r1);
end
a = (d^2 + r1^2 - r2^2) / (2 * d);
h2 = r1^2 - a^2;
if h2 <= 0
    error('CircularFPC:GeometryInfeasible', ...
        'Mounting ear root intersection is degenerate (h^2 = %.9g mm^2).', h2);
end
h = sqrt(h2);
rootXY = [a, h; a, -h];
% 用 atan2d 而非 atand(h/a)：当 a < 0 时交点位于板中心的另一侧，根部张角
% 必然大于 90°，必须如实反映，否则会漏掉「耳朵过大」这类不可行配置。
halfSpanDeg = atan2d(h, a);
% 相邻耳朵（0/90/180/270，间隔 90°）之间必须保留板料：根部角域不能相连，
% 否则四个耳朵会连成一整圈，板框拓扑不再是「主体 + 4 个局部耳朵」。
if halfSpanDeg >= 45
    error('CircularFPC:GeometryInfeasible', ...
        ['Mounting ear spans %.3f deg of the main body circle (limit 45 deg, ears are 90 deg ', ...
         'apart) for span %.6f mm, rise %.6f mm, edge clearance %.6f mm: neighbouring ears ', ...
         'would merge into a ring instead of four local ears. Reduce mountingSlotSpan, ', ...
         'mountingSlotRise or mountingSlotEdgeClearance.'], ...
        halfSpanDeg, spec.span, spec.rise, spec.edgeClearance);
end
end

function xy = mountingSlotLoopLocal(spec, filletRadius, nArc)
% 挖槽闭环（局部坐标，不重复首点）：内侧主体圆弧 P+ → P- 与中间弧 P- → P+ 共享
% 端点围成闭合挖槽。两端按 filletRadius 生成与「主体外径圆外切 + 中间弧内切」
% 的相切圆角，消除槽口尖角；圆角只作用于端点邻域，三段弧的主体关系不变。
% 采样数取奇数：对称弧的顶点（角度 0）与两端点都落在采样点上，
% 顶点半径与弦长因此是精确值而不是弦近似。
nHalf = 2 * max(12, round(nArc / 4)) + 1;
[tipMain, tipMid] = slotEndFilletPoints(spec, filletRadius);
signs = [1, -1];
upperMain = [tipMain(1, 1), tipMain(1, 2)];
lowerMain = [tipMain(2, 1), tipMain(2, 2)];
upperMid = [tipMid(1, 1), tipMid(1, 2)];
lowerMid = [tipMid(2, 1), tipMid(2, 2)];
thetaMain = atan2d(upperMain(2), upperMain(1));
thetaMid = atan2d(upperMid(2), upperMid(1) - spec.midCenterR);
% 1) 内侧弧：+thetaMain → -thetaMain（沿主体外径圆向板内）
innerAngles = linspace(thetaMain, -thetaMain, nHalf).';
innerArc = spec.outerRadius * [cosd(innerAngles), sind(innerAngles)];
innerArc(1, :) = upperMain;
innerArc(end, :) = lowerMain;
% 2) 下端圆角：内侧弧 → 中间弧
lowerFillet = filletArcBetween(spec, filletRadius, signs(2), nHalf, lowerMain, lowerMid);
% 3) 中间弧：-thetaMid → +thetaMid（向板外鼓起）
midAngles = linspace(-thetaMid, thetaMid, nHalf).';
midArc = [spec.midCenterR, 0] + spec.midArcRadius * [cosd(midAngles), sind(midAngles)];
midArc(1, :) = lowerMid;
midArc(end, :) = upperMid;
% 4) 上端圆角：中间弧 → 内侧弧
upperFillet = filletArcBetween(spec, filletRadius, signs(1), nHalf, upperMid, upperMain);
xy = [innerArc; lowerFillet; midArc; upperFillet];
if filletRadius > 0 && size(xy, 1) < 8
    error('CircularFPC:GeometryInfeasible', 'Mounting slot fillet sampling is degenerate.');
end
xy = xy([true; vecnorm(diff(xy, 1, 1), 2, 2) > 1e-12], :);
if norm(xy(1, :) - xy(end, :)) > 1e-12
    xy = [xy; xy(1, :)]; % 闭合（与板框其他闭环一致）
end
end

function xy = mountingEarLoopLocal(spec, nArc)
% 耳朵区域闭环（局部坐标，不重复首点）：最外侧等距弧（经外凸顶点的外边界）
% 向根部两侧各延伸一段，再用一条弦闭合。延伸段与闭合弦都落在主体圆内，并集后
% 不可见，因此可见外形仍严格是「J- → 顶点 → J+」的等距外偏弧。
%
% 必须向根部之外延伸：主体圆按 720 段弦离散，其弦落在真圆内侧；若耳朵弧正好
% 止于真圆上的 J±，则该弧与主体多边形边界在 J± 处近乎相切，布尔并集会产生长度
% ~1e-5 mm 的碎片边和一个 ~90° 伪角（几何上等价于零长度边）。延伸量按「端点径向
% 深入主体圆的深度」给定（而不是固定角度），这样才能保证横切足够明显。
nHalf = 2 * max(12, round(nArc / 4)) + 1; % 奇数：顶点严格落在采样点上
mountingEarCrossDepth = 0.05; % [mm] 延伸端点径向深入主体圆的最小深度
maxArcHalfDeg = 176; % 弧角上限：超过半圆会使弦闭合法失去意义
[rootXY, ~] = earRootPoints(spec);
thetaEar = abs(atan2d(rootXY(1, 2), rootXY(1, 1) - spec.midCenterR));
% 由目标深度反解延伸角：半径(θ) = |earCentre + R_arc*(cosθ, sinθ)| 随 |θ| 增大而减小，
% 在 J± 处恰好等于主体半径。解 cosθ = ((R-depth)^2 - d^2 - R_arc^2) / (2*d*R_arc)。
depthCos = ((spec.outerRadius - mountingEarCrossDepth)^2 - spec.midCenterR^2 - ...
    spec.outerArcRadius^2) / (2 * spec.midCenterR * spec.outerArcRadius);
if depthCos >= 1
    error('CircularFPC:GeometryInfeasible', ...
        ['Mounting ear cannot cross into the main body circle (span %.6f mm, rise %.6f mm, ', ...
         'edge clearance %.6f mm): no arc position reaches %.3f mm inside the main circle. ', ...
         'Increase mountingSlotRise or reduce mountingSlotEdgeClearance.'], ...
        spec.span, spec.rise, spec.edgeClearance, mountingEarCrossDepth);
end
extendedHalfDeg = acosd(max(-1, depthCos));
if extendedHalfDeg > maxArcHalfDeg
    error('CircularFPC:GeometryInfeasible', ...
        ['Mounting ear arc would have to sweep to %.3f deg to cross the main body circle ', ...
         'by %.3f mm, beyond the %.1f deg closure limit. Increase mountingSlotRise or ', ...
         'reduce mountingSlotEdgeClearance.'], extendedHalfDeg, mountingEarCrossDepth, ...
        maxArcHalfDeg);
end
earAngles = linspace(extendedHalfDeg, -extendedHalfDeg, nHalf).';
outerArc = [spec.midCenterR, 0] + spec.outerArcRadius * [cosd(earAngles), sind(earAngles)];
% 闭合弦直接连接两个延伸端点。该弦位于耳朵外弧所在的圆盘内（圆盘是凸区域），
% 因此不会在「主体 ∪ 耳朵外弧圆盘」之外多加任何板料；并集的可见外边界仍然是
% 耳朵外弧（J- → 顶点 → J+）与主体圆（J+ → J-）两段，与设计定义一致。
xy = [outerArc; outerArc(1, :)];
% 回接点必须严格位于主体圆上（正板料连接），否则明确失败而不静默退化。
if min(abs(vecnorm(rootXY, 2, 2) - spec.outerRadius)) > 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        'Mounting ear root point does not lie on the main body circle; ear connection is invalid.');
end
% 两圆必须在 J± 处以足够大的夹角横切：交角过小（近乎相切）时布尔并集会产生
% 碎片边与伪角。J± 处两圆半径方向夹角 = arccos(交点处两径向夹角的余弦)，
% 由两圆半径与圆心距给出；两圆正交时为 90°，越小越接近相切。
crossingCos = (spec.midCenterR^2 + spec.outerArcRadius^2 - spec.outerRadius^2) / ...
    (2 * spec.midCenterR * spec.outerArcRadius);
crossingAngleDeg = abs(rad2deg(acos(max(-1, min(1, crossingCos)))));
if crossingAngleDeg < 5
    error('CircularFPC:GeometryInfeasible', ...
        ['Mounting ear meets the main body circle at only %.3f deg (nearly tangent), which ', ...
         'cannot be unioned robustly. Increase mountingSlotRise or reduce ', ...
         'mountingSlotEdgeClearance.'], crossingAngleDeg);
end
% 延伸后的端点必须仍在采样弧上、且 J± 严格位于弧内部（确保横切落在采样段内）。
if abs(thetaEar) >= 180
    error('CircularFPC:GeometryInfeasible', ...
        'Mounting ear root angle is degenerate for span %.6f mm and rise %.6f mm.', ...
        spec.span, spec.rise);
end
end

function [tipMain, tipMid] = slotEndFilletPoints(spec, filletRadius)
% 挖槽两端圆角的切点：圆角圆与主体外径圆外切、与中间弧内切。
% 返回 [上端; 下端]，每行分别为内侧弧切点与中间弧切点。
if filletRadius <= 0
    tipMain = spec.endpointLocal;
    tipMid = spec.endpointLocal;
    return;
end
if filletRadius >= spec.midArcRadius - 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        ['mountingSlotEndFilletRadius %.6f mm is too large for the %.6f mm middle-arc ', ...
         'radius of this slot; reduce the fillet radius or the slot rise.'], ...
        filletRadius, spec.midArcRadius);
end
rho1 = spec.outerRadius + filletRadius;  % 与主体外径圆外切
rho2 = spec.midArcRadius - filletRadius; % 与中间弧内切
center = intersectCenters(rho1, rho2, spec.midCenterR, ...
    spec.span, spec.rise, 'slot end fillet');
tipMain = spec.outerRadius * (center / norm(center));
tipMid = [spec.midCenterR, 0] + spec.midArcRadius * ...
    ((center - [spec.midCenterR, 0]) / norm(center - [spec.midCenterR, 0]));
% 校验切点确实落在两段弧的范围内（否则圆角无法在两弧之间实现）。
if abs(atan2d(tipMain(2), tipMain(1))) >= spec.halfSpanDeg
    error('CircularFPC:GeometryInfeasible', ...
        ['mountingSlotEndFilletRadius %.6f mm does not fit: its tangent point on the main ', ...
         'body circle leaves the slot arc. Reduce the fillet radius or mountingSlotRise.'], ...
        filletRadius);
end
tipMain = [tipMain; tipMain(1), -tipMain(2)];
tipMid = [tipMid; tipMid(1), -tipMid(2)];
end

function center = intersectCenters(rho1, rho2, centerR, span, rise, label)
% 求解到板中心距离 rho1、到轴上点 (centerR,0) 距离 rho2 的交点（取上半平面）。
if ~(abs(rho1 - rho2) < centerR && centerR < rho1 + rho2)
    error('CircularFPC:GeometryInfeasible', ...
        ['%s is not constructible for span %.6f mm, rise %.6f mm: the tangent circle ', ...
         '(radii %.6f/%.6f mm around centres %.6f mm apart) has no solution. Adjust the ', ...
         'mounting slot parameters and the mount fillet radius.'], ...
        label, span, rise, rho1, rho2, centerR);
end
fu = (rho1^2 - rho2^2 + centerR^2) / (2 * centerR);
ft2 = rho1^2 - fu^2;
if ft2 <= 1e-12
    error('CircularFPC:GeometryInfeasible', ...
        '%s tangent construction is degenerate (t^2 = %.9g mm^2).', label, ft2);
end
center = [fu, sqrt(ft2)];
end

function arc = filletArcBetween(spec, filletRadius, sideSign, nArc, pStart, pEnd)
% 挖槽端部圆角弧：圆心与 slotEndFilletPoints 同一构造（切点由该函数给出），
% 弧自 pStart 到 pEnd。sideSign 选取上/下半平面的圆心。
if filletRadius <= 0
    arc = zeros(0, 2);
    return;
end
rho1 = spec.outerRadius + filletRadius;  % 与主体外径圆外切
rho2 = spec.midArcRadius - filletRadius; % 与中间弧内切
center = intersectCenters(rho1, rho2, spec.midCenterR, spec.span, spec.rise, 'slot end fillet');
center = [center(1), sideSign * center(2)];
arc = sampleCircularArc(center, filletRadius, pStart, pEnd, ...
    max(4, round(nArc / 4)), 'short');
end

function arc = sampleCircularArc(center, radius, pStart, pEnd, n, direction)
% 采样圆上从 pStart 到 pEnd 的圆弧。direction：'short' 走劣弧，'cw'/'ccw' 指定
% 绕向（局部坐标下）。端点精确写回，保证共享端点契约不被离散误差破坏。
center = reshape(center, 1, 2);
pStart = reshape(pStart, 1, 2);
pEnd = reshape(pEnd, 1, 2);
tStart = pStart - center;
tEnd = pEnd - center;
rotation = atan2(tStart(1) * tEnd(2) - tStart(2) * tEnd(1), dot(tStart, tEnd));
switch direction
    case 'short'
        % 保持 |rotation| <= pi
    case 'cw'
        if rotation > 0
            rotation = rotation - 2 * pi;
        end
    case 'ccw'
        if rotation < 0
            rotation = rotation + 2 * pi;
        end
    otherwise
        error('CircularFPC:InvalidOperation', 'Unknown arc direction: %s', direction);
end
baseAngle = atan2(tStart(2), tStart(1));
angles = baseAngle + rotation * (0:n).' / n;
arc = center + radius * [cos(angles), sin(angles)];
arc(1, :) = pStart;
arc(end, :) = pEnd;
end

function pads = buildElectrodePads(cfg, outerR)
% Two independent top-layer pads at the requested electrode direction. They
% are deliberately separate from PAD_A/PAD_B and never enter the coil route.
u = [cosd(cfg.electrodeAngleDeg), sind(cfg.electrodeAngleDeg)];
t = [-u(2), u(1)];
centerR = outerR + cfg.electrodeArmLength;
offset = (cfg.electrodeArmGap + cfg.electrodeArmWidth) / 2;
pads = struct('name', {}, 'xy', {}, 'diameter', {}, 'layer', {}, ...
    'removable', {}, 'role', {}, 'placementRegion', {}, 'bridgeAngleDeg', {});
for k = 1:2
    pads(k).name = sprintf('ELECTRODE_%s', char('A' + k - 1));
    pads(k).xy = centerR * u + (-1)^(k == 1) * offset * t;
    pads(k).diameter = cfg.electrodePadDiameter;
    pads(k).layer = 1;
    pads(k).removable = false;
    pads(k).role = 'INDEPENDENT_ELECTRODE';
    pads(k).placementRegion = 'ELECTRODE_315';
    pads(k).bridgeAngleDeg = cfg.electrodeAngleDeg;
end
end

function active = defaultActiveLayers(cfg)
key = cfg.boardLayerCount * 10 + cfg.coilLayerCount;
switch key
    case 21
        active = 1;
    case 22
        active = [1 2];
    case 41
        active = 1;
    case 42
        active = [1 4];
    case 44
        active = 1:4;
    case 66
        active = 1:6;
    otherwise
        error('CircularFPC:UnsupportedLayerCombination', ...
            'Cannot infer active layers for %d/%d.', cfg.boardLayerCount, cfg.coilLayerCount);
end
end

function xy = filletHoleCorners(xy, maxR, angleLimitDeg, nArc)
% 圆角化闭合孔槽边界：把明显非共线且内角 <= angleLimitDeg 的折角
% 替换为与两边相切的圆弧。圆弧半径为 maxR（受相邻边长限制），沿边
% 的切除长度为 R/tan(interior/2)，不能把半径误当成切除长度。
n = size(xy, 1) - 1;
if n < 3
    return;
end
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
    turn = atan2(u1(1) * u2(2) - u1(2) * u2(1), dot(u1, u2));
    dev = abs(rad2deg(turn));
    interior = 180 - dev;
    if interior > angleLimitDeg + 1e-9 || dev < 1e-6
        out = [out; cur]; %#ok<AGROW>
        continue;
    end
    tanHalfInterior = tan(deg2rad(interior / 2));
    R = min(maxR, 0.45 * min(len1, len2) * tanHalfInterior);
    if R <= 1e-3
        out = [out; cur]; %#ok<AGROW>
        continue;
    end
    trim = R / tanHalfInterior;
    % 圆心位于实际转弯侧：左转用左法向，右转用右法向。孔槽边界
    % 同时包含凸/凹方向变化，不能只按整个闭环方向筛掉其中一类。
    if turn > 0
        n1 = [-u1(2), u1(1)];
        n2 = [-u2(2), u2(1)];
    else
        n1 = [u1(2), -u1(1)];
        n2 = [u2(2), -u2(1)];
    end
    t1 = cur - trim * u1; % 切点（入边）
    t2 = cur + trim * u2; % 切点（出边）
    c1 = t1 + R * n1;
    c2 = t2 + R * n2;
    C = (c1 + c2) / 2;
    if norm(c1 - c2) > max(1e-8, R * 1e-6)
        error('CircularFPC:GeometryInfeasible', ...
            'Slot fillet tangent construction is inconsistent by %.9g mm.', norm(c1 - c2));
    end
    a1 = atan2(t1(2) - C(2), t1(1) - C(1));
    angs = a1 + turn * (0:nArc).' / nArc;
    arc = C + R * [cos(angs), sin(angs)];
    arc(1, :) = t1;
    arc(end, :) = t2;
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
% 奇数序号活动层从内向外 CCW，偶数层从外向内 CW，俯视电流同向叠加。
% 4/4 与 6/6 使用相位/分数匝表把层间过孔落在指定方位。
% 外端过孔延伸区：线圈最外圈沿径向向外延伸 eff.viaEndExtension，过孔落在延伸端，
% 焊环避开相邻匝（不影响线距/匝数），局部板框凸耳自动包络延伸区。
coils = cell(1, cfg.boardLayerCount);
rStart = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2;
% 4/4 分数匝（用户设计约定）：L2 多绕 1/4 圈使内端直接落到 225° 的 V23，
% L4 少绕 1/4 圈使内端直接落到 135° 的 VOUT——内端无任何过渡走线，
% 全部铜箔均为同心螺旋，且四层平均物理匝数（完整 360° 圈数）恰为 turnsPerCoilLayer。
is44 = cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4;
is66 = cfg.boardLayerCount == 6 && cfg.coilLayerCount == 6;
spanExtra = zeros(1, numel(activeLayers));
phaseExtra = zeros(1, numel(activeLayers));
if is44
    spanExtra = [0, 0.25, 0, -0.25];
    phaseExtra = [0, 90, 90, 0];
elseif is66
    % Outer transition lugs: V12=135°, V34=225°, V56=45°.
    % Inner transitions: V23=225°, V45=45°, VOUT=135°.
    spanExtra = [0, 0.25, 0, 0.50, 0, 0.25];
    phaseExtra = [0, 90, 90, -90, -90, 0];
end
for p = 1:numel(activeLayers)
    li = activeLayers(p);
    spanTurns = cfg.turnsPerCoilLayer + spanExtra(p);
    phaseDeg = cfg.connectionAngleDeg + phaseExtra(p) ...
        + 90 * floor((p - 1) / 2) * (~is44 && ~is66);
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
    % 外端延伸：用短平滑曲线从线圈切线转向板外，过孔落在径向对齐的终点。
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
% 平滑外伸接触弧：从线圈外端 S 沿切线方向 a 出发，平滑转向板外。
% 终点严格落在 S 的径向轴线上，故外端过孔可以精确对齐 45/135/225°。
% 使用短三次曲线而不是强行用一段固定圆弧：当起点切线接近圆周切线时，
% 固定 110° 圆弧必然带来切向偏移，导致过孔中心偏离标称径向轴。
xy = zeros(0, 2);
if norm(S) <= 1e-12 || norm(a) <= 1e-12 || E <= 1e-12
    return;
end
uLoc = S / norm(S);
a = a / norm(a);
p3 = (norm(S) + E) * uLoc;
% 控制点长度与径向外伸绑定，保持凸耳紧凑且不越入相邻外圈。
controlLength = min(0.75 * E, 0.75 * norm(p3 - S));
c1 = S + controlLength * a;
c2 = p3 - controlLength * uLoc;
t = linspace(0, 1, max(5, n)).';
w0 = (1 - t).^3;
w1 = 3 * (1 - t).^2 .* t;
w2 = 3 * (1 - t) .* t.^2;
w3 = t.^3;
xy = w0 * S + w1 * c1 + w2 * c2 + w3 * p3;
xy(1, :) = S;
xy(end, :) = p3; % 终点即外端过孔中心
end

function [coils, connectionPaths, pads, vias, seriesRoute, returnLayer, electrodePads] = ...
    buildNetwork(cfg, eff, activeLayers, directions, layoutRegions)
% 构建完整串联网络：PAD_A → 线圈(各活动层串联) → 过孔层间转移 → PAD_B，
% 并生成每段连接路径（connectionPaths 按物理层存放）。
coils = buildCoils(cfg, eff, activeLayers, directions);
connectionPaths = cell(1, cfg.boardLayerCount);
for li = 1:cfg.boardLayerCount
    connectionPaths{li} = {};
end

[pads, vias, returnLayer, routeInfo] = buildTerminals(cfg, eff, activeLayers, coils, layoutRegions);
electrodePads = layoutRegions.electrodePads;
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
% 过孔命名与角色（2/1、4/1: VRET, VOUT；2/2: V12, VOUT；4/2: V14, VOUT；
% 4/4: V12, V23, V34, VOUT；6/6: V12, V23, V34, V45, V56, VOUT）。
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
        % V23 是与其余过孔相同的 0.55/0.31 mm 贯通过孔；按真实焊环
        % 到相邻匝的 viaCoilSpacing 定位，不引入额外禁铜圈。
        keepoutR = cfg.viaCoilSpacing + cfg.viaPadDiameter / 2;
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
            viaAngles(end + 1) = atan2d(viaXY(end, 2), viaXY(end, 1)); %#ok<AGROW>
        else
            viaRoles{end + 1} = 'INNER_TRANSITION'; %#ok<AGROW>
            innerAxis = coils{activeLayers(p)}(end, :);
            innerAxis = innerAxis / norm(innerAxis);
            keepoutR = cfg.viaCoilSpacing + cfg.viaPadDiameter / 2;
            innerR = max(0.1, layoutRegions.rStart - (keepoutR + ...
                cfg.traceWidth / 2 + 1e-3) + 0.25 * eff.coilPitch);
            viaXY(end + 1, :) = innerR * innerAxis; %#ok<AGROW>
            viaRegions{end + 1} = 'RETURN_BRIDGE'; %#ok<AGROW>
            viaAngles(end + 1) = atan2d(viaXY(end, 2), viaXY(end, 1)); %#ok<AGROW>
            if isnan(rV23)
                rV23 = innerR;
            end
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
holes = layoutRegions.holeLoops;
[names, xy, radii] = terminalArrays(pads, vias);
for i = 1:numel(names)
    pxy = xy(i, :);
    r = radii(i);
    if ~isnumeric(pxy) || numel(pxy) ~= 2 || ~all(isfinite(pxy))
        error('CircularFPC:TerminalPlacementInvalid', 'Terminal %s has invalid coordinates.', names{i});
    end
    % Local via/electrode lugs can extend beyond the base circle, so use the
    % final board polyshape for containment and leave tangent clearance to
    % the segment-based result validator.
    if ~isinterior(layoutRegions.boardShape, pxy(1), pxy(2))
        error('CircularFPC:TerminalPlacementInvalid', ...
            'Terminal %s lies outside the final board outline.', names{i});
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
% Full multilayer variants place even-to-odd inner transitions directly on
% their vias. The final active layer receives the same short smooth stub to
% VOUT. This keeps the inter-layer topology explicit without changing the
% main spiral samples used by the COMSOL export.
is44 = cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4;
is66 = cfg.boardLayerCount == 6 && cfg.coilLayerCount == 6;
if ~(is44 || is66)
    return;
end
vout = vias(strcmp({vias.name}, 'VOUT'));
for p = 2:2:numel(activeLayers) - 1
    lowerLayer = activeLayers(p);
    upperLayer = activeLayers(p + 1);
    vName = sprintf('V%d%d', lowerLayer, upperLayer);
    v = vias(strcmp({vias.name}, vName));
    if isempty(v)
        error('CircularFPC:GeometryInfeasible', 'Missing inner transition via %s.', vName);
    end

    S = coils{lowerLayer}(end, :);
    a = S - coils{lowerLayer}(end - 1, :);
    a = a / norm(a);
    ext = smoothInwardArc(S, a, max(norm(v.xy - S), 1e-6), 61);
    coils{lowerLayer} = [coils{lowerLayer}; ext(2:end, :)];

    SNext = coils{upperLayer}(1, :);
    aNext = coils{upperLayer}(2, :) - coils{upperLayer}(1, :);
    aNext = aNext / norm(aNext);
    arcNext = smoothInwardArc(SNext, -aNext, max(norm(SNext - v.xy), 1e-6), 61);
    coils{upperLayer} = [flipud(arcNext); coils{upperLayer}(2:end, :)];
end

lastLayer = activeLayers(end);
SLast = coils{lastLayer}(end, :);
aLast = SLast - coils{lastLayer}(end - 1, :);
aLast = aLast / norm(aLast);
dBack = vout.xy - SLast;
dBack = dBack / norm(dBack);
stub = sampleBezier(SLast, aLast, vout.xy, dBack, 0.3, 0.3, 97);
coils{lastLayer} = [coils{lastLayer}; stub(2:end, :)];
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
