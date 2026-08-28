% GENERATE_RECTANGULAR_FPC 参数化矩形 FPC 线圈示例
% 集中修改下方参数区即可生成对应规格的 FPC 线圈。
% 输出目录固定为项目根目录下的 rectangular_fpc_output。

%% 参数区（集中可编辑）
layerCount          = 4;      % 层数
turnsPerLayer       = 12;     % 每层完整匝数
useRecommendedTurns = false;  % 是否使用自动推荐匝数
enablePreview       = true;   % 是否生成预览

%% 项目路径与路径设置
scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptDir);
if isempty(which('rectangular_fpc_main'))
    addpath(projectRoot);
end

%% 构造覆盖参数并调用公共入口
overrides = struct();
overrides.layerCount          = layerCount;
overrides.turnsPerLayer       = turnsPerLayer;
overrides.useRecommendedTurns = useRecommendedTurns;
overrides.enablePreview       = enablePreview;
overrides.designName          = sprintf('rectangular_fpc_%dlayer', layerCount);
overrides.outputRoot          = fullfile(projectRoot, 'rectangular_fpc_output');

result = rectangular_fpc_main(overrides);

%% 输出摘要
fprintf('输出目录    : %s\n', result.outputFolder);
fprintf('运行时间戳  : %s\n', result.runTimestamp);
fprintf('层数        : %d\n', result.layerCount);
fprintf('每层匝数    : %d\n', result.turnsPerLayer);
