function varargout = rectangular_fpc_read_committed(outputFolder, reader)
%RECTANGULAR_FPC_READ_COMMITTED Read one published version under its lock.
%   VALUE = RECTANGULAR_FPC_READ_COMMITTED(OUTPUTFOLDER, READER) invokes
%   READER(OUTPUTFOLDER) while holding the same exclusive lock used by the
%   publisher. Retry RectangularFPC:ConcurrentPublish after the active read
%   or same-minute replacement finishes. The folder must carry valid commit
%   evidence (SUCCESS generation_status plus a SHA-256 manifest whose every
%   entry matches on disk); otherwise RectangularFPC:OutputNotCommitted is
%   raised instead of handing a partial output to the reader.

if isstring(outputFolder) && isscalar(outputFolder)
    outputFolder = char(outputFolder);
end
if ~ischar(outputFolder) || isempty(outputFolder)
    error('RectangularFPC:InvalidReadRequest', ...
        'outputFolder must be a nonempty character vector or string scalar.');
end
outputFolder = rectangular_fpc_publish_paths( ...
    'validate_access_target', outputFolder);
if ~isa(reader, 'function_handle')
    error('RectangularFPC:InvalidReadRequest', ...
        'reader must be a function handle.');
end
if ~isfolder(outputFolder)
    error('RectangularFPC:OutputNotFound', ...
        'Published output folder does not exist: %s', outputFolder);
end

lockCleanup = rectangular_fpc_publish_atomically( ...
    'acquire_access', outputFolder); %#ok<NASGU>
if ~isfolder(outputFolder)
    error('RectangularFPC:OutputNotFound', ...
        'Published output folder does not exist: %s', outputFolder);
end
% committed 门禁：目录存在不等于发布完成。发布部分失败且回滚清理也失败时
% 可能留下半成品正式目录，读取前必须验证 commit evidence（fail-closed）。
if ~rectangular_fpc_publish_atomically('verify_committed', outputFolder)
    error('RectangularFPC:OutputNotCommitted', ...
        ['Output folder exists but is not a committed publication ', ...
        '(missing or failing generation_status/manifest integrity): %s'], ...
        outputFolder);
end
if nargout == 0
    reader(outputFolder);
else
    [varargout{1:nargout}] = reader(outputFolder);
end
clear lockCleanup;

end
