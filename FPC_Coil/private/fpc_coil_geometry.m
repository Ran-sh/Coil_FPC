function varargout = fpc_coil_geometry(operation, varargin)
%FPC_COIL_GEOMETRY Private geometry dispatcher for the FPC runtime.
%   Supported operations:
%     'turn_limits'      -> calculateTurnLimits(cfg)
%     'spiral'           -> generateSpiral(cfg, limits, direction)
%     'plan_vias'        -> planVias(cfg, spiralInfo)
%     'smooth_lead'      -> routeSmoothLead(startPt, startTangent, endPt, bendRadius, arcPointCount, tol)
%     'user_to_internal' -> userToInternalXY(xyUser, cfg)
%     'internal_to_user' -> internalToUserXY(xyInternal, cfg)
%     'auto_output_via'  -> calculateAutoOutputVia(cfg)

switch operation
    case 'turn_limits'
        [varargout{1:nargout}] = calculateTurnLimits(varargin{:});
    case 'spiral'
        [varargout{1:nargout}] = generateSpiral(varargin{:});
    case 'plan_vias'
        [varargout{1:nargout}] = planVias(varargin{:});
    case 'smooth_lead'
        [varargout{1:nargout}] = routeSmoothLead(varargin{:});
    case 'user_to_internal'
        [varargout{1:nargout}] = userToInternalXY(varargin{:});
    case 'internal_to_user'
        [varargout{1:nargout}] = internalToUserXY(varargin{:});
    case 'auto_output_via'
        [varargout{1:nargout}] = calculateAutoOutputVia(varargin{:});
    otherwise
        error('FPC_Coil:UnknownGeometryOperation', ...
            'Unknown geometry operation: %s', operation);
end

end
function limits = calculateTurnLimits(cfg)
%FPC_COIL_CALCULATE_TURN_LIMITS 计算所有解析（非几何验证）匝数上限。
%   LIMITS = FPC_COIL_CALCULATE_TURN_LIMITS(CFG)
%
%   返回结构体字段：
%     coilOuterRadius     实际线圈最外圈中心线圆角半径（mm）
%     pitch               实际节距（mm）
%     width               宽度理论上限（匝）
%     length              长度理论上限（匝）
%     cornerRadius        严格同心圆角上限（匝）；legacy_clamped 模式下为理论值
%     innerViaRegion      内圈过孔区域快速预判上限（匝）
%     tabViaRegion        尾板过孔容量预判上限（匝，尾板容量与匝数弱相关时取宽度上限）
%     analyticalMaximum   min(width,length,cornerRadius,innerViaRegion)（匝）
%     limitingFactors     限制因素列表（cellstr，按贡献顺序）
%     tabCapacityPass     尾板能否容纳全部外圈过孔（布尔，与匝数无关的硬约束）

pitch = cfg.traceWidth + cfg.traceSpacing + cfg.pitchMargin;

outerCenterInset = cfg.edgeClearance + cfg.traceWidth/2;
outerLength = cfg.plateLength - 2*outerCenterInset;
outerWidth  = cfg.plateWidth  - 2*outerCenterInset;

coilOuterRadius = resolveCoilOuterRadius(cfg, outerLength, outerWidth);

limits.coilOuterRadius = coilOuterRadius;
limits.pitch = pitch;

% 1) 宽度理论上限（不再减去任何与层数相关的相位项）
limits.width = floor((outerWidth - cfg.minInnerWidth) / (2*pitch));
limits.width = max(limits.width, 0);

% 2) 长度理论上限
limits.length = floor((outerLength - cfg.minInnerLength) / (2*pitch));
limits.length = max(limits.length, 0);

% 3) 圆角上限（严格同心：最内圈半径不得小于 minSpiralCornerRadius）
limits.cornerRadius = floor((coilOuterRadius - cfg.minSpiralCornerRadius) / pitch);
limits.cornerRadius = max(limits.cornerRadius, 0);

% 4) 内圈过孔区域快速预判
innerViaIndices = 1:2:(cfg.layerCount - 1);      % 奇数编号层间过孔（V12、V34、V56、V78）
innerViaCount = numel(innerViaIndices);
minimumViaPitch = cfg.viaPadDiameter + cfg.viaToViaClearance;
actualViaPitch = max(cfg.innerViaPitch, minimumViaPitch);
innerViaRowSpan = max(0, innerViaCount - 1) * actualViaPitch;
requiredViaToCopperCenter = ...
    cfg.viaPadDiameter/2 + cfg.traceWidth/2 + cfg.viaToCopperClearance + cfg.viaKeepoutMargin;
requiredInnerWidthForVias = 2*requiredViaToCopperCenter;
requiredInnerLengthForVias = innerViaRowSpan + 2*requiredViaToCopperCenter;
innerViaWidthMaxTurns = floor((outerWidth  - requiredInnerWidthForVias) / (2*pitch));
innerViaLengthMaxTurns = floor((outerLength - requiredInnerLengthForVias) / (2*pitch));
limits.innerViaRegion = max(0, min(innerViaWidthMaxTurns, innerViaLengthMaxTurns));

% 5) 尾板过孔容量预判（与匝数无关的硬约束）
outerViaIndices = 2:2:(cfg.layerCount - 1);      % 偶数编号层间过孔（V23、V45、V67）
outerViaCount = numel(outerViaIndices);
tabAvailableLength = cfg.tabLength - 2*cfg.viaToBoardClearance;
tabRequiredLength = max(0, outerViaCount - 1) * max(cfg.outerViaPitch, minimumViaPitch) ...
    + cfg.viaPadDiameter + 2*cfg.viaToBoardClearance;
limits.tabCapacityPass = tabRequiredLength <= tabAvailableLength + cfg.geometryTolerance;
% 尾板容量不直接随匝数变化，匝数上限沿用宽度上限，容量失败由扫描/规划阶段报告
limits.tabViaRegion = limits.width;

% 6) 综合解析上限
candidates = struct('width', limits.width, 'length', limits.length, ...
    'cornerRadius', limits.cornerRadius, 'innerViaRegion', limits.innerViaRegion);
limits.analyticalMaximum = min([limits.width, limits.length, ...
    limits.cornerRadius, limits.innerViaRegion]);

% 7) 限制因素（按最小约束报告）
limits.limitingFactors = {};
mins = min([candidates.width, candidates.length, ...
    candidates.cornerRadius, candidates.innerViaRegion]);
if candidates.width == mins
    limits.limitingFactors{end+1} = 'WIDTH_LIMIT';
end
if candidates.length == mins
    limits.limitingFactors{end+1} = 'LENGTH_LIMIT';
end
if candidates.cornerRadius == mins
    limits.limitingFactors{end+1} = 'CORNER_RADIUS_LIMIT';
end
if candidates.innerViaRegion == mins
    limits.limitingFactors{end+1} = 'INNER_VIA_CAPACITY';
end
if ~limits.tabCapacityPass
    limits.limitingFactors{end+1} = 'TAB_VIA_CAPACITY';
end
if isempty(limits.limitingFactors)
    limits.limitingFactors{1} = 'UNKNOWN';
end

end

function coilOuterRadius = resolveCoilOuterRadius(cfg, outerLength, outerWidth)
% 线圈最外圈中心线圆角半径（与板框圆角 plateCornerRadius 解耦）。
maxRadius = min(outerLength, outerWidth) / 2;
switch cfg.coilOuterCornerRadiusMode
    case 'follow_board'
        coilOuterRadius = cfg.plateCornerRadius - (cfg.edgeClearance + cfg.traceWidth/2);
        coilOuterRadius = max(coilOuterRadius, 0);
        coilOuterRadius = min(coilOuterRadius, maxRadius);
    case 'maximize'
        coilOuterRadius = maxRadius;
    case 'manual'
        coilOuterRadius = cfg.coilOuterCornerRadius;
    otherwise
        error('FPC_Coil:InvalidConfigValue', ...
            'Unknown coilOuterCornerRadiusMode ''%s''.', cfg.coilOuterCornerRadiusMode);
end
end

function [xy, startPt, endPt] = generateSpiral(cfg, limits, direction)
%FPC_COIL_GENERATE_SPIRAL 生成单层圆角矩形螺旋中心线路径。
%   [XY, STARTPT, ENDPT] = FPC_COIL_GENERATE_SPIRAL(CFG, LIMITS, DIRECTION)
%
%   参数：
%     LIMITS     fpc_coil_calculate_turn_limits 的输出（含 pitch、coilOuterRadius）
%     DIRECTION  +1 外圈向内圈绕（奇数层），-1 内圈向外圈绕（偶数层）
%
%   保证：
%     * 每层螺旋完整旋转 cfg.turnsPerLayer 个整数圈；
%     * 起点相位与终点相位相同（= connectionPhase 对应的锚点相位）；
%     * 相邻匝中心线距 = pitch；
%     * strict_concentric 模式下圆角半径严格按 radialInset 逐匝递减，
%       legacy_clamped 模式在低于 minSpiralCornerRadius 时截断（调用方需报告警告）。

pitch = limits.pitch;
coilOuterRadius = limits.coilOuterRadius;
turnCount = cfg.turnsPerLayer;

outerCenterInset = cfg.edgeClearance + cfg.traceWidth/2;
outerHalfL = (cfg.plateLength - 2*outerCenterInset) / 2;
outerHalfW = (cfg.plateWidth  - 2*outerCenterInset) / 2;

startPhase = connectionPhaseFraction(cfg.connectionSide, cfg.connectionPhase);

pointsPerTurn = max(cfg.pointsPerTurn, cfg.minTurnPointCount);
n = turnCount * pointsPerTurn + 1;

t = (0:n-1).' / (n-1);                  % 0..1
if direction > 0
    d = (t * turnCount) * pitch;        % 外圈 → 内圈
else
    d = ((1 - t) * turnCount) * pitch;  % 内圈 → 外圈
end
hx = outerHalfL - d;
hy = outerHalfW - d;
if strcmp(cfg.cornerOffsetMode, 'strict_concentric')
    R = coilOuterRadius - d;            % 严格同心等距：半径差 = pitch
else
    R = max(coilOuterRadius - d, cfg.minSpiralCornerRadius); % 旧版截断
end
R(R < cfg.geometryTolerance) = cfg.geometryTolerance;
frac = mod(startPhase + t * turnCount, 1);
xy = roundedRectPoint(frac, hx, hy, R);

startPt = xy(1, :);
endPt = xy(end, :);

end

function frac = connectionPhaseFraction(connectionSide, connectionPhase)
% 连接锚点方位 → 归一化相位。'right_center' 对应螺旋右侧直边中点，
% 相位 0 定义在右上角圆弧终点（右侧直边起点），顺时针为正。
switch connectionSide
    case 'right_center'
        frac = mod(connectionPhase, 1);
    otherwise
        error('FPC_Coil:InvalidConfigValue', ...
            'Unknown connectionSide ''%s''.', connectionSide);
end
end

function p = roundedRectPoint(frac, hx, hy, R)
% 圆角矩形周长上的点（中心原点，半长 hx，半宽 hy，圆角半径 R）。
% 四边位置由线距/边距确定，四角用 90° 圆弧连接相邻直边（切点连续）。
% 段布局：[2a, q, b, q, 2a, q, b, q]，共 8 段
%   a = hy - R （右侧直边半段）
%   b = 2*(hx - R) （顶/底直边全长）
%   q = pi*R/2 （四分之一圆弧）
% 相位 0 定义在右上角圆弧终点（右侧直边起点），顺时针为正，
% 段 1 覆盖右侧直边全长（y: hy-R → -hy+R），保证 mod 跳变处连续。
frac = frac(:);
hx = hx(:);
hy = hy(:);
R = R(:);
p = zeros(numel(frac), 2);

a = hy - R;
b = 2*(hx - R);
q = pi*R/2;
perimeter = 4*a + 2*b + 4*q;               % = 4*hx + 4*hy + (2*pi-8)*R

s = frac .* perimeter;
seg2 = 2*a;
seg3 = seg2 + q;
seg4 = seg3 + b;
seg5 = seg4 + q;
seg6 = seg5 + 2*a;
seg7 = seg6 + q;
seg8 = seg7 + b;

m1 = s < seg2;                              % 段 1：右侧直边全长（上 → 下）
m2 = s >= seg2 & s < seg3;                  % 段 2：右下角圆弧
m3 = s >= seg3 & s < seg4;                  % 段 3：底边（右 → 左）
m4 = s >= seg4 & s < seg5;                  % 段 4：左下角圆弧
m5 = s >= seg5 & s < seg6;                  % 段 5：左边（下 → 上）
m6 = s >= seg6 & s < seg7;                  % 段 6：左上角圆弧
m7 = s >= seg7 & s < seg8;                  % 段 7：顶边（左 → 右）
m8 = ~(m1 | m2 | m3 | m4 | m5 | m6 | m7);   % 段 8：右上角圆弧（终点 = 段 1 起点）

u1 = s ./ (2*a);
u2 = (s - seg2) ./ q;
u3 = (s - seg3) ./ b;
u4 = (s - seg4) ./ q;
u5 = (s - seg5) ./ (2*a);
u6 = (s - seg6) ./ q;
u7 = (s - seg7) ./ b;
u8 = (s - seg8) ./ q;

p(m1, :) = [hx(m1), hy(m1) - R(m1) - (u1(m1)*2).*a(m1)];
p(m2, :) = [hx(m2) - R(m2) + R(m2).*cos(u2(m2)*pi/2), ...
            -hy(m2) + R(m2) - R(m2).*sin(u2(m2)*pi/2)];
p(m3, :) = [hx(m3) - R(m3) - u3(m3).*b(m3), -hy(m3)];
p(m4, :) = [-hx(m4) + R(m4) + R(m4).*cos(pi/2 + u4(m4)*pi/2), ...
            -hy(m4) + R(m4) - R(m4).*sin(pi/2 + u4(m4)*pi/2)];
p(m5, :) = [-hx(m5), -hy(m5) + R(m5) + (u5(m5)*2).*a(m5)];
p(m6, :) = [-hx(m6) + R(m6) + R(m6).*cos(pi + u6(m6)*pi/2), ...
            hy(m6) - R(m6) - R(m6).*sin(pi + u6(m6)*pi/2)];
p(m7, :) = [-hx(m7) + R(m7) + u7(m7).*b(m7), hy(m7)];
p(m8, :) = [hx(m8) - R(m8) + R(m8).*cos(3*pi/2 + u8(m8)*pi/2), ...
            hy(m8) - R(m8) - R(m8).*sin(3*pi/2 + u8(m8)*pi/2)];
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
outputVia = fpc_coil_geometry('auto_output_via', cfg);
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
        if anchorDistance < bestDistance - tol || ...
                (abs(anchorDistance - bestDistance) <= tol && margin > bestMargin)
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

safeX = cfg.plateLength/2 + cfg.viaPadDiameter/2 + cfg.outputViaToBoardClearance;
maxX = cfg.plateLength/2 + cfg.tabLength - cfg.outputViaTipInset;
insetFloorX = cfg.plateLength/2 + cfg.viaPadDiameter/2 + cfg.viaToBoardClearance;
if insetFloorX > maxX + cfg.geometryTolerance
    error('FPC_Coil:ViaPlanningFailed', ...
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
    xy = userToInternalXY(xyUser(k, :), cfg);
    [ok, reason] = validateManualVia(cfg, k, xy, vias);
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
function [ok, reason] = validateManualVia(cfg, k, xy, vias)

ok = false;
reason = '';
tol = cfg.geometryTolerance;

% 板内（主体 + 尾板区域）
bodyRightX = cfg.plateLength/2;
tabTipX = bodyRightX + cfg.tabLength;
tabHalf = cfg.tabWidth/2;
inBoard = xy(1) >= -cfg.plateLength/2 + cfg.viaToBoardClearance && ...
    xy(1) <= tabTipX - cfg.viaToBoardClearance && ...
    xy(2) >= -tabHalf + cfg.viaToBoardClearance && ...
    xy(2) <= tabHalf + cfg.viaToBoardClearance;
if ~inBoard
    reason = sprintf('过孔不在板框（含尾板）内部，距板边不足 %.3f mm。', cfg.viaToBoardClearance);
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

function [path, ok, failReason] = routeSmoothLead( ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, tol)
%FPC_COIL_ROUTE_SMOOTH_LEAD Deterministic tangent fillet lead (arc + straight).
%   [PATH, OK, FAILREASON] = FPC_COIL_ROUTE_SMOOTH_LEAD(STARTPT, STARTTANGENT, ...
%   ENDPT, BENDRADIUS, ARCPOINTCOUNT, TOL)
%
%   STARTTANGENT is the exact travel direction at STARTPT. The path is a
%   single fillet arc of radius BENDRADIUS tangent to STARTTANGENT followed by
%   the required straight segment to ENDPT. Semicircle/reversal sweeps
%   (|sweep| >= pi) are rejected. Among valid candidates the shortest
%   arc+straight length wins; ties keep the earlier enumeration order
%   (left turn first, then right turn; negative offset first per side).
%   PATH is Nx2 with PATH(1,:) == STARTPT and PATH(end,:) == ENDPT.

path = [];
ok = false;
failReason = '';

t = startTangent(:)';
tnorm = norm(t);
if tnorm < tol
    failReason = 'zero start tangent';
    return;
end
t = t / tnorm;

v = endPt - startPt;
d = norm(v);
if d < tol
    path = startPt;
    ok = true;
    return;
end
dvec = v / d;

% Start direction and target direction almost aligned: plain straight lead.
if dot(t, dvec) > 1 - 1e-9
    path = [startPt; endPt];
    ok = true;
    return;
end

if bendRadius <= tol
    failReason = 'nonpositive bend radius';
    return;
end

R = bendRadius;
nLeft = [-t(2), t(1)];
bestLen = Inf;
bestPath = [];

for signIndex = 1:2
    if signIndex == 1
        sgn = 1;
    else
        sgn = -1;
    end
    center = startPt + sgn*R*nLeft;
    w = endPt - center;
    dist = norm(w);
    if dist < R - tol
        continue;
    end
    beta = atan2(w(2), w(1));
    ratio = R / dist;
    offset = acos(max(-1, min(1, ratio)));
    thetaStart = atan2(startPt(2) - center(2), startPt(1) - center(1));
    thetaEValues = [beta - offset, beta + offset];
    for offsetIndex = 1:2
        thetaE = thetaEValues(offsetIndex);
        if sgn == 1
            sweep = mod(thetaE - thetaStart, 2*pi);
        else
            sweep = -mod(thetaStart - thetaE, 2*pi);
        end
        if abs(sweep) >= pi - 1e-9 || abs(sweep) <= tol
            continue;
        end
        E = center + R*[cos(thetaE), sin(thetaE)];
        dirToEnd = endPt - E;
        straightLen = norm(dirToEnd);
        pureArc = straightLen <= tol;
        if ~pureArc
            tanEnd = sgn*[-sin(thetaE), cos(thetaE)];
            cosDir = dot(tanEnd, dirToEnd) / straightLen;
            if cosDir <= 1 - 1e-9
                continue;
            end
        end
        nArc = max(2, ceil(arcPointCount*abs(sweep)/(pi/2)) + 1);
        thetaArc = linspace(thetaStart, thetaStart + sweep, nArc)';
        arcXY = center + R*[cos(thetaArc), sin(thetaArc)];
        arcXY(1,:) = startPt;
        if pureArc
            arcXY(end,:) = endPt;
            path = arcXY;
        else
            path = [arcXY; endPt];
        end
        candidateLen = abs(sweep)*R + straightLen;
        if candidateLen < bestLen - tol
            bestLen = candidateLen;
            bestPath = path;
        end
    end
end

if ~isempty(bestPath)
    path = bestPath;
    ok = true;
else
    failReason = 'no under-180-degree tangent candidate';
end

end

function xyInternal = userToInternalXY(xyUser, cfg)
%USERTOINTERNALXY 将用户坐标（主体左下角原点）转换为内部坐标（主体中心原点）。
%   XYINTERNAL = USERTOINTERNALXY(XYUSER, CFG)
%   用户坐标系：主体接骨板左下角为 (0,0)，+X 朝右（右侧尾板），+Y 朝上。
%   内部坐标系：主体几何中心为原点，+X 朝右，+Y 朝上。
xyInternal = xyUser - [cfg.plateLength/2, cfg.plateWidth/2];
end

function xyUser = internalToUserXY(xyInternal, cfg)
%INTERNALTOUSERXY 将内部坐标（主体中心原点）转换为用户坐标（主体左下角原点）。
%   XYUSER = INTERNALTOUSERXY(XYINTERNAL, CFG)
xyUser = xyInternal + [cfg.plateLength/2, cfg.plateWidth/2];
end
