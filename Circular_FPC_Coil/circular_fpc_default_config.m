function cfg = circular_fpc_default_config(overrides)
% CIRCULAR_FPC_DEFAULT_CONFIG 圆环 FPC 线圈生成器默认配置。
if nargin < 1
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('CircularFPC:InvalidConfig', 'overrides must be a scalar struct.');
end

cfg = struct( ...
    'boardLayerCount', 4, ... % 物理板层数：2 或 4
    'coilLayerCount', 4, ... % 活动线圈层数：支持 2/1、2/2、4/1、4/2、4/4
    'boardOuterDiameter', 25.0, ... % 固定板径模式下的圆形板外径 [mm]
    'boardSizingMode', 'auto', ... % 'auto' 匝数决定板径；'fixed' 使用 boardOuterDiameter
    'coilInnerDiameter', 18.63, ... % 螺旋最内圈直径 [mm]
    'centerPlatformWidth', 13.0, ... % 中央平台宽度 [mm]
    'centerPlatformHeight', 14.0, ... % 中央平台高度 [mm]
    'platformCornerRadius', 0.2, ... % 中央平台圆角 [mm]
    'platformSlotMargin', 0.25, ... % 平台/槽建议性余量 [mm]
    'bridgeTargetWidth', 1.5, ... % 连接桥目标宽度 [mm]
    'geometryScale', 1.0, ... % 宏观几何缩放系数
    'turnsPerCoilLayer', 8, ... % 每活动层目标匝数
    'traceWidth', 0.20, ... % 铜线宽度 [mm]
    'traceSpacing', 0.15, ... % 铜线净距 [mm]
    'pitchMargin', 0.005, ... % 节距附加余量 [mm]
    'edgeClearance', 0.30, ... % 铜到板框/槽净距 [mm]
    'samplePointsPerTurn', 360, ... % 每匝采样点数
    'turnScanMax', 16, ... % 匝数扫描上限
    'connectionAngleDeg', 135.0, ... % 连接桥局部 u 轴方位角 [deg]
    'padPairSpacing', 2.0, ... % 兼容旧参数；自动模式下与 terminalLeadSpacing 同步
    'terminalLeadSpacing', 2.0, ... % mm，两条平行端子引出线中心线间距 d
    'terminalLeadLength', 1.5, ... % mm，单次圆弧切点到 PAD 中心的直线长度 L；VOUT 到 PAD_B 同为 L
    'terminalPlacementMode', 'auto', ... % 'auto' 使用 d/L 单弯拓扑；'manual' 使用人工坐标
    'manualPadAXY', zeros(0, 2), ... % manual 模式 PAD_A 坐标
    'manualPadBXY', zeros(0, 2), ... % manual 模式 PAD_B 坐标
    'manualSeriesViaXY', zeros(0, 2), ... % manual 模式串联过孔坐标
    'padDiameter', 0.6096, ... % PAD_A/PAD_B 直径 [mm]
    'viaPadDiameter', 0.55, ... % 过孔焊环外径 [mm]
    'viaDrillDiameter', 0.3, ... % 过孔钻孔内径 [mm]
    'viaCoilSpacing', 0.152, ... % 过孔焊环到线圈铜边净距 [mm]
    'minCopperInteriorAngleDeg', 90.0, ... % 铜走线最小内角 [deg]
    'minBoardInteriorAngleDeg', 90.0, ... % 板框最小内角 [deg]
    'angleToleranceDeg', 0.1, ... % 角度容差 [deg]
    'antipadDiameter', 1.2, ... % 非连接层反焊盘直径 [mm]
    'terminalClearance', 0.25, ... % 焊盘/过孔端子间最小净距 [mm]
    'copperThickness', 0.035, ... % 铜厚 [mm]
    'copperResistivity', 1.724e-8, ... % 铜电阻率 [Ohm*m]
    'manufacturingProfile', 'jlc_fpc_1oz', ...
    'manufacturingTier', 'standard', ...
    'manufacturingRuleOverrides', struct(), ...
    'enablePreview', true, ...
    'enableFigure', true, ...
    'outputRoot', fullfile(pwd, 'circular_fpc_output'), ...
    'designName', 'auto');

for f = fieldnames(overrides).'
    if ~isfield(cfg, f{1})
        error('CircularFPC:UnknownConfigField', 'Unknown config field: %s', f{1});
    end
    cfg.(f{1}) = overrides.(f{1});
end

% 新旧参数兼容：优先采用新参数；只覆盖旧 padPairSpacing 时同步到新参数。
if isfield(overrides, 'terminalLeadSpacing')
    cfg.padPairSpacing = cfg.terminalLeadSpacing;
elseif isfield(overrides, 'padPairSpacing')
    cfg.terminalLeadSpacing = cfg.padPairSpacing;
else
    cfg.padPairSpacing = cfg.terminalLeadSpacing;
end

for name = {'terminalLeadSpacing', 'terminalLeadLength'}
    value = cfg.(name{1});
    if ~isscalar(value) || ~isnumeric(value) || ~isfinite(value) || value <= 0
        error('CircularFPC:InvalidConfig', '%s must be a positive finite scalar.', name{1});
    end
end

if strcmp(cfg.designName, 'auto')
    cfg.designName = sprintf('Circular_FPC_%dL_%dC_%s', cfg.boardLayerCount, cfg.coilLayerCount, ...
        datestr(now, 'yyyymmdd_HHMM'));
end
cfg = circular_fpc_validation('validate_config', cfg);
end
