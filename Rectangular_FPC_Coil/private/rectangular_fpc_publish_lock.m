function varargout = rectangular_fpc_publish_lock(action, varargin)
%RECTANGULAR_FPC_PUBLISH_LOCK Publication ownership and fenced mutations.

switch action
    case 'acquire'
        [varargout{1}, varargout{2}] = acquirePublishLock( ...
            varargin{1}, varargin{2});
    case 'assert_owned'
        assertFenceOwned(varargin{1}, varargin{2});
    case 'move'
        [varargout{1}, varargout{2}, varargout{3}] = fencedMove( ...
            varargin{1}, varargin{2}, varargin{3}, varargin{4}, varargin{5});
    case 'remove_folder'
        fencedRemoveFolder(varargin{1}, varargin{2}, varargin{3});
    case 'delete_file'
        fencedDeleteFileIfPresent(varargin{1}, varargin{2}, varargin{3});
    case 'new_token'
        varargout{1} = uniqueToken();
    otherwise
        error('RectangularFPC:InvalidPublishRequest', ...
            'Unknown publish-lock operation: %s.', action);
end

end


function [cleanup, token] = acquirePublishLock(lockFolder, moveFolder)
% Candidate lock/claim directories receive complete owner records before a
% no-replace rename makes them visible at the fixed coordination path.
token = uniqueToken();
if isfolder(lockFolder)
    ownerTextBefore = readPublishLockOwnerText(lockFolder);
    ownerBefore = readPublishLockOwner(lockFolder);
    if ~ownerBefore.valid || ~isStaleOwner(ownerBefore)
        error('RectangularFPC:ConcurrentPublish', ...
            'Another or malformed publisher owns the lock: %s', lockFolder);
    end
    claimDir = fullfile(lockFolder, 'reclaim.claim');
    [claimed, claimToken] = acquireReclaimClaim(claimDir, moveFolder);
    if ~claimed
        error('RectangularFPC:ConcurrentPublish', ...
            'Another process is reclaiming the stale lock at %s', lockFolder);
    end
    claimCleanup = onCleanup(@() releaseReclaimClaim(claimDir, claimToken));
    ownerChanged = ~strcmp(readPublishLockOwnerText(lockFolder), ownerTextBefore) || ...
        ~strcmp(readPublishLockToken(claimDir), claimToken);
    if ~ownerChanged
        replaceOwnerAtomically(lockFolder, token, moveFolder);
        ownerChanged = ~strcmp(readPublishLockToken(lockFolder), token);
    end
    clear claimCleanup;
    if ownerChanged
        error('RectangularFPC:ConcurrentPublish', ...
            ['Publish lock at %s changed identity during stale claim; ', ...
            'another writer now owns it.'], lockFolder);
    end
elseif isfile(lockFolder)
    error('RectangularFPC:ConcurrentPublish', ...
        'Publish lock path is occupied by a file: %s', lockFolder);
else
    [claimed, message] = claimOwnedDirectoryNoReplace(lockFolder, token);
    if ~claimed
        error('RectangularFPC:ConcurrentPublish', ...
            'Another process claimed the publish lock %s: %s', ...
            lockFolder, message);
    end
end
cleanup = onCleanup(@() releasePublishLock(lockFolder, token));

end


function [ok, claimToken] = acquireReclaimClaim(claimDir, moveFolder)

claimToken = uniqueToken();
if isfolder(claimDir)
    priorClaim = readPublishLockOwner(claimDir);
    if ~priorClaim.valid || ~isStaleOwner(priorClaim)
        ok = false;
        claimToken = '';
        return;
    end
    tombstone = sprintf('%s.tomb_%s', claimDir, uniqueToken());
    [moved, ~] = tryMove(moveFolder, claimDir, tombstone);
    if ~moved
        ok = false;
        claimToken = '';
        return;
    end
    movedClaim = readPublishLockOwner(tombstone);
    if ~movedClaim.valid || ~strcmp(movedClaim.token, priorClaim.token)
        ok = false;
        claimToken = '';
        return;
    end
    rmdir(tombstone, 's');
elseif isfile(claimDir)
    ok = false;
    claimToken = '';
    return;
end
[ok, ~] = claimOwnedDirectoryNoReplace(claimDir, claimToken);
if ~ok
    claimToken = '';
end

end


function [claimed, message] = claimOwnedDirectoryNoReplace(targetDir, token)

candidateDir = sprintf('%s.candidate_%s', targetDir, token);
[created, message, messageId] = mkdir(candidateDir);
if ~created || strcmp(messageId, 'MATLAB:MKDIR:DirectoryExists')
    claimed = false;
    return;
end
candidateCleanup = onCleanup(@() removeCandidateDirectory(candidateDir));
writePublishLockOwner(candidateDir, token);
[claimed, message] = moveDirectoryNoReplace(candidateDir, targetDir);
if claimed && ~strcmp(readPublishLockToken(targetDir), token)
    claimed = false;
    message = 'claimed directory owner did not match the candidate token';
end
clear candidateCleanup;

end


function [moved, message] = moveDirectoryNoReplace(sourceDir, destinationDir)

moved = false;
message = '';
try
    if ispc
        % Directory.Move is a same-volume rename and refuses an existing
        % destination; it never merges into or replaces the fixed lock.
        System.IO.Directory.Move(sourceDir, destinationDir);
    else
        emptyParts = javaArray('java.lang.String', 0);
        sourcePath = java.nio.file.Paths.get(sourceDir, emptyParts);
        destinationPath = java.nio.file.Paths.get(destinationDir, emptyParts);
        % Deliberately pass no CopyOption. In particular, do not pass
        % ATOMIC_MOVE (whose existing-target semantics are provider-specific)
        % or REPLACE_EXISTING. Java's default contract fails if target exists.
        noReplaceOptions = javaArray('java.nio.file.CopyOption', 0);
        java.nio.file.Files.move(sourcePath, destinationPath, noReplaceOptions);
    end
    moved = true;
catch moveError
    message = moveError.message;
end

end


function removeCandidateDirectory(candidateDir)

if isfolder(candidateDir)
    rmdir(candidateDir, 's');
end

end


function releaseReclaimClaim(claimDir, token)

if isfolder(claimDir) && strcmp(readPublishLockToken(claimDir), token)
    rmdir(claimDir, 's');
end

end


function replaceOwnerAtomically(lockFolder, token, moveFolder)

pendingOwner = fullfile(lockFolder, ['owner.txt.candidate_' token]);
fid = fopen(pendingOwner, 'w', 'n', 'US-ASCII');
if fid == -1
    error('RectangularFPC:ExportWriteFailed', ...
        'Unable to create publish-lock owner swap file: %s', pendingOwner);
end
swapCleanup = onCleanup(@() fclose(fid));
writeOwnerFields(fid, token);
clear swapCleanup;
[replaced, replaceMessage] = tryMove( ...
    moveFolder, pendingOwner, fullfile(lockFolder, 'owner.txt'));
if ~replaced && strcmp(readPublishLockToken(lockFolder), token)
    replaced = true;
end
if ~replaced
    if isfile(pendingOwner)
        delete(pendingOwner);
    end
    error('RectangularFPC:ConcurrentPublish', ...
        'Unable to swap publish-lock owner at %s: %s', ...
        lockFolder, replaceMessage);
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
writeOwnerFields(fid, token);
clear cleanup;

end


function writeOwnerFields(fid, token)

fprintf(fid, 'pid=%d\n', matlabProcessID);
fprintf(fid, 'host=%s\n', localHostIdentity());
fprintf(fid, 'token=%s\n', token);
fprintf(fid, 'created=%s\n', char(datetime('now', ...
    'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX')));

end


function token = readPublishLockToken(lockFolder)

owner = readPublishLockOwner(lockFolder);
token = owner.token;

end


function text = readPublishLockOwnerText(lockFolder)

text = '';
ownerFile = fullfile(lockFolder, 'owner.txt');
if isfile(ownerFile)
    text = fileread(ownerFile);
end

end


function owner = readPublishLockOwner(lockFolder)

owner = struct('valid', false, 'pid', NaN, 'host', '', ...
    'token', '', 'created', NaT);
ownerFile = fullfile(lockFolder, 'owner.txt');
if ~isfile(ownerFile)
    return;
end
text = fileread(ownerFile);
pidMatch = regexp(text, '(?m)^pid=(\d+)$', 'tokens');
hostMatch = regexp(text, '(?m)^host=([^\r\n]+)$', 'tokens');
tokenMatch = regexp(text, '(?m)^token=([0-9a-fA-F]{32})$', 'tokens');
createdMatch = regexp(text, '(?m)^created=([^\r\n]+)$', 'tokens');
if numel(pidMatch) ~= 1 || numel(hostMatch) ~= 1 || ...
        numel(tokenMatch) ~= 1 || numel(createdMatch) ~= 1
    return;
end
pid = str2double(pidMatch{1}{1});
host = lower(strtrim(hostMatch{1}{1}));
try
    created = datetime(createdMatch{1}{1}, ...
        'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX', ...
        'TimeZone', 'UTC');
catch
    return;
end
if ~isfinite(pid) || pid < 1 || pid ~= floor(pid) || ...
        isempty(host) || isnat(created)
    return;
end
owner = struct('valid', true, 'pid', pid, 'host', host, ...
    'token', lower(tokenMatch{1}{1}), 'created', created);

end


function stale = isStaleOwner(owner)

stale = owner.valid && strcmpi(owner.host, localHostIdentity()) && ...
    ~isProcessAlive(owner.pid);

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


function [moved, message, clean] = fencedMove( ...
    moveFolder, sourceFolder, destinationFolder, lockFolder, lockToken)

assertFenceOwned(lockFolder, lockToken);
[moved, message, clean] = tryMove( ...
    moveFolder, sourceFolder, destinationFolder);
assertFenceOwned(lockFolder, lockToken);

end


function fencedRemoveFolder(folder, lockFolder, lockToken)

assertFenceOwned(lockFolder, lockToken);
rmdir(folder, 's');
assertFenceOwned(lockFolder, lockToken);

end


function fencedDeleteFileIfPresent(filename, lockFolder, lockToken)

if ~isfile(filename)
    return;
end
assertFenceOwned(lockFolder, lockToken);
delete(filename);
assertFenceOwned(lockFolder, lockToken);

end


function assertFenceOwned(lockFolder, lockToken)

if ~isfolder(lockFolder) || ...
        ~strcmp(readPublishLockToken(lockFolder), lockToken)
    error('RectangularFPC:ConcurrentPublish', ...
        ['Publication fencing token no longer owns %s; no further ', ...
        'filesystem mutation is permitted.'], lockFolder);
end

end


function [moved, message, clean] = tryMove( ...
    moveFolder, sourceFolder, destinationFolder)

reportedMoved = false;
try
    [reportedMoved, message] = moveFolder(sourceFolder, destinationFolder);
catch moveError
    message = moveError.message;
end
sourcePresent = pathExists(sourceFolder);
destinationPresent = pathExists(destinationFolder);
moved = ~sourcePresent && destinationPresent;
clean = logical(reportedMoved) && moved;
if clean
    return;
end
if moved
    message = appendMoveMessage(message, ...
        'move completed on disk but the mover reported failure');
elseif reportedMoved
    message = appendMoveMessage(message, ...
        'mover reported success but the move postcondition is false');
elseif isempty(message)
    message = 'unspecified move failure';
end

end


function present = pathExists(path)

present = isfolder(path) || isfile(path);

end


function message = appendMoveMessage(message, suffix)

if isempty(message)
    message = suffix;
else
    message = sprintf('%s (%s)', message, suffix);
end

end


function token = uniqueToken()

token = char(java.util.UUID.randomUUID());
token = strrep(token, '-', '');

end
