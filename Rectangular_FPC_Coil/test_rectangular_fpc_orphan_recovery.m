function tests = test_rectangular_fpc_orphan_recovery
% Orphan-lock and backup-recovery tests.
tests = functiontests(localfunctions);
end

function testStaleClaimOwnerReplacedDuringTransition(testCase)
support = test_rectangular_fpc_publish_support();
% 原地认领协议回归：stale 判定后、原子换主前，若 owner 已被其他写入者
% 换成新锁，认领方必须识别身份变化、fail closed，且不得破坏新锁。
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
support.writeStaleOwnerRecord(lockFolder, '1');
mover = @(source, destination) support.replaceOwnerDuringSwap( ...
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
support = test_rectangular_fpc_publish_support();
% 崩溃残留的孤儿认领（claimant 已死）必须可回收，发布正常完成。
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
support.writeStaleOwnerRecord(lockFolder, '1');
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
claimOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=2147483647\nhost=%s\ntoken=%s\n', ...
    support.localHostName(0), repmat('2', 1, 32));
verifyNotEmpty(testCase, support.localHostName(0), ...
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
support = test_rectangular_fpc_publish_support();
% 另一写入者正在认领（claimant 存活）时必须 fail closed，主锁不被破坏。
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
support.writeStaleOwnerRecord(lockFolder, '1');
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
claimOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\nhost=%s\ntoken=%s\n', ...
    matlabProcessID, support.localHostName(0), repmat('3', 1, 32));
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
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
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
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);
orphanBackup = support.legitimateBackupPath(paths, 'a');
mkdir(orphanBackup);
support.writeMarker(fullfile(orphanBackup, 'orphan_marker.txt'));
support.writeCommitEvidence(orphanBackup);
support.rewriteCommitManifest(orphanBackup, cell(0, 2));
support.writeBackupTransactionFixture( ...
    orphanBackup, paths.output, repmat('a', 1, 32));

rectangular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(orphanBackup));
verifyEmpty(testCase, dir(paths.backupPattern));
clear cleanup;
end

function testUnknownBackupLikeDirectorySurvivesCommittedReplacement(testCase)
support = test_rectangular_fpc_publish_support();
% Only publisher-issued, token-shaped backup names are recovery state.
% A user directory that merely shares the prefix is outside that protocol.
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
support.writeCommitEvidence(paths.output);
unknownBackup = support.unknownBackupLikePath(paths);
mkdir(unknownBackup);
support.writeMarker(fullfile(unknownBackup, 'do_not_touch.txt'));

rectangular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyTrue(testCase, isfile(fullfile(unknownBackup, 'do_not_touch.txt')));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testUnknownBackupLikeDirectoryWithoutOutputFailsClosed(testCase)
support = test_rectangular_fpc_publish_support();
% With no formal output and no legitimate publication backup, recovery has
% no authoritative source. The unknown directory must not be moved/deleted.
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
rmdir(paths.output, 's');
unknownBackup = support.unknownBackupLikePath(paths);
mkdir(unknownBackup);
support.writeMarker(fullfile(unknownBackup, 'do_not_touch.txt'));

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:AtomicRecoveryFailed');

verifyFalse(testCase, isfolder(paths.output));
verifyTrue(testCase, isfile(fullfile(unknownBackup, 'do_not_touch.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder([paths.output '_publish.lock']));
clear cleanup;
end

function testIncompleteOutputPreservesRecoveryBackup(testCase)
support = test_rectangular_fpc_publish_support();
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
delete(fullfile(paths.output, 'generation_status.txt'));
orphanBackup = support.legitimateBackupPath(paths, 'b');
mkdir(orphanBackup);
support.writeMarker(fullfile(orphanBackup, 'last_good_marker.txt'));
support.writeCommitEvidence(orphanBackup);
support.rewriteCommitManifest(orphanBackup, cell(0, 2));
support.writeBackupTransactionFixture( ...
    orphanBackup, paths.output, repmat('b', 1, 32));

verifyError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'RectangularFPC:AtomicRecoveryFailed');

verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyTrue(testCase, isfile(fullfile( ...
    orphanBackup, 'last_good_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function testStaleClaimOrphanStealLoserFailsClosed(testCase)
support = test_rectangular_fpc_publish_support();
% 孤儿回收原子性回归：两个回收者竞争同一孤儿认领时，基于过期判定
% rmdir 固定路径会删掉竞争者刚建好的新认领（TOCTOU，双持锁）。
% 原子 tombstone 竞争下，rename 落败的一方必须 fail closed，
% 且不得破坏赢家的活跃认领。
paths = support.makeFixture();
cleanup = onCleanup(@() support.removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
support.writeStaleOwnerRecord(lockFolder, '1');
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
orphanOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=2147483647\nhost=%s\ntoken=%s\n', ...
    support.localHostName(0), repmat('2', 1, 32));
verifyNotEmpty(testCase, support.localHostName(0), ...
    'stale-claim fixture must always write a non-empty host identity');
fprintf(fid, 'created=%s\n', char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
clear orphanOwnerCleanup;
mover = @(source, destination) support.stealTombstoneRace(source, destination, claimDir);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfolder(claimDir));
verifyTrue(testCase, contains(fileread(fullfile(claimDir, 'owner.txt')), ...
    ['token=' repmat('c', 1, 32)]));
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
clear cleanup;
end
