function result = circular_fpc_main(overrides)
% CIRCULAR_FPC_MAIN 公开生成入口（R4）：配置 → 几何计算 → 端子重布线 → 原子导出。
%
%   result = CIRCULAR_FPC_MAIN()                    使用默认配置生成
%   result = CIRCULAR_FPC_MAIN(overrides)           overrides 为标量结构体，覆盖默认配置字段
%
%   返回 result 结构体（含 outputPath）。默认 enableFigure=true 时，在
%   MATLAB 桌面环境自动弹出图像窗口；无头环境自动跳过。正式输出目录
%   已存在时不会覆盖（报错）。
if nargin < 1
    overrides = struct();
end
cfg = circular_fpc_default_config(overrides);   % 默认配置 + 覆盖 + 配置校验
result = circular_fpc_engine(cfg);              % 基础几何与首轮验证（不写文件）
result = circular_fpc_terminal_reroute(cfg, result); % d/L 确定 PAD_A/PAD_B，单弯端子走线并二次验证
outputPath = circular_fpc_export('write_all', cfg, result); % 原子写入 DXF/SVG/CSV/TXT
result.outputPath = outputPath;
for k = 1:numel(result.validation.advisories)
    fprintf('ADVISORY: %s\n', result.validation.advisories{k});
end
if cfg.enableFigure && usejava('desktop')
    circular_fpc_plot(result);
end
end
