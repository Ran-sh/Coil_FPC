function circular_fpc_publish_atomically( ...
    stagingFolder, outputFolder, moveFolder)
%CIRCULAR_FPC_PUBLISH_ATOMICALLY Commit one verified output tree once.
%   A sibling *_publish.lock directory serializes writers targeting the
%   same design. Existing formal output is never replaced. The optional
%   MOVEFOLDER handle supports deterministic failure-path tests.

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
lockCleanup = acquirePublishLock(lockFolder); %#ok<NASGU>

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

function cleanup = acquirePublishLock(lockFolder)
[created, message, messageId] = mkdir(lockFolder);
if ~created || strcmp(messageId, 'MATLAB:MKDIR:DirectoryExists')
    error('CircularFPC:ConcurrentPublish', ...
        'Another process is publishing this output: %s (%s)', ...
        lockFolder, message);
end

token = uniqueToken();
try
    writeLockOwner(lockFolder, token);
catch ownerError
    removeFolder(lockFolder);
    rethrow(ownerError);
end
cleanup = onCleanup(@() releasePublishLock(lockFolder, token));
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

function token = uniqueToken()
token = char(java.util.UUID.randomUUID());
token = strrep(token, '-', '');
end
