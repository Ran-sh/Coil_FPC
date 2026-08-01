function result = fpc_coil_main()
% FPC_COIL_MAIN
% FPC多层线圈统一入口。
%
% 用户只修改本文件中的cfg参数。
% cfg.layerCount支持2层或4层。
% 程序自动生成对应DXF、CSV、报告和预览图。

clc;
close all;

%% =========================================================
% 1. 层数和匝数
%% =========================================================

cfg.layerCount = 4;                 % 只允许2或4

cfg.useRecommendedTurns = true;     % true：按层数自动设置推荐匝数
cfg.turnsPerLayer = 10;             % false时使用本参数

% 推荐默认值：
% 2层：10匝/层
% 4层：6匝/层

%% =========================================================
% 2. 接骨板主体
%% =========================================================

cfg.plateLength = 80.0;             % 主体长度，mm
cfg.plateWidth = 12.0;              % 主体宽度，mm
cfg.plateCornerRadius = 3.0;        % 主体圆角半径，mm

%% =========================================================
% 3. 右侧新增尾部
%% =========================================================

cfg.tabLength = 12.0;               % 只向右增加，mm
cfg.tabWidth = 5.0;                 % 尾部宽度，mm
cfg.tabOuterCornerRadius = 1.5;     % 尾部右端圆角，mm
cfg.tabTransitionRadius = 1.5;      % 主体与尾部过渡圆弧，mm
cfg.tabEdgeMargin = 0.30;           % 焊盘到尾部上下边缘裕量，mm

%% =========================================================
% 4. 铜线参数
%% =========================================================

cfg.traceWidth = 0.20;              % 铜线宽度，mm
cfg.traceSpacing = 0.15;            % 目标净线距，mm
cfg.pitchMargin = 0.005;            % 几何附加节距，mm
cfg.edgeClearance = 0.50;           % 铜线到主体板边，mm
cfg.minInnerWidth = 2.00;           % 中心最小保留宽度，mm
cfg.minSpiralCornerRadius = 0.80;   % 线圈最小圆角半径，mm

%% =========================================================
% 5. 右侧引出线和焊盘
%% =========================================================

cfg.leadYOffset = 1.30;             % 上下引线Y偏移，mm
cfg.leadBendRadius = 1.20;          % 引出相切圆弧半径，mm
cfg.leadArcPointCount = 64;         % 引出圆弧采样点数

cfg.padTipInset = 1.50;             % 焊盘中心距尾部右端，mm
cfg.padDiameter = 1.50;             % 焊盘直径，mm
cfg.padTipMargin = 0.20;            % 焊盘边缘到尾部右端裕量，mm
cfg.leadTabClearance = 0.50;        % 水平引线最小长度，mm
cfg.padToPadClearance = 0.15;       % 两焊盘之间最小净距，mm
cfg.padToCopperClearance = 0.15;    % 焊盘到其他铜线净距，mm

%% =========================================================
% 6. 过孔参数
%% =========================================================

cfg.viaDrillDiameter = 0.30;        % 钻孔直径，mm
cfg.viaPadDiameter = 0.60;          % 过孔焊盘直径，mm

cfg.viaToCopperClearance = 0.15;    % 过孔焊盘到非连接铜线净距，mm
cfg.viaToBoardClearance = 0.30;     % 过孔焊盘到板框净距，mm
cfg.viaToViaClearance = 0.20;       % 两过孔焊盘之间净距，mm
cfg.viaToPadClearance = 0.20;       % 过孔焊盘到外接焊盘净距，mm
cfg.viaLandingLeadLength = 0.80;    % 过孔逃逸引线长度，mm
cfg.viaLandingClearance = 0.15;     % 过孔焊盘到本层其他匝净距，mm
cfg.viaInnerBendRadius = 0.50;      % V12/V34内圈逃逸圆弧半径，mm
cfg.viaOuterLandingLeadLength = 1.00; % V23外圈过孔向尾部引出长度，mm
cfg.viaOuterLandingClearance = 0.15;  % V23焊盘到本层其他匝净距，mm
cfg.viaOuterBendRadius = 0.30;        % V23引出圆弧半径，mm

% 四层过孔检查不通过时：
% 'warning'：继续输出，但报告WARN
% 'error'：直接停止生成
cfg.viaClearanceSeverity = 'warning';

%% =========================================================
% 7. 铜厚和电阻估算
%% =========================================================

cfg.copperThickness = 0.035;        % 铜厚，mm
cfg.copperResistivity = 1.724e-8;   % 铜电阻率，Ohm*m

%% =========================================================
% 8. 几何与数值容差
%% =========================================================

cfg.minCopperInteriorAngleDeg = 90.0;
cfg.minBoardInteriorAngleDeg = 90.0;
cfg.angleToleranceDeg = 0.1;

cfg.geometryTolerance = 1e-6;       % 坐标容差，mm
cfg.connectionTolerance = 1e-5;     % 层间端点容差，mm
cfg.clearanceTolerance = 0.002;     % 线距判断容差，mm

cfg.crossProductTolerance = 1e-12;  % 线段相交叉积容差
cfg.parameterTolerance = 1e-9;      % 线段参数容差

%% =========================================================
% 9. 离散、DXF和预览
%% =========================================================

cfg.pointsPerTurn = 900;
cfg.minTurnPointCount = 500;
cfg.boardArcPointCount = 64;
cfg.maxVerticesPerDxfEntity = 220;
cfg.previewDpi = 220;
cfg.enablePreview = true;           % 本机图形异常时可临时设为false

%% =========================================================
% 10. 检查开关
%% =========================================================

cfg.enableExactSelfIntersectionCheck = true;
cfg.enableCopperClearanceCheck = true;
cfg.enableBoardAngleCheck = true;
cfg.enableCopperAngleCheck = true;
cfg.enablePadClearanceCheck = true;
cfg.enableViaClearanceCheck = true;
cfg.enableDxfReadbackCheck = true;

%% =========================================================
% 11. 输出
%% =========================================================

cfg.outputRoot = fullfile(pwd, 'fpc_coil_output');

%% =========================================================
% 12. 根据层数自动设置
%% =========================================================

switch cfg.layerCount
    case 2
        cfg.designName = 'fpc_coil_2layer';

        if cfg.useRecommendedTurns
            cfg.turnsPerLayer = 10;
        end

    case 4
        cfg.designName = 'fpc_coil_4layer';

        if cfg.useRecommendedTurns
            cfg.turnsPerLayer = 6;
        end

    otherwise
        error('cfg.layerCount只允许设置为2或4。');
end

%% =========================================================
% 13. 调用生成核心
%% =========================================================

result = fpc_coil_generate(cfg);

end
