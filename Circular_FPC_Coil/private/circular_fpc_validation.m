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
    'traceWidth', 'traceSpacing', 'pitchMargin', 'edgeClearance', 'boardOutlineLineWidth', ...
    'platformSlotMargin', ...
    'padPairSpacing', 'terminalLeadSpacing', 'terminalLeadLength', ...
    'padDiameter', 'viaPadDiameter', 'viaDrillDiameter', 'viaCoilSpacing', ...
    'terminalClearance', 'copperThickness', 'copperResistivity', 'samplePointsPerTurn', 'turnScanMax', ...
    'minCopperInteriorAngleDeg', 'minBoardInteriorAngleDeg', 'angleToleranceDeg'};
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
% 匝数语义为物理 360° 圈数（spanTurns = turnsPerCoilLayer）；单匝完整圆环
% 未纳入端子引出与串联过孔拓扑的验证范围，因此仍要求至少 2 匝。
if cfg.turnsPerCoilLayer < 2
    error('CircularFPC:InvalidConfig', 'turnsPerCoilLayer must be at least 2.');
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
% 制造规则检查：唯一所有者 private/circular_fpc_manufacturing.m（ADR-1）。
% 必须在层组合确认后执行，避免未验证的 boardLayerCount 进入规则解析。
mfReport = circular_fpc_manufacturing('check_config', cfg);
if ~mfReport.passed
    error('CircularFPC:InvalidConfig', ...
        'Manufacturing rules violated: %s', strjoin(mfReport.failures, '; '));
end
if ~ismember(cfg.terminalPlacementMode, {'auto', 'manual'})
    error('CircularFPC:InvalidConfig', 'terminalPlacementMode must be ''auto'' or ''manual''.');
end
if ~ismember(cfg.boardSizingMode, {'auto', 'fixed'})
    error('CircularFPC:InvalidConfig', 'boardSizingMode must be ''auto'' or ''fixed''.');
end
for m = {'manualPadAXY', 'manualPadBXY', 'manualSeriesViaXY'}
    v = cfg.(m{1});
    if ~isnumeric(v) || (~isempty(v) && (size(v, 2) ~= 2 || any(~isfinite(v(:)))))
        error('CircularFPC:InvalidConfig', '%s must be empty or an Nx2 finite numeric matrix.', m{1});
    end
end
if strcmp(cfg.terminalPlacementMode, 'auto') && ...
        cfg.terminalLeadSpacing < cfg.padDiameter + cfg.terminalClearance - 1e-9
    error('CircularFPC:TerminalPlacementInvalid', ...
        ['terminalLeadSpacing d=%.6f mm is too small for PAD diameter %.6f mm ', ...
         'plus terminal clearance %.6f mm.'], ...
        cfg.terminalLeadSpacing, cfg.padDiameter, cfg.terminalClearance);
end
if ~islogical(cfg.enablePreview) || ~isscalar(cfg.enablePreview)
    error('CircularFPC:InvalidConfig', 'enablePreview must be a logical scalar.');
end
if ~islogical(cfg.enableFigure) || ~isscalar(cfg.enableFigure)
    error('CircularFPC:InvalidConfig', 'enableFigure must be a logical scalar.');
end
if ~islogical(cfg.analysisOnly) || ~isscalar(cfg.analysisOnly)
    error('CircularFPC:InvalidConfig', 'analysisOnly must be a logical scalar.');
end
if ~ischar(cfg.designName) || isempty(regexp(cfg.designName, '^[A-Za-z0-9_-]+$', 'once'))
    error('CircularFPC:InvalidConfig', 'designName must match [A-Za-z0-9_-]+.');
end
if ~ischar(cfg.outputRoot) || isempty(cfg.outputRoot)
    error('CircularFPC:InvalidConfig', 'outputRoot must be a nonempty character vector.');
end
end

function assertFeasible(cfg, eff)
% 生成前可行性校验（只做快速失败的硬检查，最终几何质量由 validate_result 实测把关）：
%   1) 线圈所需径向跨度（线宽 + 匝数*节距）必须小于环区可用跨度；
%   2) 平台最大半径不得超过 板外半径 - edgeClearance（配置荒谬时立即失败）。
% 平台四角允许进入内圆与环区相交，这正是四个自然对角连接区；只要求
% 平台水平/垂直边与内圆之间仍有槽余量，最终四槽拓扑由布尔结果验证。
coilPitch = eff.coilPitch;
requiredSpan = cfg.traceWidth + cfg.turnsPerCoilLayer * coilPitch;
boardEdgeInnerR = eff.boardOuterDiameter / 2 - cfg.boardOutlineLineWidth / 2;
availableSpan = boardEdgeInnerR - cfg.edgeClearance - eff.coilInnerDiameter / 2;
if availableSpan < requiredSpan - 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        'Coil radial span %.6f mm exceeds available annulus span %.6f mm.', requiredSpan, availableSpan);
end
platReach = roundedRectMaxRadius(eff.centerPlatformWidth, eff.centerPlatformHeight, 0);
usableInnerR = eff.coilInnerDiameter / 2 - cfg.edgeClearance;
platformSideReach = max(eff.centerPlatformWidth, eff.centerPlatformHeight) / 2;
requiredInnerR = platformSideReach + cfg.platformSlotMargin;
if usableInnerR < requiredInnerR - 1e-9
    minCoilInnerDiameter = 2 * (requiredInnerR + cfg.edgeClearance);
    error('CircularFPC:GeometryInfeasible', ...
        ['coilInnerDiameter %.6f mm is too small to retain four slots around the ', ...
         'axis-aligned %.3f x %.3f mm platform with %.3f mm side slot margin and ', ...
         '%.3f mm copper-to-slot clearance. Use at least %.6f mm.'], ...
        eff.coilInnerDiameter, eff.centerPlatformWidth, eff.centerPlatformHeight, ...
        cfg.platformSlotMargin, cfg.edgeClearance, minCoilInnerDiameter);
end
if platReach >= boardEdgeInnerR - cfg.edgeClearance - 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        ['Central platform %.3f x %.3f mm reaches %.3f mm from center, beyond ', ...
         'the board outer radius minus edge clearance (%.3f mm).'], ...
        eff.centerPlatformWidth, eff.centerPlatformHeight, platReach, ...
        boardEdgeInnerR - cfg.edgeClearance);
end
if eff.bridgeTargetWidth <= 0
    error('CircularFPC:GeometryInfeasible', 'Bridge width must be positive.');
end
end

function rMax = roundedRectMaxRadius(w, h, cornerR)
% 圆角矩形平台边界到中心的最大半径：最远点位于四段圆角弧上，
% = 弧心到中心的距离 + 圆角半径；cornerR=0 时退化为尖角半对角线。
% 正向矩形平台 cornerR=0 时为尖角半对角线；engine>platformFitAdvisories
% 使用同一公式。
halfW = w / 2;
halfH = h / 2;
r = min(cornerR, min(halfW, halfH));
rMax = sqrt((halfW - r)^2 + (halfH - r)^2) + r;
end

function v = validateResult(cfg, eff, geom)
% 结果指标校验。v 中的各项含义（写入 05_validation_report.txt）：
%   finiteCoordinates      : 所有坐标有限
%   noZeroLengthSegments   : 无零长度线段
%   noSelfIntersections    : 无自交折线
%   closedBoardLoopCount   : 板框闭环数（必须为 5 = 1 外边界 + 4 孔槽）
%   minCopperSpacingMm     : 铜线之间最小净距（须 ≥ traceSpacing）
%   minCopperToBoardMm     : 铜到板外缘最小距离（须 ≥ edgeClearance）
%   minViaToBoardMm        : 过孔焊盘切线到板框线内侧的最小距离
%   minDrillToBoardMm      : 钻孔切线到板框线内侧的最小距离
%   minViaToNonConnectedCopperMm : 通孔钻孔切线到非连接层铜的最小距离
%   minCopperToSlotsMm     : 铜/端子到孔槽最小距离（须 ≥ edgeClearance）
%   minPadViaClearanceMm   : 焊盘/过孔端子间最小净距
%   minTerminalToConnectionTraceMm : 功能端子铜盘到无关连接走线的最小净距
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
v.minCopperSpacingMm = computeCopperSpacing(cfg, eff, geom.coils, geom.connectionPaths, geom.pads, geom.vias);
v.minCopperToBoardMm = computeCopperToBoard(cfg, eff, geom.coils, geom.connectionPaths, geom.pads, geom.vias);
v.minViaToBoardMm = computeViaToBoard(cfg, eff, geom.vias);
v.minDrillToBoardMm = computeDrillToBoard(cfg, eff, geom.vias);
v.minViaToNonConnectedCopperMm = computeViaToNonConnectedCopper(cfg, geom.coils, geom.connectionPaths, geom.vias);
v.minCopperToSlotsMm = computeCopperToSlots(cfg, geom.boardLoops, geom.coils, geom.connectionPaths, geom.pads, geom.vias);
v.minPadViaClearanceMm = computeTerminalClearance(cfg, geom.pads, geom.vias);
v.minViaCoilSpacingMm = computeTerminalCoilSpacing(cfg, geom.coils, geom.vias, geom.pads);
v.minTerminalToConnectionTraceMm = computeTerminalToConnectionTrace( ...
    cfg, geom.connectionPaths, geom.vias, geom.pads);
v.minCopperInteriorAngleDeg = computeMinCopperInteriorAngle(geom.coils, geom.connectionPaths);
v.minBoardInteriorAngleDeg = computeMinBoardInteriorAngle(geom.boardLoops);
v.actualBridgeWidthMm = geom.actualBridgeWidth;
[v.uniqueSeriesNetwork, v.maxSeriesContinuityErrorMm] = ...
    checkSeriesRoute(geom.seriesRoute, geom.activeLayers, geom.vias);
v.maxConnectionTurnDeg = computeMaxConnectionTurnDeg(geom.connectionPaths, geom.seriesRoute, geom.coils);
v.viaOverlapFree = checkViaOverlap(cfg, geom.vias);
outerViaMask = strcmp({geom.vias.role}, 'OUTER_TRANSITION');
outerViaSweeps = [geom.vias(outerViaMask).contactSweepDeg];
outerViaSweeps = outerViaSweeps(isfinite(outerViaSweeps));
if isempty(outerViaSweeps)
    v.minOuterViaContactSweepDeg = inf;
    v.maxOuterViaContactSweepDeg = 0;
else
    v.minOuterViaContactSweepDeg = min(outerViaSweeps);
    v.maxOuterViaContactSweepDeg = max(outerViaSweeps);
end
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
if v.minViaToBoardMm < cfg.edgeClearance - 1e-9
    v.messages{end + 1} = 'via-pad tangent-to-board clearance below edgeClearance'; %#ok<AGROW>
end
mfRules = circular_fpc_manufacturing('resolve', cfg).rules;
if v.minDrillToBoardMm < mfRules.minDrillToBoardMm - 1e-9
    v.messages{end + 1} = 'drill-to-board clearance below manufacturing rule'; %#ok<AGROW>
end
if v.minViaToNonConnectedCopperMm < mfRules.minDrillToCopperMm - 1e-9
    v.messages{end + 1} = 'through-via drill-to-non-connected-layer copper clearance below manufacturing rule'; %#ok<AGROW>
end
if v.minCopperToSlotsMm < cfg.edgeClearance - 1e-9
    v.messages{end + 1} = 'copper-to-slot clearance below edgeClearance'; %#ok<AGROW>
end
if v.minViaCoilSpacingMm < cfg.viaCoilSpacing - 1e-9
    v.messages{end + 1} = 'via-to-coil spacing below viaCoilSpacing'; %#ok<AGROW>
end
if v.minTerminalToConnectionTraceMm < cfg.viaCoilSpacing - 1e-9
    v.messages{end + 1} = 'terminal-to-connection-trace spacing below viaCoilSpacing'; %#ok<AGROW>
end
% 全局角度规则：必须严格大于 阈值+数值容差；90° 直角本身不合法。
% 生成器应以圆弧/平滑曲线消除恰好 90° 或更尖锐的接续。
copperAngleFloor = cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg;
boardAngleFloor = cfg.minBoardInteriorAngleDeg + cfg.angleToleranceDeg;
if v.minCopperInteriorAngleDeg <= copperAngleFloor
    v.messages{end + 1} = 'copper path interior angle must be strictly greater than the minimum'; %#ok<AGROW>
end
if v.minBoardInteriorAngleDeg <= boardAngleFloor
    v.messages{end + 1} = 'board outline interior angle must be strictly greater than the minimum'; %#ok<AGROW>
end
if v.minOuterViaContactSweepDeg <= copperAngleFloor || v.maxOuterViaContactSweepDeg > 150
    v.messages{end + 1} = 'outer via contact arc sweep must be >90 degrees and <=150 degrees'; %#ok<AGROW>
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
    v.minViaToBoardMm >= cfg.edgeClearance - 1e-9 && ...
    v.minDrillToBoardMm >= mfRules.minDrillToBoardMm - 1e-9 && ...
    v.minViaToNonConnectedCopperMm >= mfRules.minDrillToCopperMm - 1e-9 && ...
    v.minCopperToSlotsMm >= cfg.edgeClearance - 1e-9 && ...
    v.minViaCoilSpacingMm >= cfg.viaCoilSpacing - 1e-9 && ...
    v.minTerminalToConnectionTraceMm >= cfg.viaCoilSpacing - 1e-9 && ...
    v.minCopperInteriorAngleDeg > copperAngleFloor && ...
    v.minBoardInteriorAngleDeg > boardAngleFloor && ...
    v.minOuterViaContactSweepDeg > copperAngleFloor && ...
    v.maxOuterViaContactSweepDeg <= 150 && ...
    v.actualBridgeWidthMm >= eff.bridgeTargetWidth - 1e-9 && ...
    v.uniqueSeriesNetwork && v.maxSeriesContinuityErrorMm <= 1e-9 && ...
    v.maxConnectionTurnDeg <= 10 && v.viaOverlapFree;
end

function degMin = computeMinCopperInteriorAngle(coils, connectionPaths)
% 所有铜走线路径（线圈 + 连接路径）的最小内角 [°]（180° = 直线，90° = 直角拐弯）。
% 规则：必须严格大于 阈值+容差（默认 >90.1°）；圆弧/贝塞尔平滑路径应远大于 90°。
degMin = 180;
for li = 1:numel(coils)
    xy = coils{li};
    if ~isempty(xy)
        degMin = min(degMin, polylineMinInteriorAngle(xy));
    end
    paths = connectionPaths{li};
    for k = 1:numel(paths)
        degMin = min(degMin, polylineMinInteriorAngle(paths{k}));
    end
end
end

function degMin = computeMinBoardInteriorAngle(boardLoops)
% 板框（外边界 + 挖空槽）所有闭环的最小内角 [°]。
% 规则：必须严格大于 阈值+容差；尖角由 filletHoleCorners 自动轻微圆角化。
degMin = 180;
for k = 1:numel(boardLoops)
    xy = boardLoops(k).xy;
    if size(xy, 1) >= 3
        degMin = min(degMin, polylineMinInteriorAngle(xy));
    end
end
end

function ang = polylineMinInteriorAngle(xy)
ang = 180;
n = size(xy, 1);
for i = 2:n - 1
    d1 = xy(i, :) - xy(i - 1, :);
    d2 = xy(i + 1, :) - xy(i, :);
    n1 = norm(d1);
    n2 = norm(d2);
    if n1 <= 1e-12 || n2 <= 1e-12
        continue;
    end
    c = dot(d1, d2) / (n1 * n2);
    dev = acosd(max(-1, min(1, c))); % 拐角偏离量 0..180
    ang = min(ang, 180 - dev);
end
end

function dMin = computeTerminalCoilSpacing(cfg, coils, vias, pads)
% 过孔焊环/焊盘外缘到其连接层上线圈铜边的最小净距（mm），须 >= cfg.viaCoilSpacing。
% 端点过孔（与线圈端点重合的引出端子）除外；线圈端点的"接入铜"（末端匝段，
% 与焊环同网络汇合）不参与净距；排除焊环 + 净距 + 半线宽 范围内的线段，
% 仅测量独立的相邻匝。
dMin = inf;
terms = struct('xy', {}, 'padDiameter', {}, 'layers', {});
for k = 1:numel(vias)
    v = vias(k);
    t = struct('xy', v.xy, 'padDiameter', v.padDiameter, ...
        'layers', unique([v.fromLayer, v.toLayer]));
    terms(end + 1) = t; %#ok<AGROW>
end
for k = 1:numel(pads)
    p = pads(k);
    t = struct('xy', p.xy, 'padDiameter', p.diameter, 'layers', p.layer);
    terms(end + 1) = t; %#ok<AGROW>
end
for k = 1:numel(terms)
    v = terms(k);
    for li = 1:numel(v.layers)
        xy = coils{v.layers(li)};
        if isempty(xy)
            continue;
        end
        zoneR = v.padDiameter / 2 + cfg.traceWidth / 2 + cfg.viaCoilSpacing;
        n = size(xy, 1);
        inZone = sum((xy - v.xy).^2, 2) <= zoneR^2;
        segMask = true(n - 1, 1);
        segMask(inZone(1:n - 1) | inZone(2:n)) = false;
        d = minDistanceToSegmentsMasked(v.xy, xy, segMask, 64);
        dMin = min(dMin, d - v.padDiameter / 2 - cfg.traceWidth / 2); % 铜边到铜边
    end
end
end

function dMin = minDistanceToSegmentsMasked(points, xy, segMask, batchSize)
% 点到折线的最小距离，跳过 segMask=false 的线段（过孔接入区）。
dMin = inf;
nPts = size(points, 1);
first = 1;
while first <= nPts
    last = min(first + batchSize - 1, nPts);
    P = points(first:last, :);
    nSeg = size(xy, 1) - 1;
    if nSeg >= 1
        A = xy(1:nSeg, :);
        B = xy(2:nSeg + 1, :);
        keep = segMask & (sum((B - A).^2, 2) > eps);
        A = A(keep, :);
        B = B(keep, :);
        if ~isempty(A)
            ax = P(:, 1) - A(:, 1).';
            ay = P(:, 2) - A(:, 2).';
            dx = (B(:, 1) - A(:, 1)).';
            dy = (B(:, 2) - A(:, 2)).';
            len2k = sum((B - A).^2, 2).';
            t = max(0, min(1, (ax .* dx + ay .* dy) ./ len2k));
            qx = A(:, 1).' + t .* dx;
            qy = A(:, 2).' + t .* dy;
            d = sqrt((P(:, 1) - qx).^2 + (P(:, 2) - qy).^2);
            dMin = min(dMin, min(d(:)));
        end
    end
    first = last + 1;
end
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
% Robust orientation test.  The previous denominator-based implementation
% ignored parallel/collinear overlap and also lost the denominator sign.
d1 = a2 - a1;
d2 = b2 - b1;
o1 = cross2(d1, b1 - a1);
o2 = cross2(d1, b2 - a1);
o3 = cross2(d2, a1 - b1);
o4 = cross2(d2, a2 - b1);
proper = ((o1 > tol & o2 < -tol) | (o1 < -tol & o2 > tol)) & ...
    ((o3 > tol & o4 < -tol) | (o3 < -tol & o4 > tol));
touch = (abs(o1) <= tol & pointsOnSegment(b1, a1, a2, tol)) | ...
    (abs(o2) <= tol & pointsOnSegment(b2, a1, a2, tol)) | ...
    (abs(o3) <= tol & pointOnSegments(a1, b1, b2, tol)) | ...
    (abs(o4) <= tol & pointOnSegments(a2, b1, b2, tol));
tf = proper | touch;
end

function z = cross2(a, b)
z = a(:, 1) .* b(:, 2) - a(:, 2) .* b(:, 1);
end

function tf = pointsOnSegment(p, a, b, tol)
tf = p(:, 1) >= min(a(1), b(1)) - tol & p(:, 1) <= max(a(1), b(1)) + tol & ...
    p(:, 2) >= min(a(2), b(2)) - tol & p(:, 2) <= max(a(2), b(2)) + tol;
end

function tf = pointOnSegments(p, a, b, tol)
tf = p(1) >= min(a(:, 1), b(:, 1)) - tol & p(1) <= max(a(:, 1), b(:, 1)) + tol & ...
    p(2) >= min(a(:, 2), b(:, 2)) - tol & p(2) <= max(a(:, 2), b(:, 2)) + tol;
end

function s = computeCopperSpacing(cfg, eff, coils, connectionPaths, pads, vias)
dMin = inf;
per = cfg.samplePointsPerTurn;
% 端子列表与焊环半径：路径端点若与某端子重合，则该端子焊环+净距带内的路径点
% 属于"端子附着铜"，其净距由 computeTerminalCoilSpacing 按其焊环规则单独把关，
% 不参与走线间间距（否则会把并网络/同网络的端子邻接区误判为间距违规，
% 如极端档小过孔下 V12 与 L2 匝的中心距 0.338 → 边缘 0.138 < traceSpacing 的假阳性）。
termXY = zeros(0, 2);
termR = zeros(0, 1);
for k = 1:numel(pads)
    termXY(end + 1, :) = pads(k).xy; %#ok<AGROW>
    termR(end + 1) = pads(k).diameter / 2; %#ok<AGROW>
end
for k = 1:numel(vias)
    termXY(end + 1, :) = vias(k).xy; %#ok<AGROW>
    termR(end + 1) = vias(k).padDiameter / 2; %#ok<AGROW>
end
zone = @(tR, p) tR + cfg.traceWidth / 2 + cfg.traceSpacing; % 附着带半径
nTerm = size(termXY, 1);
for li = 1:numel(coils)
    xy = coils{li};
    if isempty(xy)
        continue;
    end
    % A spiral's closest distinct copper is on the immediately adjacent
    % turn.  Compare the actual piecewise-linear segments at the matching
    % phase and its two neighbouring samples, rather than only vertices.
    nSeg = size(xy, 1) - 1;
    for phaseOffset = -2:2
        i = (1:nSeg).';
        j = i + per + phaseOffset;
        keepPair = j >= 1 & j <= nSeg;
        if any(keepPair)
            i = i(keepPair);
            j = j(keepPair);
            dMin = min(dMin, min(segmentPairDistances( ...
                xy(i, :), xy(i + 1, :), xy(j, :), xy(j + 1, :))));
        end
    end
end
for li = 1:numel(connectionPaths)
    Q = coils{li};
    paths = connectionPaths{li};
    for k = 1:numel(paths)
        Pfull = paths{k};
        if isempty(Pfull)
            continue;
        end
        % 端点若为端子，剔除其附着带内的路径点（端子净距单独把关）
        keep = true(size(Pfull, 1), 1);
        for e = 1:nTerm
            d0 = norm(Pfull(1, :) - termXY(e, :));
            if d0 <= 1e-9
                keep = keep & (sqrt(sum((Pfull - termXY(e, :)).^2, 2)) >= zone(termR(e), Pfull) - 1e-9 );
            end
            d1 = norm(Pfull(end, :) - termXY(e, :));
            if d1 <= 1e-9
                keep = keep & (sqrt(sum((Pfull - termXY(e, :)).^2, 2)) >= zone(termR(e), Pfull) - 1e-9);
            end
        end
        P = Pfull(keep, :);
        if size(P, 1) < 2
            continue;
        end
        if ~isempty(Q)
            Qa = Q;
            if norm(Pfull(end, :) - Q(1, :)) <= 1e-6
                Qa = Qa(min(size(Qa, 1), per + 1):end, :);
            end
            if norm(Pfull(1, :) - Q(end, :)) <= 1e-6
                Qa = Qa(1:max(1, size(Qa, 1) - per), :);
            end
            if ~isempty(Qa)
                dMin = min(dMin, polylineDistance(P, Qa));
            end
        end
        for k2 = k + 1:numel(paths)
            R = paths{k2};
            if isempty(R)
                continue;
            end
            keepR = true(size(R, 1), 1);
            for e = 1:nTerm
                if norm(R(1, :) - termXY(e, :)) <= 1e-9
                    keepR = keepR & (sqrt(sum((R - termXY(e, :)).^2, 2)) >= zone(termR(e), R) - 1e-9);
                end
                if norm(R(end, :) - termXY(e, :)) <= 1e-9
                    keepR = keepR & (sqrt(sum((R - termXY(e, :)).^2, 2)) >= zone(termR(e), R) - 1e-9);
                end
            end
            R2 = R(keepR, :);
            if size(R2, 1) < 2 || size(P, 1) < 2
                continue;
            end
            dMin = min(dMin, polylineDistance(P, R2));
        end
    end
end
s = dMin - cfg.traceWidth;
end

function dMin = polylineDistance(p, q)
% Exact minimum distance between all finite segments of two polylines.
if size(p, 1) < 2 || size(q, 1) < 2
    dMin = inf;
    return;
end
pa = p(1:end - 1, :);
pb = p(2:end, :);
qa = q(1:end - 1, :);
qb = q(2:end, :);
dMin = inf;
chunkSize = 128;
for first = 1:chunkSize:size(pa, 1)
    last = min(size(pa, 1), first + chunkSize - 1);
    nP = last - first + 1;
    nQ = size(qa, 1);
    a1 = repelem(pa(first:last, :), nQ, 1);
    a2 = repelem(pb(first:last, :), nQ, 1);
    b1 = repmat(qa, nP, 1);
    b2 = repmat(qb, nP, 1);
    dMin = min(dMin, min(segmentPairDistances(a1, a2, b1, b2)));
end
end

function d = segmentPairDistances(a1, a2, b1, b2)
% Exact Euclidean distance for corresponding 2-D segment pairs.
d = min([pointSegmentDistances(a1, b1, b2), ...
    pointSegmentDistances(a2, b1, b2), ...
    pointSegmentDistances(b1, a1, a2), ...
    pointSegmentDistances(b2, a1, a2)], [], 2);
% Endpoint distances alone are nonzero for a proper crossing.
d(segmentsIntersectRows(a1, a2, b1, b2, 1e-12)) = 0;
end

function d = pointSegmentDistances(p, a, b)
ab = b - a;
len2 = sum(ab.^2, 2);
t = zeros(size(len2));
valid = len2 > eps;
t(valid) = sum((p(valid, :) - a(valid, :)) .* ab(valid, :), 2) ./ len2(valid);
t = max(0, min(1, t));
q = a + t .* ab;
d = sqrt(sum((p - q).^2, 2));
end

function tf = segmentsIntersectRows(a1, a2, b1, b2, tol)
d1 = a2 - a1;
d2 = b2 - b1;
o1 = cross2(d1, b1 - a1);
o2 = cross2(d1, b2 - a1);
o3 = cross2(d2, a1 - b1);
o4 = cross2(d2, a2 - b1);
proper = ((o1 > tol & o2 < -tol) | (o1 < -tol & o2 > tol)) & ...
    ((o3 > tol & o4 < -tol) | (o3 < -tol & o4 > tol));
touch = (abs(o1) <= tol & pointRowsOnSegments(b1, a1, a2, tol)) | ...
    (abs(o2) <= tol & pointRowsOnSegments(b2, a1, a2, tol)) | ...
    (abs(o3) <= tol & pointRowsOnSegments(a1, b1, b2, tol)) | ...
    (abs(o4) <= tol & pointRowsOnSegments(a2, b1, b2, tol));
tf = proper | touch;
end

function tf = pointRowsOnSegments(p, a, b, tol)
tf = p(:, 1) >= min(a(:, 1), b(:, 1)) - tol & p(:, 1) <= max(a(:, 1), b(:, 1)) + tol & ...
    p(:, 2) >= min(a(:, 2), b(:, 2)) - tol & p(:, 2) <= max(a(:, 2), b(:, 2)) + tol;
end

function s = computeCopperToBoard(cfg, eff, coils, connectionPaths, pads, vias)
% 板框 DXF/SVG 轮廓以中心线表示，实体内侧边界位于中心线内
% boardOutlineLineWidth/2。所有铜均按实际外缘计算到该内侧边界的净距。
boardEdgeInnerR = eff.boardOuterDiameter / 2 - cfg.boardOutlineLineWidth / 2;
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
    dMin = min(dMin, min(boardEdgeInnerR - r) - cfg.traceWidth / 2); % 走线中心线减半线宽
end
for k = 1:numel(pads)
    dMin = min(dMin, boardEdgeInnerR - (norm(pads(k).xy) + pads(k).diameter / 2));
end
for k = 1:numel(vias)
    dMin = min(dMin, boardEdgeInnerR - (norm(vias(k).xy) + vias(k).padDiameter / 2));
end
s = dMin;
end

function s = computeViaToBoard(cfg, eff, vias)
% 过孔焊盘切线到板框线内侧边界的距离；这是四层通孔外移后的板径约束。
boardEdgeInnerR = eff.boardOuterDiameter / 2 - cfg.boardOutlineLineWidth / 2;
s = inf;
for k = 1:numel(vias)
    s = min(s, boardEdgeInnerR - (norm(vias(k).xy) + vias(k).padDiameter / 2));
end
end

function s = computeDrillToBoard(cfg, eff, vias)
% 钻孔切线到板框线内侧边界的距离（嘉立创规则：默认至少 0.176 mm）。
boardEdgeInnerR = eff.boardOuterDiameter / 2 - cfg.boardOutlineLineWidth / 2;
s = inf;
for k = 1:numel(vias)
    s = min(s, boardEdgeInnerR - (norm(vias(k).xy) + vias(k).drillDiameter / 2));
end
end

function s = computeViaToNonConnectedCopper(cfg, coils, connectionPaths, vias)
% 通孔会穿过所有物理层：非连接层移除非功能焊盘且不生成禁铜圈，
% 仍须按“实际钻孔切线到铜边”检查，不能只检查过孔连接的两层。
s = inf;
for k = 1:numel(vias)
    v = vias(k);
    connected = [v.fromLayer, v.toLayer];
    for li = 1:numel(coils)
        if ismember(li, connected)
            continue;
        end
        copper = coils{li};
        paths = connectionPaths{li};
        if ~isempty(copper)
            s = min(s, pointToCopperEdge(v.xy, copper) - v.drillDiameter / 2 - cfg.traceWidth / 2);
        end
        for p = 1:numel(paths)
            if ~isempty(paths{p})
                s = min(s, pointToCopperEdge(v.xy, paths{p}) - v.drillDiameter / 2 - cfg.traceWidth / 2);
            end
        end
    end
end
end

function d = pointToCopperEdge(point, xy)
% 点到折线中心线的最短距离；调用者再扣除钻孔和铜线半径。
if size(xy, 1) < 2
    d = inf;
    return;
end
a = xy(1:end - 1, :);
b = xy(2:end, :);
ab = b - a;
len2 = sum(ab.^2, 2);
valid = len2 > eps;
if ~any(valid)
    d = inf;
    return;
end
a = a(valid, :);
ab = ab(valid, :);
len2 = len2(valid);
t = ((point(1) - a(:, 1)) .* ab(:, 1) + (point(2) - a(:, 2)) .* ab(:, 2)) ./ len2;
t = max(0, min(1, t));
q = a + t .* ab;
d = min(sqrt(sum((q - point).^2, 2)));
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
% 铜走线与槽边用完整 segment-to-segment 精确距离：最近点可落在线段中部，
% 仅测顶点会高估净距（minDistanceToHoles 是点到线段，只适合圆盘端子）。
dMin = inf;
for li = 1:numel(coils)
    paths = [{coils{li}}, connectionPaths{li}];
    for k = 1:numel(paths)
        path = paths{k};
        if isempty(path)
            continue;
        end
        if size(path, 1) < 2
            dMin = min(dMin, ...
                minDistanceToHoles(path, holeLoops, 256) - cfg.traceWidth / 2);
            continue;
        end
        for h = 1:numel(holeLoops)
            dMin = min(dMin, ...
                polylineDistance(path, holeLoops{h}) - cfg.traceWidth / 2);
        end
    end
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

function dMin = computeTerminalToConnectionTrace( ...
    cfg, connectionPaths, vias, pads)
% Functional terminal copper disks versus every same-layer connection trace.
% Only the contiguous attachment segment of a path that actually terminates
% at the disk is exempt; unrelated paths and later path re-entry are measured.
dMin = inf;
terms = struct('xy', {}, 'radius', {}, 'layers', {});
for k = 1:numel(vias)
    terms(end + 1) = struct( ... %#ok<AGROW>
        'xy', vias(k).xy, ...
        'radius', vias(k).padDiameter / 2, ...
        'layers', unique([vias(k).fromLayer, vias(k).toLayer]));
end
for k = 1:numel(pads)
    terms(end + 1) = struct( ... %#ok<AGROW>
        'xy', pads(k).xy, ...
        'radius', pads(k).diameter / 2, ...
        'layers', pads(k).layer);
end

for termIndex = 1:numel(terms)
    term = terms(termIndex);
    zoneRadius = term.radius + cfg.traceWidth / 2 + cfg.viaCoilSpacing;
    for layerIndex = term.layers
        paths = connectionPaths{layerIndex};
        for pathIndex = 1:numel(paths)
            path = paths{pathIndex};
            if size(path, 1) < 2
                continue;
            end
            segmentMask = true(size(path, 1) - 1, 1);
            inZone = sqrt(sum((path - term.xy).^2, 2)) <= ...
                zoneRadius + 1e-9;
            if norm(path(1, :) - term.xy) <= 1e-9
                firstOutside = find(~inZone, 1, 'first');
                if isempty(firstOutside)
                    segmentMask(:) = false;
                else
                    segmentMask(1:firstOutside - 1) = false;
                end
            end
            if norm(path(end, :) - term.xy) <= 1e-9
                lastOutside = find(~inZone, 1, 'last');
                if isempty(lastOutside)
                    segmentMask(:) = false;
                else
                    segmentMask(lastOutside:end) = false;
                end
            end
            centerDistance = minDistanceToSegmentsMasked( ...
                term.xy, path, segmentMask, 1);
            dMin = min(dMin, centerDistance - term.radius - ...
                cfg.traceWidth / 2);
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
