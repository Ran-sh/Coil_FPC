% 一键生成五种层叠（2/1、2/2、4/1、4/2、4/4）的完整产物。
%
% 用法：
%   run examples/generate_all_variants.m              % 输出到 <project>/outputs
%   outputRoot = 'D:/some/dir'; run examples/generate_all_variants.m
%
% 说明：
%   - 若调用者工作区已有 outputRoot 则使用该值，否则默认 <project>/outputs；
%   - 不覆盖已有正式输出目录（circular_fpc_main 在目录已存在时报错）；
%   - 不删除任何目录、不捕获错误。
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
if ~exist('outputRoot', 'var') || isempty(outputRoot)
    outputRoot = fullfile(projectRoot, 'outputs');
end
combos = [2 1; 2 2; 4 1; 4 2; 4 4];
designNames = {'Circular_FPC_2L_1C', 'Circular_FPC_2L_2C', ...
    'Circular_FPC_4L_1C', 'Circular_FPC_4L_2C', 'Circular_FPC_4L_4C'};
variantResults = cell(1, 5);
for k = 1:5
    variantResults{k} = circular_fpc_main(struct( ...
        'boardLayerCount', combos(k, 1), ...
        'coilLayerCount', combos(k, 2), ...
        'outputRoot', outputRoot, ...
        'designName', designNames{k}));
end
for k = 1:5
    fprintf('%s -> %s\n', designNames{k}, variantResults{k}.outputPath);
end
