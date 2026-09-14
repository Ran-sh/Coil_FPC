function cfg = circular_fpc_default_config(overrides)
% CIRCULAR_FPC_DEFAULT_CONFIG 圆环 FPC 线圈生成器默认配置。
if nargin < 1
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('CircularFPC:InvalidConfig', 'overrides must be a scalar struct.');
end

cfg = struct( ...
    'boardLayerCount', 4, ... % 物理板层数：2、4 或 6
    'coilLayerCount', 4, ... % 活动线圈层数：支持 2/1、2/2、4/1、4/2、4/4、6/6
    'boardOuterDiameter', 25.0, ... % 固定板径模式下的圆形板外径 [mm]
    'boardSizingMode', 'auto', ... % 'auto' 匝数决定板径；'fixed' 使用 boardOuterDiameter
    'coilInnerDiameter', 18.63, ... % 螺旋最内圈直径 [mm]；与正向 13x14 平台自然形成四个对角连接区
    'centerPlatformWidth', 13.0, ... % 中央平台宽度 [mm]
    'centerPlatformHeight', 14.0, ... % 中央平台高度 [mm]
    'platformSlotMargin', 0.25, ... % 平台水平/垂直边到内圆的最小槽余量 [mm]
    'mountingSlotSpan', 4.0, ... % 四个正方向挖槽端点弦长（端点位于主体外径圆上，关于耳朵径向轴对称）[mm]
    'mountingSlotRise', 1.0, ... % 挖槽中间弧在耳朵中央径向轴上的外凸高度，基准为主体外径圆中央点 [mm]
    'mountingSlotEdgeClearance', NaN, ... % 中间弧到最外侧板框的板料宽度 [mm]；NaN = 沿用 edgeClearance
    'mountingSlotEndFilletRadius', 0.3, ... % 挖槽两端圆弧过渡半径（消除尖锐槽口）[mm]
    'viaLugRootOverlap', 0.4, ... % 外侧过孔凸耳与主体圆的径向重叠 [mm]
    'electrodeAngleDeg', 315.0, ... % 独立电极方向；工程坐标 315° = 右下 [deg]
    'electrodeArmLength', 5.0, ... % 独立电极板指外伸长度 [mm]
    'electrodeArmWidth', 1.5, ... % 独立电极板指宽度 [mm]
    'electrodeArmGap', 0.8, ... % 两个独立电极板指之间的净距 [mm]
    'electrodePadDiameter', 1.2, ... % 两个独立电极焊盘直径 [mm]
    'electrodeRootOverlap', 0.4, ... % 独立电极板指与主体圆的径向重叠 [mm]
    'bridgeTargetWidth', 1.5, ... % 连接桥目标宽度 [mm]
    'geometryScale', 1.0, ... % 宏观几何缩放系数
    'turnsPerCoilLayer', 7, ... % 每活动层物理匝数（完整 360° 圈数；分数匝模式保持平均）
    'traceWidth', 0.20, ... % 铜线宽度 [mm]
    'traceSpacing', 0.15, ... % 铜线净距 [mm]
    'pitchMargin', 0.005, ... % 节距附加余量 [mm]
    'edgeClearance', 0.30, ... % 铜到板框/槽净距 [mm]
    'boardOutlineLineWidth', 0.10, ... % 板框/槽轮廓线宽；auto 定径计入其内侧半宽 [mm]
    'geometrySafetyMargin', 0.002, ... % 多边形离散与布尔运算的定径安全余量 [mm]
    'samplePointsPerTurn', 360, ... % 每匝采样点数
    'turnScanMax', 16, ... % 匝数扫描上限
    'connectionAngleDeg', 135.0, ... % 端子/线圈/连接桥局部 u 轴方位角 [deg]；不旋转正向平台
    'padPairSpacing', 2.0, ... % 兼容旧参数；自动模式下与 terminalLeadSpacing 同步
    'terminalLeadSpacing', 2.0, ... % mm，两条平行端子引出线中心线间距 d
    'terminalLeadLength', 1.5, ... % mm，单次圆弧切点到 PAD 中心的直线长度 L；VOUT 到 PAD_B 同为 L
    'padDiameter', 0.6096, ... % PAD_A/PAD_B 直径 [mm]
    'viaPadDiameter', 0.55, ... % 过孔焊环外径 [mm]
    'viaDrillDiameter', 0.31, ... % 过孔钻孔内径 [mm]
    'viaCoilSpacing', 0.152, ... % 过孔焊环到线圈铜边净距 [mm]
    'minCopperInteriorAngleDeg', 90.0, ... % 铜走线内角必须严格大于该值 [deg]
    'minBoardInteriorAngleDeg', 90.0, ... % 板框/槽边内角必须严格大于该值 [deg]
    'angleToleranceDeg', 0.1, ... % 严格角度规则的数值安全余量 [deg]
    'terminalClearance', 0.25, ... % 焊盘/过孔端子间最小净距 [mm]
    'copperThickness', 0.012, ... % 嘉立创 1/3 oz 铜厚 [mm]
    'copperResistivity', 1.724e-8, ... % 铜电阻率 [Ohm*m]
    'manufacturingProfile', 'jlc_fpc_1_3oz', ...
    'manufacturingTier', 'standard', ...
    'manufacturingRuleOverrides', struct(), ...
    'enablePreview', true, ...
    'enableFigure', true, ...
    'analysisOnly', false, ... % 仅分析/验证，不导出文件（由主入口使用）
    'archivePreviousArtifacts', true, ... % 发布新产物后把同根下的旧完整产物自动移入 archive/ 并更新 LATEST.txt
    'outputRoot', fullfile(pwd, 'circular_fpc_output'), ...
    'designName', 'auto');

% 安装耳朵旧参数的显式弃用：mountingNotchDiameter 同时表达过槽宽/槽深/圆孔
% 直径三种语义，无法唯一映射到「槽口跨度 + 外凸高度」。此处不静默猜测映射，
% 而是明确报错并指出替代参数。
deprecatedMountingFields = { ...
    'mountingNotchDiameter', 'mountingSlotSpan / mountingSlotRise / mountingSlotEndFilletRadius'; ...
    'mountingNotchWall', 'mountingSlotSpan（槽口宽度由跨度与主体外径共同确定）'; ...
    'mountingLugLength', 'mountingSlotRise（外伸量现由外凸高度与 mountingSlotEdgeClearance 决定）'};
for k = 1:size(deprecatedMountingFields, 1)
    if isfield(overrides, deprecatedMountingFields{k, 1})
        error('CircularFPC:DeprecatedConfigField', ...
            ['%s is deprecated: it mixed slot width, slot depth and hole diameter in one ', ...
             'value and cannot be mapped without guessing. Use %s instead. See README ', ...
             '"Mounting ears" for the three-arc definition.'], ...
            deprecatedMountingFields{k, 1}, deprecatedMountingFields{k, 2});
    end
end

for f = fieldnames(overrides).'
    if ~isfield(cfg, f{1})
        error('CircularFPC:UnknownConfigField', 'Unknown config field: %s', f{1});
    end
    cfg.(f{1}) = overrides.(f{1});
end

% 槽到板边距离默认沿用项目既有的板边净距（edgeClearance）及其默认值。
if isnan(cfg.mountingSlotEdgeClearance)
    cfg.mountingSlotEdgeClearance = cfg.edgeClearance;
end

% 兼容旧版 1 oz profile：只有显式请求旧 profile 且未显式给铜厚时才恢复旧名义值。
% 新默认工艺始终是嘉立创 4 层 FPC0420TT-121A / 1/3 oz。
if isfield(overrides, 'manufacturingProfile') && ...
        strcmp(cfg.manufacturingProfile, 'jlc_fpc_1oz') && ~isfield(overrides, 'copperThickness')
    cfg.copperThickness = 0.035;
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
    cfg.designName = sprintf('Circular_FPC_%dL_%dC__%s', cfg.boardLayerCount, cfg.coilLayerCount, ...
        datestr(now, 'yyyymmdd_HHMMSS'));
end
cfg = CircularFpc.Quality.Result_Validation('validate_config', cfg);
end
