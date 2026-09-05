function varargout = rectangular_fpc_report_artifacts(operation, varargin)
%RECTANGULAR_FPC_REPORT_ARTIFACTS Write textual and tabular export reports.

switch operation
    case 'write_coordinates'
        writeCoordinateReport(varargin{:});
    case 'write_design_summary'
        writeDesignSummaryReport(varargin{:});
    case 'write_turn_scan'
        writeTurnScanReport(varargin{:});
    case 'scan_failure_code'
        varargout{1} = scanFailureCode(varargin{:});
    case 'write_validation'
        writeValidationReport(varargin{:});
    case 'write_generation_status'
        writeGenerationStatusFile(varargin{:});
    case 'write_layer_mapping'
        writeLayerMapping(varargin{:});
    case 'write_manufacturing_check'
        writeManufacturingCheck(varargin{:});
    case 'write_fabrication_notes'
        writeFabricationNotes(varargin{:});
    otherwise
        error('RectangularFPC:UnknownExportOperation', ...
            'Unknown report artifact operation: %s', operation);
end

end

%% =========================================================
function writeCoordinateReport(filename, cfg, result)

fid = rectangular_fpc_export_io('open_utf8_file', filename, 'pad/via coordinate CSV');
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
        rectangular_fpc_export_io('csv_text', via.name), xyUser(1), xyUser(2), via.xy(1), via.xy(2), ...
        via.fromLayer, via.toLayer, rectangular_fpc_export_io('csv_text', via.type), ...
        rectangular_fpc_export_io('csv_text', via.placementRegion), rectangular_fpc_export_io('csv_text', via.placementMode));
    fprintf(fid, '%.9f,%.9f,%.9f,%.9f,%s\n', ...
        via.padDiameter, via.drillDiameter, annularRing, ...
        via.antipadDiameter, rectangular_fpc_export_io('csv_text', via.role));
end
writePadCoordinateRow(fid, result.pads(2), cfg, 'Top-layer output terminal');
clear cleanup;

end
%% =========================================================
function writePadCoordinateRow(fid, pad, cfg, description)

xyUser = rectangular_fpc_geometry('internal_to_user', pad.xy, cfg);
fprintf(fid, '%s,%.6f,%.6f,%.6f,%.6f,L1,external,pad,', ...
    rectangular_fpc_export_io('csv_text', pad.name), xyUser(1), xyUser(2), pad.xy(1), pad.xy(2));
fprintf(fid, 'EXTERNAL_PAD,fixed,%.9f,0,0,0,%s\n', ...
    pad.diameter, rectangular_fpc_export_io('csv_text', description));

end

%% =========================================================
function writeDesignSummaryReport(filename, cfg, result)

fid = rectangular_fpc_export_io('open_utf8_file', filename, 'design summary');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Rectangular FPC coil design summary\n');
fprintf(fid, '===================================\n');
fprintf(fid, 'Design: %s\n', cfg.designName);
fprintf(fid, 'Layers / turns per layer: %d / %d\n', ...
    result.layerCount, result.turnsPerLayer);
fprintf(fid, 'Body size: %.12g x %.12g mm\n', cfg.plateLength, cfg.plateWidth);
fprintf(fid, 'Right tab: %.12g x %.12g mm\n', cfg.tabLength, cfg.tabWidth);
fprintf(fid, 'Trace width / spacing: %.12g / %.12g mm\n', ...
    cfg.traceWidth, cfg.traceSpacing);
fprintf(fid, 'Total trace length: %.12g mm\n', result.totalTraceLengthMm);
fprintf(fid, 'Estimated DC resistance: %.12g ohm\n', ...
    result.estimatedDcResistanceOhm);
fprintf(fid, 'Fully validated maximum turns: %d\n', ...
    result.fullyValidatedMaximumTurns);
fprintf(fid, 'Recommended turns: %d\n', result.recommendedTurns);
fprintf(fid, 'Minimum copper spacing: %.12g mm\n', result.minCopperSpacing);
fprintf(fid, 'Manufacturing status: %s\n', result.manufacturing.status);
fprintf(fid, 'Manufacturing applicability: %s\n', ...
    result.manufacturing.applicability);
for layerIndex = 1:cfg.layerCount
    fprintf(fid, 'L%d trace length: %.12g mm\n', ...
        layerIndex, result.layerLengthMm(layerIndex));
end
clear cleanup;

end

%% =========================================================
function writeTurnScanReport(filename, result)

fid = rectangular_fpc_export_io('open_utf8_file', filename, 'turn scan CSV');
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
        rectangular_fpc_export_io('csv_text', failureCode), rectangular_fpc_export_io('csv_text', scan.failureReason));
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

fid = rectangular_fpc_export_io('open_utf8_file', filename, 'validation report');
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

fid = rectangular_fpc_export_io('open_utf8_file', filename, 'generation status');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Rectangular FPC generation status\n');
fprintf(fid, '=================================\n');
fprintf(fid, 'Status: SUCCESS\n');
fprintf(fid, 'SchemaVersion: 2\n');
fprintf(fid, 'PublicationId: %s\n', rectangular_fpc_export_io('unique_token'));
fprintf(fid, 'Generated: %s\n', char(datetime('now', ...
    'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'Design: %s\n', cfg.designName);
fprintf(fid, 'LayerCount: %d\n', cfg.layerCount);
fprintf(fid, 'PreviewEnabled: %d\n', cfg.enablePreview);
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
function writeLayerMapping(filename, cfg)

fid = rectangular_fpc_export_io('open_utf8_file', filename, 'layer mapping CSV');
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

fid = rectangular_fpc_export_io('open_utf8_file', filename, 'manufacturing check CSV');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, ['check_id,status,measured_mm,limit_mm,margin_mm,', ...
    'code,message\n']);
for checkIndex = 1:numel(manufacturing.checks)
    check = manufacturing.checks(checkIndex);
    fprintf(fid, '%s,%s,%.17g,%.17g,%.17g,%s,%s\n', ...
        rectangular_fpc_export_io('csv_text', check.id), rectangular_fpc_export_io('csv_text', check.status), check.measuredMm, ...
        check.limitMm, check.marginMm, rectangular_fpc_export_io('csv_text', check.code), ...
        rectangular_fpc_export_io('csv_text', check.message));
end
clear cleanup;

end

%% =========================================================
function writeFabricationNotes(filename, cfg, manufacturing)

fid = rectangular_fpc_export_io('open_utf8_file', filename, 'fabrication notes');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Rectangular FPC fabrication notes\n');
fprintf(fid, '=================================\n');
fprintf(fid, 'Design: %s\n', cfg.designName);
fprintf(fid, 'Layer count: %d\n', cfg.layerCount);
fprintf(fid, 'Copper: 1 oz nominal (%.12g mm)\n', cfg.copperThickness);
fprintf(fid, 'Trace width / spacing: %.12g / %.12g mm\n', ...
    cfg.traceWidth, cfg.traceSpacing);
fprintf(fid, 'Manufacturing profile: %s (%s)\n', ...
    manufacturing.profile, manufacturing.tier);
fprintf(fid, 'Requested profile: %s\n', manufacturing.requestedProfile);
fprintf(fid, 'Base profile: %s\n', manufacturing.baseProfile);
fprintf(fid, 'Rule classification: %s\n', ...
    manufacturing.ruleClassification);
fprintf(fid, 'Profile checked on: %s\n', manufacturing.sourceCheckedOn);
fprintf(fid, 'Applicability: %s\n', manufacturing.applicability);
fprintf(fid, 'Verified: %d\n', manufacturing.verified);
baseRuleNames = fieldnames(manufacturing.baseRules);
for ruleIndex = 1:numel(baseRuleNames)
    ruleName = baseRuleNames{ruleIndex};
    fprintf(fid, 'BaseRule.%s: %.17g\n', ...
        ruleName, manufacturing.baseRules.(ruleName));
    fprintf(fid, 'EffectiveRule.%s: %.17g\n', ...
        ruleName, manufacturing.rules.(ruleName));
end
overrideNames = fieldnames(manufacturing.ruleOverrides);
fprintf(fid, 'Rule override count: %d\n', numel(overrideNames));
for overrideIndex = 1:numel(overrideNames)
    ruleName = overrideNames{overrideIndex};
    fprintf(fid, 'RuleOverride.%s: %.17g\n', ...
        ruleName, manufacturing.ruleOverrides.(ruleName));
end
fprintf(fid, ['Publication read protocol: call ', ...
    'rectangular_fpc_read_committed(outputPath, reader) so the complete ', ...
    'read holds the same exclusive lock used for replacement.\n']);
for sourceIndex = 1:numel(manufacturing.sourceUrls)
    fprintf(fid, 'Rule source: %s\n', manufacturing.sourceUrls{sourceIndex});
end
fprintf(fid, ['Import the physical-copper DXF when the EDA tool honors ', ...
    'LWPOLYLINE constant width; otherwise import the centerline DXF and ', ...
    'assign %.12g mm trace width.\n'], cfg.traceWidth);
fprintf(fid, ['The drill map is a positional reference. Create plated ', ...
    'vias and pads from 01_pad_via_coordinates.csv in the target EDA tool.\n']);
if ismember(cfg.layerCount, [2, 4])
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
