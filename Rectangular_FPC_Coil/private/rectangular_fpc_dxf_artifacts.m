function rectangular_fpc_dxf_artifacts(operation, varargin)
%RECTANGULAR_FPC_DXF_ARTIFACTS Write and verify DXF manufacturing artifacts.

switch operation
    case 'write_board_outline'
        writeBoardOutlineDxf(varargin{:});
    case 'write_centerline'
        writeCenterlineDxf(varargin{:});
    case 'write_drill_map'
        filename = varargin{1};
        vias = varargin{2};
        writeCircleDxf(filename, 'DRILL_REFERENCE', vias, ...
            @(via) via.drillDiameter > 0, @(via) via.drillDiameter);
    case 'write_physical_copper'
        writePhysicalCopperDxf(varargin{:});
    case 'write_antipad'
        filename = varargin{1};
        layerName = varargin{2};
        vias = varargin{3};
        layerIndex = varargin{4};
        writeCircleDxf(filename, layerName, vias, @antipadApplies, ...
            @(via) via.antipadDiameter, layerIndex);
    case 'verify_all'
        verifyAllDxfArtifacts(varargin{:});
    otherwise
        error('RectangularFPC:UnknownExportOperation', ...
            'Unknown DXF artifact operation: %s', operation);
end

end

%% =========================================================
function verifyAllDxfArtifacts(outputFolder, cfg, result)

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

    physicalCircles = expectedPhysicalCircles(result, layerIndex);
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

end

%% =========================================================
function writeBoardOutlineDxf(filename, boardXY, layerName)

fid = rectangular_fpc_export_io('open_ascii_file', filename, 'board-outline DXF');
cleanup = onCleanup(@() fclose(fid));
writeDxfHeader(fid, layerName);
writePolylineEntity(fid, boardXY, layerName, true, NaN);
writeDxfFooter(fid);
clear cleanup;

end

%% =========================================================
function writeCenterlineDxf(filename, paths, layerName, maxVertices)

fid = rectangular_fpc_export_io('open_ascii_file', filename, 'centerline DXF');
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
function applies = antipadApplies(via, layerIndex)

applies = via.antipadDiameter > 0 && ...
    ~ismember(layerIndex, via.connectedLayers);

end

%% =========================================================
function writePhysicalCopperDxf( ...
    filename, paths, layerName, traceWidth, maxVertices, pads, vias, layerIndex)

fid = rectangular_fpc_export_io('open_ascii_file', filename, 'DXF');
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

fid = rectangular_fpc_export_io('open_ascii_file', filename, 'DXF');
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
function readbackError(filename, contract)

error('RectangularFPC:ExportReadbackFailed', ...
    'Readback failed for %s (%s).', filename, contract);

end
