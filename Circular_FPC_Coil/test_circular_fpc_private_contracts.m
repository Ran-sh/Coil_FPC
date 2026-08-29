function tests = test_circular_fpc_private_contracts
% Private validation and atomic-publication regression tests.
tests = functiontests(localfunctions);
end

function testTerminalAnnulusRejectsUnrelatedConnectionTrace(testCase)
result = circular_fpc_main(struct( ...
    'analysisOnly', true, 'enableFigure', false, ...
    'boardLayerCount', 4, 'coilLayerCount', 4, ...
    'designName', 'terminal_trace_clearance_probe'));
geom = resultGeometry(result);

% Move functional L1/L2 via V12 beside the unrelated L1 exit trace.  It is
% far enough from both endpoint terminals to pass disk-to-disk clearance,
% but its annulus edge is only 0.075 mm from the trace edge (< 0.152 mm).
exitPath = result.layerPaths(1).connectionPaths{2};
midIndex = floor(size(exitPath, 1) / 2);
midPoint = exitPath(midIndex, :);
tangent = exitPath(midIndex + 1, :) - exitPath(midIndex - 1, :);
tangent = tangent / norm(tangent);
normal = [-tangent(2), tangent(1)];
candidate = midPoint + 0.45 * normal;
v12Index = find(strcmp({geom.vias.name}, 'V12'), 1);
geom.vias(v12Index).xy = candidate;

validation = circular_fpc_validation( ...
    'validate_result', result.config, result.effectiveDimensions, geom);
verifyTrue(testCase, isfield(validation, ...
    'minTerminalToConnectionTraceMm'));
verifyLessThan(testCase, validation.minTerminalToConnectionTraceMm, ...
    result.config.viaCoilSpacing);
verifyFalse(testCase, validation.passed);
verifyTrue(testCase, any(contains(validation.messages, ...
    'terminal-to-connection-trace')));
end

function testAtomicPublishMoveFailureCleansStagingAndLock(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
mover = @(source, destination) failPublishMove( ...
    source, destination, paths);

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output, mover), ...
    'CircularFPC:AtomicPublishFailed');
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder(paths.output));
verifyFalse(testCase, isfolder(paths.lock));
end

function testAtomicPublishRefusesConcurrentTarget(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>
mkdir(paths.lock);

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'CircularFPC:ConcurrentPublish');
verifyFalse(testCase, isfolder(paths.staging));
verifyTrue(testCase, isfolder(paths.lock));
end

function testAtomicPublishPreservesExistingFormalOutput(testCase)
paths = makePublishFixture(true);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>

verifyError(testCase, @() circular_fpc_publish_atomically( ...
    paths.staging, paths.output), 'CircularFPC:OutputExists');
verifyTrue(testCase, isfile(fullfile(paths.output, 'old_marker.txt')));
verifyFalse(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder(paths.lock));
end

function testAtomicPublishSuccessCommitsWholeTree(testCase)
paths = makePublishFixture(false);
cleanup = onCleanup(@() removeTree(paths.root)); %#ok<NASGU>

circular_fpc_publish_atomically(paths.staging, paths.output);
verifyTrue(testCase, isfile(fullfile(paths.output, 'new_marker.txt')));
verifyFalse(testCase, isfolder(paths.staging));
verifyFalse(testCase, isfolder(paths.lock));
end

function geom = resultGeometry(result)
nLayers = numel(result.layerPaths);
coils = cell(1, nLayers);
connectionPaths = cell(1, nLayers);
for layerIndex = 1:nLayers
    coils{layerIndex} = result.layerPaths(layerIndex).coilXY;
    connectionPaths{layerIndex} = ...
        result.layerPaths(layerIndex).connectionPaths;
end
geom = struct( ...
    'boardLoops', result.boardLoops, ...
    'actualBridgeWidth', result.effectiveDimensions.actualBridgeWidth, ...
    'layoutRegions', result.layoutRegions, ...
    'coils', {coils}, ...
    'connectionPaths', {connectionPaths}, ...
    'pads', result.pads, ...
    'vias', result.vias, ...
    'seriesRoute', result.seriesRoute, ...
    'seriesSequence', {result.seriesSequence}, ...
    'activeLayers', result.activeCoilLayers);
end

function paths = makePublishFixture(withExistingOutput)
paths.root = tempname;
paths.staging = fullfile(paths.root, 'staging');
paths.output = fullfile(paths.root, 'formal');
paths.lock = [paths.output '_publish.lock'];
mkdir(paths.root);
mkdir(paths.staging);
writeMarker(fullfile(paths.staging, 'new_marker.txt'));
if withExistingOutput
    mkdir(paths.output);
    writeMarker(fullfile(paths.output, 'old_marker.txt'));
end
end

function [moved, message] = failPublishMove(source, destination, paths)
if strcmp(source, paths.staging) && strcmp(destination, paths.output)
    moved = false;
    message = 'injected final move failure';
else
    [moved, message] = movefile(source, destination);
end
end

function writeMarker(filename)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'marker');
end

function removeTree(pathName)
if isfolder(pathName)
    rmdir(pathName, 's');
end
end
