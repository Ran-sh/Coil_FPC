function cfg = circular_fpc_default_config(overrides)
% CIRCULAR_FPC_DEFAULT_CONFIG 圆环 FPC 线圈生成器的默认配置（R1 契约）。
%
%   cfg = CIRCULAR_FPC_DEFAULT_CONFIG()                    使用全部默认值
%   cfg = CIRCULAR_FPC_DEFAULT_CONFIG(overrides)           用结构体覆盖部分字段
%
%   overrides 必须是标量结构体，字段名必须是本配置中已有的字段
%   （未知字段报 CircularFPC:UnknownConfigField）。覆盖后的配置会经
%   circular_fpc_validation('validate_config') 统一校验
%   （正数、整数、层叠组合、字段类型等）。
%
%   单位约定：几何尺寸均为毫米（mm），角度为度（deg），电阻率为 Ohm·m。
%   各字段含义见下方 struct 内逐项注释。
if nargin < 1
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('CircularFPC:InvalidConfig', 'overrides must be a scalar struct.');
end

% 注意：struct(...) 续行内部不能放独立注释行（MATLAB 会报语法错误），
% 因此所有字段说明都写在 '...' 之后同行内联。
cfg = struct( ...
    'boardLayerCount', 2, ... % 物理板层数：2 或 4
    'coilLayerCount', 1, ... % 活动线圈层数：与板层数只支持 2/1、2/2、4/1、4/2、4/4
    'boardOuterDiameter', 25.0, ... % 圆形板外径 [mm]（随 geometryScale 缩放；仅 boardSizingMode='fixed' 时使用）
    'boardSizingMode', 'auto', ... % 板框定尺寸方式：'auto' 由线圈匝数自动计算板框外径（推荐，输出报告板框尺寸）；'fixed' 使用 boardOuterDiameter
    'coilInnerDiameter', 18.63, ... % 螺旋线圈最内圈直径 [mm]（随缩放）
    'centerPlatformWidth', 13.0, ... % 中央连接平台宽度（切向）[mm]，可与高度独立配置（随缩放）
    'centerPlatformHeight', 11.0, ... % 中央连接平台高度（径向）[mm]，默认矩形平台（随缩放）
    'bridgeTargetWidth', 1.5, ... % 连接桥目标宽度 [mm]（随缩放）；实际桥宽会被验证不小于该值
    'geometryScale', 1.0, ... % 宏观几何缩放系数：只缩放上述宏观尺寸，不缩放制造参数
    'turnsPerCoilLayer', 8, ... % 每活动层匝数（默认 8；外端过孔通过径向延伸区放置，不影响线距/匝数）
    'traceWidth', 0.20, ... % 铜走线宽度 [mm]（制造参数，不随缩放）
    'traceSpacing', 0.15, ... % 相邻铜走线之间的最小净距 [mm]（制造参数）
    'pitchMargin', 0.005, ... % 螺旋节距安全余量 [mm]；coilPitch = traceWidth + traceSpacing + pitchMargin
    'edgeClearance', 0.30, ... % 铜到板外缘 / 孔槽的最小净距 [mm]（= 嘉立创 DRC 铜-板框 0.29972）
    'samplePointsPerTurn', 360, ... % 每匝采样点数：折线精度，点数越多越光滑、输出文件越大
    'turnScanMax', 16, ... % 04_turn_scan.csv 中匝数扫描的上限
    'connectionAngleDeg', 135.0, ... % 连接区（入口桥）方位角 [deg]，0° 指向 +X；决定焊盘对与进出线方向
    'padPairSpacing', 2.0, ... % PAD_A/PAD_B 沿连接角切向并排的中心距 [mm]，不随缩放
    'terminalPlacementMode', 'auto', ... % 端子放置方式：'auto' 自动搜索安全位置 / 'manual' 用下面三个坐标字段
    'manualPadAXY', zeros(0, 2), ... % manual 模式：PAD_A 坐标 [x y]（Nx2，mm）
    'manualPadBXY', zeros(0, 2), ... % manual 模式：PAD_B 坐标 [x y]（Nx2，mm）
    'manualSeriesViaXY', zeros(0, 2), ... % manual 模式：串联过孔坐标；行序须与过孔顺序一致：2/1、4/1 为 [VRET;VOUT]、2/2 为 [V12;VOUT]、4/2 为 [V14;VOUT]、4/4 为 [V12;V23;V34;VOUT]
    'padDiameter', 0.6096, ... % PAD_A/PAD_B 外接焊盘直径 [mm]（24 mil，可调；位于 135° 入口桥侧）
    'viaPadDiameter', 0.55, ... % 过孔焊环（pad）外径 [mm]（默认 0.55 = 嘉立创 FPC 常规推荐；外径-内径须 >= 0.2，推荐 >= 0.25）
    'viaDrillDiameter', 0.3, ... % 过孔钻孔内径 [mm]（默认 0.3，可调；制造极限：2 层板内径>=0.1/外径>=0.3，4 层板内径>=0.15/外径>=0.35，接近极限增加费用）
    'viaCoilSpacing', 0.152, ... % 过孔焊环外缘到相邻线圈匝铜边的最小净距 [mm]（= 嘉立创 DRC Track-Via 6mil；外端过孔通过径向延伸区保证，不影响线距）
    'minCopperInteriorAngleDeg', 90.0, ... % 铜走线路径允许的最小内角 [°]（严格大于该值；不允许 90° 及以下拐角）
    'minBoardInteriorAngleDeg', 90.0, ... % 板框（含挖空槽）允许的最小内角 [°]（严格大于该值；槽角自动圆角化）
    'angleToleranceDeg', 0.1, ... % 角度容差 [°]：叠加在铜线与板框最小内角阈值上（≤ 阈值+容差 即判定违规）
    'antipadDiameter', 1.2, ... % 反焊盘直径 [mm]：4 层板中过孔的非连接物理层 DXF 使用
    'terminalClearance', 0.25, ... % 焊盘/过孔等端子之间的最小净距 [mm]
    'copperThickness', 0.035, ... % 铜箔厚度 [mm]，仅用于估算直流电阻
    'copperResistivity', 1.724e-8, ... % 铜电阻率 [Ohm·m]，仅用于估算直流电阻
    'manufacturingProfile', 'jlc_fpc_1oz', ... % 制造档案名称：当前仅支持 'jlc_fpc_1oz'
    'manufacturingTier', 'standard', ... % 制造档位：'standard' 常规 JLC 极限 / 'extreme' 层相关最小尺寸（记录 HIGH_COST_EXTREME 警告）
    'manufacturingRuleOverrides', struct(), ... % 制造规则覆盖：仅允许覆盖已定义规则（见 private/circular_fpc_manufacturing.m），值为正有限标量
    'enablePreview', true, ... % 是否生成 previews/ 下的 SVG 预览文件
    'enableFigure', true, ... % 生成完成后是否在 MATLAB 桌面自动弹出图像窗口（无头环境自动跳过）
    'outputRoot', fullfile(pwd, 'circular_fpc_output'), ... % 输出根目录；正式产物在 <outputRoot>/<designName>/
    'designName', 'Circular_FPC_2L_1C'); % 设计名（用作输出目录名），只允许字母/数字/下划线/连字符

for f = fieldnames(overrides).'
    if ~isfield(cfg, f{1})
        error('CircularFPC:UnknownConfigField', 'Unknown config field: %s', f{1});
    end
    cfg.(f{1}) = overrides.(f{1});
end
cfg = circular_fpc_validation('validate_config', cfg);
end
