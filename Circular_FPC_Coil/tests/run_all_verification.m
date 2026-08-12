function run_all_verification
% Run all Circular_FPC_Coil regression tests and fail if any test fails.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
testFile = fullfile(projectRoot, 'tests', 'test_circular_fpc_regressions.m');
results = runtests(testFile);
disp(results);
assertSuccess(results);
end
