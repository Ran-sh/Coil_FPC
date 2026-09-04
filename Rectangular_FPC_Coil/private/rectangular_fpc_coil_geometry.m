function varargout = rectangular_fpc_coil_geometry(operation, varargin)
%RECTANGULAR_FPC_COIL_GEOMETRY Spiral construction and layer assembly.

switch operation
    case 'turn_limits'
        [varargout{1:nargout}] = calculateTurnLimits(varargin{:});
    case 'spiral'
        [varargout{1:nargout}] = generateSpiral(varargin{:});
    case 'derived_parameters'
        [varargout{1:nargout}] = calculateDerivedParameters(varargin{:});
    case 'build_layers'
        [varargout{1:nargout}] = buildLayerGeometry(varargin{:});
    otherwise
        error('RectangularFPC:UnknownCoilGeometryOperation', ...
            'Unknown coil geometry operation: %s', operation);
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

function d = calculateDerivedParameters(cfg)

d.pitch = cfg.traceWidth + cfg.traceSpacing + cfg.pitchMargin;
d.outerCenterInset = cfg.edgeClearance + cfg.traceWidth/2;

d.outerLength = cfg.plateLength - 2*d.outerCenterInset;
d.outerWidth  = cfg.plateWidth  - 2*d.outerCenterInset;
d.outerRadius = min( ...
    max(cfg.plateCornerRadius - d.outerCenterInset, cfg.minSpiralCornerRadius), ...
    min(d.outerLength, d.outerWidth)/2);

d.rightStraightHalf = d.outerWidth/2 - d.outerRadius;
d.outerPerimeter = rectangular_fpc_board_geometry('perimeter',  ...
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
    d.outputVia = rectangular_fpc_path_geometry('user_to_internal', cfg.manualOutputViaXY, cfg);
else
    d.outputVia = rectangular_fpc_via_planner('auto_output_via', cfg);
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
    rawLayerXY{k} = rectangular_fpc_coil_geometry('spiral', cfg, limits, direction);
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
[vias, viaFailCode, viaFailReason] = rectangular_fpc_via_planner('plan_vias', cfg, spiralInfo);
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
[keepoutXY, keepoutRadii] = rectangular_fpc_lead_router('through_keepouts', vias, 1, cfg);
[lead, okLead] = rectangular_fpc_lead_router('orthogonal',  ...
    rawLayerXY{1}, d.padA, 'prepend', ...
    cfg.leadBendRadius, cfg.leadArcPointCount, boardXY, cfg, ...
    keepoutXY, keepoutRadii);
requireRoutedLead(lead, d.padA, 'PAD_A', tol);
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
        rectangular_fpc_lead_router('through_keepouts', vias, k, cfg);
    [toKeepoutXY, toKeepoutRadii] = ...
        rectangular_fpc_lead_router('through_keepouts', vias, k + 1, cfg);
    [lead1, ok1] = rectangular_fpc_lead_router('orthogonal',  ...
        rawLayerXY{k}, vias(k).xy, 'append', ...
        bendRadius, cfg.leadArcPointCount, boardXY, cfg, ...
        fromKeepoutXY, fromKeepoutRadii);
    [lead2raw, ok2] = rectangular_fpc_lead_router('orthogonal',  ...
        rawLayerXY{k+1}, vias(k).xy, 'prepend', ...
        bendRadius, cfg.leadArcPointCount, boardXY, cfg, ...
        toKeepoutXY, toKeepoutRadii);
    requireRoutedLead(lead1, vias(k).xy, ...
        sprintf('%s from-layer', vias(k).name), tol);
    requireRoutedLead(lead2raw, vias(k).xy, ...
        sprintf('%s to-layer', vias(k).name), tol);
    okLead = ok1 && ok2;
    escapeArcFallback = escapeArcFallback || ~okLead;
    lead = lead1;
    vias(k).fromLeadPath = lead;
    vias(k).fromLeadLength = rectangular_fpc_path_geometry('path_length', lead);
    if ~isempty(lead) && size(lead, 2) == 2
        layerXY{k} = [layerXY{k}; lead(2:end,:)];
    end
    leadRev = flipud(lead2raw);
    vias(k).toLeadPath = leadRev;
    vias(k).toLeadLength = rectangular_fpc_path_geometry('path_length', leadRev);
    % requireRoutedLead 已保证路径非空且命中过孔；这里只去除与螺旋
    % 起点重复的最后一个点，再把反向引线前置到下一层。
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
    'placementRegion', 'OUTPUT_TAB', ...
    'placementMode', cfg.outputViaPlacementMode, ...
    'fromLeadLength', NaN, 'toLeadLength', NaN, ...
    'fromLeadPath', [], 'toLeadPath', []);
if strcmp(cfg.outputViaPlacementMode, 'manual')
    closedBoardXY = [boardXY; boardXY(1, :)];
    [outputViaInside, centerToBoard, requiredDistance] = ...
        rectangular_fpc_via_planner('validate_board_location', d.outputVia, cfg.viaPadDiameter, ...
        cfg.outputViaToBoardClearance, closedBoardXY, tol);
    if ~outputViaInside
        error('RectangularFPC:ViaPlanningFailed', ...
            ['VOUT 手动坐标未完整位于真实圆角板框内：中心到板框 ', ...
             '%.3f mm，要求至少 %.3f mm。'], ...
            centerToBoard, requiredDistance);
    end
end
% VOUT lead is append (continues L_last end direction) via the orthogonal router.
[keepoutXY, keepoutRadii] = ...
    rectangular_fpc_lead_router('through_keepouts', vias, cfg.layerCount, cfg);
[lead, okLead] = rectangular_fpc_lead_router('orthogonal',  ...
    rawLayerXY{cfg.layerCount}, d.outputVia, 'append', ...
    cfg.leadBendRadius, cfg.leadArcPointCount, boardXY, cfg, ...
    keepoutXY, keepoutRadii);
requireRoutedLead(lead, d.outputVia, 'VOUT', tol);
escapeArcFallback = escapeArcFallback || ~okLead;
vout.fromLeadPath = lead;
vout.fromLeadLength = rectangular_fpc_path_geometry('path_length', lead);
if ~isempty(lead)
    layerXY{cfg.layerCount} = [layerXY{cfg.layerCount}; lead(2:end,:)];
end
vias(end+1) = vout;

% VOUT 将最后一层送回顶层：L1 第二条独立 polyline（VOUT → PAD_B）
topOutputLeadXY = [d.outputVia; d.padB];
requireRoutedLead(topOutputLeadXY, d.padB, 'PAD_B', tol);

% ---- 4) 整理与连接误差 ----
for k = 1:cfg.layerCount
    layerXY{k} = rectangular_fpc_path_geometry('remove_duplicates', layerXY{k}, tol);
    layerXY{k} = rectangular_fpc_path_geometry('remove_zero_length', layerXY{k}, tol);
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

function requireRoutedLead(path, targetXY, label, tol)
if isempty(path) || size(path, 2) ~= 2 || size(path, 1) < 2 || ...
        any(~isfinite(path), 'all') || ...
        norm(path(end, :) - targetXY) > tol
    error('RectangularFPC:RoutingFailed', ...
        '%s 引线为空、坐标无效或未连接到目标端点。', label);
end
end

%% =========================================================
