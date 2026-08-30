function tests = test_rectangular_fpc_engineering
% Engineering-contract tests for the renamed rectangular FPC project.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testsFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(testsFolder);
testCase.TestData.originalPath = path;
addpath(projectRoot);
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testNewConfigurationSurface(testCase)
cfg = rectangular_fpc_default_config();

verifyFalse(testCase, cfg.analysisOnly);
verifyEqual(testCase, cfg.manufacturingProfile, 'jlc_fpc_1oz');
verifyEqual(testCase, cfg.manufacturingTier, 'standard');
verifyEqual(testCase, cfg.manufacturingRuleOverrides, struct());
verifyEqual(testCase, cfg.designName, 'rectangular_fpc_4layer');
verifyTrue(testCase, endsWith(strrep(cfg.outputRoot, '\', '/'), ...
    '/rectangular_fpc_output'));
end

function testAnalysisOnlyHasNoFilesystemSideEffects(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));

result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'outputRoot', outputRoot, ...
    'designName', 'analysis_contract', ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));

verifyFalse(testCase, isfolder(outputRoot));
verifyEqual(testCase, result.outputPath, '');
verifyEqual(testCase, result.outputFolder, '');
verifyEqual(testCase, result.runTimestamp, '');
verifyTrue(testCase, result.validation.passed);
verifyTrue(testCase, result.manufacturing.verified);
verifyEqual(testCase, result.manufacturing.applicability, 'SUPPORTED');
verifyEqual(testCase, result.totalTraceLengthMm, result.totalLengthMm, 'AbsTol', 1e-12);
verifyEqual(testCase, result.estimatedDcResistanceOhm, result.totalResistanceOhm, 'AbsTol', 1e-12);
verifyEqual(testCase, result.config.designName, 'analysis_contract');
verifyEqual(testCase, result.boardDxfFile, '');
verifyEqual(testCase, result.drillMapDxfFile, '');
verifyEqual(testCase, result.layerMappingFile, '');
verifyEqual(testCase, result.manufacturingReport, '');
verifyEqual(testCase, result.fabricationNotes, '');
verifyEqual(testCase, result.fileManifest, '');
verifyTrue(testCase, all(arrayfun(@(layer) isempty(layer.dxfFile), ...
    result.layers)));

clear cleanup;
end

function testSixLayerAnalysisIsExplicitlyUnverified(testCase)
result = rectangular_fpc_main(struct( ...
    'analysisOnly', true, ...
    'layerCount', 6, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));

verifyFalse(testCase, result.manufacturing.verified);
verifyEqual(testCase, result.manufacturing.applicability, ...
    'UNVERIFIED_LAYER_COUNT');
verifyTrue(testCase, result.manufacturing.exportAllowed);
verifyNotEmpty(testCase, result.manufacturing.warnings);
verifyEqual(testCase, result.manufacturing.status, 'UNVERIFIED');
seriesVias = result.vias(~strcmp({result.vias.name}, 'VOUT'));
verifyEqual(testCase, {seriesVias.type}, ...
    repmat({'adjacent_layer_via'}, 1, numel(seriesVias)));
viaTechnology = result.manufacturing.checks( ...
    strcmp({result.manufacturing.checks.id}, 'VIA_TECHNOLOGY'));
verifyEqual(testCase, viaTechnology.status, 'WARN');
verifyEqual(testCase, viaTechnology.code, 'UNVERIFIED_VIA_TECHNOLOGY');
end

function testRecommendedTurnsUseEffectiveConfigInResultAndReports(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));
result = rectangular_fpc_main(struct( ...
    'outputRoot', outputRoot, ...
    'designName', 'recommended_turn_contract', ...
    'useRecommendedTurns', true, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));

verifyEqual(testCase, result.config.turnsPerLayer, result.turnsPerLayer);
verifyEqual(testCase, result.requestedConfig.turnsPerLayer, 1);
verifyGreaterThan(testCase, result.turnsPerLayer, 1);
verifyTrue(testCase, contains(fileread(result.summaryFile), sprintf( ...
    'Layers / turns per layer: %d / %d', ...
    result.layerCount, result.turnsPerLayer)));
verifyTrue(testCase, contains(fileread(fullfile( ...
    result.outputPath, 'generation_status.txt')), sprintf( ...
    'TurnsPerLayer: %d', result.turnsPerLayer)));

clear cleanup;
end

function testPublicInvalidConfigValuesUseRectangularIdentifier(testCase)
cases = { ...
    struct('turnsPerLayer', [1, 2]), ...
    struct('traceWidth', NaN), ...
    struct('plateLength', "invalid"), ...
    struct('coilOuterCornerRadiusMode', 'manual', ...
        'coilOuterCornerRadius', [1, 2]), ...
    struct('viaClearanceSeverity', 42), ...
    struct('outputViaType', 42), ...
    struct('minSpiralCornerRadius', -1), ...
    struct('minSpiralCornerRadius', 0)};
for caseIndex = 1:numel(cases)
    overrides = cases{caseIndex};
    overrides.analysisOnly = true;
    overrides.enablePreview = false;
    overrides.enableFigure = false;
    verifyError(testCase, @() rectangular_fpc_main(overrides), ...
        'RectangularFPC:InvalidConfigValue');
end
end

function testLegacyWrappersForwardWithDeprecationWarning(testCase)
lastwarn('');
legacyCfg = fpc_coil_default_config(struct('analysisOnly', true));
[~, warningId] = lastwarn;

verifyEqual(testCase, warningId, 'RectangularFPC:DeprecatedAPI');
verifyTrue(testCase, legacyCfg.analysisOnly);

lastwarn('');
legacyResult = fpc_coil_main(struct( ...
    'analysisOnly', true, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));
[~, warningId] = lastwarn;

verifyEqual(testCase, warningId, 'RectangularFPC:DeprecatedAPI');
verifyEqual(testCase, legacyResult.outputPath, '');
end

function testLegacyAndNewAnalysisResultsAreEquivalent(testCase)
overrides = struct( ...
    'analysisOnly', true, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false);
newResult = rectangular_fpc_main(overrides);
warningState = warning('off', 'RectangularFPC:DeprecatedAPI');
cleanup = onCleanup(@() warning(warningState));
legacyResult = fpc_coil_main(overrides);

verifyEqual(testCase, legacyResult.boardXY, newResult.boardXY, 'AbsTol', 1e-12);
verifyEqual(testCase, legacyResult.totalLengthMm, newResult.totalLengthMm, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, legacyResult.totalResistanceOhm, ...
    newResult.totalResistanceOhm, 'AbsTol', 1e-12);
verifyEqual(testCase, legacyResult.validation, newResult.validation);
verifyEqual(testCase, legacyResult.manufacturing, newResult.manufacturing);
clear cleanup;
end

function testManufacturingProfilesOverridesAndAnalysisFailure(testCase)
twoLayer = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 2, 'turnsPerLayer', 1, ...
    'enablePreview', false, 'enableFigure', false));
verifyTrue(testCase, twoLayer.manufacturing.verified);
verifyEqual(testCase, twoLayer.manufacturing.rules.minViaDrillMm, 0.30);
verifyEqual(testCase, twoLayer.manufacturing.rules.minViaPadMm, 0.55);

extreme = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 4, 'turnsPerLayer', 1, ...
    'viaDrillDiameter', 0.15, 'viaPadDiameter', 0.35, ...
    'manufacturingTier', 'extreme', ...
    'enablePreview', false, 'enableFigure', false));
verifyTrue(testCase, extreme.manufacturing.verified);
verifyEqual(testCase, extreme.manufacturing.rules.minViaDrillMm, 0.15);
verifyEqual(testCase, extreme.manufacturing.rules.minViaPadMm, 0.35);
verifyEqual(testCase, extreme.manufacturing.status, 'WARN');

failed = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'turnsPerLayer', 1, ...
    'manufacturingRuleOverrides', struct('minTraceWidthMm', 0.30), ...
    'enablePreview', false, 'enableFigure', false));
verifyFalse(testCase, failed.manufacturing.exportAllowed);
verifyFalse(testCase, failed.manufacturing.verified);
verifyEqual(testCase, failed.manufacturing.status, 'FAIL');
verifyNotEmpty(testCase, failed.manufacturing.failures);
end

function testCopperToBoardUsesMeasuredFinalGeometry(testCase)
% H2 契约：COPPER_TO_BOARD 必须来自最终几何实测（走线 + PAD + 过孔焊环），
% 而不是配置值 edgeClearance。配置允许下限附近的 PAD 内缩必须被制造判定拦截。
defaults = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 2, 'turnsPerLayer', 1, ...
    'enablePreview', false, 'enableFigure', false));
defaultRow = defaults.manufacturing.checks( ...
    strcmp({defaults.manufacturing.checks.id}, 'COPPER_TO_BOARD'));
assertNumElements(testCase, defaultRow, 1);
verifyEqual(testCase, defaultRow.measuredMm, ...
    defaults.validation.minCopperToBoardMm, 'AbsTol', 1e-9);
verifyGreaterThanOrEqual(testCase, defaultRow.measuredMm, ...
    defaults.manufacturing.rules.minCopperToBoardMm - 1e-9);
verifyTrue(testCase, defaults.manufacturing.verified);

% padTipInset 取配置允许下限：焊盘铜边到板边实测约 0.20 mm (< 0.30)，
% 配置校验与既有几何检查都放行，但制造资格必须 FAIL 并禁止导出。
adversarial = rectangular_fpc_main(struct( ...
    'analysisOnly', true, 'layerCount', 2, 'turnsPerLayer', 1, ...
    'padTipInset', defaults.config.padDiameter / 2 + defaults.config.padTipMargin, ...
    'enablePreview', false, 'enableFigure', false));
adversarialRow = adversarial.manufacturing.checks( ...
    strcmp({adversarial.manufacturing.checks.id}, 'COPPER_TO_BOARD'));
assertNumElements(testCase, adversarialRow, 1);
verifyLessThan(testCase, adversarialRow.measuredMm, ...
    adversarial.manufacturing.rules.minCopperToBoardMm);
verifyEqual(testCase, adversarialRow.measuredMm, ...
    adversarial.validation.minCopperToBoardMm, 'AbsTol', 1e-9);
verifyFalse(testCase, adversarial.manufacturing.verified);
verifyFalse(testCase, adversarial.manufacturing.exportAllowed);
verifyEqual(testCase, adversarial.manufacturing.status, 'FAIL');
end

function testSupportedManufacturingUsesPlatedThroughViasAndAntipads(testCase)
for layerCount = [2, 4]
    result = rectangular_fpc_main(struct( ...
        'analysisOnly', true, ...
        'layerCount', layerCount, ...
        'turnsPerLayer', 1, ...
        'enablePreview', false, ...
        'enableFigure', false));
    cfg = result.config;

    verifyTrue(testCase, result.manufacturing.verified);
    viaTechnology = result.manufacturing.checks( ...
        strcmp({result.manufacturing.checks.id}, 'VIA_TECHNOLOGY'));
    assertNumElements(testCase, viaTechnology, 1);
    verifyEqual(testCase, viaTechnology.status, 'PASS');
    verifyEqual(testCase, {result.vias.type}, ...
        repmat({'through_via'}, 1, numel(result.vias)));
    verifyGreaterThanOrEqual(testCase, cfg.viaToCopperClearance, ...
        result.manufacturing.rules.minViaToTraceMm);
    verifyGreaterThanOrEqual(testCase, cfg.outputViaToCopperClearance, ...
        result.manufacturing.rules.minViaToTraceMm);
    viaToTrace = result.manufacturing.checks( ...
        strcmp({result.manufacturing.checks.id}, 'VIA_TO_TRACE'));
    assertNumElements(testCase, viaToTrace, 1);
    verifyNotEqual(testCase, viaToTrace.status, 'FAIL');

    for viaIndex = 1:numel(result.vias)
        via = result.vias(viaIndex);
        nonConnectedLayers = setdiff(1:layerCount, via.connectedLayers);
        if isempty(nonConnectedLayers)
            continue
        end
        verifyGreaterThanOrEqual(testCase, via.antipadDiameter, ...
            via.padDiameter + 2 * ...
            result.manufacturing.rules.minViaToTraceMm - ...
            cfg.geometryTolerance);
    end
end
end

function testSupportedQualificationRejectsDisabledRequiredChecks(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));
overrides = struct( ...
    'analysisOnly', true, ...
    'outputRoot', outputRoot, ...
    'designName', 'disabled_check_contract', ...
    'turnsPerLayer', 1, ...
    'enableCopperClearanceCheck', false, ...
    'enablePreview', false, ...
    'enableFigure', false);

result = rectangular_fpc_main(overrides);
verifyFalse(testCase, result.manufacturing.verified);
verifyFalse(testCase, result.manufacturing.exportAllowed);
verifyEqual(testCase, result.manufacturing.status, 'FAIL');
qualification = result.manufacturing.checks(strcmp( ...
    {result.manufacturing.checks.id}, 'REQUIRED_VALIDATION_CHECKS'));
assertNumElements(testCase, qualification, 1);
verifyEqual(testCase, qualification.status, 'FAIL');
verifyEqual(testCase, qualification.code, 'REQUIRED_CHECK_DISABLED');
verifyFalse(testCase, isfolder(outputRoot));

overrides.analysisOnly = false;
verifyError(testCase, @() rectangular_fpc_main(overrides), ...
    'RectangularFPC:ManufacturingFailed');
if isfolder(outputRoot)
    formal = dir(fullfile(outputRoot, 'disabled_check_contract_*'));
    verifyEmpty(testCase, formal([formal.isdir]));
end

clear cleanup;
end

function testTimestampedExportContainsEngineeringArtifacts(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));

result = rectangular_fpc_main(struct( ...
    'outputRoot', outputRoot, ...
    'designName', 'timestamp_contract', ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false));

verifyMatches(testCase, result.runTimestamp, '^\d{8}_\d{4}$');
verifyEqual(testCase, result.outputPath, fullfile(outputRoot, ...
    ['timestamp_contract_' result.runTimestamp]));
verifyTrue(testCase, isfile(fullfile(result.outputPath, 'dxf', ...
    '00_board_outline.dxf')));
verifyTrue(testCase, isfile(fullfile(result.outputPath, 'dxf', ...
    '00_drill_map.dxf')));
for layer = 1:result.layerCount
    layerFolder = fullfile(result.outputPath, 'dxf', sprintf('L%d', layer));
    verifyTrue(testCase, isfile(fullfile(layerFolder, ...
        sprintf('%02d_copper_L%d.dxf', layer, layer))));
    verifyTrue(testCase, isfile(fullfile(layerFolder, ...
        sprintf('%02d_copper_physical_L%d.dxf', layer, layer))));
    verifyTrue(testCase, isfile(fullfile(layerFolder, ...
        sprintf('%02d_antipad_keepout_L%d.dxf', layer, layer))));
    antipadFile = fullfile(layerFolder, ...
        sprintf('%02d_antipad_keepout_L%d.dxf', layer, layer));
    expectedAntipads = sum(arrayfun(@(via) ...
        via.antipadDiameter > 0 && ...
        ~ismember(layer, via.connectedLayers), result.vias));
    verifyEqual(testCase, countDxfEntities(antipadFile, 'CIRCLE'), ...
        expectedAntipads);
end
for reportIndex = 1:8
    pattern = fullfile(result.outputPath, 'reports', sprintf('%02d_*', reportIndex));
    verifyEqual(testCase, numel(dir(pattern)), 1, ...
        sprintf('expected exactly one report with index %02d', reportIndex));
end

manifestPath = fullfile(result.outputPath, 'reports', '08_file_manifest.csv');
manifest = readtable(manifestPath, 'TextType', 'string');
verifyEqual(testCase, manifest.Properties.VariableNames, ...
    {'relativePath', 'role', 'sizeBytes', 'sha256'});
verifyFalse(testCase, any(manifest.relativePath == "reports/08_file_manifest.csv"));
verifyTrue(testCase, all(strlength(manifest.sha256) == 64));
verifyEqual(testCase, height(manifest), countFiles(result.outputPath) - 1);
for rowIndex = 1:height(manifest)
    artifactPath = fullfile(result.outputPath, ...
        strrep(char(manifest.relativePath(rowIndex)), '/', filesep));
    info = dir(artifactPath);
    verifyEqual(testCase, manifest.sizeBytes(rowIndex), info.bytes);
    verifyEqual(testCase, manifest.sha256(rowIndex), ...
        string(sha256File(artifactPath)));
end

clear cleanup;
end

function testSameMinuteReplacementRollbackAndHistoricalRetention(testCase)
workspaceRoot = tempname;
outputRoot = fullfile(workspaceRoot, 'rectangular_fpc_output');
legacyRoot = fullfile(workspaceRoot, 'fpc_coil_output');
mkdir(legacyRoot);
writeMarker(fullfile(legacyRoot, 'historical_marker.txt'));
oldVersion = fullfile(outputRoot, 'atomic_contract_20000101_0000');
mkdir(oldVersion);
writeMarker(fullfile(oldVersion, 'old_version_marker.txt'));
cleanup = onCleanup(@() removeWorkspaceRoot(workspaceRoot));

base = struct( ...
    'outputRoot', outputRoot, 'designName', 'atomic_contract', ...
    'turnsPerLayer', 1, 'enablePreview', false, 'enableFigure', false);
[before, after] = generateSameMinutePair(base);
verifyEqual(testCase, before.outputPath, after.outputPath);
verifyTrue(testCase, isfile(after.fileManifest));
verifyTrue(testCase, isfile(fullfile(oldVersion, 'old_version_marker.txt')));
verifyTrue(testCase, isfile(fullfile(legacyRoot, 'historical_marker.txt')));

writeMarker(fullfile(after.outputPath, 'published_marker.txt'));
bad = base;
bad.manufacturingRuleOverrides = struct('minTraceWidthMm', 0.30);
verifyError(testCase, @() rectangular_fpc_main(bad), ...
    'RectangularFPC:ManufacturingFailed');
verifyTrue(testCase, isfile(fullfile(after.outputPath, 'published_marker.txt')));
verifyTrue(testCase, isfile(fullfile(legacyRoot, 'historical_marker.txt')));

% Simulate a process interruption for the minute that the next call will
% target. Deriving the target immediately before invoking the entry point
% keeps this test valid even when the earlier assertions cross a minute.
for recoveryAttempt = 1:3
    prospectiveTimestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmm'));
    prospectivePath = fullfile(outputRoot, ...
        ['atomic_contract_' prospectiveTimestamp]);
    orphanBackup = [prospectivePath '_backup_interrupted_test'];
    if isfolder(prospectivePath)
        [moved, message] = movefile(prospectivePath, orphanBackup);
        verifyTrue(testCase, moved, message);
    else
        mkdir(orphanBackup);
        writeMarker(fullfile(orphanBackup, 'interrupted_marker.txt'));
    end
    staleLockFolder = [prospectivePath '_publish.lock'];
    mkdir(staleLockFolder);
    writeStaleLockOwner(staleLockFolder);
    recovered = rectangular_fpc_main(base);
    if strcmp(recovered.outputPath, prospectivePath)
        break;
    end
    if isfolder(orphanBackup)
        rmdir(orphanBackup, 's');
    end
    if isfolder(staleLockFolder)
        rmdir(staleLockFolder, 's');
    end
end
verifyEqual(testCase, recovered.outputPath, prospectivePath);
verifyTrue(testCase, isfile(recovered.fileManifest));
verifyFalse(testCase, isfolder(orphanBackup));
verifyFalse(testCase, isfolder(staleLockFolder));

% A concurrent publication lock must fail closed without disturbing the
% already published minute version or leaving a staging directory behind.
writeMarker(fullfile(recovered.outputPath, 'lock_preservation_marker.txt'));
lockTimes = [datetime('now'), datetime('now') + minutes(1)];
lockFolders = cell(1, numel(lockTimes));
for lockIndex = 1:numel(lockTimes)
    stamp = char(datetime(lockTimes(lockIndex), 'Format', 'yyyyMMdd_HHmm'));
    versionPath = fullfile(outputRoot, ['atomic_contract_' stamp]);
    lockFolders{lockIndex} = [versionPath '_publish.lock'];
    mkdir(lockFolders{lockIndex});
end
verifyError(testCase, @() rectangular_fpc_main(base), ...
    'RectangularFPC:ConcurrentPublish');
verifyTrue(testCase, isfile(fullfile( ...
    recovered.outputPath, 'lock_preservation_marker.txt')));
for lockIndex = 1:numel(lockFolders)
    if isfolder(lockFolders{lockIndex})
        rmdir(lockFolders{lockIndex});
    end
end
verifyEmpty(testCase, dir(fullfile(outputRoot, '*_rectangular_fpc_staging')));

clear cleanup;
end

function testManufacturingFailureDoesNotCreateFormalOutput(testCase)
outputRoot = freshOutputRoot();
cleanup = onCleanup(@() removeOutputRoot(outputRoot));
overrides = struct( ...
    'outputRoot', outputRoot, ...
    'designName', 'manufacturing_failure', ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false, ...
    'manufacturingRuleOverrides', struct('minTraceWidthMm', 0.30));

verifyError(testCase, @() rectangular_fpc_main(overrides), ...
    'RectangularFPC:ManufacturingFailed');
if isfolder(outputRoot)
    formal = dir(fullfile(outputRoot, 'manufacturing_failure_*'));
    formal = formal([formal.isdir]);
    verifyEmpty(testCase, formal);
end

clear cleanup;
end

function testActiveGeometryErrorsUseRectangularIdentifiers(testCase)
terminalConfig = struct( ...
    'analysisOnly', true, ...
    'tabWidth', 1.0, ...
    'turnsPerLayer', 1, ...
    'enablePreview', false, ...
    'enableFigure', false);
verifyError(testCase, @() rectangular_fpc_main(terminalConfig), ...
    'RectangularFPC:InvalidTerminalGeometry');

turnConfig = struct( ...
    'analysisOnly', true, ...
    'turnsPerLayer', 20, ...
    'enablePreview', false, ...
    'enableFigure', false);
verifyError(testCase, @() rectangular_fpc_main(turnConfig), ...
    'RectangularFPC:TurnLimitExceeded');
end

function outputRoot = freshOutputRoot()
outputRoot = fullfile(tempname, 'rectangular_fpc_test_output');
end

function removeOutputRoot(outputRoot)
if isfolder(outputRoot)
    rmdir(outputRoot, 's');
end
parent = fileparts(outputRoot);
if isfolder(parent)
    rmdir(parent, 's');
end
end

function [before, after] = generateSameMinutePair(overrides)
before = rectangular_fpc_main(overrides);
for attempt = 1:3
    replacementMarker = fullfile(before.outputPath, ...
        'same_minute_replacement_marker.txt');
    writeMarker(replacementMarker);
    after = rectangular_fpc_main(overrides);
    if strcmp(before.runTimestamp, after.runTimestamp)
        if isfile(replacementMarker)
            error('RectangularFPC:TestAtomicReplacement', ...
                'Same-minute publication did not replace the prior version.');
        end
        return;
    end
    before = after;
end
error('RectangularFPC:TestClockBoundary', ...
    'Unable to generate two designs in the same minute.');
end

function count = countFiles(root)
entries = dir(fullfile(root, '**', '*'));
count = sum(~[entries.isdir]);
end

function count = countDxfEntities(filename, entityName)
content = fileread(filename);
count = numel(regexp(content, ...
    ['(?m)^' regexptranslate('escape', entityName) '\r?$'], 'match'));
end

function hash = sha256File(filename)
fid = fopen(filename, 'rb');
cleanup = onCleanup(@() fclose(fid));
raw = fread(fid, Inf, '*uint8');
clear cleanup;
messageDigest = java.security.MessageDigest.getInstance('SHA-256');
digest = messageDigest.digest(raw);
hash = lower(reshape(dec2hex(typecast(digest, 'uint8'), 2).', 1, []));
end

function writeMarker(filename)
fid = fopen(filename, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'preserve');
clear cleanup;
end

function writeStaleLockOwner(lockFolder)
fid = fopen(fullfile(lockFolder, 'owner.txt'), 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'pid=2147483647\n');
fprintf(fid, 'host=%s\n', localHostIdentity());
fprintf(fid, 'token=interrupted_test\n');
fprintf(fid, 'created=2000-01-01T00:00:00.000Z\n');
clear cleanup;
end

function host = localHostIdentity()
host = getenv('COMPUTERNAME');
if isempty(host)
    host = getenv('HOSTNAME');
end
if isempty(host)
    host = char(java.net.InetAddress.getLocalHost().getHostName());
end
host = lower(strtrim(host));
end

function removeWorkspaceRoot(workspaceRoot)
if isfolder(workspaceRoot)
    rmdir(workspaceRoot, 's');
end
end
