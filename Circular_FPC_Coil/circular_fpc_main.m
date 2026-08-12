function result = circular_fpc_main(overrides)
% CIRCULAR_FPC_MAIN 公开生成入口（R4）：配置 → 几何计算 → 原子导出。
%
%   result = CIRCULAR_FPC_MAIN()                    使用默认配置生成
%   result = CIRCULAR_FPC_MAIN(overrides)           overrides 为标量结构体，覆盖默认配置字段
%
%   返回 result 结构体（含 outputPath）。默认 enableFigure=true 时，在
%   MATLAB 桌面环境自动弹出图像窗口；无头环境自动跳过，之后可手动调用
%   circular_fpc_plot(result)。正式输出目录已存在时不会覆盖（报错）。
if nargin < 1
    overrides = struct();
end
cfg = circular_fpc_default_config(overrides);   % 默认配置 + 覆盖 + 配置校验
result = circular_fpc_engine(cfg);              % 计算几何与结果验证（不写文件）
outputPath = circular_fpc_export('write_all', cfg, result); % 原子写入 DXF/SVG/CSV/TXT
result.outputPath = outputPath;
% 运行完成后在 MATLAB 桌面环境自动弹出图像窗口（可在窗口内另存为其他格式）。
% 无头环境（如 CI 的 -batch 运行）自动跳过，需要时仍可手动调用 circular_fpc_plot(result)。
if cfg.enableFigure && usejava('desktop')
    circular_fpc_plot(result);
end
end
