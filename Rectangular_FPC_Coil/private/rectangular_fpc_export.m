function varargout = rectangular_fpc_export(operation, varargin)
%RECTANGULAR_FPC_EXPORT Private export dispatcher for the rectangular FPC runtime.
%   Supported operations:
%     'previews' -> writePreviews(cfg, boardXY, layerPaths, padA, padB, vias, previewFolder)
%     'formal_export' -> atomically publish a complete result artifact set
%     'engineering_artifacts' -> complete and verify the formal export set

switch operation
    case 'previews'
        [varargout{1:nargout}] = writePreviews(varargin{:});
    case 'formal_export'
        varargout{1} = writeFormalExport(varargin{:});
    case 'engineering_artifacts'
        writeEngineeringArtifacts(varargin{:});
    otherwise
        error('RectangularFPC:UnknownExportOperation', ...
            'Unknown export operation: %s', operation);
end

end

%% =========================================================
function result = writeFormalExport(cfg, result)
% The analysis result is immutable input. All filesystem effects, including
% staging, verification, and atomic publication, are owned by this module.

if cfg.analysisOnly
    error('RectangularFPC:InvalidExportRequest', ...
        'formal_export requires analysisOnly=false.');
end
if ~result.validation.passed
    error('RectangularFPC:ValidationFailed', ...
        'A failed analysis result cannot be exported.');
end
if ~result.manufacturing.exportAllowed
    error('RectangularFPC:ManufacturingFailed', ...
        'Manufacturing checks failed: %s', ...
        strjoin(result.manufacturing.failures, '; '));
end

outputFolder = fullfile(cfg.outputRoot, cfg.designName);
if ~isfolder(cfg.outputRoot)
    mkdir(cfg.outputRoot);
end
tempOutputFolder = [tempname(cfg.outputRoot), '_rectangular_fpc_staging'];
prepareFormalTempFolder(tempOutputFolder);
stagingCleanup = onCleanup(@() removeStagingFolder(tempOutputFolder));

try
    dxfFolder = fullfile(tempOutputFolder, 'dxf');
    boardDxfFile = fullfile(dxfFolder, '00_board_outline.dxf');
    writeBoardOutlineDxf(boardDxfFile, result.boardXY, 'BOARD_OUTLINE');

    copperFileNames = cell(cfg.layerCount, 1);
    for layerIndex = 1:cfg.layerCount
        layerFolder = fullfile(dxfFolder, sprintf('L%d', layerIndex));
        if ~isfolder(layerFolder)
            mkdir(layerFolder);
        end
        copperFileNames{layerIndex} = sprintf( ...
            '%02d_copper_L%d.dxf', layerIndex, layerIndex);
        writeCenterlineDxf( ...
            fullfile(layerFolder, copperFileNames{layerIndex}), ...
            result.layerPaths{layerIndex}, ...
            result.layers(layerIndex).name, cfg.maxVerticesPerDxfEntity);
    end

    reportsFolder = fullfile(tempOutputFolder, 'reports');
    writeCoordinateReport(fullfile( ...
        reportsFolder, '01_pad_via_coordinates.csv'), cfg, result);
    writeDesignSummaryReport(fullfile( ...
        reportsFolder, '03_design_summary.txt'), cfg, result);
    writeTurnScanReport(fullfile( ...
        reportsFolder, '04_turn_scan.csv'), result);
    writeValidationReport(fullfile( ...
        reportsFolder, '05_validation_report.txt'), result.validation);

    if cfg.enablePreview
        writePreviews(cfg, result.boardXY, result.layerPaths, ...
            result.pads(1).xy, result.pads(2).xy, result.vias, ...
            fullfile(tempOutputFolder, 'previews'));
    end
    writeGenerationStatusFile( ...
        fullfile(tempOutputFolder, 'generation_status.txt'), cfg, result);

    writeEngineeringArtifacts(cfg, tempOutputFolder, boardDxfFile, ...
        copperFileNames, result.layerPaths, result.vias, ...
        result.manufacturing, result);
    rectangular_fpc_publish_atomically(tempOutputFolder, outputFolder);
catch ME
    rethrow(ME);
end
clear stagingCleanup;

result.outputFolder = outputFolder;
result.outputPath = outputFolder;
result.coordinateCsv = fullfile( ...
    outputFolder, 'reports', '01_pad_via_coordinates.csv');
result.layerMappingFile = fullfile( ...
    outputFolder, 'reports', '02_layer_mapping.csv');
result.summaryFile = fullfile( ...
    outputFolder, 'reports', '03_design_summary.txt');
result.turnScanFile = fullfile( ...
    outputFolder, 'reports', '04_turn_scan.csv');
result.validationReport = fullfile( ...
    outputFolder, 'reports', '05_validation_report.txt');
result.manufacturingReport = fullfile( ...
    outputFolder, 'reports', '06_manufacturing_check.csv');
result.fabricationNotes = fullfile( ...
    outputFolder, 'reports', '07_fabrication_notes.txt');
result.fileManifest = fullfile( ...
    outputFolder, 'reports', '08_file_manifest.csv');
result.boardDxfFile = fullfile(outputFolder, 'dxf', '00_board_outline.dxf');
result.drillMapDxfFile = fullfile(outputFolder, 'dxf', '00_drill_map.dxf');
for layerIndex = 1:cfg.layerCount
    layerFolder = fullfile(outputFolder, 'dxf', sprintf('L%d', layerIndex));
    result.layers(layerIndex).centerlineDxfFile = fullfile(layerFolder, ...
        sprintf('%02d_copper_L%d.dxf', layerIndex, layerIndex));
    result.layers(layerIndex).dxfFile = ...
        result.layers(layerIndex).centerlineDxfFile;
    result.layers(layerIndex).physicalCopperDxfFile = fullfile(layerFolder, ...
        sprintf('%02d_copper_physical_L%d.dxf', layerIndex, layerIndex));
    result.layers(layerIndex).antipadKeepoutDxfFile = fullfile(layerFolder, ...
        sprintf('%02d_antipad_keepout_L%d.dxf', layerIndex, layerIndex));
    result.layers(layerIndex).legacyDxfFile = '';
end

end

%% =========================================================
function prepareFormalTempFolder(tempOutputFolder)

if isfolder(tempOutputFolder)
    rmdir(tempOutputFolder, 's');
elseif isfile(tempOutputFolder)
    error('RectangularFPC:ExportWriteFailed', ...
        'Temporary output path is occupied by a file: %s', tempOutputFolder);
end
mkdir(tempOutputFolder);
mkdir(fullfile(tempOutputFolder, 'dxf'));
mkdir(fullfile(tempOutputFolder, 'reports'));
mkdir(fullfile(tempOutputFolder, 'previews'));

end

%% =========================================================
function removeStagingFolder(tempOutputFolder)

if isfolder(tempOutputFolder)
    rmdir(tempOutputFolder, 's');
end

end

%% =========================================================
function writeBoardOutlineDxf(filename, boardXY, layerName)

fid = openAsciiFile(filename, 'board-outline DXF');
cleanup = onCleanup(@() fclose(fid));
writeDxfHeader(fid, layerName);
writePolylineEntity(fid, boardXY, layerName, true, NaN);
writeDxfFooter(fid);
clear cleanup;

end

%% =========================================================
function writeCenterlineDxf(filename, paths, layerName, maxVertices)

fid = openAsciiFile(filename, 'centerline DXF');
cleanup = onCleanup(@() fclose(fid));
writeDxfHeader(fid, layerName);
for pathIndex = 1:numel(paths)
    xy = paths{pathIndex};
    firstIndex = 1;
    while firstIndex < size(xy, 1)
        lastIndex = min(firstIndex + maxVertices - 1, size(xy, 1));
        writePolylineEntity( ...
            fid, xy(firstIndex:lastIndex, :), layerName, false, NaN);
        if lastIndex == size(xy, 1)
            break;
        end
        firstIndex = lastIndex;
    end
end
writeDxfFooter(fid);
clear cleanup;

end

%% =========================================================
function writeCoordinateReport(filename, cfg, result)

fid = openUtf8File(filename, 'pad/via coordinate CSV');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, ['name,x_body_lower_left_mm,y_body_lower_left_mm,', ...
    'x_internal_center_mm,y_internal_center_mm,from_layer,to_layer,', ...
    'object_type,placement_region,placement_mode,pad_diameter_mm,', ...
    'drill_diameter_mm,annular_ring_mm,antipad_diameter_mm,description\n']);
writePadCoordinateRow(fid, result.pads(1), cfg, 'Top-layer input terminal');
for viaIndex = 1:numel(result.vias)
    via = result.vias(viaIndex);
    xyUser = rectangular_fpc_geometry('internal_to_user', via.xy, cfg);
    annularRing = (via.padDiameter - via.drillDiameter) / 2;
    fprintf(fid, '%s,%.6f,%.6f,%.6f,%.6f,L%d,L%d,%s,%s,%s,', ...
        csvText(via.name), xyUser(1), xyUser(2), via.xy(1), via.xy(2), ...
        via.fromLayer, via.toLayer, csvText(via.type), ...
        csvText(via.placementRegion), csvText(via.placementMode));
    fprintf(fid, '%.3f,%.3f,%.3f,%.3f,%s\n', ...
        via.padDiameter, via.drillDiameter, annularRing, ...
        via.antipadDiameter, csvText(via.role));
end
writePadCoordinateRow(fid, result.pads(2), cfg, 'Top-layer output terminal');
clear cleanup;

end

%% =========================================================
function writePadCoordinateRow(fid, pad, cfg, description)

xyUser = rectangular_fpc_geometry('internal_to_user', pad.xy, cfg);
fprintf(fid, '%s,%.6f,%.6f,%.6f,%.6f,L1,external,pad,', ...
    csvText(pad.name), xyUser(1), xyUser(2), pad.xy(1), pad.xy(2));
fprintf(fid, 'EXTERNAL_PAD,fixed,%.3f,0,0,0,%s\n', ...
    pad.diameter, csvText(description));

end

%% =========================================================
function writeDesignSummaryReport(filename, cfg, result)

fid = openUtf8File(filename, 'design summary');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Rectangular FPC coil design summary\n');
fprintf(fid, '===================================\n');
fprintf(fid, 'Design: %s\n', cfg.designName);
fprintf(fid, 'Layers / turns per layer: %d / %d\n', ...
    result.layerCount, result.turnsPerLayer);
fprintf(fid, 'Body size: %.3f x %.3f mm\n', cfg.plateLength, cfg.plateWidth);
fprintf(fid, 'Right tab: %.3f x %.3f mm\n', cfg.tabLength, cfg.tabWidth);
fprintf(fid, 'Trace width / spacing: %.3f / %.3f mm\n', ...
    cfg.traceWidth, cfg.traceSpacing);
fprintf(fid, 'Total trace length: %.6f mm\n', result.totalTraceLengthMm);
fprintf(fid, 'Estimated DC resistance: %.9f ohm\n', ...
    result.estimatedDcResistanceOhm);
fprintf(fid, 'Fully validated maximum turns: %d\n', ...
    result.fullyValidatedMaximumTurns);
fprintf(fid, 'Recommended turns: %d\n', result.recommendedTurns);
fprintf(fid, 'Minimum copper spacing: %.6f mm\n', result.minCopperSpacing);
fprintf(fid, 'Manufacturing status: %s\n', result.manufacturing.status);
fprintf(fid, 'Manufacturing applicability: %s\n', ...
    result.manufacturing.applicability);
for layerIndex = 1:cfg.layerCount
    fprintf(fid, 'L%d trace length: %.6f mm\n', ...
        layerIndex, result.layerLengthMm(layerIndex));
end
clear cleanup;

end

%% =========================================================
function writeTurnScanReport(filename, result)

fid = openUtf8File(filename, 'turn scan CSV');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, ['turns,passed,is_fully_validated_maximum,failure_code,', ...
    'failure_reason\n']);
for scanIndex = 1:numel(result.turnScan)
    scan = result.turnScan(scanIndex);
    if isfield(scan, 'failureCode')
        failureCode = scan.failureCode;
    else
        failureCode = scanFailureCode(scan.failureReason);
    end
    fprintf(fid, '%d,%d,%d,%s,%s\n', ...
        scan.turns, scan.passed, ...
        scan.turns == result.fullyValidatedMaximumTurns, ...
        csvText(failureCode), csvText(scan.failureReason));
end
clear cleanup;

end

%% =========================================================
function code = scanFailureCode(reason)

if isempty(reason)
    code = '';
elseif contains(reason, '内圈空白')
    code = 'INNER_VIA_CAPACITY';
elseif contains(reason, '尾板')
    code = 'TAB_VIA_CAPACITY';
elseif contains(reason, '手动')
    code = 'MANUAL_VIA_INVALID';
elseif contains(reason, '平滑圆弧') || contains(reason, '转向角') || contains(reason, '圆弧')
    code = 'ROUTING_ARC_FAILURE';
elseif contains(reason, '自相交')
    code = 'COPPER_SELF_INTERSECTION';
elseif contains(reason, '间距不足') || contains(reason, '线距')
    code = 'COPPER_SPACING';
else
    code = 'UNKNOWN';
end

end

%% =========================================================
function writeValidationReport(filename, validation)

fid = openUtf8File(filename, 'validation report');
cleanup = onCleanup(@() fclose(fid));
for lineIndex = 1:numel(validation.reportLines)
    fprintf(fid, '%s\n', validation.reportLines{lineIndex});
end
fprintf(fid, 'Export staging            : PASS\n');
fprintf(fid, 'Formal result             : PASS\n');
clear cleanup;

end

%% =========================================================
function writeGenerationStatusFile(filename, cfg, result)

fid = openUtf8File(filename, 'generation status');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Rectangular FPC generation status\n');
fprintf(fid, '=================================\n');
fprintf(fid, 'Status: SUCCESS\n');
fprintf(fid, 'Generated: %s\n', char(datetime('now', ...
    'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'Design: %s\n', cfg.designName);
fprintf(fid, 'LayerCount: %d\n', cfg.layerCount);
fprintf(fid, 'TurnsPerLayer: %d\n', result.turnsPerLayer);
fprintf(fid, 'ManufacturingProfile: %s\n', result.manufacturing.profile);
fprintf(fid, 'ManufacturingTier: %s\n', result.manufacturing.tier);
fprintf(fid, 'ManufacturingStatus: %s\n', result.manufacturing.status);
fprintf(fid, 'ManufacturingApplicability: %s\n', ...
    result.manufacturing.applicability);
fprintf(fid, 'ManufacturingVerified: %d\n', result.manufacturing.verified);
for warningIndex = 1:numel(result.manufacturing.warnings)
    fprintf(fid, 'WARNING: %s\n', result.manufacturing.warnings{warningIndex});
end
clear cleanup;

end

%% =========================================================
function writeEngineeringArtifacts( ...
    cfg, outputFolder, boardDxfFile, copperFileNames, ...
    layerPaths, vias, manufacturing, result)
% Complete the standardized manufacturing handoff, then verify every
% manifest entry before the engine is allowed to publish the temp folder.

dxfFolder = fullfile(outputFolder, 'dxf');
reportsFolder = fullfile(outputFolder, 'reports');

copyRequiredFile(boardDxfFile, fullfile(dxfFolder, '00_board_outline.dxf'));
writeCircleDxf(fullfile(dxfFolder, '00_drill_map.dxf'), ...
    'DRILL_REFERENCE', vias, @(via) via.drillDiameter > 0, ...
    @(via) via.drillDiameter);

for layerIndex = 1:cfg.layerCount
    layerFolder = fullfile(dxfFolder, sprintf('L%d', layerIndex));
    sourceCenterline = fullfile( ...
        layerFolder, copperFileNames{layerIndex});
    centerlineFile = fullfile(layerFolder, sprintf( ...
        '%02d_copper_L%d.dxf', layerIndex, layerIndex));
    physicalFile = fullfile(layerFolder, sprintf( ...
        '%02d_copper_physical_L%d.dxf', layerIndex, layerIndex));
    antipadFile = fullfile(layerFolder, sprintf( ...
        '%02d_antipad_keepout_L%d.dxf', layerIndex, layerIndex));

    copyRequiredFile(sourceCenterline, centerlineFile);
    writePhysicalCopperDxf(physicalFile, layerPaths{layerIndex}, ...
        sprintf('COPPER_PHYSICAL_L%d', layerIndex), ...
        cfg.traceWidth, cfg.maxVerticesPerDxfEntity, ...
        result.pads, vias, layerIndex);
    writeCircleDxf(antipadFile, ...
        sprintf('ANTIPAD_KEEP_OUT_L%d', layerIndex), vias, ...
        @antipadApplies, @(via) via.antipadDiameter, layerIndex);
end

writeLayerMapping(fullfile(reportsFolder, '02_layer_mapping.csv'), cfg);
writeManufacturingCheck( ...
    fullfile(reportsFolder, '06_manufacturing_check.csv'), manufacturing);
writeFabricationNotes( ...
    fullfile(reportsFolder, '07_fabrication_notes.txt'), cfg, manufacturing);

verifyReadableArtifactSet(outputFolder, cfg, result);
manifestPath = fullfile(reportsFolder, '08_file_manifest.csv');
writeFileManifest(manifestPath, outputFolder);
verifyFileManifest(manifestPath, outputFolder);

end

%% =========================================================
function verifyReadableArtifactSet(outputFolder, cfg, result)

verifyBoardDxf(fullfile(outputFolder, 'dxf', ...
    '00_board_outline.dxf'), result.boardXY, cfg.geometryTolerance);
verifyDrillDxf(fullfile(outputFolder, 'dxf', ...
    '00_drill_map.dxf'), result.vias, cfg.geometryTolerance);
for layerIndex = 1:cfg.layerCount
    layerFolder = fullfile(outputFolder, 'dxf', sprintf('L%d', layerIndex));
    expectedChunks = splitExpectedPaths( ...
        result.layerPaths{layerIndex}, cfg.maxVerticesPerDxfEntity);
    verifyCopperDxf(fullfile(layerFolder, sprintf( ...
        '%02d_copper_L%d.dxf', layerIndex, layerIndex)), ...
        expectedChunks, result.layers(layerIndex).name, NaN, ...
        zeros(0, 3), cfg.geometryTolerance);

    physicalCircles = expectedPhysicalCircles( ...
        result, layerIndex);
    verifyCopperDxf(fullfile(layerFolder, sprintf( ...
        '%02d_copper_physical_L%d.dxf', layerIndex, layerIndex)), ...
        expectedChunks, sprintf('COPPER_PHYSICAL_L%d', layerIndex), ...
        cfg.traceWidth, physicalCircles, cfg.geometryTolerance);

    antipadCircles = expectedAntipadCircles(result.vias, layerIndex);
    verifyCircleOnlyDxf(fullfile(layerFolder, sprintf( ...
        '%02d_antipad_keepout_L%d.dxf', layerIndex, layerIndex)), ...
        sprintf('ANTIPAD_KEEP_OUT_L%d', layerIndex), ...
        antipadCircles, cfg.geometryTolerance);
end

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
verifyTextArtifact(fullfile(outputFolder, 'reports', ...
    '07_fabrication_notes.txt'), { ...
    'Rectangular FPC fabrication notes', ...
    sprintf('Design: %s', cfg.designName), ...
    sprintf('Applicability: %s', result.manufacturing.applicability)});
verifyTextArtifact(fullfile(outputFolder, 'generation_status.txt'), { ...
    'Status: SUCCESS', sprintf('Design: %s', cfg.designName), ...
    sprintf('LayerCount: %d', result.layerCount), ...
    sprintf('TurnsPerLayer: %d', result.turnsPerLayer), ...
    sprintf('ManufacturingStatus: %s', result.manufacturing.status)});

svgFiles = dir(fullfile(outputFolder, 'previews', '*.svg'));
expectedSvgCount = double(cfg.enablePreview) * (cfg.layerCount + 3);
if numel(svgFiles) ~= expectedSvgCount
    error('RectangularFPC:ExportReadbackFailed', ...
        'Expected %d SVG previews, found %d.', expectedSvgCount, numel(svgFiles));
end
expectedSvgNames = expectedPreviewNames(cfg);
actualSvgNames = reshape(string({svgFiles.name}), [], 1);
if ~isequal(sort(actualSvgNames), sort(expectedSvgNames))
    error('RectangularFPC:ExportReadbackFailed', ...
        'SVG filename contract failed in %s.', fullfile(outputFolder, 'previews'));
end
for fileIndex = 1:numel(svgFiles)
    filename = fullfile(svgFiles(fileIndex).folder, svgFiles(fileIndex).name);
    svgText = lower(fileread(filename));
    if ~contains(svgText, '<svg') || contains(svgText, '<image')
        error('RectangularFPC:ExportReadbackFailed', ...
            'SVG readback contract failed: %s', filename);
    end
end

end

%% =========================================================
function verifyBoardDxf(filename, boardXY, tolerance)

entities = readDxfEntities(filename);
if numel(entities) ~= 1 || ~strcmp(entities(1).type, 'LWPOLYLINE') || ...
        ~strcmp(entities(1).layer, 'BOARD_OUTLINE') || ...
        entities(1).closed ~= 1
    readbackError(filename, 'board entity contract');
end
verifyCoordinates(filename, entities(1).xy, boardXY, tolerance);

end

%% =========================================================
function verifyDrillDxf(filename, vias, tolerance)

circles = [reshape([vias.xy], 2, []).', ...
    reshape([vias.drillDiameter], [], 1) / 2];
verifyCircleOnlyDxf(filename, 'DRILL_REFERENCE', circles, tolerance);

end

%% =========================================================
function verifyCopperDxf( ...
    filename, expectedChunks, layerName, expectedWidth, expectedCircles, tolerance)

entities = readDxfEntities(filename);
types = {entities.type};
polylines = entities(strcmp(types, 'LWPOLYLINE'));
circles = entities(strcmp(types, 'CIRCLE'));
if numel(polylines) ~= numel(expectedChunks) || ...
        numel(circles) ~= size(expectedCircles, 1)
    readbackError(filename, 'entity count');
end
for entityIndex = 1:numel(polylines)
    entity = polylines(entityIndex);
    if ~strcmp(entity.layer, layerName) || entity.closed ~= 0
        readbackError(filename, 'polyline layer or closure');
    end
    if isfinite(expectedWidth) && ...
            abs(entity.width - expectedWidth) > tolerance
        readbackError(filename, 'physical copper width');
    elseif ~isfinite(expectedWidth) && isfinite(entity.width)
        readbackError(filename, 'unexpected centerline width');
    end
    verifyCoordinates(filename, entity.xy, expectedChunks{entityIndex}, tolerance);
end
verifyCircleEntities(filename, circles, layerName, expectedCircles, tolerance);

end

%% =========================================================
function verifyCircleOnlyDxf(filename, layerName, expectedCircles, tolerance)

entities = readDxfEntities(filename);
if any(~strcmp({entities.type}, 'CIRCLE')) || ...
        numel(entities) ~= size(expectedCircles, 1)
    readbackError(filename, 'circle-only entity contract');
end
verifyCircleEntities(filename, entities, layerName, expectedCircles, tolerance);

end

%% =========================================================
function verifyCircleEntities(filename, entities, layerName, expected, tolerance)

actual = zeros(numel(entities), 3);
for entityIndex = 1:numel(entities)
    if ~strcmp(entities(entityIndex).layer, layerName)
        readbackError(filename, 'circle layer');
    end
    actual(entityIndex, :) = [entities(entityIndex).center, ...
        entities(entityIndex).radius];
end
if ~isempty(expected)
    actual = sortrows(actual, [1, 2, 3]);
    expected = sortrows(expected, [1, 2, 3]);
end
verifyCoordinates(filename, actual, expected, tolerance);

end

%% =========================================================
function chunks = splitExpectedPaths(paths, maxVertices)

chunkCount = 0;
for pathIndex = 1:numel(paths)
    chunkCount = chunkCount + max(1, ceil( ...
        (size(paths{pathIndex}, 1) - 1) / (maxVertices - 1)));
end
chunks = cell(1, chunkCount);
chunkIndex = 0;
for pathIndex = 1:numel(paths)
    xy = paths{pathIndex};
    firstIndex = 1;
    while firstIndex < size(xy, 1)
        lastIndex = min(firstIndex + maxVertices - 1, size(xy, 1));
        chunkIndex = chunkIndex + 1;
        chunks{chunkIndex} = xy(firstIndex:lastIndex, :);
        if lastIndex == size(xy, 1)
            break;
        end
        firstIndex = lastIndex;
    end
end

end

%% =========================================================
function circles = expectedPhysicalCircles(result, layerIndex)

connected = arrayfun(@(via) ...
    ismember(layerIndex, via.connectedLayers), result.vias);
circleCount = sum(connected) + double(layerIndex == 1) * numel(result.pads);
circles = zeros(circleCount, 3);
circleIndex = 0;
if layerIndex == 1
    padCount = numel(result.pads);
    circles(1:padCount, :) = [reshape([result.pads.xy], 2, []).', ...
        reshape([result.pads.diameter], [], 1) / 2];
    circleIndex = padCount;
end
for viaIndex = 1:numel(result.vias)
    via = result.vias(viaIndex);
    if connected(viaIndex)
        circleIndex = circleIndex + 1;
        circles(circleIndex, :) = [via.xy, via.padDiameter / 2];
    end
end

end

%% =========================================================
function circles = expectedAntipadCircles(vias, layerIndex)

applies = arrayfun(@(via) antipadApplies(via, layerIndex), vias);
circles = zeros(sum(applies), 3);
circleIndex = 0;
for viaIndex = 1:numel(vias)
    via = vias(viaIndex);
    if applies(viaIndex)
        circleIndex = circleIndex + 1;
        circles(circleIndex, :) = [via.xy, via.antipadDiameter / 2];
    end
end

end

%% =========================================================
function entities = readDxfEntities(filename)

content = fileread(filename);
if ~contains(content, 'AC1015') || ~contains(content, '$INSUNITS') || ...
        ~endsWith(strtrim(content), 'EOF') || ...
        contains(content, 'NaN') || contains(content, 'Inf')
    readbackError(filename, 'base DXF contract');
end
lines = regexp(strtrim(content), '\r?\n', 'split').';
if mod(numel(lines), 2) ~= 0
    readbackError(filename, 'group-code pairing');
end
codes = str2double(lines(1:2:end));
values = lines(2:2:end);
if any(isnan(codes))
    readbackError(filename, 'non-numeric group code');
end
unitIndex = find(codes == 9 & strcmp(values, '$INSUNITS'), 1);
if isempty(unitIndex) || unitIndex == numel(codes) || ...
        codes(unitIndex + 1) ~= 70 || str2double(values{unitIndex + 1}) ~= 4
    readbackError(filename, 'millimetre units');
end

entitiesNameIndex = find(codes == 2 & strcmp(values, 'ENTITIES'), 1);
if isempty(entitiesNameIndex)
    readbackError(filename, 'missing ENTITIES section');
end
sectionEndOffset = find(codes(entitiesNameIndex + 1:end) == 0 & ...
    strcmp(values(entitiesNameIndex + 1:end), 'ENDSEC'), 1);
if isempty(sectionEndOffset)
    readbackError(filename, 'unterminated ENTITIES section');
end
sectionEndIndex = entitiesNameIndex + sectionEndOffset;
typeMask = codes == 0;
typeMask(1:entitiesNameIndex) = false;
typeMask(sectionEndIndex:end) = false;
unexpectedTypes = values(typeMask & ...
    ~ismember(values, {'LWPOLYLINE', 'CIRCLE'}));
if ~isempty(unexpectedTypes)
    readbackError(filename, sprintf('unexpected DXF entity %s', ...
        unexpectedTypes{1}));
end

entityMask = codes == 0 & ...
    (strcmp(values, 'LWPOLYLINE') | strcmp(values, 'CIRCLE'));
starts = find(entityMask);
template = struct('type', '', 'layer', '', 'xy', zeros(0, 2), ...
    'closed', NaN, 'width', NaN, 'center', [NaN, NaN], 'radius', NaN);
entities = repmat(template, numel(starts), 1);
for entityIndex = 1:numel(starts)
    first = starts(entityIndex);
    nextZero = find(codes(first + 1:end) == 0, 1);
    if isempty(nextZero)
        last = numel(codes);
    else
        last = first + nextZero - 1;
    end
    entityCodes = codes(first:last);
    entityValues = values(first:last);
    entities(entityIndex).type = values{first};
    entities(entityIndex).layer = char(groupText( ...
        entityCodes, entityValues, 8, ''));
    if strcmp(entities(entityIndex).type, 'LWPOLYLINE')
        x = groupNumbers(entityCodes, entityValues, 10);
        y = groupNumbers(entityCodes, entityValues, 20);
        declaredCount = groupNumber(entityCodes, entityValues, 90, NaN);
        if numel(x) ~= numel(y) || declaredCount ~= numel(x)
            readbackError(filename, 'polyline vertex declaration');
        end
        entities(entityIndex).xy = [x, y];
        entities(entityIndex).closed = groupNumber( ...
            entityCodes, entityValues, 70, NaN);
        entities(entityIndex).width = groupNumber( ...
            entityCodes, entityValues, 43, NaN);
    else
        entities(entityIndex).center = [ ...
            groupNumber(entityCodes, entityValues, 10, NaN), ...
            groupNumber(entityCodes, entityValues, 20, NaN)];
        entities(entityIndex).radius = groupNumber( ...
            entityCodes, entityValues, 40, NaN);
    end
end

end

%% =========================================================
function values = groupNumbers(codes, textValues, groupCode)

values = str2double(textValues(codes == groupCode));

end

%% =========================================================
function value = groupNumber(codes, textValues, groupCode, defaultValue)

values = groupNumbers(codes, textValues, groupCode);
if isempty(values)
    value = defaultValue;
else
    value = values(1);
end

end

%% =========================================================
function value = groupText(codes, textValues, groupCode, defaultValue)

index = find(codes == groupCode, 1);
if isempty(index)
    value = defaultValue;
else
    value = textValues{index};
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
        expectedCodes(scanIndex) = string(scanFailureCode(scan.failureReason));
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
verifyCoordinates(filename, data.measured_mm, ...
    [manufacturing.checks.measuredMm].', 1e-8);
verifyCoordinates(filename, data.limit_mm, ...
    [manufacturing.checks.limitMm].', 1e-8);
verifyCoordinates(filename, data.margin_mm, ...
    [manufacturing.checks.marginMm].', 1e-8);
if ~isequal(normalizeMissingStrings(data.code), ...
        string({manufacturing.checks.code}.')) || ...
        ~isequal(normalizeMissingStrings(data.message), ...
        string({manufacturing.checks.message}.'))
    readbackError(filename, 'manufacturing code or message');
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
function names = expectedPreviewNames(cfg)

if ~cfg.enablePreview
    names = strings(0, 1);
    return;
end
names = strings(cfg.layerCount + 3, 1);
names(1:3) = ["01_preview_full.svg"; ...
    "02_preview_right_tab.svg"; "03_preview_pads_vias.svg"];
for layerIndex = 1:cfg.layerCount
    names(layerIndex + 3) = sprintf( ...
        '%02d_preview_layer_L%d_%s.svg', layerIndex + 3, ...
        layerIndex, layerRole(cfg, layerIndex));
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
function readbackError(filename, contract)

error('RectangularFPC:ExportReadbackFailed', ...
    'Readback failed for %s (%s).', filename, contract);

end

%% =========================================================
function copyRequiredFile(sourcePath, destinationPath)

if ~isfile(sourcePath)
    error('RectangularFPC:MissingExportArtifact', ...
        'Required source artifact is missing: %s', sourcePath);
end
if strcmpi(char(sourcePath), char(destinationPath))
    return;
end
[copied, message] = copyfile(sourcePath, destinationPath, 'f');
if ~copied
    error('RectangularFPC:ExportWriteFailed', ...
        'Unable to create %s: %s', destinationPath, message);
end

end

%% =========================================================
function applies = antipadApplies(via, layerIndex)

applies = via.antipadDiameter > 0 && ...
    ~ismember(layerIndex, via.connectedLayers);

end

%% =========================================================
function writePhysicalCopperDxf( ...
    filename, paths, layerName, traceWidth, maxVertices, pads, vias, layerIndex)

fid = openAsciiFile(filename, 'DXF');
cleanup = onCleanup(@() fclose(fid));
writeDxfHeader(fid, layerName);

for pathIndex = 1:numel(paths)
    xy = paths{pathIndex};
    firstIndex = 1;
    while firstIndex < size(xy, 1)
        lastIndex = min(firstIndex + maxVertices - 1, size(xy, 1));
        writePolylineWithWidth( ...
            fid, xy(firstIndex:lastIndex, :), layerName, traceWidth);
        if lastIndex == size(xy, 1)
            break;
        end
        firstIndex = lastIndex;
    end
end

if layerIndex == 1
    for padIndex = 1:numel(pads)
        writeCircleEntity(fid, layerName, pads(padIndex).xy, ...
            pads(padIndex).diameter / 2);
    end
end
for viaIndex = 1:numel(vias)
    if ismember(layerIndex, vias(viaIndex).connectedLayers)
        writeCircleEntity(fid, layerName, vias(viaIndex).xy, ...
            vias(viaIndex).padDiameter / 2);
    end
end

writeDxfFooter(fid);
clear cleanup;

end

%% =========================================================
function writeCircleDxf(filename, layerName, vias, predicate, diameter, varargin)

fid = openAsciiFile(filename, 'DXF');
cleanup = onCleanup(@() fclose(fid));
writeDxfHeader(fid, layerName);

for viaIndex = 1:numel(vias)
    via = vias(viaIndex);
    if isempty(varargin)
        applies = predicate(via);
    else
        applies = predicate(via, varargin{:});
    end
    if applies
        writeCircleEntity(fid, layerName, via.xy, diameter(via) / 2);
    end
end

writeDxfFooter(fid);
clear cleanup;

end

%% =========================================================
function writeCircleEntity(fid, layerName, center, radius)

dxfPairLocal(fid, 0, 'CIRCLE');
dxfPairLocal(fid, 100, 'AcDbEntity');
dxfPairLocal(fid, 8, layerName);
dxfPairLocal(fid, 100, 'AcDbCircle');
dxfPairLocal(fid, 10, center(1));
dxfPairLocal(fid, 20, center(2));
dxfPairLocal(fid, 30, 0);
dxfPairLocal(fid, 40, radius);

end

%% =========================================================
function writeDxfHeader(fid, layerName)

dxfPairLocal(fid, 0, 'SECTION');
dxfPairLocal(fid, 2, 'HEADER');
dxfPairLocal(fid, 9, '$ACADVER');
dxfPairLocal(fid, 1, 'AC1015');
dxfPairLocal(fid, 9, '$INSUNITS');
dxfPairLocal(fid, 70, 4);
dxfPairLocal(fid, 0, 'ENDSEC');
dxfPairLocal(fid, 0, 'SECTION');
dxfPairLocal(fid, 2, 'TABLES');
dxfPairLocal(fid, 0, 'TABLE');
dxfPairLocal(fid, 2, 'LAYER');
dxfPairLocal(fid, 70, 1);
dxfPairLocal(fid, 0, 'LAYER');
dxfPairLocal(fid, 2, layerName);
dxfPairLocal(fid, 70, 0);
dxfPairLocal(fid, 62, 7);
dxfPairLocal(fid, 6, 'CONTINUOUS');
dxfPairLocal(fid, 0, 'ENDTAB');
dxfPairLocal(fid, 0, 'ENDSEC');
dxfPairLocal(fid, 0, 'SECTION');
dxfPairLocal(fid, 2, 'ENTITIES');

end

%% =========================================================
function writeDxfFooter(fid)

dxfPairLocal(fid, 0, 'ENDSEC');
dxfPairLocal(fid, 0, 'EOF');

end

%% =========================================================
function writePolylineWithWidth(fid, xy, layerName, traceWidth)

writePolylineEntity(fid, xy, layerName, false, traceWidth);

end


%% =========================================================
function writePolylineEntity(fid, xy, layerName, isClosed, traceWidth)

dxfPairLocal(fid, 0, 'LWPOLYLINE');
dxfPairLocal(fid, 100, 'AcDbEntity');
dxfPairLocal(fid, 8, layerName);
dxfPairLocal(fid, 100, 'AcDbPolyline');
dxfPairLocal(fid, 90, size(xy, 1));
dxfPairLocal(fid, 70, double(isClosed));
if isfinite(traceWidth)
    dxfPairLocal(fid, 43, traceWidth);
end
dxfPairLocal(fid, 38, 0);
for pointIndex = 1:size(xy, 1)
    dxfPairLocal(fid, 10, xy(pointIndex, 1));
    dxfPairLocal(fid, 20, xy(pointIndex, 2));
end

end

%% =========================================================
function dxfPairLocal(fid, groupCode, value)

persistent integerCodes
if isempty(integerCodes)
    integerCodes = [60:79, 90:99, 170:179, 270:289, ...
        370:389, 400:409, 1060:1071];
end
fprintf(fid, '%d\n', groupCode);
if isnumeric(value)
    if any(groupCode == integerCodes)
        fprintf(fid, '%d\n', round(value));
    else
        fprintf(fid, '%.9f\n', value);
    end
else
    fprintf(fid, '%s\n', char(value));
end

end

%% =========================================================
function writeLayerMapping(filename, cfg)

fid = openUtf8File(filename, 'layer mapping CSV');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, ['layer,role,stack_position,centerline_dxf,', ...
    'physical_copper_dxf,antipad_keepout_dxf\n']);
for layerIndex = 1:cfg.layerCount
    if layerIndex == 1
        role = 'TOP';
    elseif layerIndex == cfg.layerCount
        role = 'BOTTOM';
    else
        role = sprintf('INNER_%d', layerIndex - 1);
    end
    fprintf(fid, 'L%d,%s,%d,%s,%s,%s\n', ...
        layerIndex, role, layerIndex, ...
        sprintf('../dxf/L%d/%02d_copper_L%d.dxf', ...
            layerIndex, layerIndex, layerIndex), ...
        sprintf('../dxf/L%d/%02d_copper_physical_L%d.dxf', ...
            layerIndex, layerIndex, layerIndex), ...
        sprintf('../dxf/L%d/%02d_antipad_keepout_L%d.dxf', ...
            layerIndex, layerIndex, layerIndex));
end
clear cleanup;

end

%% =========================================================
function writeManufacturingCheck(filename, manufacturing)

fid = openUtf8File(filename, 'manufacturing check CSV');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, ['check_id,status,measured_mm,limit_mm,margin_mm,', ...
    'code,message\n']);
for checkIndex = 1:numel(manufacturing.checks)
    check = manufacturing.checks(checkIndex);
    fprintf(fid, '%s,%s,%.9g,%.9g,%.9g,%s,%s\n', ...
        csvText(check.id), csvText(check.status), check.measuredMm, ...
        check.limitMm, check.marginMm, csvText(check.code), ...
        csvText(check.message));
end
clear cleanup;

end

%% =========================================================
function writeFabricationNotes(filename, cfg, manufacturing)

fid = openUtf8File(filename, 'fabrication notes');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Rectangular FPC fabrication notes\n');
fprintf(fid, '=================================\n');
fprintf(fid, 'Design: %s\n', cfg.designName);
fprintf(fid, 'Layer count: %d\n', cfg.layerCount);
fprintf(fid, 'Copper: 1 oz nominal (%.3f mm)\n', cfg.copperThickness);
fprintf(fid, 'Trace width / spacing: %.3f / %.3f mm\n', ...
    cfg.traceWidth, cfg.traceSpacing);
fprintf(fid, 'Manufacturing profile: %s (%s)\n', ...
    manufacturing.profile, manufacturing.tier);
fprintf(fid, 'Profile checked on: %s\n', manufacturing.sourceCheckedOn);
fprintf(fid, 'Applicability: %s\n', manufacturing.applicability);
fprintf(fid, 'Verified: %d\n', manufacturing.verified);
fprintf(fid, ['Publication read protocol: do not read the design directory ', ...
    'while its sibling *_publish.lock directory exists; retry after the ', ...
    'lock disappears.\n']);
for sourceIndex = 1:numel(manufacturing.sourceUrls)
    fprintf(fid, 'Rule source: %s\n', manufacturing.sourceUrls{sourceIndex});
end
fprintf(fid, ['Import the physical-copper DXF when the EDA tool honors ', ...
    'LWPOLYLINE constant width; otherwise import the centerline DXF and ', ...
    'assign %.3f mm trace width.\n'], cfg.traceWidth);
fprintf(fid, ['The drill map is a positional reference. Create plated ', ...
    'vias and pads from 01_pad_via_coordinates.csv in the target EDA tool.\n']);
if strcmp(manufacturing.applicability, 'SUPPORTED')
    fprintf(fid, ['All vias are plated through holes through the complete stack. ', ...
        'Create copper pads only on connectedLayers and apply each layer''s ', ...
        'antipad keepout DXF on every non-connected layer.\n']);
else
    fprintf(fid, ['The series interconnects use an unverified adjacent-layer ', ...
        'via model; VOUT is a plated through hole. Confirm the stackup and ', ...
        'drilling process with the fabricator before ordering.\n']);
end
for warningIndex = 1:numel(manufacturing.warnings)
    fprintf(fid, 'WARNING: %s\n', manufacturing.warnings{warningIndex});
end
clear cleanup;

end

%% =========================================================
function writeFileManifest(filename, outputFolder)

if isfile(filename)
    delete(filename);
end
files = regularFiles(outputFolder);
relativePaths = cell(numel(files), 1);
for fileIndex = 1:numel(files)
    relativePaths{fileIndex} = relativeArtifactPath( ...
        fullfile(files(fileIndex).folder, files(fileIndex).name), outputFolder);
end
[relativePaths, order] = sort(relativePaths);
files = files(order);

fid = openUtf8File(filename, 'file manifest');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
for fileIndex = 1:numel(files)
    absolutePath = fullfile(files(fileIndex).folder, files(fileIndex).name);
    fprintf(fid, '%s,%s,%d,%s\n', ...
        csvText(relativePaths{fileIndex}), ...
        csvText(artifactRole(relativePaths{fileIndex})), ...
        files(fileIndex).bytes, sha256File(absolutePath));
end
clear cleanup;

end

%% =========================================================
function verifyFileManifest(filename, outputFolder)

manifest = readtable(filename, 'TextType', 'string', ...
    'VariableNamingRule', 'preserve', 'Delimiter', ',');
expectedVariables = {'relativePath', 'role', 'sizeBytes', 'sha256'};
if ~isequal(manifest.Properties.VariableNames, expectedVariables)
    error('RectangularFPC:ManifestVerificationFailed', ...
        'Manifest column contract is invalid.');
end
if any(manifest.relativePath == "reports/08_file_manifest.csv")
    error('RectangularFPC:ManifestVerificationFailed', ...
        'The file manifest must exclude itself.');
end
files = regularFiles(outputFolder);
actualPaths = strings(numel(files), 1);
for fileIndex = 1:numel(files)
    actualPaths(fileIndex) = string(relativeArtifactPath(fullfile( ...
        files(fileIndex).folder, files(fileIndex).name), outputFolder));
end
manifestMask = actualPaths ~= "reports/08_file_manifest.csv";
manifestFiles = files(manifestMask);
actualPaths = actualPaths(manifestMask);
listedPaths = manifest.relativePath;
if height(manifest) ~= numel(manifestFiles) || ...
        numel(unique(listedPaths)) ~= numel(listedPaths) || ...
        ~isequal(sort(listedPaths), sort(actualPaths))
    error('RectangularFPC:ManifestVerificationFailed', ...
        'Manifest path set is incomplete, duplicated, or contains extras.');
end
for rowIndex = 1:height(manifest)
    relativePath = char(manifest.relativePath(rowIndex));
    absolutePath = fullfile(outputFolder, ...
        strrep(relativePath, '/', filesep));
    if ~isfile(absolutePath)
        error('RectangularFPC:ManifestVerificationFailed', ...
            'Manifest entry is missing: %s', relativePath);
    end
    fileInfo = dir(absolutePath);
    expectedRole = artifactRole(relativePath);
    if fileInfo.bytes ~= manifest.sizeBytes(rowIndex) || ...
            ~strcmpi(sha256File(absolutePath), char(manifest.sha256(rowIndex))) || ...
            ~strcmp(expectedRole, char(manifest.role(rowIndex)))
        error('RectangularFPC:ManifestVerificationFailed', ...
            'Manifest role, size, or SHA-256 mismatch: %s', relativePath);
    end
end

end

%% =========================================================
function files = regularFiles(outputFolder)

files = dir(fullfile(outputFolder, '**', '*'));
files = files(~[files.isdir]);

end

%% =========================================================
function relativePath = relativeArtifactPath(absolutePath, outputFolder)

prefix = [char(outputFolder), filesep];
absolutePath = char(absolutePath);
if ~startsWith(absolutePath, prefix)
    error('RectangularFPC:ManifestVerificationFailed', ...
        'Artifact is outside the output folder: %s', absolutePath);
end
relativePath = strrep(absolutePath(numel(prefix) + 1:end), '\', '/');

end

%% =========================================================
function role = artifactRole(relativePath)

if strcmp(relativePath, 'dxf/00_board_outline.dxf')
    role = 'board_outline';
elseif strcmp(relativePath, 'dxf/00_drill_map.dxf')
    role = 'drill_reference';
elseif contains(relativePath, '_copper_physical_')
    role = 'physical_copper';
elseif contains(relativePath, '_antipad_keepout_')
    role = 'antipad_keepout';
elseif contains(relativePath, '_copper_L')
    role = 'copper_centerline';
elseif startsWith(relativePath, 'dxf/')
    role = 'legacy_dxf_alias';
elseif strcmp(relativePath, 'reports/01_pad_via_coordinates.csv')
    role = 'pad_via_coordinates';
elseif strcmp(relativePath, 'reports/02_layer_mapping.csv')
    role = 'layer_mapping';
elseif strcmp(relativePath, 'reports/03_design_summary.txt')
    role = 'design_summary';
elseif strcmp(relativePath, 'reports/04_turn_scan.csv')
    role = 'turn_scan';
elseif strcmp(relativePath, 'reports/05_validation_report.txt')
    role = 'validation_report';
elseif strcmp(relativePath, 'reports/06_manufacturing_check.csv')
    role = 'manufacturing_check';
elseif strcmp(relativePath, 'reports/07_fabrication_notes.txt')
    role = 'fabrication_notes';
elseif startsWith(relativePath, 'previews/')
    role = 'svg_preview';
elseif strcmp(relativePath, 'generation_status.txt')
    role = 'generation_status';
else
    role = 'artifact';
end

end

%% =========================================================
function hash = sha256File(filename)

fid = fopen(filename, 'rb');
if fid == -1
    error('RectangularFPC:ManifestVerificationFailed', ...
        'Unable to read artifact for hashing: %s', filename);
end
cleanup = onCleanup(@() fclose(fid));
raw = fread(fid, Inf, '*uint8');
clear cleanup;
messageDigest = java.security.MessageDigest.getInstance('SHA-256');
digest = messageDigest.digest(raw);
hash = lower(reshape(dec2hex(typecast(digest, 'uint8'), 2).', 1, []));

end

%% =========================================================
function value = csvText(value)

value = ['"', strrep(char(value), '"', '""'), '"'];

end

%% =========================================================
function fid = openAsciiFile(filename, description)

fid = fopen(filename, 'w', 'n', 'US-ASCII');
if fid == -1
    error('RectangularFPC:ExportWriteFailed', ...
        'Unable to create %s: %s', description, filename);
end

end

%% =========================================================
function fid = openUtf8File(filename, description)

fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid == -1
    error('RectangularFPC:ExportWriteFailed', ...
        'Unable to create %s: %s', description, filename);
end

end

%% =========================================================
function writePreviews(cfg, boardXY, layerPaths, padA, padB, vias, previewFolder)
% 生成两张隐藏图窗的纯矢量 SVG 预览并立即关闭图窗；
% 导出异常时也必须关闭对应图窗后再抛出。

if ~exist(previewFolder, 'dir')
    mkdir(previewFolder);
end

priorFigures = double(findall(0, 'Type', 'figure'));

try
    fig = plotFullPreview(cfg, boardXY, layerPaths, padA, padB, vias);
    exportFigureAndClose(fig, fullfile(previewFolder, '01_preview_full.svg'));

    fig = plotRightTabPreview(cfg, boardXY, layerPaths, padA, padB, vias);
    exportFigureAndClose(fig, fullfile(previewFolder, '02_preview_right_tab.svg'));

    fig = plotPadsViasPreview(cfg, boardXY, padA, padB, vias);
    exportFigureAndClose(fig, fullfile(previewFolder, '03_preview_pads_vias.svg'));

    for k = 1:numel(layerPaths)
        fig = plotLayerPreview(cfg, boardXY, layerPaths, padA, padB, vias, k);
        fileName = sprintf('%02d_preview_layer_L%d_%s.svg', k + 3, k, layerRole(cfg, k));
        exportFigureAndClose(fig, fullfile(previewFolder, fileName));
    end
catch ME
    closeCreatedFigures(priorFigures);
    rethrow(ME);
end

end
function fig = plotFullPreview( ...
    cfg, boardXY, layerPaths, padA, padB, vias)

titleText = sprintf( ...
    '%d-layer FPC coil | body %.0fx%.0f mm | tab %.0fx%.0f mm | %d turns/layer | %.2f/%.2f mm', ...
    cfg.layerCount, cfg.plateLength, cfg.plateWidth, ...
    cfg.tabLength, cfg.tabWidth, cfg.turnsPerLayer, ...
    cfg.traceWidth, cfg.traceSpacing);

fig = plotLayout( ...
    cfg, boardXY, layerPaths, padA, padB, vias, titleText, true, []);

end

%% =========================================================
function fig = plotRightTabPreview( ...
    cfg, boardXY, layerPaths, padA, padB, vias)

titleText = sprintf( ...
    'Right tab detail | body %.0f mm + tab %.0f mm | %d turns/layer', ...
    cfg.plateLength, cfg.tabLength, cfg.turnsPerLayer);

fig = plotLayout( ...
    cfg, boardXY, layerPaths, padA, padB, vias, titleText, true, ...
    [cfg.plateLength/2 - 8, cfg.plateLength/2 + cfg.tabLength + 2]);

ylim([-cfg.plateWidth/2 - 1, cfg.plateWidth/2 + 1]);

end

%% =========================================================
function fig = plotLayout( ...
    cfg, boardXY, layerPaths, padA, padB, vias, titleText, addLegend, xRange)

fig = figure('Name', titleText, 'Color', 'w', 'Visible', 'off');

hold on;
axis equal;
grid on;
box on;

plot([boardXY(:,1); boardXY(1,1)], ...
     [boardXY(:,2); boardXY(1,2)], ...
     '--', 'LineWidth', 1.0, 'DisplayName', 'Board outline');

for k = 1:numel(layerPaths)
    for pathIndex = 1:numel(layerPaths{k})
        path = layerPaths{k}{pathIndex};
        if pathIndex == 1
            displayName = sprintf('L%d coil', k);
        else
            displayName = sprintf('L%d output return', k);
        end
        plot(path(:,1), path(:,2), ...
            'LineWidth', 0.8, 'DisplayName', displayName);
    end
end

plot(padA(1), padA(2), 'o', ...
    'MarkerSize', 7, 'LineWidth', 1.2, 'DisplayName', 'PAD A');
text(padA(1), padA(2) + 0.6, 'PAD_A', ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', [0.85 0.33 0.10], 'Clipping', 'on');

for k = 1:numel(vias)
    plot(vias(k).xy(1), vias(k).xy(2), 's', ...
        'MarkerSize', 6, 'LineWidth', 1.0, ...
        'DisplayName', vias(k).name);
    text(vias(k).xy(1), vias(k).xy(2) + 0.45, vias(k).name, ...
        'FontSize', 7, 'HorizontalAlignment', 'center', ...
        'Color', [0.2 0.35 0.6], 'Clipping', 'on');
end

plot(padB(1), padB(2), 'o', ...
    'MarkerSize', 7, 'LineWidth', 1.2, 'DisplayName', 'PAD B');
text(padB(1), padB(2) - 0.8, 'PAD_B', ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', [0.85 0.33 0.10], 'Clipping', 'on');

% 主体左下角原点标记（内部坐标系下的主体左下角，对应用户坐标 (0,0)）
originXY = [-cfg.plateLength/2, -cfg.plateWidth/2];
plot(originXY(1), originXY(2), 'k+', 'MarkerSize', 9, 'LineWidth', 1.2);
text(originXY(1), originXY(2) - 1.1, 'body lower-left (0,0)', ...
    'FontSize', 7, 'HorizontalAlignment', 'left', 'Color', 'k', 'Clipping', 'on');

xlabel('X / mm');
ylabel('Y / mm');
title(titleText);

if ~isempty(xRange)
    xlim(xRange);
end

if addLegend
    legend('Location', 'bestoutside');
end

end

%% =========================================================
function fig = plotPadsViasPreview(cfg, boardXY, padA, padB, vias)
% Right-side placement view of external pads and vias, to scale.
% Coil paths are intentionally not drawn in this preview.
fig = figure('Name', 'Pad and via placement', 'Color', 'w', 'Visible', 'off');

try
hold on;
axis equal;
grid on;
box on;

drawBoardOutline(boardXY);

drawCircle(padA(1), padA(2), cfg.padDiameter, [0.85 0.33 0.10], 1.2, 'PAD_A');
text(padA(1), padA(2) + cfg.padDiameter/2 + 0.45, 'PAD_A', ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', [0.85 0.33 0.10], ...
    'Clipping', 'on', 'Interpreter', 'none');

drawCircle(padB(1), padB(2), cfg.padDiameter, [0.85 0.33 0.10], 1.2, 'PAD_B');
text(padB(1), padB(2) - cfg.padDiameter/2 - 0.45, 'PAD_B', ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', [0.85 0.33 0.10], ...
    'Clipping', 'on', 'Interpreter', 'none');

viaColors = lines(numel(vias));
annotationX = cfg.plateLength/2 + cfg.tabLength - 4;
annotationY = linspace(cfg.plateWidth/2 - 2, -cfg.plateWidth/2 + 1.5, numel(vias));

for v = 1:numel(vias)
    via = vias(v);
    drawCircle(via.xy(1), via.xy(2), via.padDiameter, viaColors(v, :), 1.2, via.name);
    drawCircle(via.xy(1), via.xy(2), via.drillDiameter, 'k', 0.8, sprintf('%s drill', via.name));
    if via.antipadDiameter > 0
        drawCircle(via.xy(1), via.xy(2), via.antipadDiameter, ...
            [0.6 0.2 0.2], 1.0, sprintf('%s antipad', via.name), '--');
    end
    labelText = sprintf('%s (L%d-L%d)', via.name, ...
        via.connectedLayers(1), via.connectedLayers(2));
    if via.antipadDiameter > 0 && ...
            ~isempty(setdiff(1:cfg.layerCount, via.connectedLayers))
        labelText = sprintf('%s | %s antipad', labelText, via.name);
    end
    text(annotationX, annotationY(v), labelText, ...
        'FontSize', 7, 'HorizontalAlignment', 'right', 'Interpreter', 'none', ...
        'Color', viaColors(v, :), 'Clipping', 'on');
end

xlabel('X / mm');
ylabel('Y / mm');
title('Pad / via placement (right tab)');
xlim([cfg.plateLength/2 - 8, cfg.plateLength/2 + cfg.tabLength + 2]);
ylim([-cfg.plateWidth/2 - 1, cfg.plateWidth/2 + 1]);
text(cfg.plateLength/2 - 7.5, cfg.plateWidth/2 - 0.7, ...
    'Outer: via pad | Inner: drill | Dashed: non-connected-layer antipad', ...
    'FontSize', 7, 'HorizontalAlignment', 'left', 'Interpreter', 'none', ...
    'Color', [0.2 0.2 0.2], 'Clipping', 'on');

catch ME
    close(fig);
    rethrow(ME);
end

end

%% =========================================================
function fig = plotLayerPreview(cfg, boardXY, layerPaths, padA, padB, vias, k)
% Standalone preview for one copper layer. Plated through holes appear on
% every layer: connected layers show the pad and non-connected layers show
% the antipad keepout.
role = layerRole(cfg, k);
titleText = sprintf('Layer L%d (%s)', k, role);

fig = figure('Name', titleText, 'Color', 'w', 'Visible', 'off');

try
hold on;
axis equal;
grid on;
box on;

drawBoardOutline(boardXY);

for pathIndex = 1:numel(layerPaths{k})
    path = layerPaths{k}{pathIndex};
    if pathIndex == 1
        displayName = sprintf('L%d coil', k);
    else
        displayName = sprintf('L%d output return', k);
    end
    plot(path(:, 1), path(:, 2), 'LineWidth', 0.8, 'DisplayName', displayName);
end

if k == 1
    drawCircle(padA(1), padA(2), cfg.padDiameter, [0.85 0.33 0.10], 1.2, 'PAD_A');
    drawCircle(padB(1), padB(2), cfg.padDiameter, [0.85 0.33 0.10], 1.2, 'PAD_B');
end

for v = 1:numel(vias)
    via = vias(v);
    connected = any(via.connectedLayers == k);
    if connected
        drawCircle(via.xy(1), via.xy(2), via.padDiameter, ...
            [0.2 0.35 0.6], 1.2, via.name);
    elseif strcmp(via.type, 'through_via') && via.antipadDiameter > 0
        drawCircle(via.xy(1), via.xy(2), via.antipadDiameter, ...
            [0.6 0.2 0.2], 1.0, sprintf('%s antipad', via.name), '--');
    else
        continue
    end
    drawCircle(via.xy(1), via.xy(2), via.drillDiameter, ...
        'k', 0.8, sprintf('%s drill', via.name));
end

xlabel('X / mm');
ylabel('Y / mm');
title(titleText);
xlim([min(boardXY(:, 1)) - 1, max(boardXY(:, 1)) + 1]);
ylim([min(boardXY(:, 2)) - 1, max(boardXY(:, 2)) + 1]);
legend('Location', 'bestoutside', 'Interpreter', 'none');

catch ME
    close(fig);
    rethrow(ME);
end

end

%% =========================================================
function role = layerRole(cfg, k)
% ASCII role suffix for layer preview file names.
if k == 1
    role = 'top';
elseif k == cfg.layerCount
    role = 'bottom';
else
    role = sprintf('inner%d', k - 1);
end

end

%% =========================================================
function exportFigureAndClose(fig, filename)
% Export one hidden figure as a white-background vector SVG and close it.
% The original exception is rethrown so the caller can close sibling figures.
try
    exportgraphics(fig, filename, ...
        'ContentType', 'vector', 'BackgroundColor', 'white');
catch ME
    close(fig);
    rethrow(ME);
end
close(fig);

end

%% =========================================================
function closeCreatedFigures(priorFigures)
% Close all figures that did not exist before this writePreviews call.
currentFigures = double(findall(0, 'Type', 'figure'));
newFigures = setdiff(currentFigures, priorFigures);
for k = 1:numel(newFigures)
    h = newFigures(k);
    if isgraphics(h, 'figure')
        close(h);
    end
end

end

%% =========================================================
function drawBoardOutline(boardXY)
% Dashed board outline, same visual style as the existing previews.
plot([boardXY(:, 1); boardXY(1, 1)], ...
     [boardXY(:, 2); boardXY(1, 2)], ...
     '--', 'LineWidth', 1.0, 'DisplayName', 'Board outline');

end

%% =========================================================
function drawCircle(x, y, diameter, lineColor, lineWidth, displayName, lineStyle)
% Unfilled circle of the given true diameter using only basic MATLAB graphics.
if nargin < 6
    displayName = '';
end
if nargin < 7
    lineStyle = '-';
end
radius = diameter / 2;
theta = linspace(0, 2*pi, 121);
cx = x + radius * cos(theta);
cy = y + radius * sin(theta);
if isempty(displayName)
    plot(cx, cy, 'Color', lineColor, 'LineWidth', lineWidth, 'LineStyle', lineStyle, ...
        'HandleVisibility', 'off');
else
    plot(cx, cy, 'Color', lineColor, 'LineWidth', lineWidth, 'LineStyle', lineStyle, ...
        'DisplayName', displayName);
end

end
