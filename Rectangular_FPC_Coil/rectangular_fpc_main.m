function result = rectangular_fpc_main(overrides)
%RECTANGULAR_FPC_MAIN Analyze and optionally export a rectangular FPC coil.
%   RESULT = RECTANGULAR_FPC_MAIN() uses the documented defaults.
%   RESULT = RECTANGULAR_FPC_MAIN(OVERRIDES) applies supported overrides.
%   Set analysisOnly=true to run geometry, validation, and manufacturing
%   checks without creating files or directories.

if nargin < 1
    overrides = struct();
end

requestedCfg = rectangular_fpc_default_config(overrides);
validatedRequestedCfg = rectangular_fpc_validation('config', requestedCfg);
logicalDesignName = validatedRequestedCfg.designName;
runTimestamp = '';

analysisCfg = validatedRequestedCfg;
analysisCfg.analysisOnly = true;
result = rectangular_fpc_engine(analysisCfg);
effectiveCfg = result.config;
effectiveCfg.analysisOnly = validatedRequestedCfg.analysisOnly;
if ~validatedRequestedCfg.analysisOnly
    runTimestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmm'));
    exportCfg = effectiveCfg;
    exportCfg.designName = sprintf('%s_%s', logicalDesignName, runTimestamp);
    if ~result.manufacturing.exportAllowed
        error('RectangularFPC:ManufacturingFailed', ...
            'Manufacturing checks failed: %s', ...
            strjoin(result.manufacturing.failures, '; '));
    end
    result = rectangular_fpc_export('formal_export', exportCfg, result);
end
result.runTimestamp = runTimestamp;
result.logicalDesignName = logicalDesignName;
result.requestedConfig = requestedCfg;
result.config = effectiveCfg;

for k = 1:numel(result.manufacturing.warnings)
    fprintf('ADVISORY: %s\n', result.manufacturing.warnings{k});
end

% When enableFigure is true (default) and a MATLAB desktop is available,
% pop up the interactive figure viewer; headless runs (e.g. CI -batch) skip
% the popup automatically. The viewer is implemented in private/rectangular_fpc_plot.m
% and figures can be saved from the window menu.
if ~validatedRequestedCfg.analysisOnly && ...
        validatedRequestedCfg.enableFigure && usejava('desktop')
    rectangular_fpc_plot(result);
end

end
