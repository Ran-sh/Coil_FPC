function tests = test_rectangular_fpc_committed_reader
% Committed-reader and artifact-contract tests.
tests = functiontests(localfunctions);
end

function testCommittedReaderHoldsExclusiveAccessLock(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);

reader = @(folder) support.verifyPublishBlockedDuringRead(testCase, folder, paths);
marker = rectangular_fpc_read_committed(paths.output, reader);

verifyEqual(testCase, marker, 'old_marker');
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderRejectsUncommittedFolder(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
delete(fullfile(paths.output, 'generation_status.txt'));

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for uncommitted output');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderRejectsTamperedManifest(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);
fid = fopen(fullfile(paths.output, 'old_marker.txt'), 'a');
tamperCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'TAMPERED');
clear tamperCleanup;

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for tampered output');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderAcceptsCommittedTree(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);

marker = rectangular_fpc_read_committed(paths.output, @(folder) ...
    fileread(fullfile(folder, 'old_marker.txt')));

verifyEqual(testCase, marker, 'marker');
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderRejectsSelfConsistentManifestMissingRequiredArtifacts(testCase)
support = test_rectangular_fpc_publish_support();
% Removing a required handoff artifact and rebuilding a perfectly
% self-consistent manifest must still be rejected. This isolates the
% semantic commit contract from ordinary missing-file/hash failures.
requiredArtifacts = { ...
    'dxf/00_board_outline.dxf', ...
    'dxf/00_drill_map.dxf', ...
    'dxf/L1/01_copper_physical_L1.dxf', ...
    'reports/05_validation_report.txt'};

for artifactIndex = 1:numel(requiredArtifacts)
    paths = support.makeFixture();
    cleanup = onCleanup(@() support.removeFixture(paths.root));
    support.writeCommitEvidence(paths.output);
    artifact = fullfile(paths.output, strrep( ...
        requiredArtifacts{artifactIndex}, '/', filesep));
    delete(artifact);
    support.rewriteCommitManifest(paths.output, cell(0, 2));

    reader = @(folder) error('Test:ReaderMustNotRun', ...
        'reader callback must not run when %s is absent from a self-consistent manifest', ...
        requiredArtifacts{artifactIndex});
    verifyError(testCase, @() rectangular_fpc_read_committed( ...
        paths.output, reader), 'RectangularFPC:OutputNotCommitted', ...
        sprintf('required artifact was not enforced: %s', ...
        requiredArtifacts{artifactIndex}));
    verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
    clear cleanup;
end
end

function testReaderRejectsIncorrectManifestRole(testCase)
support = test_rectangular_fpc_publish_support();
% Path, size and digest remain valid; only the semantic role is wrong.
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);
support.rewriteCommitManifest(paths.output, { ...
    'dxf/00_board_outline.dxf', 'artifact'});

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for an incorrect manifest role');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderCallbackFailureReleasesLock(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);
originalFolder = pwd;
folderCleanup = onCleanup(@() cd(originalFolder));

reader = @(folder) support.changeDirectoryAndFail(folder, paths.root);
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'Test:InjectedReaderFailure');

verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear folderCleanup;
clear cleanup;
end

function testReaderAcceptsStringScalarOutputPath(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);

marker = rectangular_fpc_read_committed(string(paths.output), @(folder) ...
    fileread(fullfile(char(folder), 'old_marker.txt')));

verifyEqual(testCase, marker, 'marker');
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderAcceptsRelativeAndTrailingSeparatorPaths(testCase)
support = test_rectangular_fpc_publish_support();
originalFolder = pwd;
paths = support.makeFixture();
cleanup = onCleanup(@() support.restoreFolderAndRemove(originalFolder, paths.root));
[~, outputName] = fileparts(paths.output);
cd(paths.root);

relativeMarker = rectangular_fpc_read_committed(outputName, @(folder) ...
    fileread(fullfile(folder, 'old_marker.txt')));
trailingMarker = rectangular_fpc_read_committed( ...
    [paths.output filesep], @(folder) ...
    fileread(fullfile(folder, 'old_marker.txt')));

verifyEqual(testCase, relativeMarker, 'marker');
verifyEqual(testCase, trailingMarker, 'marker');
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
cd(originalFolder);
clear cleanup;
end

function testReaderRejectsUnsupportedLayerCountBeforeExpansion(testCase)
support = test_rectangular_fpc_publish_support();
unsupported = [0, 1, 3, 9, 1000000000];
for layerCount = unsupported
    paths = support.makeFixture();
    cleanup = onCleanup(@() support.removeFixture(paths.root));
    statusFile = fullfile(paths.output, 'generation_status.txt');
    statusText = fileread(statusFile);
    statusText = regexprep(statusText, ...
        '(?m)^LayerCount:\s*2\s*$', sprintf('LayerCount: %d', layerCount));
    support.writeText(statusFile, statusText);
    support.rewriteCommitManifest(paths.output, cell(0, 2));

    reader = @(folder) error('Test:ReaderMustNotRun', ...
        'reader callback must not run for LayerCount %d', layerCount);
    verifyError(testCase, @() rectangular_fpc_read_committed( ...
        paths.output, reader), 'RectangularFPC:OutputNotCommitted');
    verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
    clear cleanup;
end
end

function testReaderRejectsHeaderOnlyManifest(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);
fid = fopen(fullfile(paths.output, 'reports', '08_file_manifest.csv'), 'w');
manifestCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
clear manifestCleanup;

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for header-only manifest');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
clear cleanup;
end

function testReaderRejectsTruncatedManifest(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);
% 只保留 old_marker 行、丢掉 generation_status 行：磁盘文件仍在，
% 清单集合与实际文件集合不全等，必须拒绝。
oldMarker = fullfile(paths.output, 'old_marker.txt');
oldInfo = dir(oldMarker);
fid = fopen(fullfile(paths.output, 'reports', '08_file_manifest.csv'), 'w');
manifestCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
fprintf(fid, 'old_marker.txt,test,%d,%s\n', oldInfo.bytes, support.sha256File(oldMarker));
clear manifestCleanup;

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for truncated manifest');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
clear cleanup;
end

function testReaderRejectsDuplicateManifestRows(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);
statusFile = fullfile(paths.output, 'generation_status.txt');
statusInfo = dir(statusFile);
fid = fopen(fullfile(paths.output, 'reports', '08_file_manifest.csv'), 'w');
manifestCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
fprintf(fid, 'generation_status.txt,status,%d,%s\n', ...
    statusInfo.bytes, support.sha256File(statusFile));
fprintf(fid, 'generation_status.txt,status,%d,%s\n', ...
    statusInfo.bytes, support.sha256File(statusFile));
clear manifestCleanup;

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for duplicated manifest rows');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
clear cleanup;
end
