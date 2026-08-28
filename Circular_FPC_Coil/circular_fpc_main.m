function result = circular_fpc_main(overrides)
% CIRCULAR_FPC_MAIN 唯一公开执行入口（R4）：分析 → 原子导出。
%
%   result = CIRCULAR_FPC_MAIN()                    使用默认配置生成
%   result = CIRCULAR_FPC_MAIN(overrides)           overrides 为标量结构体，覆盖默认配置字段
%
%   返回 result 结构体（含 outputPath）。默认 enableFigure=true 时，在
%   MATLAB 桌面环境自动弹出图像窗口；无头环境自动跳过。正式输出目录
%   已存在时不会覆盖（报错）。设置 overrides.analysisOnly=true 可只做
%   分析与验证而不写文件；该模式供仓库内验证使用。
if nargin < 1
    overrides = struct();
end
% 几何、端子重布线、验证与制造检查由 private/circular_fpc_analyze
% 统一完成；公共层不暴露这些实现函数。
result = circular_fpc_analyze(overrides);
cfg = result.config;
if cfg.analysisOnly
    result.outputPath = '';
    return;
end
outputPath = circular_fpc_export('write_all', cfg, result); % 原子写入 DXF/SVG/CSV/TXT
result.outputPath = outputPath;
for k = 1:numel(result.validation.advisories)
    fprintf('ADVISORY: %s\n', result.validation.advisories{k});
end
if cfg.enableFigure && usejava('desktop')
    circular_fpc_plot(result);
end
end
