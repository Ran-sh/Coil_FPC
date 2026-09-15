function tests = test_rectangular_fpc_export_contracts
% Formal artifact readback contracts that exercise existing output trees.
tests = functiontests(localfunctions);
end

function testCoordinateCsvManufacturingFieldsAreReadBack(testCase)
paths = makeFormalOutput(false);
cleanup = onCleanup(@() removeTree(paths.root));
filename = fullfile(paths.result.outputPath, 'reports', ...
    '01_pad_via_coordinates.csv');
baseline = readtable(filename, 'TextType', 'string');
viaRow = 2;
mutations = { ...
    @(data) setNumeric(data, 'pad_diameter_mm', viaRow, 0.1), ...
    @(data) setNumeric(data, 'drill_diameter_mm', viaRow, 0.1), ...
    @(data) setNumeric(data, 'annular_ring_mm', viaRow, 0.1), ...
    @(data) setNumeric(data, 'antipad_diameter_mm', viaRow, 0.1), ...
    @(data) setText(data, 'from_layer', viaRow, "L99"), ...
    @(data) setText(data, 'to_layer', viaRow, "L99"), ...
    @(data) setText(data, 'object_type', viaRow, "tampered_type"), ...
    @(data) setText(data, 'placement_region', viaRow, "tampered_region"), ...
    @(data) setText(data, 'placement_mode', viaRow, "tampered_mode"), ...
    @(data) setText(data, 'description', viaRow, "tampered_description")};

for mutationIndex = 1:numel(mutations)
    writetable(mutations{mutationIndex}(baseline), filename);
    verifyError(testCase, @() verifyExistingOutput(paths), ...
        'RectangularFPC:ExportReadbackFailed');
end
end

function testMalformedOrEmptySvgIsRejectedByProductionReadback(testCase)
paths = makeFormalOutput(true);
cleanup = onCleanup(@() removeTree(paths.root));
filename = fullfile(paths.result.outputPath, 'previews', ...
    '01_preview_full.svg');
baselineSvg = fileread(filename);
verifyFalse(testCase, contains(baselineSvg, '>data1</text>'), ...
    'Preview legend must not expose MATLAB auto-generated series names.');
invalidDocuments = { ...
    '<svg', ...
    '<svg xmlns="http://www.w3.org/2000/svg"></svg>', ...
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><path/></svg>', ...
    ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">', ...
     '<path d="M0 0 L0 0"/></svg>'], ...
    ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="garbage">', ...
     '<path d="M0 0 L1 1"/></svg>'], ...
    ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">', ...
     '<script>alert(1)</script><path d="M0 0 L1 1"/></svg>'], ...
    ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">', ...
     '<foreignObject/><path d="M0 0 L1 1"/></svg>'], ...
    ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">', ...
     '<path onload="alert(1)" d="M0 0 L1 1"/></svg>'], ...
    ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">', ...
     '<a href="javascript:alert(1)"><path d="M0 0 L1 1"/></a></svg>']};
for documentIndex = 1:numel(invalidDocuments)
    fid = fopen(filename, 'w');
    fileCleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', invalidDocuments{documentIndex});
    clear fileCleanup;
    verifyError(testCase, @() verifyReadableOutput(paths), ...
        'RectangularFPC:ExportReadbackFailed');
end
end

function testGenerationStatusManufacturingFieldsAreReadBack(testCase)
paths = makeFormalOutput(false);
cleanup = onCleanup(@() removeTree(paths.root));
filename = fullfile(paths.result.outputPath, 'generation_status.txt');
baseline = fileread(filename);
expected = { ...
    paths.result.manufacturing.profile, ...
    paths.result.manufacturing.tier, ...
    paths.result.manufacturing.status, ...
    paths.result.manufacturing.applicability, ...
    sprintf('%d', paths.result.manufacturing.verified)};
fields = { ...
    'ManufacturingProfile', ...
    'ManufacturingTier', ...
    'ManufacturingStatus', ...
    'ManufacturingApplicability', ...
    'ManufacturingVerified'};
replacements = {'tampered', 'tampered', 'FAIL', 'CUSTOM_RULES', '0'};
for fieldIndex = 1:numel(fields)
    originalLine = sprintf('%s: %s', fields{fieldIndex}, expected{fieldIndex});
    replacementLine = sprintf('%s: %s', ...
        fields{fieldIndex}, replacements{fieldIndex});
    tampered = strrep(baseline, originalLine, replacementLine);
    assertNotEqual(testCase, tampered, baseline);
    writeTextFile(filename, tampered);
    verifyError(testCase, @() verifyExistingOutput(paths), ...
        'RectangularFPC:ExportReadbackFailed');
end
writeTextFile(filename, sprintf('%sManufacturingVerified: 0\n', baseline));
verifyError(testCase, @() verifyExistingOutput(paths), ...
    'RectangularFPC:ExportReadbackFailed');
end

function testCustomRulesKeepSupportedThroughViaFabricationNotes(testCase)
paths = makeFormalOutput(false, struct( ...
    'manufacturingRuleOverrides', struct('minTraceWidthMm', 0.10)));
cleanup = onCleanup(@() removeTree(paths.root));
verifyEqual(testCase, paths.result.manufacturing.applicability, ...
    'CUSTOM_RULES');
verifyFalse(testCase, paths.result.manufacturing.verified);
notes = fileread(fullfile(paths.result.outputPath, 'reports', ...
    '07_fabrication_notes.txt'));
verifyTrue(testCase, contains(notes, ...
    'All vias are plated through holes through the complete stack.'));
verifyFalse(testCase, contains(notes, ...
    'series interconnects use an unverified adjacent-layer via model'));
verifyTrue(testCase, contains(notes, ...
    'Requested profile: jlc_fpc_1oz'));
verifyTrue(testCase, contains(notes, 'Base profile: jlc_fpc_1oz'));
verifyTrue(testCase, contains(notes, ...
    'Rule classification: CUSTOM_RELAXED'));
baseRuleLine = sprintf('BaseRule.minTraceWidthMm: %.17g', ...
    paths.result.manufacturing.baseRules.minTraceWidthMm);
effectiveRuleLine = sprintf('EffectiveRule.minTraceWidthMm: %.17g', ...
    paths.result.manufacturing.rules.minTraceWidthMm);
overrideLine = sprintf('RuleOverride.minTraceWidthMm: %.17g', ...
    paths.result.manufacturing.ruleOverrides.minTraceWidthMm);
verifyTrue(testCase, contains(notes, baseRuleLine));
verifyTrue(testCase, contains(notes, effectiveRuleLine));
verifyTrue(testCase, contains(notes, overrideLine));
tampered = strrep(notes, baseRuleLine, ...
    'BaseRule.minTraceWidthMm: 0');
writeTextFile(fullfile(paths.result.outputPath, 'reports', ...
    '07_fabrication_notes.txt'), tampered);
verifyError(testCase, @() verifyReadableOutput(paths), ...
    'RectangularFPC:ExportReadbackFailed');
end

function testTwoLayerNotApplicableManufacturingRowRoundTrips(testCase)
paths = makeFormalOutput(false, struct('layerCount', 2));
cleanup = onCleanup(@() removeTree(paths.root));
data = readtable(fullfile(paths.result.outputPath, 'reports', ...
    '06_manufacturing_check.csv'), 'TextType', 'string');
row = data(data.check_id == "DRILL_TO_COPPER", :);
verifyEqual(testCase, height(row), 1);
verifyEqual(testCase, row.status, "NOT_APPLICABLE");
verifyTrue(testCase, isnan(row.measured_mm));
verifyEqual(testCase, row.code, "NOT_APPLICABLE");
end

function testCoordinateCsvPreservesLegalSubMillimeterPrecision(testCase)
paths = makeFormalOutput(false, struct('padDiameter', 1.5004));
cleanup = onCleanup(@() removeTree(paths.root));
data = readtable(fullfile(paths.result.outputPath, 'reports', ...
    '01_pad_via_coordinates.csv'), 'TextType', 'string');
padRows = data.object_type == "pad";
verifyEqual(testCase, data.pad_diameter_mm(padRows), ...
    repmat(1.5004, nnz(padRows), 1), 'AbsTol', 1e-12);
end

function testManufacturingCsvPreservesLargeMagnitudePrecision(testCase)
paths = makeScaledFormalOutput(100);
cleanup = onCleanup(@() removeTree(paths.root));
data = readtable(fullfile(paths.result.outputPath, 'reports', ...
    '06_manufacturing_check.csv'), 'TextType', 'string');
row = data(data.check_id == "TRACE_WIDTH", :);
verifyEqual(testCase, height(row), 1);
verifyEqual(testCase, row.measured_mm, 20.00000004, 'AbsTol', 1e-12);
end

function testRelativeOutputRootPublishesCanonicalOutputPaths(testCase)
workspaceRoot = tempname;
mkdir(workspaceRoot);
originalFolder = pwd;
cleanup = onCleanup(@() cleanupRelativeWorkspace( ...
    originalFolder, workspaceRoot));
cd(workspaceRoot);
result = rectangular_fpc_main(struct( ...
    'outputRoot', 'relative_output', ...
    'designName', 'relative_output_contract', ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));
expectedRoot = char(java.io.File(fullfile( ...
    workspaceRoot, 'relative_output')).getCanonicalPath());
verifyTrue(testCase, startsWith(result.outputPath, ...
    [expectedRoot filesep]));
verifyTrue(testCase, isfolder(result.outputPath));
verifyTrue(testCase, isfile(result.fileManifest));
end

function testFabricationNotesPreserveActionableTraceWidth(testCase)
paths = makeFormalOutput(false, struct('traceWidth', 0.2004));
cleanup = onCleanup(@() removeTree(paths.root));
notes = fileread(fullfile(paths.result.outputPath, 'reports', ...
    '07_fabrication_notes.txt'));
summary = fileread(fullfile(paths.result.outputPath, 'reports', ...
    '03_design_summary.txt'));
verifyTrue(testCase, contains(notes, 'assign 0.2004 mm trace width.'));
verifyTrue(testCase, contains(notes, ...
    'Trace width / spacing: 0.2004 / 0.15 mm'));
verifyTrue(testCase, contains(summary, ...
    'Trace width / spacing: 0.2004 / 0.15 mm'));
end

function testComsolSolidDxfSeparatesCoilFromTerminalCopper(testCase)
paths = makeFormalOutput(false, struct('layerCount', 2));
cleanup = onCleanup(@() removeTree(paths.root));
result = paths.result;
cfg = paths.cfg;
for layer = 1:result.layerCount
    coilRings = RectangularFpc.Geometry.Copper_Outline('coil_rings', ...
        result.layers(layer).spiralXY, cfg.traceWidth);
    condRings = RectangularFpc.Geometry.Copper_Outline('conductor_rings', ...
        result.layerPaths{layer}, cfg.traceWidth);
    verifyEqual(testCase, numel(coilRings), 1);
    verifyEqual(testCase, numel(condRings), numel(result.layerPaths{layer}));

    coilFile = result.layers(layer).solidCopperDxfFile;
    condFile = result.layers(layer).terminalSolidDxfFile;
    verifyTrue(testCase, isfile(coilFile));
    verifyTrue(testCase, isfile(condFile));
    verifyRingEntities(testCase, coilFile, ...
        sprintf('COPPER_SOLID_L%d', layer), 1);
    verifyRingEntities(testCase, condFile, ...
        sprintf('COPPER_SOLID_TERMINALS_L%d', layer), numel(condRings));

    % 本层导体 = 螺旋 + 引线，面积必须严格大于"只有线圈"的实体。
    coilArea = RectangularFpc.Geometry.Copper_Outline('area', coilRings{1});
    chainArea = RectangularFpc.Geometry.Copper_Outline('area', condRings{1});
    verifyGreaterThan(testCase, chainArea, coilArea);

    % 端子铜只出现在 with_terminals 变体里：纯螺旋不接触任何焊盘或过孔中心，
    % 而导体实体必须精确落在线端节点上（端帽过节点）。
    for padIndex = 1:numel(result.pads)
        verifyGreaterThan(testCase, ringDistance(coilRings{1}, ...
            result.pads(padIndex).xy), 0);
    end
    for viaIndex = 1:numel(result.vias)
        verifyGreaterThan(testCase, ringDistance(coilRings{1}, ...
            result.vias(viaIndex).xy), 0);
    end
    if layer == 1
        % L1 有两个连通体：主链（从 PAD_A 出发）与 VOUT → PAD_B 回程。
        verifyEqual(testCase, numel(condRings), 2);
        verifyLessThan(testCase, ringDistance(condRings{1}, ...
            result.pads(1).xy), 1e-9);
        verifyLessThan(testCase, ringDistance(condRings{2}, ...
            result.pads(2).xy), 1e-9);
        verifyLessThan(testCase, ringDistance(condRings{2}, ...
            result.vias(end).xy), 1e-9);
    else
        verifyEqual(testCase, numel(condRings), 1);
    end
end
end

function testComsolSolidDxfTamperingIsRejected(testCase)
paths = makeFormalOutput(false, struct('layerCount', 2));
cleanup = onCleanup(@() removeTree(paths.root));
filename = paths.result.layers(1).solidCopperDxfFile;
baseline = fileread(filename);

mutations = { ...
    @(text) strrep(text, 'COPPER_SOLID_L1', 'COPPER_SOLID_L2'), ...
    @(text) regexprep(text, '(?m)^90\r?\n(\d+)', ...
        '90\n${num2str(str2double($1) + 1)}', 'once'), ...
    @(text) regexprep(text, '(?m)^0\r?\nLWPOLYLINE', '0\nCIRCLE', 'once'), ...
    @flipFirstEntityClosedFlag, ...
    @(text) regexprep(text, '(?m)^10\r?\n[-\d.]+', '10\n0.000000000', 'once')};
for mutationIndex = 1:numel(mutations)
    tampered = mutations{mutationIndex}(baseline);
    assertNotEqual(testCase, tampered, baseline);
    rewriteFile(filename, tampered);
    verifyError(testCase, @() verifyReadableOutput(paths), ...
        'RectangularFPC:ExportReadbackFailed');
    rewriteFile(filename, baseline);
end

verifyReadableOutput(paths);
end

function testComsolSolidManifestRolesAreDeclared(testCase)
paths = makeFormalOutput(false, struct('layerCount', 2));
cleanup = onCleanup(@() removeTree(paths.root));
manifest = readtable(fullfile(paths.result.outputPath, 'reports', ...
    '08_file_manifest.csv'), 'TextType', 'string');
solid = manifest(contains(manifest.relativePath, '_copper_solid_'), :);
verifyEqual(testCase, height(solid), 2 * paths.result.layerCount);
terminals = solid(contains(solid.relativePath, '_with_terminals_'), :);
verifyEqual(testCase, height(terminals), paths.result.layerCount);
verifyTrue(testCase, all(terminals.role == "copper_solid_with_terminals"));
coilOnly = solid(~contains(solid.relativePath, '_with_terminals_'), :);
verifyEqual(testCase, height(coilOnly), paths.result.layerCount);
verifyTrue(testCase, all(coilOnly.role == "copper_solid"));
end

function verifyRingEntities(testCase, filename, layerName, expectedCount)
% 独立读回：COMSOL 实体文件必须只含闭合、无宽度的 LWPOLYLINE，每个环一个
% 实体，首顶点显式重复为末顶点。
entities = readLwPolylines(filename);
verifyEqual(testCase, numel(entities), expectedCount);
verifyEqual(testCase, countDxfType(filename, 'CIRCLE'), 0, ...
    'COMSOL solid files must not carry pads, vias, drills, or antipads.');
for entityIndex = 1:numel(entities)
    entity = entities(entityIndex);
    verifyEqual(testCase, entity.layer, layerName);
    verifyEqual(testCase, entity.closed, 1);
    verifyTrue(testCase, isnan(entity.width), ...
        'COMSOL solid rings must not carry a group-43 width.');
    verifyGreaterThanOrEqual(testCase, size(entity.xy, 1), 4);
    verifyEqual(testCase, entity.xy(1, :), entity.xy(end, :), ...
        'AbsTol', 1e-9);
end
end

function count = countDxfType(filename, entityName)
content = fileread(filename);
count = numel(regexp(content, ...
    ['(?m)^' regexptranslate('escape', entityName) '\r?$'], 'match'));
end

function entities = readLwPolylines(filename)
content = fileread(filename);
lines = regexp(strtrim(content), '\r?\n', 'split').';
codes = str2double(lines(1:2:end));
values = lines(2:2:end);
starts = find(codes == 0 & strcmp(values, 'LWPOLYLINE'));
template = struct('layer', '', 'closed', NaN, 'width', NaN, ...
    'xy', zeros(0, 2));
entities = repmat(template, numel(starts), 1);
for entityIndex = 1:numel(starts)
    first = starts(entityIndex);
    nextStart = find(codes(first + 1:end) == 0, 1);
    if isempty(nextStart)
        last = numel(codes);
    else
        last = first + nextStart - 1;
    end
    index = first:last;
    layerIndex = index(find(codes(index) == 8, 1));
    closedIndex = index(find(codes(index) == 70, 1));
    widthIndex = index(find(codes(index) == 43, 1));
    xIndex = index(codes(index) == 10);
    yIndex = index(codes(index) == 20);
    entities(entityIndex).layer = values{layerIndex};
    entities(entityIndex).closed = str2double(values{closedIndex});
    if ~isempty(widthIndex)
        entities(entityIndex).width = str2double(values{widthIndex});
    end
    entities(entityIndex).xy = ...
        [str2double(values(xIndex)), str2double(values(yIndex))];
end
end

function tampered = flipFirstEntityClosedFlag(text)
% 只翻第一个实体自己的 group-70（闭合法）：文件头 TABLES 段也有 70，纯正则
% 替换会打错地方，所以按解析出的行号定位。
lines = regexp(strtrim(text), '\r?\n', 'split').';
codes = str2double(lines(1:2:end));
values = lines(2:2:end);
starts = find(codes == 0 & strcmp(values, 'LWPOLYLINE'));
closedOffset = find(codes(starts(1):end) == 70, 1) + starts(1) - 1;
values{closedOffset} = '0';
lines(2:2:end) = values;
tampered = strjoin(lines, '\n');
end

function distance = ringDistance(ring, point)
distance = RectangularFpc.Geometry.Path_Geometry( ...
    'minimum_distance_point_polyline', point, ring);
end

function rewriteFile(filename, content)
fid = fopen(filename, 'w');
assert(fid ~= -1, 'Unable to rewrite export-contract fixture.');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', content);
clear cleanup;
end

function paths = makeFormalOutput(enablePreview, extraOverrides)
if nargin < 2
    extraOverrides = struct();
end
paths.root = tempname;
outputRoot = fullfile(paths.root, 'output');
overrides = struct( ...
    'outputRoot', outputRoot, ...
    'designName', 'export_contract', ...
    'turnsPerLayer', 1, ...
    'enablePreview', enablePreview, ...
    'enableFigure', false);
names = fieldnames(extraOverrides);
for nameIndex = 1:numel(names)
    overrides.(names{nameIndex}) = extraOverrides.(names{nameIndex});
end
paths.result = rectangular_fpc_main(overrides);
paths.cfg = paths.result.config;
paths.cfg.designName = sprintf('%s_%s', ...
    paths.result.logicalDesignName, paths.result.runTimestamp);
end

function paths = makeScaledFormalOutput(scale)
cfg = rectangular_fpc_default_config();
lengthFields = { ...
    'plateLength', 'plateWidth', 'plateCornerRadius', ...
    'tabLength', 'tabWidth', 'tabOuterCornerRadius', ...
    'tabTransitionRadius', 'tabEdgeMargin', ...
    'traceWidth', 'traceSpacing', 'pitchMargin', 'edgeClearance', ...
    'minInnerWidth', 'minInnerLength', 'minSpiralCornerRadius', ...
    'leadYOffset', 'leadBendRadius', 'padTipInset', 'padDiameter', ...
    'padTipMargin', 'leadTabClearance', 'padToPadClearance', ...
    'padToCopperClearance', 'viaDrillDiameter', 'viaPadDiameter', ...
    'viaToCopperClearance', 'viaToBoardClearance', ...
    'viaToViaClearance', 'viaToPadClearance', ...
    'viaLandingLeadLength', 'viaLandingClearance', ...
    'viaInnerBendRadius', 'viaOuterLandingLeadLength', ...
    'viaOuterLandingClearance', 'viaOuterBendRadius', ...
    'innerViaPitch', 'innerViaRowOffsetY', ...
    'outerViaPitch', 'outerViaRowOffsetY', ...
    'viaKeepoutMargin', 'autoViaGridStep', 'outputViaTipInset', ...
    'outputViaAntiPadDiameter', 'outputViaToCopperClearance', ...
    'outputViaToBoardClearance'};
for fieldIndex = 1:numel(lengthFields)
    name = lengthFields{fieldIndex};
    cfg.(name) = cfg.(name) * scale;
end
cfg.traceWidth = 20.00000004;
cfg.turnsPerLayer = 1;
cfg.enablePreview = false;
cfg.enableFigure = false;
paths.root = tempname;
cfg.outputRoot = fullfile(paths.root, 'output');
cfg.designName = 'mfg_precision_contract';
paths.result = rectangular_fpc_main(cfg);
paths.cfg = paths.result.config;
paths.cfg.designName = sprintf('%s_%s', ...
    paths.result.logicalDesignName, paths.result.runTimestamp);
end

function verifyExistingOutput(paths)
RectangularFpc.Export.Export_All('verify_output', paths.cfg, paths.result, ...
    paths.result.outputPath);
end

function verifyReadableOutput(paths)
RectangularFpc.Export.Export_Verification('readable_artifact_set', ...
    paths.result.outputPath, paths.cfg, paths.result);
end

function data = setNumeric(data, name, row, delta)
data.(name)(row) = data.(name)(row) + delta;
end

function data = setText(data, name, row, value)
data.(name)(row) = value;
end

function writeTextFile(filename, content)
fid = fopen(filename, 'w', 'n', 'UTF-8');
assert(fid ~= -1, 'Unable to open export-contract fixture.');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', content);
clear cleanup;
end

function removeTree(root)
if isfolder(root)
    rmdir(root, 's');
end
end

function cleanupRelativeWorkspace(originalFolder, workspaceRoot)
cd(originalFolder);
removeTree(workspaceRoot);
end
