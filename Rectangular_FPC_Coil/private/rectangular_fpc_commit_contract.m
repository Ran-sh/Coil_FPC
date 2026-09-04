function [committed, reason] = rectangular_fpc_commit_contract(outputFolder)
%RECTANGULAR_FPC_COMMIT_CONTRACT Verify a complete published handoff.
%   This is the single commit-evidence gate shared by publishing and
%   committed readers. It validates the status schema, exact mandatory
%   artifact paths and roles, the manifest/disk set, sizes, and SHA-256.

committed = false;
reason = '';
try
    outputFolder = normalizeFolderArgument(outputFolder);
    status = readStatusContract(outputFolder);
    manifest = readManifestContract(outputFolder);
    validateManifestPaths(outputFolder, manifest);
    validateRequiredArtifacts(manifest, status.layerCount, ...
        status.previewEnabled);
    committed = true;
catch contractError
    reason = contractError.message;
end

end


function outputFolder = normalizeFolderArgument(outputFolder)

if isstring(outputFolder) && isscalar(outputFolder)
    outputFolder = char(outputFolder);
end
if ~ischar(outputFolder) || isempty(outputFolder)
    error('RectangularFPC:InvalidCommitContract', ...
        'Output folder must be a nonempty character vector or string scalar.');
end
outputFolder = rectangular_fpc_publish_paths('normalize', outputFolder);

end


function status = readStatusContract(outputFolder)

statusFile = fullfile(outputFolder, 'generation_status.txt');
if ~isfile(statusFile)
    error('RectangularFPC:InvalidCommitContract', ...
        'Missing generation_status.txt.');
end
text = fileread(statusFile);
schemaVersion = parseIntegerField(text, 'SchemaVersion');
layerCount = parseIntegerField(text, 'LayerCount');
previewEnabled = parseIntegerField(text, 'PreviewEnabled');
publicationId = parseTextField(text, 'PublicationId');
publicationStatus = parseTextField(text, 'Status');

if schemaVersion ~= 2
    error('RectangularFPC:InvalidCommitContract', ...
        'Unsupported generation status SchemaVersion: %d.', schemaVersion);
end
if ~ismember(layerCount, [2, 4, 6, 8])
    error('RectangularFPC:InvalidCommitContract', ...
        'LayerCount must be one of the supported values 2, 4, 6, or 8.');
end
if ~ismember(previewEnabled, [0, 1])
    error('RectangularFPC:InvalidCommitContract', ...
        'PreviewEnabled must be 0 or 1.');
end
if isempty(regexp(publicationId, '^[0-9a-fA-F]{32}$', 'once'))
    error('RectangularFPC:InvalidCommitContract', ...
        'PublicationId must contain exactly 32 hexadecimal characters.');
end
if ~strcmp(publicationStatus, 'SUCCESS')
    error('RectangularFPC:InvalidCommitContract', ...
        'Generation status is not SUCCESS.');
end

status = struct( ...
    'layerCount', layerCount, ...
    'previewEnabled', logical(previewEnabled));

end


function value = parseIntegerField(text, name)

raw = parseTextField(text, name);
value = str2double(raw);
if ~isfinite(value) || value ~= floor(value)
    error('RectangularFPC:InvalidCommitContract', ...
        'Status field %s must be an integer.', name);
end

end


function value = parseTextField(text, name)

matches = regexp(text, ['(?m)^' name ':\s*([^\r\n]+?)\s*$'], ...
    'tokens');
if numel(matches) ~= 1
    error('RectangularFPC:InvalidCommitContract', ...
        'Status field %s must occur exactly once.', name);
end
value = strtrim(matches{1}{1});

end


function manifest = readManifestContract(outputFolder)

manifestFile = fullfile(outputFolder, 'reports', '08_file_manifest.csv');
if ~isfile(manifestFile)
    error('RectangularFPC:InvalidCommitContract', ...
        'Missing reports/08_file_manifest.csv.');
end
manifest = readtable(manifestFile, 'TextType', 'string', ...
    'VariableNamingRule', 'preserve', 'Delimiter', ',');
expectedColumns = {'relativePath', 'role', 'sizeBytes', 'sha256'};
if ~isequal(manifest.Properties.VariableNames, expectedColumns)
    error('RectangularFPC:InvalidCommitContract', ...
        'Manifest column contract is invalid.');
end
if isempty(manifest)
    error('RectangularFPC:InvalidCommitContract', ...
        'Manifest must contain at least one artifact.');
end

end


function validateManifestPaths(outputFolder, manifest)

listed = strrep(string(manifest.relativePath), '\', '/');
if any(listed == "") || numel(unique(listed)) ~= numel(listed) || ...
        any(listed == "reports/08_file_manifest.csv")
    error('RectangularFPC:InvalidCommitContract', ...
        'Manifest paths are empty, duplicated, or include the manifest.');
end
for rowIndex = 1:height(manifest)
    relativePath = char(manifest.relativePath(rowIndex));
    if ~isSafeRelativePath(relativePath)
        error('RectangularFPC:InvalidCommitContract', ...
            'Unsafe manifest path: %s.', relativePath);
    end
    expectedRole = artifactRole(relativePath);
    if ~strcmp(char(manifest.role(rowIndex)), expectedRole)
        error('RectangularFPC:InvalidCommitContract', ...
            'Manifest role mismatch for %s.', relativePath);
    end
    artifact = fullfile(outputFolder, strrep(relativePath, '/', filesep));
    info = dir(artifact);
    digest = char(manifest.sha256(rowIndex));
    sizeBytes = manifest.sizeBytes(rowIndex);
    if isempty(info) || info(1).isdir || ~isscalar(sizeBytes) || ...
            ~isfinite(sizeBytes) || sizeBytes < 0 || ...
            sizeBytes ~= floor(sizeBytes) || info(1).bytes ~= sizeBytes || ...
            isempty(regexp(digest, '^[0-9a-fA-F]{64}$', 'once')) || ...
            ~strcmpi(sha256File(artifact), digest)
        error('RectangularFPC:InvalidCommitContract', ...
            'Manifest size or SHA-256 mismatch for %s.', relativePath);
    end
end

actual = listOutputArtifacts(outputFolder, ...
    fullfile(outputFolder, 'reports', '08_file_manifest.csv'));
if ~isequal(sort(listed), sort(actual))
    error('RectangularFPC:InvalidCommitContract', ...
        'Manifest and on-disk artifact sets differ.');
end

end


function safe = isSafeRelativePath(relativePath)

safe = ischar(relativePath) && ~isempty(relativePath) && ...
    ~startsWith(relativePath, '/') && ~startsWith(relativePath, '\') && ...
    isempty(regexp(relativePath, '^[A-Za-z]:', 'once')) && ...
    ~contains(relativePath, '\');
if ~safe
    return;
end
parts = strsplit(relativePath, '/');
safe = all(~strcmp(parts, '..')) && all(~strcmp(parts, '.')) && ...
    all(~cellfun('isempty', parts));

end


function validateRequiredArtifacts(manifest, layerCount, previewEnabled)

requiredPaths = [ ...
    "generation_status.txt"; ...
    "dxf/00_board_outline.dxf"; ...
    "dxf/00_drill_map.dxf"; ...
    "reports/01_pad_via_coordinates.csv"; ...
    "reports/02_layer_mapping.csv"; ...
    "reports/03_design_summary.txt"; ...
    "reports/04_turn_scan.csv"; ...
    "reports/05_validation_report.txt"; ...
    "reports/06_manufacturing_check.csv"; ...
    "reports/07_fabrication_notes.txt"];
for layerIndex = 1:layerCount
    layerRoot = sprintf('dxf/L%d/', layerIndex);
    requiredPaths(end+1, 1) = string([layerRoot sprintf( ...
        '%02d_copper_L%d.dxf', layerIndex, layerIndex)]); %#ok<AGROW>
    requiredPaths(end+1, 1) = string([layerRoot sprintf( ...
        '%02d_copper_physical_L%d.dxf', layerIndex, layerIndex)]); %#ok<AGROW>
    requiredPaths(end+1, 1) = string([layerRoot sprintf( ...
        '%02d_antipad_keepout_L%d.dxf', layerIndex, layerIndex)]); %#ok<AGROW>
end

listed = string(manifest.relativePath);
missing = requiredPaths(~ismember(requiredPaths, listed));
if ~isempty(missing)
    error('RectangularFPC:InvalidCommitContract', ...
        'Required publication artifact is missing: %s.', missing(1));
end

previewPaths = listed(startsWith(listed, "previews/"));
expectedPreviews = expectedPreviewPaths(layerCount);
if previewEnabled
    if ~isequal(sort(previewPaths), sort(expectedPreviews))
        error('RectangularFPC:InvalidCommitContract', ...
            'PreviewEnabled=1 requires the exact preview artifact set.');
    end
elseif ~isempty(previewPaths)
    error('RectangularFPC:InvalidCommitContract', ...
        'PreviewEnabled=0 forbids preview artifacts.');
end

end


function paths = expectedPreviewPaths(layerCount)

paths = [ ...
    "previews/01_preview_full.svg"; ...
    "previews/02_preview_right_tab.svg"; ...
    "previews/03_preview_pads_vias.svg"];
for layerIndex = 1:layerCount
    if layerIndex == 1
        layerRole = 'top';
    elseif layerIndex == layerCount
        layerRole = 'bottom';
    else
        layerRole = sprintf('inner%d', layerIndex - 1);
    end
    paths(end+1, 1) = string(sprintf( ...
        'previews/%02d_preview_layer_L%d_%s.svg', ...
        layerIndex + 3, layerIndex, layerRole)); %#ok<AGROW>
end

end


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


function paths = listOutputArtifacts(outputFolder, manifestFile)

entries = dir(fullfile(outputFolder, '**', '*'));
entries = entries(~[entries.isdir]);
paths = strings(0, 1);
for entryIndex = 1:numel(entries)
    fullPath = fullfile(entries(entryIndex).folder, entries(entryIndex).name);
    if strcmp(fullPath, manifestFile)
        continue;
    end
    relative = extractAfter(fullPath, [outputFolder filesep]);
    paths(end+1, 1) = string(strrep(relative, filesep, '/')); %#ok<AGROW>
end

end


function hash = sha256File(filename)

fid = fopen(filename, 'rb');
if fid == -1
    error('RectangularFPC:InvalidCommitContract', ...
        'Unable to read artifact: %s.', filename);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
clear cleanup;
digest = java.security.MessageDigest.getInstance('SHA-256');
hashBytes = typecast(digest.digest(bytes), 'uint8');
hash = lower(reshape(dec2hex(hashBytes, 2).', 1, []));

end
