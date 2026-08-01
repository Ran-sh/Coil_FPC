function tests = test_fpc_coil_regressions
% Regression tests for the reviewed FPC coil geometry and reporting fixes.

tests = functiontests(localfunctions);

end

function testConfigurationExposesDedicatedClearancesAndRadii(testCase)

mainText = fileread('fpc_coil_main.m');
verifyNotEmpty(testCase, regexp(mainText, ...
    'cfg\.viaToPadClearance\s*=\s*0\.20', 'once'));
verifyNotEmpty(testCase, regexp(mainText, ...
    'cfg\.viaInnerBendRadius\s*=\s*0\.50', 'once'));

end

function testFinalGeometryDrivesConnectionErrors(testCase)

generatorText = fileread('fpc_coil_generate.m');
verifyNotEmpty(testCase, regexp(generatorText, ...
    'connectionErrors\(k\)\s*=\s*norm\(\s*layerXY\{k\}\(end,:\)\s*-\s*layerXY\{k\+1\}\(1,:\)\)', ...
    'once'));

end

function testCircularObjectsMustBeInsideBoard(testCase)

generatorText = fileread('fpc_coil_generate.m');
verifyGreaterThanOrEqual(testCase, ...
    numel(regexp(generatorText, 'inpolygon\(', 'match')), 2);

end

function testReportsDistinguishWidthAndValidatedLimits(testCase)

generatorText = fileread('fpc_coil_generate.m');
verifyNotEmpty(testCase, regexp(generatorText, ...
    'Width-based maximum turns', 'once'));
verifyNotEmpty(testCase, regexp(generatorText, ...
    'Fully validated maximum turns', 'once'));
verifyEmpty(testCase, regexp(generatorText, ...
    'Maximum recommended\s*:', 'once'));

end

function testEscapeLeadUsesTrimmedFillet(testCase)

generatorText = fileread('fpc_coil_generate.m');
verifyNotEmpty(testCase, regexp(generatorText, ...
    'trimDistance\s*=\s*radius\s*\*\s*tan\(', 'once'));
verifyNotEmpty(testCase, regexp(generatorText, ...
    'xy\s*=\s*\[trimmedXY\(1:trimSegmentIndex,:\);\s*arcXY', 'once'));

end
