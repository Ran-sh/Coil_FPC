function varargout = rectangular_fpc_publish_paths(action, varargin)
%RECTANGULAR_FPC_PUBLISH_PATHS Pure publication-path validation helpers.
%   This module performs no filesystem writes or deletes. Root rejection
%   happens from path syntax before canonicalization, so even an unreachable
%   UNC share root is rejected without probing it.

switch action
    case 'validate'
        if numel(varargin) ~= 2
            invalidRequest('validate requires staging and output paths.');
        end
        [varargout{1}, varargout{2}] = validatePair( ...
            varargin{1}, varargin{2});
    case 'normalize'
        if numel(varargin) ~= 1
            invalidRequest('normalize requires exactly one path.');
        end
        varargout{1} = canonicalizePath(varargin{1}, 'path');
    case 'is_ancestor'
        if numel(varargin) ~= 2
            invalidRequest('is_ancestor requires two paths.');
        end
        ancestor = canonicalizePath(varargin{1}, 'ancestor path');
        descendant = canonicalizePath(varargin{2}, 'descendant path');
        varargout{1} = isStrictAncestor(ancestor, descendant);
    otherwise
        invalidRequest('Unknown publication-path operation: %s.', action);
end

end


function [stagingFolder, outputFolder] = validatePair(stagingInput, outputInput)

rejectRootSyntax(stagingInput, 'staging folder');
rejectRootSyntax(outputInput, 'output folder');
stagingFolder = canonicalizePath(stagingInput, 'staging folder');
outputFolder = canonicalizePath(outputInput, 'output folder');
rejectCanonicalRoot(stagingFolder, 'staging folder');
rejectCanonicalRoot(outputFolder, 'output folder');

[stagingParent, stagingName] = fileparts(stagingFolder);
[outputParent, outputName] = fileparts(outputFolder);
if isempty(stagingName) || isempty(outputName)
    invalidRequest('Staging and output folders must have nonempty basenames.');
end
if samePath(stagingFolder, outputFolder) || ...
        isStrictAncestor(stagingFolder, outputFolder) || ...
        isStrictAncestor(outputFolder, stagingFolder)
    invalidRequest( ...
        'Staging and output folders must be distinct and non-nested.');
end
if ~samePath(stagingParent, outputParent)
    invalidRequest( ...
        'Staging and output folders must share one canonical parent.');
end
reservedBackupPrefix = [outputName '_backup_'];
if strcmpi(stagingName, [outputName '_publish.lock']) || ...
        startsWith(lower(stagingName), lower(reservedBackupPrefix))
    invalidRequest( ...
        'Staging folder uses a reserved publication name: %s.', stagingName);
end

end


function path = canonicalizePath(path, description)

path = pathText(path, description);
file = java.io.File(path);
if ~file.isAbsolute()
    path = fullfile(pwd, path);
end
path = char(java.io.File(path).getCanonicalPath());

end


function value = pathText(value, description)

if isstring(value) && isscalar(value)
    value = char(value);
end
if ~ischar(value) || isempty(value) || isempty(strtrim(value))
    invalidRequest( ...
        '%s must be a nonempty character vector or string scalar.', ...
        description);
end

end


function rejectRootSyntax(path, description)

path = pathText(path, description);
normalized = strrep(strtrim(path), '/', '\');
isDriveRoot = ~isempty(regexp(normalized, '^[A-Za-z]:\\*$', 'once'));
isCurrentDriveRoot = strcmp(normalized, '\');
isUncShareRoot = ~isempty(regexp(normalized, ...
    '^\\\\[^\\]+\\[^\\]+\\*$', 'once'));
isExtendedUncRoot = ~isempty(regexp(normalized, ...
    '^\\\\\?\\UNC\\[^\\]+\\[^\\]+\\*$', 'once'));
isPosixRoot = all(path == '/');
if isDriveRoot || isCurrentDriveRoot || isUncShareRoot || ...
        isExtendedUncRoot || isPosixRoot
    invalidRequest('%s must not be a filesystem root.', description);
end

end


function rejectCanonicalRoot(path, description)

root = char(java.io.File(path).toPath().getRoot());
if samePath(trimTrailingSeparators(path), trimTrailingSeparators(root))
    invalidRequest('%s must not be a filesystem root.', description);
end

end


function ancestor = isStrictAncestor(candidate, descendant)

candidate = comparisonKey(trimTrailingSeparators(candidate));
descendant = comparisonKey(trimTrailingSeparators(descendant));
if strcmp(candidate, descendant)
    ancestor = false;
    return;
end
if endsWith(candidate, filesep)
    prefix = candidate;
else
    prefix = [candidate filesep];
end
ancestor = startsWith(descendant, prefix);

end


function path = trimTrailingSeparators(path)

path = char(path);
root = char(java.io.File(path).toPath().getRoot());
minimumLength = numel(root);
while numel(path) > minimumLength && ...
        (endsWith(path, '/') || endsWith(path, '\'))
    path(end) = [];
end

end


function equal = samePath(left, right)

equal = strcmp(comparisonKey(left), comparisonKey(right));

end


function key = comparisonKey(path)

key = strrep(char(path), '/', filesep);
if ispc
    key = lower(key);
end

end


function invalidRequest(message, varargin)

error('RectangularFPC:InvalidPublishRequest', message, varargin{:});

end
