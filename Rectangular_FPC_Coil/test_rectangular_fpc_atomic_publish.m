function tests = test_rectangular_fpc_atomic_publish
% Deterministic failure-path tests for the private atomic publisher.
tests = functiontests(localfunctions);
end

function testPublishFailureRestoresPriorVersion(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
mover = @(source, destination) controlledMove( ...
    source, destination, paths, true, false);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), ...
    'RectangularFPC:AtomicPublishFailed');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
backups = dir(paths.backupPattern);
verifyEmpty(testCase, backups([backups.isdir]));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testRestoreFailureRaisesAtomicRollbackFailedAndKeepsBackup(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
mover = @(source, destination) controlledMove( ...
    source, destination, paths, true, true);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), ...
    'RectangularFPC:AtomicRollbackFailed');

verifyFalse(testCase, isfolder(paths.output));
backups = dir(paths.backupPattern);
backups = backups([backups.isdir]);
verifyNumElements(testCase, backups, 1);
verifyTrue(testCase, isfile(fullfile( ...
    backups(1).folder, backups(1).name, 'old_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testPublicationGapIsCoveredByOwnershipLock(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
observationFile = fullfile(paths.root, 'move_observations.txt');
mover = @(source, destination) observingMove( ...
    source, destination, paths, observationFile);

rectangular_fpc_publish_atomically(paths.staging, paths.output, mover);

observations = fileread(observationFile);
verifyTrue(testCase, contains(observations, 'PRIOR_MOVE_LOCKED'));
verifyTrue(testCase, contains(observations, 'PUBLICATION_GAP_LOCKED'));
verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testPriorMoveThenFailureRestoresUsingObservedState(testCase)
for mode = {'throw', 'false'}
    paths = makeFixture();
    cleanup = onCleanup(@() removeFixture(paths.root));
    mover = @(source, destination) ambiguousPhaseMove( ...
        source, destination, paths, 'prior', mode{1});

    assertError(testCase, @() rectangular_fpc_publish_atomically( ...
        paths.staging, paths.output, mover), ...
        'RectangularFPC:AtomicPublishFailed');
    verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
    verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
    verifyEmpty(testCase, dir([paths.output '_backup_*.transaction']));
    clear cleanup;
end
end

function testPublishMoveThenFailureRestoresUsingObservedState(testCase)
for mode = {'throw', 'false'}
    paths = makeFixture();
    cleanup = onCleanup(@() removeFixture(paths.root));
    mover = @(source, destination) ambiguousPhaseMove( ...
        source, destination, paths, 'publish', mode{1});

    assertError(testCase, @() rectangular_fpc_publish_atomically( ...
        paths.staging, paths.output, mover), ...
        'RectangularFPC:AtomicPublishFailed');
    verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
    verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
    verifyEmpty(testCase, dir([paths.output '_backup_*.transaction']));
    clear cleanup;
end
end

function testRestoreMoveThenFailureIsRecognizedAsRestored(testCase)
for mode = {'throw', 'false'}
    paths = makeFixture();
    cleanup = onCleanup(@() removeFixture(paths.root));
    mover = @(source, destination) ambiguousRollbackMove( ...
        source, destination, paths, mode{1});

    assertError(testCase, @() rectangular_fpc_publish_atomically( ...
        paths.staging, paths.output, mover), ...
        'RectangularFPC:AtomicPublishFailed');
    verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
    verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
    verifyEmpty(testCase, dir([paths.output '_backup_*.transaction']));
    clear cleanup;
end
end

function testOwnerSwapMoveThenFailureUsesInstalledToken(testCase)
for mode = {'throw', 'false'}
    paths = makeFixture();
    cleanup = onCleanup(@() removeFixture(paths.root));
    lockFolder = [paths.output '_publish.lock'];
    mkdir(lockFolder);
    writeStaleOwnerRecord(lockFolder, '1');
    mover = @(source, destination) ambiguousOwnerSwapMove( ...
        source, destination, lockFolder, mode{1});

    rectangular_fpc_publish_atomically(paths.staging, paths.output, mover);

    verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
    verifyFalse(testCase, isfolder(lockFolder));
    clear cleanup;
end
end

function testPostPublishContractFailureRestoresPriorVersion(testCase)
% The staged tree is valid before its move. Corrupt it only after it has
% occupied the formal path, proving the mandatory post-move contract gate
% runs before the recoverable prior version is deleted.
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
mover = @(source, destination) corruptAfterPublicationMove( ...
    source, destination, paths);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), ...
    'RectangularFPC:AtomicPublishFailed');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyTrue(testCase, rectangular_fpc_publish_atomically( ...
    'verify_committed', paths.output));
backups = dir(paths.backupPattern);
verifyEmpty(testCase, backups([backups.isdir]));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testPublisherRejectsEqualStagingAndOutputWithoutCleanup(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.output, paths.output), 'RectangularFPC:InvalidPublishRequest');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, rectangular_fpc_publish_atomically( ...
    'verify_committed', paths.output));
clear cleanup;
end

function testPublisherRejectsStagingAncestorWithoutCleanup(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.root, paths.output), 'RectangularFPC:InvalidPublishRequest');

verifyTrue(testCase, isfolder(paths.root));
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
clear cleanup;
end

function testPublisherRejectsStagingDescendantWithoutCleanup(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
descendant = fullfile(paths.output, 'nested_staging');
mkdir(descendant);
writeMarker(fullfile(descendant, 'do_not_delete.txt'));

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    descendant, paths.output), 'RectangularFPC:InvalidPublishRequest');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, isfile(fullfile(descendant, 'do_not_delete.txt')));
clear cleanup;
end

function testPublisherCanonicalizesRelativePaths(testCase)
originalFolder = pwd;
paths = makeFixture();
cleanup = onCleanup(@() restoreFolderAndRemove(originalFolder, paths.root));
[~, outputName] = fileparts(paths.output);
[~, stagingName] = fileparts(paths.staging);
cd(paths.root);

rectangular_fpc_publish_atomically(stagingName, outputName);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
cd(originalFolder);
clear cleanup;
end

function testOwnerReplacementAtDestructiveMoveFailsClosed(testCase)
% A writer that loses its owner token at the output-to-backup boundary must
% not publish over the replacement owner. The prior output is the recovery
% source and therefore must remain available after the fenced failure.
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
mover = @(source, destination) replaceOwnerAtDestructiveMove( ...
    source, destination, paths);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), ...
    'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyTrue(testCase, isfolder([paths.output '_publish.lock']));
verifyTrue(testCase, contains(fileread(fullfile( ...
    [paths.output '_publish.lock'], 'owner.txt')), ...
    ['token=' repmat('e', 1, 32)]));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function testForeignHostLockFailsClosed(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
writeLockOwner(lockFolder, 'definitely-not-this-host', 2147483647);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, isfolder(lockFolder));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function testCommittedReaderHoldsExclusiveAccessLock(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);

reader = @(folder) verifyPublishBlockedDuringRead(testCase, folder, paths);
marker = rectangular_fpc_read_committed(paths.output, reader);

verifyEqual(testCase, marker, 'old_marker');
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderRejectsUncommittedFolder(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
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
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
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
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);

marker = rectangular_fpc_read_committed(paths.output, @(folder) ...
    fileread(fullfile(folder, 'old_marker.txt')));

verifyEqual(testCase, marker, 'marker');
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderRejectsSelfConsistentManifestMissingRequiredArtifacts(testCase)
% Removing a required handoff artifact and rebuilding a perfectly
% self-consistent manifest must still be rejected. This isolates the
% semantic commit contract from ordinary missing-file/hash failures.
requiredArtifacts = { ...
    'dxf/00_board_outline.dxf', ...
    'dxf/00_drill_map.dxf', ...
    'dxf/L1/01_copper_physical_L1.dxf', ...
    'reports/05_validation_report.txt'};

for artifactIndex = 1:numel(requiredArtifacts)
    paths = makeFixture();
    cleanup = onCleanup(@() removeFixture(paths.root));
    writeCommitEvidence(paths.output);
    artifact = fullfile(paths.output, strrep( ...
        requiredArtifacts{artifactIndex}, '/', filesep));
    delete(artifact);
    rewriteCommitManifest(paths.output, cell(0, 2));

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
% Path, size and digest remain valid; only the semantic role is wrong.
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
rewriteCommitManifest(paths.output, { ...
    'dxf/00_board_outline.dxf', 'artifact'});

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for an incorrect manifest role');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderCallbackFailureReleasesLock(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
originalFolder = pwd;
folderCleanup = onCleanup(@() cd(originalFolder));

reader = @(folder) changeDirectoryAndFail(folder, paths.root);
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'Test:InjectedReaderFailure');

verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear folderCleanup;
clear cleanup;
end

function testReaderAcceptsStringScalarOutputPath(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);

marker = rectangular_fpc_read_committed(string(paths.output), @(folder) ...
    fileread(fullfile(char(folder), 'old_marker.txt')));

verifyEqual(testCase, marker, 'marker');
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testReaderAcceptsRelativeAndTrailingSeparatorPaths(testCase)
originalFolder = pwd;
paths = makeFixture();
cleanup = onCleanup(@() restoreFolderAndRemove(originalFolder, paths.root));
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
unsupported = [0, 1, 3, 9, 1000000000];
for layerCount = unsupported
    paths = makeFixture();
    cleanup = onCleanup(@() removeFixture(paths.root));
    statusFile = fullfile(paths.output, 'generation_status.txt');
    statusText = fileread(statusFile);
    statusText = regexprep(statusText, ...
        '(?m)^LayerCount:\s*2\s*$', sprintf('LayerCount: %d', layerCount));
    writeText(statusFile, statusText);
    rewriteCommitManifest(paths.output, cell(0, 2));

    reader = @(folder) error('Test:ReaderMustNotRun', ...
        'reader callback must not run for LayerCount %d', layerCount);
    verifyError(testCase, @() rectangular_fpc_read_committed( ...
        paths.output, reader), 'RectangularFPC:OutputNotCommitted');
    verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
    clear cleanup;
end
end

function testReaderRejectsHeaderOnlyManifest(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
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
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
% 只保留 old_marker 行、丢掉 generation_status 行：磁盘文件仍在，
% 清单集合与实际文件集合不全等，必须拒绝。
oldMarker = fullfile(paths.output, 'old_marker.txt');
oldInfo = dir(oldMarker);
fid = fopen(fullfile(paths.output, 'reports', '08_file_manifest.csv'), 'w');
manifestCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
fprintf(fid, 'old_marker.txt,test,%d,%s\n', oldInfo.bytes, sha256File(oldMarker));
clear manifestCleanup;

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for truncated manifest');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
clear cleanup;
end

function testReaderRejectsDuplicateManifestRows(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
statusFile = fullfile(paths.output, 'generation_status.txt');
statusInfo = dir(statusFile);
fid = fopen(fullfile(paths.output, 'reports', '08_file_manifest.csv'), 'w');
manifestCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
fprintf(fid, 'generation_status.txt,status,%d,%s\n', ...
    statusInfo.bytes, sha256File(statusFile));
fprintf(fid, 'generation_status.txt,status,%d,%s\n', ...
    statusInfo.bytes, sha256File(statusFile));
clear manifestCleanup;

reader = @(folder) error('Test:ReaderMustNotRun', ...
    'reader callback must not run for duplicated manifest rows');
assertError(testCase, @() rectangular_fpc_read_committed( ...
    paths.output, reader), 'RectangularFPC:OutputNotCommitted');
clear cleanup;
end

function testStaleClaimOwnerReplacedDuringTransition(testCase)
% 原地认领协议回归：stale 判定后、原子换主前，若 owner 已被其他写入者
% 换成新锁，认领方必须识别身份变化、fail closed，且不得破坏新锁。
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
writeStaleOwnerRecord(lockFolder, '1');
mover = @(source, destination) replaceOwnerDuringSwap( ...
    source, destination, lockFolder);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfolder(lockFolder));
verifyTrue(testCase, contains(fileread(fullfile(lockFolder, 'owner.txt')), ...
    ['token=' repmat('f', 1, 32)]));
verifyFalse(testCase, isfolder(fullfile(lockFolder, 'reclaim.claim')));
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
clear cleanup;
end

function testStaleClaimRecoversOrphanedReclaimClaim(testCase)
% 崩溃残留的孤儿认领（claimant 已死）必须可回收，发布正常完成。
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
writeStaleOwnerRecord(lockFolder, '1');
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
claimOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=2147483647\nhost=%s\ntoken=%s\n', ...
    localHostName(0), repmat('2', 1, 32));
verifyNotEmpty(testCase, localHostName(0), ...
    'stale-claim fixture must always write a non-empty host identity');
fprintf(fid, 'created=%s\n', char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
clear claimOwnerCleanup;

rectangular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(lockFolder));
clear cleanup;
end

function testStaleClaimRefusesBusyReclaimClaim(testCase)
% 另一写入者正在认领（claimant 存活）时必须 fail closed，主锁不被破坏。
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
writeStaleOwnerRecord(lockFolder, '1');
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
claimOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\nhost=%s\ntoken=%s\n', ...
    matlabProcessID, localHostName(0), repmat('3', 1, 32));
fprintf(fid, 'created=%s\n', char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
clear claimOwnerCleanup;

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyTrue(testCase, contains(fileread(fullfile(lockFolder, 'owner.txt')), ...
    'created=2000-01-01T00:00:00.000Z'));
clear cleanup;
end

function testExpiredMalformedFixedLockFailsClosed(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
fileCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear fileCleanup;

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, isfolder(lockFolder));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function testCommittedOutputCleansLegitimateOrphanBackup(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
orphanBackup = legitimateBackupPath(paths, 'a');
mkdir(orphanBackup);
writeMarker(fullfile(orphanBackup, 'orphan_marker.txt'));
writeCommitEvidence(orphanBackup);
rewriteCommitManifest(orphanBackup, cell(0, 2));
writeBackupTransactionFixture( ...
    orphanBackup, paths.output, repmat('a', 1, 32));

rectangular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(orphanBackup));
verifyEmpty(testCase, dir(paths.backupPattern));
clear cleanup;
end

function testUnknownBackupLikeDirectorySurvivesCommittedReplacement(testCase)
% Only publisher-issued, token-shaped backup names are recovery state.
% A user directory that merely shares the prefix is outside that protocol.
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
unknownBackup = unknownBackupLikePath(paths);
mkdir(unknownBackup);
writeMarker(fullfile(unknownBackup, 'do_not_touch.txt'));

rectangular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyTrue(testCase, isfile(fullfile(unknownBackup, 'do_not_touch.txt')));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testUnknownBackupLikeDirectoryWithoutOutputFailsClosed(testCase)
% With no formal output and no legitimate publication backup, recovery has
% no authoritative source. The unknown directory must not be moved/deleted.
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
rmdir(paths.output, 's');
unknownBackup = unknownBackupLikePath(paths);
mkdir(unknownBackup);
writeMarker(fullfile(unknownBackup, 'do_not_touch.txt'));

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:AtomicRecoveryFailed');

verifyFalse(testCase, isfolder(paths.output));
verifyTrue(testCase, isfile(fullfile(unknownBackup, 'do_not_touch.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testIncompleteOutputPreservesRecoveryBackup(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
delete(fullfile(paths.output, 'generation_status.txt'));
orphanBackup = legitimateBackupPath(paths, 'b');
mkdir(orphanBackup);
writeMarker(fullfile(orphanBackup, 'last_good_marker.txt'));
writeCommitEvidence(orphanBackup);
rewriteCommitManifest(orphanBackup, cell(0, 2));
writeBackupTransactionFixture( ...
    orphanBackup, paths.output, repmat('b', 1, 32));

verifyError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:AtomicRecoveryFailed');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, isfile(fullfile( ...
    orphanBackup, 'last_good_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function paths = makeFixture()
paths.root = tempname;
paths.output = fullfile(paths.root, 'design_20000101_0000');
paths.staging = fullfile(paths.root, 'staging');
paths.backupPattern = [paths.output '_backup_*'];
mkdir(paths.output);
mkdir(paths.staging);
writeMarker(fullfile(paths.output, 'old_marker.txt'));
writeMarker(fullfile(paths.staging, 'new_marker.txt'));
writeCommitEvidence(paths.output);
writeCommitEvidence(paths.staging);
end

function [moved, message] = controlledMove( ...
    source, destination, paths, failPublish, failRestore)
isPublish = strcmp(source, paths.staging) && strcmp(destination, paths.output);
isRestore = startsWith(source, [paths.output '_backup_']) && ...
    strcmp(destination, paths.output);
if (failPublish && isPublish) || (failRestore && isRestore)
    moved = false;
    message = 'injected move failure';
else
    [moved, message] = movefile(source, destination);
end
end

function [moved, message] = ambiguousPhaseMove( ...
    source, destination, paths, phase, mode)
isPrior = strcmp(source, paths.output) && ...
    startsWith(destination, [paths.output '_backup_']);
isPublish = strcmp(source, paths.staging) && strcmp(destination, paths.output);
[moved, message] = movefile(source, destination);
if (strcmp(phase, 'prior') && isPrior) || ...
        (strcmp(phase, 'publish') && isPublish)
    [moved, message] = reportMoveFailureAfterSuccess(mode);
end
end

function [moved, message] = ambiguousRollbackMove( ...
    source, destination, paths, mode)
isPublish = strcmp(source, paths.staging) && strcmp(destination, paths.output);
isRestore = startsWith(source, [paths.output '_backup_']) && ...
    strcmp(destination, paths.output);
if isPublish
    moved = false;
    message = 'injected publish failure';
    return;
end
[moved, message] = movefile(source, destination);
if isRestore
    [moved, message] = reportMoveFailureAfterSuccess(mode);
end
end

function [moved, message] = ambiguousOwnerSwapMove( ...
    source, destination, lockFolder, mode)
[moved, message] = movefile(source, destination);
ownerFile = fullfile(lockFolder, 'owner.txt');
if strcmp(destination, ownerFile) && contains(source, 'owner.txt.candidate_')
    [moved, message] = reportMoveFailureAfterSuccess(mode);
end
end

function [moved, message] = reportMoveFailureAfterSuccess(mode)
if strcmp(mode, 'throw')
    error('Test:MoveFailedAfterSuccess', ...
        'injected failure after the filesystem move completed');
end
moved = false;
message = 'mover returned false after the filesystem move completed';
end

function [moved, message] = corruptAfterPublicationMove( ...
    source, destination, paths)
[moved, message] = movefile(source, destination);
if moved && strcmp(source, paths.staging) && strcmp(destination, paths.output)
    delete(fullfile(destination, 'dxf', '00_board_outline.dxf'));
end
end

function [moved, message] = replaceOwnerAtDestructiveMove( ...
    source, destination, paths)
isPriorVersionMove = strcmp(source, paths.output) && ...
    startsWith(destination, [paths.output '_backup_']);
if isPriorVersionMove
    lockFolder = [paths.output '_publish.lock'];
    writeOwnerRecord(lockFolder, localHostName(0), matlabProcessID, ...
        repmat('e', 1, 32));
    moved = false;
    message = 'ownership replaced before destructive move';
    return;
end
[moved, message] = movefile(source, destination);
end

function testStaleClaimOrphanStealLoserFailsClosed(testCase)
% 孤儿回收原子性回归：两个回收者竞争同一孤儿认领时，基于过期判定
% rmdir 固定路径会删掉竞争者刚建好的新认领（TOCTOU，双持锁）。
% 原子 tombstone 竞争下，rename 落败的一方必须 fail closed，
% 且不得破坏赢家的活跃认领。
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
writeStaleOwnerRecord(lockFolder, '1');
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
orphanOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=2147483647\nhost=%s\ntoken=%s\n', ...
    localHostName(0), repmat('2', 1, 32));
verifyNotEmpty(testCase, localHostName(0), ...
    'stale-claim fixture must always write a non-empty host identity');
fprintf(fid, 'created=%s\n', char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
clear orphanOwnerCleanup;
mover = @(source, destination) stealTombstoneRace(source, destination, claimDir);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfolder(claimDir));
verifyTrue(testCase, contains(fileread(fullfile(claimDir, 'owner.txt')), ...
    ['token=' repmat('c', 1, 32)]));
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
clear cleanup;
end

function [moved, message] = stealTombstoneRace(source, destination, claimDir)
isTombstone = startsWith(source, claimDir) && ...
    startsWith(destination, [claimDir '.tomb_']);
if isTombstone
    % 模拟竞争者已抢先完成回收并建立自己的活跃认领
    rmdir(source, 's');
    mkdir(claimDir);
    fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
    busyCleanup = onCleanup(@() fclose(fid));
    fprintf(fid, 'pid=%d\nhost=sim-host-b\ntoken=%s\n', ...
        matlabProcessID, repmat('c', 1, 32));
    fprintf(fid, 'created=%s\n', char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
    clear busyCleanup;
    moved = false;
    message = 'tombstone claim lost the atomic steal race';
else
    [moved, message] = movefile(source, destination);
end
end

function [moved, message] = replaceOwnerDuringSwap(source, destination, lockFolder)
% 模拟竞争转换：在原子换主一步，另一位写入者已把 owner 换成自己的新锁。
ownerFile = fullfile(lockFolder, 'owner.txt');
if strcmp(destination, ownerFile) && contains(source, 'owner.txt.candidate_')
    fid = fopen(ownerFile, 'w');
    freshCleanup = onCleanup(@() fclose(fid));
    fprintf(fid, 'pid=1\nhost=sim-host-a\ntoken=%s\n', repmat('f', 1, 32));
    fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
    clear freshCleanup;
    delete(source);
    moved = true;
    message = '';
else
    [moved, message] = movefile(source, destination);
end
end

function host = localHostName(~)
% 带 1 个输入参数（避免被 functiontests 当作测试函数注册）。
host = lower(strtrim(getenv('COMPUTERNAME')));
if isempty(host)
    host = lower(strtrim(getenv('HOSTNAME')));
end
if isempty(host)
    try
        host = lower(strtrim(char(java.net.InetAddress.getLocalHost().getHostName())));
    catch
        host = '';
    end
end
if isempty(host)
    error('RectangularFPC:TestHostUnavailable', ...
        'Unable to determine a non-empty host identity for the test fixture.');
end
end

function [moved, message] = observingMove( ...
    source, destination, paths, observationFile)
lockFolder = [paths.output '_publish.lock'];
if strcmp(source, paths.output) && startsWith(destination, ...
        [paths.output '_backup_']) && isfolder(lockFolder)
    appendObservation(observationFile, 'PRIOR_MOVE_LOCKED');
elseif strcmp(source, paths.staging) && strcmp(destination, paths.output) && ...
        ~isfolder(paths.output) && isfolder(lockFolder)
    appendObservation(observationFile, 'PUBLICATION_GAP_LOCKED');
end
[moved, message] = movefile(source, destination);
end

function appendObservation(filename, observation)
fid = fopen(filename, 'a');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', observation);
clear cleanup;
end

function writeLockOwner(lockFolder, host, pid)
writeOwnerRecord(lockFolder, host, pid, repmat('d', 1, 32));
end

function writeOwnerRecord(lockFolder, host, pid, token)
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\n', pid);
fprintf(fid, 'host=%s\n', host);
fprintf(fid, 'token=%s\n', token);
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear cleanup;
end

function writeStaleOwnerRecord(lockFolder, hexDigit)
writeOwnerRecord(lockFolder, localHostName(0), 2147483647, ...
    repmat(hexDigit, 1, 32));
end

function marker = verifyPublishBlockedDuringRead(testCase, folder, paths)
verifyTrue(testCase, isfolder([paths.output '_publish.lock']));
[~, outputName] = fileparts(paths.output);
outputAlias = fullfile(paths.root, '.', outputName);
verifyError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, outputAlias), 'RectangularFPC:ConcurrentPublish');
verifyTrue(testCase, isfolder(folder));
marker = erase(fileread(fullfile(folder, 'old_marker.txt')), 'marker');
marker = ['old_' marker 'marker'];
end

function changeDirectoryAndFail(folder, destination)
cd(destination);
error('Test:InjectedReaderFailure', ...
    'injected reader callback failure for %s', char(folder));
end

function writeMarker(filename)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'marker');
clear cleanup;
end

function writeCommitEvidence(outputFolder)
statusFile = fullfile(outputFolder, 'generation_status.txt');
fid = fopen(statusFile, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'SchemaVersion: 2\n');
fprintf(fid, 'Status: SUCCESS\n');
fprintf(fid, 'LayerCount: 2\n');
fprintf(fid, 'PreviewEnabled: 0\n');
fprintf(fid, 'PublicationId: %s\n', repmat('9', 1, 32));
clear cleanup;

dxfFolder = fullfile(outputFolder, 'dxf');
layerFolder = fullfile(dxfFolder, 'L1');
reportsFolder = fullfile(outputFolder, 'reports');
ensureFixtureFolder(dxfFolder);
ensureFixtureFolder(layerFolder);
ensureFixtureFolder(fullfile(dxfFolder, 'L2'));
ensureFixtureFolder(reportsFolder);
artifactPaths = { ...
    'dxf/00_board_outline.dxf', ...
    'dxf/00_drill_map.dxf', ...
    'dxf/L1/01_copper_L1.dxf', ...
    'dxf/L1/01_copper_physical_L1.dxf', ...
    'dxf/L1/01_antipad_keepout_L1.dxf', ...
    'dxf/L2/02_copper_L2.dxf', ...
    'dxf/L2/02_copper_physical_L2.dxf', ...
    'dxf/L2/02_antipad_keepout_L2.dxf', ...
    'reports/01_pad_via_coordinates.csv', ...
    'reports/02_layer_mapping.csv', ...
    'reports/03_design_summary.txt', ...
    'reports/04_turn_scan.csv', ...
    'reports/05_validation_report.txt', ...
    'reports/06_manufacturing_check.csv', ...
    'reports/07_fabrication_notes.txt'};
for artifactIndex = 1:numel(artifactPaths)
    writeMarker(fullfile(outputFolder, strrep( ...
        artifactPaths{artifactIndex}, '/', filesep)));
end
rewriteCommitManifest(outputFolder, cell(0, 2));
end

function rewriteCommitManifest(outputFolder, roleOverrides)
manifestFile = fullfile(outputFolder, 'reports', '08_file_manifest.csv');
files = dir(fullfile(outputFolder, '**', '*'));
files = files(~[files.isdir]);
relativePaths = strings(0, 1);
absolutePaths = strings(0, 1);
for fileIndex = 1:numel(files)
    absolutePath = fullfile(files(fileIndex).folder, files(fileIndex).name);
    if strcmp(absolutePath, manifestFile)
        continue;
    end
    relativePath = extractAfter(absolutePath, [outputFolder filesep]);
    relativePaths(end+1, 1) = string(strrep(relativePath, filesep, '/')); %#ok<AGROW>
    absolutePaths(end+1, 1) = string(absolutePath); %#ok<AGROW>
end
[relativePaths, order] = sort(relativePaths);
absolutePaths = absolutePaths(order);

fid = fopen(manifestFile, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
for fileIndex = 1:numel(relativePaths)
    relativePath = char(relativePaths(fileIndex));
    absolutePath = char(absolutePaths(fileIndex));
    info = dir(absolutePath);
    role = fixtureArtifactRole(relativePath);
    if ~isempty(roleOverrides)
        overrideIndex = find(strcmp(roleOverrides(:, 1), relativePath), 1);
        if ~isempty(overrideIndex)
            role = roleOverrides{overrideIndex, 2};
        end
    end
    fprintf(fid, '%s,%s,%d,%s\n', relativePath, role, ...
        info.bytes, sha256File(absolutePath));
end
clear cleanup;
end

function writeText(filename, value)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', value);
clear cleanup;
end

function role = fixtureArtifactRole(relativePath)
if strcmp(relativePath, 'dxf/00_board_outline.dxf')
    role = 'board_outline';
elseif strcmp(relativePath, 'dxf/00_drill_map.dxf')
    role = 'drill_reference';
elseif contains(relativePath, '_copper_physical_')
    role = 'physical_copper';
elseif contains(relativePath, '_antipad_keepout_')
    role = 'antipad_keepout';
elseif contains(relativePath, '_copper_L')
    role = 'copper_centerline';
elseif strcmp(relativePath, 'reports/01_pad_via_coordinates.csv')
    role = 'pad_via_coordinates';
elseif strcmp(relativePath, 'reports/02_layer_mapping.csv')
    role = 'layer_mapping';
elseif strcmp(relativePath, 'reports/03_design_summary.txt')
    role = 'design_summary';
elseif strcmp(relativePath, 'reports/04_turn_scan.csv')
    role = 'turn_scan';
elseif strcmp(relativePath, 'reports/05_validation_report.txt')
    role = 'validation_report';
elseif strcmp(relativePath, 'reports/06_manufacturing_check.csv')
    role = 'manufacturing_check';
elseif strcmp(relativePath, 'reports/07_fabrication_notes.txt')
    role = 'fabrication_notes';
elseif strcmp(relativePath, 'generation_status.txt')
    role = 'generation_status';
else
    role = 'artifact';
end
end

function backupFolder = legitimateBackupPath(paths, hexDigit)
% Publisher tokens are 32 lowercase hexadecimal characters (UUID sans '-').
backupFolder = [paths.output '_backup_' repmat(hexDigit, 1, 32)];
end

function ensureFixtureFolder(folder)
if ~isfolder(folder)
    mkdir(folder);
end
end

function backupFolder = unknownBackupLikePath(paths)
backupFolder = [paths.output '_backup_keep'];
end

function writeBackupTransactionFixture( ...
    backupFolder, outputFolder, transactionId)
markerFile = [backupFolder '.transaction'];
target = char(java.io.File(outputFolder).getCanonicalPath());
target = strrep(strtrim(target), '/', filesep);
if ispc
    target = lower(target);
end
fid = fopen(markerFile, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'SchemaVersion: 1\n');
fprintf(fid, 'Target: %s\n', target);
fprintf(fid, 'TransactionId: %s\n', transactionId);
fprintf(fid, 'Payload: prior_committed_output\n');
clear cleanup;
end

function hash = sha256File(filename)
fid = fopen(filename, 'rb');
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
clear cleanup;
digest = java.security.MessageDigest.getInstance('SHA-256');
hashBytes = typecast(digest.digest(bytes), 'uint8');
hash = lower(reshape(dec2hex(hashBytes, 2).', 1, []));
end

function removeFixture(root)
if isfolder(root)
    rmdir(root, 's');
end
end

function restoreFolderAndRemove(folder, root)
cd(folder);
removeFixture(root);
end
