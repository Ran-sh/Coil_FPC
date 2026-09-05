function rectangular_fpc_export_verification(operation, varargin)
%RECTANGULAR_FPC_EXPORT_VERIFICATION Read back the complete staged artifact set.

switch operation
    case 'readable_artifact_set'
        verifyReadableArtifactSet(varargin{:});
    otherwise
        error('RectangularFPC:UnknownExportOperation', ...
            'Unknown export verification operation: %s', operation);
end

end

%% =========================================================
function verifyReadableArtifactSet(outputFolder, cfg, result)

rectangular_fpc_dxf_artifacts('verify_all', outputFolder, cfg, result);

verifyCoordinateCsv(fullfile(outputFolder, 'reports', ...
    '01_pad_via_coordinates.csv'), cfg, result);
verifyLayerMappingCsv(fullfile(outputFolder, 'reports', ...
    '02_layer_mapping.csv'), cfg);
verifyTurnScanCsv(fullfile(outputFolder, 'reports', ...
    '04_turn_scan.csv'), result);
verifyManufacturingCsv(fullfile(outputFolder, 'reports', ...
    '06_manufacturing_check.csv'), result.manufacturing);

verifyTextArtifact(fullfile(outputFolder, 'reports', ...
    '03_design_summary.txt'), { ...
    'Rectangular FPC coil design summary', ...
    sprintf('Design: %s', cfg.designName), ...
    sprintf('Layers / turns per layer: %d / %d', ...
    result.layerCount, result.turnsPerLayer), ...
    sprintf('Manufacturing status: %s', result.manufacturing.status)});
verifyTextArtifact(fullfile(outputFolder, 'reports', ...
    '05_validation_report.txt'), { ...
    'Export staging            : PASS', ...
    'Formal result             : PASS'});
verifyFabricationNotes(fullfile(outputFolder, 'reports', ...
    '07_fabrication_notes.txt'), cfg, result.manufacturing);
verifyGenerationStatus(fullfile(outputFolder, 'generation_status.txt'), ...
    cfg, result);

svgFiles = dir(fullfile(outputFolder, 'previews', '*.svg'));
expectedSvgCount = double(cfg.enablePreview) * (cfg.layerCount + 3);
if numel(svgFiles) ~= expectedSvgCount
    error('RectangularFPC:ExportReadbackFailed', ...
        'Expected %d SVG previews, found %d.', expectedSvgCount, numel(svgFiles));
end
expectedSvgNames = rectangular_fpc_preview_export('expected_names', cfg);
actualSvgNames = reshape(string({svgFiles.name}), [], 1);
if ~isequal(sort(actualSvgNames), sort(expectedSvgNames))
    error('RectangularFPC:ExportReadbackFailed', ...
        'SVG filename contract failed in %s.', fullfile(outputFolder, 'previews'));
end
for fileIndex = 1:numel(svgFiles)
    filename = fullfile(svgFiles(fileIndex).folder, svgFiles(fileIndex).name);
    verifySvgArtifact(filename);
end

end

%% =========================================================
function verifyCoordinateCsv(filename, cfg, result)

data = readContractTable(filename);
expectedNames = {'name', 'x_body_lower_left_mm', 'y_body_lower_left_mm', ...
    'x_internal_center_mm', 'y_internal_center_mm', 'from_layer', ...
    'to_layer', 'object_type', 'placement_region', 'placement_mode', ...
    'pad_diameter_mm', 'drill_diameter_mm', 'annular_ring_mm', ...
    'antipad_diameter_mm', 'description'};
verifyTableContract(filename, data, expectedNames, numel(result.vias) + 2);

expectedObjectNames = [{result.pads(1).name}, {result.vias.name}, ...
    {result.pads(2).name}].';
if ~isequal(cellstr(string(data.name)), expectedObjectNames)
    readbackError(filename, 'coordinate object order');
end
internalXY = [result.pads(1).xy; reshape([result.vias.xy], 2, []).'; ...
    result.pads(2).xy];
userXY = rectangular_fpc_geometry('internal_to_user', internalXY, cfg);
verifyCoordinates(filename, [data.x_internal_center_mm, ...
    data.y_internal_center_mm], internalXY, 1e-6);
verifyCoordinates(filename, [data.x_body_lower_left_mm, ...
    data.y_body_lower_left_mm], userXY, 1e-6);

rowCount = numel(result.vias) + 2;
expectedFrom = strings(rowCount, 1);
expectedTo = strings(rowCount, 1);
expectedType = strings(rowCount, 1);
expectedRegion = strings(rowCount, 1);
expectedMode = strings(rowCount, 1);
expectedPadDiameter = zeros(rowCount, 1);
expectedDrillDiameter = zeros(rowCount, 1);
expectedAnnularRing = zeros(rowCount, 1);
expectedAntipadDiameter = zeros(rowCount, 1);
expectedDescription = strings(rowCount, 1);

expectedFrom(1) = "L1";
expectedTo(1) = "external";
expectedType(1) = "pad";
expectedRegion(1) = "EXTERNAL_PAD";
expectedMode(1) = "fixed";
expectedPadDiameter(1) = result.pads(1).diameter;
expectedDescription(1) = "Top-layer input terminal";
for viaIndex = 1:numel(result.vias)
    rowIndex = viaIndex + 1;
    via = result.vias(viaIndex);
    expectedFrom(rowIndex) = sprintf('L%d', via.fromLayer);
    expectedTo(rowIndex) = sprintf('L%d', via.toLayer);
    expectedType(rowIndex) = string(via.type);
    expectedRegion(rowIndex) = string(via.placementRegion);
    expectedMode(rowIndex) = string(via.placementMode);
    expectedPadDiameter(rowIndex) = via.padDiameter;
    expectedDrillDiameter(rowIndex) = via.drillDiameter;
    expectedAnnularRing(rowIndex) = ...
        (via.padDiameter - via.drillDiameter) / 2;
    expectedAntipadDiameter(rowIndex) = via.antipadDiameter;
    expectedDescription(rowIndex) = string(via.role);
end
expectedFrom(end) = "L1";
expectedTo(end) = "external";
expectedType(end) = "pad";
expectedRegion(end) = "EXTERNAL_PAD";
expectedMode(end) = "fixed";
expectedPadDiameter(end) = result.pads(2).diameter;
expectedDescription(end) = "Top-layer output terminal";

verifyTextColumn(filename, data.from_layer, expectedFrom, 'from_layer');
verifyTextColumn(filename, data.to_layer, expectedTo, 'to_layer');
verifyTextColumn(filename, data.object_type, expectedType, 'object_type');
verifyTextColumn(filename, data.placement_region, expectedRegion, ...
    'placement_region');
verifyTextColumn(filename, data.placement_mode, expectedMode, ...
    'placement_mode');
verifyCoordinates(filename, data.pad_diameter_mm, expectedPadDiameter, 1e-6);
verifyCoordinates(filename, data.drill_diameter_mm, ...
    expectedDrillDiameter, 1e-6);
verifyCoordinates(filename, data.annular_ring_mm, expectedAnnularRing, 1e-6);
verifyCoordinates(filename, data.antipad_diameter_mm, ...
    expectedAntipadDiameter, 1e-6);
verifyTextColumn(filename, data.description, expectedDescription, 'description');

end

%% =========================================================
function verifyTextColumn(filename, actual, expected, contract)

actual = string(actual);
actual(ismissing(actual)) = "";
expected = string(expected);
expected(ismissing(expected)) = "";
if ~isequal(actual(:), expected(:))
    readbackError(filename, [contract ' mismatch']);
end

end

%% =========================================================
function verifySvgArtifact(filename)

svgText = fileread(filename);
lowerText = lower(svgText);
if contains(lowerText, '<!doctype') || contains(lowerText, '<!entity') || ...
        contains(lowerText, '<image') || contains(lowerText, '<script') || ...
        contains(lowerText, '<foreignobject') || ...
        contains(lowerText, 'javascript:') || ...
        ~isempty(regexp(lowerText, '\son[a-z]+\s*=', 'once'))
    readbackError(filename, 'unsafe or embedded SVG content');
end
try
    document = xmlread(filename);
    root = document.getDocumentElement();
    if ~strcmpi(char(root.getNodeName()), 'svg') || ...
            ~validSvgViewBox(char(root.getAttribute('viewBox')))
        readbackError(filename, 'SVG root or viewBox contract');
    end
    if ~hasRenderableVector(root)
        readbackError(filename, 'SVG contains no nonempty vector geometry');
    end
catch verificationError
    if strcmp(verificationError.identifier, ...
            'RectangularFPC:ExportReadbackFailed')
        rethrow(verificationError);
    end
    readbackError(filename, 'SVG is not well-formed XML');
end

end

%% =========================================================
function hasVector = hasRenderableVector(root)

attributeContracts = { ...
    'path', {'d'}; ...
    'polyline', {'points'}; ...
    'polygon', {'points'}; ...
    'circle', {'r'}; ...
    'ellipse', {'rx', 'ry'}; ...
    'rect', {'width', 'height'}};
hasVector = false;
for contractIndex = 1:size(attributeContracts, 1)
    nodes = root.getElementsByTagName(attributeContracts{contractIndex, 1});
    attributes = attributeContracts{contractIndex, 2};
    for nodeIndex = 0:nodes.getLength() - 1
        complete = true;
        for attributeIndex = 1:numel(attributes)
            value = strtrim(char(nodes.item(nodeIndex).getAttribute( ...
                attributes{attributeIndex})));
            complete = complete && ~isempty(value);
        end
        if complete && attributeGeometryIsNonempty( ...
                attributeContracts{contractIndex, 1}, ...
                nodes.item(nodeIndex), attributes)
            hasVector = true;
            return;
        end
    end
end

lineNodes = root.getElementsByTagName('line');
lineAttributes = {'x1', 'y1', 'x2', 'y2'};
for nodeIndex = 0:lineNodes.getLength() - 1
    coordinates = nan(1, numel(lineAttributes));
    for attributeIndex = 1:numel(lineAttributes)
        value = strtrim(char(lineNodes.item(nodeIndex).getAttribute( ...
            lineAttributes{attributeIndex})));
        coordinates(attributeIndex) = str2double(value);
    end
    if all(isfinite(coordinates)) && ...
            any(coordinates(1:2) ~= coordinates(3:4))
        hasVector = true;
        return;
    end
end

end

%% =========================================================
function valid = validSvgViewBox(viewBox)

parts = regexp(strtrim(viewBox), '[,\s]+', 'split');
parts = parts(~cellfun('isempty', parts));
values = str2double(parts);
valid = numel(values) == 4 && all(isfinite(values)) && ...
    values(3) > 0 && values(4) > 0;

end

%% =========================================================
function nonempty = attributeGeometryIsNonempty(tagName, node, attributes)

values = cell(size(attributes));
for attributeIndex = 1:numel(attributes)
    values{attributeIndex} = char(node.getAttribute( ...
        attributes{attributeIndex}));
end
numberPattern = '[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?';
numbers = str2double(regexp(strjoin(values, ' '), ...
    numberPattern, 'match'));
if any(~isfinite(numbers))
    nonempty = false;
    return;
end
switch tagName
    case 'path'
        nonempty = ~isempty(regexp(values{1}, '^\s*[Mm]', 'once')) && ...
            hasDistinctPointPairs(numbers, 2);
    case 'polyline'
        nonempty = mod(numel(numbers), 2) == 0 && ...
            hasDistinctPointPairs(numbers, 2);
    case 'polygon'
        nonempty = numel(numbers) >= 6 && mod(numel(numbers), 2) == 0 && ...
            hasDistinctPointPairs(numbers, 3);
    case 'circle'
        nonempty = isscalar(numbers) && numbers(1) > 0;
    case {'ellipse', 'rect'}
        nonempty = numel(numbers) == 2 && all(numbers > 0);
    otherwise
        nonempty = false;
end

end

%% =========================================================
function distinct = hasDistinctPointPairs(numbers, minimumPointCount)

pointCount = floor(numel(numbers) / 2);
if pointCount < minimumPointCount
    distinct = false;
    return;
end
points = reshape(numbers(1:2 * pointCount), 2, []).';
distinct = any(any(points(2:end, :) ~= points(1, :)));

end

%% =========================================================
function verifyGenerationStatus(filename, cfg, result)

content = fileread(filename);
expectedFields = { ...
    'Status', 'SUCCESS'; ...
    'SchemaVersion', '2'; ...
    'Design', cfg.designName; ...
    'LayerCount', sprintf('%d', result.layerCount); ...
    'PreviewEnabled', sprintf('%d', cfg.enablePreview); ...
    'TurnsPerLayer', sprintf('%d', result.turnsPerLayer); ...
    'ManufacturingProfile', result.manufacturing.profile; ...
    'ManufacturingTier', result.manufacturing.tier; ...
    'ManufacturingStatus', result.manufacturing.status; ...
    'ManufacturingApplicability', result.manufacturing.applicability; ...
    'ManufacturingVerified', sprintf('%d', result.manufacturing.verified)};
for fieldIndex = 1:size(expectedFields, 1)
    actual = exactKeyValueField(filename, content, expectedFields{fieldIndex, 1});
    if ~strcmp(actual, expectedFields{fieldIndex, 2})
        readbackError(filename, sprintf('%s status field mismatch', ...
            expectedFields{fieldIndex, 1}));
    end
end
publicationId = exactKeyValueField(filename, content, 'PublicationId');
if isempty(regexp(publicationId, '^[0-9a-fA-F]{32}$', 'once'))
    readbackError(filename, 'PublicationId status field mismatch');
end
exactKeyValueField(filename, content, 'Generated');

end

%% =========================================================
function verifyFabricationNotes(filename, cfg, manufacturing)

content = fileread(filename);
expectedFields = { ...
    'Design', cfg.designName; ...
    'Layer count', sprintf('%d', cfg.layerCount); ...
    'Manufacturing profile', sprintf('%s (%s)', ...
        manufacturing.profile, manufacturing.tier); ...
    'Requested profile', manufacturing.requestedProfile; ...
    'Base profile', manufacturing.baseProfile; ...
    'Rule classification', manufacturing.ruleClassification; ...
    'Profile checked on', manufacturing.sourceCheckedOn; ...
    'Applicability', manufacturing.applicability; ...
    'Verified', sprintf('%d', manufacturing.verified); ...
    'Rule override count', sprintf('%d', ...
        numel(fieldnames(manufacturing.ruleOverrides)))};
for fieldIndex = 1:size(expectedFields, 1)
    actual = exactKeyValueField( ...
        filename, content, expectedFields{fieldIndex, 1});
    if ~strcmp(actual, expectedFields{fieldIndex, 2})
        readbackError(filename, sprintf('%s field mismatch', ...
            expectedFields{fieldIndex, 1}));
    end
end

baseRuleNames = fieldnames(manufacturing.baseRules);
for ruleIndex = 1:numel(baseRuleNames)
    ruleName = baseRuleNames{ruleIndex};
    verifyNumericTextField(filename, content, ['BaseRule.' ruleName], ...
        manufacturing.baseRules.(ruleName));
    verifyNumericTextField(filename, content, ['EffectiveRule.' ruleName], ...
        manufacturing.rules.(ruleName));
end
overrideNames = fieldnames(manufacturing.ruleOverrides);
for overrideIndex = 1:numel(overrideNames)
    ruleName = overrideNames{overrideIndex};
    verifyNumericTextField(filename, content, ['RuleOverride.' ruleName], ...
        manufacturing.ruleOverrides.(ruleName));
end

sourceMatches = regexp(content, '(?m)^Rule source:\s*([^\r\n]+?)\s*$', ...
    'tokens');
actualSources = cellfun(@(match) strtrim(match{1}), ...
    sourceMatches, 'UniformOutput', false);
if ~isequal(actualSources(:), manufacturing.sourceUrls(:))
    readbackError(filename, 'manufacturing rule source chain mismatch');
end

end

%% =========================================================
function verifyNumericTextField(filename, content, fieldName, expected)

actual = exactKeyValueField(filename, content, fieldName);
if ~strcmp(actual, sprintf('%.17g', expected))
    readbackError(filename, sprintf('%s field mismatch', fieldName));
end

end

%% =========================================================
function value = exactKeyValueField(filename, content, fieldName)

matches = regexp(content, ['(?m)^' regexptranslate('escape', fieldName) ...
    ':\s*([^\r\n]+?)\s*$'], 'tokens');
if numel(matches) ~= 1
    readbackError(filename, sprintf( ...
        '%s field must occur exactly once', fieldName));
end
value = strtrim(matches{1}{1});

end

%% =========================================================
function verifyLayerMappingCsv(filename, cfg)

data = readContractTable(filename);
expectedNames = {'layer', 'role', 'stack_position', 'centerline_dxf', ...
    'physical_copper_dxf', 'antipad_keepout_dxf'};
verifyTableContract(filename, data, expectedNames, cfg.layerCount);
expectedLayers = string(compose('L%d', (1:cfg.layerCount).'));
expectedRoles = strings(cfg.layerCount, 1);
expectedCenterline = strings(cfg.layerCount, 1);
expectedPhysical = strings(cfg.layerCount, 1);
expectedAntipad = strings(cfg.layerCount, 1);
for layerIndex = 1:cfg.layerCount
    if layerIndex == 1
        expectedRoles(layerIndex) = "TOP";
    elseif layerIndex == cfg.layerCount
        expectedRoles(layerIndex) = "BOTTOM";
    else
        expectedRoles(layerIndex) = "INNER_" + string(layerIndex - 1);
    end
    expectedCenterline(layerIndex) = sprintf( ...
        '../dxf/L%d/%02d_copper_L%d.dxf', ...
        layerIndex, layerIndex, layerIndex);
    expectedPhysical(layerIndex) = sprintf( ...
        '../dxf/L%d/%02d_copper_physical_L%d.dxf', ...
        layerIndex, layerIndex, layerIndex);
    expectedAntipad(layerIndex) = sprintf( ...
        '../dxf/L%d/%02d_antipad_keepout_L%d.dxf', ...
        layerIndex, layerIndex, layerIndex);
end
if ~isequal(string(data.layer), expectedLayers) || ...
        ~isequal(string(data.role), expectedRoles) || ...
        ~isequal(data.stack_position, (1:cfg.layerCount).') || ...
        ~isequal(string(data.centerline_dxf), expectedCenterline) || ...
        ~isequal(string(data.physical_copper_dxf), expectedPhysical) || ...
        ~isequal(string(data.antipad_keepout_dxf), expectedAntipad)
    readbackError(filename, 'layer mapping rows');
end

end

%% =========================================================
function verifyTurnScanCsv(filename, result)

data = readContractTable(filename);
expectedNames = {'turns', 'passed', 'is_fully_validated_maximum', ...
    'failure_code', 'failure_reason'};
verifyTableContract(filename, data, expectedNames, numel(result.turnScan));
expectedMaximum = [result.turnScan.turns].' == ...
    result.fullyValidatedMaximumTurns;
expectedCodes = strings(numel(result.turnScan), 1);
expectedReasons = strings(numel(result.turnScan), 1);
for scanIndex = 1:numel(result.turnScan)
    scan = result.turnScan(scanIndex);
    if isfield(scan, 'failureCode')
        expectedCodes(scanIndex) = string(scan.failureCode);
    else
        expectedCodes(scanIndex) = string(rectangular_fpc_report_artifacts('scan_failure_code', scan.failureReason));
    end
    expectedReasons(scanIndex) = string(scan.failureReason);
end
actualCodes = normalizeMissingStrings(data.failure_code);
actualReasons = normalizeMissingStrings(data.failure_reason);
if ~isequal(data.turns, [result.turnScan.turns].') || ...
        ~isequal(logical(data.passed), [result.turnScan.passed].') || ...
        ~isequal(logical(data.is_fully_validated_maximum), expectedMaximum) || ...
        ~isequal(actualCodes, expectedCodes) || ...
        ~isequal(actualReasons, expectedReasons)
    readbackError(filename, 'turn scan rows');
end

end

%% =========================================================
function verifyManufacturingCsv(filename, manufacturing)

data = readContractTable(filename);
expectedNames = {'check_id', 'status', 'measured_mm', 'limit_mm', ...
    'margin_mm', 'code', 'message'};
verifyTableContract(filename, data, expectedNames, numel(manufacturing.checks));
if ~isequal(string(data.check_id), string({manufacturing.checks.id}.')) || ...
        ~isequal(string(data.status), string({manufacturing.checks.status}.'))
    readbackError(filename, 'manufacturing check rows');
end
verifyNumericContract(filename, data.measured_mm, ...
    [manufacturing.checks.measuredMm].', 1e-8);
verifyNumericContract(filename, data.limit_mm, ...
    [manufacturing.checks.limitMm].', 1e-8);
verifyNumericContract(filename, data.margin_mm, ...
    [manufacturing.checks.marginMm].', 1e-8);
if ~isequal(normalizeMissingStrings(data.code), ...
        string({manufacturing.checks.code}.')) || ...
        ~isequal(normalizeMissingStrings(data.message), ...
        string({manufacturing.checks.message}.'))
    readbackError(filename, 'manufacturing code or message');
end

end

%% =========================================================
function verifyNumericContract(filename, actual, expected, tolerance)

if ~isequal(size(actual), size(expected)) || ...
        any(isinf(actual), 'all') || any(isinf(expected), 'all') || ...
        ~isequal(isnan(actual), isnan(expected)) || ...
        ~isequal(isfinite(actual), isfinite(expected))
    readbackError(filename, 'numeric contract mismatch');
end
finiteValues = isfinite(expected);
if any(finiteValues, 'all') && ...
        max(abs(actual(finiteValues) - expected(finiteValues)), [], 'all') > tolerance
    readbackError(filename, 'numeric contract mismatch');
end

end

%% =========================================================
function values = normalizeMissingStrings(values)

values = string(values);
values(ismissing(values)) = "";

end

%% =========================================================
function verifyTextArtifact(filename, requiredFragments)

content = fileread(filename);
if isempty(strtrim(content)) || ...
        any(~cellfun(@(fragment) contains(content, fragment), requiredFragments))
    error('RectangularFPC:ExportReadbackFailed', ...
        'Text artifact readback contract failed: %s', filename);
end

end

%% =========================================================
function data = readContractTable(filename)

data = readtable(filename, 'TextType', 'string', ...
    'VariableNamingRule', 'preserve', 'Delimiter', ',');

end

%% =========================================================
function verifyTableContract(filename, data, expectedNames, expectedRows)

if ~isequal(data.Properties.VariableNames, expectedNames) || ...
        height(data) ~= expectedRows
    error('RectangularFPC:ExportReadbackFailed', ...
        ['Readback failed for %s (CSV schema or row count). ', ...
        'Expected [%s] x %d; found [%s] x %d.'], ...
        filename, strjoin(expectedNames, ','), expectedRows, ...
        strjoin(data.Properties.VariableNames, ','), height(data));
end

end

%% =========================================================
function verifyCoordinates(filename, actual, expected, tolerance)

if ~isequal(size(actual), size(expected)) || ...
        any(~isfinite(actual), 'all') || ...
        (~isempty(actual) && max(abs(actual - expected), [], 'all') > tolerance)
    readbackError(filename, 'coordinate or diameter mismatch');
end

end

%% =========================================================
function readbackError(filename, contract)

error('RectangularFPC:ExportReadbackFailed', ...
    'Readback failed for %s (%s).', filename, contract);

end
