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
% 任一验证指标失败（间距/净距/连续性/角度等）一律拒绝继续，杜绝带病导出。
% 角度类指标特别检出并给出与算法一致的错误文案；其余指标由 manufacturing 复核兜底。
if ~validation.passed
    error('CircularFPC:ValidationFailed', ...
        'Generated geometry failed validation: %s', strjoin(validation.messages, '; '));
end
% 制造结果二次审查（ADR-1/9）：以实际几何结果指标替换配置值重新检查。
manufacturing = circular_fpc_manufacturing('check_result', cfg, validation);
if ~manufacturing.passed
    error('CircularFPC:ValidationFailed', ...
        'Manufacturing result checks failed: %s', strjoin(manufacturing.failures, '; '));
end
% 建议性提示（非错误）：平台角部超出内接圆进入桥区走廊时给出量化建议，
% 最终可行性由上面的实测验证判定。advisories 随 result.validation 输出，
% main 入口打印到命令行，analyze 只读入口仅携带不打印。
validation.advisories = platformFitAdvisories(cfg, eff);
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
% 板框自动定尺寸（mm）：外径 = 2 × (最大铜外缘半径 + 板边净距)。
% 最大铜外缘取两项之大：
%   ① 基准匝数层（L1/L3）外端 + 过孔延伸区 + 端点过孔焊环半径；
%   ② 分数匝层（4/4 的 L2 多绕 1/4 圈）外端 + 延伸区 + 半线宽。
% 若不取 ②，极限档小焊环下 L2 外端会越过板边净距（实测 0.286 < 0.3）。
baseSpan = cfg.turnsPerCoilLayer - 1;
spanMax = baseSpan;
if cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4
    spanMax = baseSpan + 0.25; % 4/4 的 L2 多绕 1/4 圈（L4 少绕，外端不变大）
end
rStart = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2;
coilOuterR = rStart + eff.coilPitch * baseSpan;
coilOuterRMax = rStart + eff.coilPitch * spanMax;
maxCopperR = max(coilOuterR + eff.viaEndExtension + max(cfg.traceWidth, cfg.viaPadDiameter) / 2, ...
    coilOuterRMax + eff.viaEndExtension + cfg.traceWidth / 2);
d = 2 * (maxCopperR + cfg.edgeClearance);
end

function msgs = platformFitAdvisories(cfg, eff)
% 中央平台与线圈内径的内接关系检查（建议性，不报错）：
% 平台圆角化后实际最大半径（roundedRectMaxRadius，与 validation 同式）
% + platformSlotMargin 超出 可用半径(ID/2 - edgeClearance) 时，
% 矩形平台四角进入四条连接桥的走廊——该处铜线本就跨越桥体，最终可行性
% 由 validate_result 实测铜-槽净距判定；此处仅输出量化提示与两个修正建议：
%   ① 当前内径下等比缩放平台的最大可行尺寸（二分法：缩放同步改变平台尺寸与圆角半径）；
%   ② 容纳当前平台所需的最小线圈内径。
msgs = {};
usableR = eff.coilInnerDiameter / 2 - cfg.edgeClearance;
reach = roundedRectMaxRadius(eff.centerPlatformWidth, eff.centerPlatformHeight, eff.platformCornerR);
if reach + cfg.platformSlotMargin < usableR - 1e-9
    return;
end
lo = 0.0;
hi = 1.0;
for iter = 1:40
    mid = (lo + hi) / 2;
    rMid = roundedRectMaxRadius(mid * eff.centerPlatformWidth, ...
        mid * eff.centerPlatformHeight, mid * eff.platformCornerR);
    if rMid + cfg.platformSlotMargin < usableR
        lo = mid;
    else
        hi = mid;
    end
end
over = reach + cfg.platformSlotMargin - usableR;
minID = 2 * (reach + cfg.platformSlotMargin + cfg.edgeClearance);
msgs{end + 1} = sprintf(['Central platform %.2f x %.2f mm exceeds the inscribed circle by ', ...
    '%.3f mm (reach %.3f + slot margin %.3f > usable radius %.3f); its corners enter the ', ...
    'bridge corridors, where copper already crosses the bridges - final acceptance ', ...
    'relies on measured copper-to-slot clearance. Fix options: shrink platform to at most ', ...
    '%.2f x %.2f mm (same aspect ratio), or increase coilInnerDiameter to at least %.2f mm.'], ...
    eff.centerPlatformWidth, eff.centerPlatformHeight, over, reach, cfg.platformSlotMargin, ...
    usableR, lo * eff.centerPlatformWidth, lo * eff.centerPlatformHeight, minID);
end

function rMax = roundedRectMaxRadius(w, h, cornerR)
% 圆角矩形平台边界到中心的最大半径（与 validation>assertFeasible 使用同一公式：
% 最远点位于圆角弧上 = 弧心距离 + 半径；cornerR=0 时为尖角半对角线）。
halfW = w / 2;
halfH = h / 2;
r = min(cornerR, min(halfW, halfH));
rMax = sqrt((halfW - r)^2 + (halfH - r)^2) + r;
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
