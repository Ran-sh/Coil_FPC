function varargout = circular_fpc_manufacturing(operation, varargin)
% CIRCULAR_FPC_MANUFACTURING 制造档案与制造检查的唯一所有者（ADR-1）。
%
%   profile = CIRCULAR_FPC_MANUFACTURING('resolve', cfg)
%   report  = CIRCULAR_FPC_MANUFACTURING('check_config', cfg)
%   report  = CIRCULAR_FPC_MANUFACTURING('check_result', cfg, validation)
%
%   规则数值只允许出现在本文件（ADR-3/4）；其余模块通过本入口消费解析后的
%   规则与检查行，不再持有硬编码 DRC 常量。
switch operation
    case 'resolve'
        varargout{1} = resolveProfile(varargin{1});
    case 'check_config'
        varargout{1} = checkConfig(varargin{1});
    case 'check_result'
        varargout{1} = checkResult(varargin{1}, varargin{2});
    otherwise
        error('CircularFPC:InvalidOperation', 'Unknown manufacturing operation: %s', operation);
end
end

function p = resolveProfile(cfg)
% 解析制造档案：标准档 -> extreme 层降档 -> 规则覆盖；sources 标记覆盖来源。
validateManufacturingConfig(cfg);
p.profile = cfg.manufacturingProfile;
p.tier = cfg.manufacturingTier;
p.standardRules = standardRules();      % 标准档基线，始终保留（用于 HIGH_COST_EXTREME 判定）
p.rules = p.standardRules;
p.sources = struct();
for f = fieldnames(p.standardRules).'
    p.sources.(f{1}) = 'profile';
end
if strcmp(p.tier, 'extreme')
    if cfg.boardLayerCount == 2
        p.rules.minViaDrill2LayerMm = 0.10;
        p.rules.minViaPad2LayerMm = 0.30;
    else
        p.rules.minViaDrill4LayerMm = 0.15;
        p.rules.minViaPad4LayerMm = 0.35;
    end
end
ov = cfg.manufacturingRuleOverrides;
for f = fieldnames(ov).'
    p.rules.(f{1}) = ov.(f{1});
    p.sources.(f{1}) = 'override';
end
end

function validateManufacturingConfig(cfg)
% 只支持 jlc_fpc_1oz / standard|extreme；overrides 必须是标量 struct，
% 字段限 ADR-3 名单，值为正有限标量（nearLimitFraction 另需 <= 1）。
if ~ischar(cfg.manufacturingProfile) || ~strcmp(cfg.manufacturingProfile, 'jlc_fpc_1oz')
    error('CircularFPC:InvalidConfig', 'manufacturingProfile must be ''jlc_fpc_1oz''.');
end
if ~ischar(cfg.manufacturingTier) || ~ismember(cfg.manufacturingTier, {'standard', 'extreme'})
    error('CircularFPC:InvalidConfig', 'manufacturingTier must be ''standard'' or ''extreme''.');
end
ov = cfg.manufacturingRuleOverrides;
if ~isstruct(ov) || ~isscalar(ov)
    error('CircularFPC:InvalidConfig', 'manufacturingRuleOverrides must be a scalar struct.');
end
allowed = ruleNames();
for f = fieldnames(ov).'
    if ~ismember(f{1}, allowed)
        error('CircularFPC:UnknownManufacturingRule', 'Unknown manufacturing rule override: %s', f{1});
    end
    v = ov.(f{1});
    if ~isscalar(v) || ~isnumeric(v) || ~isfinite(v) || v <= 0
        error('CircularFPC:InvalidConfig', 'Manufacturing rule override %s must be a positive finite scalar.', f{1});
    end
    if strcmp(f{1}, 'nearLimitFraction') && v > 1
        error('CircularFPC:InvalidConfig', 'nearLimitFraction must be > 0 and <= 1.');
    end
end
end

function names = ruleNames()
names = {'minTraceWidthMm', 'minTraceSpacingMm', 'minCopperToBoardMm', ...
    'minCopperToSlotMm', 'minTerminalClearanceMm', 'minViaCoilSpacingMm', ...
    'minDrillToCopperMm', 'minViaDrill2LayerMm', 'minViaPad2LayerMm', ...
    'minViaDrill4LayerMm', 'minViaPad4LayerMm', 'minViaPadDrillDifferenceMm', ...
    'recommendedViaPadDrillDifferenceMm', 'nominalCopperThicknessMm', ...
    'copperThicknessToleranceMm', 'nearLimitFraction'};
end

function s = standardRules()
% ADR-4 标准档数值（mm）：2L/4L 过孔均为 .30/.55；extreme 层降档在 resolveProfile 处理。
s = struct( ...
    'minTraceWidthMm', 0.102, ...
    'minTraceSpacingMm', 0.102, ...
    'minCopperToBoardMm', 0.30, ...
    'minCopperToSlotMm', 0.30, ...
    'minTerminalClearanceMm', 0.152, ...
    'minViaCoilSpacingMm', 0.152, ...
    'minDrillToCopperMm', 0.176, ...
    'minViaDrill2LayerMm', 0.30, ...
    'minViaPad2LayerMm', 0.55, ...
    'minViaDrill4LayerMm', 0.30, ...
    'minViaPad4LayerMm', 0.55, ...
    'minViaPadDrillDifferenceMm', 0.20, ...
    'recommendedViaPadDrillDifferenceMm', 0.25, ...
    'nominalCopperThicknessMm', 0.035, ...
    'copperThicknessToleranceMm', 0.001, ...
    'nearLimitFraction', 0.20);
end

function report = checkConfig(cfg)
p = resolveProfile(cfg);
rows = buildChecks(cfg, p, struct());
report = buildReport(p, rows);
end

function report = checkResult(cfg, validation)
% 结果二次审查：TRACE_SPACING/COPPER_TO_BOARD/COPPER_TO_SLOT/
% TERMINAL_CLEARANCE/VIA_COIL_SPACING 用实际几何指标替换配置值，其余仍来自 cfg。
p = resolveProfile(cfg);
measuredMap = struct( ...
    'TRACE_SPACING', validation.minCopperSpacingMm, ...
    'COPPER_TO_BOARD', validation.minCopperToBoardMm, ...
    'COPPER_TO_SLOT', validation.minCopperToSlotsMm, ...
    'TERMINAL_CLEARANCE', validation.minPadViaClearanceMm, ...
    'VIA_COIL_SPACING', validation.minViaCoilSpacingMm);
rows = buildChecks(cfg, p, measuredMap);
report = buildReport(p, rows);
end

function report = buildReport(p, rows)
report.profile = p.profile;
report.tier = p.tier;
report.rules = p.rules;
report.checks = rows;
report.warnings = {rows(strcmp({rows.status}, 'WARN')).message};
report.failures = {rows(strcmp({rows.status}, 'FAIL')).message};
report.passed = isempty(report.failures);
end

function rows = buildChecks(cfg, p, measuredMap)
% 构造全部 11 个检查行并分类。measuredMap 覆盖实际几何测量值（check_result）。
r = p.rules;
s = p.sources;
if cfg.boardLayerCount == 2
    drillRule = 'minViaDrill2LayerMm';
    padRule = 'minViaPad2LayerMm';
    drillStd = p.standardRules.minViaDrill2LayerMm;
    padStd = p.standardRules.minViaPad2LayerMm;
else
    drillRule = 'minViaDrill4LayerMm';
    padRule = 'minViaPad4LayerMm';
    drillStd = p.standardRules.minViaDrill4LayerMm;
    padStd = p.standardRules.minViaPad4LayerMm;
end
m = struct();
m.TRACE_WIDTH = cfg.traceWidth;
m.TRACE_SPACING = cfg.traceSpacing;
m.COPPER_TO_BOARD = cfg.edgeClearance;
m.COPPER_TO_SLOT = cfg.edgeClearance;
m.TERMINAL_CLEARANCE = cfg.terminalClearance;
m.VIA_COIL_SPACING = cfg.viaCoilSpacing;
m.DRILL_TO_COPPER = cfg.viaCoilSpacing + (cfg.viaPadDiameter - cfg.viaDrillDiameter) / 2;
m.VIA_DRILL = cfg.viaDrillDiameter;
m.VIA_PAD = cfg.viaPadDiameter;
m.VIA_PAD_DRILL_DIFFERENCE = cfg.viaPadDiameter - cfg.viaDrillDiameter;
m.COPPER_THICKNESS = cfg.copperThickness;
for f = fieldnames(measuredMap).'
    if isfield(m, f{1})
        m.(f{1}) = measuredMap.(f{1});
    end
end
rows = struct('id', {}, 'measuredMm', {}, 'limitMm', {}, 'source', {}, ...
    'kind', {}, 'stdLimitMm', {}, 'recommendedMm', {}, 'toleranceMm', {});
rows(end + 1) = rawRow('TRACE_WIDTH', m.TRACE_WIDTH, r.minTraceWidthMm, s.minTraceWidthMm, 'min', NaN, NaN, NaN);
rows(end + 1) = rawRow('TRACE_SPACING', m.TRACE_SPACING, r.minTraceSpacingMm, s.minTraceSpacingMm, 'min', NaN, NaN, NaN);
rows(end + 1) = rawRow('COPPER_TO_BOARD', m.COPPER_TO_BOARD, r.minCopperToBoardMm, s.minCopperToBoardMm, 'min', NaN, NaN, NaN);
rows(end + 1) = rawRow('COPPER_TO_SLOT', m.COPPER_TO_SLOT, r.minCopperToSlotMm, s.minCopperToSlotMm, 'min', NaN, NaN, NaN);
rows(end + 1) = rawRow('TERMINAL_CLEARANCE', m.TERMINAL_CLEARANCE, r.minTerminalClearanceMm, s.minTerminalClearanceMm, 'min', NaN, NaN, NaN);
rows(end + 1) = rawRow('VIA_COIL_SPACING', m.VIA_COIL_SPACING, r.minViaCoilSpacingMm, s.minViaCoilSpacingMm, 'min', NaN, NaN, NaN);
rows(end + 1) = rawRow('DRILL_TO_COPPER', m.DRILL_TO_COPPER, r.minDrillToCopperMm, s.minDrillToCopperMm, 'min', NaN, NaN, NaN);
rows(end + 1) = rawRow('VIA_DRILL', m.VIA_DRILL, r.(drillRule), s.(drillRule), 'min', drillStd, NaN, NaN);
rows(end + 1) = rawRow('VIA_PAD', m.VIA_PAD, r.(padRule), s.(padRule), 'min', padStd, NaN, NaN);
rows(end + 1) = rawRow('VIA_PAD_DRILL_DIFFERENCE', m.VIA_PAD_DRILL_DIFFERENCE, r.minViaPadDrillDifferenceMm, ...
    s.minViaPadDrillDifferenceMm, 'padDrill', NaN, r.recommendedViaPadDrillDifferenceMm, NaN);
rows(end + 1) = rawRow('COPPER_THICKNESS', m.COPPER_THICKNESS, r.nominalCopperThicknessMm, ...
    s.nominalCopperThicknessMm, 'copper', NaN, NaN, r.copperThicknessToleranceMm);
rows = classifyChecks(rows, p);
end

function row = rawRow(id, measured, limit, source, kind, stdLimit, recommended, tolerance)
row = struct('id', id, 'measuredMm', measured, 'limitMm', limit, 'source', source, ...
    'kind', kind, 'stdLimitMm', stdLimit, 'recommendedMm', recommended, 'toleranceMm', tolerance);
end

function rows = classifyChecks(rows, p)
out = struct('id', {}, 'measuredMm', {}, 'limitMm', {}, 'marginMm', {}, ...
    'status', {}, 'source', {}, 'code', {}, 'message', {});
for k = 1:numel(rows)
    out(end + 1) = classifyRow(rows(k), p); %#ok<AGROW>
end
rows = out;
end

function rowOut = classifyRow(row, p)
id = row.id;
measured = row.measuredMm;
limit = row.limitMm;
switch row.kind
    case 'copper'
        tol = row.toleranceMm;
        margin = tol - abs(measured - limit);
        if abs(measured - limit) <= tol + 1e-9
            rowOut = makeRow(id, measured, limit, margin, 'PASS', row.source, 'PASS', ...
                sprintf('%s measured %.6f mm matches nominal %.6f mm +/- %.6f mm.', id, measured, limit, tol));
        else
            rowOut = makeRow(id, measured, limit, margin, 'FAIL', row.source, 'RULE_VIOLATION', ...
                sprintf('%s measured %.6f mm exceeds tolerance +/- %.6f mm around nominal %.6f mm.', id, measured, tol, limit));
        end
    case 'padDrill'
        margin = measured - limit;
        if measured < limit - 1e-9
            rowOut = makeRow(id, measured, limit, margin, 'FAIL', row.source, 'RULE_VIOLATION', ...
                sprintf('%s measured %.6f mm is below minimum %.6f mm.', id, measured, limit));
        elseif measured < row.recommendedMm - 1e-9
            rowOut = makeRow(id, measured, limit, margin, 'WARN', row.source, 'BELOW_RECOMMENDED', ...
                sprintf('%s measured %.6f mm is below recommended %.6f mm.', id, measured, row.recommendedMm));
        elseif margin <= p.rules.nearLimitFraction * limit + 1e-9
            rowOut = makeRow(id, measured, limit, margin, 'WARN', row.source, 'NEAR_LIMIT', ...
                sprintf('%s measured %.6f mm is within %.0f%% of minimum %.6f mm.', id, measured, 100 * p.rules.nearLimitFraction, limit));
        else
            rowOut = makeRow(id, measured, limit, margin, 'PASS', row.source, 'PASS', ...
                sprintf('%s measured %.6f mm passes minimum %.6f mm.', id, measured, limit));
        end
    otherwise
        margin = measured - limit;
        if measured < limit - 1e-9
            rowOut = makeRow(id, measured, limit, margin, 'FAIL', row.source, 'RULE_VIOLATION', ...
                sprintf('%s measured %.6f mm is below limit %.6f mm.', id, measured, limit));
        elseif strcmp(p.tier, 'extreme') && (strcmp(id, 'VIA_DRILL') || strcmp(id, 'VIA_PAD')) && measured < row.stdLimitMm - 1e-9
            rowOut = makeRow(id, measured, limit, margin, 'WARN', row.source, 'HIGH_COST_EXTREME', ...
                sprintf('%s measured %.6f mm is below standard limit %.6f mm (HIGH_COST_EXTREME).', id, measured, row.stdLimitMm));
        elseif margin <= p.rules.nearLimitFraction * limit + 1e-9
            rowOut = makeRow(id, measured, limit, margin, 'WARN', row.source, 'NEAR_LIMIT', ...
                sprintf('%s measured %.6f mm is within %.0f%% of limit %.6f mm.', id, measured, 100 * p.rules.nearLimitFraction, limit));
        else
            rowOut = makeRow(id, measured, limit, margin, 'PASS', row.source, 'PASS', ...
                sprintf('%s measured %.6f mm passes limit %.6f mm.', id, measured, limit));
        end
end
end

function row = makeRow(id, measured, limit, margin, status, source, code, message)
row = struct('id', id, 'measuredMm', measured, 'limitMm', limit, 'marginMm', margin, ...
    'status', status, 'source', source, 'code', code, 'message', message);
end
