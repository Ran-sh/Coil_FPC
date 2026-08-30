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
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
staleOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear staleOwnerCleanup;
mover = @(source, destination) replaceOwnerDuringSwap( ...
    source, destination, lockFolder);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfolder(lockFolder));
verifyTrue(testCase, contains(fileread(fullfile(lockFolder, 'owner.txt')), ...
    'token=fresh_owner_a'));
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
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
staleOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear staleOwnerCleanup;
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
claimOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=2147483647\nhost=%s\ntoken=orphan_claim\n', localHostName(0));
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
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
staleOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear staleOwnerCleanup;
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
claimOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\nhost=%s\ntoken=busy_claim\n', matlabProcessID, localHostName(0));
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

function testStaleClaimOrphanStealLoserFailsClosed(testCase)
% 孤儿回收原子性回归：两个回收者竞争同一孤儿认领时，基于过期判定
% rmdir 固定路径会删掉竞争者刚建好的新认领（TOCTOU，双持锁）。
% 原子 tombstone 竞争下，rename 落败的一方必须 fail closed，
% 且不得破坏赢家的活跃认领。
paths = makeFixture();
cleanup = onCleanup(@() removeFixture(paths.root));
lockFolder = [paths.output '_publish.lock'];
mkdir(lockFolder);
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
staleOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear staleOwnerCleanup;
claimDir = fullfile(lockFolder, 'reclaim.claim');
mkdir(claimDir);
fid = fopen(fullfile(claimDir, 'owner.txt'), 'w');
orphanOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=2147483647\nhost=%s\ntoken=orphan_claim\n', localHostName(0));
fprintf(fid, 'created=%s\n', char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
clear orphanOwnerCleanup;
mover = @(source, destination) stealTombstoneRace(source, destination, claimDir);

assertError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), 'RectangularFPC:ConcurrentPublish');

verifyTrue(testCase, isfolder(claimDir));
verifyTrue(testCase, contains(fileread(fullfile(claimDir, 'owner.txt')), ...
    'token=busy_claim'));
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
    fprintf(fid, 'pid=%d\nhost=sim-host-b\ntoken=busy_claim\n', matlabProcessID);
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
if strcmp(destination, ownerFile) && endsWith(source, 'owner.txt.new')
    fid = fopen(ownerFile, 'w');
    freshCleanup = onCleanup(@() fclose(fid));
    fprintf(fid, 'pid=1\nhost=sim-host-a\ntoken=fresh_owner_a\n');
    fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
    clear freshCleanup;
    delete(source);
    moved = true;
    message = '';
else
    [moved, message] = movefile(source, destination);
end
end

function host = localHostName(ignore)
% 带 1 个输入参数（避免被 functiontests 当作测试函数注册）。
%ignore documents the intentionally unused input argument.
host = lower(strtrim(getenv('COMPUTERNAME')));
if isempty(host)
    host = lower(strtrim(getenv('HOSTNAME')));
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
