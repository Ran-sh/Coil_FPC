function tests = test_rectangular_fpc_export_contracts
% Formal artifact readback contracts that exercise existing output trees.
tests = functiontests(localfunctions);
end

function testCoordinateCsvManufacturingFieldsAreReadBack(testCase)
paths = makeFormalOutput(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
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
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
filename = fullfile(paths.result.outputPath, 'previews', ...
    '01_preview_full.svg');
invalidDocuments = {'<svg', '<svg xmlns="http://www.w3.org/2000/svg"></svg>'};
for documentIndex = 1:numel(invalidDocuments)
    fid = fopen(filename, 'w');
    fileCleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', invalidDocuments{documentIndex});
    clear fileCleanup;
    verifyError(testCase, @() verifyExistingOutput(paths), ...
        'RectangularFPC:ExportReadbackFailed');
end
end

function paths = makeFormalOutput(enablePreview)
paths.root = tempname;
outputRoot = fullfile(paths.root, 'output');
paths.result = rectangular_fpc_main(struct( ...
    'outputRoot', outputRoot, ...
    'designName', 'export_contract', ...
    'turnsPerLayer', 1, ...
    'enablePreview', enablePreview, ...
    'enableFigure', false));
paths.cfg = paths.result.config;
paths.cfg.designName = sprintf('%s_%s', ...
    paths.result.logicalDesignName, paths.result.runTimestamp);
end

function verifyExistingOutput(paths)
rectangular_fpc_export('verify_output', paths.cfg, paths.result, ...
    paths.result.outputPath);
end

function data = setNumeric(data, name, row, delta)
data.(name)(row) = data.(name)(row) + delta;
end

function data = setText(data, name, row, value)
data.(name)(row) = value;
end

function removeTree(root)
if isfolder(root)
    rmdir(root, 's');
end
end
