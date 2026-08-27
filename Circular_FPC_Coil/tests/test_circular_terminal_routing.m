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
r = circular_fpc_analyze(struct( ...
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
r = circular_fpc_analyze(struct( ...
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
verifyError(testCase, @() circular_fpc_analyze(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, ...
    'terminalLeadLength', 0.5, 'designName', 'terminal_too_short')), ...
    'CircularFPC:TerminalPlacementInvalid');
end
