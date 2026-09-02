function varargout = rectangular_fpc_manufacturing(operation, varargin)
%RECTANGULAR_FPC_MANUFACTURING Central owner of manufacturing rules.
switch operation
    case 'validate_config'
        validateManufacturingConfig(varargin{1});
    case 'resolve'
        varargout{1} = resolveProfile(varargin{1});
    case 'check_config'
        varargout{1} = buildReport(varargin{1}, struct());
    case 'check_result'
        varargout{1} = buildReport(varargin{1}, varargin{2});
    otherwise
        error('RectangularFPC:InvalidOperation', ...
            'Unknown manufacturing operation: %s.', operation);
end
end

function validateManufacturingConfig(cfg)
if ~ischar(cfg.manufacturingProfile) || ...
        ~strcmp(cfg.manufacturingProfile, 'jlc_fpc_1oz')
    error('RectangularFPC:InvalidConfigValue', ...
        'manufacturingProfile must be ''jlc_fpc_1oz''.');
end
if ~ischar(cfg.manufacturingTier) || ...
        ~ismember(cfg.manufacturingTier, {'standard', 'extreme'})
    error('RectangularFPC:InvalidConfigValue', ...
        'manufacturingTier must be ''standard'' or ''extreme''.');
end
overrides = cfg.manufacturingRuleOverrides;
if ~isstruct(overrides) || ~isscalar(overrides)
    error('RectangularFPC:InvalidConfigValue', ...
        'manufacturingRuleOverrides must be a scalar struct.');
end
allowed = ruleNames();
for field = fieldnames(overrides).'
    name = field{1};
    if ~ismember(name, allowed)
        error('RectangularFPC:UnknownManufacturingRule', ...
            'Unknown manufacturing rule override: %s.', name);
    end
    value = overrides.(name);
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
        error('RectangularFPC:InvalidConfigValue', ...
            'Manufacturing rule override %s must be a positive finite scalar.', name);
    end
    if strcmp(name, 'nearLimitFraction') && value > 1
        error('RectangularFPC:InvalidConfigValue', ...
            'nearLimitFraction must be greater than zero and at most one.');
    end
end
end

function profile = resolveProfile(cfg)
validateManufacturingConfig(cfg);
profile.name = cfg.manufacturingProfile;
profile.tier = cfg.manufacturingTier;
profile.checkedOn = '2026-08-28';
profile.sourceUrls = { ...
    'https://jlcpcb.com/capabilities/flex-pcb-capabilities/', ...
    'https://jlcpcb.com/help/article/fpc-design-clearance', ...
    ['https://jlcpcb.com/help/article/', ...
    'difference-and-tolerance-explanation-between-via-and-pad-holes']};
profile.rules = standardRules();
if strcmp(profile.tier, 'extreme')
    if cfg.layerCount == 2
        profile.rules.minViaDrillMm = 0.10;
        profile.rules.minViaPadMm = 0.30;
    elseif cfg.layerCount == 4
        profile.rules.minViaDrillMm = 0.15;
        profile.rules.minViaPadMm = 0.35;
    end
end
for field = fieldnames(cfg.manufacturingRuleOverrides).'
    profile.rules.(field{1}) = cfg.manufacturingRuleOverrides.(field{1});
end
end

function validateResultInput(result)
% check_result 输入契约：缺任一实测字段必须 fail closed，防止部分构造的
% 输入静默跳过资格检查（如缺 vias 时绕过 VIA_TECHNOLOGY 行）。
% minCopperSpacing 允许 NaN：线距检查被禁用（含 6/8 层未验证叠层）时
% validation 合法返回 NaN——2/4 层经 REQUIRED_VALIDATION_CHECKS 行 FAIL
% 拒绝导出；6/8 层按仓库政策保持可导出但仅 WARN、永不宣称 verified。
if ~isfield(result, 'minCopperSpacing') || ~isnumeric(result.minCopperSpacing) || ...
        ~isscalar(result.minCopperSpacing)
    error('RectangularFPC:ManufacturingInputContract', ...
        'check_result requires a measured minCopperSpacing (NaN when the clearance check is disabled).');
end
if ~isfield(result, 'minCopperToBoardMm') || ~isnumeric(result.minCopperToBoardMm) || ...
        ~isscalar(result.minCopperToBoardMm) || ~isfinite(result.minCopperToBoardMm)
    error('RectangularFPC:ManufacturingInputContract', ...
        'check_result requires a finite minCopperToBoardMm measured by validation.');
end
if ~isfield(result, 'vias') || ~isstruct(result.vias) || isempty(result.vias)
    error('RectangularFPC:ManufacturingInputContract', ...
        'check_result requires the measured vias array for via-technology qualification.');
end
if ~isfield(result, 'viaNonConnectedCopperPassed') || ...
        ~islogical(result.viaNonConnectedCopperPassed) || ...
        ~isscalar(result.viaNonConnectedCopperPassed)
    error('RectangularFPC:ManufacturingInputContract', ...
        'check_result requires the logical viaNonConnectedCopperPassed verdict.');
end
requiredMeasurements = { ...
    'minPadToUnrelatedTraceMm', ...
    'minViaToUnrelatedCopperMm', ...
    'minDrillToNonConnectedCopperMm', ...
    'minDrillToBoardMm'};
for fieldIndex = 1:numel(requiredMeasurements)
    fieldName = requiredMeasurements{fieldIndex};
    if ~isfield(result, fieldName) || ~isnumeric(result.(fieldName)) || ...
            ~isscalar(result.(fieldName)) || isnan(result.(fieldName))
        error('RectangularFPC:ManufacturingInputContract', ...
            'check_result requires measured %s.', fieldName);
    end
end
end

function names = ruleNames()
names = fieldnames(standardRules()).';
end

function rules = standardRules()
rules = struct( ...
    'minTraceWidthMm', 0.102, ...
    'minTraceSpacingMm', 0.102, ...
    'minCopperToBoardMm', 0.30, ...
    'minPadToTraceMm', 0.20, ...
    'minViaToTraceMm', 0.20, ...
    'minDrillToCopperMm', 0.176, ...
    'minDrillToBoardMm', 0.176, ...
    'minViaDrillMm', 0.30, ...
    'minViaPadMm', 0.55, ...
    'minViaPadDrillDifferenceMm', 0.20, ...
    'recommendedViaPadDrillDifferenceMm', 0.25, ...
    'nominalCopperThicknessMm', 0.035, ...
    'copperThicknessToleranceMm', 0.001, ...
    'nearLimitFraction', 0.20);
end

function report = buildReport(cfg, result)
profile = resolveProfile(cfg);
rules = profile.rules;
if isempty(fieldnames(result))
    % check_config：无最终几何结果，报告配置设计目标。
    measuredSpacing = cfg.traceSpacing;
    measuredCopperToBoard = cfg.edgeClearance;
    measuredPadToTrace = cfg.padToCopperClearance;
    measuredViaToTrace = min(cfg.viaToCopperClearance, ...
        cfg.outputViaToCopperClearance);
    hasVias = false;
else
    % check_result：输入契约 fail closed，缺任一实测字段即拒绝，
    % 防止部分构造的输入静默跳过资格检查（如缺 vias 时绕过 VIA_TECHNOLOGY）。
    validateResultInput(result);
    if isfinite(result.minCopperSpacing)
        measuredSpacing = result.minCopperSpacing;
    else
        % 线距检查被禁用时 validation 返回 NaN：回退到配置目标仅用于报告
        % 展示，资格判定由 REQUIRED_VALIDATION_CHECKS 行 fail closed。
        measuredSpacing = cfg.traceSpacing;
    end
    measuredCopperToBoard = result.minCopperToBoardMm;
    measuredPadToTrace = result.minPadToUnrelatedTraceMm;
    measuredViaToTrace = result.minViaToUnrelatedCopperMm;
    hasVias = true;
end
% COPPER_TO_BOARD 必须使用最终几何（含 PAD 与过孔焊环）的实测最小铜到板边距离；
% edgeClearance 只是布线设计目标，不能充当最终实测值（否则 PAD 铜边可绕过 DRC）。

rows = [ ...
    minimumRow('TRACE_WIDTH', cfg.traceWidth, rules.minTraceWidthMm, rules); ...
    minimumRow('TRACE_SPACING', measuredSpacing, rules.minTraceSpacingMm, rules); ...
    minimumRow('COPPER_TO_BOARD', measuredCopperToBoard, rules.minCopperToBoardMm, rules); ...
    minimumRow('PAD_TO_TRACE', measuredPadToTrace, rules.minPadToTraceMm, rules); ...
    minimumRow('VIA_TO_TRACE', measuredViaToTrace, rules.minViaToTraceMm, rules); ...
    minimumRow('VIA_DRILL', cfg.viaDrillDiameter, rules.minViaDrillMm, rules); ...
    minimumRow('VIA_PAD', cfg.viaPadDiameter, rules.minViaPadMm, rules); ...
    padDrillRow(cfg.viaPadDiameter - cfg.viaDrillDiameter, rules); ...
    copperThicknessRow(cfg.copperThickness, rules)];
if hasVias
    rows(end+1) = minimumRow('DRILL_TO_COPPER', ...
        result.minDrillToNonConnectedCopperMm, rules.minDrillToCopperMm, rules);
    rows(end+1) = minimumRow('DRILL_TO_BOARD', ...
        result.minDrillToBoardMm, rules.minDrillToBoardMm, rules);
    rows(end+1) = viaTechnologyRow(cfg, result, rules);
end
rows(end+1) = requiredValidationChecksRow(cfg);

supported = ismember(cfg.layerCount, [2, 4]);
if supported
    applicability = 'SUPPORTED';
else
    applicability = 'UNVERIFIED_LAYER_COUNT';
end
failures = {rows(strcmp({rows.status}, 'FAIL')).message};
warnings = {rows(strcmp({rows.status}, 'WARN')).message};
if strcmp(profile.tier, 'extreme')
    warnings = [{sprintf(['Extreme manufacturing tier selected for %d layers; ', ...
        'confirm capability and pricing with the fabricator before ordering.'], ...
        cfg.layerCount)}, warnings];
end
if ~supported
    warnings = [{sprintf(['Layer count %d is not listed by the selected ', ...
        'JLCPCB FPC profile; geometry may be exported but is not manufacturing verified.'], ...
        cfg.layerCount)}, warnings];
end

if ~isempty(failures)
    overallStatus = 'FAIL';
elseif ~supported
    overallStatus = 'UNVERIFIED';
elseif ~isempty(warnings)
    overallStatus = 'WARN';
else
    overallStatus = 'PASS';
end

report = struct( ...
    'profile', profile.name, ...
    'tier', profile.tier, ...
    'sourceCheckedOn', profile.checkedOn, ...
    'sourceUrls', {profile.sourceUrls}, ...
    'applicability', applicability, ...
    'status', overallStatus, ...
    'verified', supported && isempty(failures), ...
    'exportAllowed', isempty(failures), ...
    'passed', isempty(failures), ...
    'rules', rules, ...
    'checks', rows, ...
    'warnings', {warnings}, ...
    'failures', {failures});
end

function row = minimumRow(id, measured, limit, rules)
margin = measured - limit;
if margin < -1e-9
    status = 'FAIL';
    code = 'RULE_VIOLATION';
    message = sprintf('%s %.6f mm is below minimum %.6f mm.', id, measured, limit);
elseif margin <= rules.nearLimitFraction * limit + 1e-9
    status = 'WARN';
    code = 'NEAR_LIMIT';
    message = sprintf('%s %.6f mm is near minimum %.6f mm.', id, measured, limit);
else
    status = 'PASS';
    code = 'PASS';
    message = sprintf('%s %.6f mm passes minimum %.6f mm.', id, measured, limit);
end
row = makeRow(id, measured, limit, margin, status, code, message);
end

function row = padDrillRow(measured, rules)
limit = rules.minViaPadDrillDifferenceMm;
row = minimumRow('VIA_PAD_DRILL_DIFFERENCE', measured, limit, rules);
if strcmp(row.status, 'PASS') && ...
        measured < rules.recommendedViaPadDrillDifferenceMm - 1e-9
    row.status = 'WARN';
    row.code = 'BELOW_RECOMMENDED';
    row.message = sprintf(['VIA_PAD_DRILL_DIFFERENCE %.6f mm is below ', ...
        'recommended %.6f mm.'], measured, rules.recommendedViaPadDrillDifferenceMm);
end
end

function row = copperThicknessRow(measured, rules)
limit = rules.nominalCopperThicknessMm;
tolerance = rules.copperThicknessToleranceMm;
margin = tolerance - abs(measured - limit);
if margin < -1e-9
    status = 'FAIL';
    code = 'RULE_VIOLATION';
    message = sprintf('COPPER_THICKNESS %.6f mm is outside %.6f +/- %.6f mm.', ...
        measured, limit, tolerance);
else
    status = 'PASS';
    code = 'PASS';
    message = sprintf('COPPER_THICKNESS %.6f mm matches the 1 oz profile.', measured);
end
row = makeRow('COPPER_THICKNESS', measured, limit, margin, status, code, message);
end

function row = viaTechnologyRow(cfg, result, rules)
vias = result.vias;
allThrough = ~isempty(vias) && all(strcmp({vias.type}, 'through_via'));
antipadsComplete = true;
for viaIndex = 1:numel(vias)
    via = vias(viaIndex);
    if isempty(setdiff(1:cfg.layerCount, via.connectedLayers))
        continue
    end
    requiredDiameter = via.padDiameter + 2 * rules.minViaToTraceMm;
    if via.antipadDiameter < requiredDiameter - cfg.geometryTolerance
        antipadsComplete = false;
        break
    end
end
clearancePass = isfield(result, 'viaNonConnectedCopperPassed') && ...
    result.viaNonConnectedCopperPassed;
passed = allThrough && antipadsComplete && clearancePass;

if passed
    status = 'PASS';
    code = 'PASS';
    message = ['All interconnects use plated through holes with verified ', ...
        'non-connected-layer antipads and copper clearance.'];
elseif ismember(cfg.layerCount, [2, 4])
    status = 'FAIL';
    code = 'UNSUPPORTED_VIA_TECHNOLOGY';
    message = ['The supported-layer design requires plated through holes ', ...
        'with complete antipads and verified non-connected-layer clearance.'];
else
    status = 'WARN';
    code = 'UNVERIFIED_VIA_TECHNOLOGY';
    message = ['Via technology is not qualified for this unverified layer ', ...
        'count; confirm the stackup and drilling process with the fabricator.'];
end
row = makeRow('VIA_TECHNOLOGY', double(passed), 1, ...
    double(passed) - 1, status, code, message);
end

function row = requiredValidationChecksRow(cfg)
requiredNames = { ...
    'enableCopperClearanceCheck', ...
    'enablePadClearanceCheck', ...
    'enableViaClearanceCheck'};
enabled = cellfun(@(name) cfg.(name), requiredNames);
passed = all(enabled);
if passed
    status = 'PASS';
    code = 'PASS';
    message = 'All manufacturing-qualification clearance checks are enabled.';
elseif ismember(cfg.layerCount, [2, 4])
    % 2/4 层宣称"制造已验证"：禁用任一必需检查必须 FAIL 拒绝导出。
    status = 'FAIL';
    code = 'REQUIRED_CHECK_DISABLED';
    message = sprintf('Required manufacturing check(s) disabled: %s.', ...
        strjoin(requiredNames(~enabled), ', '));
else
    % 6/8 层本就 UNVERIFIED_LAYER_COUNT、按仓库政策可导出但不可宣称已验证；
    % 禁用检查只降级为 WARN 提示，不改变其可导出属性。
    status = 'WARN';
    code = 'UNVERIFIED_CHECK_CONFIGURATION';
    message = sprintf('Clearance check(s) disabled for unverified stackup: %s.', ...
        strjoin(requiredNames(~enabled), ', '));
end
row = makeRow('REQUIRED_VALIDATION_CHECKS', double(passed), 1, ...
    double(passed) - 1, status, code, message);
end

function row = makeRow(id, measured, limit, margin, status, code, message)
row = struct('id', id, 'measuredMm', measured, 'limitMm', limit, ...
    'marginMm', margin, 'status', status, 'code', code, 'message', message);
end
