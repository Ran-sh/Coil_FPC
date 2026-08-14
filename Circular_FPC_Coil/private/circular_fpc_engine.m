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
end
circular_fpc_validation('validate_feasibility', cfg, eff);
[boardLoops, actualBridgeWidth, layoutRegions] = circular_fpc_geometry('board', cfg, eff);
eff.actualBridgeWidth = actualBridgeWidth;
activeLayers = activeLayerMap(cfg);         % 层叠组合 → 活动线圈层，如 4/2 → [1 4]
directions = ones(1, numel(activeLayers));  % 绕向：+1 = CCW 由内向外，-1 = CW 由外向内
directions(2:2:end) = -1;                   % 奇数序号层 CCW、偶数层 CW（层间交替反向）
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
geom.seriesRoute = seriesRoute;
geom.seriesSequence = seriesSequence;
geom.activeLayers = activeLayers;
validation = circular_fpc_validation('validate_result', cfg, eff, geom);
% 铜线或板框出现尖角/尖点时，不得继续构建结果或进入正式导出阶段。
hasSharpAngle = validation.minCopperInteriorAngleDeg <= ...
    cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg || ...
    validation.minBoardInteriorAngleDeg <= ...
    cfg.minBoardInteriorAngleDeg + cfg.angleToleranceDeg;
if hasSharpAngle
    error('CircularFPC:ValidationFailed', ...
        'Generated geometry failed validation: %s', strjoin(validation.messages, '; '));
end
% 制造结果二次审查（ADR-1/9）：以实际几何结果指标替换配置值重新检查。
manufacturing = circular_fpc_manufacturing('check_result', cfg, validation);
if ~manufacturing.passed
    error('CircularFPC:ValidationFailed', ...
        'Manufacturing result checks failed: %s', strjoin(manufacturing.failures, '; '));
end
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
% 板框自动定尺寸（mm）：外径 = 2 × (线圈最外圈中心线半径 + 过孔延伸区 + 过孔焊环半径 + 板边净距)。
% 线圈最外圈中心线半径 = 线圈内径/2 + 线宽/2 + 节距 × (匝数-1)。
coilOuterR = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2 + eff.coilPitch * (cfg.turnsPerCoilLayer - 1);
maxCopperR = coilOuterR + eff.viaEndExtension + max(cfg.traceWidth, cfg.viaPadDiameter) / 2;
d = 2 * (maxCopperR + cfg.edgeClearance);
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
