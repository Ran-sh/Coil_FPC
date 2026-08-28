function rectangular_fpc_publish_atomically( ...
    tempOutputFolder, outputFolder, moveFolder)
%RECTANGULAR_FPC_PUBLISH_ATOMICALLY Publish one minute-version atomically.
%   RECTANGULAR_FPC_PUBLISH_ATOMICALLY(STAGING, OUTPUT) replaces OUTPUT
%   with STAGING while retaining a recoverable backup until publication
%   succeeds. An optional MOVEFOLDER function handle supports deterministic
%   failure-path testing and defaults to @movefile.
%   The sibling *_publish.lock directory is the commit barrier: readers must
%   retry while it exists and only open OUTPUT after observing it absent.

if nargin < 2
    error('RectangularFPC:InvalidPublishRequest', ...
        'Both a staging folder and an output folder are required.');
end
if nargin < 3 || isempty(moveFolder)
    moveFolder = @movefile;
elseif ~isa(moveFolder, 'function_handle')
    error('RectangularFPC:InvalidPublishMover', ...
        'The injected folder mover must be a function handle.');
end

stagingCleanup = onCleanup(@() removeStagingFolder(tempOutputFolder));
lockFolder = [outputFolder '_publish.lock'];
lockCleanup = acquirePublishLock( ...
    lockFolder, moveFolder); %#ok<NASGU>

recoverOrphanBackup(outputFolder, moveFolder);
backupFolder = sprintf('%s_backup_%s', outputFolder, uniqueToken());

hadPriorVersion = isfolder(outputFolder);
if hadPriorVersion
    [moved, message] = tryMoveFolder( ...
        moveFolder, outputFolder, backupFolder);
    if ~moved
        error('RectangularFPC:AtomicPublishFailed', ...
            'Unable to stage the prior version for replacement: %s', message);
    end
elseif isfile(outputFolder)
    error('RectangularFPC:AtomicPublishFailed', ...
        'Formal output path is occupied by a file: %s', outputFolder);
end

try
    [moved, message] = tryMoveFolder( ...
        moveFolder, tempOutputFolder, outputFolder);
    if ~moved
        error('RectangularFPC:AtomicPublishFailed', ...
            'Unable to publish the staged version: %s', message);
    end
catch publishError
    rollbackFailedPublish( ...
        publishError, outputFolder, backupFolder, hadPriorVersion, moveFolder);
end

if isfolder(backupFolder)
    try
        rmdir(backupFolder, 's');
    catch cleanupError
        warning('RectangularFPC:BackupCleanupFailed', ...
            'Published successfully, but backup cleanup failed: %s', ...
            cleanupError.message);
    end
end

clear lockCleanup;
clear stagingCleanup;

end


function rollbackFailedPublish( ...
    publishError, outputFolder, backupFolder, hadPriorVersion, moveFolder)

cleanupFailure = '';
if isfolder(outputFolder)
    try
        rmdir(outputFolder, 's');
    catch cleanupError
        cleanupFailure = cleanupError.message;
    end
end

if hadPriorVersion && isfolder(backupFolder)
    if isempty(cleanupFailure)
        [restored, restoreMessage] = tryMoveFolder( ...
            moveFolder, backupFolder, outputFolder);
    else
        restored = false;
        restoreMessage = sprintf( ...
            'partial published output could not be removed: %s', ...
            cleanupFailure);
    end
    if ~restored
        error('RectangularFPC:AtomicRollbackFailed', ...
            ['Publish failed (%s), and the prior version could not be ', ...
            'restored from %s: %s'], ...
            publishError.message, backupFolder, restoreMessage);
    end
elseif ~isempty(cleanupFailure)
    error('RectangularFPC:AtomicRollbackFailed', ...
        ['Publish failed (%s), and the partial formal output could ', ...
        'not be removed: %s'], publishError.message, cleanupFailure);
end

rethrow(publishError);

end


function cleanup = acquirePublishLock(lockFolder, moveFolder)

staleClaimFolder = '';
if isfolder(lockFolder)
    if ~isStalePublishLock(lockFolder)
        error('RectangularFPC:ConcurrentPublish', ...
            'Another process is publishing this minute version: %s', ...
            lockFolder);
    end
    staleClaimFolder = sprintf('%s_stale_%s', lockFolder, uniqueToken());
    [claimed, claimMessage] = tryMoveFolder( ...
        moveFolder, lockFolder, staleClaimFolder);
    if ~claimed
        error('RectangularFPC:ConcurrentPublish', ...
            'Unable to claim stale publication lock %s: %s', ...
            lockFolder, claimMessage);
    end
    staleCleanup = onCleanup(@() removeStaleLockClaim(staleClaimFolder));
end

[created, message, messageId] = mkdir(lockFolder);
if ~created || strcmp(messageId, 'MATLAB:MKDIR:DirectoryExists')
    error('RectangularFPC:ConcurrentPublish', ...
        'Another process is publishing this minute version: %s (%s)', ...
        lockFolder, message);
end

token = uniqueToken();
try
    writePublishLockOwner(lockFolder, token);
catch ownerError
    rmdir(lockFolder, 's');
    rethrow(ownerError);
end
cleanup = onCleanup(@() releasePublishLock(lockFolder, token));

if ~isempty(staleClaimFolder)
    removeStaleLockClaim(staleClaimFolder);
    clear staleCleanup;
end

end


function releasePublishLock(lockFolder, token)

if isfolder(lockFolder) && strcmp(readPublishLockToken(lockFolder), token)
    rmdir(lockFolder, 's');
end

end


function writePublishLockOwner(lockFolder, token)

filename = fullfile(lockFolder, 'owner.txt');
fid = fopen(filename, 'w', 'n', 'US-ASCII');
if fid == -1
    error('RectangularFPC:ExportWriteFailed', ...
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


function token = readPublishLockToken(lockFolder)

token = '';
filename = fullfile(lockFolder, 'owner.txt');
if ~isfile(filename)
    return;
end
match = regexp(fileread(filename), '(?m)^token=([^\r\n]+)$', ...
    'tokens', 'once');
if ~isempty(match)
    token = match{1};
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
    if isempty(pidMatch) || isempty(hostMatch) || ...
            ~strcmpi(strtrim(hostMatch{1}), localHostIdentity())
        stale = false;
    else
        stale = ~isProcessAlive(str2double(pidMatch{1}));
    end
else
    % An ownerless lock is ambiguous (legacy or currently initializing),
    % so fail closed. A dead recorded PID is the only automatic takeover
    % condition.
    stale = false;
end

end


function alive = isProcessAlive(pid)

alive = false;
if ~isfinite(pid) || pid < 1 || pid ~= floor(pid)
    return;
end
if ispc
    try
        process = System.Diagnostics.Process.GetProcessById(int32(pid));
        alive = ~process.HasExited;
        process.Dispose();
    catch
        alive = false;
    end
else
    [status, ~] = system(sprintf('kill -0 %d 2>/dev/null', pid));
    alive = status == 0;
end

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
    error('RectangularFPC:PublishHostUnavailable', ...
        'Unable to determine the local host identity for publication locking.');
end

end


function removeStaleLockClaim(folder)

if isfolder(folder)
    rmdir(folder, 's');
end

end


function recoverOrphanBackup(outputFolder, moveFolder)

if isfolder(outputFolder)
    return;
end
if isfile(outputFolder)
    error('RectangularFPC:AtomicPublishFailed', ...
        'Formal output path is occupied by a file: %s', outputFolder);
end

[parentFolder, outputName] = fileparts(outputFolder);
backups = dir(fullfile(parentFolder, [outputName '_backup_*']));
backups = backups([backups.isdir]);
if isempty(backups)
    return;
end

[~, newestIndex] = max([backups.datenum]);
backupFolder = fullfile(backups(newestIndex).folder, backups(newestIndex).name);
[restored, message] = tryMoveFolder( ...
    moveFolder, backupFolder, outputFolder);
if ~restored
    error('RectangularFPC:AtomicRecoveryFailed', ...
        'Unable to recover interrupted publication from %s: %s', ...
        backupFolder, message);
end

end


function [moved, message] = tryMoveFolder( ...
    moveFolder, sourceFolder, destinationFolder)

try
    [moved, message] = moveFolder(sourceFolder, destinationFolder);
catch moveError
    moved = false;
    message = moveError.message;
end
if ~moved && isempty(message)
    message = 'unspecified folder move failure';
end

end


function removeStagingFolder(tempOutputFolder)

if isfolder(tempOutputFolder)
    rmdir(tempOutputFolder, 's');
end

end


function token = uniqueToken()

token = char(java.util.UUID.randomUUID());
token = strrep(token, '-', '');

end
