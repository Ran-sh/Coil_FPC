repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);

outputRoot = fullfile(repoRoot, 'fpc_coil_output');
layerCounts = [2, 4, 6, 8];
results = cell(size(layerCounts));

for index = 1:numel(layerCounts)
    layerCount = layerCounts(index);
    cfg = fpc_coil_default_config(struct( ...
        'layerCount', layerCount, ...
        'designName', sprintf('fpc_coil_%dlayer', layerCount), ...
        'outputRoot', outputRoot, ...
        'enablePreview', true));
    results{index} = fpc_coil_generate(cfg);
end

archiveName = fullfile(outputRoot, 'Coil_FPC_verified_outputs.zip');
designFolders = arrayfun( ...
    @(n) sprintf('fpc_coil_%dlayer', n), ...
    layerCounts, 'UniformOutput', false);
zip(archiveName, designFolders, outputRoot);

fprintf('Verified output archive: %s\n', archiveName);
