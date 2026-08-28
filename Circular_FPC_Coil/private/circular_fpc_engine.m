function result = circular_fpc_engine(cfg)
% 组装完整生成结果（R2-R4），只计算、不写任何输出文件。
% 流程：有效尺寸 → 可行性校验 → 板框/桥 → 线圈与端子网络 → 结果验证 → 汇总。
eff = circular_fpc_geometry('effective', cfg);
% 外端过孔延伸区：导线从线圈最外圈沿径向向外延伸 E，过孔落在延伸端，
% 焊环与相邻匝净距 = E + 节距 - 焊环半径 - 半线宽，须 >= viaCoilSpacing。
% 由此过孔不影响线距/匝数，代价是板框相应变大（auto 模式自动计入）。
eff.viaEndExtension = max(0, cfg.viaCoilSpacing + cfg.viaPadDiameter / 2 + cfg.traceWidth / 2 - eff.coilPitch);
if strcmp(cfg.boardSizingMode, 'auto')
    % 板框自动定尺寸：线圈最外圈中心线 + 延伸区 + 端点过孔焊环 + 板边净距。
    eff.boardOuterDiameter = requiredBoardDiameter(cfg, eff);
    if strcmp(cfg.terminalPlacementMode, 'manual')
        % 手动模式仍允许 auto 板径，但必须再包住用户给定的实际端子坐标；
        % 这样 auto → manual 回读不会把已验证的外移过孔截回板边。
        eff.boardOuterDiameter = max(eff.boardOuterDiameter, ...
            requiredManualTerminalBoardDiameter(cfg));
    end
end
activeLayers = activeLayerMap(cfg);         % 层叠组合 → 活动线圈层，如 4/2 → [1 4]
directions = ones(1, numel(activeLayers));  % 绕向：+1 = CCW 由内向外，-1 = CW 由外向内
directions(2:2:end) = -1;                   % 奇数序号层 CCW、偶数层 CW（层间交替反向）
% 4/4 通孔会穿过另外两层：若非连接层的线进入钻孔/反焊盘区域，
% 自动增加所有外端过孔的径向引出长度，并同步扩大板框。2 层线圈、
% 4 层板但只有 1/2 层活动线圈没有这条跨活动层的约束。
crossLayerSizing = cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4;
contactArcSizing = cfg.coilLayerCount > 1;
autoOuterSizing = crossLayerSizing || contactArcSizing;
maxOuterSizingPasses = 12;
for sizingPass = 1:maxOuterSizingPasses
    if sizingPass > 1 && strcmp(cfg.boardSizingMode, 'auto')
        eff.boardOuterDiameter = requiredBoardDiameter(cfg, eff);
    end
    circular_fpc_validation('validate_feasibility', cfg, eff);
    [boardLoops, actualBridgeWidth, layoutRegions] = circular_fpc_geometry('board', cfg, eff);
    eff.actualBridgeWidth = actualBridgeWidth;
    [coils, connectionPaths, pads, vias, seriesRoute, returnLayer] = ...
        circular_fpc_geometry('network', cfg, eff, activeLayers, directions, layoutRegions);
    seriesSequence = buildSeriesSequence(seriesRoute); % 只保留关键节点的串联序列（用于报告）
    geom = struct();
    geom.boardLoops = boardLoops;
    geom.actualBridgeWidth = actualBridgeWidth;
    geom.layoutRegions = layoutRegions;
    geom.coils = coils;
    geom.connectionPaths = connectionPaths;
    geom.pads = pads;
    geom.vias = vias;
    if strcmp(cfg.terminalPlacementMode, 'auto')
        % VOUT is only a provisional search result here and is replaced by
        % circular_fpc_terminal_reroute.  Do not let that throw-away point
        % drive the antipad sizing loop; final validation checks real VOUT.
        geom.antipadValidationVias = vias(~strcmp({vias.name}, 'VOUT'));
    end
    geom.seriesRoute = seriesRoute;
    geom.seriesSequence = seriesSequence;
    geom.activeLayers = activeLayers;
    validation = circular_fpc_validation('validate_result', cfg, eff, geom);
    if ~autoOuterSizing || sizingPass == maxOuterSizingPasses
        break;
    end
    mfRules = circular_fpc_manufacturing('resolve', cfg).rules;
    deltaDrill = 0;
    deltaAntipad = 0;
    if crossLayerSizing
        deltaDrill = mfRules.minDrillToCopperMm - validation.minViaToNonConnectedCopperMm;
        deltaAntipad = -validation.minAntipadToNonConnectedCopperMm;
    end
    angleFloor = cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg;
    contactArcInvalid = contactArcSizing && ...
        (validation.minOuterViaContactSweepDeg <= angleFloor || ...
        validation.maxOuterViaContactSweepDeg > 150);
    deltaContact = 0.05 * contactArcInvalid;
    requiredExtension = max([0, deltaDrill, deltaAntipad, deltaContact]);
    if requiredExtension <= 1e-9
        break;
    end
    % 加 1 um 防止下一轮因浮点误差反复停在边界上。
    eff.viaEndExtension = eff.viaEndExtension + requiredExtension + 1e-6;
end
mfRules = circular_fpc_manufacturing('resolve', cfg).rules;
if crossLayerSizing && (validation.minViaToNonConnectedCopperMm < ...
        mfRules.minDrillToCopperMm - 1e-9 || ...
        validation.minAntipadToNonConnectedCopperMm < -1e-9)
    error('CircularFPC:GeometryInfeasible', ...
        ['4/4 through-via drill/antipad cannot clear non-connected-layer copper ', ...
         'within %d automatic sizing passes.'], maxOuterSizingPasses);
end
if contactArcSizing && (validation.minOuterViaContactSweepDeg <= ...
        cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg || ...
        validation.maxOuterViaContactSweepDeg > 150)
    error('CircularFPC:GeometryInfeasible', ...
        ['Outer-via circular contacts cannot satisfy the strict >90-degree ', ...
        'and <=150-degree sweep rule within %d automatic sizing passes.'], ...
        maxOuterSizingPasses);
end
% Auto 模式的基础网络只作为 terminal reroute 的输入。它仍然包含旧的
% 端子桥路径，某些合法 d/L 组合（例如较小 d）可能只会让这套即将被
% 替换的旧路径触发角度/净距检查；最终结果会在 circular_fpc_terminal_reroute
% 完成后重新做完整 validation + manufacturing 检查。manual 模式没有后置
% 重布线，因此必须在这里严格拒绝基础几何失败。
if strcmp(cfg.terminalPlacementMode, 'manual')
    if ~validation.passed
        error('CircularFPC:ValidationFailed', ...
            'Generated geometry failed validation: %s', strjoin(validation.messages, '; '));
    end
    manufacturing = circular_fpc_manufacturing('check_result', cfg, validation);
    if ~manufacturing.passed
        error('CircularFPC:ValidationFailed', ...
            'Manufacturing result checks failed: %s', strjoin(manufacturing.failures, '; '));
    end
else
    manufacturing = circular_fpc_manufacturing('check_result', cfg, validation);
end
% 平台/内径关系已在生成前作为硬可行性约束检查；保留空 advisories 字段，
% 维持报告结构兼容，不再允许角部伸入环区后依赖事后 DRC 侥幸通过。
validation.advisories = {};
layerPaths = buildLayerPaths(cfg.boardLayerCount, activeLayers, directions, coils, connectionPaths);
totalLengthMm = computeTotalLength(coils, connectionPaths);
% 直流电阻粗估：R = ρ * L / (线宽 * 铜厚)，仅几何长度估算（无电气性能声明）。
resOhm = cfg.copperResistivity * (totalLengthMm / 1000) / ...
    ((cfg.traceWidth / 1000) * (cfg.copperThickness / 1000));
result = struct();
result.boardLayerCount = cfg.boardLayerCount;
result.coilLayerCount = cfg.coilLayerCount;
result.activeCoilLayers = activeLayers;     % 实际承载线圈的活动层号
result.effectiveDimensions = eff;           % 缩放后的有效尺寸 + coilPitch + actualBridgeWidth
result.boardLoops = boardLoops;             % 板框：1 外边界 + 4 孔槽闭环
result.layoutRegions = layoutRegions;       % 平台矩形、桥宽和局部布局参考系
result.layerPaths = layerPaths;             % 按物理层组织的铜层数据（见 buildLayerPaths）
result.pads = pads;                         % PAD_A / PAD_B
result.vias = vias;                         % 串联过孔（VRET/V12/V23/V34/VOUT 等）
result.seriesSequence = seriesSequence;     % 串联顺序名列表，如 {PAD_A, COIL_L1, VRET, RETURN_L2, VOUT, PAD_B}
result.seriesRoute = seriesRoute;           % 完整串联路由（含坐标与层转移）
result.returnLayer = returnLayer;           % 单线圈组合的回流层（2/1→2，4/1→4），多线圈为 NaN
result.totalTraceLengthMm = totalLengthMm;  % 铜走线总长（线圈 + 连接路径）
result.estimatedDcResistanceOhm = resOhm;   % 直流电阻几何粗估
result.validation = validation;             % 验证结果（见 circular_fpc_validation）
result.manufacturing = manufacturing;       % 制造档案检查报告（见 circular_fpc_manufacturing）
result.outputPath = fullfile(cfg.outputRoot, cfg.designName);
result.config = cfg;
end

function d = requiredBoardDiameter(cfg, eff)
% 板框自动定尺寸（mm）：boardOuterDiameter 是板框轮廓中心线直径；
% 外径 = 2 × (最大铜外缘半径 + 板边净距 + 板框线宽/2)。
% 最大铜外缘取两项之大：
%   ① 基准匝数层（L1/L3）外端 + 过孔延伸区 + 端点过孔焊盘切线；
%   ② 分数匝层（4/4 的 L2 多绕 1/4 圈）原始外端 + 半线宽。
% 若不取 ②，极限档小焊环下 L2 外端会越过板边净距（实测 0.286 < 0.3）。
baseSpan = cfg.turnsPerCoilLayer - 1;
spanMax = baseSpan;
if cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4
    spanMax = baseSpan + 0.25; % 4/4 的 L2 多绕 1/4 圈（L4 少绕，外端不变大）
end
rStart = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2;
coilOuterR = rStart + eff.coilPitch * baseSpan;
coilOuterRMax = rStart + eff.coilPitch * spanMax;
% 110° 外端接触弧除径向外移 E 外还会产生切向偏移；以 E 作为切向上界
% 取 hypot，保守包住实际弧端/过孔中心。下游分数匝层不再另加外伸弧。
maxViaTangentR = hypot(coilOuterR + eff.viaEndExtension, eff.viaEndExtension) + ...
    cfg.viaPadDiameter / 2;
maxTraceTangentR = coilOuterRMax + cfg.traceWidth / 2;
maxCopperR = max(maxViaTangentR, maxTraceTangentR);
d = 2 * (maxCopperR + cfg.edgeClearance + cfg.boardOutlineLineWidth / 2);
end

function d = requiredManualTerminalBoardDiameter(cfg)
% 手动端子坐标的最大铜切线 + 板边净距 + 板框线宽半宽。
maxTerminalR = -inf;
if ~isempty(cfg.manualPadAXY)
    maxTerminalR = max(maxTerminalR, max(sqrt(sum(cfg.manualPadAXY.^2, 2))) + cfg.padDiameter / 2);
end
if ~isempty(cfg.manualPadBXY)
    maxTerminalR = max(maxTerminalR, max(sqrt(sum(cfg.manualPadBXY.^2, 2))) + cfg.padDiameter / 2);
end
if ~isempty(cfg.manualSeriesViaXY)
    maxTerminalR = max(maxTerminalR, max(sqrt(sum(cfg.manualSeriesViaXY.^2, 2))) + cfg.viaPadDiameter / 2);
end
if isinf(maxTerminalR)
    d = 0;
else
    d = 2 * (maxTerminalR + cfg.edgeClearance + cfg.boardOutlineLineWidth / 2);
end
end

function active = activeLayerMap(cfg)
% 层叠组合 → 活动线圈层映射：
%   2/1 → L1；2/2 → L1,L2；4/1 → L1；4/2 → L1,L4；4/4 → L1,L2,L3,L4
layerKey = cfg.boardLayerCount * 10 + cfg.coilLayerCount;
switch layerKey
    case 21
        active = [1];
    case 22
        active = [1 2];
    case 41
        active = [1];
    case 42
        active = [1 4];
    case 44
        active = [1 2 3 4];
    otherwise
        error('CircularFPC:UnsupportedLayerCombination', 'Unsupported layer combination.');
end
end

function seq = buildSeriesSequence(seriesRoute)
% 从 seriesRoute 中提取串联序列：去掉普通 TRACE（保留 RETURN_*），
% 只保留 PAD / COIL / VIA / RETURN 关键节点名。
keep = true(1, numel(seriesRoute));
for k = 1:numel(seriesRoute)
    if strcmp(seriesRoute(k).kind, 'TRACE') && ~strncmp(seriesRoute(k).name, 'RETURN_', 7)
        keep(k) = false;
    end
end
seq = {seriesRoute(keep).name};
end

function layerPaths = buildLayerPaths(boardLayerCount, activeLayers, directions, coils, connectionPaths)
% 按物理层组织输出：每层记录是否活动线圈层、绕向、线圈折线与连接路径；
% 非活动层（如 2/1 的 L2 回流层）coilXY 为空，只含连接路径。
layerPaths = struct('layerNumber', {}, 'isActiveCoilLayer', {}, 'windingDirection', {}, ...
    'coilXY', {}, 'connectionPaths', {});
for li = 1:boardLayerCount
    p = find(activeLayers == li, 1);
    layerPaths(li).layerNumber = li;
    layerPaths(li).connectionPaths = connectionPaths{li};
    if isempty(p)
        layerPaths(li).isActiveCoilLayer = false;
        layerPaths(li).windingDirection = 'NONE';
        layerPaths(li).coilXY = [];
    else
        layerPaths(li).isActiveCoilLayer = true;
        if directions(p) > 0
            layerPaths(li).windingDirection = 'CCW';
        else
            layerPaths(li).windingDirection = 'CW';
        end
        layerPaths(li).coilXY = coils{li};
    end
end
end

function L = computeTotalLength(coils, connectionPaths)
% 铜走线总长 = 各活动层线圈折线长度 + 各层连接路径长度（单位 mm）。
L = 0;
for li = 1:numel(coils)
    xy = coils{li};
    if ~isempty(xy)
        L = L + sum(sqrt(sum(diff(xy, 1, 1).^2, 2)));
    end
    paths = connectionPaths{li};
    for k = 1:numel(paths)
        p = paths{k};
        L = L + sum(sqrt(sum(diff(p, 1, 1).^2, 2)));
    end
end
end
