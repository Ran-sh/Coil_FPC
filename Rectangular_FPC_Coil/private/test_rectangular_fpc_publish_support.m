function support = test_rectangular_fpc_publish_support
% Shared fixtures and fault injectors for atomic publication tests.
support = struct();
support.makeFixture = @makeFixture;
support.controlledMove = @controlledMove;
support.ambiguousPhaseMove = @ambiguousPhaseMove;
support.ambiguousRollbackMove = @ambiguousRollbackMove;
support.ambiguousOwnerSwapMove = @ambiguousOwnerSwapMove;
support.reportMoveFailureAfterSuccess = @reportMoveFailureAfterSuccess;
support.corruptAfterPublicationMove = @corruptAfterPublicationMove;
support.replaceOwnerAtDestructiveMove = @replaceOwnerAtDestructiveMove;
support.stealTombstoneRace = @stealTombstoneRace;
support.replaceOwnerDuringSwap = @replaceOwnerDuringSwap;
support.localHostName = @localHostName;
support.observingMove = @observingMove;
support.appendObservation = @appendObservation;
support.writeLockOwner = @writeLockOwner;
support.writeOwnerRecord = @writeOwnerRecord;
support.writeStaleOwnerRecord = @writeStaleOwnerRecord;
support.verifyPublishBlockedDuringRead = @verifyPublishBlockedDuringRead;
support.changeDirectoryAndFail = @changeDirectoryAndFail;
support.writeMarker = @writeMarker;
support.writeCommitEvidence = @writeCommitEvidence;
support.rewriteCommitManifest = @rewriteCommitManifest;
support.writeText = @writeText;
support.fixtureArtifactRole = @fixtureArtifactRole;
support.legitimateBackupPath = @legitimateBackupPath;
support.ensureFixtureFolder = @ensureFixtureFolder;
support.unknownBackupLikePath = @unknownBackupLikePath;
support.writeBackupTransactionFixture = @writeBackupTransactionFixture;
support.sha256File = @sha256File;
support.removeFixture = @removeFixture;
support.restoreFolderAndRemove = @restoreFolderAndRemove;
end
function paths = makeFixture()
paths.root = tempname;
paths.output = fullfile(paths.root, 'design_20000101_0000');
paths.staging = fullfile(paths.root, 'staging');
paths.backupPattern = [paths.output '_backup_*'];
mkdir(paths.output);
mkdir(paths.staging);
writeMarker(fullfile(paths.output, 'old_marker.txt'));
writeMarker(fullfile(paths.staging, 'new_marker.txt'));
writeCommitEvidence(paths.output);
writeCommitEvidence(paths.staging);
end

function [moved, message] = controlledMove( ...
    source, destination, paths, failPublish, failRestore)
isPublish = strcmp(source, paths.staging) && strcmp(destination, paths.output);
isRestore = startsWith(source, [paths.output '_backup_']) && ...
    strcmp(destination, paths.output);
if (failPublish && isPublish) || (failRestore && isRestore)
    moved = false;
    message = 'injected move failure';
else
    [moved, message] = movefile(source, destination);
end
end

function [moved, message] = ambiguousPhaseMove( ...
    source, destination, paths, phase, mode)
isPrior = strcmp(source, paths.output) && ...
    startsWith(destination, [paths.output '_backup_']);
isPublish = strcmp(source, paths.staging) && strcmp(destination, paths.output);
[moved, message] = movefile(source, destination);
if (strcmp(phase, 'prior') && isPrior) || ...
        (strcmp(phase, 'publish') && isPublish)
    [moved, message] = reportMoveFailureAfterSuccess(mode);
end
end

function [moved, message] = ambiguousRollbackMove( ...
    source, destination, paths, mode)
isPublish = strcmp(source, paths.staging) && strcmp(destination, paths.output);
isRestore = startsWith(source, [paths.output '_backup_']) && ...
    strcmp(destination, paths.output);
if isPublish
    moved = false;
    message = 'injected publish failure';
    return;
end
[moved, message] = movefile(source, destination);
if isRestore
    [moved, message] = reportMoveFailureAfterSuccess(mode);
end
end

function [moved, message] = ambiguousOwnerSwapMove( ...
    source, destination, lockFolder, mode)
[moved, message] = movefile(source, destination);
ownerFile = fullfile(lockFolder, 'owner.txt');
if strcmp(destination, ownerFile) && contains(source, 'owner.txt.candidate_')
    [moved, message] = reportMoveFailureAfterSuccess(mode);
end
end

function [moved, message] = reportMoveFailureAfterSuccess(mode)
if strcmp(mode, 'throw')
    error('Test:MoveFailedAfterSuccess', ...
        'injected failure after the filesystem move completed');
end
moved = false;
message = 'mover returned false after the filesystem move completed';
end

function [moved, message] = corruptAfterPublicationMove( ...
    source, destination, paths)
[moved, message] = movefile(source, destination);
if moved && strcmp(source, paths.staging) && strcmp(destination, paths.output)
    delete(fullfile(destination, 'dxf', '00_board_outline.dxf'));
end
end

function [moved, message] = replaceOwnerAtDestructiveMove( ...
    source, destination, paths)
isPriorVersionMove = strcmp(source, paths.output) && ...
    startsWith(destination, [paths.output '_backup_']);
if isPriorVersionMove
    lockFolder = [paths.output '_publish.lock'];
    writeOwnerRecord(lockFolder, localHostName(0), matlabProcessID, ...
        repmat('e', 1, 32));
    moved = false;
    message = 'ownership replaced before destructive move';
    return;
end
[moved, message] = movefile(source, destination);
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
    fprintf(fid, 'pid=%d\nhost=sim-host-b\ntoken=%s\n', ...
        matlabProcessID, repmat('c', 1, 32));
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
if strcmp(destination, ownerFile) && contains(source, 'owner.txt.candidate_')
    fid = fopen(ownerFile, 'w');
    freshCleanup = onCleanup(@() fclose(fid));
    fprintf(fid, 'pid=1\nhost=sim-host-a\ntoken=%s\n', repmat('f', 1, 32));
    fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
    clear freshCleanup;
    delete(source);
    moved = true;
    message = '';
else
    [moved, message] = movefile(source, destination);
end
end

function host = localHostName(~)
% 带 1 个输入参数（避免被 functiontests 当作测试函数注册）。
host = lower(strtrim(getenv('COMPUTERNAME')));
if isempty(host)
    host = lower(strtrim(getenv('HOSTNAME')));
end
if isempty(host)
    try
        host = lower(strtrim(char(java.net.InetAddress.getLocalHost().getHostName())));
    catch
        host = '';
    end
end
if isempty(host)
    error('RectangularFPC:TestHostUnavailable', ...
        'Unable to determine a non-empty host identity for the test fixture.');
end
end

function [moved, message] = observingMove( ...
    source, destination, paths, observationFile)
lockFolder = [paths.output '_publish.lock'];
if strcmp(source, paths.output) && startsWith(destination, ...
        [paths.output '_backup_']) && isfolder(lockFolder)
    appendObservation(observationFile, 'PRIOR_MOVE_LOCKED');
elseif strcmp(source, paths.staging) && strcmp(destination, paths.output) && ...
        ~isfolder(paths.output) && isfolder(lockFolder)
    appendObservation(observationFile, 'PUBLICATION_GAP_LOCKED');
end
[moved, message] = movefile(source, destination);
end

function appendObservation(filename, observation)
fid = fopen(filename, 'a');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', observation);
clear cleanup;
end

function writeLockOwner(lockFolder, host, pid)
writeOwnerRecord(lockFolder, host, pid, repmat('d', 1, 32));
end

function writeOwnerRecord(lockFolder, host, pid, token)
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=%d\n', pid);
fprintf(fid, 'host=%s\n', host);
fprintf(fid, 'token=%s\n', token);
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear cleanup;
end

function writeStaleOwnerRecord(lockFolder, hexDigit)
writeOwnerRecord(lockFolder, localHostName(0), 2147483647, ...
    repmat(hexDigit, 1, 32));
end

function marker = verifyPublishBlockedDuringRead(testCase, folder, paths)
verifyTrue(testCase, isfolder([paths.output '_publish.lock']));
[~, outputName] = fileparts(paths.output);
outputAlias = fullfile(paths.root, '.', outputName);
verifyError(testCase, @() rectangular_fpc_publish_atomically( ...
    paths.staging, outputAlias), 'RectangularFPC:ConcurrentPublish');
verifyTrue(testCase, isfolder(folder));
marker = erase(fileread(fullfile(folder, 'old_marker.txt')), 'marker');
marker = ['old_' marker 'marker'];
end

function changeDirectoryAndFail(folder, destination)
cd(destination);
error('Test:InjectedReaderFailure', ...
    'injected reader callback failure for %s', char(folder));
end

function writeMarker(filename)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'marker');
clear cleanup;
end

function writeCommitEvidence(outputFolder)
statusFile = fullfile(outputFolder, 'generation_status.txt');
fid = fopen(statusFile, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'SchemaVersion: 2\n');
fprintf(fid, 'Status: SUCCESS\n');
fprintf(fid, 'LayerCount: 2\n');
fprintf(fid, 'PreviewEnabled: 0\n');
fprintf(fid, 'PublicationId: %s\n', repmat('9', 1, 32));
clear cleanup;

dxfFolder = fullfile(outputFolder, 'dxf');
layerFolder = fullfile(dxfFolder, 'L1');
reportsFolder = fullfile(outputFolder, 'reports');
ensureFixtureFolder(dxfFolder);
ensureFixtureFolder(layerFolder);
ensureFixtureFolder(fullfile(dxfFolder, 'L2'));
ensureFixtureFolder(reportsFolder);
artifactPaths = { ...
    'dxf/00_board_outline.dxf', ...
    'dxf/00_drill_map.dxf', ...
    'dxf/L1/01_copper_L1.dxf', ...
    'dxf/L1/01_copper_physical_L1.dxf', ...
    'dxf/L1/01_antipad_keepout_L1.dxf', ...
    'dxf/L2/02_copper_L2.dxf', ...
    'dxf/L2/02_copper_physical_L2.dxf', ...
    'dxf/L2/02_antipad_keepout_L2.dxf', ...
    'reports/01_pad_via_coordinates.csv', ...
    'reports/02_layer_mapping.csv', ...
    'reports/03_design_summary.txt', ...
    'reports/04_turn_scan.csv', ...
    'reports/05_validation_report.txt', ...
    'reports/06_manufacturing_check.csv', ...
    'reports/07_fabrication_notes.txt'};
for artifactIndex = 1:numel(artifactPaths)
    writeMarker(fullfile(outputFolder, strrep( ...
        artifactPaths{artifactIndex}, '/', filesep)));
end
rewriteCommitManifest(outputFolder, cell(0, 2));
end

function rewriteCommitManifest(outputFolder, roleOverrides)
manifestFile = fullfile(outputFolder, 'reports', '08_file_manifest.csv');
files = dir(fullfile(outputFolder, '**', '*'));
files = files(~[files.isdir]);
relativePaths = strings(0, 1);
absolutePaths = strings(0, 1);
for fileIndex = 1:numel(files)
    absolutePath = fullfile(files(fileIndex).folder, files(fileIndex).name);
    if strcmp(absolutePath, manifestFile)
        continue;
    end
    relativePath = extractAfter(absolutePath, [outputFolder filesep]);
    relativePaths(end+1, 1) = string(strrep(relativePath, filesep, '/')); %#ok<AGROW>
    absolutePaths(end+1, 1) = string(absolutePath); %#ok<AGROW>
end
[relativePaths, order] = sort(relativePaths);
absolutePaths = absolutePaths(order);

fid = fopen(manifestFile, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
for fileIndex = 1:numel(relativePaths)
    relativePath = char(relativePaths(fileIndex));
    absolutePath = char(absolutePaths(fileIndex));
    info = dir(absolutePath);
    role = fixtureArtifactRole(relativePath);
    if ~isempty(roleOverrides)
        overrideIndex = find(strcmp(roleOverrides(:, 1), relativePath), 1);
        if ~isempty(overrideIndex)
            role = roleOverrides{overrideIndex, 2};
        end
    end
    fprintf(fid, '%s,%s,%d,%s\n', relativePath, role, ...
        info.bytes, sha256File(absolutePath));
end
clear cleanup;
end

function writeText(filename, value)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', value);
clear cleanup;
end

function role = fixtureArtifactRole(relativePath)
if strcmp(relativePath, 'dxf/00_board_outline.dxf')
    role = 'board_outline';
elseif strcmp(relativePath, 'dxf/00_drill_map.dxf')
    role = 'drill_reference';
elseif contains(relativePath, '_copper_physical_')
    role = 'physical_copper';
elseif contains(relativePath, '_antipad_keepout_')
    role = 'antipad_keepout';
elseif contains(relativePath, '_copper_L')
    role = 'copper_centerline';
elseif strcmp(relativePath, 'reports/01_pad_via_coordinates.csv')
    role = 'pad_via_coordinates';
elseif strcmp(relativePath, 'reports/02_layer_mapping.csv')
    role = 'layer_mapping';
elseif strcmp(relativePath, 'reports/03_design_summary.txt')
    role = 'design_summary';
elseif strcmp(relativePath, 'reports/04_turn_scan.csv')
    role = 'turn_scan';
elseif strcmp(relativePath, 'reports/05_validation_report.txt')
    role = 'validation_report';
elseif strcmp(relativePath, 'reports/06_manufacturing_check.csv')
    role = 'manufacturing_check';
elseif strcmp(relativePath, 'reports/07_fabrication_notes.txt')
    role = 'fabrication_notes';
elseif strcmp(relativePath, 'generation_status.txt')
    role = 'generation_status';
else
    role = 'artifact';
end
end

function backupFolder = legitimateBackupPath(paths, hexDigit)
% Publisher tokens are 32 lowercase hexadecimal characters (UUID sans '-').
backupFolder = [paths.output '_backup_' repmat(hexDigit, 1, 32)];
end

function ensureFixtureFolder(folder)
if ~isfolder(folder)
    mkdir(folder);
end
end

function backupFolder = unknownBackupLikePath(paths)
backupFolder = [paths.output '_backup_keep'];
end

function writeBackupTransactionFixture( ...
    backupFolder, outputFolder, transactionId)
markerFile = [backupFolder '.transaction'];
target = char(java.io.File(outputFolder).getCanonicalPath());
target = strrep(strtrim(target), '/', filesep);
if ispc
    target = lower(target);
end
fid = fopen(markerFile, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'SchemaVersion: 1\n');
fprintf(fid, 'Target: %s\n', target);
fprintf(fid, 'TransactionId: %s\n', transactionId);
fprintf(fid, 'Payload: prior_committed_output\n');
clear cleanup;
end

function hash = sha256File(filename)
fid = fopen(filename, 'rb');
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
clear cleanup;
digest = java.security.MessageDigest.getInstance('SHA-256');
hashBytes = typecast(digest.digest(bytes), 'uint8');
hash = lower(reshape(dec2hex(hashBytes, 2).', 1, []));
end

function removeFixture(root)
if isfolder(root)
    rmdir(root, 's');
end
end

function restoreFolderAndRemove(folder, root)
cd(folder);
removeFixture(root);
end
