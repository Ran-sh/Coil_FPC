function tests = test_rectangular_fpc_publish_paths
% Pure path-contract tests: no publisher call and no recursive cleanup.
tests = functiontests(localfunctions);
end

function testRejectsWindowsDriveRootBeforeFilesystemMutation(testCase)
driveRoot = char(java.io.File(pwd).toPath().getRoot());
staging = fullfile(tempdir, 'rectangular_fpc_path_validation_stage');

verifyError(testCase, @() rectangular_fpc_publish_paths( ...
    'validate', staging, driveRoot), ...
    'RectangularFPC:InvalidPublishRequest');
end

function testRejectsUncShareRootWithoutProbingShare(testCase)
uncShareRoot = '\\server.invalid\share\';
staging = fullfile(tempdir, 'rectangular_fpc_path_validation_stage');

verifyError(testCase, @() rectangular_fpc_publish_paths( ...
    'validate', staging, uncShareRoot), ...
    'RectangularFPC:InvalidPublishRequest');
end

function testRejectsEmptyOutputBasename(testCase)
staging = fullfile(tempdir, 'rectangular_fpc_path_validation_stage');

verifyError(testCase, @() rectangular_fpc_publish_paths( ...
    'validate', staging, ''), ...
    'RectangularFPC:InvalidPublishRequest');
end

function testRootAncestorComparisonDoesNotCreateDoubleSeparator(testCase)
driveRoot = char(java.io.File(pwd).toPath().getRoot());
child = fullfile(driveRoot, 'rectangular_fpc_child');

verifyTrue(testCase, rectangular_fpc_publish_paths( ...
    'is_ancestor', driveRoot, child));
verifyFalse(testCase, rectangular_fpc_publish_paths( ...
    'is_ancestor', child, driveRoot));
end

function testAcceptsSiblingCanonicalFolders(testCase)
parent = fullfile(tempdir, 'rectangular_fpc_path_validation_parent');
staging = fullfile(parent, 'staging');
output = fullfile(parent, 'design_20000101_0000');

[normalizedStaging, normalizedOutput] = ...
    rectangular_fpc_publish_paths('validate', staging, output);

verifyEqual(testCase, normalizedStaging, ...
    char(java.io.File(staging).getCanonicalPath()));
verifyEqual(testCase, normalizedOutput, ...
    char(java.io.File(output).getCanonicalPath()));
end

function testAccessTargetNormalizesSafePathAndRejectsRoots(testCase)
safePath = fullfile(tempname, 'published_output');
expected = char(java.io.File(safePath).getCanonicalPath());
actual = rectangular_fpc_publish_paths( ...
    'validate_access_target', safePath);
verifyEqual(testCase, actual, expected);

unsafeRoots = {'C:\', '\\offline-server\offline-share\', '/'};
for rootIndex = 1:numel(unsafeRoots)
    verifyError(testCase, @() rectangular_fpc_publish_paths( ...
        'validate_access_target', unsafeRoots{rootIndex}), ...
        'RectangularFPC:InvalidPublishRequest');
end
end
