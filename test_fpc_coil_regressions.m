function tests = test_fpc_coil_regressions
% Behavior-level regression tests for the configurable multilayer generator.

tests = functiontests(localfunctions);

end

function setupOnce(testCase)

testCase.TestData.outputRoot = tempname;
mkdir(testCase.TestData.outputRoot);

end

function teardownOnce(testCase)

if exist(testCase.TestData.outputRoot, 'dir')
    rmdir(testCase.TestData.outputRoot, 's');
end

end

function testDefaultConfigurationIsAStandalonePublicEntryPoint(testCase)

cfg = fpc_coil_default_config();

verifyTrue(testCase, isstruct(cfg));
verifyTrue(testCase, isfield(cfg, 'layerCount'));
verifyTrue(testCase, isfield(cfg, 'turnsPerLayer'));
verifyTrue(testCase, isfield(cfg, 'outputRoot'));

end

function testDefaultConfigurationAcceptsCallerOverrides(testCase)

overrides = struct( ...
    'layerCount', 6, ...
    'turnsPerLayer', 7, ...
    'enablePreview', false, ...
    'designName', 'override_contract');

cfg = fpc_coil_default_config(overrides);

verifyEqual(testCase, cfg.layerCount, 6);
verifyEqual(testCase, cfg.turnsPerLayer, 7);
verifyFalse(testCase, cfg.enablePreview);
verifyEqual(testCase, cfg.designName, 'override_contract');

end

function testConfigurationValidationAcceptsSixAndEightLayers(testCase)

for layerCount = [6, 8]
    cfg = fastConfig(layerCount, testCase.TestData.outputRoot);
    validated = fpc_coil_validate_config(cfg);
    verifyEqual(testCase, validated.layerCount, layerCount);
end

end

function testConfigurationValidationRejectsOddLayerCountClearly(testCase)

cfg = fastConfig(3, testCase.TestData.outputRoot);

try
    fpc_coil_validate_config(cfg);
    verifyFail(testCase, 'A three-layer winding must be rejected.');
catch ME
    verifyEqual(testCase, ME.identifier, 'FPC_Coil:InvalidLayerCount');
    verifyNotEmpty(testCase, regexp(ME.message, '3', 'once'));
    verifyNotEmpty(testCase, regexp(ME.message, '(even|偶数)', 'once'));
end

end

function testResultExposesStructuredOutputThroughVia(testCase)

result = generatedSixLayerDesign(testCase.TestData.outputRoot);

verifyTrue(testCase, isstruct(result.vias));
requiredFields = {'name', 'xy', 'fromLayer', 'toLayer', 'type'};
verifyTrue(testCase, all(isfield(result.vias, requiredFields)));

vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
verifyNumElements(testCase, vout, 1);
verifyEqual(testCase, vout.fromLayer, 6);
verifyEqual(testCase, vout.toLayer, 1);
verifyEqual(testCase, vout.type, 'through_via');
verifySize(testCase, vout.xy, [1, 2]);

end

function testPadBIsAnExternalTerminalOnTopLayer(testCase)

result = generatedSixLayerDesign(testCase.TestData.outputRoot);
padB = result.pads(strcmp({result.pads.name}, 'PAD_B'));

verifyNumElements(testCase, padB, 1);
verifyEqual(testCase, padB.layer, 1);
verifySize(testCase, padB.xy, [1, 2]);

end

function testTopLayerContainsIndependentCoilAndOutputReturnPaths(testCase)

result = generatedSixLayerDesign(testCase.TestData.outputRoot);
paths = result.layers(1).paths;

verifyTrue(testCase, iscell(paths));
verifyNumElements(testCase, paths, 2);
verifyGreaterThan(testCase, size(paths{1}, 1), 1);
verifyGreaterThan(testCase, size(paths{2}, 1), 1);
verifySize(testCase, paths{1}, [size(paths{1}, 1), 2]);
verifySize(testCase, paths{2}, [size(paths{2}, 1), 2]);

end

function testLayerNamesAndDxfOutputsScaleWithLayerCount(testCase)

result = generatedSixLayerDesign(testCase.TestData.outputRoot);
expectedNames = { ...
    'COPPER_L1_TOP', ...
    'COPPER_L2_INNER1', ...
    'COPPER_L3_INNER2', ...
    'COPPER_L4_INNER3', ...
    'COPPER_L5_INNER4', ...
    'COPPER_L6_BOTTOM'};

verifyNumElements(testCase, result.layers, 6);
verifyEqual(testCase, {result.layers.name}, expectedNames);
for k = 1:6
    verifyTrue(testCase, exist(result.layers(k).dxfFile, 'file') == 2, ...
        sprintf('Missing generated DXF for L%d.', k));
end
verifyTrue(testCase, exist(result.coordinateCsv, 'file') == 2);
verifyTrue(testCase, exist(result.summaryFile, 'file') == 2);
verifyTrue(testCase, exist(result.validationReport, 'file') == 2);

end

function testTurnScanReturnsSpecificFailureReason(testCase)

cfg = fastConfig(6, testCase.TestData.outputRoot);
scan = fpc_coil_scan_turns(cfg, [1, 20]);

verifyTrue(testCase, isstruct(scan));
verifyTrue(testCase, all(isfield(scan, {'turns', 'passed', 'failureReason'})));
verifyEqual(testCase, [scan.turns], [1, 20]);
verifyTrue(testCase, scan(1).passed);
verifyFalse(testCase, scan(2).passed);
verifyNotEmpty(testCase, scan(2).failureReason);
verifyNotEmpty(testCase, regexp(scan(2).failureReason, '(width|宽度|空间)', 'once'));

end

function cfg = fastConfig(layerCount, outputRoot)

cfg = fpc_coil_default_config(struct( ...
    'layerCount', layerCount, ...
    'turnsPerLayer', 1, ...
    'useRecommendedTurns', false, ...
    'pointsPerTurn', 100, ...
    'minTurnPointCount', 100, ...
    'boardArcPointCount', 8, ...
    'leadArcPointCount', 8, ...
    'enablePreview', false, ...
    'enableDxfReadbackCheck', false, ...
    'enableExactSelfIntersectionCheck', false, ...
    'enableCopperClearanceCheck', false, ...
    'enableBoardAngleCheck', false, ...
    'enableCopperAngleCheck', false, ...
    'enablePadClearanceCheck', false, ...
    'enableViaClearanceCheck', false, ...
    'outputRoot', outputRoot, ...
    'designName', sprintf('behavior_%dlayer', layerCount)));

end

function result = generatedSixLayerDesign(outputRoot)

persistent cachedOutputRoot cachedResult

if isempty(cachedResult) || ~strcmp(cachedOutputRoot, outputRoot)
    cfg = fastConfig(6, outputRoot);
    cachedResult = fpc_coil_generate(cfg);
    cachedOutputRoot = outputRoot;
end
result = cachedResult;

end
