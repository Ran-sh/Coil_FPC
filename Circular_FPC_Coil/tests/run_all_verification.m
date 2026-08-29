function results = run_all_verification
% Run all Circular_FPC_Coil regression and private-contract tests.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
behaviorResults = runtests(fullfile(projectRoot, 'tests'), 'IncludeSubfolders', false);
privateContractResults = runtests(fullfile(projectRoot, ...
    'test_circular_fpc_private_contracts.m'));
results = [behaviorResults(:); privateContractResults(:)];
disp(results);
assert(~isempty(results), 'CircularFPC:NoTestsDiscovered', ...
    'Circular FPC verification discovered zero tests.');
assertSuccess(results);
end
