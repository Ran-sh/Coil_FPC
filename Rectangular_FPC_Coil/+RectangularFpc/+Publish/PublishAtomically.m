function varargout = PublishAtomically( ...
    tempOutputFolder, outputFolder, moveFolder)
%RECTANGULAR_FPC_PUBLISH_ATOMICALLY Publish one minute-version safely.
%   The sibling *_publish.lock directory is the commit barrier. Lock
%   ownership/fencing and backup recovery live in dedicated private modules;
%   this function only coordinates the publication transaction.

if nargin >= 1 && ischar(tempOutputFolder) && ...
        strcmp(tempOutputFolder, 'acquire_access')
    if nargin ~= 2
        error('RectangularFPC:InvalidPublishRequest', ...
            'acquire_access requires exactly one output folder.');
    end
    outputFolder = RectangularFpc.Publish.PublishPaths( ...
        'validate_access_target', outputFolder);
    [varargout{1}, ~] = RectangularFpc.Publish.PublishLock( ...
        'acquire', [outputFolder '_publish.lock'], @movefile);
    return;
end

if nargin >= 1 && ischar(tempOutputFolder) && ...
        strcmp(tempOutputFolder, 'verify_committed')
    if nargin ~= 2
        error('RectangularFPC:InvalidPublishRequest', ...
            'verify_committed requires exactly one output folder.');
    end
    varargout{1} = RectangularFpc.Publish.CommitContract(outputFolder);
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
        'The injected mover must be a function handle.');
end

% Pure validation is deliberately complete before onCleanup registration,
% lock creation, marker creation, or any other filesystem mutation.
[tempOutputFolder, outputFolder] = RectangularFpc.Publish.PublishPaths( ...
    'validate', tempOutputFolder, outputFolder);
stagingCleanup = onCleanup(@() removeStagingFolder(tempOutputFolder));
lockFolder = [outputFolder '_publish.lock'];
[lockCleanup, lockToken] = RectangularFpc.Publish.PublishLock( ...
    'acquire', lockFolder, moveFolder); %#ok<ASGLU>

RectangularFpc.Publish.BackupRecovery( ...
    'recover', outputFolder, moveFolder, lockFolder, lockToken);
[stagingCommitted, stagingReason] = ...
    RectangularFpc.Publish.CommitContract(tempOutputFolder);
if ~stagingCommitted
    error('RectangularFPC:AtomicPublishFailed', ...
        'Staged output does not satisfy the commit contract: %s', ...
        stagingReason);
end

transactionToken = RectangularFpc.Publish.PublishLock('new_token');
backupFolder = sprintf('%s_backup_%s', outputFolder, transactionToken);
backupMarker = RectangularFpc.Publish.BackupRecovery( ...
    'marker_path', backupFolder);
hadPriorVersion = isfolder(outputFolder);
priorVersionMoved = false;
newVersionPublished = false;

try
    if hadPriorVersion
        RectangularFpc.Publish.PublishLock( ...
            'assert_owned', lockFolder, lockToken);
        backupMarker = RectangularFpc.Publish.BackupRecovery( ...
            'write_marker', backupFolder, outputFolder, transactionToken);
        RectangularFpc.Publish.PublishLock( ...
            'assert_owned', lockFolder, lockToken);
        [moved, message, moveClean] = RectangularFpc.Publish.PublishLock( ...
            'move', moveFolder, outputFolder, backupFolder, ...
            lockFolder, lockToken);
        priorVersionMoved = moved;
        if ~moveClean
            if ~moved && isfolder(outputFolder) && ~isfolder(backupFolder)
                RectangularFpc.Publish.PublishLock( ...
                    'delete_file', backupMarker, lockFolder, lockToken);
            end
            error('RectangularFPC:AtomicPublishFailed', ...
                'Unable to stage the prior version for replacement: %s', ...
                message);
        end
    elseif isfile(outputFolder)
        error('RectangularFPC:AtomicPublishFailed', ...
            'Formal output path is occupied by a file: %s', outputFolder);
    end

    [moved, message, moveClean] = RectangularFpc.Publish.PublishLock( ...
        'move', moveFolder, tempOutputFolder, outputFolder, ...
        lockFolder, lockToken);
    newVersionPublished = moved;
    if ~moveClean
        error('RectangularFPC:AtomicPublishFailed', ...
            'Unable to publish the staged version: %s', message);
    end
    [publishedCommitted, publishedReason] = ...
        RectangularFpc.Publish.CommitContract(outputFolder);
    if ~publishedCommitted
        error('RectangularFPC:AtomicPublishFailed', ...
            'Published output failed the commit contract: %s', ...
            publishedReason);
    end
catch publishError
    rollbackFailedPublish( ...
        publishError, outputFolder, backupFolder, backupMarker, ...
        priorVersionMoved, newVersionPublished, moveFolder, ...
        lockFolder, lockToken);
end

cleanupPriorBackup(backupFolder, backupMarker, lockFolder, lockToken);
clear lockCleanup;
clear stagingCleanup;

end


function rollbackFailedPublish( ...
    publishError, outputFolder, backupFolder, backupMarker, ...
    priorVersionMoved, newVersionPublished, moveFolder, lockFolder, lockToken)

cleanupFailure = '';
if newVersionPublished && isfolder(outputFolder)
    try
        RectangularFpc.Publish.PublishLock( ...
            'remove_folder', outputFolder, lockFolder, lockToken);
    catch cleanupError
        cleanupFailure = cleanupError.message;
    end
end

if priorVersionMoved && isfolder(backupFolder)
    if isempty(cleanupFailure)
        [restored, restoreMessage] = RectangularFpc.Publish.PublishLock( ...
            'move', moveFolder, backupFolder, outputFolder, ...
            lockFolder, lockToken);
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
    RectangularFpc.Publish.PublishLock( ...
        'delete_file', backupMarker, lockFolder, lockToken);
elseif ~isempty(cleanupFailure)
    error('RectangularFPC:AtomicRollbackFailed', ...
        ['Publish failed (%s), and the partial formal output could ', ...
        'not be removed: %s'], publishError.message, cleanupFailure);
elseif isfile(backupMarker)
    RectangularFpc.Publish.PublishLock( ...
        'delete_file', backupMarker, lockFolder, lockToken);
end
rethrow(publishError);

end


function cleanupPriorBackup( ...
    backupFolder, backupMarker, lockFolder, lockToken)

if ~isfolder(backupFolder)
    return;
end
try
    RectangularFpc.Publish.PublishLock( ...
        'remove_folder', backupFolder, lockFolder, lockToken);
    RectangularFpc.Publish.PublishLock( ...
        'delete_file', backupMarker, lockFolder, lockToken);
catch cleanupError
    if strcmp(cleanupError.identifier, 'RectangularFPC:ConcurrentPublish')
        rethrow(cleanupError);
    end
    warning('RectangularFPC:BackupCleanupFailed', ...
        'Published successfully, but backup cleanup failed: %s', ...
        cleanupError.message);
end

end


function removeStagingFolder(tempOutputFolder)

if isfolder(tempOutputFolder)
    rmdir(tempOutputFolder, 's');
end

end
