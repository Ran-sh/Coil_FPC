function varargout = rectangular_fpc_publish_atomically( ...
    tempOutputFolder, outputFolder, moveFolder)
%RECTANGULAR_FPC_PUBLISH_ATOMICALLY Publish one minute-version atomically.
%   RECTANGULAR_FPC_PUBLISH_ATOMICALLY(STAGING, OUTPUT) replaces OUTPUT
%   with STAGING while retaining a recoverable backup until publication
%   succeeds. An optional MOVEFOLDER function handle supports deterministic
%   failure-path testing and defaults to @movefile.
%   The sibling *_publish.lock directory is the commit barrier. Readers use
%   the acquire_access operation through rectangular_fpc_read_committed so
%   checking and reading occur while holding the same exclusive lock.

if nargin >= 1 && ischar(tempOutputFolder) && ...
        strcmp(tempOutputFolder, 'acquire_access')
    if nargin ~= 2
        error('RectangularFPC:InvalidPublishRequest', ...
            'acquire_access requires exactly one output folder.');
    end
    varargout{1} = acquirePublishLock( ...
        [outputFolder '_publish.lock'], @movefile);
    return;
end

if nargin >= 1 && ischar(tempOutputFolder) && ...
        strcmp(tempOutputFolder, 'verify_committed')
    if nargin ~= 2
        error('RectangularFPC:InvalidPublishRequest', ...
            'verify_committed requires exactly one output folder.');
    end
    varargout{1} = isCommittedOutput(outputFolder);
    return;
end

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
    % TOCTOU 防护：stale 判定与目录搬移之间存在窗口，同路径可能已被
    % 其他写入者用全新锁重新占用。claim 后必须核对搬走目录的 owner
    % 证据与判定时读到的一致；不一致则原样恢复并 fail closed。
    ownerTextBefore = readPublishLockOwnerText(lockFolder);
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
    if ~strcmp(readPublishLockOwnerText(staleClaimFolder), ownerTextBefore)
        [restored, restoreMessage] = tryMoveFolder( ...
            moveFolder, staleClaimFolder, lockFolder);
        if ~restored
            warning('RectangularFPC:StaleClaimRestoreFailed', ...
                ['Stale claim of %s hit an identity change and the ', ...
                'displaced lock could not be restored: %s'], ...
                lockFolder, restoreMessage);
        end
        error('RectangularFPC:ConcurrentPublish', ...
            ['Publish lock at %s changed identity during stale claim; ', ...
            'another writer now owns it.'], lockFolder);
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


function text = readPublishLockOwnerText(lockFolder)

text = '';
ownerFile = fullfile(lockFolder, 'owner.txt');
if isfile(ownerFile)
    text = fileread(ownerFile);
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
    if hasOrphanBackups(outputFolder)
        if isCommittedOutput(outputFolder)
            removeOrphanBackups(outputFolder);
        else
            error('RectangularFPC:AtomicRecoveryFailed', ...
                ['Formal output is incomplete while a recovery backup ', ...
                'exists; both were preserved for manual inspection: %s'], ...
                outputFolder);
        end
    end
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


function present = hasOrphanBackups(outputFolder)

[parentFolder, outputName] = fileparts(outputFolder);
backups = dir(fullfile(parentFolder, [outputName '_backup_*']));
present = any([backups.isdir]);

end


function committed = isCommittedOutput(outputFolder)

committed = false;
statusFile = fullfile(outputFolder, 'generation_status.txt');
manifestFile = fullfile(outputFolder, 'reports', '08_file_manifest.csv');
if ~isfile(statusFile) || ~isfile(manifestFile) || ...
        isempty(regexp(fileread(statusFile), ...
        '(?m)^Status:\s*SUCCESS\s*$', 'once'))
    return;
end
try
    manifest = readtable(manifestFile, 'TextType', 'string');
    required = {'relativePath', 'sizeBytes', 'sha256'};
    if ~all(ismember(required, manifest.Properties.VariableNames))
        return;
    end
    listed = strrep(string(manifest.relativePath), '\', '/');
    if isempty(listed) || any(listed == "") || ...
            numel(unique(listed)) ~= numel(listed)
        return;
    end
    % 完整性门禁：清单必须与目录中除清单自身外的全部 regular files
    % 集合完全相等。逐行校验无法发现空清单/截断清单（循环 0 次即通过），
    % 集合全等才能保证半成品目录 fail closed。
    actual = listOutputArtifacts(outputFolder, manifestFile);
    if ~isequal(sort(listed), sort(actual))
        return;
    end
    for rowIndex = 1:height(manifest)
        artifact = fullfile(outputFolder, strrep( ...
            char(manifest.relativePath(rowIndex)), '/', filesep));
        info = dir(artifact);
        if isempty(info) || info(1).isdir || ...
                info(1).bytes ~= manifest.sizeBytes(rowIndex) || ...
                ~strcmpi(sha256File(artifact), ...
                char(manifest.sha256(rowIndex)))
            return;
        end
    end
catch
    return;
end
committed = true;

end


function paths = listOutputArtifacts(outputFolder, manifestFile)

entries = dir(fullfile(outputFolder, '**', '*'));
entries = entries(~[entries.isdir]);
paths = strings(0, 1);
for entryIndex = 1:numel(entries)
    fullPath = fullfile(entries(entryIndex).folder, ...
        entries(entryIndex).name);
    if strcmp(fullPath, manifestFile)
        continue;
    end
    relative = extractAfter(fullPath, outputFolder);
    relative = strrep(relative, filesep, '/');
    if startsWith(relative, '/')
        relative = extractAfter(relative, '/');
    end
    paths(end+1, 1) = string(relative); %#ok<AGROW>
end

end


function removeOrphanBackups(outputFolder)

[parentFolder, outputName] = fileparts(outputFolder);
backups = dir(fullfile(parentFolder, [outputName '_backup_*']));
for backupIndex = 1:numel(backups)
    if backups(backupIndex).isdir
        rmdir(fullfile(backups(backupIndex).folder, ...
            backups(backupIndex).name), 's');
    end
end

end


function hash = sha256File(filename)

fid = fopen(filename, 'rb');
if fid == -1
    hash = '';
    return;
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
clear cleanup;
digest = java.security.MessageDigest.getInstance('SHA-256');
hashBytes = typecast(digest.digest(bytes), 'uint8');
hash = lower(reshape(dec2hex(hashBytes, 2).', 1, []));

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
