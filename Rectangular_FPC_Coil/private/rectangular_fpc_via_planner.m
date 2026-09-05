function varargout = rectangular_fpc_via_planner(operation, varargin)
%RECTANGULAR_FPC_VIA_PLANNER Series and output-via placement.

switch operation
    case 'plan_vias'
        [varargout{1:nargout}] = planVias(varargin{:});
    case 'auto_output_via'
        [varargout{1:nargout}] = calculateAutoOutputVia(varargin{:});
    case 'validate_board_location'
        [varargout{1:nargout}] = validateViaBoardLocation(varargin{:});
    otherwise
        error('RectangularFPC:UnknownViaPlannerOperation', ...
            'Unknown via planner operation: %s', operation);
end
end

function [vias, failureCode, failureReason] = planVias(cfg, spiralInfo)
%FPC_COIL_PLAN_VIAS 规划全部层间串联过孔（V12、V23、……）的位置。
%   [VIAS, FAILURECODE, FAILUREREASON] = FPC_COIL_PLAN_VIAS(CFG, SPIRALINFO)
%
%   SPIRALINFO 结构（内部坐标，主体中心原点）：
%     innerHalfL, innerHalfW   内圈铜线中心线半长/半宽（mm）
%     innerRadius              内圈圆角半径（mm）
%     endPoints                (layerCount+1) 行结构，endPoints(k) 为
%                              Lk 与 L(k+1) 的共享连接点（raw，未加引线）
%     endTangents              (layerCount+1) 行，endTangents(k) 为
%                              Lk 末端切线单位向量（指向连接点）
%
%   返回：
%     VIAS          (layerCount-1) 行结构数组，字段：
%                   name, xy（内部坐标）, fromLayer, toLayer,
%                   placementRegion（'INNER_BLANK'/'RIGHT_TAB'）,
%                   placementMode（'legacy_auto'/'hybrid_auto'/'manual'）,
%                   padDiameter, drillDiameter,
%                   fromLeadLength, toLeadLength（后续布线填充，初始 NaN）,
%                   fromLeadPath, toLeadPath（后续布线填充，初始 []）
%     FAILURECODE   '' 或 'MANUAL_VIA_INVALID'/'TAB_VIA_CAPACITY'/
%                   'INNER_VIA_CAPACITY'/'VIA_TO_COPPER_CLEARANCE'/
%                   'VIA_TO_BOARD_CLEARANCE'/'VIA_TO_PAD_CLEARANCE'
%     FAILUREREASON 人类可读的中文原因（'' 表示成功）

failureCode = '';
failureReason = '';

viaTemplate = struct( ...
    'name', '', 'xy', [0, 0], 'fromLayer', 0, 'toLayer', 0, ...
    'placementRegion', '', 'placementMode', '', ...
    'padDiameter', cfg.viaPadDiameter, 'drillDiameter', cfg.viaDrillDiameter, ...
    'fromLeadLength', NaN, 'toLeadLength', NaN, ...
    'fromLeadPath', [], 'toLeadPath', []);

vias = repmat(viaTemplate, cfg.layerCount - 1, 1);
for k = 1:cfg.layerCount - 1
    vias(k).name = sprintf('V%d%d', k, k + 1);
    vias(k).fromLayer = k;
    vias(k).toLayer = k + 1;
end

switch cfg.viaPlacementMode
    case 'legacy_auto'
        % 保留旧版行为：过孔位于螺旋端点附近（内圈沿内法线、外圈沿 +X）。
        for k = 1:cfg.layerCount - 1
            endpoint = spiralInfo.endPoints(k).xy;
            if mod(k, 2) == 1
                inward = spiralInfo.endPoints(k).inwardNormal;   % 指向中心空白
                xy = endpoint + inward*cfg.viaLandingLeadLength;
                region = 'INNER_BLANK';
            else
                xy = endpoint + [cfg.viaOuterLandingLeadLength, 0];
                region = 'RIGHT_TAB';
            end
            vias(k).xy = xy;
            vias(k).placementRegion = region;
            vias(k).placementMode = 'legacy_auto';
        end

    case 'hybrid_auto'
        [vias, failureCode, failureReason] = planHybridAuto(cfg, vias, spiralInfo);

    case 'manual'
        [vias, failureCode, failureReason] = planManual(cfg, vias);

    otherwise
        failureCode = 'UNKNOWN';
        failureReason = sprintf('未知过孔放置模式 ''%s''。', cfg.viaPlacementMode);
end

end

%% ---------------------------------------------------------------

function [vias, failureCode, failureReason] = planHybridAuto(cfg, vias, spiralInfo)

failureCode = '';
failureReason = '';
tol = cfg.geometryTolerance;

innerHalfL = spiralInfo.innerHalfL;
innerHalfW = spiralInfo.innerHalfW;
innerRadius = spiralInfo.innerRadius;

% 过孔焊盘中心到内圈铜线中心线的最小要求距离
requiredViaToCopperCenter = ...
    cfg.viaPadDiameter/2 + cfg.traceWidth/2 + cfg.viaToCopperClearance + cfg.viaKeepoutMargin;

% 内圈空白禁布边界（内圈铜线中心线再内缩 padD/2+clearance+keepout）
% 圆角矩形近似：把内圈中心线按距离 d 内缩得到的矩形。
innerClearHalfL = innerHalfL - requiredViaToCopperCenter - cfg.traceWidth/2;
innerClearHalfW = innerHalfW - requiredViaToCopperCenter - cfg.traceWidth/2;

% ---- 内圈过孔（奇数编号：V12、V34、V56、V78）----
innerIndices = find(mod(1:cfg.layerCount-1, 2) == 1);
innerCount = numel(innerIndices);
if innerCount > 0
    minimumViaPitch = cfg.viaPadDiameter + cfg.viaToViaClearance;
    actualViaPitch = max(cfg.innerViaPitch, minimumViaPitch);
    rowSpan = (innerCount - 1) * actualViaPitch;

    if rowSpan > 2*innerClearHalfL + tol
        failureCode = 'INNER_VIA_CAPACITY';
        failureReason = sprintf( ...
            ['内圈空白区域不足以横向排列 %d 个过孔：所需长度 %.3f mm，', ...
             '可用长度 %.3f mm。建议减小内圈过孔数量、增大板尺寸或使用手动坐标。'], ...
            innerCount, rowSpan, 2*innerClearHalfL);
        return;
    end

    % Y 方向搜索：优先 innerViaRowOffsetY，失败则按 autoViaGridStep 上下搜索
    yMax = max(0, innerClearHalfW - cfg.viaPadDiameter/2 - cfg.viaKeepoutMargin);
    yMin = -yMax;
    yy = cfg.innerViaRowOffsetY;
    step = cfg.autoViaGridStep;
    yList = [];
    if yy >= yMin && yy <= yMax
        yList = [yList, yy];
    end
    if step > 0
        yList = unique([yList, yy + step*(1:ceil((yMax-yy)/step)), ...
            yy - step*(1:ceil((yy-yMin)/step))]);
    end
    yList = yList(yList >= yMin - tol & yList <= yMax + tol);

    placed = false;
    bestMargin = -inf;
    bestDistance = inf;
    bestXY = zeros(innerCount, 2);
    anchorXY = zeros(innerCount, 2);
    for m = 1:innerCount
        anchorXY(m, :) = spiralInfo.endPoints(innerIndices(m)).xy;
    end
    xs = innerClearHalfL - (0:innerCount-1)' * actualViaPitch;
    for yi = yList
        ys = repmat(yi, innerCount, 1);
        candXY = [xs, ys];
        ok = true;
        margin = inf;
        % 每个过孔：在禁布区内、与相邻过孔互距、与内圈铜线净距
        for m = 1:innerCount
            if ~pointInsideClearRect(candXY(m,:), innerClearHalfL, innerClearHalfW, innerRadius - cfg.traceWidth/2 - cfg.viaKeepoutMargin, tol)
                ok = false;
                break;
            end
            if m > 1 && norm(candXY(m,:) - candXY(m-1,:)) < actualViaPitch - tol
                ok = false;
                break;
            end
            dist = pointToRoundedRectCenterline(candXY(m,:), innerHalfL, innerHalfW, innerRadius);
            m_ = dist - requiredViaToCopperCenter;
            if m_ < -tol
                ok = false;
                break;
            end
            margin = min(margin, m_);
        end
        if ok
            anchorDistance = sum(vecnorm(candXY - anchorXY, 2, 2));
            if anchorDistance < bestDistance - tol || ...
                    (abs(anchorDistance - bestDistance) <= tol && margin > bestMargin)
                bestDistance = anchorDistance;
                bestMargin = margin;
                bestXY = candXY;
                placed = true;
            end
        end
    end
    if ~placed
        failureCode = 'INNER_VIA_CAPACITY';
        failureReason = sprintf( ...
            ['无法在内圈空白区域放置 %d 个横向排列过孔（行 Y=%.3f mm 及其邻近行均失败）。', ...
             '内圈空白半宽 %.3f mm、半长 %.3f mm。'], ...
            innerCount, cfg.innerViaRowOffsetY, innerClearHalfW, innerClearHalfL);
        return;
    end
    for m = 1:innerCount
        k = innerIndices(m);
        vias(k).xy = bestXY(m, :);
        vias(k).placementRegion = 'INNER_BLANK';
        vias(k).placementMode = 'hybrid_auto';
    end
end

% ---- 尾板过孔（偶数编号：V23、V45、V67）----
outerIndices = find(mod(1:cfg.layerCount-1, 2) == 0);
outerCount = numel(outerIndices);
if outerCount > 0
    [okTab, tabXY, tabReason] = planTabVias(cfg, outerIndices, outerCount, spiralInfo);
    if ~okTab
        failureCode = tabReason;
        return;
    end
    for m = 1:outerCount
        k = outerIndices(m);
        vias(k).xy = tabXY(m, :);
        vias(k).placementRegion = 'RIGHT_TAB';
        vias(k).placementMode = 'hybrid_auto';
    end
end

end

%% ---------------------------------------------------------------

function [ok, tabXY, failureCode] = planTabVias(cfg, outerIndices, outerCount, spiralInfo)

ok = false;
tabXY = zeros(outerCount, 2);
tol = cfg.geometryTolerance;

bodyRightX = cfg.plateLength/2;
tabTipX = bodyRightX + cfg.tabLength;
tabHalf = cfg.tabWidth/2;

% 尾板内部可用区域（扣除过孔 pad 半径 + 到板框净距 + 右端圆角区）
% 过孔中心到板框（含圆角弧）距离须 ≥ padR + viaToBoardClearance；
% 右端圆角圆心在 (tabTipX - tabRadius, 0)，过孔须在圆外且距弧足够。
xMin = bodyRightX + cfg.viaPadDiameter/2 + cfg.viaToBoardClearance;
tabRadius = cfg.tabOuterCornerRadius;
xTabArcCenter = tabTipX - tabRadius;
xMax = xTabArcCenter - (tabRadius + cfg.viaPadDiameter/2 + cfg.viaToBoardClearance);
yMax = tabHalf - cfg.viaPadDiameter/2 - cfg.viaToBoardClearance;

% 固定禁布对象：PAD_A、PAD_B、VOUT（内部坐标）
padA = [tabTipX - cfg.padTipInset, +cfg.leadYOffset];
padB = [tabTipX - cfg.padTipInset, -cfg.leadYOffset];
outputVia = calculateAutoOutputVia(cfg);
pads = [padA; padB];
% L1 回路线（VOUT→padB 直线）
returnLeadA = outputVia;
returnLeadB = padB;

minPadDist = cfg.viaPadDiameter/2 + cfg.padDiameter/2 + cfg.viaToPadClearance;
minViaToReturn = cfg.viaPadDiameter/2 + cfg.traceWidth/2 + cfg.outputViaToCopperClearance;
minViaToVia = cfg.viaPadDiameter + cfg.viaToViaClearance;

% 估算可用长度（扣除 PAD/VOUT 占位后）：
% 把 pads 与 outputVia 视为需要横向避让的禁布圆心。
% 候选 X 从 xMin 起按最小节距向右紧凑排列
minCandidatePitch = max(cfg.outerViaPitch, minViaToVia);
needLength = (outerCount - 1)*minCandidatePitch;
if needLength > (xMax - xMin) + tol
    failureCode = 'TAB_VIA_CAPACITY';
    return;
end

% Y 搜索
yLim = max(0, yMax - cfg.viaPadDiameter/2 - cfg.viaKeepoutMargin);
step = cfg.autoViaGridStep;
yList = [];
yy = cfg.outerViaRowOffsetY;
if yy >= -yLim && yy <= yLim
    yList = [yList, yy];
end
if step > 0
    yList = unique([yList, yy + step*(1:ceil((yLim-yy)/step)), ...
        yy - step*(1:ceil((yLim+yy)/step))]);
end
yList = yList(yList >= -yLim - tol & yList <= yLim + tol);

bestMargin = -inf;
bestDistance = inf;
bestOffsetDistance = inf;
bestXY = [];
anchorXY = zeros(outerCount, 2);
for m = 1:outerCount
    anchorXY(m, :) = spiralInfo.endPoints(outerIndices(m)).xy;
end
xs = xMin + (0:outerCount-1)' * minCandidatePitch;
for yi = yList
    % 沿 X 从左向右（靠近锚点）紧凑排列，保持中心距
    cand = [xs, repmat(yi, outerCount, 1)];
    margin = inf;
    conflict = false;
    for m = 1:outerCount
        if m > 1 && norm(cand(m,:) - cand(m-1,:)) < minViaToVia - tol
            conflict = true;
            break;
        end
        % 到 PAD/VOUT 中心距
        for p = 1:size(pads,1)
            if norm(cand(m,:) - pads(p,:)) < minPadDist - tol
                conflict = true;
                break;
            end
        end
        if conflict, break; end
        if norm(cand(m,:) - outputVia) < minViaToVia - tol
            conflict = true;
            break;
        end
        % 到 L1 回路线
        dReturn = distancePointToSegment(cand(m,:), returnLeadA, returnLeadB);
        if dReturn < minViaToReturn - tol
            conflict = true;
            break;
        end
        % 余量
        mPad = min(norm(cand(m,:) - pads(1,:)), norm(cand(m,:) - pads(2,:)));
        margin = min(margin, min(mPad - minPadDist, dReturn - minViaToReturn));
    end
    if ~conflict
        anchorDistance = sum(vecnorm(cand - anchorXY, 2, 2));
        offsetDistance = abs(yi - cfg.outerViaRowOffsetY);
        if offsetDistance < bestOffsetDistance - tol || ...
                (abs(offsetDistance - bestOffsetDistance) <= tol && ...
                (anchorDistance < bestDistance - tol || ...
                (abs(anchorDistance - bestDistance) <= tol && ...
                margin > bestMargin)))
            bestOffsetDistance = offsetDistance;
            bestDistance = anchorDistance;
            bestMargin = margin;
            bestXY = cand;
        end
    end
end

if isempty(bestXY)
    failureCode = 'TAB_VIA_CAPACITY';
    return;
end
tabXY = bestXY;
ok = true;
failureCode = '';

end

function outputVia = calculateAutoOutputVia(cfg)

requiredBoardClearance = max( ...
    cfg.outputViaToBoardClearance, cfg.viaToBoardClearance);
safeX = cfg.plateLength/2 + cfg.viaPadDiameter/2 + ...
    requiredBoardClearance;
maxX = cfg.plateLength/2 + cfg.tabLength - cfg.outputViaTipInset;
if safeX > maxX + cfg.geometryTolerance
    error('RectangularFPC:ViaPlanningFailed', ...
        '自动 VOUT 可用横向区间为空：安全左界 %.3f mm 大于最小内缩右界 %.3f mm。', ...
        safeX, maxX);
end
outputVia = [safeX, -cfg.leadYOffset];

end

%% ---------------------------------------------------------------

function [vias, failureCode, failureReason] = planManual(cfg, vias)

failureCode = '';
failureReason = '';

xyUser = cfg.manualSeriesViaXY;
manualBoardXY = rectangular_fpc_board_geometry('board_outline', cfg);
closedManualBoardXY = [manualBoardXY; manualBoardXY(1, :)];
% 防御性行数检查：manualSeriesViaXY 必须恰好 layerCount-1 行（V12、V23……）。
% 过孔规划可能在配置验证之外被内部复用，因此在此复查。
if size(xyUser, 1) ~= cfg.layerCount - 1
    failureCode = 'MANUAL_VIA_INVALID';
    failureReason = sprintf( ...
        'manualSeriesViaXY 必须恰好为 layerCount-1=%d 行（依次对应 V12、V23……），当前为 %d 行。', ...
        cfg.layerCount - 1, size(xyUser, 1));
    return;
end
for k = 1:cfg.layerCount - 1
    xy = rectangular_fpc_path_geometry('user_to_internal', xyUser(k, :), cfg);
    [ok, reason] = validateManualVia( ...
        cfg, k, xy, vias, closedManualBoardXY);
    if ~ok
        failureCode = 'MANUAL_VIA_INVALID';
        failureReason = sprintf( ...
            '%s 手动坐标 (%.3f, %.3f) mm 无效：%s', ...
            vias(k).name, xyUser(k,1), xyUser(k,2), reason);
        return;
    end
    vias(k).xy = xy;
    vias(k).placementMode = 'manual';
    vias(k).placementRegion = '';
end

end

%% ---------------------------------------------------------------

function [ok, reason] = validateManualVia(cfg, k, xy, vias, closedBoardXY)

ok = false;
reason = '';
tol = cfg.geometryTolerance;

[inBoard, centerToBoard, requiredDistance] = validateViaBoardLocation( ...
    xy, cfg.viaPadDiameter, cfg.viaToBoardClearance, ...
    closedBoardXY, tol);
if ~inBoard
    reason = sprintf( ...
        '过孔焊盘未完整位于真实圆角板框内：中心到板框 %.3f mm，要求至少 %.3f mm。', ...
        centerToBoard, requiredDistance);
    return;
end

% 与其他已放置过孔互距
for j = 1:k - 1
    if norm(xy - vias(j).xy) < cfg.viaPadDiameter + cfg.viaToViaClearance - tol
        reason = sprintf('与 %s 中心距 %.3f mm 不足 %.3f mm。', ...
            vias(j).name, norm(xy - vias(j).xy), ...
            cfg.viaPadDiameter + cfg.viaToViaClearance);
        return;
    end
end

ok = true;
end

function [ok, centerToBoard, requiredDistance] = validateViaBoardLocation( ...
    xy, padDiameter, clearance, closedBoardXY, tol)

[inside, onBoundary] = inpolygon( ...
    xy(1), xy(2), closedBoardXY(:, 1), closedBoardXY(:, 2));
centerToBoard = inf;
for segmentIndex = 1:size(closedBoardXY, 1) - 1
    centerToBoard = min(centerToBoard, distancePointToSegment( ...
        xy, closedBoardXY(segmentIndex, :), ...
        closedBoardXY(segmentIndex + 1, :)));
end
requiredDistance = padDiameter / 2 + clearance;
ok = (inside || onBoundary) && ...
    centerToBoard >= requiredDistance - tol;
end

%% ---------------------------------------------------------------

function inside = pointInsideClearRect(p, halfL, halfW, cornerR, tol)
% 点是否在圆角矩形禁布边界内部（中心原点，半长 halfL，半宽 halfW，圆角 cornerR）
inside = false;
% 矩形主体部分
if abs(p(1)) <= halfL && abs(p(2)) <= halfW
    inside = true;
    return;
end
% 角部圆弧（右上、右下、左上、左下）
cx = [ halfL - cornerR,  halfL - cornerR, -halfL + cornerR, -halfL + cornerR];
cy = [ halfW - cornerR, -halfW + cornerR,  halfW - cornerR, -halfW + cornerR];
for a = 1:4
    d = norm(p - [cx(a), cy(a)]);
    if d <= cornerR + tol
        inside = true;
        return;
    end
end
end

%% ---------------------------------------------------------------

function d = pointToRoundedRectCenterline(p, halfL, halfW, cornerR)
% 点到圆角矩形中心线的最近距离（中心原点）
% 到 4 条直边距离
dRect = min([abs(abs(p(1)) - halfL), abs(abs(p(2)) - halfW)]);
% 到 4 个角圆弧中心距离 - cornerR
cx = [ halfL - cornerR,  halfL - cornerR, -halfL + cornerR, -halfL + cornerR];
cy = [ halfW - cornerR, -halfW + cornerR,  halfW - cornerR, -halfW + cornerR];
dArc = inf;
for a = 1:4
    dArc = min(dArc, abs(norm(p - [cx(a), cy(a)]) - cornerR));
end
% 点在矩形内部时 dRect 为到边的距离（负数区域取绝对值会偏大），
% 需要取到边界的最小距离：若点在内部，取到各边/圆弧的最小距离。
if abs(p(1)) <= halfL && abs(p(2)) <= halfW
    dInside = min([halfL - abs(p(1)), halfW - abs(p(2))]);
    d = dInside;
else
    d = min(dRect, dArc);
end
end

%% ---------------------------------------------------------------

function d = distancePointToSegment(p, a, b)
v = b - a;
w = p - a;
c = max(0, min(1, dot(w, v)/dot(v, v)));
d = norm(w - c*v);
end
