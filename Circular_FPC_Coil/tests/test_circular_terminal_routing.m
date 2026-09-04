function tests = test_circular_terminal_routing
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
testCase.TestData.projectRoot = projectRoot;
end

function testDefaultTerminalParameters(testCase)
cfg = circular_fpc_default_config(struct('designName', 'terminal_default_contract'));
verifyEqual(testCase, cfg.terminalLeadSpacing, 2.0, 'AbsTol', 1e-12);
verifyEqual(testCase, cfg.terminalLeadLength, 1.5, 'AbsTol', 1e-12);
verifyEqual(testCase, cfg.padPairSpacing, cfg.terminalLeadSpacing, 'AbsTol', 1e-12);
end

function testFourTwoDeterministicPadAndVoutGeometry(testCase)
d = 2.2;
L = 1.6;
r = analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, ...
    'terminalLeadSpacing', d, 'terminalLeadLength', L, ...
    'designName', 'terminal_42'));
verifyTrue(testCase, r.validation.passed);
padA = r.pads(strcmp({r.pads.name}, 'PAD_A'));
padB = r.pads(strcmp({r.pads.name}, 'PAD_B'));
vout = r.vias(strcmp({r.vias.name}, 'VOUT'));
verifyEqual(testCase, norm(padB.xy - padA.xy), d, 'AbsTol', 1e-6);
verifyEqual(testCase, norm(padB.xy - vout.xy), L, 'AbsTol', 1e-6);
verifyEqual(testCase, r.terminalRouting.bendRadiusMm, ...
    r.terminalRouting.entryBendRadiusMm, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, r.terminalRouting.entryBendRadiusMm, 0);
verifyGreaterThan(testCase, r.terminalRouting.outputBendRadiusMm, 0);
verifyGreaterThan(testCase, r.terminalRouting.entrySweepDeg, 90.1);
verifyGreaterThan(testCase, r.terminalRouting.outputSweepDeg, 90.1);
verifyEqual(testCase, r.terminalRouting.entryBendCount, 1);
verifyEqual(testCase, r.terminalRouting.outputBendCount, 1);
verifyEqual(testCase, r.terminalRouting.exitBendCount, 0);
end

function testAutomaticBendsAreSingleTangentCircles(testCase)
r = analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'designName', 'terminal_circle_contract'));
u = [cosd(r.config.connectionAngleDeg), sind(r.config.connectionAngleDeg)];

entryArc = r.terminalRouting.entryPath(end - 48:end, :);
assertCircularArc(testCase, entryArc, ...
    r.terminalRouting.entryBendRadiusMm, ...
    r.terminalRouting.entrySweepDeg);
entryCenter = threePointCircleCenter(entryArc(1, :), ...
    entryArc(ceil(end / 2), :), entryArc(end, :));
entryEndTangent = unitVector(r.layerPaths(1).coilXY(2, :) - ...
    r.layerPaths(1).coilXY(1, :));
verifyLessThan(testCase, abs(dot(unitVector(entryArc(1, :) - ...
    entryCenter), u)), 1e-9);
verifyLessThan(testCase, abs(dot(unitVector(entryArc(end, :) - ...
    entryCenter), entryEndTangent)), 1e-9);

outputArc = r.terminalRouting.outputPath;
assertCircularArc(testCase, outputArc, ...
    r.terminalRouting.outputBendRadiusMm, ...
    r.terminalRouting.outputSweepDeg);
outputCenter = threePointCircleCenter(outputArc(1, :), ...
    outputArc(ceil(end / 2), :), outputArc(end, :));
lastLayer = r.activeCoilLayers(end);
outputStartTangent = unitVector(r.layerPaths(lastLayer).coilXY(end, :) - ...
    r.layerPaths(lastLayer).coilXY(end - 1, :));
verifyLessThan(testCase, abs(dot(unitVector(outputArc(1, :) - ...
    outputCenter), outputStartTangent)), 1e-9);
verifyLessThan(testCase, abs(dot(unitVector(outputArc(end, :) - ...
    outputCenter), -u)), 1e-9);
end

function testSingleCoilOutputBendMetadataIsExplicitlyAbsent(testCase)
for boardLayers = [2, 4]
    r = analyzeInternal(struct( ...
        'boardLayerCount', boardLayers, ...
        'coilLayerCount', 1, ...
        'designName', sprintf('single_coil_metadata_%d', boardLayers)));
    verifyEmpty(testCase, r.terminalRouting.outputPath);
    verifyEqual(testCase, r.terminalRouting.outputBendCount, 0);
    verifyTrue(testCase, isnan(r.terminalRouting.outputBendRadiusMm));
    verifyTrue(testCase, isnan(r.terminalRouting.outputSweepDeg));
    verifyEqual(testCase, r.terminalRouting.outputPhaseOffsetDeg, 0, ...
        'AbsTol', 1e-12);
end
end

function testTerminalBendSweepsStrictlyExceedNinety(testCase)
% Measure the complete single bend, not the small heading increment between
% adjacent sampled arc segments.
combos = [2 1; 2 2; 4 1; 4 2; 4 4];
for row = 1:size(combos, 1)
    r = analyzeInternal(struct( ...
        'boardLayerCount', combos(row, 1), ...
        'coilLayerCount', combos(row, 2), ...
        'designName', sprintf('terminal_sweep_%d_%d', combos(row, 1), combos(row, 2))));
    entrySweep = netPathHeadingSweepDeg(r.terminalRouting.entryPath);
    verifyGreaterThan(testCase, entrySweep, 90.1, ...
        sprintf('%d/%d L1 entry sweep must be strictly >90.1 deg (got %.6f).', ...
        combos(row, 1), combos(row, 2), entrySweep));
    verifyEqual(testCase, curvatureSignChanges(r.terminalRouting.entryPath), 0, ...
        sprintf('%d/%d L1 entry must remain one curvature direction.', ...
        combos(row, 1), combos(row, 2)));

    if combos(row, 2) > 1
        outputSweep = netPathHeadingSweepDeg(r.terminalRouting.outputPath);
        verifyGreaterThan(testCase, outputSweep, 90.1, ...
            sprintf('%d/%d final-layer output sweep must be strictly >90.1 deg (got %.6f).', ...
            combos(row, 1), combos(row, 2), outputSweep));
        verifyEqual(testCase, curvatureSignChanges(r.terminalRouting.outputPath), 0, ...
            sprintf('%d/%d final-layer output must remain one curvature direction.', ...
            combos(row, 1), combos(row, 2)));
    end
end
end

function testExitIsStraightAndParallelLeadSpacing(testCase)
r = analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, ...
    'terminalLeadSpacing', 2.0, 'terminalLeadLength', 1.5, ...
    'designName', 'terminal_straight_exit'));
u = [cosd(r.config.connectionAngleDeg), sind(r.config.connectionAngleDeg)];
t = [-sind(r.config.connectionAngleDeg), cosd(r.config.connectionAngleDeg)];
exitPath = r.terminalRouting.exitPath;
delta = exitPath(end,:) - exitPath(1,:);
verifyLessThanOrEqual(testCase, abs(dot(delta, t)), 1e-9);
verifyEqual(testCase, abs(dot(delta, u)), r.config.terminalLeadLength, 'AbsTol', 1e-6);
padA = r.pads(strcmp({r.pads.name}, 'PAD_A')).xy;
padB = r.pads(strcmp({r.pads.name}, 'PAD_B')).xy;
verifyEqual(testCase, abs(dot(padB-padA, t)), r.config.terminalLeadSpacing, 'AbsTol', 1e-6);
verifyLessThanOrEqual(testCase, abs(dot(padB-padA, u)), 1e-6);
end

function testTooShortOutputLeadIsRejected(testCase)
verifyError(testCase, @() analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, ...
    'terminalLeadLength', 0.5, 'designName', 'terminal_too_short')), ...
    'CircularFPC:TerminalPlacementInvalid');
end

function testOutputLeadCannotCrossBoardCenter(testCase)
% A very long inward lead places both pads on the wrong side of the coil.
verifyError(testCase, @() analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, ...
    'terminalLeadLength', 10, 'designName', 'terminal_crosses_center')), ...
    'CircularFPC:TerminalPlacementInvalid');
end

function testAntipadIsNotAPublicGeometryControl(testCase)
% These are ordinary plated through-vias.  A separate large antipad is not
% part of this signal-layer FPC geometry and must not remain in the config API.
verifyError(testCase, @() circular_fpc_default_config(struct( ...
    'antipadDiameter', 1.2)), 'CircularFPC:UnknownConfigField');
end

function testCopperSpacingUsesContinuousSegments(testCase)
% With coarse sampling the vertex gap is 0.1501 mm, while the actual
% segment-to-segment clearance is about 0.14968 mm and must be rejected.
verifyError(testCase, @() analyzeInternal(struct( ...
    'boardLayerCount', 2, 'coilLayerCount', 2, ...
    'samplePointsPerTurn', 72, 'pitchMargin', 1e-4, ...
    'designName', 'continuous_segment_spacing')), ...
    'CircularFPC:ValidationFailed');
end

function testLayerPreviewShowsIdenticalThroughViasOnEveryLayer(testCase)
root = tempname;
mkdir(root);
cleanup = onCleanup(@() removeTree(root)); %#ok<NASGU>
result = circular_fpc_main(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'analysisOnly', false, 'enableFigure', false, 'enablePreview', true, ...
    'outputRoot', root, 'designName', 'layer_via_semantics'));

verifyEqual(testCase, [result.vias.padDiameter], ...
    repmat(result.config.viaPadDiameter, 1, numel(result.vias)), 'AbsTol', 1e-12);
verifyEqual(testCase, [result.vias.drillDiameter], ...
    repmat(result.config.viaDrillDiameter, 1, numel(result.vias)), 'AbsTol', 1e-12);
layerFiles = { ...
    '03_preview_layer_L1_top.svg', ...
    '04_preview_layer_L2_inner1.svg', ...
    '05_preview_layer_L3_inner2.svg', ...
    '06_preview_layer_L4_bottom.svg'};
for li = 1:numel(layerFiles)
    svg = fileread(fullfile(result.outputPath, 'previews', layerFiles{li}));
    verifyTrue(testCase, ~isempty(regexp(svg, ...
        'fill="#ffcc1a"\s+fill-opacity="1(?:\.0+)?"', 'once')), ...
        sprintf('%s must render the yellow board material as opaque.', layerFiles{li}));
    verifyFalse(testCase, contains(svg, 'fill="#ffcc1a" fill-opacity="0.45"'), ...
        sprintf('%s must not render translucent board material.', layerFiles{li}));
    for k = 1:numel(result.vias)
        name = result.vias(k).name;
        verifyTrue(testCase, contains(svg, sprintf( ...
            'data-via-name="%s" data-via-role="copper-ring"', name)));
        verifyTrue(testCase, contains(svg, sprintf( ...
            'data-via-name="%s" data-via-role="drill"', name)));
        ringPattern = sprintf(['data-via-name="%s" ', ...
            'data-via-role="copper-ring"[^>]*r="%.6f"'], ...
            name, result.config.viaPadDiameter / 2);
        drillPattern = sprintf(['data-via-name="%s" ', ...
            'data-via-role="drill"[^>]*r="%.6f"'], ...
            name, result.config.viaDrillDiameter / 2);
        verifyEqual(testCase, numel(regexp(svg, ringPattern, 'match')), 1);
        verifyEqual(testCase, numel(regexp(svg, drillPattern, 'match')), 1);
    end
    verifyFalse(testCase, contains(svg, 'data-via-role="antipad"'));
    verifyFalse(testCase, contains(svg, 'stroke-dasharray'));
end
end

function sweep = netPathHeadingSweepDeg(path)
segments = diff(path, 1, 1);
segments = segments(sqrt(sum(segments.^2, 2)) > 1e-10, :);
if size(segments, 1) < 2
    sweep = 0;
    return;
end
heading = unwrap(atan2(segments(:, 2), segments(:, 1)));
sweep = abs(rad2deg(heading(end) - heading(1)));
end

function count = curvatureSignChanges(path)
segments = diff(path, 1, 1);
segments = segments(sqrt(sum(segments.^2, 2)) > 1e-10, :);
if size(segments, 1) < 3
    count = 0;
    return;
end
heading = unwrap(atan2(segments(:, 2), segments(:, 1)));
turns = diff(heading);
turns = turns(abs(turns) > deg2rad(0.02));
if isempty(turns)
    count = 0;
else
    signs = sign(turns);
    count = sum(signs(2:end) ~= signs(1:end - 1));
end
end

function assertCircularArc(testCase, path, expectedRadius, expectedSweepDeg)
center = threePointCircleCenter(path(1, :), ...
    path(ceil(end / 2), :), path(end, :));
radii = sqrt(sum((path - center).^2, 2));
verifyEqual(testCase, radii, repmat(expectedRadius, size(radii)), ...
    'AbsTol', 1e-7);
v1 = unitVector(path(1, :) - center);
v2 = unitVector(path(end, :) - center);
sweep = mod(rad2deg(atan2(v1(1) * v2(2) - v1(2) * v2(1), ...
    dot(v1, v2))), 360);
verifyEqual(testCase, sweep, expectedSweepDeg, 'AbsTol', 1e-7);
end

function center = threePointCircleCenter(a, b, c)
matrix = 2 * [b - a; c - a];
rhs = [dot(b, b) - dot(a, a); dot(c, c) - dot(a, a)];
verifyCondition = abs(det(matrix));
if verifyCondition <= 1e-12
    error('CircularFPC:TestDegenerateCircle', ...
        'Three arc points do not define a stable circle.');
end
center = (matrix \ rhs).';
end

function value = unitVector(value)
value = value / norm(value);
end

function result = analyzeInternal(overrides)
% 测试适配器：通过唯一公共主入口进入只读分析模式。
if nargin < 1
    overrides = struct();
end
overrides.analysisOnly = true;
result = circular_fpc_main(overrides);
end

function removeTree(pathName)
if isfolder(pathName)
    rmdir(pathName, 's');
end
end
