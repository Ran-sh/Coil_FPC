function tests = test_rectangular_fpc_regressions
% Behavior-level regression tests for the configurable multilayer generator.

tests = functiontests(localfunctions);

end

function setupOnce(testCase)

testsFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(testsFolder);
testCase.TestData.originalPath = path;
addpath(projectRoot);
testCase.TestData.projectRoot = projectRoot;

testCase.TestData.outputRoot = tempname;
mkdir(testCase.TestData.outputRoot);

end

function teardownOnce(testCase)

if exist(testCase.TestData.outputRoot, 'dir')
    rmdir(testCase.TestData.outputRoot, 's');
end
path(testCase.TestData.originalPath);

end

function testDefaultConfigurationIsAStandalonePublicEntryPoint(testCase)

cfg = rectangular_fpc_default_config();

verifyTrue(testCase, isstruct(cfg));
verifyTrue(testCase, isfield(cfg, 'layerCount'));
verifyTrue(testCase, isfield(cfg, 'turnsPerLayer'));
verifyTrue(testCase, isfield(cfg, 'outputRoot'));

end

function testDefaultFourLayerTwelveTurnGoldenRegression(testCase)

result = rectangular_fpc_main(struct('analysisOnly', true));
cfg = result.config;

verifyTrue(testCase, result.passed);
verifyTrue(testCase, result.validation.passed);
verifyEqual(testCase, result.layerCount, 4);
verifyEqual(testCase, result.turnsPerLayer, 12);
verifyEqual(testCase, [ ...
    result.widthBasedMaximumTurns, ...
    result.lengthBasedMaximumTurns, ...
    result.cornerRadiusMaximumTurns, ...
    result.innerViaRegionMaximumTurns, ...
    result.analyticalMaximumTurns, ...
    result.fullyValidatedMaximumTurns, ...
    result.recommendedTurns], [13, 109, 12, 13, 12, 12, 11]);
verifyEqual(testCase, result.turnLimits.limitingFactors, ...
    {'CORNER_RADIUS_LIMIT'});
verifyNumElements(testCase, result.turnScan, 1);
verifyEqual(testCase, result.turnScan.turns, 12);
verifyTrue(testCase, result.turnScan.passed);

verifyEqual(testCase, result.layerLengthMm, [ ...
    1901.1203102664804; ...
    1880.7016880192257; ...
    1883.2812328989990; ...
    1883.8998560612240], 'AbsTol', 1e-6);
verifyEqual(testCase, result.totalTraceLengthMm, ...
    7549.0030872459283, 'AbsTol', 1e-6);
verifyEqual(testCase, result.estimatedDcResistanceOhm, ...
    18.592116174874256, 'AbsTol', 1e-9);
verifyEqual(testCase, result.minCopperSpacing, ...
    0.149846190509252, 'AbsTol', 1e-9);
verifyEqual(testCase, [min(result.boardXY); max(result.boardXY)], ...
    [-40, -6; 52, 6], 'AbsTol', cfg.geometryTolerance);
verifyEqual(testCase, localQuantizedCoordinateSha256(result.boardXY), ...
    '82ecf87f12bf020089b319dee2ee7411c8950c5831587e726926be3b591e570a');

verifyEqual(testCase, cellfun(@numel, result.layerPaths), [2; 1; 1; 1]);
expectedPathHashes = { ...
    '3f5d0cf9ef07d1f9faf87b25b9f44695d91602258eff7b2c2e989421c23cc5ea'; ...
    'd0921220694384001b04a80a98bf1ce6de94375a0467a05c2852c561f06455be'; ...
    '67768e22428b1efef606daa4a0f1b55da347ac3e3b52df968dacdb4645c95c4b'; ...
    '6ca9a055938c269d060fb83da17f208c3eefeb9fc45011813f7e927bcb49a231'};
for layerIndex = 1:result.layerCount
    verifyEqual(testCase, ...
        localQuantizedPathSetSha256(result.layerPaths{layerIndex}), ...
        expectedPathHashes{layerIndex});
end

verifyEqual(testCase, {result.pads.name}, {'PAD_A', 'PAD_B'});
verifyEqual(testCase, vertcat(result.pads.xy), [50.5, 1.1; 50.5, -1.1], ...
    'AbsTol', cfg.geometryTolerance);
verifyEqual(testCase, [result.pads.layer], [1, 1]);
verifyEqual(testCase, {result.vias.name}, {'V12', 'V23', 'V34', 'VOUT'});
verifyEqual(testCase, [result.vias.fromLayer], [1, 2, 3, 4]);
verifyEqual(testCase, [result.vias.toLayer], [2, 3, 4, 1]);
verifyEqual(testCase, vertcat(result.vias.connectedLayers), ...
    [1, 2; 2, 3; 3, 4; 4, 1]);
verifyEqual(testCase, {result.vias.type}, repmat({'through_via'}, 1, 4));
verifyEqual(testCase, vertcat(result.vias.xy), [ ...
    34.34, 0.0; 40.60, 0.0; 32.34, 0.0; 40.60, -1.10], ...
    'AbsTol', cfg.geometryTolerance);
verifyEqual(testCase, {result.vias.role}, { ...
    'series_interconnect', 'series_interconnect', ...
    'series_interconnect', 'output_return'});
verifyEqual(testCase, result.layerPaths{1}{1}(1, :), ...
    result.pads(1).xy, 'AbsTol', cfg.connectionTolerance);
verifyEqual(testCase, result.layerPaths{1}{1}(end, :), ...
    result.vias(1).xy, 'AbsTol', cfg.connectionTolerance);
for layerIndex = 2:result.layerCount
    verifyEqual(testCase, result.layerPaths{layerIndex}{1}(1, :), ...
        result.vias(layerIndex - 1).xy, 'AbsTol', cfg.connectionTolerance);
    verifyEqual(testCase, result.layerPaths{layerIndex}{1}(end, :), ...
        result.vias(layerIndex).xy, 'AbsTol', cfg.connectionTolerance);
end
verifyEqual(testCase, result.layerPaths{1}{2}(1, :), ...
    result.vias(end).xy, 'AbsTol', cfg.connectionTolerance);
verifyEqual(testCase, result.layerPaths{1}{2}(end, :), ...
    result.pads(2).xy, 'AbsTol', cfg.connectionTolerance);

end

function testDefaultConfigurationAcceptsCallerOverrides(testCase)

overrides = struct( ...
    'layerCount', 6, ...
    'turnsPerLayer', 7, ...
    'enablePreview', false, ...
    'designName', 'override_contract');

cfg = rectangular_fpc_default_config(overrides);

verifyEqual(testCase, cfg.layerCount, 6);
verifyEqual(testCase, cfg.turnsPerLayer, 7);
verifyFalse(testCase, cfg.enablePreview);
verifyEqual(testCase, cfg.designName, 'override_contract');

end

function testConfigurationSurfaceContainsOnlySupportedFields(testCase)

cfg = rectangular_fpc_default_config();
removedFields = { ...
    'outputReturnBendRadius', ...
    'manufacturingTolerance', ...
    'previewDpi'};

hasSmoothLeadField = isfield(cfg, 'requireSmoothLeadTransitions');
verifyTrue(testCase, hasSmoothLeadField);
if hasSmoothLeadField
    verifyTrue(testCase, cfg.requireSmoothLeadTransitions);
end
verifyFalse(testCase, isfield(cfg, 'requireSmoothEscapeArcs'));
for k = 1:numel(removedFields)
    verifyFalse(testCase, isfield(cfg, removedFields{k}));
end

cfgOverride = rectangular_fpc_default_config(struct( ...
    'requireSmoothLeadTransitions', false));
verifyFalse(testCase, cfgOverride.requireSmoothLeadTransitions);

rejectedFields = [removedFields, {'requireSmoothEscapeArcs', 'notARealOption'}];
for k = 1:numel(rejectedFields)
    overrides = struct();
    overrides.(rejectedFields{k}) = 1;
    verifyError(testCase, @() rectangular_fpc_default_config(overrides), ...
        'RectangularFPC:UnknownConfigField');
end

end

function testPublicMatlabSurfaceIsMinimal(testCase)

testFolder = fileparts(mfilename('fullpath'));
[~, folderName] = fileparts(testFolder);
if strcmpi(folderName, 'tests')
    projectRoot = fileparts(testFolder);
else
    projectRoot = testFolder;
end

rootFiles = dir(fullfile(projectRoot, '*.m'));
rootNames = sort({rootFiles.name});
rootNames = rootNames(~startsWith(rootNames, 'test_'));
expectedRootNames = sort({ ...
    'fpc_coil_default_config.m', ...
    'fpc_coil_main.m', ...
    'rectangular_fpc_default_config.m', ...
    'rectangular_fpc_main.m'});
verifyEqual(testCase, rootNames, expectedRootNames);

privateFiles = dir(fullfile(projectRoot, 'private', '*.m'));
privateNames = sort({privateFiles.name});
privateNames = privateNames(~startsWith(privateNames, 'test_'));
expectedPrivateNames = sort({ ...
    'rectangular_fpc_engine.m', ...
    'rectangular_fpc_export.m', ...
    'rectangular_fpc_geometry.m', ...
    'rectangular_fpc_manufacturing.m', ...
    'rectangular_fpc_plot.m', ...
    'rectangular_fpc_publish_atomically.m', ...
    'rectangular_fpc_validation.m'});
verifyEqual(testCase, privateNames, expectedPrivateNames);
verifyEqual(testCase, exist(fullfile(projectRoot, 'tests', ...
    'test_rectangular_fpc_regressions.m'), 'file'), 2);

end

function testFigureViewerCreatesFigureWithLayersAndPads(testCase)

priorFigs = findall(0, 'Type', 'figure');
result = rectangular_fpc_main(struct('enablePreview', false, 'enableFigure', true));
verifyTrue(testCase, result.passed);

% 新字段必须出现在 result 中，供图窗绘制使用
verifyEqual(testCase, size(result.boardXY, 2), 2);
cfg = rectangular_fpc_default_config();
verifyEqual(testCase, result.pads(1).diameter, cfg.padDiameter);

% 图窗由 private/rectangular_fpc_plot 实现（不作为公共 API），仅在 MATLAB 桌面
% 环境由 rectangular_fpc_main 自动弹出；无头 -batch 运行按设计跳过弹窗。
newFigs = setdiff(findall(0, 'Type', 'figure'), priorFigs);
if isempty(newFigs)
    % 无头环境：验证实现文件确实位于 private/ 目录内
    testFolder = fileparts(mfilename('fullpath'));
    verifyEqual(testCase, exist(fullfile(fileparts(testFolder), ...
        'private', 'rectangular_fpc_plot.m'), 'file'), 2);
    return;
end

testCase.addTeardown(@() close(newFigs));
% 与 previews/ 的 SVG 输出一致：总览一张，每层一张
verifyEqual(testCase, numel(newFigs), result.layerCount + 1, ...
    'expected one overview window plus one window per layer');
figNames = arrayfun(@(h) h.Name, newFigs, 'UniformOutput', false);
verifyTrue(testCase, any(contains(figNames, 'Overview')), ...
    'overview window missing');
for k = 1:result.layerCount
    verifyTrue(testCase, any(contains(figNames, sprintf('Layer %d (', k))), ...
        sprintf('missing window for layer %d', k));
end
for k = 1:numel(newFigs)
    axesCount = numel(findobj(newFigs(k), 'Type', 'axes'));
    verifyEqual(testCase, axesCount, 1, ...
        sprintf('window %d should have exactly 1 axes, got %d', k, axesCount));
end
overviewFig = newFigs(contains(figNames, 'Overview'));
verifyTrue(testCase, ~isempty(findobj(overviewFig(1), 'Type', 'legend')), ...
    'overview window should have a layer legend');

end

function testConfigurationValidationAcceptsSixAndEightLayers(testCase)

for layerCount = [6, 8]
    if layerCount == 6
        result = generatedSixLayerDesign(testCase.TestData.outputRoot);
    else
        result = generatedEightLayerValidated(testCase.TestData.outputRoot);
    end
    verifyEqual(testCase, result.layerCount, layerCount);
end

end

function testConfigurationValidationRejectsOddLayerCountClearly(testCase)

cfg = fastConfig(3, testCase.TestData.outputRoot);

try
    rectangular_fpc_main(cfg);
    verifyFail(testCase, 'A three-layer winding must be rejected.');
catch ME
    verifyEqual(testCase, ME.identifier, 'RectangularFPC:InvalidLayerCount');
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
verifyFalse(testCase, result.manufacturing.verified);
verifyEqual(testCase, result.manufacturing.applicability, ...
    'UNVERIFIED_LAYER_COUNT');
statusText = fileread(fullfile(result.outputFolder, 'generation_status.txt'));
verifyNotEmpty(testCase, regexp(statusText, ...
    'ManufacturingApplicability:\s*UNVERIFIED_LAYER_COUNT', 'once'));

end

function testOversizedTurnCountReturnsSpecificFailureReason(testCase)

cfg = fastConfig(6, testCase.TestData.outputRoot);
cfg.turnsPerLayer = 20;
cfg.designName = 'oversized_turns_failure';

try
    rectangular_fpc_main(cfg);
    messageText = '';
catch ME
    messageText = ME.message;
end

verifyNotEmpty(testCase, messageText);
verifyNotEmpty(testCase, regexp(messageText, '(width|宽度|空间)', 'once'));

end

function testEightLayerProductionValidationPasses(testCase)

result = generatedEightLayerValidated(testCase.TestData.outputRoot);

verifyTrue(testCase, result.passed);
verifyEqual(testCase, result.layerCount, 8);
verifyEqual(testCase, result.turnsPerLayer, 1);
verifyFalse(testCase, result.manufacturing.verified);
verifyEqual(testCase, result.manufacturing.applicability, ...
    'UNVERIFIED_LAYER_COUNT');
notesText = fileread(result.fabricationNotes);
verifyNotEmpty(testCase, regexp(notesText, ...
    'Applicability:\s*UNVERIFIED_LAYER_COUNT', 'once'));
verifyGreaterThanOrEqual(testCase, result.fullyValidatedMaximumTurns, 1);
verifyGreaterThanOrEqual(testCase, result.recommendedTurns, 1);
verifyTrue(testCase, isfinite(result.totalLengthMm));
verifyGreaterThan(testCase, result.totalResistanceOhm, 0);

vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
seriesVias = result.vias(~strcmp({result.vias.name}, 'VOUT'));
verifyEqual(testCase, vout.antipadDiameter, 1.00, 'AbsTol', 1e-12);
verifyEqual(testCase, {seriesVias.type}, ...
    repmat({'adjacent_layer_via'}, 1, 7));
verifyEqual(testCase, [seriesVias.antipadDiameter], zeros(1, 7));

end

function testOutputViaSpecificBoardClearanceIsEnforced(testCase)

cfg = fastConfig(6, testCase.TestData.outputRoot);
cfg.enableViaClearanceCheck = true;
cfg.outputViaToBoardClearance = 100;
cfg.designName = 'vout_board_clearance_failure';

verifyError(testCase, @() rectangular_fpc_main(cfg), ...
    'RectangularFPC:NoValidTurnCount');

end

function testOutputAntipadHonorsConfiguredSeverity(testCase)

cfg = fastConfig(6, testCase.TestData.outputRoot);
cfg.enableViaClearanceCheck = true;
cfg.outputViaAntiPadDiameter = 20;
cfg.viaClearanceSeverity = 'error';
cfg.designName = 'vout_antipad_error';
verifyError(testCase, @() rectangular_fpc_main(cfg), ...
    'RectangularFPC:NoValidTurnCount');

cfg.viaClearanceSeverity = 'warning';
cfg.designName = 'vout_antipad_warning';
result = rectangular_fpc_main(cfg);
verifyTrue(testCase, result.passed);

end

function testRecommendedFourLayerDesignUsesAnglesStrictlyAboveNinety(testCase)

result = generatedFourLayerValidated(testCase.TestData.outputRoot);
cfg = rectangular_fpc_default_config();

verifyGreaterThan(testCase, result.minCopperAngle, ...
    cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg);
reportText = fileread(result.validationReport);
verifyEmpty(testCase, regexp(reportText, ...
    'FALLBACK_TO_SHARP_CORNER', 'once'));

end

function testLayerCountDoesNotChangeTurnsPerLayer(testCase)
% 任务十七.1：只改 layerCount 不得自动修改 turnsPerLayer
cfg4 = rectangular_fpc_default_config(struct('layerCount', 4));
cfg6 = rectangular_fpc_default_config(struct('layerCount', 6));
verifyEqual(testCase, cfg4.turnsPerLayer, cfg6.turnsPerLayer);

end

function testWidthLimitIndependentOfLayerCount(testCase)
% 任务十七.2：相同板尺寸/线宽/线距/圆角/中心空白下，2/4/6/8 层宽度上限相同
widths = zeros(4, 1);
layerList = [2 4 6 8];
for idx = 1:4
    cfg = fastConfig(layerList(idx), testCase.TestData.outputRoot);
    cfg.designName = sprintf('width_limit_%dlayer', layerList(idx));
    result = rectangular_fpc_main(cfg);
    widths(idx) = result.turnLimits.width;
end
verifyTrue(testCase, all(widths == widths(1)));

end

function testManualViaCoordinatesMatchInput(testCase)
% 任务十七.3：手动过孔坐标与输入一致（误差 < connectionTolerance）
cfg = rectangular_fpc_default_config(struct( ...
    'layerCount', 4, ...
    'viaPlacementMode', 'manual', ...
    'manualSeriesViaXY', [25.0, 6.0; 82.0, 6.0; 55.0, 6.0], ...
    'outputViaPlacementMode', 'manual', ...
    'manualOutputViaXY', [87.0, 4.7], ...
    'outputRoot', testCase.TestData.outputRoot, ...
    'designName', 'manual_roundtrip', ...
    'enablePreview', false, ...
    'enableDxfReadbackCheck', false));

try
    result = rectangular_fpc_main(cfg);
    tol = cfg.connectionTolerance;
    seriesNames = {'V12', 'V23', 'V34'};
    for k = 1:3
        v = result.vias(strcmp({result.vias.name}, seriesNames{k}));
        verifyNumElements(testCase, v, 1);
        uv = localInternalToUserXY(v.xy, cfg);
        verifyLessThan(testCase, norm(uv - cfg.manualSeriesViaXY(k, :)), tol);
    end
    vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
    verifyNumElements(testCase, vout, 1);
    uvout = localInternalToUserXY(vout.xy, cfg);
    verifyLessThan(testCase, norm(uvout - cfg.manualOutputViaXY), tol);
catch ME
    verifyFail(testCase, sprintf('手动坐标生成失败：%s', ME.message));
end

end

function testManualViaRowCountRejected(testCase)
% 任务十七.4：手动过孔行数错误必须明确拒绝
cfg = rectangular_fpc_default_config(struct( ...
    'layerCount', 4, ...
    'viaPlacementMode', 'manual', ...
    'manualSeriesViaXY', [25.0, 6.0; 82.0, 6.0], ...   % 只有 2 行，需要 3 行
    'outputRoot', testCase.TestData.outputRoot, ...
    'designName', 'manual_bad_rows'));

verifyError(testCase, @() rectangular_fpc_main(cfg), ...
    'RectangularFPC:InvalidManualVias');

end

function testManualViaOutsideBoardRejected(testCase)
% 任务十七.4：过孔在板外必须报出具体失败
cfg = rectangular_fpc_default_config(struct( ...
    'layerCount', 4, ...
    'viaPlacementMode', 'manual', ...
    'manualSeriesViaXY', [25.0, 6.0; 82.0, 60.0; 55.0, 6.0], ... % V23 在板外
    'outputRoot', testCase.TestData.outputRoot, ...
    'designName', 'manual_outside_board', ...
    'enablePreview', false, ...
    'enableDxfReadbackCheck', false, ...
    'enableViaClearanceCheck', false));

verifyError(testCase, @() rectangular_fpc_main(cfg), ...
    'RectangularFPC:ViaPlanningFailed');

end

function testStrictConcentricRadiusNoClamp(testCase)
% 任务十七.7：strict_concentric 模式内圈圆角无最小半径截断
cfg = fastConfig(4, testCase.TestData.outputRoot);
cfg.cornerOffsetMode = 'strict_concentric';
cfg.designName = 'strict_concentric_radius';
result = rectangular_fpc_main(cfg);
limits = result.turnLimits;
strictInner = limits.coilOuterRadius - cfg.turnsPerLayer * limits.pitch;
verifyGreaterThan(testCase, strictInner, 0);
verifyTrue(testCase, limits.cornerRadius == ...
    floor((limits.coilOuterRadius - cfg.minSpiralCornerRadius) / limits.pitch));

end

function testFourLayerEightTurnsTarget(testCase)
% 任务十七.9：80×12、8 匝、maximize + strict + hybrid_auto 目标场景
cfg = rectangular_fpc_default_config(struct( ...
    'plateLength', 80.0, 'plateWidth', 12.0, ...
    'traceWidth', 0.20, 'traceSpacing', 0.15, 'pitchMargin', 0.005, ...
    'coilOuterCornerRadiusMode', 'maximize', ...
    'cornerOffsetMode', 'strict_concentric', ...
    'viaPlacementMode', 'hybrid_auto', ...
    'turnsPerLayer', 8, ...
    'outputRoot', testCase.TestData.outputRoot, ...
    'designName', 'target_4layer_8turns', ...
    'enablePreview', false));

try
    result = rectangular_fpc_main(cfg);
    verifyTrue(testCase, result.passed);
catch ME
    if strcmp(ME.identifier, 'RectangularFPC:NoValidTurnCount') || ...
            strcmp(ME.identifier, 'RectangularFPC:ViaPlanningFailed')
        % 若确实无法通过，输出真实限制因素（诊断测试）
        verifyTrue(testCase, false, ...
            sprintf('4 层 8 匝目标未通过：%s', ME.message));
    else
        rethrow(ME);
    end
end

end

function testPreviewOutputUsesVectorSvgOnly(testCase)
    cfg = rectangular_fpc_default_config(struct( ...
        'layerCount', 4, ...
        'turnsPerLayer', 1, ...
        'enablePreview', true, ...
        'enableFigure', false, ...
        'outputRoot', testCase.TestData.outputRoot, ...
        'designName', 'svg_preview_contract'));
    result = rectangular_fpc_main(cfg);
    previewFolder = fullfile(result.outputFolder, 'previews');
    svgFiles = dir(fullfile(previewFolder, '*.svg'));
    pngFiles = dir(fullfile(previewFolder, '*.png'));
    assertNumElements(testCase, svgFiles, 7);
    names = sort({svgFiles.name});
    verifyEqual(testCase, names, {'01_preview_full.svg', '02_preview_right_tab.svg', '03_preview_pads_vias.svg', '04_preview_layer_L1_top.svg', '05_preview_layer_L2_inner1.svg', '06_preview_layer_L3_inner2.svg', '07_preview_layer_L4_bottom.svg'});
    verifyEmpty(testCase, pngFiles);
    for k = 1:numel(svgFiles)
        filename = fullfile(svgFiles(k).folder, svgFiles(k).name);
        xmlread(filename);
        content = fileread(filename);
        verifyNotEmpty(testCase, regexpi(content, '<svg(?:\s|>)', 'once'));
        verifyEmpty(testCase, regexpi(content, '<image(?:\s|>)', 'once'));
        verifyNotEmpty(testCase, regexpi(content, '<(?:path|polyline|polygon|line|circle|ellipse|rect|text)(?:\s|>)', 'once'));
    end

    % 右侧尾板预览必须真正聚焦右侧区域：viewBox 宽高比上限保护，
    % 防止范围外数据标签把画布横向撑宽。
    detailFile = fullfile(previewFolder, names{2});
    detailContent = fileread(detailFile);
    viewBoxTokens = regexp(detailContent, 'viewBox="([^"]+)"', 'tokens', 'once');
    verifyNotEmpty(testCase, viewBoxTokens);
    viewBoxNumbers = str2double(strsplit(viewBoxTokens{1}));
    detailWidth = viewBoxNumbers(3) - viewBoxNumbers(1);
    detailHeight = viewBoxNumbers(4) - viewBoxNumbers(2);
    verifyGreaterThan(testCase, detailWidth, 0);
    verifyGreaterThan(testCase, detailHeight, 0);
    verifyLessThan(testCase, detailWidth / detailHeight, 4);

    padViaContent = fileread(fullfile(previewFolder, '03_preview_pads_vias.svg'));
    verifyNotEmpty(testCase, regexp(padViaContent, 'PAD_A', 'once'));
    verifyNotEmpty(testCase, regexp(padViaContent, 'PAD_B', 'once'));
    verifyTrue(testCase, contains(padViaContent, 'V12 (L1-L2)'));
    verifyTrue(testCase, contains(padViaContent, 'V23 (L2-L3)'));
    verifyTrue(testCase, contains(padViaContent, 'V34 (L3-L4)'));
    verifyTrue(testCase, contains(padViaContent, 'VOUT (L4-L1)'));
    verifyNotEmpty(testCase, regexp(padViaContent, 'drill', 'once'));
    verifyNotEmpty(testCase, regexp(padViaContent, ...
        'non-connected-layer antipad', 'once'));
    for viaName = {'V12', 'V23', 'V34', 'VOUT'}
        verifyTrue(testCase, contains(padViaContent, ...
            sprintf('%s antipad', viaName{1})));
    end
    verifyEmpty(testCase, regexp(padViaContent, 'L1 coil', 'once'));

    l1Content = fileread(fullfile(previewFolder, '04_preview_layer_L1_top.svg'));
    verifyNotEmpty(testCase, regexp(l1Content, 'L1 coil', 'once'));
    verifyNotEmpty(testCase, regexp(l1Content, 'L1 output return', 'once'));
    verifyNotEmpty(testCase, regexp(l1Content, 'PAD_A', 'once'));
    verifyNotEmpty(testCase, regexp(l1Content, 'PAD_B', 'once'));
    verifyNotEmpty(testCase, regexp(l1Content, 'V12', 'once'));
    verifyNotEmpty(testCase, regexp(l1Content, 'VOUT', 'once'));
    verifyTrue(testCase, contains(l1Content, 'V23 antipad'));
    verifyTrue(testCase, contains(l1Content, 'V34 antipad'));

    l2Content = fileread(fullfile(previewFolder, '05_preview_layer_L2_inner1.svg'));
    verifyNotEmpty(testCase, regexp(l2Content, 'L2 coil', 'once'));
    verifyNotEmpty(testCase, regexp(l2Content, 'V12', 'once'));
    verifyNotEmpty(testCase, regexp(l2Content, 'V23', 'once'));
    verifyEmpty(testCase, regexp(l2Content, 'PAD_A', 'once'));
    verifyEmpty(testCase, regexp(l2Content, 'PAD_B', 'once'));
    verifyTrue(testCase, contains(l2Content, 'V34 antipad'));
    verifyTrue(testCase, contains(l2Content, 'VOUT antipad'));

    l3Content = fileread(fullfile(previewFolder, '06_preview_layer_L3_inner2.svg'));
    verifyNotEmpty(testCase, regexp(l3Content, 'L3 coil', 'once'));
    verifyNotEmpty(testCase, regexp(l3Content, 'V23', 'once'));
    verifyNotEmpty(testCase, regexp(l3Content, 'V34', 'once'));
    verifyEmpty(testCase, regexp(l3Content, 'PAD_A', 'once'));
    verifyEmpty(testCase, regexp(l3Content, 'PAD_B', 'once'));
    verifyTrue(testCase, contains(l3Content, 'V12 antipad'));
    verifyTrue(testCase, contains(l3Content, 'VOUT antipad'));

    l4Content = fileread(fullfile(previewFolder, '07_preview_layer_L4_bottom.svg'));
    verifyNotEmpty(testCase, regexp(l4Content, 'L4 coil', 'once'));
    verifyNotEmpty(testCase, regexp(l4Content, 'V34', 'once'));
    verifyNotEmpty(testCase, regexp(l4Content, 'VOUT', 'once'));
    verifyEmpty(testCase, regexp(l4Content, 'PAD_A', 'once'));
    verifyEmpty(testCase, regexp(l4Content, 'PAD_B', 'once'));
    verifyTrue(testCase, contains(l4Content, 'V12 antipad'));
    verifyTrue(testCase, contains(l4Content, 'V23 antipad'));

    cfg6 = fastConfig(6, testCase.TestData.outputRoot);
    cfg6.enablePreview = true;
    cfg6.designName = 'svg_preview_contract_6layer';
    result6 = rectangular_fpc_main(cfg6);
    previewFolder6 = fullfile(result6.outputFolder, 'previews');
    svgFiles6 = dir(fullfile(previewFolder6, '*.svg'));
    pngFiles6 = dir(fullfile(previewFolder6, '*.png'));
    assertNumElements(testCase, svgFiles6, 9);
    names6 = sort({svgFiles6.name});
    verifyEqual(testCase, names6, {'01_preview_full.svg', '02_preview_right_tab.svg', '03_preview_pads_vias.svg', '04_preview_layer_L1_top.svg', '05_preview_layer_L2_inner1.svg', '06_preview_layer_L3_inner2.svg', '07_preview_layer_L4_inner3.svg', '08_preview_layer_L5_inner4.svg', '09_preview_layer_L6_bottom.svg'});
    verifyEmpty(testCase, pngFiles6);
    for k = 1:numel(svgFiles6)
        filename6 = fullfile(svgFiles6(k).folder, svgFiles6(k).name);
        xmlread(filename6);
        content6 = fileread(filename6);
        verifyNotEmpty(testCase, regexpi(content6, '<svg(?:\s|>)', 'once'));
        verifyEmpty(testCase, regexpi(content6, '<image(?:\s|>)', 'once'));
        verifyNotEmpty(testCase, regexpi(content6, '<(?:path|polyline|polygon|line|circle|ellipse|rect|text)(?:\s|>)', 'once'));
    end
end

function testPadALeadUsesOrthogonalRunsAndRoundedTransition(testCase)

result = generatedFourLayerValidated(testCase.TestData.outputRoot);
cfg = rectangular_fpc_default_config(struct('turnsPerLayer', 1));
threshold = cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg;
tol = cfg.connectionTolerance;

vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
outerAnchor = vout.fromLeadPath(1, :);

padA = result.pads(strcmp({result.pads.name}, 'PAD_A'));
layer1 = result.layers(1).paths{1};
padAnchorIndex = find( ...
    vecnorm(layer1 - outerAnchor, 2, 2) <= tol, 1, 'first');
verifyNotEmpty(testCase, padAnchorIndex);
padAngle = localInteriorAngleDeg(padA.xy, outerAnchor, ...
    layer1(padAnchorIndex + 1, :));
verifyGreaterThan(testCase, padAngle, threshold);
padLead = layer1(1:padAnchorIndex, :);
[runCount, totalTurnDeg] = localCurvatureSummary(padLead);
verifyGreaterThanOrEqual(testCase, runCount, 1);
verifyGreaterThan(testCase, totalTurnDeg, 1);
maxArcChord = 2 * cfg.leadBendRadius * sin(pi / (4 * cfg.leadArcPointCount)) ...
    + 10 * cfg.geometryTolerance;
axialTol = 10 * cfg.geometryTolerance;
segDx = diff(padLead(:, 1));
segDy = diff(padLead(:, 2));
segLen = hypot(segDx, segDy);
longMask = segLen > maxArcChord;
axialMask = abs(segDx) <= axialTol | abs(segDy) <= axialTol;
verifyTrue(testCase, any(longMask));
verifyTrue(testCase, all(axialMask(longMask)));

end

function testViaLeadsUseOrthogonalRunsAndRoundedTransitions(testCase)

result = generatedFourLayerValidated(testCase.TestData.outputRoot);
cfg = rectangular_fpc_default_config(struct('turnsPerLayer', 1));
threshold = cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg;

viaNames = {'V12', 'V23', 'V34', 'VOUT'};
pathCount = 0;
longSegmentCount = 0;
for k = 1:numel(viaNames)
    via = result.vias(strcmp({result.vias.name}, viaNames{k}));
    verifyNumElements(testCase, via, 1);
    [viaPathCount, viaLongSegmentCount] = ...
        localVerifyViaLeadSegments(testCase, via, cfg);
    pathCount = pathCount + viaPathCount;
    longSegmentCount = longSegmentCount + viaLongSegmentCount;
end

verifyGreaterThan(testCase, pathCount, 0);
verifyGreaterThan(testCase, longSegmentCount, 0);
verifyGreaterThan(testCase, result.minCopperAngle, threshold);

end

function testHybridAutoSeriesViasArePackedNearestCoilAnchors(testCase)

result = generatedFourLayerValidated(testCase.TestData.outputRoot);
cfg = rectangular_fpc_default_config(struct('turnsPerLayer', 1));
tol = cfg.geometryTolerance;

pitch = cfg.traceWidth + cfg.traceSpacing + cfg.pitchMargin;
outerCenterInset = cfg.edgeClearance + cfg.traceWidth/2;
innerCenterInset = outerCenterInset + cfg.turnsPerLayer * pitch;
innerHalfL = (cfg.plateLength - 2 * innerCenterInset) / 2;
requiredViaToCopperCenter = cfg.viaPadDiameter/2 + cfg.traceWidth/2 + ...
    cfg.viaToCopperClearance + cfg.viaKeepoutMargin;
expectedInnerRight = innerHalfL - requiredViaToCopperCenter - cfg.traceWidth/2;
actualViaPitch = max(cfg.innerViaPitch, ...
    cfg.viaPadDiameter + cfg.viaToViaClearance);
expectedOuterX = cfg.plateLength/2 + cfg.viaPadDiameter/2 + ...
    cfg.viaToBoardClearance;

verifyTrue(testCase, result.passed);

viaNames = {'V12', 'V23', 'V34'};
expectedXY = { ...
    [expectedInnerRight, cfg.innerViaRowOffsetY], ...
    [expectedOuterX, cfg.outerViaRowOffsetY], ...
    [expectedInnerRight - actualViaPitch, cfg.innerViaRowOffsetY]};
maxLeadLengths = [2.5, 2.5, 4.5];
for k = 1:numel(viaNames)
    via = result.vias(strcmp({result.vias.name}, viaNames{k}));
    verifyNumElements(testCase, via, 1);
    verifyEqual(testCase, via.xy, expectedXY{k}, 'AbsTol', tol);
    verifyTrue(testCase, ~isnan(via.fromLeadLength));
    verifyTrue(testCase, ~isnan(via.toLeadLength));
    verifyLessThan(testCase, ...
        max(via.fromLeadLength, via.toLeadLength), maxLeadLengths(k));
end

end

function testOutputViaUsesViaClearanceDuringTabViaPlanning(testCase)

cfg = rectangular_fpc_default_config(struct( ...
    'layerCount', 4, ...
    'turnsPerLayer', 1, ...
    'leadYOffset', 1.10, ...
    'enablePreview', false, ...
    'viaClearanceSeverity', 'error', ...
    'outputRoot', testCase.TestData.outputRoot, ...
    'designName', 'red_vout_uses_via_clearance'));
result = rectangular_fpc_main(cfg);
tol = cfg.geometryTolerance;

verifyTrue(testCase, result.passed);

v23 = result.vias(strcmp({result.vias.name}, 'V23'));
vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
verifyNumElements(testCase, v23, 1);
verifyNumElements(testCase, vout, 1);

expectedV23XY = [cfg.plateLength/2 + cfg.viaPadDiameter/2 + ...
    cfg.viaToBoardClearance, cfg.outerViaRowOffsetY];
verifyEqual(testCase, v23.xy, expectedV23XY, 'AbsTol', tol);

minViaToVia = cfg.viaPadDiameter + cfg.viaToViaClearance;
minPadDist = cfg.viaPadDiameter/2 + cfg.padDiameter/2 + cfg.viaToPadClearance;
centerDistance = norm(v23.xy - vout.xy);
verifyGreaterThanOrEqual(testCase, centerDistance, minViaToVia - tol);
verifyLessThan(testCase, centerDistance, minPadDist - tol);

end

function testAutoVoutUsesNearestSafeTabLocation(testCase)

result = generatedFourLayerValidated(testCase.TestData.outputRoot);
cfg = rectangular_fpc_default_config(struct('turnsPerLayer', 1));
tol = cfg.geometryTolerance;

expectedVoutXY = [cfg.plateLength/2 + cfg.viaPadDiameter/2 + ...
    cfg.outputViaToBoardClearance, -cfg.leadYOffset];
expectedPadBXY = [cfg.plateLength/2 + cfg.tabLength - cfg.padTipInset, ...
    -cfg.leadYOffset];

verifyTrue(testCase, result.passed);

vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
verifyNumElements(testCase, vout, 1);
verifyEqual(testCase, vout.xy, expectedVoutXY, 'AbsTol', tol);
verifyLessThan(testCase, vout.fromLeadLength, 3.0);

padB = result.pads(strcmp({result.pads.name}, 'PAD_B'));
verifyNumElements(testCase, padB, 1);
verifyEqual(testCase, padB.xy, expectedPadBXY, 'AbsTol', tol);

returnPath = result.layers(1).paths{2};
verifyEqual(testCase, returnPath(1, :), vout.xy, 'AbsTol', tol);
verifyEqual(testCase, returnPath(end, :), padB.xy, 'AbsTol', tol);
verifyGreaterThan(testCase, sum(hypot(diff(returnPath(:, 1)), ...
    diff(returnPath(:, 2)))), 8.0);

end

function testAutoVoutRejectsEmptyInsetRange(testCase)

cfg = fastConfig(4, testCase.TestData.outputRoot);
cfg.designName = 'auto_vout_empty_inset_red';
cfg.outputViaTipInset = 11.5;

verifyError(testCase, @() rectangular_fpc_main(cfg), 'RectangularFPC:ViaPlanningFailed');

end

function testLeadRoutingPreservesRawSpiralCoordinates(testCase)

cfg = fastConfig(4, testCase.TestData.outputRoot);
cfg.designName = 'routing_body_fixture';
result = rectangular_fpc_main(cfg);
tol = cfg.connectionTolerance;
pointCount = cfg.turnsPerLayer * ...
    max(cfg.pointsPerTurn, cfg.minTurnPointCount) + 1;
vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
v12 = result.vias(strcmp({result.vias.name}, 'V12'));
outerAnchor = vout.fromLeadPath(1, :);
innerAnchor = v12.fromLeadPath(1, :);
expectedHashes = { ...
    'd3936e76936b1bd8c6dfa97fd1ff2c98561da2aa872b56fef2d94cacd4e6f9a1', ...
    'b3fd4c80ec95ba4016f9866e644a5ad05f5c5ae7557393d5cf445290751ed186'};

for layerIndex = 1:cfg.layerCount
    path = result.layers(layerIndex).paths{1};
    if mod(layerIndex, 2) == 1
        anchor = outerAnchor;
        expectedHash = expectedHashes{1};
    else
        anchor = innerAnchor;
        expectedHash = expectedHashes{2};
    end
    anchorIndex = find( ...
        vecnorm(path - anchor, 2, 2) <= tol, 1, 'first');
    verifyNotEmpty(testCase, anchorIndex);
    verifyGreaterThanOrEqual(testCase, ...
        size(path, 1) - anchorIndex + 1, pointCount);
    body = path(anchorIndex:anchorIndex + pointCount - 1, :);
    verifyEqual(testCase, localCoordinateSha256(body), expectedHash);
end

end

function testDefaultRightPadGroupIsCompactAndBalanced(testCase)

cfg = rectangular_fpc_default_config(struct( ...
    'layerCount', 4, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'viaClearanceSeverity', 'error', ...
    'outputRoot', testCase.TestData.outputRoot, ...
    'designName', 'red_compact_pad_group'));

tol = cfg.geometryTolerance;

verifyEqual(testCase, cfg.leadYOffset, 1.10, 'AbsTol', tol);

result = rectangular_fpc_main(cfg);
verifyTrue(testCase, result.passed);

padA = result.pads(strcmp({result.pads.name}, 'PAD_A'));
padB = result.pads(strcmp({result.pads.name}, 'PAD_B'));
v23 = result.vias(strcmp({result.vias.name}, 'V23'));
vout = result.vias(strcmp({result.vias.name}, 'VOUT'));
verifyNumElements(testCase, padA, 1);
verifyNumElements(testCase, padB, 1);
verifyNumElements(testCase, v23, 1);
verifyNumElements(testCase, vout, 1);

expectedPadX = cfg.plateLength/2 + cfg.tabLength - cfg.padTipInset;
expectedVoutX = cfg.plateLength/2 + cfg.viaPadDiameter/2 + ...
    cfg.outputViaToBoardClearance;
expectedV23X = cfg.plateLength/2 + cfg.viaPadDiameter/2 + ...
    cfg.viaToBoardClearance;

verifyEqual(testCase, padA.xy, [expectedPadX, +1.10], 'AbsTol', tol);
verifyEqual(testCase, padB.xy, [expectedPadX, -1.10], 'AbsTol', tol);
verifyEqual(testCase, vout.xy, [expectedVoutX, -1.10], 'AbsTol', tol);
verifyEqual(testCase, v23.xy, ...
    [expectedV23X, cfg.outerViaRowOffsetY], 'AbsTol', tol);

padGap = norm(padA.xy - padB.xy) - cfg.padDiameter;
topEdgeGap = cfg.tabWidth/2 - (padA.xy(2) + cfg.padDiameter/2);
bottomEdgeGap = (padB.xy(2) - cfg.padDiameter/2) - (-cfg.tabWidth/2);

verifyEqual(testCase, padGap, 0.70, 'AbsTol', tol);
verifyEqual(testCase, topEdgeGap, 0.65, 'AbsTol', tol);
verifyEqual(testCase, bottomEdgeGap, 0.65, 'AbsTol', tol);
verifyGreaterThanOrEqual(testCase, padGap, cfg.padToPadClearance - tol);
verifyLessThanOrEqual(testCase, abs(padGap - topEdgeGap), 0.05 + tol);
verifyLessThanOrEqual(testCase, abs(padGap - bottomEdgeGap), 0.05 + tol);
verifyGreaterThanOrEqual(testCase, ...
    norm(v23.xy - vout.xy), cfg.viaPadDiameter + cfg.viaToViaClearance - tol);

overrideCfg = rectangular_fpc_default_config(struct('leadYOffset', 1.30));
verifyEqual(testCase, overrideCfg.leadYOffset, 1.30);

end

function angleDeg = localInteriorAngleDeg(previousPt, junctionPt, nextPt)

v1 = previousPt - junctionPt;
v2 = nextPt - junctionPt;
cosAngle = dot(v1, v2) / (norm(v1) * norm(v2));
angleDeg = acosd(max(-1, min(1, cosAngle)));

end

function [runCount, totalTurnDeg] = localCurvatureSummary(path)

segments = diff(path, 1, 1);
headings = atan2(segments(:, 2), segments(:, 1));
delta = atan2(sin(diff(headings)), cos(diff(headings)));
curved = abs(delta) > deg2rad(1e-4);
runCount = sum(diff([false; curved; false]) == 1);
totalTurnDeg = sum(abs(rad2deg(delta)));

end

function [pathCount, longSegmentCount] = localVerifyViaLeadSegments( ...
    testCase, via, cfg)

pathCount = 0;
longSegmentCount = 0;
if strcmp(via.name, 'VOUT')
    bendRadius = cfg.leadBendRadius;
else
    series = floor(str2double(via.name(2:end)) / 10);
    if mod(series, 2) == 1
        bendRadius = cfg.viaInnerBendRadius;
    else
        bendRadius = cfg.viaOuterBendRadius;
    end
end
maxArcChord = 2 * bendRadius * sin(pi / (4 * cfg.leadArcPointCount)) ...
    + 10 * cfg.geometryTolerance;

leadFields = {'fromLeadPath', 'from'; 'toLeadPath', 'to'};
for fieldIndex = 1:size(leadFields, 1)
    leadPath = via.(leadFields{fieldIndex, 1});
    if isempty(leadPath) || size(leadPath, 1) < 2
        continue;
    end
    pathCount = pathCount + 1;
    segDx = diff(leadPath(:, 1));
    segDy = diff(leadPath(:, 2));
    segLen = hypot(segDx, segDy);
    for segIndex = 1:numel(segLen)
        if segLen(segIndex) <= maxArcChord
            continue;
        end
        longSegmentCount = longSegmentCount + 1;
        isAxial = abs(segDx(segIndex)) <= 10 * cfg.geometryTolerance || ...
            abs(segDy(segIndex)) <= 10 * cfg.geometryTolerance;
        verifyTrue(testCase, isAxial, sprintf( ...
            '%s.%sLeadPath long segment %d: length=%.6f mm, dx=%.6f, dy=%.6f', ...
            via.name, leadFields{fieldIndex, 2}, segIndex, ...
            segLen(segIndex), segDx(segIndex), segDy(segIndex)));
    end
end

end

function hashText = localCoordinateSha256(xy)

textValue = sprintf('%.17g,%.17g\n', xy.');
digest = java.security.MessageDigest.getInstance('SHA-256');
hashBytes = typecast(digest.digest(uint8(textValue)), 'uint8');
hashText = lower(reshape(dec2hex(hashBytes, 2).', 1, []));

end

function hashText = localQuantizedCoordinateSha256(xy)

quantized = int64(round(xy / 1e-4));
textValue = sprintf('%d,%d\n', quantized.');
digest = java.security.MessageDigest.getInstance('SHA-256');
hashBytes = typecast(digest.digest(uint8(textValue)), 'uint8');
hashText = lower(reshape(dec2hex(hashBytes, 2).', 1, []));

end

function hashText = localQuantizedPathSetSha256(paths)

digest = java.security.MessageDigest.getInstance('SHA-256');
for pathIndex = 1:numel(paths)
    digest.update(uint8(sprintf('path=%d\n', pathIndex)));
    quantized = int64(round(paths{pathIndex} / 1e-4));
    digest.update(uint8(sprintf('%d,%d\n', quantized.')));
end
hashBytes = typecast(digest.digest(), 'uint8');
hashText = lower(reshape(dec2hex(hashBytes, 2).', 1, []));

end

function cfg = fastConfig(layerCount, outputRoot)

cfg = rectangular_fpc_default_config(struct( ...
    'layerCount', layerCount, ...
    'turnsPerLayer', 1, ...
    'useRecommendedTurns', false, ...
    'pointsPerTurn', 100, ...
    'minTurnPointCount', 100, ...
    'boardArcPointCount', 8, ...
    'leadArcPointCount', 8, ...
    'enablePreview', false, ...
    'requireSmoothLeadTransitions', false, ...
    'enableDxfReadbackCheck', false, ...
    'enableExactSelfIntersectionCheck', false, ...
    'enableCopperClearanceCheck', false, ...
    'enableBoardAngleCheck', false, ...
    'enableCopperAngleCheck', false, ...
    'enablePadClearanceCheck', false, ...
    'enableViaClearanceCheck', false, ...
    'outputRoot', outputRoot, ...
    'designName', sprintf('behavior_%dlayer', layerCount)));
if ismember(layerCount, [2, 4])
    cfg.analysisOnly = true;
end

end

function result = generatedSixLayerDesign(outputRoot)

persistent cachedOutputRoot cachedResult

if isempty(cachedResult) || ~strcmp(cachedOutputRoot, outputRoot)
    cfg = fastConfig(6, outputRoot);
    cachedResult = rectangular_fpc_main(cfg);
    cachedOutputRoot = outputRoot;
end
result = cachedResult;

end

function result = generatedEightLayerValidated(outputRoot)

persistent cachedOutputRoot cachedResult

if isempty(cachedResult) || ~strcmp(cachedOutputRoot, outputRoot)
    cfg = rectangular_fpc_default_config(struct( ...
        'layerCount', 8, ...
        'turnsPerLayer', 1, ...
        'outputRoot', outputRoot, ...
        'designName', 'validated_8layer', ...
        'enablePreview', false));
    cachedResult = rectangular_fpc_main(cfg);
    cachedOutputRoot = outputRoot;
end
result = cachedResult;

end

function result = generatedFourLayerValidated(outputRoot)

persistent cachedOutputRoot cachedResult

if isempty(cachedResult) || ~strcmp(cachedOutputRoot, outputRoot)
    cfg = rectangular_fpc_default_config(struct( ...
        'layerCount', 4, ...
        'turnsPerLayer', 1, ...
        'outputRoot', outputRoot, ...
        'designName', 'validated_4layer_strict_angle', ...
        'enablePreview', false));
    cachedResult = rectangular_fpc_main(cfg);
    cachedOutputRoot = outputRoot;
end
result = cachedResult;

end

function xyUser = localInternalToUserXY(xyInternal, cfg)

xyUser = xyInternal + [cfg.plateLength/2, cfg.plateWidth/2];

end
