function varargout = rectangular_fpc_backup_recovery(action, varargin)
%RECTANGULAR_FPC_BACKUP_RECOVERY Target-bound publication backup protocol.

switch action
    case 'recover'
        recoverOrphanBackup( ...
            varargin{1}, varargin{2}, varargin{3}, varargin{4});
    case 'write_marker'
        markerFile = backupTransactionMarkerPath(varargin{1});
        writeBackupTransactionMarker( ...
            markerFile, varargin{2}, varargin{3});
        varargout{1} = markerFile;
    case 'marker_path'
        varargout{1} = backupTransactionMarkerPath(varargin{1});
    otherwise
        error('RectangularFPC:InvalidPublishRequest', ...
            'Unknown backup-recovery operation: %s.', action);
end

end


function recoverOrphanBackup( ...
    outputFolder, moveFolder, lockFolder, lockToken)

state = inspectBackupState(outputFolder);
if isfolder(outputFolder)
    [committed, reason] = rectangular_fpc_commit_contract(outputFolder);
    if ~committed
        error('RectangularFPC:AtomicRecoveryFailed', ...
            ['Existing formal-output target is not a committed ', ...
             'publication and was preserved without replacement: %s (%s)'], ...
            outputFolder, reason);
    end
    if ~isempty(state.validFolders)
        for backupIndex = 1:numel(state.validFolders)
            rectangular_fpc_publish_lock('remove_folder', ...
                state.validFolders{backupIndex}, lockFolder, lockToken);
            rectangular_fpc_publish_lock('delete_file', ...
                state.validMarkers{backupIndex}, lockFolder, lockToken);
        end
    end
    return;
end
if isfile(outputFolder)
    error('RectangularFPC:AtomicPublishFailed', ...
        'Formal output path is occupied by a file: %s', outputFolder);
end

if isempty(state.validFolders)
    if state.hasBackupLikeDirectory
        error('RectangularFPC:AtomicRecoveryFailed', ...
            ['No target-bound publication backup can be trusted for ', ...
            'missing output %s; unknown backup-like directories were ', ...
            'preserved.'], outputFolder);
    end
    return;
end
if numel(state.validFolders) ~= 1
    error('RectangularFPC:AtomicRecoveryFailed', ...
        ['Multiple valid recovery backups exist for missing output %s; ', ...
        'all were preserved for manual resolution.'], outputFolder);
end

backupFolder = state.validFolders{1};
[backupCommitted, backupReason] = ...
    rectangular_fpc_commit_contract(backupFolder);
if ~backupCommitted
    error('RectangularFPC:AtomicRecoveryFailed', ...
        'Recovery backup is not committed: %s (%s)', ...
        backupFolder, backupReason);
end
[restored, message, moveClean] = rectangular_fpc_publish_lock( ...
    'move', moveFolder, backupFolder, outputFolder, lockFolder, lockToken);
if restored
    rectangular_fpc_publish_lock( ...
        'delete_file', state.validMarkers{1}, lockFolder, lockToken);
end
if ~moveClean
    error('RectangularFPC:AtomicRecoveryFailed', ...
        'Unable to recover interrupted publication from %s: %s', ...
        backupFolder, message);
end

end


function state = inspectBackupState(outputFolder)

[parentFolder, outputName] = fileparts(outputFolder);
entries = dir(fullfile(parentFolder, [outputName '_backup_*']));
validFolders = cell(0, 1);
validMarkers = cell(0, 1);
hasBackupLikeDirectory = false;
nameExpression = ['^' regexptranslate('escape', outputName) ...
    '_backup_([0-9a-fA-F]{32})$'];
for entryIndex = 1:numel(entries)
    entry = entries(entryIndex);
    if ~entry.isdir
        continue;
    end
    hasBackupLikeDirectory = true;
    tokenMatch = regexp(entry.name, nameExpression, 'tokens', 'once');
    if isempty(tokenMatch)
        continue;
    end
    backupFolder = fullfile(entry.folder, entry.name);
    markerFile = backupTransactionMarkerPath(backupFolder);
    markerValid = validBackupTransactionMarker( ...
        markerFile, outputFolder, tokenMatch{1});
    backupCommitted = false;
    if markerValid
        backupCommitted = rectangular_fpc_commit_contract(backupFolder);
    end
    if markerValid && backupCommitted
        validFolders{end+1, 1} = backupFolder; %#ok<AGROW>
        validMarkers{end+1, 1} = markerFile; %#ok<AGROW>
    end
end
state = struct( ...
    'validFolders', {validFolders}, ...
    'validMarkers', {validMarkers}, ...
    'hasBackupLikeDirectory', hasBackupLikeDirectory);

end


function markerFile = backupTransactionMarkerPath(backupFolder)

markerFile = [backupFolder '.transaction'];

end


function writeBackupTransactionMarker(markerFile, outputFolder, token)

if isfile(markerFile) || isfolder(markerFile)
    error('RectangularFPC:AtomicPublishFailed', ...
        'Backup transaction marker path is occupied: %s', markerFile);
end
fid = fopen(markerFile, 'w', 'n', 'UTF-8');
if fid == -1
    error('RectangularFPC:ExportWriteFailed', ...
        'Unable to create backup transaction marker: %s', markerFile);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'SchemaVersion: 1\n');
fprintf(fid, 'Target: %s\n', canonicalTargetPath(outputFolder));
fprintf(fid, 'TransactionId: %s\n', lower(token));
fprintf(fid, 'Payload: prior_committed_output\n');
clear cleanup;

end


function valid = validBackupTransactionMarker( ...
    markerFile, outputFolder, expectedToken)

valid = false;
if ~isfile(markerFile)
    return;
end
try
    text = fileread(markerFile);
    schema = markerField(text, 'SchemaVersion');
    target = markerField(text, 'Target');
    transactionId = markerField(text, 'TransactionId');
    payload = markerField(text, 'Payload');
    valid = strcmp(schema, '1') && ...
        strcmp(normalizeBoundPath(target), canonicalTargetPath(outputFolder)) && ...
        strcmpi(transactionId, expectedToken) && ...
        ~isempty(regexp(transactionId, '^[0-9a-fA-F]{32}$', 'once')) && ...
        strcmp(payload, 'prior_committed_output');
catch
    valid = false;
end

end


function value = markerField(text, fieldName)

matches = regexp(text, ['(?m)^' fieldName ':\s*([^\r\n]+?)\s*$'], ...
    'tokens');
if numel(matches) ~= 1
    error('RectangularFPC:InvalidBackupMarker', ...
        'Backup marker field %s must occur exactly once.', fieldName);
end
value = strtrim(matches{1}{1});

end


function path = canonicalTargetPath(path)

path = rectangular_fpc_publish_paths('normalize', path);
path = normalizeBoundPath(path);

end


function path = normalizeBoundPath(path)

path = strrep(strtrim(char(path)), '/', filesep);
if ispc
    path = lower(path);
end

end
