function varargout = rectangular_fpc_read_committed(outputFolder, reader)
%RECTANGULAR_FPC_READ_COMMITTED Read one published version under its lock.
%   VALUE = RECTANGULAR_FPC_READ_COMMITTED(OUTPUTFOLDER, READER) invokes
%   READER(OUTPUTFOLDER) while holding the same exclusive lock used by the
%   publisher. Retry RectangularFPC:ConcurrentPublish after the active read
%   or same-minute replacement finishes.

if ~ischar(outputFolder) || isempty(outputFolder)
    error('RectangularFPC:InvalidReadRequest', ...
        'outputFolder must be a nonempty character vector.');
end
if ~isa(reader, 'function_handle')
    error('RectangularFPC:InvalidReadRequest', ...
        'reader must be a function handle.');
end

lockCleanup = rectangular_fpc_publish_atomically( ...
    'acquire_access', outputFolder); %#ok<NASGU>
if ~isfolder(outputFolder)
    error('RectangularFPC:OutputNotFound', ...
        'Published output folder does not exist: %s', outputFolder);
end
if nargout == 0
    reader(outputFolder);
else
    [varargout{1:nargout}] = reader(outputFolder);
end
clear lockCleanup;

end
