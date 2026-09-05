function tests = test_rectangular_fpc_engineering
% Engineering-contract tests for the renamed rectangular FPC project.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testsFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(testsFolder);
testCase.TestData.originalPath = path;
addpath(projectRoot);
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testNewConfigurationSurface(testCase)
cfg = rectangular_fpc_default_config();

verifyFalse(testCase, cfg.analysisOnly);
verifyEqual(testCase, cfg.manufacturingProfile, 'jlc_fpc_1oz');
verifyEqual(testCase, cfg.manufacturingTier, 'standard');
verifyEqual(testCase, cfg.manufacturingRuleOverrides, struct());
verifyEqual(testCase, cfg.designName, 'rectangular_fpc_4layer');
verifyTrue(testCase, endsWith(strrep(cfg.outputRoot, '\', '/'), ...
    '/rectangular_fpc_output'));
end

function testAnalysisOnlyHasNoFilesystemSideEffects(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));

result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'outputRoot', outputRoot, ...
    'designName', 'analysis_contract', ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));

verifyFalse(testCase, isfolder(outputRoot));
verifyEqual(testCase, result.outputPath, '');
verifyEqual(testCase, result.outputFolder, '');
verifyEqual(testCase, result.runTimestamp, '');
verifyTrue(testCase, result.validation.passed);
verifyTrue(testCase, result.manufacturing.verified);
verifyEqual(testCase, result.manufacturing.applicability, 'SUPPORTED');
verifyEqual(testCase, result.totalTraceLengthMm, result.totalLengthMm, 'AbsTol', 1e-12);
verifyEqual(testCase, result.estimatedDcResistanceOhm, result.totalResistanceOhm, 'AbsTol', 1e-12);
verifyEqual(testCase, result.config.designName, 'analysis_contract');
verifyEqual(testCase, result.boardDxfFile, '');
verifyEqual(testCase, result.drillMapDxfFile, '');
verifyEqual(testCase, result.layerMappingFile, '');
verifyEqual(testCase, result.manufacturingReport, '');
verifyEqual(testCase, result.fabricationNotes, '');
verifyEqual(testCase, result.fileManifest, '');
verifyTrue(testCase, all(arrayfun(@(layer) isempty(layer.dxfFile), ...
    result.layers)));

clear cleanup;
end

function testSixLayerAnalysisIsExplicitlyUnverified(testCase)
result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 6, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));

verifyFalse(testCase, result.manufacturing.verified);
verifyEqual(testCase, result.manufacturing.applicability, ...
    'UNVERIFIED_LAYER_COUNT');
verifyTrue(testCase, result.manufacturing.exportAllowed);
verifyNotEmpty(testCase, result.manufacturing.warnings);
verifyEqual(testCase, result.manufacturing.status, 'UNVERIFIED');
seriesVias = result.vias(~strcmp({result.vias.name}, 'VOUT'));
verifyEqual(testCase, {seriesVias.type}, ...
    repmat({'adjacent_layer_via'}, 1, numel(seriesVias)));
viaTechnology = result.manufacturing.checks( ...
    strcmp({result.manufacturing.checks.id}, 'VIA_TECHNOLOGY'));
verifyEqual(testCase, viaTechnology.status, 'WARN');
verifyEqual(testCase, viaTechnology.code, 'UNVERIFIED_VIA_TECHNOLOGY');
end

function testRecommendedTurnsUseEffectiveConfigInResultAndReports(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));
result = rectangular_fpc_main(struct( ...
    'outputRoot', outputRoot, ...
    'designName', 'recommended_turn_contract', ...
    'useRecommendedTurns', true, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));

verifyEqual(testCase, result.config.turnsPerLayer, result.turnsPerLayer);
verifyEqual(testCase, result.requestedConfig.turnsPerLayer, 1);
verifyGreaterThan(testCase, result.turnsPerLayer, 1);
verifyTrue(testCase, contains(fileread(result.summaryFile), sprintf( ...
    'Layers / turns per layer: %d / %d', ...
    result.layerCount, result.turnsPerLayer)));
verifyTrue(testCase, contains(fileread(fullfile( ...
    result.outputPath, 'generation_status.txt')), sprintf( ...
    'TurnsPerLayer: %d', result.turnsPerLayer)));

clear cleanup;
end

function testPublicInvalidConfigValuesUseRectangularIdentifier(testCase)
cases = { ...
    struct('turnsPerLayer', [1, 2]), ...
    struct('traceWidth', NaN), ...
    struct('plateLength', "invalid"), ...
    struct('coilOuterCornerRadiusMode', 'manual', ...
        'coilOuterCornerRadius', [1, 2]), ...
    struct('viaClearanceSeverity', 42), ...
    struct('outputViaType', 42), ...
    struct('minSpiralCornerRadius', -1), ...
    struct('minSpiralCornerRadius', 0)};
for caseIndex = 1:numel(cases)
    overrides = cases{caseIndex};
    overrides.analysisOnly = true;
    overrides.enablePreview = false;
    overrides.enableFigure = false;
    verifyError(testCase, @() rectangular_fpc_main(overrides), ...
        'RectangularFPC:InvalidConfigValue');
end
end

function testAnalysisOnlyIsValidatedBeforeInternalAnalysisOverride(testCase)
invalidValues = {2, [true, false], "true"};
for valueIndex = 1:numel(invalidValues)
    verifyError(testCase, @() rectangular_fpc_main(struct( ...
        'analysisOnly', invalidValues{valueIndex}, ...
        'enablePreview', false, ...
        'enableFigure', false)), ...
        'RectangularFPC:InvalidConfigValue');
end
result = rectangular_fpc_main(struct( ...
    'analysisOnly', 1, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));
verifyTrue(testCase, result.config.analysisOnly);
verifyClass(testCase, result.config.analysisOnly, 'logical');
end

function testLegacyWrappersForwardWithDeprecationWarning(testCase)
lastwarn('');
legacyCfg = fpc_coil_default_config(struct('analysisOnly', true));
[~, warningId] = lastwarn;

verifyEqual(testCase, warningId, 'RectangularFPC:DeprecatedAPI');
verifyTrue(testCase, legacyCfg.analysisOnly);

lastwarn('');
legacyResult = fpc_coil_main(struct( ...
    'analysisOnly', true, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));
[~, warningId] = lastwarn;

verifyEqual(testCase, warningId, 'RectangularFPC:DeprecatedAPI');
verifyEqual(testCase, legacyResult.outputPath, '');
end

function testLegacyAndNewAnalysisResultsAreEquivalent(testCase)
overrides = struct( ...
    'analysisOnly', true, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false);
newResult = rectangular_fpc_main(overrides);
warningState = warning('off', 'RectangularFPC:DeprecatedAPI');
cleanup = onCleanup(@() warning(warningState));
legacyResult = fpc_coil_main(overrides);

verifyEqual(testCase, legacyResult.boardXY, newResult.boardXY, 'AbsTol', 1e-12);
verifyEqual(testCase, legacyResult.totalLengthMm, newResult.totalLengthMm, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, legacyResult.totalResistanceOhm, ...
    newResult.totalResistanceOhm, 'AbsTol', 1e-12);
verifyEqual(testCase, legacyResult.validation, newResult.validation);
verifyEqual(testCase, legacyResult.manufacturing, newResult.manufacturing);
clear cleanup;
end

function testManufacturingProfilesOverridesAndAnalysisFailure(testCase)
twoLayer = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 2, 'turnsPerLayer', 1, ...
    'enablePreview', false, 'enableFigure', false));
verifyTrue(testCase, twoLayer.manufacturing.verified);
verifyEqual(testCase, twoLayer.manufacturing.rules.minViaDrillMm, 0.30);
verifyEqual(testCase, twoLayer.manufacturing.rules.minViaPadMm, 0.55);

extreme = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 4, 'turnsPerLayer', 1, ...
    'viaDrillDiameter', 0.15, 'viaPadDiameter', 0.35, ...
    'manufacturingTier', 'extreme', ...
    'enablePreview', false, 'enableFigure', false));
verifyTrue(testCase, extreme.manufacturing.verified);
verifyEqual(testCase, extreme.manufacturing.rules.minViaDrillMm, 0.15);
verifyEqual(testCase, extreme.manufacturing.rules.minViaPadMm, 0.35);
verifyEqual(testCase, extreme.manufacturing.status, 'WARN');

failed = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'turnsPerLayer', 1, ...
    'manufacturingRuleOverrides', struct('minTraceWidthMm', 0.30), ...
    'enablePreview', false, 'enableFigure', false));
verifyFalse(testCase, failed.manufacturing.exportAllowed);
verifyFalse(testCase, failed.manufacturing.verified);
verifyEqual(testCase, failed.manufacturing.status, 'FAIL');
verifyNotEmpty(testCase, failed.manufacturing.failures);
end

function testQualifiedFourLayerSeriesViasAreStaggered(testCase)
result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 4, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));
seriesVias = result.vias(strcmp( ...
    {result.vias.role}, 'series_interconnect'));
seriesXY = vertcat(seriesVias.xy);
verifyGreaterThan(testCase, range(seriesXY(:, 2)), ...
    result.config.geometryTolerance);
stagger = result.manufacturing.checks(strcmp( ...
    {result.manufacturing.checks.id}, 'VIA_STAGGER'));
assertNumElements(testCase, stagger, 1);
verifyEqual(testCase, stagger.status, 'PASS');
verifyTrue(testCase, result.manufacturing.verified);
end

function testCollinearManualSeriesViasFailQualifiedManufacturing(testCase)
result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 4, ...
    'turnsPerLayer', 1, ...
    'viaPlacementMode', 'manual', ...
    'manualSeriesViaXY', [25, 6; 82, 6; 55, 6], ...
    'enablePreview', false, ...
    'enableFigure', false));
stagger = result.manufacturing.checks(strcmp( ...
    {result.manufacturing.checks.id}, 'VIA_STAGGER'));
assertNumElements(testCase, stagger, 1);
verifyEqual(testCase, stagger.status, 'FAIL');
verifyEqual(testCase, stagger.code, 'VIA_ROW_COLLINEAR');
verifyFalse(testCase, result.manufacturing.verified);
verifyFalse(testCase, result.manufacturing.exportAllowed);
end

function testOfficialManufacturingRuleConstants(testCase)
% The public manufacturing report must preserve the exact audited JLC FPC
% constants instead of silently rounding or replacing them with estimates.
standard = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 4, 'turnsPerLayer', 1, ...
    'manufacturingTier', 'standard', ...
    'enablePreview', false, 'enableFigure', false));
rules = standard.manufacturing.rules;

verifyEqual(testCase, rules.minTraceWidthMm, 0.102);
verifyEqual(testCase, rules.minTraceSpacingMm, 0.102);
verifyEqual(testCase, rules.minViaDrillMm, 0.30);
verifyEqual(testCase, rules.minViaPadMm, 0.55);
verifyEqual(testCase, rules.minViaPadDrillDifferenceMm, 0.20);
verifyEqual(testCase, rules.recommendedViaPadDrillDifferenceMm, 0.25);
verifyEqual(testCase, rules.minPadToTraceMm, 0.20);
verifyEqual(testCase, rules.minViaToBoardMm, 0.50);
verifyEqual(testCase, standard.manufacturing.requestedProfile, ...
    'jlc_fpc_1oz');
verifyEqual(testCase, standard.manufacturing.sourceCheckedOn, '2026-09-04');
verifyEqual(testCase, standard.manufacturing.profile, 'jlc_fpc_1oz');
verifyEqual(testCase, standard.manufacturing.baseProfile, 'jlc_fpc_1oz');
verifyEqual(testCase, standard.manufacturing.ruleClassification, 'OFFICIAL');
verifyEqual(testCase, standard.manufacturing.baseRules, rules);
verifyEqual(testCase, standard.manufacturing.ruleOverrides, struct());

twoLayerExtreme = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 2, 'turnsPerLayer', 1, ...
    'manufacturingTier', 'extreme', ...
    'enablePreview', false, 'enableFigure', false));
verifyEqual(testCase, twoLayerExtreme.manufacturing.rules.minViaDrillMm, 0.10);
verifyEqual(testCase, twoLayerExtreme.manufacturing.rules.minViaPadMm, 0.30);

fourLayerExtreme = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 4, 'turnsPerLayer', 1, ...
    'viaDrillDiameter', 0.15, 'viaPadDiameter', 0.35, ...
    'manufacturingTier', 'extreme', ...
    'enablePreview', false, 'enableFigure', false));
verifyEqual(testCase, fourLayerExtreme.manufacturing.rules.minViaDrillMm, 0.15);
verifyEqual(testCase, fourLayerExtreme.manufacturing.rules.minViaPadMm, 0.35);
end

function testRelaxedRuleOverrideIsCustomAndUnverified(testCase)
override = struct('minTraceWidthMm', 0.10);
result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 4, 'turnsPerLayer', 1, ...
    'manufacturingRuleOverrides', override, ...
    'enablePreview', false, 'enableFigure', false));
report = result.manufacturing;

verifyEqual(testCase, report.requestedProfile, 'jlc_fpc_1oz');
verifyEqual(testCase, report.profile, 'custom');
verifyEqual(testCase, report.baseProfile, 'jlc_fpc_1oz');
verifyEqual(testCase, report.ruleClassification, 'CUSTOM_RELAXED');
verifyEqual(testCase, report.applicability, 'CUSTOM_RULES');
verifyEqual(testCase, report.baseRules.minTraceWidthMm, 0.102);
verifyEqual(testCase, report.rules.minTraceWidthMm, 0.10);
verifyEqual(testCase, report.ruleOverrides, override);
verifyFalse(testCase, report.verified);
verifyTrue(testCase, report.exportAllowed);
verifyEqual(testCase, report.status, 'UNVERIFIED');
end

function testUnsupportedLayerCountRemainsPrimaryWithRelaxedRules(testCase)
override = struct('minTraceWidthMm', 0.10);
for layerCount = [6, 8]
    result = rectangular_fpc_main(struct( ...
        'analysisOnly', true, ...
        'layerCount', layerCount, ...
        'turnsPerLayer', 1, ...
        'manufacturingRuleOverrides', override, ...
        'enablePreview', false, ...
        'enableFigure', false));
    report = result.manufacturing;
    verifyEqual(testCase, report.applicability, ...
        'UNVERIFIED_LAYER_COUNT');
    verifyEqual(testCase, report.profile, 'custom');
    verifyEqual(testCase, report.ruleClassification, 'CUSTOM_RELAXED');
    verifyFalse(testCase, report.verified);
    verifyTrue(testCase, report.exportAllowed);
    verifyEqual(testCase, report.status, 'UNVERIFIED');
    warningText = strjoin(report.warnings, newline);
    verifyTrue(testCase, contains(warningText, ...
        'Relaxed manufacturing override'));
    verifyTrue(testCase, contains(warningText, ...
        sprintf('Layer count %d', layerCount)));
end
end

function testConservativeRuleOverrideRetainsOfficialVerification(testCase)
override = struct('minTraceWidthMm', 0.15);
result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 4, 'turnsPerLayer', 1, ...
    'manufacturingRuleOverrides', override, ...
    'enablePreview', false, 'enableFigure', false));
report = result.manufacturing;

verifyEqual(testCase, report.requestedProfile, 'jlc_fpc_1oz');
verifyEqual(testCase, report.profile, 'jlc_fpc_1oz');
verifyEqual(testCase, report.baseProfile, 'jlc_fpc_1oz');
verifyEqual(testCase, report.ruleClassification, 'OFFICIAL_CONSERVATIVE');
verifyEqual(testCase, report.applicability, 'SUPPORTED');
verifyEqual(testCase, report.baseRules.minTraceWidthMm, 0.102);
verifyEqual(testCase, report.rules.minTraceWidthMm, 0.15);
verifyEqual(testCase, report.ruleOverrides, override);
verifyTrue(testCase, report.verified);
verifyTrue(testCase, report.exportAllowed);
end

function testCopperToBoardUsesMeasuredFinalGeometry(testCase)
% H2 契约：COPPER_TO_BOARD 必须来自最终几何实测（走线 + PAD + 过孔焊环），
% 而不是配置值 edgeClearance。配置允许下限附近的 PAD 内缩必须被制造判定拦截。
defaults = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 2, 'turnsPerLayer', 1, ...
    'enablePreview', false, 'enableFigure', false));
defaultRow = defaults.manufacturing.checks( ...
    strcmp({defaults.manufacturing.checks.id}, 'COPPER_TO_BOARD'));
assertNumElements(testCase, defaultRow, 1);
verifyEqual(testCase, defaultRow.measuredMm, ...
    defaults.validation.minCopperToBoardMm, 'AbsTol', 1e-9);
verifyGreaterThanOrEqual(testCase, defaultRow.measuredMm, ...
    defaults.manufacturing.rules.minCopperToBoardMm - 1e-9);
verifyTrue(testCase, defaults.manufacturing.verified);

% padTipInset 取配置允许下限：焊盘铜边到板边实测约 0.20 mm (< 0.30)，
% 配置校验与既有几何检查都放行，但制造资格必须 FAIL 并禁止导出。
adversarial = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 2, 'turnsPerLayer', 1, ...
    'padTipInset', defaults.config.padDiameter / 2 + defaults.config.padTipMargin, ...
    'enablePreview', false, 'enableFigure', false));
adversarialRow = adversarial.manufacturing.checks( ...
    strcmp({adversarial.manufacturing.checks.id}, 'COPPER_TO_BOARD'));
assertNumElements(testCase, adversarialRow, 1);
verifyLessThan(testCase, adversarialRow.measuredMm, ...
    adversarial.manufacturing.rules.minCopperToBoardMm);
verifyEqual(testCase, adversarialRow.measuredMm, ...
    adversarial.validation.minCopperToBoardMm, 'AbsTol', 1e-9);
verifyFalse(testCase, adversarial.manufacturing.verified);
verifyFalse(testCase, adversarial.manufacturing.exportAllowed);
verifyEqual(testCase, adversarial.manufacturing.status, 'FAIL');
end

function testSupportedManufacturingUsesPlatedThroughViasAndAntipads(testCase)
for layerCount = [2, 4]
    result = rectangular_fpc_main(struct( ...
        'analysisOnly', true, ...
        'layerCount', layerCount, ...
        'turnsPerLayer', 1, ...
        'enablePreview', false, ...
        'enableFigure', false));
    cfg = result.config;

    verifyTrue(testCase, result.manufacturing.verified);
    viaTechnology = result.manufacturing.checks( ...
        strcmp({result.manufacturing.checks.id}, 'VIA_TECHNOLOGY'));
    assertNumElements(testCase, viaTechnology, 1);
    verifyEqual(testCase, viaTechnology.status, 'PASS');
    verifyEqual(testCase, {result.vias.type}, ...
        repmat({'through_via'}, 1, numel(result.vias)));
    verifyGreaterThanOrEqual(testCase, cfg.viaToCopperClearance, ...
        result.manufacturing.rules.minViaToTraceMm);
    verifyGreaterThanOrEqual(testCase, cfg.outputViaToCopperClearance, ...
        result.manufacturing.rules.minViaToTraceMm);
    verifyEqual(testCase, cfg.viaToBoardClearance, 0.50);
    verifyEqual(testCase, cfg.outputViaToBoardClearance, 0.50);
    viaToTrace = result.manufacturing.checks( ...
        strcmp({result.manufacturing.checks.id}, 'VIA_TO_TRACE'));
    assertNumElements(testCase, viaToTrace, 1);
    verifyNotEqual(testCase, viaToTrace.status, 'FAIL');
    viaToBoard = result.manufacturing.checks( ...
        strcmp({result.manufacturing.checks.id}, 'VIA_TO_BOARD'));
    assertNumElements(testCase, viaToBoard, 1);
    verifyEqual(testCase, viaToBoard.measuredMm, ...
        result.validation.minViaToBoardMm, 'AbsTol', 1e-9);
    verifyGreaterThanOrEqual(testCase, viaToBoard.measuredMm, ...
        result.manufacturing.rules.minViaToBoardMm - ...
        cfg.geometryTolerance);
    verifyNotEqual(testCase, viaToBoard.status, 'FAIL');

    for viaIndex = 1:numel(result.vias)
        via = result.vias(viaIndex);
        nonConnectedLayers = setdiff(1:layerCount, via.connectedLayers);
        if isempty(nonConnectedLayers)
            continue
        end
        verifyGreaterThanOrEqual(testCase, via.antipadDiameter, ...
            via.padDiameter + 2 * ...
            result.manufacturing.rules.minViaToTraceMm - ...
            cfg.geometryTolerance);
    end
end
end

function testDefaultTopologyHasPhysicalEndpointConnections(testCase)
for layerCount = [2, 4]
    result = rectangular_fpc_main(struct( ...
        'analysisOnly', true, ...
        'layerCount', layerCount, ...
        'turnsPerLayer', 1, ...
        'enablePreview', false, ...
        'enableFigure', false));
    verifyTopologyContract(testCase, result);
end
end

function testManualFallbackNeverReturnsDisconnectedTopology(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));
overrides = struct( ...
    'analysisOnly', true, ...
    'outputRoot', outputRoot, ...
    'designName', 'manual_fallback_contract', ...
    'layerCount', 4, ...
    'turnsPerLayer', 1, ...
    'minSpiralCornerRadius', 4.7, ...
    'viaPlacementMode', 'manual', ...
    'manualSeriesViaXY', [25, 6; 82, 6; 55, 6], ...
    'outputViaPlacementMode', 'manual', ...
    'manualOutputViaXY', [87, 4.7], ...
    'requireSmoothLeadTransitions', false, ...
    'enablePreview', false, ...
    'enableFigure', false);

[analysisSucceeded, result, errorId] = invokeRectangular(overrides);
if analysisSucceeded
    verifyTrue(testCase, result.passed);
    verifyTrue(testCase, result.validation.passed);
    verifyTrue(testCase, result.validation.topologyPassed);
    verifyTrue(testCase, result.manufacturing.verified);
    verifyTrue(testCase, result.manufacturing.exportAllowed);
    verifyTopologyContract(testCase, result);
else
    verifyTrue(testCase, ismember(errorId, { ...
        'RectangularFPC:RoutingFailed', ...
        'RectangularFPC:ValidationFailed'}), ...
        sprintf('Unexpected analysis error identifier: %s', errorId));
end
verifyFalse(testCase, isfolder(outputRoot));

overrides.analysisOnly = false;
[formalSucceeded, formalResult, errorId] = invokeRectangular(overrides);
if analysisSucceeded
    verifyTrue(testCase, formalSucceeded, ...
        'A connected manual fallback should remain exportable.');
    if formalSucceeded
        verifyTrue(testCase, formalResult.validation.topologyPassed);
        verifyTopologyContract(testCase, formalResult);
        verifyTrue(testCase, isfolder(formalResult.outputPath));
    end
else
    verifyFalse(testCase, formalSucceeded);
    verifyTrue(testCase, ismember(errorId, { ...
        'RectangularFPC:RoutingFailed', ...
        'RectangularFPC:ValidationFailed'}), ...
        sprintf('Unexpected formal-export error identifier: %s', errorId));
end
if isfolder(outputRoot)
    formal = dir(fullfile(outputRoot, 'manual_fallback_contract_*'));
    if analysisSucceeded
        verifyNumElements(testCase, formal([formal.isdir]), 1);
    else
        verifyEmpty(testCase, formal([formal.isdir]));
    end
end

clear cleanup;
end

function testLayerCountAboveEightIsRejectedEvenWhenConfiguredMaximumIsRaised(testCase)
verifyError(testCase, @() rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 10, ...
    'maxLayerCount', 10, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false)), ...
    'RectangularFPC:InvalidLayerCount');
end

function testAutoVoutRejectsClearanceOutsideUsableInsetRange(testCase)
% outputViaToBoardClearance participates in the actual selected safe X.
% The planner must compare that selected X, not the smaller generic-via
% clearance floor, against the right-hand tip-inset boundary.
verifyError(testCase, @() rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 4, ...
    'turnsPerLayer', 1, ...
    'outputViaToBoardClearance', 8.0, ...
    'enablePreview', false, ...
    'enableFigure', false)), ...
    'RectangularFPC:ViaPlanningFailed');
end

function testManualSeriesViaUsesActualRoundedBoardBoundary(testCase)
% In user coordinates [91.5, 8.0] lies inside the old coarse tab rectangle
% but its pad/clearance disk crosses the rounded tip boundary. Planning must
% reject it even when the optional downstream via-clearance scan is off.
verifyError(testCase, @() rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 4, ...
    'turnsPerLayer', 1, ...
    'viaPlacementMode', 'manual', ...
    'manualSeriesViaXY', [25, 6; 91.5, 8.0; 55, 6], ...
    'enableViaClearanceCheck', false, ...
    'enablePreview', false, ...
    'enableFigure', false)), ...
    'RectangularFPC:ViaPlanningFailed');
end

function testManualOutputViaUsesActualRoundedBoardBoundary(testCase)
verifyError(testCase, @() rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 4, ...
    'turnsPerLayer', 1, ...
    'outputViaPlacementMode', 'manual', ...
    'manualOutputViaXY', [91.5, 8.0], ...
    'enableViaClearanceCheck', false, ...
    'enablePreview', false, ...
    'enableFigure', false)), ...
    'RectangularFPC:ViaPlanningFailed');
end

function testTwoLayerDrillToNonConnectedCopperIsNotApplicable(testCase)
result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 2, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));
row = result.manufacturing.checks(strcmp( ...
    {result.manufacturing.checks.id}, 'DRILL_TO_COPPER'));

assertNumElements(testCase, row, 1);
verifyEqual(testCase, row.status, 'NOT_APPLICABLE');
verifyEqual(testCase, row.code, 'NOT_APPLICABLE');
verifyFalse(testCase, isinf(row.measuredMm));
verifyTrue(testCase, isnan(row.measuredMm));
end

function testSupportedQualificationRejectsDisabledRequiredChecks(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));
overrides = struct( ...
    'analysisOnly', true, ...
    'outputRoot', outputRoot, ...
    'designName', 'disabled_check_contract', ...
    'turnsPerLayer', 1, ...
    'enableCopperClearanceCheck', false, ...
    'enablePreview', false, ...
    'enableFigure', false);

result = rectangular_fpc_main(overrides);
verifyFalse(testCase, result.manufacturing.verified);
verifyFalse(testCase, result.manufacturing.exportAllowed);
verifyEqual(testCase, result.manufacturing.status, 'FAIL');
qualification = result.manufacturing.checks(strcmp( ...
    {result.manufacturing.checks.id}, 'REQUIRED_VALIDATION_CHECKS'));
assertNumElements(testCase, qualification, 1);
verifyEqual(testCase, qualification.status, 'FAIL');
verifyEqual(testCase, qualification.code, 'REQUIRED_CHECK_DISABLED');
verifyFalse(testCase, isfolder(outputRoot));

overrides.analysisOnly = false;
verifyError(testCase, @() rectangular_fpc_main(overrides), ...
    'RectangularFPC:ManufacturingFailed');
if isfolder(outputRoot)
    formal = dir(fullfile(outputRoot, 'disabled_check_contract_*'));
    verifyEmpty(testCase, formal([formal.isdir]));
end

clear cleanup;
end

function testTimestampedExportContainsEngineeringArtifacts(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));

result = rectangular_fpc_main(struct( ...
    'outputRoot', outputRoot, ...
    'designName', 'timestamp_contract', ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));

verifyMatches(testCase, result.runTimestamp, '^\d{8}_\d{4}$');
verifyEqual(testCase, result.outputPath, fullfile(outputRoot, ...
    ['timestamp_contract_' result.runTimestamp]));
verifyTrue(testCase, isfile(fullfile(result.outputPath, 'dxf', ...
    '00_board_outline.dxf')));
verifyTrue(testCase, isfile(fullfile(result.outputPath, 'dxf', ...
    '00_drill_map.dxf')));
for layer = 1:result.layerCount
    layerFolder = fullfile(result.outputPath, 'dxf', sprintf('L%d', layer));
    verifyTrue(testCase, isfile(fullfile(layerFolder, ...
        sprintf('%02d_copper_L%d.dxf', layer, layer))));
    verifyTrue(testCase, isfile(fullfile(layerFolder, ...
        sprintf('%02d_copper_physical_L%d.dxf', layer, layer))));
    verifyTrue(testCase, isfile(fullfile(layerFolder, ...
        sprintf('%02d_antipad_keepout_L%d.dxf', layer, layer))));
    antipadFile = fullfile(layerFolder, ...
        sprintf('%02d_antipad_keepout_L%d.dxf', layer, layer));
    expectedAntipads = sum(arrayfun(@(via) ...
        via.antipadDiameter > 0 && ...
        ~ismember(layer, via.connectedLayers), result.vias));
    verifyEqual(testCase, countDxfEntities(antipadFile, 'CIRCLE'), ...
        expectedAntipads);
end
for reportIndex = 1:8
    pattern = fullfile(result.outputPath, 'reports', sprintf('%02d_*', reportIndex));
    verifyEqual(testCase, numel(dir(pattern)), 1, ...
        sprintf('expected exactly one report with index %02d', reportIndex));
end

manifestPath = fullfile(result.outputPath, 'reports', '08_file_manifest.csv');
manifest = readtable(manifestPath, 'TextType', 'string');
verifyEqual(testCase, manifest.Properties.VariableNames, ...
    {'relativePath', 'role', 'sizeBytes', 'sha256'});
verifyFalse(testCase, any(manifest.relativePath == "reports/08_file_manifest.csv"));
verifyTrue(testCase, all(strlength(manifest.sha256) == 64));
verifyEqual(testCase, height(manifest), countFiles(result.outputPath) - 1);
for rowIndex = 1:height(manifest)
    artifactPath = fullfile(result.outputPath, ...
        strrep(char(manifest.relativePath(rowIndex)), '/', filesep));
    info = dir(artifactPath);
    verifyEqual(testCase, manifest.sizeBytes(rowIndex), info.bytes);
    verifyEqual(testCase, manifest.sha256(rowIndex), ...
        string(sha256File(artifactPath)));
end

clear cleanup;
end

function testSameMinuteReplacementRollbackAndHistoricalRetention(testCase)
workspaceRoot = tempname;
outputRoot = fullfile(workspaceRoot, 'rectangular_fpc_output');
legacyRoot = fullfile(workspaceRoot, 'fpc_coil_output');
mkdir(legacyRoot);
writeMarker(fullfile(legacyRoot, 'historical_marker.txt'));
oldVersion = fullfile(outputRoot, 'atomic_contract_20000101_0000');
mkdir(oldVersion);
writeMarker(fullfile(oldVersion, 'old_version_marker.txt'));
cleanup = onCleanup(@() removeWorkspaceRoot(workspaceRoot));

base = struct( ...
    'outputRoot', outputRoot, 'designName', 'atomic_contract', ...
    'turnsPerLayer', 1, 'enablePreview', false, 'enableFigure', false);
[before, after] = generateSameMinutePair(base);
verifyEqual(testCase, before.outputPath, after.outputPath);
verifyTrue(testCase, isfile(after.fileManifest));
verifyTrue(testCase, isfile(fullfile(oldVersion, 'old_version_marker.txt')));
verifyTrue(testCase, isfile(fullfile(legacyRoot, 'historical_marker.txt')));

publishedId = readPublicationId(after.outputPath);
publishedManifestHash = sha256File(after.fileManifest);
bad = base;
bad.manufacturingRuleOverrides = struct('minTraceWidthMm', 0.30);
verifyError(testCase, @() rectangular_fpc_main(bad), ...
    'RectangularFPC:ManufacturingFailed');
verifyEqual(testCase, readPublicationId(after.outputPath), publishedId);
verifyEqual(testCase, sha256File(after.fileManifest), publishedManifestHash);
verifyTrue(testCase, isfile(fullfile(legacyRoot, 'historical_marker.txt')));

% Simulate a process interruption for the minute that the next call will
% target. Deriving the target immediately before invoking the entry point
% keeps this test valid even when the earlier assertions cross a minute.
for recoveryAttempt = 1:3
    seeded = rectangular_fpc_main(base);
    prospectivePath = seeded.outputPath;
    transactionToken = '11111111111111111111111111111111';
    orphanBackup = sprintf('%s_backup_%s', ...
        prospectivePath, transactionToken);
    orphanMarker = [orphanBackup '.transaction'];
    [moved, message] = movefile(prospectivePath, orphanBackup);
    verifyTrue(testCase, moved, message);
    writeRecoveryMarker( ...
        orphanMarker, prospectivePath, transactionToken);
    staleLockFolder = [prospectivePath '_publish.lock'];
    mkdir(staleLockFolder);
    writeStaleLockOwner(staleLockFolder);
    recovered = rectangular_fpc_main(base);
    if strcmp(recovered.outputPath, prospectivePath)
        break;
    end
    if isfolder(orphanBackup)
        rmdir(orphanBackup, 's');
    end
    if isfile(orphanMarker)
        delete(orphanMarker);
    end
    if isfolder(staleLockFolder)
        rmdir(staleLockFolder, 's');
    end
end
verifyEqual(testCase, recovered.outputPath, prospectivePath);
verifyTrue(testCase, isfile(recovered.fileManifest));
verifyFalse(testCase, isfolder(orphanBackup));
verifyFalse(testCase, isfile(orphanMarker));
verifyFalse(testCase, isfolder(staleLockFolder));

% A concurrent publication lock must fail closed without disturbing the
% already published minute version or leaving a staging directory behind.
lockedPublicationId = readPublicationId(recovered.outputPath);
lockedManifestHash = sha256File(recovered.fileManifest);
lockTimes = [datetime('now'), datetime('now') + minutes(1)];
lockFolders = cell(1, numel(lockTimes));
for lockIndex = 1:numel(lockTimes)
    stamp = char(datetime(lockTimes(lockIndex), 'Format', 'yyyyMMdd_HHmm'));
    versionPath = fullfile(outputRoot, ['atomic_contract_' stamp]);
    lockFolders{lockIndex} = [versionPath '_publish.lock'];
    mkdir(lockFolders{lockIndex});
end
verifyError(testCase, @() rectangular_fpc_main(base), ...
    'RectangularFPC:ConcurrentPublish');
verifyEqual(testCase, readPublicationId(recovered.outputPath), ...
    lockedPublicationId);
verifyEqual(testCase, sha256File(recovered.fileManifest), ...
    lockedManifestHash);
for lockIndex = 1:numel(lockFolders)
    if isfolder(lockFolders{lockIndex})
        rmdir(lockFolders{lockIndex});
    end
end
verifyEmpty(testCase, dir(fullfile(outputRoot, '*_rectangular_fpc_staging')));

clear cleanup;
end

function testManufacturingFailureDoesNotCreateFormalOutput(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));
overrides = struct( ...
    'outputRoot', outputRoot, ...
    'designName', 'manufacturing_failure', ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false, ...
    'manufacturingRuleOverrides', struct('minTraceWidthMm', 0.30));

verifyError(testCase, @() rectangular_fpc_main(overrides), ...
    'RectangularFPC:ManufacturingFailed');
if isfolder(outputRoot)
    formal = dir(fullfile(outputRoot, 'manufacturing_failure_*'));
    formal = formal([formal.isdir]);
    verifyEmpty(testCase, formal);
end

clear cleanup;
end

function testActiveGeometryErrorsUseRectangularIdentifiers(testCase)
terminalConfig = struct( ...
    'analysisOnly', true, ...
    'tabWidth', 1.0, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false);
verifyError(testCase, @() rectangular_fpc_main(terminalConfig), ...
    'RectangularFPC:InvalidTerminalGeometry');

turnConfig = struct( ...
    'analysisOnly', true, ...
    'turnsPerLayer', 20, ...
    'enablePreview', false, ...
    'enableFigure', false);
verifyError(testCase, @() rectangular_fpc_main(turnConfig), ...
    'RectangularFPC:TurnLimitExceeded');
end

function verifyTopologyContract(testCase, result)
tol = result.config.connectionTolerance;
verifyTrue(testCase, result.validation.topologyPassed);
seriesVias = result.vias(strcmp({result.vias.role}, 'series_interconnect'));
for viaIndex = 1:numel(seriesVias)
    via = seriesVias(viaIndex);
    verifyFalse(testCase, isempty(via.fromLeadPath), ...
        sprintf('%s fromLeadPath must not be empty.', via.name));
    verifyFalse(testCase, isempty(via.toLeadPath), ...
        sprintf('%s toLeadPath must not be empty.', via.name));
    if ~isempty(via.fromLeadPath)
        verifyLessThanOrEqual(testCase, ...
            norm(via.fromLeadPath(end, :) - via.xy), tol);
    end
    if ~isempty(via.toLeadPath)
        verifyLessThanOrEqual(testCase, ...
            norm(via.toLeadPath(1, :) - via.xy), tol);
    end
end

padA = result.pads(strcmp({result.pads.name}, 'PAD_A'));
padB = result.pads(strcmp({result.pads.name}, 'PAD_B'));
vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
assertNumElements(testCase, padA, 1);
assertNumElements(testCase, padB, 1);
assertNumElements(testCase, vout, 1);
verifyFalse(testCase, isempty(result.layerPaths{1}{1}));
verifyFalse(testCase, isempty(result.layerPaths{result.layerCount}{1}));
verifyGreaterThanOrEqual(testCase, numel(result.layerPaths{1}), 2);
if ~isempty(result.layerPaths{1}{1})
    verifyLessThanOrEqual(testCase, ...
        norm(result.layerPaths{1}{1}(1, :) - padA.xy), tol);
end
if ~isempty(result.layerPaths{result.layerCount}{1})
    verifyLessThanOrEqual(testCase, ...
        norm(result.layerPaths{result.layerCount}{1}(end, :) - vout.xy), tol);
end
if numel(result.layerPaths{1}) >= 2 && ~isempty(result.layerPaths{1}{2})
    returnPath = result.layerPaths{1}{2};
    verifyLessThanOrEqual(testCase, norm(returnPath(1, :) - vout.xy), tol);
    verifyLessThanOrEqual(testCase, norm(returnPath(end, :) - padB.xy), tol);
end
end

function [succeeded, result, errorId] = invokeRectangular(overrides)
succeeded = false;
result = struct();
errorId = '';
try
    result = rectangular_fpc_main(overrides);
    succeeded = true;
catch ME
    errorId = ME.identifier;
end
end

function outputRoot = freshOutputRoot()
outputRoot = fullfile(tempname, 'rectangular_fpc_test_output');
end

function removeOutputRoot(outputRoot)
if isfolder(outputRoot)
    rmdir(outputRoot, 's');
end
parent = fileparts(outputRoot);
if isfolder(parent)
    rmdir(parent, 's');
end
end

function [before, after] = generateSameMinutePair(overrides)
before = rectangular_fpc_main(overrides);
beforePublicationId = readPublicationId(before.outputPath);
for attempt = 1:3
    after = rectangular_fpc_main(overrides);
    if strcmp(before.runTimestamp, after.runTimestamp)
        afterPublicationId = readPublicationId(after.outputPath);
        if strcmp(beforePublicationId, afterPublicationId)
            error('RectangularFPC:TestAtomicReplacement', ...
                'Same-minute publication retained the prior PublicationId.');
        end
        return;
    end
    before = after;
    beforePublicationId = readPublicationId(before.outputPath);
end
error('RectangularFPC:TestClockBoundary', ...
    'Unable to generate two designs in the same minute.');
end

function publicationId = readPublicationId(outputFolder)
statusText = fileread(fullfile(outputFolder, 'generation_status.txt'));
match = regexp(statusText, ...
    '(?m)^PublicationId:\s*([0-9a-fA-F]{32})\s*$', 'tokens');
if numel(match) ~= 1
    error('RectangularFPC:TestPublicationId', ...
        'Expected exactly one valid PublicationId in %s.', outputFolder);
end
publicationId = lower(match{1}{1});
end

function count = countFiles(root)
entries = dir(fullfile(root, '**', '*'));
count = sum(~[entries.isdir]);
end

function count = countDxfEntities(filename, entityName)
content = fileread(filename);
count = numel(regexp(content, ...
    ['(?m)^' regexptranslate('escape', entityName) '\r?$'], 'match'));
end

function hash = sha256File(filename)
fid = fopen(filename, 'rb');
cleanup = onCleanup(@() fclose(fid));
raw = fread(fid, Inf, '*uint8');
clear cleanup;
messageDigest = java.security.MessageDigest.getInstance('SHA-256');
digest = messageDigest.digest(raw);
hash = lower(reshape(dec2hex(typecast(digest, 'uint8'), 2).', 1, []));
end

function writeMarker(filename)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'preserve');
clear cleanup;
end

function writeStaleLockOwner(lockFolder)
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=2147483647\n');
fprintf(fid, 'host=%s\n', localHostIdentity());
fprintf(fid, 'token=22222222222222222222222222222222\n');
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear cleanup;
end

function writeRecoveryMarker(filename, outputFolder, token)
fid = fopen(filename, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));
target = char(java.io.File(outputFolder).getCanonicalPath());
fprintf(fid, 'SchemaVersion: 1\n');
fprintf(fid, 'Target: %s\n', target);
fprintf(fid, 'TransactionId: %s\n', token);
fprintf(fid, 'Payload: prior_committed_output\n');
clear cleanup;
end

function host = localHostIdentity()
host = getenv('COMPUTERNAME');
if isempty(host)
    host = getenv('HOSTNAME');
end
if isempty(host)
    host = char(java.net.InetAddress.getLocalHost().getHostName());
end
host = lower(strtrim(host));
end

function removeWorkspaceRoot(workspaceRoot)
if isfolder(workspaceRoot)
    rmdir(workspaceRoot, 's');
end
end
