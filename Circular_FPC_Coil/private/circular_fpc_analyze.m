function result = circular_fpc_analyze(overrides)
% CIRCULAR_FPC_ANALYZE 只读分析入口。
%
%   result = CIRCULAR_FPC_ANALYZE()                    使用默认配置只读分析
%   result = CIRCULAR_FPC_ANALYZE(overrides)           overrides 为标量结构体
%
%   本入口只计算几何、端子重布线、验证与制造检查，不产生任何文件系统输出。
if nargin < 1
    overrides = struct();
end
cfg = circular_fpc_default_config(overrides);
result = circular_fpc_engine(cfg);
result = circular_fpc_terminal_reroute(cfg, result);
result.outputPath = '';
end
