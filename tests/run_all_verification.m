function results = run_all_verification()
%RUN_ALL_VERIFICATION Run the public-API regression suite from tests.
%   RESULTS = RUN_ALL_VERIFICATION() adds the project root to the path,
%   runs the full moved suite, propagates any failure to the caller, and
%   restores the original path.

testsFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(testsFolder);
originalPath = path;
cleanup = onCleanup(@() path(originalPath));
addpath(projectRoot);
results = runtests(fullfile(testsFolder, 'test_fpc_coil_regressions.m'));
assertSuccess(results);
clear cleanup;

end
