function tests = test_rectangular_fpc_atomic_publish
% Atomic transaction and ownership-fencing tests.
tests = functiontests(localfunctions);
end

function testPublishFailureRestoresPriorVersion(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
mover = @(source, destination) support.controlledMove( ...
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
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
mover = @(source, destination) support.controlledMove( ...
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
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
observationFile = fullfile(paths.root, 'move_observations.txt');
mover = @(source, destination) support.observingMove( ...
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
support = test_rectangular_fpc_publish_support();
for mode = {'throw', 'false'}
    paths = support.makeFixture();
    cleanup = onCleanup(@() support.removeFixture(paths.root));
    mover = @(source, destination) support.ambiguousPhaseMove( ...
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
support = test_rectangular_fpc_publish_support();
for mode = {'throw', 'false'}
    paths = support.makeFixture();
    cleanup = onCleanup(@() support.removeFixture(paths.root));
    mover = @(source, destination) support.ambiguousPhaseMove( ...
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
support = test_rectangular_fpc_publish_support();
for mode = {'throw', 'false'}
    paths = support.makeFixture();
    cleanup = onCleanup(@() support.removeFixture(paths.root));
    mover = @(source, destination) support.ambiguousRollbackMove( ...
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
support = test_rectangular_fpc_publish_support();
for mode = {'throw', 'false'}
    paths = support.makeFixture();
    cleanup = onCleanup(@() support.removeFixture(paths.root));
    lockFolder = [paths.output '_publish.lock'];
    mkdir(lockFolder);
    support.writeStaleOwnerRecord(lockFolder, '1');
    mover = @(source, destination) support.ambiguousOwnerSwapMove( ...
        source, destination, lockFolder, mode{1});

    rectangular_fpc_publish_atomically(paths.staging, paths.output, mover);

    verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
    verifyFalse(testCase, isfolder(lockFolder));
    clear cleanup;
end
end

function testPostPublishContractFailureRestoresPriorVersion(testCase)
support = test_rectangular_fpc_publish_support();
% The staged tree is valid before its move. Corrupt it only after it has
% occupied the formal path, proving the mandatory post-move contract gate
% runs before the recoverable prior version is deleted.
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
mover = @(source, destination) support.corruptAfterPublicationMove( ...
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

function testUncommittedExistingTargetIsPreserved(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
delete(fullfile(paths.output, 'reports', '08_file_manifest.csv'));
sentinel = fullfile(paths.output, 'user_owned_sentinel.txt');
support.writeMarker(sentinel);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), ...
    'RectangularFPC:AtomicRecoveryFailed');

verifyTrue(testCase, isfile(sentinel));
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyEmpty(testCase, dir(paths.backupPattern));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testPublisherRejectsEqualStagingAndOutputWithoutCleanup(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.output, paths.output), 'RectangularFPC:InvalidPublishRequest');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, rectangular_fpc_publish_atomically( ...
    'verify_committed', paths.output));
clear cleanup;
end

function testPublisherRejectsStagingAncestorWithoutCleanup(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.root, paths.output), 'RectangularFPC:InvalidPublishRequest');

verifyTrue(testCase, isfolder(paths.root));
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
clear cleanup;
end

function testPublisherRejectsStagingDescendantWithoutCleanup(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
descendant = fullfile(paths.output, 'nested_staging');
mkdir(descendant);
support.writeMarker(fullfile(descendant, 'do_not_delete.txt'));

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    descendant, paths.output), 'RectangularFPC:InvalidPublishRequest');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, isfile(fullfile(descendant, 'do_not_delete.txt')));
clear cleanup;
end

function testPublisherCanonicalizesRelativePaths(testCase)
support = test_rectangular_fpc_publish_support();
originalFolder = pwd;
paths = support.makeFixture();
cleanup = onCleanup(@() support.restoreFolderAndRemove(originalFolder, paths.root));
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
support = test_rectangular_fpc_publish_support();
% A writer that loses its owner token at the output-to-backup boundary must
% not publish over the replacement owner. The prior output is the recovery
% source and therefore must remain available after the fenced failure.
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
mover = @(source, destination) support.replaceOwnerAtDestructiveMove( ...
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
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
support.writeLockOwner(lockFolder, 'definitely-not-this-host', 2147483647);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, isfolder(lockFolder));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end
