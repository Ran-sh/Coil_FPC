function result = Generate(cfg)
% 组装完整生成结果（R2-R4），只计算、不写任何输出文件。
% 流程：有效尺寸 → 可行性校验 → 板框/桥 → 线圈与端子网络 → 结果验证 → 汇总。
eff = CircularFpc.Geometry.Board_And_Coil('effective', cfg);
% 外端过孔延伸区：导线从线圈最外圈沿径向向外延伸 E，过孔落在延伸端，
% 焊环与相邻匝净距 = E + 节距 - 焊环半径 - 半线宽，须 >= viaCoilSpacing。
% 由此过孔不影响线距/匝数，代价是板框相应变大（auto 模式自动计入）。
eff.viaEndExtension = max(0, cfg.viaCoilSpacing + cfg.viaPadDiameter / 2 + cfg.traceWidth / 2 - eff.coilPitch);
if strcmp(cfg.boardSizingMode, 'auto')
    % 板框自动定尺寸：线圈最外圈中心线 + 延伸区 + 端点过孔焊环 + 板边净距。
    eff.boardOuterDiameter = requiredBoardDiameter(cfg, eff);
end
activeLayers = activeLayerMap(cfg);         % 层叠组合 → 活动线圈层
directions = ones(1, numel(activeLayers));  % 绕向：+1 = CCW 由内向外，-1 = CW 由外向内
directions(2:2:end) = -1;                   % 奇数序号层 CCW、偶数层 CW（层间交替反向）
% 全活动多层通孔会穿过另外的非连接层：若非连接层的线进入真实钻孔区域，
% 自动增加所有外端过孔的径向引出长度。2 层线圈、4 层板但只有 1/2 层
% 活动线圈没有这条跨活动层的约束。
crossLayerSizing = cfg.boardLayerCount >= 4 && cfg.coilLayerCount == cfg.boardLayerCount;
contactArcSizing = cfg.coilLayerCount > 1;
autoOuterSizing = crossLayerSizing || contactArcSizing;
maxOuterSizingPasses = 20;
for sizingPass = 1:maxOuterSizingPasses
    if sizingPass > 1 && strcmp(cfg.boardSizingMode, 'auto')
        eff.boardOuterDiameter = requiredBoardDiameter(cfg, eff);
    end
    CircularFpc.Quality.Result_Validation('validate_feasibility', cfg, eff);
    [boardLoops, actualBridgeWidth, layoutRegions] = ...
        CircularFpc.Geometry.Board_And_Coil('board', cfg, eff, activeLayers);
    eff.actualBridgeWidth = actualBridgeWidth;
    [coils, connectionPaths, pads, vias, seriesRoute, returnLayer, electrodePads] = ...
        CircularFpc.Geometry.Board_And_Coil('network', cfg, eff, activeLayers, directions, layoutRegions);
    seriesSequence = buildSeriesSequence(seriesRoute); % 只保留关键节点的串联序列（用于报告）
    geom = struct();
    geom.boardLoops = boardLoops;
    geom.actualBridgeWidth = actualBridgeWidth;
    geom.layoutRegions = layoutRegions;
    geom.coils = coils;
    geom.connectionPaths = connectionPaths;
    geom.pads = pads;
    geom.vias = vias;
    geom.electrodePads = electrodePads;
    geom.seriesRoute = seriesRoute;
    geom.seriesSequence = seriesSequence;
    geom.activeLayers = activeLayers;
    validation = CircularFpc.Quality.Result_Validation('validate_result', cfg, eff, geom);
    if ~autoOuterSizing || sizingPass == maxOuterSizingPasses
        break;
    end
    mfRules = CircularFpc.Quality.Jlc_Rules('resolve', cfg).rules;
    deltaDrill = 0;
    if crossLayerSizing
        deltaDrill = mfRules.minDrillToCopperMm - validation.minViaToNonConnectedCopperMm;
    end
    angleFloor = cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg;
    contactArcInvalid = contactArcSizing && ...
        (validation.minOuterViaContactSweepDeg <= angleFloor || ...
        validation.maxOuterViaContactSweepDeg > 150);
    % 两阶段步长：前 8 轮保持历史 0.05 mm 平步长（默认配置的收敛轨迹与
    % 锁定净距哨兵完全不变）；若 8 轮后接触角仍不可行，说明平步长预算
    % 不足以跨过亏欠（典型是粗采样下候选扫角随 E 变化缓慢），改为按亏欠
    % 比例升级（上限 0.5 mm/轮），避免把可收敛配置误报成不可行。
    deltaContact = 0.05 * contactArcInvalid;
    if contactArcInvalid && sizingPass > 8
        contactDeficitDeg = max(angleFloor - validation.minOuterViaContactSweepDeg, 0) + ...
            max(validation.maxOuterViaContactSweepDeg - 150, 0);
        deltaContact = min(0.5, 0.05 + 0.02 * contactDeficitDeg);
    end
    radiusInfeasible = contactArcSizing && ...
        validation.minOuterViaContactRadiusMm < cfg.traceWidth - 1e-9;
    deltaRadius = 0.05 * radiusInfeasible;
    if radiusInfeasible && sizingPass > 8
        deltaRadius = min(0.5, 0.05 + ...
            0.5 * (cfg.traceWidth - validation.minOuterViaContactRadiusMm));
    end
    requiredExtension = max([0, deltaDrill, deltaContact, deltaRadius]);
    if requiredExtension <= 1e-9
        break;
    end
    % 加 1e-6 mm（1 nm）作为浮点收敛余量，让下一轮不再因浮点误差停在边界上。
    % 注意这只是收敛 epsilon，远小于任何制造公差：净距因此收敛到"刚好达标"
    % （4/4 实测 DRILL_TO_COPPER = 0.176001 mm，余量 1 nm）。若要真实工艺余量，
    % 应提高 minDrillToCopper/viaCoilSpacing 规则值，而不是依赖这里。
    eff.viaEndExtension = eff.viaEndExtension + requiredExtension + 1e-6;
end
mfRules = CircularFpc.Quality.Jlc_Rules('resolve', cfg).rules;
if crossLayerSizing && validation.minViaToNonConnectedCopperMm < ...
    mfRules.minDrillToCopperMm - 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        ['Multi-layer through-via drill cannot clear non-connected-layer copper ', ...
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
if contactArcSizing && validation.minOuterViaContactRadiusMm < cfg.traceWidth - 1e-9
    error('CircularFPC:GeometryInfeasible', ...
        ['Outer-via circular contacts cannot reach a radius of one trace ', ...
        'width (%.4f mm) within %d automatic sizing passes.'], ...
        cfg.traceWidth, maxOuterSizingPasses);
end
% Auto 模式的基础网络只作为 terminal reroute 的输入。它仍然包含旧的
% 端子桥路径，某些合法 d/L 组合（例如较小 d）可能只会让这套即将被
% 替换的旧路径触发角度/净距检查；最终结果会在 CircularFpc.Geometry.Terminal_Routing
% 完成后重新做完整 validation + manufacturing 检查。
manufacturing = CircularFpc.Quality.Jlc_Rules('check_result', cfg, validation);
% 平台水平/垂直边槽余量已预检，四角与内圆自然形成的四个连接区由
% 最终布尔拓扑和铜到槽 DRC 检查；保留空 advisories 字段维持报告结构。
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
result.boardLoops = boardLoops;             % 板框：1 外边界 + 4 平台槽 + 4 耳朵挖槽
result.layoutRegions = layoutRegions;       % 平台矩形、桥宽和局部布局参考系
result.layerPaths = layerPaths;             % 按物理层组织的铜层数据（见 buildLayerPaths）
result.pads = pads;                         % PAD_A / PAD_B（线圈串联端子）
result.electrodePads = electrodePads;       % 独立电极焊盘，不进入线圈串联网络
result.vias = vias;                         % 串联过孔（VRET/V12/V23/V34/VOUT 等）
result.seriesSequence = seriesSequence;     % 串联顺序名列表，如 {PAD_A, COIL_L1, VRET, RETURN_L2, VOUT, PAD_B}
result.seriesRoute = seriesRoute;           % 完整串联路由（含坐标与层转移）
result.returnLayer = returnLayer;           % 单线圈组合的回流层（2/1→2，4/1→4），多线圈为 NaN
result.totalTraceLengthMm = totalLengthMm;  % 铜走线总长（线圈 + 连接路径）
result.estimatedDcResistanceOhm = resOhm;   % 直流电阻几何粗估
result.validation = validation;             % 验证结果（见 CircularFpc.Quality.Result_Validation）
result.manufacturing = manufacturing;       % 制造档案检查报告（见 CircularFpc.Quality.Jlc_Rules）
result.outputPath = fullfile(cfg.outputRoot, cfg.designName);
result.config = cfg;
end

function d = requiredBoardDiameter(cfg, eff)
% 板框自动定尺寸（mm）：boardOuterDiameter 是板框轮廓中心线直径；
% 主体圆外径 = 2 ×（最大主螺旋铜外缘 + 板边净距 + 板框线宽/2）。
% 外侧过孔、安装缺口和独立电极由 buildBoardGeometry 单独生成局部凸耳，
% 不再把这些局部特征的半径传播到整圈主体圆。
baseSpan = cfg.turnsPerCoilLayer; % 物理匝数 = 完整 360° 圈数，与螺旋生成一致
spanMax = baseSpan;
if cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4
    spanMax = baseSpan + 0.25; % 4/4 的 L2 多绕 1/4 圈（L4 少绕，外端不变大）
elseif cfg.boardLayerCount == 6 && cfg.coilLayerCount == 6
    spanMax = baseSpan + 0.50; % 6/6 的 L4 半匝相位跳转给出最大外端跨度
end
rStart = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2;
coilOuterRMax = rStart + eff.coilPitch * spanMax;
maxCopperR = coilOuterRMax + cfg.traceWidth / 2;
d = 2 * (maxCopperR + cfg.edgeClearance + cfg.boardOutlineLineWidth / 2 + ...
    cfg.geometrySafetyMargin);
end

function active = activeLayerMap(cfg)
% 层叠组合 → 活动线圈层映射：
%   2/1 → L1；2/2 → L1,L2；4/1 → L1；4/2 → L1,L4；4/4 → L1..L4；6/6 → L1..L6
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
    case 66
        active = [1 2 3 4 5 6];
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
