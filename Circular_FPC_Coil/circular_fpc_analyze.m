function result = circular_fpc_analyze(overrides)
% CIRCULAR_FPC_ANALYZE 只读分析入口（R2/ADR-5）。
%
%   result = CIRCULAR_FPC_ANALYZE()                    使用默认配置只读分析
%   result = CIRCULAR_FPC_ANALYZE(overrides)           overrides 为标量结构体
%
%   与 circular_fpc_main 不同：本入口只计算几何、验证与制造检查报告，
%   不调用 export/mkdir/plot/write，也不调用 warning()，不产生任何
%   文件系统输出；返回 result 的 outputPath 恒为 ''（ADR-5）。
%
%   坐标约定与 engine 一致：+X 向右、+Y 向上。SVG 预览的 Y 轴翻转只
%   发生在导出层，本只读入口不涉及。
if nargin < 1
    overrides = struct();
end
cfg = circular_fpc_default_config(overrides);   % 默认配置 + 覆盖 + 配置/制造校验
result = circular_fpc_engine(cfg);              % 只计算，不写文件（含制造结果二次审查）
result.outputPath = '';                         % 只读入口不产生输出路径
end
