% GENERATE_RECTANGULAR_FPC 参数化矩形 FPC 线圈示例
% 集中修改下方参数区即可生成对应规格的 FPC 线圈。
% 输出目录固定为项目根目录下的 rectangular_fpc_output；同名设计在
% 同一分钟内替换该分钟版本，跨分钟保留历史版本。

%% 参数区（集中可编辑）
layerCount          = 4;      % 层数
turnsPerLayer       = 12;     % 每层完整匝数
useRecommendedTurns = false;  % 是否使用自动推荐匝数
enablePreview       = true;   % 是否生成预览

%% 项目路径与路径设置
scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptDir);
originalPath = path;
pathCleanup = onCleanup(@() path(originalPath));
addpath(projectRoot, '-begin');
entry = which('rectangular_fpc_main');
assert(strcmpi(entry, fullfile(projectRoot, 'rectangular_fpc_main.m')), ...
    'RectangularFPC:WrongProjectOnPath', ...
    '示例解析到了其他目录中的 rectangular_fpc_main。');

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
fprintf('输出目录    : %s\n', result.outputPath);
fprintf('运行时间戳  : %s\n', result.runTimestamp);
fprintf('层数        : %d\n', result.layerCount);
fprintf('每层匝数    : %d\n', result.turnsPerLayer);
fprintf('制造状态    : %s\n', result.manufacturing.status);
fprintf('适用范围    : %s\n', result.manufacturing.applicability);
fprintf('官方已验证  : %d\n', result.manufacturing.verified);
if ~result.manufacturing.verified
    warning('RectangularFPC:UnverifiedManufacturing', ...
        '该输出不是当前官方制造档案下的已验证设计。');
end
clear pathCleanup;
