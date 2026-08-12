function varargout = circular_fpc_validation(operation, varargin)
% 配置 / 几何可行性 / 结果指标校验（R1-R4）：
%   'validate_config'     : 校验 cfg 各字段类型与取值（正数、整数、层叠组合等）
%   'validate_feasibility': 生成前校验几何是否可行（圆环径向跨度、平台能否放入环区）
%   'validate_result'     : 生成后校验结果指标（坐标有限、无自交、净距、桥宽、串联连续性等）
switch operation
    case 'validate_config'
        varargout{1} = validateConfig(varargin{1});
    case 'validate_feasibility'
        assertFeasible(varargin{1}, varargin{2});
    case 'validate_result'
        varargout{1} = validateResult(varargin{1}, varargin{2}, varargin{3});
    otherwise
        error('CircularFPC:InvalidOperation', 'Unknown validation operation: %s', operation);
end
end

function cfg = validateConfig(cfg)
% 必须为正的有限标量数值的字段（长度/直径/净距/厚度/电阻率/采样数等）。
numFields = {'boardOuterDiameter', 'coilInnerDiameter', 'centerPlatformWidth', ...
    'centerPlatformHeight', 'bridgeTargetWidth', 'geometryScale', 'turnsPerCoilLayer', ...
    'traceWidth', 'traceSpacing', 'pitchMargin', 'edgeClearance', ...
    'padPairSpacing', ...
    'padDiameter', 'viaPadDiameter', 'viaDrillDiameter', 'antipadDiameter', ...
    'terminalClearance', 'copperThickness', 'copperResistivity', 'samplePointsPerTurn', 'turnScanMax'};
for k = 1:numel(numFields)
    v = cfg.(numFields{k});
    if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v) || v <= 0
        error('CircularFPC:InvalidConfig', '%s must be a positive finite scalar.', numFields{k});
    end
end
if ~isscalar(cfg.connectionAngleDeg) || ~isnumeric(cfg.connectionAngleDeg) || ~isfinite(cfg.connectionAngleDeg)
    error('CircularFPC:InvalidConfig', 'connectionAngleDeg must be a finite numeric scalar.');
end
if mod(cfg.turnsPerCoilLayer, 1) ~= 0 || mod(cfg.samplePointsPerTurn, 1) ~= 0 || mod(cfg.turnScanMax, 1) ~= 0
    error('CircularFPC:InvalidConfig', 'turnsPerCoilLayer, samplePointsPerTurn and turnScanMax must be integers.');
end
supported = {[2 1], [2 2], [4 1], [4 2], [4 4]};
ok = false;
for k = 1:numel(supported)
    if isequal([cfg.boardLayerCount, cfg.coilLayerCount], supported{k})
        ok = true;
        break;
    end
end
if ~ok
    error('CircularFPC:UnsupportedLayerCombination', ...
        'Unsupported boardLayerCount/coilLayerCount combination: %d/%d.', ...
        cfg.boardLayerCount, cfg.coilLayerCount);
end
if ~ismember(cfg.terminalPlacementMode, {'auto', 'manual'})
    error('CircularFPC:InvalidConfig', 'terminalPlacementMode must be ''auto'' or ''manual''.');
end
for m = {'manualPadAXY', 'manualPadBXY', 'manualSeriesViaXY'}
    v = cfg.(m{1});
    if ~isnumeric(v) || (~isempty(v) && (size(v, 2) ~= 2 || any(~isfinite(v(:)))))
        error('CircularFPC:InvalidConfig', '%s must be empty or an Nx2 finite numeric matrix.', m{1});
    end
end
if ~islogical(cfg.enablePreview) || ~isscalar(cfg.enablePreview)
    error('CircularFPC:InvalidConfig', 'enablePreview must be a logical scalar.');
end
if ~islogical(cfg.enableFigure) || ~isscalar(cfg.enableFigure)
    error('CircularFPC:InvalidConfig', 'enableFigure must be a logical scalar.');
end
if ~ischar(cfg.designName) || isempty(regexp(cfg.designName, '^[A-Za-z0-9_-]+$', 'once'))
    error('CircularFPC:InvalidConfig', 'designName must match [A-Za-z0-9_-]+.');
end
if ~ischar(cfg.outputRoot) || isempty(cfg.outputRoot)
    error('CircularFPC:InvalidConfig', 'outputRoot must be a nonempty character vector.');
end
end

function assertFeasible(cfg, eff)
% 生成前可行性校验：
%   1) 线圈所需径向跨度（线宽 + (匝数-1)*节距）必须小于环区可用跨度；
%   2) 中央平台（含余量）必须能放进内圆环区，不能压到槽边。
coilPitch = eff.coilPitch;
requiredSpan = cfg.traceWidth + (cfg.turnsPerCoilLayer - 1) * coilPitch;
availableSpan = eff.boardOuterDiameter / 2 - cfg.edgeClearance - eff.coilInnerDiameter / 2;
if availableSpan < requiredSpan - 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        'Coil radial span %.6f mm exceeds available annulus span %.6f mm.', requiredSpan, availableSpan);
end
halfDiag = sqrt((eff.centerPlatformWidth / 2)^2 + (eff.centerPlatformHeight / 2)^2);
slotMargin = 0.25;
annulusInnerRadius = eff.coilInnerDiameter / 2 - cfg.edgeClearance;
if halfDiag + slotMargin >= annulusInnerRadius - 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        'Central platform %.3f x %.3f mm does not fit inside the annulus.', ...
        eff.centerPlatformWidth, eff.centerPlatformHeight);
end
if eff.bridgeTargetWidth <= 0
    error('CircularFPC:GeometryInfeasible', 'Bridge width must be positive.');
end
end

function v = validateResult(cfg, eff, geom)
% 结果指标校验。v 中的各项含义（写入 05_validation_report.txt）：
%   finiteCoordinates      : 所有坐标有限
%   noZeroLengthSegments   : 无零长度线段
%   noSelfIntersections    : 无自交折线
%   closedBoardLoopCount   : 板框闭环数（必须为 5 = 1 外边界 + 4 孔槽）
%   minCopperSpacingMm     : 铜线之间最小净距（须 ≥ traceSpacing）
%   minCopperToBoardMm     : 铜到板外缘最小距离（须 ≥ edgeClearance）
%   minCopperToSlotsMm     : 铜/端子到孔槽最小距离（须 ≥ edgeClearance）
%   minPadViaClearanceMm   : 焊盘/过孔端子间最小净距
%   actualBridgeWidthMm    : 实际桥宽（须 ≥ bridgeTargetWidth）
%   uniqueSeriesNetwork    : 串联网络唯一且连续
%   maxSeriesContinuityErrorMm / maxConnectionTurnDeg / viaOverlapFree : 连接质量指标
v = struct();
v.finiteCoordinates = true;
v.noZeroLengthSegments = true;
v.noSelfIntersections = true;
v.messages = {};
for k = 1:numel(geom.boardLoops)
    xy = geom.boardLoops(k).xy;
    if ~allFinite(xy)
        v.finiteCoordinates = false;
    end
    if hasZeroLength(xy)
        v.noZeroLengthSegments = false;
    end
    if selfIntersects(xy, true, 1e-9)
        v.noSelfIntersections = false;
    end
end
for li = 1:numel(geom.coils)
    xy = geom.coils{li};
    if ~isempty(xy)
        if ~allFinite(xy)
            v.finiteCoordinates = false;
        end
        if hasZeroLength(xy)
            v.noZeroLengthSegments = false;
        end
        if selfIntersects(xy, false, 1e-9)
            v.noSelfIntersections = false;
        end
    end
    paths = geom.connectionPaths{li};
    for k = 1:numel(paths)
        pxy = paths{k};
        if ~allFinite(pxy)
            v.finiteCoordinates = false;
        end
        if hasZeroLength(pxy)
            v.noZeroLengthSegments = false;
        end
        if selfIntersects(pxy, false, 1e-9)
            v.noSelfIntersections = false;
        end
    end
end
for k = 1:numel(geom.pads)
    if ~allFinite(geom.pads(k).xy)
        v.finiteCoordinates = false;
    end
end
for k = 1:numel(geom.vias)
    if ~allFinite(geom.vias(k).xy)
        v.finiteCoordinates = false;
    end
end
v.closedBoardLoopCount = numel(geom.boardLoops);
v.minCopperSpacingMm = computeCopperSpacing(cfg, eff, geom.coils, geom.connectionPaths);
v.minCopperToBoardMm = computeCopperToBoard(cfg, eff, geom.coils, geom.connectionPaths);
v.minCopperToSlotsMm = computeCopperToSlots(cfg, geom.boardLoops, geom.coils, geom.connectionPaths, geom.pads, geom.vias);
v.minPadViaClearanceMm = computeTerminalClearance(cfg, geom.pads, geom.vias);
v.actualBridgeWidthMm = geom.actualBridgeWidth;
[v.uniqueSeriesNetwork, v.maxSeriesContinuityErrorMm] = ...
    checkSeriesRoute(geom.seriesRoute, geom.activeLayers, geom.vias);
v.maxConnectionTurnDeg = computeMaxConnectionTurnDeg(geom.connectionPaths, geom.seriesRoute, geom.coils);
v.viaOverlapFree = checkViaOverlap(cfg, geom.vias);
if ~v.finiteCoordinates
    v.messages{end + 1} = 'non-finite coordinates found'; %#ok<AGROW>
end
if ~v.noZeroLengthSegments
    v.messages{end + 1} = 'zero-length segment found'; %#ok<AGROW>
end
if ~v.noSelfIntersections
    v.messages{end + 1} = 'self-intersecting polyline found'; %#ok<AGROW>
end
if v.closedBoardLoopCount ~= 5
    v.messages{end + 1} = sprintf('expected 5 board loops, got %d', v.closedBoardLoopCount); %#ok<AGROW>
end
if v.minCopperSpacingMm < cfg.traceSpacing - 1e-9
    v.messages{end + 1} = 'copper spacing below traceSpacing'; %#ok<AGROW>
end
if v.minCopperToBoardMm < cfg.edgeClearance - 1e-9
    v.messages{end + 1} = 'copper-to-board clearance below edgeClearance'; %#ok<AGROW>
end
if v.minCopperToSlotsMm < cfg.edgeClearance - 1e-9
    v.messages{end + 1} = 'copper-to-slot clearance below edgeClearance'; %#ok<AGROW>
end
if v.actualBridgeWidthMm < eff.bridgeTargetWidth - 1e-9
    v.messages{end + 1} = 'actual bridge width below target'; %#ok<AGROW>
end
if ~v.uniqueSeriesNetwork
    v.messages{end + 1} = 'series network is not unique/continuous'; %#ok<AGROW>
end
if v.maxSeriesContinuityErrorMm > 1e-9
    v.messages{end + 1} = 'series route continuity error too large'; %#ok<AGROW>
end
if v.maxConnectionTurnDeg > 10
    v.messages{end + 1} = 'connection turn angle too large'; %#ok<AGROW>
end
if ~v.viaOverlapFree
    v.messages{end + 1} = 'via overlap detected'; %#ok<AGROW>
end
v.passed = v.finiteCoordinates && v.noZeroLengthSegments && v.noSelfIntersections && ...
    v.closedBoardLoopCount == 5 && ...
    v.minCopperSpacingMm >= cfg.traceSpacing - 1e-9 && ...
    v.minCopperToBoardMm >= cfg.edgeClearance - 1e-9 && ...
    v.minCopperToSlotsMm >= cfg.edgeClearance - 1e-9 && ...
    v.actualBridgeWidthMm >= eff.bridgeTargetWidth - 1e-9 && ...
    v.uniqueSeriesNetwork && v.maxSeriesContinuityErrorMm <= 1e-9 && ...
    v.maxConnectionTurnDeg <= 10 && v.viaOverlapFree;
end

function tf = allFinite(xy)
tf = all(isfinite(xy(:)));
end

function tf = hasZeroLength(xy)
tf = any(all(abs(diff(xy, 1, 1)) < 1e-12, 2));
end

function tf = selfIntersects(xy, isClosed, tol)
n = size(xy, 1);
if n < 4
    tf = false;
    return;
end
segs = n - 1;
for i = 1:segs - 1
    a1 = xy(i, :);
    a2 = xy(i + 1, :);
    jStart = i + 2;
    jEnd = segs;
    if isClosed && i == 1
        jEnd = segs - 1;
    end
    if jStart > jEnd
        continue;
    end
    b1 = xy(jStart:jEnd, :);
    b2 = xy(jStart + 1:jEnd + 1, :);
    if any(segmentsIntersect(a1, a2, b1, b2, tol))
        tf = true;
        return;
    end
end
tf = false;
end

function tf = segmentsIntersect(a1, a2, b1, b2, tol)
d1 = a2 - a1;
d2 = b2 - b1;
denom = d1(1) * d2(:, 2) - d1(2) * d2(:, 1);
par = abs(denom) <= 1e-12;
r = b1 - a1;
t = (r(:, 1) .* d2(:, 2) - r(:, 2) .* d2(:, 1)) ./ max(abs(denom), eps);
u = (r(:, 1) * d1(2) - r(:, 2) * d1(1)) ./ max(abs(denom), eps);
ok = ~par & t >= -tol & t <= 1 + tol & u >= -tol & u <= 1 + tol;
tf = any(ok);
end

function s = computeCopperSpacing(cfg, eff, coils, connectionPaths)
dMin = inf;
per = cfg.samplePointsPerTurn;
for li = 1:numel(coils)
    xy = coils{li};
    if isempty(xy)
        continue;
    end
    n = size(xy, 1);
    for i = 1:n
        idx = i + per * (1:cfg.turnsPerCoilLayer - 1);
        idx = idx(idx <= n);
        if isempty(idx)
            continue;
        end
        d = sqrt(sum((xy(i, :) - xy(idx, :)).^2, 2));
        dMin = min(dMin, min(d));
    end
end
for li = 1:numel(connectionPaths)
    Q = coils{li};
    paths = connectionPaths{li};
    for k = 1:numel(paths)
        P = paths{k};
        if isempty(P)
            continue;
        end
        if ~isempty(Q)
            Qa = Q;
            if norm(P(end, :) - Q(1, :)) <= 1e-6
                Qa = Qa(min(size(Qa, 1), per + 1):end, :);
            end
            if norm(P(1, :) - Q(end, :)) <= 1e-6
                Qa = Qa(1:max(1, size(Qa, 1) - per), :);
            end
            if ~isempty(Qa)
                D = sqrt((P(:, 1) - Qa(:, 1).').^2 + (P(:, 2) - Qa(:, 2).').^2);
                mask = D > 1e-6;
                if any(mask(:))
                    dMin = min(dMin, min(D(mask)));
                end
            end
        end
        for k2 = k + 1:numel(paths)
            R = paths{k2};
            if isempty(R)
                continue;
            end
            D = sqrt((P(:, 1) - R(:, 1).').^2 + (P(:, 2) - R(:, 2).').^2);
            mask = D > 1e-6;
            if any(mask(:))
                dMin = min(dMin, min(D(mask)));
            end
        end
    end
end
s = dMin - cfg.traceWidth;
end

function s = computeCopperToBoard(cfg, eff, coils, connectionPaths)
outerR = eff.boardOuterDiameter / 2;
dMin = inf;
for li = 1:numel(coils)
    pts = coils{li};
    paths = connectionPaths{li};
    for k = 1:numel(paths)
        pts = [pts; paths{k}]; %#ok<AGROW>
    end
    if isempty(pts)
        continue;
    end
    r = sqrt(sum(pts.^2, 2));
    dMin = min(dMin, min(outerR - r));
end
s = dMin - cfg.traceWidth / 2;
end

function s = computeCopperToSlots(cfg, boardLoops, coils, connectionPaths, pads, vias)
holeLoops = {};
for k = 1:numel(boardLoops)
    if boardLoops(k).isHole
        holeLoops{end + 1} = boardLoops(k).xy; %#ok<AGROW>
    end
end
if isempty(holeLoops)
    s = inf;
    return;
end
dMin = inf;
for li = 1:numel(coils)
    pts = coils{li};
    paths = connectionPaths{li};
    for k = 1:numel(paths)
        pts = [pts; paths{k}]; %#ok<AGROW>
    end
    if isempty(pts)
        continue;
    end
    dMin = min(dMin, minDistanceToHoles(pts, holeLoops, 256) - cfg.traceWidth / 2);
end
for k = 1:numel(pads)
    dMin = min(dMin, minDistanceToHoles(pads(k).xy, holeLoops, 256) - pads(k).diameter / 2);
end
for k = 1:numel(vias)
    dMin = min(dMin, minDistanceToHoles(vias(k).xy, holeLoops, 256) - vias(k).padDiameter / 2);
end
s = dMin;
end

function c = computeTerminalClearance(cfg, pads, vias)
[~, xy, radii] = terminalArrays(pads, vias);
c = inf;
for i = 1:size(xy, 1)
    for j = i + 1:size(xy, 1)
        c = min(c, norm(xy(i, :) - xy(j, :)) - radii(i) - radii(j));
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

function [tf, maxErr] = checkSeriesRoute(route, activeLayers, vias)
tf = false;
maxErr = 0;
if isempty(route)
    return;
end
reqFields = {'name', 'kind', 'startXY', 'endXY', 'startLayer', 'endLayer'};
if ~all(ismember(reqFields, fieldnames(route)))
    return;
end
if numel(route) < 3
    return;
end
if ~strcmp(route(1).kind, 'PAD') || ~strcmp(route(1).name, 'PAD_A')
    return;
end
if ~strcmp(route(end).kind, 'PAD') || ~strcmp(route(end).name, 'PAD_B')
    return;
end
if numel(unique({route.name})) ~= numel(route)
    return;
end
vNames = {vias.name};
coilIdx = find(strcmp({route.kind}, 'COIL'));
if numel(coilIdx) ~= numel(activeLayers)
    return;
end
for c = 1:numel(coilIdx)
    k = coilIdx(c);
    if ~strcmp(route(k).name, sprintf('COIL_L%d', activeLayers(c)))
        return;
    end
end
for k = 1:numel(route)
    if ~isnumeric(route(k).startXY) || numel(route(k).startXY) ~= 2 || ...
            ~all(isfinite(route(k).startXY))
        return;
    end
    if ~isnumeric(route(k).endXY) || numel(route(k).endXY) ~= 2 || ...
            ~all(isfinite(route(k).endXY))
        return;
    end
    if ~isscalar(route(k).startLayer) || ~isnumeric(route(k).startLayer) || ...
            ~isscalar(route(k).endLayer) || ~isnumeric(route(k).endLayer)
        return;
    end
    if strcmp(route(k).kind, 'VIA') && ~ismember(route(k).name, vNames)
        return;
    end
end
for k = 1:numel(route) - 1
    e = norm(route(k).endXY - route(k + 1).startXY);
    maxErr = max(maxErr, e);
    if e > 1e-9
        return;
    end
    if route(k).endLayer ~= route(k + 1).startLayer
        return;
    end
end
tf = true;
end

function degMax = computeMaxConnectionTurnDeg(connectionPaths, route, coils)
degMax = 0;
for li = 1:numel(connectionPaths)
    paths = connectionPaths{li};
    for k = 1:numel(paths)
        degMax = max(degMax, polylineMaxTurnDeg(paths{k}));
    end
end
for k = 1:numel(route) - 1
    a = route(k);
    b = route(k + 1);
    if a.endLayer ~= b.startLayer
        continue;
    end
    if strcmp(a.kind, 'TRACE') && strcmp(b.kind, 'COIL')
        p = findTracePath(connectionPaths, a.startLayer, a.startXY, a.endXY);
        q = coils{a.startLayer};
        if isempty(p) || isempty(q) || size(p, 1) < 2 || size(q, 1) < 2
            continue;
        end
        degMax = max(degMax, angleBetweenDeg(p(end, :) - p(end - 1, :), q(2, :) - q(1, :)));
    elseif strcmp(a.kind, 'COIL') && strcmp(b.kind, 'TRACE')
        q = coils{a.startLayer};
        p = findTracePath(connectionPaths, b.startLayer, b.startXY, b.endXY);
        if isempty(p) || isempty(q) || size(p, 1) < 2 || size(q, 1) < 2
            continue;
        end
        degMax = max(degMax, angleBetweenDeg(q(end, :) - q(end - 1, :), p(2, :) - p(1, :)));
    end
end
end

function p = findTracePath(connectionPaths, layer, startXY, endXY)
p = [];
paths = connectionPaths{layer};
for k = 1:numel(paths)
    q = paths{k};
    if size(q, 1) >= 2 && norm(q(1, :) - startXY) <= 1e-9 && norm(q(end, :) - endXY) <= 1e-9
        p = q;
        return;
    end
end
end

function degMax = polylineMaxTurnDeg(p)
degMax = 0;
if size(p, 1) < 3
    return;
end
for i = 2:size(p, 1) - 1
    degMax = max(degMax, angleBetweenDeg(p(i, :) - p(i - 1, :), p(i + 1, :) - p(i, :)));
end
end

function deg = angleBetweenDeg(d1, d2)
deg = 0;
n1 = norm(d1);
n2 = norm(d2);
if n1 <= 1e-12 || n2 <= 1e-12
    return;
end
deg = acosd(max(-1, min(1, dot(d1, d2) / (n1 * n2))));
end

function tf = checkViaOverlap(cfg, vias)
tf = true;
for i = 1:numel(vias)
    for j = i + 1:numel(vias)
        d = norm(vias(i).xy - vias(j).xy);
        if d < cfg.viaPadDiameter + cfg.terminalClearance - 1e-9
            tf = false;
            return;
        end
    end
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

function dMin = minDistanceToHoles(points, holeLoops, batchSize)
dMin = inf;
nPts = size(points, 1);
first = 1;
while first <= nPts
    last = min(first + batchSize - 1, nPts);
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
        t = (ax .* dx + ay .* dy) ./ len2k;
        t = max(0, min(1, t));
        qx = A(:, 1).' + t .* dx;
        qy = A(:, 2).' + t .* dy;
        d = sqrt((P(:, 1) - qx).^2 + (P(:, 2) - qy).^2);
        dMin = min(dMin, min(d(:)));
    end
    first = last + 1;
end
end
