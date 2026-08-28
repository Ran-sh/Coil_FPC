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
verifyEqual(testCase, r.terminalRouting.bendRadiusMm, d/2, 'AbsTol', 1e-12);
verifyEqual(testCase, r.terminalRouting.entryBendCount, 1);
verifyEqual(testCase, r.terminalRouting.outputBendCount, 1);
verifyEqual(testCase, r.terminalRouting.exitBendCount, 0);
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

function testAntipadProtectsEveryUnconnectedCopperLayer(testCase)
% The configured antipad, not merely the drill, is the no-copper envelope.
verifyError(testCase, @() analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'antipadDiameter', 20, 'designName', 'antipad_must_clear_copper')), ...
    'CircularFPC:GeometryInfeasible');
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

function testLayerPreviewDistinguishesCopperRingAndAntipad(testCase)
root = tempname;
mkdir(root);
cleanup = onCleanup(@() removeTree(root)); %#ok<NASGU>
result = circular_fpc_main(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'analysisOnly', false, 'enableFigure', false, 'enablePreview', true, ...
    'outputRoot', root, 'designName', 'layer_via_semantics'));

v12 = result.vias(strcmp({result.vias.name}, 'V12'));
verifyEqual(testCase, sort([v12.fromLayer, v12.toLayer]), [1 2]);
layer1 = fullfile(result.outputPath, 'previews', '03_preview_layer_L1_top.svg');
layer3 = fullfile(result.outputPath, 'previews', '05_preview_layer_L3_inner2.svg');
svg1 = fileread(layer1);
svg3 = fileread(layer3);
verifyTrue(testCase, contains(svg1, 'data-via-name="V12" data-via-role="copper-ring"'));
verifyTrue(testCase, contains(svg3, 'data-via-name="V12" data-via-role="antipad"'));
verifyTrue(testCase, contains(svg3, 'data-via-name="V12" data-via-role="drill"'));
verifyFalse(testCase, contains(svg3, 'data-via-name="V12" data-via-role="copper-ring"'));
verifyFalse(testCase, contains(svg3, 'stroke-dasharray'));
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
