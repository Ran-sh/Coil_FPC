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
behaviorResults = runtests(testsFolder, 'IncludeSubfolders', false);
atomicResults = runtests(fullfile(projectRoot, ...
    'test_rectangular_fpc_atomic_publish.m'));
committedReaderResults = runtests(fullfile(projectRoot, ...
    'test_rectangular_fpc_committed_reader.m'));
orphanRecoveryResults = runtests(fullfile(projectRoot, ...
    'test_rectangular_fpc_orphan_recovery.m'));
privateContractResults = runtests(fullfile(projectRoot, ...
    'test_rectangular_fpc_private_contracts.m'));
exportContractResults = runtests(fullfile(projectRoot, ...
    'test_rectangular_fpc_export_contracts.m'));
publishPathResults = runtests(fullfile(projectRoot, ...
    'test_rectangular_fpc_publish_paths.m'));
results = [behaviorResults(:); atomicResults(:); ...
    committedReaderResults(:); orphanRecoveryResults(:); ...
    privateContractResults(:); exportContractResults(:); ...
    publishPathResults(:)];
assert(~isempty(results), 'RectangularFPC:NoTestsDiscovered', ...
    'Rectangular FPC verification discovered zero tests.');
assertSuccess(results);
clear cleanup;

end
