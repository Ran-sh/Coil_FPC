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

function testExpiredMalformedLockCanBeRecovered(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
fileCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear fileCleanup;

rectangular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(lockFolder));
clear cleanup;
end

function testCommittedOutputCleansOrphanBackup(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
writeCommitEvidence(paths.output);
orphanBackup = [paths.output '_backup_committed_crash'];
mkdir(orphanBackup);
writeMarker(fullfile(orphanBackup, 'orphan_marker.txt'));

rectangular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(orphanBackup));
verifyEmpty(testCase, dir(paths.backupPattern));
clear cleanup;
end

function testIncompleteOutputPreservesRecoveryBackup(testCase)
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
orphanBackup = [paths.output '_backup_rollback_failed'];
mkdir(orphanBackup);
writeMarker(fullfile(orphanBackup, 'last_good_marker.txt'));

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
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\n', pid);
fprintf(fid, 'host=%s\n', host);
fprintf(fid, 'token=foreign_host_test\n');
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear cleanup;
end

function marker = verifyPublishBlockedDuringRead(testCase, folder, paths)
verifyTrue(testCase, isfolder([paths.output '_publish.lock']));
verifyError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:ConcurrentPublish');
verifyTrue(testCase, isfolder(folder));
marker = erase(fileread(fullfile(folder, 'old_marker.txt')), 'marker');
marker = ['old_' marker 'marker'];
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
fprintf(fid, 'Status: SUCCESS\n');
clear cleanup;
reportsFolder = fullfile(outputFolder, 'reports');
mkdir(reportsFolder);
manifestFile = fullfile(reportsFolder, '08_file_manifest.csv');
oldMarker = fullfile(outputFolder, 'old_marker.txt');
oldInfo = dir(oldMarker);
statusInfo = dir(statusFile);
fid = fopen(manifestFile, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
fprintf(fid, 'old_marker.txt,test,%d,%s\n', ...
    oldInfo.bytes, sha256File(oldMarker));
fprintf(fid, 'generation_status.txt,status,%d,%s\n', ...
    statusInfo.bytes, sha256File(statusFile));
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
