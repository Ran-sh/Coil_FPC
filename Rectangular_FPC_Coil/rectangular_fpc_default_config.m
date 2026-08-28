function cfg = rectangular_fpc_default_config(overrides)
%RECTANGULAR_FPC_DEFAULT_CONFIG Return a caller-overridable configuration.
%   CFG = RECTANGULAR_FPC_DEFAULT_CONFIG() returns the production defaults.
%   CFG = RECTANGULAR_FPC_DEFAULT_CONFIG(OVERRIDES) replaces supported fields
%   from a scalar struct and rejects unknown field names.

if nargin < 1
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('RectangularFPC:InvalidOverrides', ...
        'overrides must be a scalar struct.');
end

cfg = struct();

% Winding and supported stack-up.
% 线圈匝数与支持的层叠参数
cfg.layerCount = 4;                                        % 层，当前生成的 FPC 铜层数量，只支持 2 到 maxLayerCount 的偶数
cfg.maxLayerCount = 8;                                     % 层，允许的最大铜层数，仅作为 layerCount 的上限校验
cfg.useRecommendedTurns = false;                           % 布尔，true 时自动使用安全推荐匝数（完整验证上限减 recommendedTurnMargin），忽略 turnsPerLayer
cfg.turnsPerLayer = 12;                                     % 匝，手动模式下的每层匝数（每层整数圈数），超过理论上限会报错

% Connection anchors (normalized phase).
% 层间连接锚点参数（归一化相位）
cfg.connectionPhase = 0.0;                                 % —，归一化相位，所有层内外连接锚点所在位置（0~1）
cfg.connectionSide = 'right_center';                       % 字符串，连接锚点所在方位，当前支持 'right_center'

% Board body and right-hand terminal tab (mm).
% 主板区域与右侧端子尾板尺寸，单位：mm
cfg.plateLength = 80.0;                                    % mm，主体线圈区域长度
cfg.plateWidth = 12.0;                                     % mm，主体线圈区域宽度
cfg.plateCornerRadius = 3.0;                               % mm，仅控制接骨板主体外框圆角
cfg.tabLength = 12.0;                                      % mm，右侧尾板长度，从主体右边缘向外延伸
cfg.tabWidth = 5.0;                                        % mm，右侧尾板宽度，需容纳焊盘、引出线与边距
cfg.tabOuterCornerRadius = 1.5;                            % mm，尾板外端两个圆角半径
cfg.tabTransitionRadius = 1.5;                             % mm，主体与尾板之间的过渡圆角半径
cfg.tabEdgeMargin = 0.30;                                  % mm，尾板内边缘相对焊盘/引出线预留的最小边距

% Copper geometry (mm).
% 铜线几何参数，单位：mm
cfg.traceWidth = 0.20;                                     % mm，铜线宽度
cfg.traceSpacing = 0.15;                                   % mm，相邻铜线之间的目标净间距
cfg.pitchMargin = 0.005;                                   % mm，附加节距余量，实际节距 = traceWidth + traceSpacing + pitchMargin
cfg.edgeClearance = 0.50;                                  % mm，铜线边缘到主体板边的安全距离
cfg.minInnerWidth = 1.00;                                  % mm，线圈中心必须保留的空白区域宽度
cfg.minInnerLength = 1.00;                                 % mm，线圈中心必须保留的空白区域最小长度
cfg.minSpiralCornerRadius = 0.80;                          % mm，螺旋最内圈允许的最小圆角半径（严格同心模式下作为匝数上限约束）

% Coil outer corner radius modes.
% 线圈外圈圆角模式（与板框圆角 plateCornerRadius 解耦）
cfg.coilOuterCornerRadiusMode = 'maximize';                % 字符串，'follow_board'、'maximize' 或 'manual'，决定线圈最外圈中心线圆角半径
cfg.coilOuterCornerRadius = [];                            % mm，manual 模式下的线圈最外圈中心线圆角半径，其他模式忽略
cfg.cornerOffsetMode = 'strict_concentric';                % 字符串，'strict_concentric'（严格同心等距）或 'legacy_clamped'（旧版最小半径截断）

% Leads and external pads (mm).
% 引出线与外部焊盘参数，单位：mm
cfg.leadYOffset = 1.10;                                    % mm，PAD_A/PAD_B/VOUT 相对板中线的 Y 方向偏移
cfg.leadBendRadius = 1.20;                                 % mm，焊盘与螺旋之间 90° 切向圆弧的半径
cfg.leadArcPointCount = 64;                                % 点，引出线圆弧（含逃逸引线圆弧）的采样点数
cfg.padTipInset = 1.50;                                    % mm，焊盘圆心到尾板右端尖端的水平内缩距离
cfg.padDiameter = 1.50;                                    % mm，PAD_A/PAD_B 焊盘直径
cfg.padTipMargin = 0.20;                                   % mm，焊盘右缘到尾板尖端的最小间隙，仅用于配置校验
cfg.leadTabClearance = 0.50;                               % mm，焊盘到圆弧起点之间水平引出线段的最小长度
cfg.padToPadClearance = 0.15;                              % mm，PAD_A 与 PAD_B 之间的目标净间距
cfg.padToCopperClearance = 0.20;                           % mm，焊盘边缘到非连接铜线的最小净距（JLCPCB FPC 生产经验下限）

% Inter-layer vias (mm).
% 层间串联过孔参数，单位：mm
cfg.viaDrillDiameter = 0.30;                               % mm，层间过孔钻孔直径
cfg.viaPadDiameter = 0.60;                                 % mm，层间过孔焊盘直径
cfg.viaToCopperClearance = 0.20;                           % mm，过孔焊盘到非连接铜层铜线的最小净距
cfg.viaToBoardClearance = 0.30;                            % mm，层间过孔到板框的最小净距
cfg.viaToViaClearance = 0.20;                              % mm，相邻过孔之间的目标净间距
cfg.viaToPadClearance = 0.20;                              % mm，过孔焊盘到 PAD_A/PAD_B 的目标净间距
cfg.viaLandingLeadLength = 0.80;                           % mm，旧版自动模式（legacy_auto）内侧过孔朝线圈内部方向的逃逸引线长度
cfg.viaLandingClearance = 0.15;                            % mm，内侧过孔与其连接层铜线之间的净距
cfg.viaInnerBendRadius = 0.60;                             % mm，内侧逃逸引线圆弧半径上限；为通孔反焊盘保留净距
cfg.viaOuterLandingLeadLength = 1.00;                      % mm，旧版自动模式外侧过孔朝右的逃逸引线长度
cfg.viaOuterLandingClearance = 0.15;                       % mm，外侧过孔与其连接层铜线之间的净距
cfg.viaOuterBendRadius = 0.30;                             % mm，外侧逃逸引线圆弧半径上限
cfg.viaClearanceSeverity = 'warning';                      % 字符串，过孔在非连接层净距不足时按 'warning'（仅报告）或 'error'（验证失败）处理

% Via placement planning.
% 过孔自动规划参数
cfg.viaPlacementMode = 'hybrid_auto';                      % 字符串，'legacy_auto'（旧版自动）、'hybrid_auto'（推荐自动）或 'manual'（人工坐标）
cfg.innerViaLayout = 'horizontal';                         % 字符串，内圈过孔排列方向，当前支持 'horizontal'（沿 X 方向）
cfg.innerViaPitch = 2.00;                                  % mm，内圈过孔期望中心间距（实际取 max(该值, viaPadDiameter+viaToViaClearance)）
cfg.innerViaRowOffsetY = 0.00;                             % mm，内圈过孔排相对主体中线的 Y 方向偏移
cfg.outerViaLayout = 'horizontal';                         % 字符串，右侧尾板过孔排列方向，当前支持 'horizontal'（沿 X 方向）
cfg.outerViaPitch = 1.50;                                  % mm，尾板过孔期望中心间距
cfg.outerViaRowOffsetY = 0.00;                             % mm，尾板过孔排相对主体中线的 Y 方向偏移
cfg.viaKeepoutMargin = 0.10;                               % mm，过孔自动规划附加安全余量
cfg.autoViaGridStep = 0.25;                                % mm，自动过孔候选位置搜索步长
cfg.recommendedTurnMargin = 1;                             % 匝，推荐匝数相对完整验证上限保留的匝数裕量

% Last-layer output via and independent L1 return (mm). VOUT reuses the
% common drill/pad diameters and is a through via with inner-layer antipads.
% 末层输出过孔与 L1 独立回路线参数，单位：mm；VOUT 为贯穿所有层的通孔，中间层需按反焊盘直径开禁铜窗
cfg.outputViaType = 'through_via';                         % 字符串，VOUT 过孔类型，目前只支持贯穿所有层的 'through_via'
cfg.outputViaTipInset = 4.00;                              % mm，auto 模式 VOUT 圆心到尾板右端尖端的最小水平内缩限制（实际位置可更靠左）
cfg.outputViaAntiPadDiameter = 1.00;                       % mm，VOUT 在中间非连接层的反焊盘（禁铜开窗）直径
cfg.outputViaToCopperClearance = 0.20;                     % mm，VOUT 到 L1 回路线铜线的最小净距
cfg.outputViaToBoardClearance = 0.30;                      % mm，VOUT 到板框的最小净距

% User coordinate origin and manual via coordinates.
% 用户坐标系与人工过孔坐标参数
cfg.coordinateOrigin = 'body_lower_left';                  % 字符串，用户输入及导出坐标原点，当前支持 'body_lower_left'（主体左下角）
cfg.manualSeriesViaXY = zeros(0,2);                        % mm，人工层间过孔坐标，每行依次对应 V12、V23、V34……；手动模式下行数必须等于 layerCount-1
cfg.outputViaPlacementMode = 'auto';                       % 字符串，VOUT 使用 'auto'（自动）或 'manual'（人工坐标）
cfg.manualOutputViaXY = zeros(0,2);                        % mm，人工 VOUT 坐标，仅 manual 模式使用（1×2 矩阵）

% Material and manufacturing assumptions.
% 材料与制造假设参数
cfg.copperThickness = 0.035;                               % mm，铜箔厚度，用于直流电阻估算
cfg.copperResistivity = 1.724e-8;                          % Ω·m，铜电阻率，用于直流电阻估算
cfg.minAnnularRing = 0.10;                                 % mm，过孔最小环宽（对应焊盘与钻孔直径差至少 0.20 mm）
cfg.manufacturingProfile = 'jlc_fpc_1oz';                  % 字符串，制造规则档案
cfg.manufacturingTier = 'standard';                        % 字符串，'standard' 或 'extreme'
cfg.manufacturingRuleOverrides = struct();                 % 结构体，允许覆盖制造规则模块公开的数值规则

% Geometry tolerances and discretization.
% 几何容差与离散化参数
cfg.minCopperInteriorAngleDeg = 90.0;                      % °，铜线路径允许的最小内角，实际要求严格大于该值加 angleToleranceDeg
cfg.minBoardInteriorAngleDeg = 90.0;                       % °，板框允许的最小内角，实际要求严格大于该值加 angleToleranceDeg
cfg.angleToleranceDeg = 0.1;                               % °，叠加在铜线与板框最小内角阈值上的角度容差
cfg.requireSmoothLeadTransitions = true;                   % 布尔，true 时引线无法构造平滑过渡而回退成尖角即验证失败
cfg.geometryTolerance = 1e-6;                              % mm，全局几何容差，用于点去重、零长度段与尺寸校验
cfg.connectionTolerance = 1e-5;                            % mm，层间端点连接误差上限，超过即验证失败
cfg.clearanceTolerance = 0.002;                            % mm，线距检查允许的负偏差，目标中心线距减去该值作为下限
cfg.crossProductTolerance = 1e-12;                         % —，自交检查中判断线段平行所用的叉积阈值
cfg.parameterTolerance = 1e-9;                             % —，自交检查中线段交点参数 t/u 的端点包容容差
cfg.pointsPerTurn = 900;                                   % 点，每匝螺旋的采样点数
cfg.minTurnPointCount = 500;                               % 点，单条螺旋路径的最少采样点数，与 pointsPerTurn 取较大者
cfg.boardArcPointCount = 64;                               % 点，板框所有圆弧的采样点数
cfg.maxVerticesPerDxfEntity = 220;                         % 点，单条 DXF LWPOLYLINE 允许的最大顶点数，超出时按此拆分
cfg.enablePreview = true;                                  % 布尔，true 时生成 previews 预览图，false 时跳过
cfg.enableFigure = true;                                   % 布尔，true 时运行完成后在 MATLAB 桌面环境弹出图像窗口（figure），可在窗口内另存为其他格式

% Validation switches.
% 验证开关，关闭后不合格几何可能进入输出文件，生产设计不建议关闭
cfg.enableExactSelfIntersectionCheck = true;               % 布尔，true 时检查板框与铜线自交、同层路径间相交
cfg.enableCopperClearanceCheck = true;                     % 布尔，true 时检查铜线之间的实际最小线距
cfg.enableBoardAngleCheck = true;                          % 布尔，true 时检查板框最小内角
cfg.enableCopperAngleCheck = true;                         % 布尔，true 时检查铜线路径最小内角
cfg.enablePadClearanceCheck = true;                        % 布尔，true 时检查焊盘在板内、焊盘互距及焊盘到铜线净距
cfg.enableViaClearanceCheck = true;                        % 布尔，true 时检查过孔互距及过孔到板框/焊盘/铜线净距与反焊盘开窗
cfg.enableDxfReadbackCheck = true;                         % 布尔，true 时回读 DXF 检查文件完整性与顶点数

% Output.
% 输出目录参数
cfg.analysisOnly = false;                                  % 布尔，true 时只分析/验证，不创建任何文件或目录
cfg.outputRoot = fullfile(pwd, 'rectangular_fpc_output');  % 字符串，输出根目录；正式输出为 <designName>_yyyyMMdd_HHmm
cfg.designName = 'rectangular_fpc_4layer';                 % 字符串，逻辑设计名，只允许字母、数字、下划线和连字符

names = fieldnames(overrides);
for k = 1:numel(names)
    name = names{k};
    if ~isfield(cfg, name)
        error('RectangularFPC:UnknownConfigField', ...
            'Unknown configuration field ''%s''.', name);
    end
    cfg.(name) = overrides.(name);
end

% Derive only the design folder name when layerCount is overridden.
% 层数只影响输出目录名，不再自动修改每层匝数（匝数由几何尺寸与验证决定）。
if ~isfield(overrides, 'designName') && isfield(overrides, 'layerCount')
    cfg.designName = sprintf('rectangular_fpc_%dlayer', cfg.layerCount);
end

end
