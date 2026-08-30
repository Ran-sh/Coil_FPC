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

function testAtomicPublishStaleClaimOwnerReplacedDuringTransition(testCase)
% 原地认领协议回归：stale 判定后、原子换主前，若 owner 已被其他写入者
% 换成新锁，认领方必须识别身份变化、fail closed，且不得破坏新锁。
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', NaN, 'created=2000-01-01T00:00:00.000Z');
mover = @(source, destination) replaceOwnerDuringSwap( ...
    source, destination, paths.lock);

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), 'CircularFPC:ConcurrentPublish');

verifyTrue(testCase, isfolder(paths.lock));
verifyTrue(testCase, contains(fileread(fullfile(paths.lock, 'owner.txt')), ...
    'token=fresh_owner_a'));
verifyFalse(testCase, isfolder(fullfile(paths.lock, 'reclaim.claim')));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function testAtomicPublishRecoversOrphanedReclaimClaim(testCase)
% 崩溃残留的孤儿认领（claimant 已死）必须可回收，发布正常完成。
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', NaN, 'created=2000-01-01T00:00:00.000Z');
claimDir = fullfile(paths.lock, 'reclaim.claim');
writePublishLockOwnerFile(claimDir, '', 2147483647, '');

circular_fpc_publish_atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.lock));
clear cleanup;
end

function testAtomicPublishRefusesBusyReclaimClaim(testCase)
% 另一写入者正在认领（claimant 存活）时必须 fail closed，主锁不被破坏。
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', NaN, 'created=2000-01-01T00:00:00.000Z');
claimDir = fullfile(paths.lock, 'reclaim.claim');
writePublishLockOwnerFile(claimDir, '', matlabProcessID, '');

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');

% 忙碌认领属于其他写入者：其 claim 目录必须原样保留，主锁不被破坏
verifyTrue(testCase, isfolder(fullfile(paths.lock, 'reclaim.claim')));
verifyFalse(testCase, isfolder(paths.output));
verifyTrue(testCase, contains(fileread(fullfile(paths.lock, 'owner.txt')), ...
    'created=2000-01-01T00:00:00.000Z'));
clear cleanup;
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

function testCopperToSlotCatchesSegmentInteriorViolation(testCase)
% M3 回归：铜-槽净距必须用 segment-to-segment 测量。构造一条两端顶点
% 均远离槽边、但线段中部掠过槽边界仅 ~0.15 mm 的附加连接路径——
% 顶点采样测不到（两端 > edgeClearance），精确线段测量必须抓到。
result = circular_fpc_main(struct( ...
    'analysisOnly', true, 'enableFigure', false, ...
    'boardLayerCount', 2, 'coilLayerCount', 2, ...
    'designName', 'slot_segment_probe'));
cfg = result.config;
geom = resultGeometry(result);
holeIdx = find([geom.boardLoops.isHole]);
verifyFalse(testCase, isempty(holeIdx));

% 选质心离端子焊盘最远的槽，避开端子净距检查的干扰
padCenter = mean(cat(1, geom.pads.xy), 1);
best = -inf;
H = [];
for k = holeIdx
    loopCentroid = mean(geom.boardLoops(k).xy(1:end-1, :), 1);
    d = norm(loopCentroid - padCenter);
    if d > best
        best = d;
        H = geom.boardLoops(k).xy;
    end
end
verifyFalse(testCase, isempty(H));

% 沿最长的边界段构造斜切线段：p1/p2 偏置 0.40/0.10 mm、切向各外延
% L/2+0.35，保证两端顶点距槽边界 > edgeClearance；线段中部在原边界段
% 上方仅 ~0.14 mm 处掠过（顶点采样不可见）。
segLen = sqrt(sum((H(2:end, :) - H(1:end-1, :)).^2, 2));
[~, sIdx] = max(segLen);
q1 = H(sIdx, :);
q2 = H(sIdx + 1, :);
tHat = (q2 - q1) / norm(q2 - q1);
nHat = [-tHat(2), tHat(1)];
loopCentroid = mean(H(1:end-1, :), 1);
if dot(nHat, q1 - loopCentroid) < 0
    nHat = -nHat; % 指向槽外（铜侧）
end
m = (q1 + q2) / 2;
w = segLen(sIdx) / 2 + 0.50;
p1 = m + nHat * 0.40 - tHat * w;
p2 = m + nHat * 0.10 + tHat * w;
endpoints = [p1; p2];
for endpointIndex = 1:2
    verifyGreaterThan(testCase, ...
        minPointToLoopDistance(endpoints(endpointIndex, :), H), ...
        cfg.edgeClearance + 0.02);
end

geom.connectionPaths{1} = [geom.connectionPaths{1}, {[p1; p2]}];
validation = circular_fpc_validation('validate_result', result.config, ...
    result.effectiveDimensions, geom);
verifyLessThan(testCase, validation.minCopperToSlotsMm, cfg.edgeClearance - 0.05);
verifyFalse(testCase, validation.passed);
end

function d = minPointToLoopDistance(point, xy)
a = xy(1:end-1, :);
b = xy(2:end, :);
p = repmat(point, size(a, 1), 1);
ab = b - a;
len2 = max(sum(ab.^2, 2), eps);
t = max(0, min(1, sum((p - a) .* ab, 2) ./ len2));
q = a + t .* ab;
d = min(sqrt(sum((p - q).^2, 2)));
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
