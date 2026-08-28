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

function writeMarker(filename)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'marker');
clear cleanup;
end

function removeFixture(root)
if isfolder(root)
    rmdir(root, 's');
end
end
