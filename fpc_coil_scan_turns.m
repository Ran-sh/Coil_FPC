function scan = fpc_coil_scan_turns(cfg, turnValues)
%FPC_COIL_SCAN_TURNS Generate and validate selected turn-count candidates.

cfg = fpc_coil_validate_config(cfg);
validateattributes(turnValues, {'numeric'}, ...
    {'vector', 'integer', 'positive', 'finite'});

turnValues = reshape(turnValues, 1, []);
scan = repmat(struct( ...
    'turns', 0, ...
    'passed', false, ...
    'failureReason', '', ...
    'minCopperAngle', NaN, ...
    'minCopperSpacing', NaN, ...
    'totalLengthMm', NaN, ...
    'totalResistanceOhm', NaN), numel(turnValues), 1);

for index = 1:numel(turnValues)
    candidate = cfg;
    candidate.useRecommendedTurns = false;
    candidate.turnsPerLayer = turnValues(index);
    candidate.designName = sprintf('%s_scan_%dturns', ...
        cfg.designName, turnValues(index));
    candidate.enablePreview = false;

    scan(index).turns = turnValues(index);
    try
        result = fpc_coil_generate(candidate);
        scan(index).passed = result.passed;
        scan(index).minCopperAngle = result.minCopperAngle;
        scan(index).minCopperSpacing = result.minCopperSpacing;
        scan(index).totalLengthMm = result.totalLengthMm;
        scan(index).totalResistanceOhm = result.totalResistanceOhm;
    catch ME
        scan(index).passed = false;
        scan(index).failureReason = ME.message;
    end
end

end
