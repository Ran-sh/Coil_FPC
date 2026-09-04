function varargout = rectangular_fpc_export_io(operation, varargin)
%RECTANGULAR_FPC_EXPORT_IO Shared filesystem and manifest primitives.

switch operation
    case 'canonical_absolute_folder'
        varargout{1} = canonicalAbsoluteFolder(varargin{:});
    case 'prepare_temp_folder'
        prepareFormalTempFolder(varargin{:});
    case 'remove_staging_folder'
        removeStagingFolder(varargin{:});
    case 'copy_required_file'
        copyRequiredFile(varargin{:});
    case 'write_file_manifest'
        writeFileManifest(varargin{:});
    case 'verify_file_manifest'
        verifyFileManifest(varargin{:});
    case 'csv_text'
        varargout{1} = csvText(varargin{:});
    case 'open_ascii_file'
        varargout{1} = openAsciiFile(varargin{:});
    case 'open_utf8_file'
        varargout{1} = openUtf8File(varargin{:});
    case 'unique_token'
        varargout{1} = uniqueToken();
    otherwise
        error('RectangularFPC:UnknownExportOperation', ...
            'Unknown export I/O operation: %s', operation);
end

end

%% =========================================================
function folder = canonicalAbsoluteFolder(folder)

if isstring(folder) && isscalar(folder)
    folder = char(folder);
end
if ~ischar(folder) || isempty(folder)
    error('RectangularFPC:InvalidExportRequest', ...
        'outputRoot must be a nonempty character vector or string scalar.');
end
file = java.io.File(folder);
if ~file.isAbsolute()
    folder = fullfile(pwd, folder);
end
folder = char(java.io.File(folder).getCanonicalPath());

end

%% =========================================================
function prepareFormalTempFolder(tempOutputFolder)

if isfolder(tempOutputFolder)
    rmdir(tempOutputFolder, 's');
elseif isfile(tempOutputFolder)
    error('RectangularFPC:ExportWriteFailed', ...
        'Temporary output path is occupied by a file: %s', tempOutputFolder);
end
mkdir(tempOutputFolder);
mkdir(fullfile(tempOutputFolder, 'dxf'));
mkdir(fullfile(tempOutputFolder, 'reports'));
mkdir(fullfile(tempOutputFolder, 'previews'));

end

%% =========================================================
function removeStagingFolder(tempOutputFolder)

if isfolder(tempOutputFolder)
    rmdir(tempOutputFolder, 's');
end

end

%% =========================================================
function copyRequiredFile(sourcePath, destinationPath)

if ~isfile(sourcePath)
    error('RectangularFPC:MissingExportArtifact', ...
        'Required source artifact is missing: %s', sourcePath);
end
if strcmpi(char(sourcePath), char(destinationPath))
    return;
end
[copied, message] = copyfile(sourcePath, destinationPath, 'f');
if ~copied
    error('RectangularFPC:ExportWriteFailed', ...
        'Unable to create %s: %s', destinationPath, message);
end

end

%% =========================================================
function writeFileManifest(filename, outputFolder)

if isfile(filename)
    delete(filename);
end
files = regularFiles(outputFolder);
relativePaths = cell(numel(files), 1);
for fileIndex = 1:numel(files)
    relativePaths{fileIndex} = relativeArtifactPath( ...
        fullfile(files(fileIndex).folder, files(fileIndex).name), outputFolder);
end
[relativePaths, order] = sort(relativePaths);
files = files(order);

fid = openUtf8File(filename, 'file manifest');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
for fileIndex = 1:numel(files)
    absolutePath = fullfile(files(fileIndex).folder, files(fileIndex).name);
    fprintf(fid, '%s,%s,%d,%s\n', ...
        csvText(relativePaths{fileIndex}), ...
        csvText(artifactRole(relativePaths{fileIndex})), ...
        files(fileIndex).bytes, sha256File(absolutePath));
end
clear cleanup;

end

%% =========================================================
function verifyFileManifest(filename, outputFolder)

manifest = readtable(filename, 'TextType', 'string', ...
    'VariableNamingRule', 'preserve', 'Delimiter', ',');
expectedVariables = {'relativePath', 'role', 'sizeBytes', 'sha256'};
if ~isequal(manifest.Properties.VariableNames, expectedVariables)
    error('RectangularFPC:ManifestVerificationFailed', ...
        'Manifest column contract is invalid.');
end
if any(manifest.relativePath == "reports/08_file_manifest.csv")
    error('RectangularFPC:ManifestVerificationFailed', ...
        'The file manifest must exclude itself.');
end
files = regularFiles(outputFolder);
actualPaths = strings(numel(files), 1);
for fileIndex = 1:numel(files)
    actualPaths(fileIndex) = string(relativeArtifactPath(fullfile( ...
        files(fileIndex).folder, files(fileIndex).name), outputFolder));
end
manifestMask = actualPaths ~= "reports/08_file_manifest.csv";
manifestFiles = files(manifestMask);
actualPaths = actualPaths(manifestMask);
listedPaths = manifest.relativePath;
if height(manifest) ~= numel(manifestFiles) || ...
        numel(unique(listedPaths)) ~= numel(listedPaths) || ...
        ~isequal(sort(listedPaths), sort(actualPaths))
    error('RectangularFPC:ManifestVerificationFailed', ...
        'Manifest path set is incomplete, duplicated, or contains extras.');
end
for rowIndex = 1:height(manifest)
    relativePath = char(manifest.relativePath(rowIndex));
    absolutePath = fullfile(outputFolder, ...
        strrep(relativePath, '/', filesep));
    if ~isfile(absolutePath)
        error('RectangularFPC:ManifestVerificationFailed', ...
            'Manifest entry is missing: %s', relativePath);
    end
    fileInfo = dir(absolutePath);
    expectedRole = artifactRole(relativePath);
    if fileInfo.bytes ~= manifest.sizeBytes(rowIndex) || ...
            ~strcmpi(sha256File(absolutePath), char(manifest.sha256(rowIndex))) || ...
            ~strcmp(expectedRole, char(manifest.role(rowIndex)))
        error('RectangularFPC:ManifestVerificationFailed', ...
            'Manifest role, size, or SHA-256 mismatch: %s', relativePath);
    end
end

end

%% =========================================================
function files = regularFiles(outputFolder)

files = dir(fullfile(outputFolder, '**', '*'));
files = files(~[files.isdir]);

end

%% =========================================================
function relativePath = relativeArtifactPath(absolutePath, outputFolder)

prefix = [char(outputFolder), filesep];
absolutePath = char(absolutePath);
if ~startsWith(absolutePath, prefix)
    error('RectangularFPC:ManifestVerificationFailed', ...
        'Artifact is outside the output folder: %s', absolutePath);
end
relativePath = strrep(absolutePath(numel(prefix) + 1:end), '\', '/');

end

%% =========================================================
function role = artifactRole(relativePath)

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
elseif startsWith(relativePath, 'dxf/')
    role = 'legacy_dxf_alias';
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
elseif startsWith(relativePath, 'previews/')
    role = 'svg_preview';
elseif strcmp(relativePath, 'generation_status.txt')
    role = 'generation_status';
else
    role = 'artifact';
end

end

%% =========================================================
function hash = sha256File(filename)

fid = fopen(filename, 'rb');
if fid == -1
    error('RectangularFPC:ManifestVerificationFailed', ...
        'Unable to read artifact for hashing: %s', filename);
end
cleanup = onCleanup(@() fclose(fid));
raw = fread(fid, Inf, '*uint8');
clear cleanup;
messageDigest = java.security.MessageDigest.getInstance('SHA-256');
digest = messageDigest.digest(raw);
hash = lower(reshape(dec2hex(typecast(digest, 'uint8'), 2).', 1, []));

end

%% =========================================================
function value = csvText(value)

value = ['"', strrep(char(value), '"', '""'), '"'];

end

%% =========================================================
function fid = openAsciiFile(filename, description)

fid = fopen(filename, 'w', 'n', 'US-ASCII');
if fid == -1
    error('RectangularFPC:ExportWriteFailed', ...
        'Unable to create %s: %s', description, filename);
end

end

%% =========================================================
function fid = openUtf8File(filename, description)

fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid == -1
    error('RectangularFPC:ExportWriteFailed', ...
        'Unable to create %s: %s', description, filename);
end

end

%% =========================================================
function token = uniqueToken()

token = char(java.util.UUID.randomUUID());
token = strrep(token, '-', '');

end
