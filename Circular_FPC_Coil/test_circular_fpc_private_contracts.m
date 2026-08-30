function tests = test_circular_fpc_private_contracts
% Private validation and atomic-publication regression tests.
tests = functiontests(localfunctions);
end

function testTerminalAnnulusRejectsUnrelatedConnectionTrace(testCase)
result = circular_fpc_main(struct( ...
    'analysisOnly', true, 'enableFigure', false, ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'designName', 'terminal_trace_clearance_probe'));
geom = resultGeometry(result);

% Move functional L1/L2 via V12 beside the unrelated L1 exit trace.  It is
% far enough from both endpoint terminals to pass disk-to-disk clearance,
% but its annulus edge is only 0.075 mm from the trace edge (< 0.152 mm).
exitPath = result.layerPaths(1).connectionPaths{2};
midIndex = floor(size(exitPath, 1) / 2);
midPoint = exitPath(midIndex, :);
tangent = exitPath(midIndex + 1, :) - exitPath(midIndex - 1, :);
tangent = tangent / norm(tangent);
normal = [-tangent(2), tangent(1)];
candidate = midPoint + 0.45 * normal;
v12Index = find(strcmp({geom.vias.name}, 'V12'), 1);
geom.vias(v12Index).xy = candidate;

validation = circular_fpc_validation( ...
    'validate_result', result.config, result.effectiveDimensions, geom);
verifyTrue(testCase, isfield(validation, ...
    'minTerminalToConnectionTraceMm'));
verifyLessThan(testCase, validation.minTerminalToConnectionTraceMm, ...
    result.config.viaCoilSpacing);
verifyFalse(testCase, validation.passed);
verifyTrue(testCase, any(contains(validation.messages, ...
    'terminal-to-connection-trace')));
end

function testAtomicPublishMoveFailureCleansStagingAndLock(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
mover = @(source, destination) failPublishMove( ...
    source, destination, paths);

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), ...
    'CircularFPC:AtomicPublishFailed');
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder(paths.output));
verifyFalse(testCase, isfolder(paths.lock));
end

function testAtomicPublishRefusesConcurrentTarget(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
mkdir(paths.lock);

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');
verifyFalse(testCase, isfolder(paths.staging));
verifyTrue(testCase, isfolder(paths.lock));
end

function testAtomicPublishRecoversStaleLockFromDeadOwner(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', 2147483647, '');

circular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.lock));
clear cleanup;
end

function testAtomicPublishRefusesLiveLockOwner(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', matlabProcessID, '');

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');
verifyTrue(testCase, isfolder(paths.lock));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function testAtomicPublishRefusesForeignHostLock(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, 'definitely-not-this-host', 2147483647, '');

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');
verifyTrue(testCase, isfolder(paths.lock));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function testAtomicPublishRecoversExpiredMalformedLock(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', NaN, ...
    'created=2000-01-01T00:00:00.000Z');

circular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.lock));
clear cleanup;
end

function testAtomicPublishRefusesFreshMalformedLock(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', NaN, '');

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');
verifyTrue(testCase, isfolder(paths.lock));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function writePublishLockOwnerFile(lockFolder, host, pid, createdText)
% host 为空时写入本机身份（与发布器 localHostIdentity 相同的解析顺序）。
if ~isfolder(lockFolder)
    mkdir(lockFolder);
end
if isempty(host)
    host = getenv('COMPUTERNAME');
    if isempty(host)
        host = getenv('HOSTNAME');
    end
    if isempty(host)
        host = char(java.net.InetAddress.getLocalHost().getHostName());
    end
    host = lower(strtrim(host));
end
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\n', pid);
fprintf(fid, 'host=%s\n', host);
fprintf(fid, 'token=test_lock_owner\n');
if isempty(createdText)
    fprintf(fid, 'created=%s\n', char(datetime('now', ...
        'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
else
    fprintf(fid, '%s\n', createdText);
end
clear cleanup;
end

function testAtomicPublishStaleClaimRejectsReplacedFreshLock(testCase)
% TOCTOU 回归：stale 判定后、claim 生效前，若同路径已被其他写入者的
% 全新锁占用，claim 必须识别身份变化、原样恢复并 fail closed，
% 不得破坏仍活跃的锁。
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
mkdir(paths.lock);
fid = fopen(fullfile(paths.lock, 'owner.txt'), 'w');
staleOwnerCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear staleOwnerCleanup;
mover = @(source, destination) replaceLockDuringClaim( ...
    source, destination, paths.lock);

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), 'CircularFPC:ConcurrentPublish');

verifyTrue(testCase, isfolder(paths.lock));
verifyTrue(testCase, contains(fileread(fullfile(paths.lock, 'owner.txt')), ...
    'token=fresh_owner_a'));
verifyFalse(testCase, isfolder(paths.staging));
verifyEmpty(testCase, dir([paths.lock '_stale_*']));
clear cleanup;
end

function [moved, message] = replaceLockDuringClaim(source, destination, lockFolder)
% 模拟 stale 回收竞争：在 stale 判定之后、claim 生效之前，另一写入者 A
% 已回收旧锁并在同路径建立全新锁；随后的 claim 搬走的是 A 的新鲜锁。
isClaim = strcmp(source, lockFolder) && ...
    startsWith(destination, [lockFolder '_stale_']);
isRestore = startsWith(source, [lockFolder '_stale_']) && ...
    strcmp(destination, lockFolder);
if isClaim
    simClaim = [lockFolder '_stale_sim_a'];
    movefile(source, simClaim);
    rmdir(simClaim, 's');
    mkdir(lockFolder);
    fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
    freshCleanup = onCleanup(@() fclose(fid));
    fprintf(fid, 'pid=1\nhost=sim-host-a\ntoken=fresh_owner_a\n');
    fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
    clear freshCleanup;
    [moved, message] = movefile(source, destination);
elseif isRestore
    [moved, message] = movefile(source, destination);
else
    [moved, message] = movefile(source, destination);
end
end

function testAtomicPublishPreservesExistingFormalOutput(testCase)
paths = makePublishFixture(true);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'CircularFPC:OutputExists');
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder(paths.lock));
end

function testAtomicPublishSuccessCommitsWholeTree(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>

circular_fpc_publish_atomically(paths.staging, paths.output);
verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder(paths.lock));
end

function geom = resultGeometry(result)
nLayers = numel(result.layerPaths);
coils = cell(1, nLayers);
connectionPaths = cell(1, nLayers);
for layerIndex = 1:nLayers
    coils{layerIndex} = result.layerPaths(layerIndex).coilXY;
    connectionPaths{layerIndex} = ...
        result.layerPaths(layerIndex).connectionPaths;
end
geom = struct( ...
    'boardLoops', result.boardLoops, ...
    'actualBridgeWidth', result.effectiveDimensions.actualBridgeWidth, ...
    'layoutRegions', result.layoutRegions, ...
    'coils', {coils}, ...
    'connectionPaths', {connectionPaths}, ...
    'pads', result.pads, ...
    'vias', result.vias, ...
    'seriesRoute', result.seriesRoute, ...
    'seriesSequence', {result.seriesSequence}, ...
    'activeLayers', result.activeCoilLayers);
end

function paths = makePublishFixture(withExistingOutput)
paths.root = tempname;
paths.staging = fullfile(paths.root, 'staging');
paths.output = fullfile(paths.root, 'formal');
paths.lock = [paths.output '_publish.lock'];
mkdir(paths.root);
mkdir(paths.staging);
writeMarker(fullfile(paths.staging, 'new_marker.txt'));
if withExistingOutput
    mkdir(paths.output);
    writeMarker(fullfile(paths.output, 'old_marker.txt'));
end
end

function [moved, message] = failPublishMove(source, destination, paths)
if strcmp(source, paths.staging) && strcmp(destination, paths.output)
    mkdir(destination);
    writeMarker(fullfile(destination, 'partial_marker.txt'));
    moved = false;
    message = 'injected partial final move failure';
else
    [moved, message] = movefile(source, destination);
end
end

function writeMarker(filename)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'marker');
end

function removeTree(pathName)
if isfolder(pathName)
    rmdir(pathName, 's');
end
end
