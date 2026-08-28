function run_all_verification
% Run all Circular_FPC_Coil regression tests and fail if any test fails.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
results = runtests(fullfile(projectRoot, 'tests'));
disp(results);
assertSuccess(results);
end
