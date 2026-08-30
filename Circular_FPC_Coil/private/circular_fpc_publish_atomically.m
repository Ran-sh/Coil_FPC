function circular_fpc_publish_atomically( ...
    stagingFolder, outputFolder, moveFolder)
%CIRCULAR_FPC_PUBLISH_ATOMICALLY Commit one verified output tree once.
%   A sibling *_publish.lock directory serializes writers targeting the
%   same design. Locks left by dead local owners (process exit, power loss)
%   are claimed in place — the lock directory never disappears — while
%   foreign-host and fresh malformed locks still fail closed. Existing
%   formal output is never replaced. The optional MOVEFOLDER handle
%   supports deterministic failure-path tests.

if nargin < 2
    error('CircularFPC:InvalidPublishRequest', ...
        'Both a staging folder and an output folder are required.');
end
if nargin < 3 || isempty(moveFolder)
    moveFolder = @movefile;
elseif ~isa(moveFolder, 'function_handle')
    error('CircularFPC:InvalidPublishMover', ...
        'The injected folder mover must be a function handle.');
end
if ~isfolder(stagingFolder)
    error('CircularFPC:InvalidPublishRequest', ...
        'Staging folder does not exist: %s', stagingFolder);
end

stagingCleanup = onCleanup(@() removeFolder(stagingFolder));
lockFolder = [outputFolder '_publish.lock'];
lockCleanup = acquirePublishLock(lockFolder, moveFolder); %#ok<NASGU>

if isfolder(outputFolder)
    error('CircularFPC:OutputExists', ...
        'Output directory already exists: %s', outputFolder);
elseif isfile(outputFolder)
    error('CircularFPC:AtomicPublishFailed', ...
        'Formal output path is occupied by a file: %s', outputFolder);
end

try
    [moved, message] = tryMoveFolder(moveFolder, stagingFolder, outputFolder);
    if ~moved || ~isfolder(outputFolder) || isfolder(stagingFolder)
        if moved
            message = 'folder mover returned an inconsistent final state';
        end
        error('CircularFPC:AtomicPublishFailed', ...
            'Unable to publish the staged output: %s', message);
    end
catch publishError
    try
        removeFormalOutput(outputFolder);
    catch cleanupError
        error('CircularFPC:AtomicRollbackFailed', ...
            ['Publish failed (%s), and the partial formal output could ', ...
             'not be removed: %s'], publishError.message, cleanupError.message);
    end
    rethrow(publishError);
end

clear lockCleanup;
clear stagingCleanup;
end

function cleanup = acquirePublishLock(lockFolder, moveFolder)
% 原地认领协议（消除搬移式 stale 回收的无锁窗口）：
%   - 锁目录路径永不消失，第三方无法趁虚 mkdir 建锁；
%   - 固定名 reclaim.claim 子目录作为迁移互斥（自身带 owner 证据，
%     孤儿认领仅在 claimant 已死/过期时按现有 stale 语义回收）；
%   - 复核 owner.txt 未被替换后，经 owner.txt.new → owner.txt 原子换主。
token = uniqueToken();
if isfolder(lockFolder)
    ownerTextBefore = readPublishLockOwnerText(lockFolder);
    if ~isStalePublishLock(lockFolder)
        error('CircularFPC:ConcurrentPublish', ...
            'Another process is publishing this output: %s', ...
            lockFolder);
    end
    claimDir = fullfile(lockFolder, 'reclaim.claim');
    if ~acquireReclaimClaim(claimDir)
        error('CircularFPC:ConcurrentPublish', ...
            'Another process is reclaiming the stale lock at %s', ...
            lockFolder);
    end
    claimCleanup = onCleanup(@() releaseReclaimClaim(claimDir));
    ownerChanged = ~strcmp(readPublishLockOwnerText(lockFolder), ownerTextBefore);
    if ~ownerChanged
        replaceOwnerAtomically(lockFolder, token, moveFolder);
        ownerChanged = ~strcmp(readLockToken(lockFolder), token);
    end
    clear claimCleanup;
    if ownerChanged
        error('CircularFPC:ConcurrentPublish', ...
            ['Publish lock at %s changed identity during stale claim; ', ...
             'another writer now owns it.'], lockFolder);
    end
else
    [created, message, messageId] = mkdir(lockFolder);
    if ~created || strcmp(messageId, 'MATLAB:MKDIR:DirectoryExists')
        error('CircularFPC:ConcurrentPublish', ...
            'Another process is publishing this output: %s (%s)', ...
            lockFolder, message);
    end
    try
        writeLockOwner(lockFolder, token);
    catch ownerError
        rmdir(lockFolder, 's');
        rethrow(ownerError);
    end
end
cleanup = onCleanup(@() releasePublishLock(lockFolder, token));
end

function ok = acquireReclaimClaim(claimDir)
ok = tryCreateClaimDir(claimDir);
if ~ok && isStalePublishLock(claimDir)
    % 崩溃残留的孤儿认领：仅当 claimant 自身已死/过期时才可回收重试；
    % 空或畸形认领按现有 5 分钟宽限语义处理，不立即抢占。
    rmdir(claimDir, 's');
    ok = tryCreateClaimDir(claimDir);
end
if ok
    try
        writeLockOwner(claimDir, uniqueToken());
    catch
        releaseReclaimClaim(claimDir);
        ok = false;
    end
end
end

function ok = tryCreateClaimDir(claimDir)
[created, ~, messageId] = mkdir(claimDir);
ok = created && ~strcmp(messageId, 'MATLAB:MKDIR:DirectoryExists');
end

function releaseReclaimClaim(claimDir)
if isfolder(claimDir)
    rmdir(claimDir, 's');
end
end

function replaceOwnerAtomically(lockFolder, token, moveFolder)
pendingOwner = fullfile(lockFolder, 'owner.txt.new');
fid = fopen(pendingOwner, 'w', 'n', 'US-ASCII');
if fid == -1
    error('CircularFPC:ExportWriteFailed', ...
        'Unable to create publish-lock owner swap file: %s', pendingOwner);
end
swapCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\n', matlabProcessID);
fprintf(fid, 'host=%s\n', localHostIdentity());
fprintf(fid, 'token=%s\n', token);
fprintf(fid, 'created=%s\n', char(datetime('now', ...
    'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
clear swapCleanup;
[replaced, replaceMessage] = tryMoveFolder(moveFolder, pendingOwner, ...
    fullfile(lockFolder, 'owner.txt'));
if ~replaced
    if isfile(pendingOwner)
        delete(pendingOwner);
    end
    error('CircularFPC:ConcurrentPublish', ...
        'Unable to swap publish-lock owner at %s: %s', lockFolder, replaceMessage);
end
end

function writeLockOwner(lockFolder, token)
filename = fullfile(lockFolder, 'owner.txt');
fid = fopen(filename, 'w', 'n', 'US-ASCII');
if fid == -1
    error('CircularFPC:ExportWriteFailed', ...
        'Unable to create publish-lock owner: %s', filename);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\n', matlabProcessID);
fprintf(fid, 'host=%s\n', localHostIdentity());
fprintf(fid, 'token=%s\n', token);
fprintf(fid, 'created=%s\n', char(datetime('now', ...
    'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));
clear cleanup;
end

function releasePublishLock(lockFolder, token)
if isfolder(lockFolder) && strcmp(readLockToken(lockFolder), token)
    rmdir(lockFolder, 's');
end
end

function token = readLockToken(lockFolder)
token = '';
ownerFile = fullfile(lockFolder, 'owner.txt');
if ~isfile(ownerFile)
    return;
end
match = regexp(fileread(ownerFile), '(?m)^token=([^\r\n]+)$', ...
    'tokens', 'once');
if ~isempty(match)
    token = match{1};
end
end

function text = readPublishLockOwnerText(lockFolder)
text = '';
ownerFile = fullfile(lockFolder, 'owner.txt');
if isfile(ownerFile)
    text = fileread(ownerFile);
end
end

function [moved, message] = tryMoveFolder(moveFolder, source, destination)
try
    [moved, message] = moveFolder(source, destination);
catch moveError
    moved = false;
    message = moveError.message;
end
if ~moved && isempty(message)
    message = 'unspecified folder move failure';
end
end

function removeFolder(folder)
if isfolder(folder)
    rmdir(folder, 's');
end
end

function removeFormalOutput(outputPath)
if isfolder(outputPath)
    rmdir(outputPath, 's');
elseif isfile(outputPath)
    delete(outputPath);
end
end

function stale = isStalePublishLock(lockFolder)

ownerFile = fullfile(lockFolder, 'owner.txt');
if isfile(ownerFile)
    ownerText = fileread(ownerFile);
    pidMatch = regexp(ownerText, '(?m)^pid=(\d+)$', ...
        'tokens', 'once');
    hostMatch = regexp(ownerText, '(?m)^host=([^\r\n]+)$', ...
        'tokens', 'once');
    if isempty(pidMatch) || isempty(hostMatch)
        stale = isExpiredIncompleteLock(ownerText, ownerFile);
    elseif ~strcmpi(strtrim(hostMatch{1}), localHostIdentity())
        stale = false;
    else
        stale = ~isProcessAlive(str2double(pidMatch{1}));
    end
else
    stale = isExpiredIncompleteLock('', lockFolder);
end

end

function alive = isProcessAlive(pid)

alive = true;
if ~isfinite(pid) || pid < 1 || pid ~= floor(pid)
    return;
end
if ispc
    try
        process = System.Diagnostics.Process.GetProcessById(int32(pid));
        alive = ~process.HasExited;
        process.Dispose();
    catch probeError
        if ~isempty(probeError.ExceptionObject) && strcmp( ...
                char(probeError.ExceptionObject.GetType().FullName), ...
                'System.ArgumentException')
            alive = false;
        else
            alive = true;
        end
    end
elseif isunix
    [status, ~] = system(sprintf('ps -p %d -o pid=', pid));
    if status == 0
        alive = true;
    elseif status == 1
        alive = false;
    else
        alive = true;
    end
end

end

function expired = isExpiredIncompleteLock(ownerText, fallbackPath)

gracePeriod = minutes(5);
created = NaT;
match = regexp(ownerText, '(?m)^created=([^\r\n]+)$', ...
    'tokens', 'once');
if ~isempty(match)
    try
        created = datetime(match{1}, ...
            'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX', ...
            'TimeZone', 'UTC');
    catch
        created = NaT;
    end
end
if isnat(created)
    info = dir(fallbackPath);
    if isempty(info)
        expired = false;
        return;
    end
    created = datetime(info(1).datenum, 'ConvertFrom', 'datenum', ...
        'TimeZone', 'UTC');
end
expired = datetime('now', 'TimeZone', 'UTC') - created > gracePeriod;

end

function host = localHostIdentity()

host = getenv('COMPUTERNAME');
if isempty(host)
    host = getenv('HOSTNAME');
end
if isempty(host)
    try
        host = char(java.net.InetAddress.getLocalHost().getHostName());
    catch
        host = '';
    end
end
host = lower(strtrim(host));
if isempty(host)
    error('CircularFPC:PublishHostUnavailable', ...
        'Unable to determine the local host identity for publication locking.');
end

end

function token = uniqueToken()
token = char(java.util.UUID.randomUUID());
token = strrep(token, '-', '');
end
