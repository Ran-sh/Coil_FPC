function varargout = rectangular_fpc_geometry(operation, varargin)
%FPC_COIL_GEOMETRY Private geometry dispatcher for the FPC runtime.
%   Supported operations:
%     'turn_limits'      -> calculateTurnLimits(cfg)
%     'spiral'           -> generateSpiral(cfg, limits, direction)
%     'plan_vias'        -> planVias(cfg, spiralInfo)
%     'smooth_lead'      -> routeSmoothLead(startPt, startTangent, endPt, bendRadius, arcPointCount, tol)
%     'user_to_internal' -> userToInternalXY(xyUser, cfg)
%     'internal_to_user' -> internalToUserXY(xyInternal, cfg)
%     'auto_output_via'  -> calculateAutoOutputVia(cfg)
%     'derived_parameters' -> calculateDerivedParameters(cfg)
%     'board_outline'      -> generateSmoothBoardOutline(cfg)
%     'build_layers'       -> buildLayerGeometry(cfg, d, limits, boardXY)
%     'normalize_layers'   -> normalizeLayerPaths(layerXY, layerPaths, tol)

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
    case 'derived_parameters'
        [varargout{1:nargout}] = calculateDerivedParameters(varargin{:});
    case 'board_outline'
        [varargout{1:nargout}] = generateSmoothBoardOutline(varargin{:});
    case 'build_layers'
        [varargout{1:nargout}] = buildLayerGeometry(varargin{:});
    case 'normalize_layers'
        [varargout{1:nargout}] = normalizeLayerPaths(varargin{:});
    case 'remove_duplicates'
        [varargout{1:nargout}] = removeDuplicatePoints(varargin{:});
    case 'remove_zero_length'
        [varargout{1:nargout}] = removeZeroLengthSegments(varargin{:});
    case 'has_zero_length'
        [varargout{1:nargout}] = anyZeroLengthSegments(varargin{:});
    case 'path_length'
        [varargout{1:nargout}] = calculatePathLength(varargin{:});
    otherwise
        error('RectangularFPC:UnknownGeometryOperation', ...
            'Unknown geometry operation: %s', operation);
end

end
function [layerXY, layerPaths] = normalizeLayerPaths( ...
    layerXY, layerPaths, tol)

for layerIndex = 1:numel(layerPaths)
    for pathIndex = 1:numel(layerPaths{layerIndex})
        layerPaths{layerIndex}{pathIndex} = removeDuplicatePoints( ...
            layerPaths{layerIndex}{pathIndex}, tol);
        layerPaths{layerIndex}{pathIndex} = removeZeroLengthSegments( ...
            layerPaths{layerIndex}{pathIndex}, tol);
    end
    layerXY{layerIndex} = layerPaths{layerIndex}{1};
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
        error('RectangularFPC:InvalidConfigValue', ...
            'Unknown coilOuterCornerRadiusMode ''%s''.', cfg.coilOuterCornerRadiusMode);
end
end

function [xy, startPt, endPt] = generateSpiral(cfg, limits, direction)
%FPC_COIL_GENERATE_SPIRAL 生成单层圆角矩形螺旋中心线路径。
%   [XY, STARTPT, ENDPT] = FPC_COIL_GENERATE_SPIRAL(CFG, LIMITS, DIRECTION)
%
%   参数：
%     LIMITS     rectangular_fpc_calculate_turn_limits 的输出（含 pitch、coilOuterRadius）
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
        error('RectangularFPC:InvalidConfigValue', ...
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
outputVia = rectangular_fpc_geometry('auto_output_via', cfg);
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

function d = calculateDerivedParameters(cfg)

d.pitch = cfg.traceWidth + cfg.traceSpacing + cfg.pitchMargin;
d.outerCenterInset = cfg.edgeClearance + cfg.traceWidth/2;

d.outerLength = cfg.plateLength - 2*d.outerCenterInset;
d.outerWidth  = cfg.plateWidth  - 2*d.outerCenterInset;
d.outerRadius = min( ...
    max(cfg.plateCornerRadius - d.outerCenterInset, cfg.minSpiralCornerRadius), ...
    min(d.outerLength, d.outerWidth)/2);

d.rightStraightHalf = d.outerWidth/2 - d.outerRadius;
d.outerPerimeter = roundedRectPerimeter( ...
    d.outerLength, d.outerWidth, d.outerRadius);

d.leadJoinAbsY = abs(cfg.leadYOffset) + cfg.leadBendRadius;
% 连接相位已统一由 cfg.connectionPhase/connectionSide 控制，
% 不再通过随层数变化的 phaseStep 补偿；每层螺旋均为整数圈。

d.bodyRightX = cfg.plateLength/2;
d.tabTipX = d.bodyRightX + cfg.tabLength;
d.outerRightCenterX = d.bodyRightX - d.outerCenterInset;
d.requiredHalfWidth = abs(cfg.leadYOffset) + ...
    max(cfg.traceWidth/2, cfg.padDiameter/2) + cfg.tabEdgeMargin;

d.padA = [d.tabTipX - cfg.padTipInset, +cfg.leadYOffset];
d.padB = [d.tabTipX - cfg.padTipInset, -cfg.leadYOffset];
if strcmp(cfg.outputViaPlacementMode, 'manual')
    d.outputVia = rectangular_fpc_geometry('user_to_internal', cfg.manualOutputViaXY, cfg);
else
    d.outputVia = rectangular_fpc_geometry('auto_output_via', cfg);
end

end

%% =========================================================
function [layerXY, layerPaths, vias, connectionErrors, escapeArcFallback] = ...
    buildLayerGeometry(cfg, d, limits, boardXY)

tol = cfg.geometryTolerance;
escapeArcFallback = false;

% ---- 1) 每层螺旋：整数圈数 + 统一连接相位；相邻层内外锚点重合 ----
rawLayerXY = cell(cfg.layerCount, 1);
for k = 1:cfg.layerCount
    if mod(k,2) == 1
        direction = +1;      % 奇数层：外圈 → 内圈
    else
        direction = -1;      % 偶数层：内圈 → 外圈
    end
    rawLayerXY{k} = rectangular_fpc_geometry('spiral', cfg, limits, direction);
end

% 内圈锚点（奇层终点 = 偶层起点）与外圈锚点（偶层终点 = 奇层起点）
anchorInner = rawLayerXY{1}(end,:);
anchorOuter = rawLayerXY{1}(1,:);
for k = 2:cfg.layerCount
    if mod(k,2) == 1
        anchorErr = norm(rawLayerXY{k}(1,:) - anchorOuter);
    else
        anchorErr = norm(rawLayerXY{k}(1,:) - anchorInner);
    end
    if anchorErr > cfg.connectionTolerance
        error('RectangularFPC:ConnectionFailed', ...
            'L%d连接锚点误差%.6f mm，超过容差%.6f mm', ...
            k, anchorErr, cfg.connectionTolerance);
    end
end

% ---- 2) 过孔规划 ----
outerCenterInset = d.outerCenterInset;
innerCenterInset = outerCenterInset + cfg.turnsPerLayer*d.pitch;
innerLength = cfg.plateLength - 2*innerCenterInset;
innerWidth  = cfg.plateWidth  - 2*innerCenterInset;

innerRadiusStrict = limits.coilOuterRadius - cfg.turnsPerLayer*d.pitch;
if strcmp(cfg.cornerOffsetMode, 'legacy_clamped')
    innerRadius = max(innerRadiusStrict, cfg.minSpiralCornerRadius);
else
    innerRadius = innerRadiusStrict;
end

spiralInfo.innerHalfL = innerLength/2;
spiralInfo.innerHalfW = innerWidth/2;
spiralInfo.innerRadius = innerRadius;
spiralInfo.endPoints = struct('xy', cell(cfg.layerCount, 1));
for k = 1:cfg.layerCount-1
    if mod(k,2) == 1
        spiralInfo.endPoints(k).xy = anchorInner;
        tangent = rawLayerXY{k}(end,:) - rawLayerXY{k}(end-1,:);
        tnorm = norm(tangent);
        if tnorm < tol
            error('RectangularFPC:RoutingFailed', ...
                'L%d末端切线无效。', k);
        end
        spiralInfo.endPoints(k).tangent = tangent/tnorm;
        inwardA = [-tangent(2), tangent(1)]/tnorm;
        inwardB = -inwardA;
        if dot(inwardA, -anchorInner) >= dot(inwardB, -anchorInner)
            spiralInfo.endPoints(k).inwardNormal = inwardA;
        else
            spiralInfo.endPoints(k).inwardNormal = inwardB;
        end
    else
        spiralInfo.endPoints(k).xy = anchorOuter;
        tangent = rawLayerXY{k}(end,:) - rawLayerXY{k}(end-1,:);
        tnorm = norm(tangent);
        if tnorm < tol
            error('RectangularFPC:RoutingFailed', ...
                'L%d末端切线无效。', k);
        end
        spiralInfo.endPoints(k).tangent = tangent/tnorm;
        spiralInfo.endPoints(k).inwardNormal = [0, 0];
    end
end
[vias, viaFailCode, viaFailReason] = rectangular_fpc_geometry('plan_vias', cfg, spiralInfo);
if ~isempty(viaFailCode)
    error('RectangularFPC:ViaPlanningFailed', viaFailReason);
end

% JLC FPC does not qualify blind/buried vias for the supported 2/4-layer
% profile. Those series interconnects are therefore plated through holes:
% copper pads exist only on their two connected layers and every other
% layer receives an antipad keepout. The unsupported 6/8-layer modes retain
% their adjacent-layer interconnect model and are explicitly unverified.
qualifiedLayerCount = ismember(cfg.layerCount, [2, 4]);
for k = 1:numel(vias)
    vias(k).connectedLayers = [k, k+1];
    vias(k).role = 'series_interconnect';
    if qualifiedLayerCount
        vias(k).type = 'through_via';
        vias(k).antipadDiameter = cfg.viaPadDiameter + ...
            2 * cfg.viaToCopperClearance;
    else
        vias(k).type = 'adjacent_layer_via';
        vias(k).antipadDiameter = 0;
    end
end

% ---- 3) 逃逸引线与焊盘引线（通用平滑布线）----
layerXY = rawLayerXY;

% L1 起点（外圈锚点）→ PAD_A
% 引线以 flipud 前置到 L1 起点：90° 型候选首段 = -t，flipud 后
% 到达 L1 起点方向 = +t，须 = spiralTangentStart，故布线沿 +spiralTangentStart。
[keepoutXY, keepoutRadii] = throughViaKeepoutsForLayer(vias, 1, cfg);
[lead, okLead] = routeOrthogonalLeadByPriority( ...
    rawLayerXY{1}, d.padA, 'prepend', ...
    cfg.leadBendRadius, cfg.leadArcPointCount, boardXY, cfg, ...
    keepoutXY, keepoutRadii);
escapeArcFallback = escapeArcFallback || ~okLead;
layerXY{1} = [flipud(lead(2:end,:)); layerXY{1}];

% 各层间过孔引线：内圈过孔（奇数编号）走中心空白，尾板过孔（偶数编号）走尾板
% 过孔两侧独立布线（alpha 恒负时圆弧实际首段 = -t）：
%   lead1（append 到 Lk 末端）沿 +tangentEnd 布线，首段实际 = -tangentEnd，
%   与 Lk 末端方向（tangentEnd）形成折角 —— 由 cosDir 候选选择最优近似；
%   lead2（prepend 到 L(k+1) 起点）沿 -tangentEnd 布线再 flipud，
%   flipud 后到达 L(k+1) 起点方向 = +tangentEnd，与螺旋平滑衔接。
for k = 1:cfg.layerCount-1
    if mod(k,2) == 1
        % Inner via (odd k): center region, bend radius viaInnerBendRadius
        bendRadius = cfg.viaInnerBendRadius;
    else
        % Tab via (even k): tab region, bend radius viaOuterBendRadius
        bendRadius = cfg.viaOuterBendRadius;
    end
    [fromKeepoutXY, fromKeepoutRadii] = ...
        throughViaKeepoutsForLayer(vias, k, cfg);
    [toKeepoutXY, toKeepoutRadii] = ...
        throughViaKeepoutsForLayer(vias, k + 1, cfg);
    [lead1, ok1] = routeOrthogonalLeadByPriority( ...
        rawLayerXY{k}, vias(k).xy, 'append', ...
        bendRadius, cfg.leadArcPointCount, boardXY, cfg, ...
        fromKeepoutXY, fromKeepoutRadii);
    [lead2raw, ok2] = routeOrthogonalLeadByPriority( ...
        rawLayerXY{k+1}, vias(k).xy, 'prepend', ...
        bendRadius, cfg.leadArcPointCount, boardXY, cfg, ...
        toKeepoutXY, toKeepoutRadii);
    okLead = ok1 && ok2;
    escapeArcFallback = escapeArcFallback || ~okLead;
    lead = lead1;
    vias(k).fromLeadPath = lead;
    vias(k).fromLeadLength = calculatePathLength(lead);
    if ~isempty(lead) && size(lead, 2) == 2
        layerXY{k} = [layerXY{k}; lead(2:end,:)];
    end
    leadRev = flipud(lead2raw);
    vias(k).toLeadPath = leadRev;
    vias(k).toLeadLength = calculatePathLength(leadRev);
    % 布线失败（lead 为空）时跳过 prepend：两端停在共享锚点，
    % 连接误差仍为 0，由 escapeArcFallback 标志交给验证阶段裁决。
    if ~isempty(leadRev) && size(leadRev, 2) == 2
        layerXY{k+1} = [leadRev(1:end-1,:); layerXY{k+1}];
    end
end

% 最后一层（偶数层，终点为外圈锚点）→ VOUT
vout = struct( ...
    'name', 'VOUT', 'xy', d.outputVia, ...
    'fromLayer', cfg.layerCount, 'toLayer', 1, ...
    'connectedLayers', [cfg.layerCount, 1], ...
    'type', cfg.outputViaType, 'role', 'output_return', ...
    'drillDiameter', cfg.viaDrillDiameter, ...
    'padDiameter', cfg.viaPadDiameter, ...
    'antipadDiameter', cfg.outputViaAntiPadDiameter, ...
    'placementRegion', 'OUTPUT_TAB', 'placementMode', 'auto', ...
    'fromLeadLength', NaN, 'toLeadLength', NaN, ...
    'fromLeadPath', [], 'toLeadPath', []);
% VOUT lead is append (continues L_last end direction) via the orthogonal router.
[keepoutXY, keepoutRadii] = ...
    throughViaKeepoutsForLayer(vias, cfg.layerCount, cfg);
[lead, okLead] = routeOrthogonalLeadByPriority( ...
    rawLayerXY{cfg.layerCount}, d.outputVia, 'append', ...
    cfg.leadBendRadius, cfg.leadArcPointCount, boardXY, cfg, ...
    keepoutXY, keepoutRadii);
escapeArcFallback = escapeArcFallback || ~okLead;
vout.fromLeadPath = lead;
vout.fromLeadLength = calculatePathLength(lead);
if ~isempty(lead)
    layerXY{cfg.layerCount} = [layerXY{cfg.layerCount}; lead(2:end,:)];
end
vias(end+1) = vout;

% VOUT 将最后一层送回顶层：L1 第二条独立 polyline（VOUT → PAD_B）
topOutputLeadXY = [d.outputVia; d.padB];

% ---- 4) 整理与连接误差 ----
for k = 1:cfg.layerCount
    layerXY{k} = removeDuplicatePoints(layerXY{k}, tol);
    layerXY{k} = removeZeroLengthSegments(layerXY{k}, tol);
end

layerPaths = cell(cfg.layerCount, 1);
for k = 1:cfg.layerCount
    layerPaths{k} = layerXY(k);
end
layerPaths{1}{end+1} = topOutputLeadXY;

connectionErrors = zeros(cfg.layerCount+1, 1);
for k = 1:cfg.layerCount-1
    connectionErrors(k) = norm(layerXY{k}(end,:) - layerXY{k+1}(1,:));
end
connectionErrors(cfg.layerCount) = ...
    norm(layerXY{cfg.layerCount}(end,:) - d.outputVia);
connectionErrors(cfg.layerCount+1) = norm(topOutputLeadXY(1,:) - d.outputVia);

end

%% =========================================================

function outlineXY = generateSmoothBoardOutline(cfg)

L = cfg.plateLength;
W = cfg.plateWidth;
R = cfg.plateCornerRadius;
tabLength = cfg.tabLength;
tabHalfWidth = cfg.tabWidth/2;
tabRadius = cfg.tabOuterCornerRadius;
transitionRadius = cfg.tabTransitionRadius;
arcPointCount = cfg.boardArcPointCount;
tol = cfg.geometryTolerance;

hx = L/2;
hy = W/2;

R = max(0, min(R, min(hx, hy)));
tabRadius = max(0, min(tabRadius, min(tabLength, cfg.tabWidth)/2));

if transitionRadius <= 0
    error('RectangularFPC:BoardGeometryFailed', ...
        'tabTransitionRadius必须大于0。');
end

if tabHalfWidth + 2*transitionRadius > hy + tol
    error('RectangularFPC:BoardGeometryFailed', ...
        'tabTransitionRadius过大，无法保持在主体上下边界内。');
end

bodyTopRightCenter = [hx-R, hy-R];
bodyBottomRightCenter = [hx-R, -hy+R];

dyTop = tabHalfWidth + transitionRadius - (hy-R);
distTransition = R + transitionRadius;

if abs(dyTop) >= distTransition - tol
    error('RectangularFPC:BoardGeometryFailed', ...
        'tabTransitionRadius无法与主体右上圆角形成相切过渡。');
end

dxTop = sqrt(distTransition^2 - dyTop^2);
ctTop = [bodyTopRightCenter(1) + dxTop, tabHalfWidth + transitionRadius];
unitTop = [dxTop, dyTop]/distTransition;
pTop = bodyTopRightCenter + R*unitTop;
qTop = [ctTop(1), tabHalfWidth];

bodyThetaTopEnd = atan2(pTop(2) - bodyTopRightCenter(2), ...
                        pTop(1) - bodyTopRightCenter(1));
thetaPTop = atan2(pTop(2) - ctTop(2), pTop(1) - ctTop(1));
thetaQTop = -pi/2;
sweepTop = mod(thetaQTop - thetaPTop, 2*pi);
if sweepTop > pi
    sweepTop = sweepTop - 2*pi;
end

thetaTop = thetaPTop + sweepTop*linspace(0,1,arcPointCount).';
arcTop = [ctTop(1) + transitionRadius*cos(thetaTop), ...
          ctTop(2) + transitionRadius*sin(thetaTop)];

dyBottom = (-tabHalfWidth - transitionRadius) - (-hy + R);
dxBottom = sqrt(distTransition^2 - dyBottom^2);
ctBottom = [bodyBottomRightCenter(1) + dxBottom, ...
            -tabHalfWidth - transitionRadius];
unitBottom = [dxBottom, dyBottom]/distTransition;
pBottom = bodyBottomRightCenter + R*unitBottom;
qBottom = [ctBottom(1), -tabHalfWidth];

bodyThetaBottomEnd = atan2(pBottom(2) - bodyBottomRightCenter(2), ...
                           pBottom(1) - bodyBottomRightCenter(1));
thetaPBottom = atan2(pBottom(2) - ctBottom(2), ...
                     pBottom(1) - ctBottom(1));
thetaQBottom = pi/2;
sweepBottom = mod(thetaQBottom - thetaPBottom, 2*pi);
if sweepBottom > pi
    sweepBottom = sweepBottom - 2*pi;
end

thetaBottom = thetaPBottom + sweepBottom*linspace(0,1,arcPointCount).';
arcBottomP2Q = [ctBottom(1) + transitionRadius*cos(thetaBottom), ...
                ctBottom(2) + transitionRadius*sin(thetaBottom)];
arcBottomQ2P = flipud(arcBottomP2Q);

xTabRight = hx + tabLength;
xTabArcCenter = xTabRight - tabRadius;
yTabTop = tabHalfWidth;
yTabBottom = -tabHalfWidth;
yTabUpperArcCenter = yTabTop - tabRadius;
yTabLowerArcCenter = yTabBottom + tabRadius;

if qTop(1) >= xTabArcCenter - tol
    error('RectangularFPC:BoardGeometryFailed', ...
        'tabTransitionRadius过大或tabLength过短，过渡圆弧会越过尾部外圆角。');
end

parts = cell(14,1);

parts{1} = [qTop; xTabArcCenter, yTabTop];
parts{2} = sampleArc(xTabArcCenter, yTabUpperArcCenter, tabRadius, ...
    pi/2, 0, arcPointCount, tol);
parts{3} = [xTabRight, yTabUpperArcCenter; ...
            xTabRight, yTabLowerArcCenter];
parts{4} = sampleArc(xTabArcCenter, yTabLowerArcCenter, tabRadius, ...
    0, -pi/2, arcPointCount, tol);
parts{5} = [xTabArcCenter, yTabBottom; qBottom];
parts{6} = arcBottomQ2P;
parts{7} = sampleArc(bodyBottomRightCenter(1), bodyBottomRightCenter(2), R, ...
    bodyThetaBottomEnd, -pi/2, arcPointCount, tol);
parts{8} = [hx-R, -hy; -hx+R, -hy];
parts{9} = sampleArc(-hx+R, -hy+R, R, -pi/2, -pi, arcPointCount, tol);
parts{10} = [-hx, -hy+R; -hx, hy-R];
parts{11} = sampleArc(-hx+R, hy-R, R, pi, pi/2, arcPointCount, tol);
parts{12} = [-hx+R, hy; hx-R, hy];
parts{13} = sampleArc(bodyTopRightCenter(1), bodyTopRightCenter(2), R, ...
    pi/2, bodyThetaTopEnd, arcPointCount, tol);
parts{14} = arcTop;

outlineXY = vertcat(parts{:});
outlineXY = removeDuplicatePoints(outlineXY, tol);
outlineXY = removeZeroLengthSegments(outlineXY, tol);

if norm(outlineXY(end,:) - outlineXY(1,:)) < tol
    outlineXY(end,:) = [];
end

if size(outlineXY,1) < 12
    error('RectangularFPC:BoardGeometryFailed', ...
        '生成的板框点数异常。');
end

if any(~isfinite(outlineXY), 'all')
    error('RectangularFPC:BoardGeometryFailed', ...
        '生成的板框包含无效坐标。');
end

end

%% =========================================================
function xy = sampleArc(cx, cy, r, thetaStart, thetaEnd, pointCount, tol)

if r <= tol
    xy = [cx, cy];
    return;
end

theta = linspace(thetaStart, thetaEnd, pointCount).';
xy = [cx + r*cos(theta), cy + r*sin(theta)];

end

%% =========================================================
function perimeter = roundedRectPerimeter(L, W, R)

R = min(max(R,0), min(L,W)/2);
perimeter = 2*(L+W-4*R) + 2*pi*R;

end

%% =========================================================
function [xy, keep] = removeDuplicatePoints(xy, tol)

if size(xy,1) < 2
    keep = true(size(xy,1),1);
    return;
end

distance = hypot(diff(xy(:,1)), diff(xy(:,2)));
keep = [true; distance > tol];
xy = xy(keep,:);

end

%% =========================================================
function [xy, keep] = removeZeroLengthSegments(xy, tol)

if size(xy,1) < 2
    keep = true(size(xy,1),1);
    return;
end

distance = hypot(diff(xy(:,1)), diff(xy(:,2)));
keep = [true; distance > tol];
xy = xy(keep,:);

end

%% =========================================================
function tf = anyZeroLengthSegments(xy, tol)

tf = false;
if size(xy,1) < 2
    return;
end

tf = any(hypot(diff(xy(:,1)), diff(xy(:,2))) <= tol);

end

%% =========================================================

function [path, ok] = routeLeadByPriority( ...
    basePath, endPt, mode, bendRadius, arcPointCount, boardXY, cfg)
% Priority lead routing: straight, then one fillet + straight, then two-leg
% dogleg; ties at the same priority use the shorter total length.
tol = cfg.geometryTolerance;
path = [];
ok = false;

if strcmp(mode, 'append')
    startPt = basePath(end,:);
    startTangent = basePath(end,:) - basePath(end-1,:);
else
    startPt = basePath(1,:);
    startTangent = -(basePath(2,:) - basePath(1,:));
end

direct = [startPt; endPt];
if candidateCompliant(basePath, direct, mode, boardXY, cfg)
    path = direct;
    ok = true;
    return;
end

[filletPath, filletOk] = rectangular_fpc_geometry('smooth_lead',  ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, tol);
if filletOk && candidateCompliant(basePath, filletPath, mode, boardXY, cfg)
    path = filletPath;
    ok = true;
    return;
end

waypoints = {[endPt(1), startPt(2)], [startPt(1), endPt(2)]};
bestLen = Inf;
bestPath = [];
for wpIndex = 1:numel(waypoints)
    wp = waypoints{wpIndex};
    [cand, candOk] = routeViaWaypoint( ...
        startPt, startTangent, wp, endPt, bendRadius, arcPointCount, tol);
    if ~candOk
        continue;
    end
    if ~candidateCompliant(basePath, cand, mode, boardXY, cfg)
        continue;
    end
    candLen = calculatePathLength(cand);
    if candLen < bestLen - tol
        bestLen = candLen;
        bestPath = cand;
    end
end
if ~isempty(bestPath)
    path = bestPath;
    ok = true;
end

end

function [path, ok] = routeOrthogonalLeadByPriority( ...
    basePath, endPt, mode, bendRadius, arcPointCount, boardXY, cfg, ...
    keepoutXY, keepoutRadii)
% Orthogonal lead routing: axial straight, tangent arc plus axial
% straight, and two-arc orthogonal dogleg candidates; every candidate is
% judged by candidateCompliant in priority order.
path = [];
ok = false;
if nargin < 8
    keepoutXY = zeros(0, 2);
    keepoutRadii = zeros(0, 1);
end

if strcmp(mode, 'append')
    startPt = basePath(end,:);
    startTangent = basePath(end,:) - basePath(end-1,:);
else
    startPt = basePath(1,:);
    startTangent = -(basePath(2,:) - basePath(1,:));
end

[candidates, priorities] = buildOrthogonalViaCandidates( ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, cfg.geometryTolerance);

for priority = 1:3
    candidateIndices = find(priorities == priority);
    if isempty(candidateIndices)
        continue;
    end
    lengths = zeros(numel(candidateIndices), 1);
    for k = 1:numel(candidateIndices)
        lengths(k) = calculatePathLength(candidates{candidateIndices(k)});
    end
    order = sortrows([lengths, candidateIndices(:)], [1, 2]);
    for k = 1:size(order, 1)
        cand = candidates{order(k, 2)};
        if candidateCompliant(basePath, cand, mode, boardXY, cfg) && ...
                pathClearsKeepouts(cand, keepoutXY, keepoutRadii, ...
                cfg.geometryTolerance)
            path = cand;
            ok = true;
            return;
        end
    end
end

if ~cfg.requireSmoothLeadTransitions
    [path, ok] = routeLeadByPriority( ...
        basePath, endPt, mode, bendRadius, arcPointCount, boardXY, cfg);
end

end

function [xy, radii] = throughViaKeepoutsForLayer(vias, layerIndex, cfg)
if isempty(vias)
    xy = zeros(0, 2);
    radii = zeros(0, 1);
    return
end
isKeepout = arrayfun(@(via) ...
    strcmp(via.type, 'through_via') && ...
    ~ismember(layerIndex, via.connectedLayers), vias);
selected = vias(isKeepout);
if isempty(selected)
    xy = zeros(0, 2);
    radii = zeros(0, 1);
    return
end
xy = vertcat(selected.xy);
radii = [selected.antipadDiameter].' / 2 + cfg.traceWidth / 2;
end

function clears = pathClearsKeepouts(path, keepoutXY, keepoutRadii, tol)
clears = true;
for keepoutIndex = 1:size(keepoutXY, 1)
    distance = inf;
    for segmentIndex = 1:size(path, 1) - 1
        distance = min(distance, distancePointToSegment( ...
            keepoutXY(keepoutIndex, :), path(segmentIndex, :), ...
            path(segmentIndex + 1, :)));
    end
    if distance < keepoutRadii(keepoutIndex) - tol
        clears = false;
        return
    end
end
end

function [candidates, priorities] = buildOrthogonalViaCandidates( ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, tol)

candidates = {};
tangentNorm = norm(startTangent);
if tangentNorm <= tol
    return;
end
tu = startTangent / tangentNorm;
thetaStart = atan2(tu(2), tu(1));
axes = [1, 0; 0, 1; -1, 0; 0, -1];
candidateBuffer = cell(1, 29);
priorityBuffer = zeros(1, 29);
candidateCount = 0;

% 1) Axial straight line only.
if abs(endPt(1) - startPt(1)) <= tol || abs(endPt(2) - startPt(2)) <= tol
    candidateCount = candidateCount + 1;
    candidateBuffer{candidateCount} = [startPt; endPt];
    priorityBuffer(candidateCount) = 1;
end

% 2) Single tangent arc plus axial straight segment.
for axisIndex = 1:size(axes, 1)
    axis = axes(axisIndex, :);
    thetaAxis = atan2(axis(2), axis(1));
    sweep = atan2(sin(thetaAxis - thetaStart), cos(thetaAxis - thetaStart));
    if abs(sweep) >= pi - 1e-9
        continue;
    end
    if abs(sweep) <= 1e-12
        continue;
    end
    turnSign = sign(sweep);
    leftNormal = [-tu(2); tu(1)];
    radialUnit = -turnSign * leftNormal;
    rot = [cos(sweep), -sin(sweep); sin(sweep), cos(sweep)];
    offset = (rot - eye(2)) * radialUnit;
    if abs(axis(1)) == 1
        if abs(offset(2)) <= tol
            continue;
        end
        radius = (endPt(2) - startPt(2)) / offset(2);
    else
        if abs(offset(1)) <= tol
            continue;
        end
        radius = (endPt(1) - startPt(1)) / offset(1);
    end
    if radius <= tol || radius > bendRadius + tol
        continue;
    end
    arcEnd = startPt + radius * offset.';
    remaining = endPt - arcEnd;
    if abs(axis(1) * remaining(2) - axis(2) * remaining(1)) > tol
        continue;
    end
    if dot(axis, remaining) < -tol
        continue;
    end
    [arc, arcOk] = buildTangentArc( ...
        startPt, startTangent, axis, radius, arcPointCount);
    if ~arcOk
        continue;
    end
    candidateCount = candidateCount + 1;
    candidateBuffer{candidateCount} = appendPathPoints(arc, endPt, tol);
    priorityBuffer(candidateCount) = 2;
end

% 3) Two-arc orthogonal dogleg.
firstRadii = [bendRadius, bendRadius / 2, bendRadius / 4];
for radiusIndex = 1:numel(firstRadii)
    firstRadius = firstRadii(radiusIndex);
    if firstRadius <= tol
        continue;
    end
    for axisIndex = 1:size(axes, 1)
        d1 = axes(axisIndex, :);
        thetaAxis = atan2(d1(2), d1(1));
        sweep = atan2(sin(thetaAxis - thetaStart), cos(thetaAxis - thetaStart));
        if abs(sweep) >= pi - 1e-9
            continue;
        end
        turnSign = sign(sweep);
        leftNormal = [-tu(2); tu(1)];
        radialUnit = -turnSign * leftNormal;
        rot = [cos(sweep), -sin(sweep); sin(sweep), cos(sweep)];
        offset = (rot - eye(2)) * radialUnit;
        firstEnd = startPt + firstRadius * offset.';
        perps = [[-d1(2), d1(1)]; [d1(2), -d1(1)]];
        for perpIndex = 1:size(perps, 1)
            d2 = perps(perpIndex, :);
            s = dot(endPt - firstEnd, d1);
            q = dot(endPt - firstEnd, d2);
            if s < -tol || q < -tol
                continue;
            end
            cornerRadius = min([bendRadius, s, q]);
            if cornerRadius <= tol
                continue;
            end
            t1 = firstEnd + (s - cornerRadius) * d1;
            t2 = endPt - (q - cornerRadius) * d2;
            [arc1, arc1Ok] = buildTangentArc( ...
                startPt, startTangent, d1, firstRadius, arcPointCount);
            if ~arc1Ok
                continue;
            end
            [arc2, arc2Ok] = buildTangentArc( ...
                t1, d1, d2, cornerRadius, arcPointCount);
            if ~arc2Ok
                continue;
            end
            if norm(arc2(end,:) - t2) > 10 * tol
                continue;
            end
            candidateCount = candidateCount + 1;
            candidateBuffer{candidateCount} = appendPathPoints( ...
                appendPathPoints(appendPathPoints(arc1, t1, tol), arc2, tol), ...
                endPt, tol);
            priorityBuffer(candidateCount) = 3;
        end
    end
end

candidates = candidateBuffer(1:candidateCount);
priorities = priorityBuffer(1:candidateCount);

end

function [arc, ok] = buildTangentArc( ...
    startPt, startTangent, endTangent, radius, arcPointCount)

ok = false;
arc = [];
tangentNorm = norm(startTangent);
endNorm = norm(endTangent);
if tangentNorm <= eps || endNorm <= eps || radius <= eps
    return;
end
tu = startTangent / tangentNorm;
eu = endTangent / endNorm;
thetaStart = atan2(tu(2), tu(1));
thetaEnd = atan2(eu(2), eu(1));
sweep = atan2(sin(thetaEnd - thetaStart), cos(thetaEnd - thetaStart));
if abs(sweep) >= pi - 1e-9
    return;
end
if abs(sweep) <= 1e-12
    arc = startPt;
    ok = true;
    return;
end
turnSign = sign(sweep);
leftNormal = [-tu(2); tu(1)];
radialUnit = -turnSign * leftNormal;
phiStart = atan2(radialUnit(2), radialUnit(1));
center = startPt - radius * radialUnit.';
nArc = max(2, ceil(arcPointCount * abs(sweep) / (pi / 2)) + 1);
theta = linspace(phiStart, phiStart + sweep, nArc).';
arc = center + radius * [cos(theta), sin(theta)];
arc(1, :) = startPt;
arc(end, :) = center + radius * [cos(phiStart + sweep), sin(phiStart + sweep)];
ok = true;

end

function pts = appendPathPoints(a, b, tol)

pts = [a; b];
if size(pts, 1) < 2
    return;
end
keep = true(size(pts, 1), 1);
for k = 2:size(pts, 1)
    if norm(pts(k, :) - pts(k - 1, :)) <= tol
        keep(k) = false;
    end
end
pts = pts(keep, :);

end

function pass = candidateCompliant(basePath, candidate, mode, boardXY, cfg)

pass = rectangular_fpc_validation( ...
    'route_candidate', basePath, candidate, mode, boardXY, cfg);

end

function [path, ok] = routeViaWaypoint( ...
    startPt, startTangent, waypoint, endPt, bendRadius, arcPointCount, tol)
% Two-leg route: start -> waypoint along startTangent, then along the actual
% end direction of the first leg to endPt. No early skip between waypoints.
path = [];
ok = false;

[path1, ok1] = rectangular_fpc_geometry('smooth_lead',  ...
    startPt, startTangent, waypoint, bendRadius, arcPointCount, tol);
if ~ok1
    return;
end
if size(path1, 1) < 2
    return;
end
if norm(waypoint - endPt) <= tol
    path = path1;
    ok = true;
    return;
end
lastDir = path1(end,:) - path1(end-1,:);
if norm(lastDir) <= tol
    lastDir = [1, 0];
end
[path2, ok2] = rectangular_fpc_geometry('smooth_lead',  ...
    waypoint, lastDir, endPt, bendRadius, arcPointCount, tol);
if ~ok2
    return;
end
path = [path1; path2(2:end, :)];
ok = true;

end

%% =========================================================
function len = calculatePathLength(xy)

% 防御：空或非 Nx2 输入按 0 处理（正常路径始终为 Nx2）。
if isempty(xy) || size(xy, 2) ~= 2
    len = 0;
    return;
end
len = sum(hypot(diff(xy(:,1)), diff(xy(:,2))));

end
