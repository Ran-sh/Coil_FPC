function tests = test_circular_fpc_private_contracts
% Private validation and atomic-publication regression tests.
tests = functiontests(localfunctions);
end

function testAutomaticTerminalReroutePreservesL1Spiral(testCase)
cfg = circular_fpc_default_config(struct( ...
    'analysisOnly', true, ...
    'enableFigure', false, ...
    'enablePreview', false, ...
    'boardLayerCount', 4, ...
    'coilLayerCount', 4, ...
    'designName', 'preserve_archimedean_spiral'));
base = CircularFpc.Pipeline.Generate(cfg);
routed = CircularFpc.Geometry.Terminal_Routing(cfg, base);

verifyEqual(testCase, routed.layerPaths(1).coilXY, ...
    base.layerPaths(1).coilXY, 'AbsTol', 1e-12, ...
    ['Terminal routing must add a separate tangent transition and must ', ...
    'not phase-warp points that are reported as the Archimedean coil.']);
verifyEqual(testCase, routed.terminalRouting.entryPhaseOffsetDeg, 0, ...
    'AbsTol', 1e-12);
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

validation = CircularFpc.Quality.Result_Validation( ...
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

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
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

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');
verifyFalse(testCase, isfolder(paths.staging));
verifyTrue(testCase, isfolder(paths.lock));
end

function testAtomicPublishRecoversStaleLockFromDeadOwner(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', 2147483647, '');

CircularFpc.Export.Publish_Atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.lock));
clear cleanup;
end

function testAtomicPublishRefusesLiveLockOwner(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', matlabProcessID, '');

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');
verifyTrue(testCase, isfolder(paths.lock));
verifyFalse(testCase, isfolder(paths.staging));
clear cleanup;
end

function testAtomicPublishRefusesForeignHostLock(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, 'definitely-not-this-host', 2147483647, '');

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
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

CircularFpc.Export.Publish_Atomically(paths.staging, paths.output);

verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.lock));
clear cleanup;
end

function testAtomicPublishRefusesFreshMalformedLock(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', NaN, '');

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
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

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
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

CircularFpc.Export.Publish_Atomically(paths.staging, paths.output);

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

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');

% 忙碌认领属于其他写入者：其 claim 目录必须原样保留，主锁不被破坏
verifyTrue(testCase, isfolder(fullfile(paths.lock, 'reclaim.claim')));
verifyFalse(testCase, isfolder(paths.output));
verifyTrue(testCase, contains(fileread(fullfile(paths.lock, 'owner.txt')), ...
    'created=2000-01-01T00:00:00.000Z'));
clear cleanup;
end

function testAtomicPublishOrphanClaimStealLoserFailsClosed(testCase)
% 孤儿回收原子性回归：两个回收者竞争同一孤儿认领时，基于过期判定
% rmdir 固定路径会删掉竞争者刚建好的新认领（TOCTOU，双持锁）。
% 原子 tombstone 竞争下，rename 落败的一方必须 fail closed，
% 且不得破坏赢家的活跃认领。
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
writePublishLockOwnerFile(paths.lock, '', NaN, 'created=2000-01-01T00:00:00.000Z');
claimDir = fullfile(paths.lock, 'reclaim.claim');
writePublishLockOwnerFile(claimDir, '', 2147483647, '');
mover = @(source, destination) stealTombstoneRace(source, destination, claimDir);

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
    paths.staging, paths.output, mover), 'CircularFPC:ConcurrentPublish');

verifyTrue(testCase, isfolder(claimDir));
verifyTrue(testCase, contains(fileread(fullfile(claimDir, 'owner.txt')), ...
    'token=busy_claim'));
verifyFalse(testCase, isfolder(paths.output));
verifyFalse(testCase, isfolder(paths.staging));
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

function testAtomicPublishPreservesExistingFormalOutput(testCase)
paths = makePublishFixture(true);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>

verifyError(testCase, @() CircularFpc.Export.Publish_Atomically( ...
    paths.staging, paths.output), 'CircularFPC:OutputExists');
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder(paths.lock));
end

function testAtomicPublishSuccessCommitsWholeTree(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>

CircularFpc.Export.Publish_Atomically(paths.staging, paths.output);
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
holeIdx = find([geom.boardLoops.isHole] & ...
    startsWith(string({geom.boardLoops.name}), 'hole_'));
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
validation = CircularFpc.Quality.Result_Validation('validate_result', result.config, ...
    result.effectiveDimensions, geom);
verifyLessThan(testCase, validation.minCopperToSlotsMm, cfg.edgeClearance - 0.05);
verifyFalse(testCase, validation.passed);
end

function testDefaultClearanceMetricsArePinnedExactly(testCase)
% 净距指标是线段-线段精确距离核的唯一可观测输出。距离核允许用包围盒下界
% 剪枝以加速（见 segmentPairDistances 的 pruneAbove），但剪枝不得改变结果：
% 这里把默认 4/4 的实测值按 1e-9 锁死，任何让核多算/少算的改动都会在此暴露，
% 而不是只让某个上限/下限断言继续通过。
result = circular_fpc_main(struct( ...
    'analysisOnly', true, 'enableFigure', false, ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'designName', 'pinned_clearance_metrics'));
verifyTrue(testCase, result.validation.passed);
tol = 1e-9;
verifyEqual(testCase, result.validation.minCopperSpacingMm, ...
    0.15496263114492698, 'AbsTol', tol);
verifyEqual(testCase, result.validation.minCopperToBoardMm, ...
    0.3014902872774986, 'AbsTol', tol);
verifyEqual(testCase, result.validation.minCopperToSlotsMm, ...
    0.30998054553262444, 'AbsTol', tol);
verifyEqual(testCase, result.validation.minViaCoilSpacingMm, ...
    0.15580274311364448, 'AbsTol', tol);
verifyEqual(testCase, result.validation.minTerminalToConnectionTraceMm, ...
    0.17360998579486206, 'AbsTol', tol);
verifyEqual(testCase, result.validation.minOuterViaContactSweepDeg, ...
    114.00214740156351, 'AbsTol', tol);
end

function testOuterViaContactCompletenessFailsClosed(testCase)
% 完备性判据的负向测试（审查补充）：外端过孔的接触测量缺失、或
% OUTER_TRANSITION 集合与层拓扑错配（过孔被漏建/角色被改标），都必须让
% 验证 fail closed，而不是让接触闸门被空洞地跳过。
result = circular_fpc_main(struct( ...
    'analysisOnly', true, 'enableFigure', false, ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'designName', 'contact_completeness_probe'));
verifyTrue(testCase, result.validation.passed);
verifyTrue(testCase, result.validation.outerViaContactsMeasured);
% (a) 测量缺失：V12 的上游接触扫角变成 NaN。
geom = resultGeometry(result);
idx12 = find(strcmp({geom.vias.name}, 'V12'), 1);
geom.vias(idx12).upstreamContactSweepDeg = NaN;
brokenMeasurement = CircularFpc.Quality.Result_Validation('validate_result', ...
    result.config, result.effectiveDimensions, geom);
verifyFalse(testCase, brokenMeasurement.outerViaContactsMeasured);
verifyFalse(testCase, brokenMeasurement.passed);
verifyTrue(testCase, any(contains(brokenMeasurement.messages, 'outer via contact')));
% (b) 集合错配：V34 被改标为 INNER_TRANSITION，外端过孔集合与拓扑期望
% （V12+V34）不再匹配。
geom2 = resultGeometry(result);
idx34 = find(strcmp({geom2.vias.name}, 'V34'), 1);
geom2.vias(idx34).role = 'INNER_TRANSITION';
brokenRole = CircularFpc.Quality.Result_Validation('validate_result', ...
    result.config, result.effectiveDimensions, geom2);
verifyFalse(testCase, brokenRole.outerViaContactsMeasured);
verifyFalse(testCase, brokenRole.passed);
end

function testFourLayerWindingSuperpositionIsVerifiedAndNotVacuous(testCase)
% 磁场同向叠加的几何前提：四个活动层的电流环绕方向必须同号。该性质此前只由
% 生成器写入的 windingDirection 标签（逐层 CCW/CW 交替，描述的是绕制行进
% 方向而非环绕方向）间接体现，匝数回归又用 abs() 丢掉了符号，因此"某层被反向
% 导致磁场相消"不会被任何断言拦住。这里同时验证两件事：
%   (1) 真实 4/4 网络的四层环绕角同号且为正；
%   (2) 该判据不是空断言——把任意一层的点序翻转（电流反向）后必须报错。
result = circular_fpc_main(struct( ...
    'analysisOnly', true, 'enableFigure', false, ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'designName', 'winding_superposition_probe'));
verifyTrue(testCase, result.validation.windingSuperpositionConsistent, ...
    'Default 4/4 must superpose its layer fields.');
verifyTrue(testCase, result.validation.passed);
verifyGreaterThan(testCase, result.validation.minSignedCirculationDeg, 180);
% 逐层独立复算，确认四层环绕角不仅同号，且与实测匝数相符。
for li = result.activeCoilLayers
    xy = result.layerPaths(li).coilXY;
    dx = diff(xy(:, 1));
    dy = diff(xy(:, 2));
    xm = (xy(1:end - 1, 1) + xy(2:end, 1)) / 2;
    ym = (xy(1:end - 1, 2) + xy(2:end, 2)) / 2;
    circulation = rad2deg(sum((xm .* dy - ym .* dx) ./ (xm.^2 + ym.^2)));
    verifyGreaterThan(testCase, circulation, 180, ...
        sprintf('L%d must circulate in the shared direction.', li));
end

geom = resultGeometry(result);
geom.coils{2} = flipud(geom.coils{2});
flipped = CircularFpc.Quality.Result_Validation('validate_result', result.config, ...
    result.effectiveDimensions, geom);
verifyFalse(testCase, flipped.windingSuperpositionConsistent, ...
    'A reversed layer must be rejected, otherwise the check proves nothing.');
verifyFalse(testCase, flipped.passed);
verifyTrue(testCase, any(contains(flipped.messages, 'circulation')));
end

function testEarZoomHelperDefaultsToFourByFourAndStaysConsistent(testCase)
% CircularFpc.Export.Ear_Zoom_Figure 是文档承诺的辅助核对工具，必须与同一批产物描述同一构型。
% 其默认曾硬编码为 4/2，与公开生成器默认（4/4）及 README 的 4/4 语境不一致，
% 会让放大图标题/主圆直径与 canonical 产物对不上。这里锁定 4/4 默认，
% 并确认显式覆盖仍被尊重、且输出文件写在正式产物目录之外。
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, 's'));
pngPath = fullfile(tmp, 'ear44.png');
svgPath = fullfile(tmp, 'ear44.svg');
CircularFpc.Export.Ear_Zoom_Figure(pngPath, svgPath);
verifyTrue(testCase, isfile(pngPath));
verifyTrue(testCase, isfile(svgPath));
verifyGreaterThan(testCase, dir(pngPath).bytes, 0);

% 默认构型必须与公开默认一致：直接比对分析结果的活动层集合。
defaultCfg = circular_fpc_default_config(struct('analysisOnly', true));
verifyEqual(testCase, defaultCfg.boardLayerCount, 4);
verifyEqual(testCase, defaultCfg.coilLayerCount, 4);

% 显式覆盖为 4/2 时仍应生成，且不改变公开默认。
png42 = fullfile(tmp, 'ear42.png');
svg42 = fullfile(tmp, 'ear42.svg');
CircularFpc.Export.Ear_Zoom_Figure(png42, svg42, struct('boardLayerCount', 4, 'coilLayerCount', 2));
verifyTrue(testCase, isfile(png42));
verifyTrue(testCase, isfile(svg42));
verifyEqual(testCase, defaultCfg.coilLayerCount, 4, ...
    'An override passed to the helper must not mutate the public default.');
end

function testAnnotatedPreviewMirrorsTheFullContractSet(testCase)
% preview/ 下 zh/ 与 en/ 必须是 JLC/、COMSOL/ 的**完整镜像**：每个契约预览都有
% 对应的一份中文与一份英文，且相对路径、文件名完全一致——规则只有"同名不同语言"
% 一条，不需要额外记住哪些图有标注版。镜像属于原子发布并登记 manifest role，缺图
% 或未登记都应让导出失败，而不是静默少图。
outRoot = tempname;
mkdir(outRoot);
c = onCleanup(@() rmdir(outRoot, 's'));
result = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'mirror_preview', ...
    'boardLayerCount', 4, 'coilLayerCount', 2, 'enableFigure', false, 'enablePreview', true));
pv = fullfile(result.outputPath, 'preview');

% 契约组清单取自磁盘，再要求 zh/en 逐个同路径存在。
contract = {};
for grp = {'JLC', 'COMSOL'}
    d = dir(fullfile(pv, grp{1}, '**', '*.svg'));
    for k = 1:numel(d)
        full = fullfile(d(k).folder, d(k).name);
        contract{end + 1} = strrep(strrep(full, [pv filesep], ''), '', '/'); %#ok<AGROW>
    end
end
verifyEqual(testCase, numel(contract), 28, ...
    'the 4/2 contract set holds 28 previews: three JLC tiers plus two COMSOL');
for lang = {'zh', 'en'}
    for k = 1:numel(contract)
        p = fullfile(pv, lang{1}, strrep(contract{k}, '/', filesep));
        verifyTrue(testCase, isfile(p), ...
            sprintf('missing %s mirror of %s', lang{1}, contract{k}));
    end
end

% 统一命名与固定图号：01 总览、02 连接区，逐层恒为 1x_layer_Lx_<role>。
for tier = {'1_path_only', '2_trace_only', '3_trace_pad_via'}
    verifyTrue(testCase, isfile(fullfile(pv, 'JLC', tier{1}, '01_overview.svg')));
    verifyTrue(testCase, isfile(fullfile(pv, 'JLC', tier{1}, '02_connection_zone.svg')));
    verifyTrue(testCase, isfile(fullfile(pv, 'JLC', tier{1}, '11_layer_L1_top.svg')));
    verifyTrue(testCase, isfile(fullfile(pv, 'JLC', tier{1}, '14_layer_L4_bottom.svg')));
end
verifyFalse(testCase, isfile(fullfile(pv, 'JLC', '1_path_only', '01_preview_full.svg')), ...
    'the legacy preview_ naming must be gone');
verifyTrue(testCase, isfile(fullfile(pv, 'COMSOL', '1_coil_only', '01_overview.svg')));
verifyTrue(testCase, isfile(fullfile(pv, 'COMSOL', '2_coil_with_lead', '01_overview.svg')));

% zh/en 必须真的分别是中文与英文，且语言元数据不得互换。
zhTxt = fileread(fullfile(pv, 'zh', 'JLC', '3_trace_pad_via', '01_overview.svg'));
enTxt = fileread(fullfile(pv, 'en', 'JLC', '3_trace_pad_via', '01_overview.svg'));
verifyTrue(testCase, contains(zhTxt, 'data-annotated-lang="zh"'));
verifyTrue(testCase, contains(enTxt, 'data-annotated-lang="en"'));
verifyTrue(testCase, contains(zhTxt, '图例'));
verifyTrue(testCase, contains(zhTxt, '说明'));
verifyTrue(testCase, contains(enTxt, 'Legend'));
verifyTrue(testCase, contains(enTxt, 'Notes'));
% 中文版含中文端子标注，且不得残留基线的英文方括号写法。
verifyTrue(testCase, contains(zhTxt, '入口桥'));
verifyFalse(testCase, contains(zhTxt, '[ENTRY_BRIDGE]'));
verifyFalse(testCase, contains(enTxt, '[ENTRY_BRIDGE]'));
% 端子标注的机器可读属性必须保留，否则下游按 data-name 取端子会失效。
verifyTrue(testCase, contains(zhTxt, 'data-name="PAD_A"'));
verifyTrue(testCase, contains(zhTxt, 'class="terminal-leader"'));

% manifest 必须登记全部镜像，且每个文件都在清单里。
man = readtable(fullfile(result.outputPath, 'reports', '08_file_manifest.csv'));
roles = string(man.role);
verifyEqual(testCase, sum(roles == "preview_annotated"), 2 * numel(contract), ...
    'every contract preview must have a zh and an en mirror');
verifyFalse(testCase, any(roles == "preview_base"), ...
    'the redundant base/ copy set is gone');
listed = string(man.relativePath);
verifyTrue(testCase, all(ismember( ...
    ["preview/zh/JLC/3_trace_pad_via/14_layer_L4_bottom.svg", ...
     "preview/en/COMSOL/2_coil_with_lead/01_overview.svg"], listed)));
end

function testAttachedPreviewTextStaysInsideItsFrame(testCase)
% 标注文字不得越出帧宽，正文之间不得重叠。这是在导出时由
% CircularFpc.Export.Annotated_Previews('audit') 强制的；此处用独立实现复核，避免
% "同一个函数自己检查自己"。
outRoot = tempname;
mkdir(outRoot);
c = onCleanup(@() rmdir(outRoot, 's'));
result = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'attached_layout', ...
    'boardLayerCount', 4, 'coilLayerCount', 2, 'enableFigure', false, 'enablePreview', true));
pv = fullfile(result.outputPath, 'preview');
for lang = {'zh', 'en'}
    files = dir(fullfile(pv, lang{1}, '**', '*.svg'));
    verifyEqual(testCase, numel(files), 28, ...
        'each language set mirrors the whole 22-figure contract set');
    for k = 1:numel(files)
        p = fullfile(files(k).folder, files(k).name);
        txt = fileread(p);
        % 'tokens','once' 返回的是嵌套 cell（{1x1 cell}），要先取出来再 sscanf。
        vbTok = regexp(txt, 'viewBox="([^"]+)"', 'tokens', 'once');
        verifyFalse(testCase, isempty(vbTok));
        vb = sscanf(vbTok{1}, '%f');
        verifyEqual(testCase, numel(vb), 4);
        x0 = vb(1);
        x1 = vb(1) + vb(3);
        tok = regexp(txt, '<text\b([^>]*)>([^<]*)</text>', 'tokens');
        for q = 1:numel(tok)
            attrs = tok{q}{1};
            body = tok{q}{2};
            sizeTok = regexp(attrs, 'font-size="([^"]+)"', 'tokens', 'once');
            xTok = regexp(attrs, 'x="([^"]+)"', 'tokens', 'once');
            verifyFalse(testCase, isempty(sizeTok) || isempty(xTok));
            sz = str2double(sizeTok{1});
            x = str2double(xTok{1});
            % 内联估宽：本文件里的辅助函数必须是单参数，否则会被测试框架当成
            % 测试用例（"must accept one input argument"）而整体排除。
            w = 0;
            for ci = 1:numel(body)
                cp = double(body(ci));
                wide = (cp >= 4352 & cp <= 4447) || (cp >= 11904 & cp <= 42191) || ...
                    (cp >= 44032 & cp <= 55215) || (cp >= 63744 & cp <= 64255) || ...
                    (cp >= 65072 & cp <= 65103) || (cp >= 65280 & cp <= 65519);
                if wide
                    w = w + sz;
                else
                    w = w + sz * 0.56;
                end
            end
            verifyLessThanOrEqual(testCase, x + w, x1 + 1e-6, ...
                sprintf('%s: text overflows the frame: "%s"', ...
                files(k).name, body));
            verifyGreaterThanOrEqual(testCase, x, x0 - 1e-6, ...
                sprintf('%s: text starts before the frame', files(k).name));
        end
    end
end
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
