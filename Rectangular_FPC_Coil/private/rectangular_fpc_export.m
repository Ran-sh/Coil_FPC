function varargout = rectangular_fpc_export(operation, varargin)
%RECTANGULAR_FPC_EXPORT Private export dispatcher for the rectangular FPC runtime.
%   Supported operations:
%     'previews' -> writePreviews(cfg, boardXY, layerPaths, padA, padB, vias, previewFolder)
%     'formal_export' -> atomically publish a complete result artifact set
%     'engineering_artifacts' -> complete and verify the formal export set

switch operation
    case 'previews'
        [varargout{1:nargout}] = rectangular_fpc_preview_export( ...
            'write', varargin{:});
    case 'formal_export'
        varargout{1} = writeFormalExport(varargin{:});
    case 'engineering_artifacts'
        writeEngineeringArtifacts(varargin{:});
    case 'verify_output'
        cfg = varargin{1};
        result = varargin{2};
        outputFolder = varargin{3};
        rectangular_fpc_export_verification( ...
            'readable_artifact_set', outputFolder, cfg, result);
        rectangular_fpc_export_io('verify_file_manifest', fullfile( ...
            outputFolder, 'reports', '08_file_manifest.csv'), outputFolder);
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

outputRoot = rectangular_fpc_export_io( ...
    'canonical_absolute_folder', cfg.outputRoot);
outputFolder = fullfile(outputRoot, cfg.designName);
if ~isfolder(outputRoot)
    mkdir(outputRoot);
end
tempOutputFolder = [tempname(outputRoot), '_rectangular_fpc_staging'];
rectangular_fpc_export_io('prepare_temp_folder', tempOutputFolder);
stagingCleanup = onCleanup(@() rectangular_fpc_export_io( ...
    'remove_staging_folder', tempOutputFolder));

try
    dxfFolder = fullfile(tempOutputFolder, 'dxf');
    boardDxfFile = fullfile(dxfFolder, '00_board_outline.dxf');
    rectangular_fpc_dxf_artifacts('write_board_outline', ...
        boardDxfFile, result.boardXY, 'BOARD_OUTLINE');

    copperFileNames = cell(cfg.layerCount, 1);
    for layerIndex = 1:cfg.layerCount
        layerFolder = fullfile(dxfFolder, sprintf('L%d', layerIndex));
        if ~isfolder(layerFolder)
            mkdir(layerFolder);
        end
        copperFileNames{layerIndex} = sprintf( ...
            '%02d_copper_L%d.dxf', layerIndex, layerIndex);
        rectangular_fpc_dxf_artifacts('write_centerline', ...
            fullfile(layerFolder, copperFileNames{layerIndex}), ...
            result.layerPaths{layerIndex}, ...
            result.layers(layerIndex).name, cfg.maxVerticesPerDxfEntity);
    end

    reportsFolder = fullfile(tempOutputFolder, 'reports');
    rectangular_fpc_report_artifacts('write_coordinates', fullfile( ...
        reportsFolder, '01_pad_via_coordinates.csv'), cfg, result);
    rectangular_fpc_report_artifacts('write_design_summary', fullfile( ...
        reportsFolder, '03_design_summary.txt'), cfg, result);
    rectangular_fpc_report_artifacts('write_turn_scan', fullfile( ...
        reportsFolder, '04_turn_scan.csv'), result);
    rectangular_fpc_report_artifacts('write_validation', fullfile( ...
        reportsFolder, '05_validation_report.txt'), result.validation);

    if cfg.enablePreview
        rectangular_fpc_preview_export( ...
            'write', cfg, result.boardXY, result.layerPaths, ...
            result.pads(1).xy, result.pads(2).xy, result.vias, ...
            fullfile(tempOutputFolder, 'previews'));
    end
    rectangular_fpc_report_artifacts('write_generation_status', ...
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
function writeEngineeringArtifacts( ...
    cfg, outputFolder, boardDxfFile, copperFileNames, ...
    layerPaths, vias, manufacturing, result)
% Complete the standardized manufacturing handoff, then verify every
% manifest entry before the engine is allowed to publish the temp folder.

dxfFolder = fullfile(outputFolder, 'dxf');
reportsFolder = fullfile(outputFolder, 'reports');

rectangular_fpc_export_io('copy_required_file', boardDxfFile, ...
    fullfile(dxfFolder, '00_board_outline.dxf'));
rectangular_fpc_dxf_artifacts('write_drill_map', ...
    fullfile(dxfFolder, '00_drill_map.dxf'), vias);

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

    rectangular_fpc_export_io('copy_required_file', ...
        sourceCenterline, centerlineFile);
    rectangular_fpc_dxf_artifacts('write_physical_copper', ...
        physicalFile, layerPaths{layerIndex}, ...
        sprintf('COPPER_PHYSICAL_L%d', layerIndex), ...
        cfg.traceWidth, cfg.maxVerticesPerDxfEntity, ...
        result.pads, vias, layerIndex);
    rectangular_fpc_dxf_artifacts('write_antipad', antipadFile, ...
        sprintf('ANTIPAD_KEEP_OUT_L%d', layerIndex), vias, layerIndex);
end

rectangular_fpc_report_artifacts('write_layer_mapping', ...
    fullfile(reportsFolder, '02_layer_mapping.csv'), cfg);
rectangular_fpc_report_artifacts('write_manufacturing_check', ...
    fullfile(reportsFolder, '06_manufacturing_check.csv'), manufacturing);
rectangular_fpc_report_artifacts('write_fabrication_notes', ...
    fullfile(reportsFolder, '07_fabrication_notes.txt'), cfg, manufacturing);

rectangular_fpc_export_verification( ...
    'readable_artifact_set', outputFolder, cfg, result);
manifestPath = fullfile(reportsFolder, '08_file_manifest.csv');
rectangular_fpc_export_io('write_file_manifest', manifestPath, outputFolder);
rectangular_fpc_export_io('verify_file_manifest', manifestPath, outputFolder);

end
