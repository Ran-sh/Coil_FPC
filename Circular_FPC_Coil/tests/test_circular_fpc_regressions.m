function tests = test_circular_fpc_regressions
% Function-based behavior regression tests for Circular_FPC_Coil (R1-R4).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = 'D:/A_Bone_healing/bone_healing_simulink/Coil/Circular_FPC_Coil';
addpath(projectRoot);
testCase.TestData.projectRoot = projectRoot;
end

function testDefaultConfigContractAndOverrides(testCase)
cfg = circular_fpc_default_config();
verifyEqual(testCase, cfg.boardLayerCount, 2);
verifyEqual(testCase, cfg.coilLayerCount, 1);
verifyEqual(testCase, cfg.boardOuterDiameter, 25.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.coilInnerDiameter, 18.63, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.centerPlatformWidth, 13.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.centerPlatformHeight, 11.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.bridgeTargetWidth, 1.5, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.turnsPerCoilLayer, 8);
verifyEqual(testCase, cfg.traceWidth, 0.20, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.traceSpacing, 0.15, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.pitchMargin, 0.005, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.edgeClearance, 0.50, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.connectionAngleDeg, 135.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.geometryScale, 1.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.terminalPlacementMode, 'auto');
verifyEmpty(testCase, cfg.manualPadAXY);
verifyEmpty(testCase, cfg.manualPadBXY);
verifyEqual(testCase, size(cfg.manualSeriesViaXY), [0 2]);
verifyTrue(testCase, isfield(cfg, 'padDiameter'));
verifyTrue(testCase, isfield(cfg, 'viaDrillDiameter'));
verifyTrue(testCase, isfield(cfg, 'viaPadDiameter'));
verifyTrue(testCase, isfield(cfg, 'outputRoot'));
verifyTrue(testCase, isfield(cfg, 'designName'));
verifyTrue(testCase, cfg.enablePreview);
verifyTrue(testCase, isfield(cfg, 'padPairSpacing'), 'default config missing padPairSpacing');
if isfield(cfg, 'padPairSpacing')
    verifyEqual(testCase, cfg.padPairSpacing, 2.0, 'AbsTol', 1e-9);
end
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', 0)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', NaN)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', Inf)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', [1 2])), 'CircularFPC:InvalidConfig');
cfg24 = circular_fpc_default_config(struct('padPairSpacing', 2.4));
if isfield(cfg24, 'padPairSpacing')
    verifyEqual(testCase, cfg24.padPairSpacing, 2.4, 'AbsTol', 1e-9);
end
cfg2 = circular_fpc_default_config(struct('turnsPerCoilLayer', 10));
verifyEqual(testCase, cfg2.turnsPerCoilLayer, 10);
verifyEqual(testCase, cfg2.boardOuterDiameter, 25.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg2.coilLayerCount, 1);
verifyEqual(testCase, cfg2.traceSpacing, 0.15, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg2.edgeClearance, 0.50, 'AbsTol', 1e-9);
cfgZero = circular_fpc_default_config(struct('connectionAngleDeg', 0));
verifyEqual(testCase, cfgZero.connectionAngleDeg, 0, 'AbsTol', 1e-9);
cfgNeg = circular_fpc_default_config(struct('connectionAngleDeg', -45));
verifyEqual(testCase, cfgNeg.connectionAngleDeg, -45, 'AbsTol', 1e-9);
verifyError(testCase, @() circular_fpc_default_config(struct('connectionAngleDeg', NaN)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('connectionAngleDeg', Inf)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('connectionAngleDeg', [0 1])), 'CircularFPC:InvalidConfig');
end

function testRejectsUnsupportedLayerMatrix(testCase)
verifyError(testCase, @() circular_fpc_default_config(struct('unknownField', 1)), 'CircularFPC:UnknownConfigField');
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 3)), 'CircularFPC:UnsupportedLayerCombination');
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 4, 'coilLayerCount', 3)), 'CircularFPC:UnsupportedLayerCombination');
verifyError(testCase, @() circular_fpc_default_config(struct('boardOuterDiameter', 0)), 'CircularFPC:InvalidConfig');
end

function testDefaultBoardGeometry(testCase)
cfg = circular_fpc_default_config();
outRoot = createTempOutput(testCase);
lastwarn('');
result = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'default_geometry'));
[warningMessage, warningId] = lastwarn;
verifyEmpty(testCase, warningMessage);
verifyEmpty(testCase, warningId);
verifyEqual(testCase, result.boardLayerCount, 2);
verifyEqual(testCase, result.coilLayerCount, 1);
verifyEqual(testCase, result.activeCoilLayers, [1]);
verifyEqual(testCase, result.effectiveDimensions.boardOuterDiameter, 25.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.coilInnerDiameter, 18.63, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformWidth, 13.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformHeight, 11.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.bridgeTargetWidth, 1.5, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.coilPitch, 0.355, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.turnsPerCoilLayer, 8);
verifyGreaterThanOrEqual(testCase, result.effectiveDimensions.actualBridgeWidth, 1.5);
outerLoop = result.boardLoops(1);
verifyFalse(testCase, outerLoop.isHole);
outerXY = outerLoop.xy(1:end - 1, :);
nominalOuterRadius = result.effectiveDimensions.boardOuterDiameter / 2;
outerRadii = hypot(outerXY(:, 1), outerXY(:, 2));
verifyLessThanOrEqual(testCase, max(outerRadii), nominalOuterRadius + 1e-6);
verifyGreaterThanOrEqual(testCase, min(outerRadii), nominalOuterRadius - 2e-4);
verifyEqual(testCase, numel(result.boardLoops), 5);
holeCount = 0;
for k = 1:numel(result.boardLoops)
    bl = result.boardLoops(k);
    verifyTrue(testCase, isfield(bl, 'name'));
    verifyTrue(testCase, isfield(bl, 'isHole'));
    verifyTrue(testCase, isfield(bl, 'xy'));
    verifyTrue(testCase, isfield(bl, 'orientation'));
    verifyTrue(testCase, islogical(bl.isHole));
    if bl.isHole
        holeCount = holeCount + 1;
    end
    xy = bl.xy;
    verifyTrue(testCase, ~isempty(xy) && size(xy, 2) == 2 && all(isfinite(xy(:))));
    verifyEqual(testCase, xy(1, :), xy(end, :), 'AbsTol', 1e-9);
    verifyTrue(testCase, ~any(all(diff(xy, 1, 1) == 0, 2)));
    verifyTrue(testCase, isscalar(bl.orientation) && isnumeric(bl.orientation) && ~isnan(bl.orientation));
end
verifyEqual(testCase, holeCount, 4);
verifyTrue(testCase, result.validation.passed);
verifyTrue(testCase, result.validation.finiteCoordinates);
verifyTrue(testCase, result.validation.noZeroLengthSegments);
verifyTrue(testCase, result.validation.noSelfIntersections);
verifyEqual(testCase, result.validation.closedBoardLoopCount, 5);
verifyGreaterThanOrEqual(testCase, result.validation.minCopperSpacingMm, 0.15);
verifyGreaterThanOrEqual(testCase, result.validation.minCopperToBoardMm, 0.50);
verifyGreaterThanOrEqual(testCase, result.validation.minCopperToSlotsMm, cfg.edgeClearance);
verifyGreaterThanOrEqual(testCase, result.validation.actualBridgeWidthMm, 1.5);
verifyTrue(testCase, result.validation.uniqueSeriesNetwork);
verifyTrue(testCase, result.validation.viaOverlapFree);
verifyTrue(testCase, isfield(result, 'totalTraceLengthMm'));
verifyTrue(testCase, isfield(result, 'estimatedDcResistanceOhm'));
verifyTrue(testCase, isfinite(result.totalTraceLengthMm) && result.totalTraceLengthMm > 0);
verifyTrue(testCase, isfinite(result.estimatedDcResistanceOhm) && result.estimatedDcResistanceOhm > 0);
verifyTrue(testCase, ischar(result.outputPath));
end

function testGeometryScaleKeepsManufacturingRules(testCase)
base = circular_fpc_default_config();
scaled = circular_fpc_default_config(struct('geometryScale', 2.0));
verifyEqual(testCase, scaled.boardOuterDiameter, base.boardOuterDiameter, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.coilInnerDiameter, base.coilInnerDiameter, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.centerPlatformWidth, base.centerPlatformWidth, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.centerPlatformHeight, base.centerPlatformHeight, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.bridgeTargetWidth, base.bridgeTargetWidth, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.geometryScale, 2.0, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.traceWidth, base.traceWidth, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.traceSpacing, base.traceSpacing, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.pitchMargin, base.pitchMargin, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.edgeClearance, base.edgeClearance, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.padDiameter, base.padDiameter, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.viaPadDiameter, base.viaPadDiameter, 'AbsTol', 1e-9);
verifyEqual(testCase, scaled.viaDrillDiameter, base.viaDrillDiameter, 'AbsTol', 1e-9);
verifyTrue(testCase, isfield(base, 'padPairSpacing'), 'base config missing padPairSpacing');
verifyTrue(testCase, isfield(scaled, 'padPairSpacing'), 'scaled config missing padPairSpacing');
if isfield(base, 'padPairSpacing') && isfield(scaled, 'padPairSpacing')
    verifyEqual(testCase, scaled.padPairSpacing, base.padPairSpacing, 'AbsTol', 1e-9);
end
outRoot = createTempOutput(testCase);
result = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'scaled_geometry', 'geometryScale', 2.0));
verifyEqual(testCase, result.effectiveDimensions.boardOuterDiameter, 50.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.coilInnerDiameter, 37.26, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformWidth, 26.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformHeight, 22.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.bridgeTargetWidth, 3.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.coilPitch, 0.355, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.turnsPerCoilLayer, 8);
fullSvg = fullfile(result.outputPath, 'previews', '01_preview_full.svg');
verifyTrue(testCase, isfile(fullSvg));
if isfile(fullSvg)
    svgTxt = fileread(fullSvg);
    verifyTrue(testCase, contains(svgTxt, 'viewBox="-25.500000 -25.500000 51.000000 51.000000"'));
end
end

function testInvalidGeometryRejected(testCase)
outRoot = createTempOutput(testCase);
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'invalid_platform', 'centerPlatformWidth', 20.0)), 'CircularFPC:GeometryInfeasible');
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'invalid_scale', 'geometryScale', 0.05)), 'CircularFPC:GeometryInfeasible');
verifyFalse(testCase, isfolder(fullfile(outRoot, 'invalid_platform')));
verifyFalse(testCase, isfolder(fullfile(outRoot, 'invalid_scale')));
end

function testSupportedLayerMatrixAndSeriesContinuity(testCase)
combos = {2, 1; 2, 2; 4, 1; 4, 2; 4, 4};
expectedActive = {[1]; [1 2]; [1]; [1 4]; [1 2 3 4]};
expectedDirections = {{'CCW'}; {'CCW', 'CW'}; {'CCW'}; {'CCW', 'CW'}; {'CCW', 'CW', 'CCW', 'CW'}};
expectedSequence = { ...
    {'PAD_A', 'COIL_L1', 'VRET', 'RETURN_L2', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'V12', 'COIL_L2', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'VRET', 'RETURN_L4', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'V14', 'COIL_L4', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'V12', 'COIL_L2', 'V23', 'COIL_L3', 'V34', 'COIL_L4', 'VOUT', 'PAD_B'}};
outRoot = createTempOutput(testCase);
for k = 1:size(combos, 1)
    result = circular_fpc_main(struct('boardLayerCount', combos{k, 1}, 'coilLayerCount', combos{k, 2}, ...
        'outputRoot', outRoot, 'designName', sprintf('layers_%d_%d', combos{k, 1}, combos{k, 2})));
    verifyTrue(testCase, result.validation.passed, ...
        sprintf('layers_%d_%d validation.passed=false: %s', combos{k, 1}, combos{k, 2}, ...
        strjoin(result.validation.messages, ' | ')));
    if combos{k, 1} == 4 && combos{k, 2} == 4
        v23 = result.vias(strcmp({result.vias.name}, 'V23'));
        verifyEqual(testCase, numel(v23), 1, 'layers_4_4 must contain exactly one V23 via');
        verifyEqual(testCase, v23.fromLayer, 2);
        verifyEqual(testCase, v23.toLayer, 3);
        verifyEqual(testCase, v23.role, 'INNER_TRANSITION');
        verifyGreaterThanOrEqual(testCase, result.validation.minCopperToSlotsMm, ...
            result.config.edgeClearance - 1e-9);
    end
    verifyEqual(testCase, result.activeCoilLayers, expectedActive{k});
    verifyEqual(testCase, numel(result.layerPaths), combos{k, 1});
    for li = 1:numel(result.layerPaths)
        lp = result.layerPaths(li);
        verifyEqual(testCase, lp.layerNumber, li);
        isActive = ismember(li, expectedActive{k});
        verifyEqual(testCase, lp.isActiveCoilLayer, isActive);
        verifyTrue(testCase, isfield(lp, 'windingDirection'));
        if isActive
            verifyFalse(testCase, isempty(lp.coilXY));
            idx = find(expectedActive{k} == li, 1);
            verifyEqual(testCase, lp.windingDirection, expectedDirections{k}{idx});
        else
            verifyEmpty(testCase, lp.coilXY);
        end
        verifyTrue(testCase, isfield(lp, 'connectionPaths'));
        if isfield(lp, 'connectionPaths')
            verifyTrue(testCase, iscell(lp.connectionPaths));
        end
    end
    verifyEqual(testCase, result.seriesSequence, expectedSequence{k});
    verifyPhysicalSeriesRoute(testCase, result, expectedActive{k});
    verifyTrue(testCase, result.validation.uniqueSeriesNetwork);
    verifyTrue(testCase, result.validation.viaOverlapFree);
    verifyEqual(testCase, numel(result.pads), 2);
    verifyEqual(testCase, sort({result.pads.name}), {'PAD_A', 'PAD_B'});
    for p = 1:numel(result.pads)
        verifyEqual(testCase, result.pads(p).layer, 1);
        verifyTrue(testCase, result.pads(p).removable);
    end
    voutCount = sum(strcmp({result.vias.name}, 'VOUT'));
    verifyEqual(testCase, voutCount, 1);
    verifyTrue(testCase, isfield(result, 'returnLayer'));
    if isfield(result, 'returnLayer')
        if combos{k, 2} == 1
            verifyEqual(testCase, result.returnLayer, combos{k, 1});
            verifyEqual(testCase, sort({result.vias.name}), {'VOUT', 'VRET'});
            retLP = result.layerPaths(combos{k, 1});
            verifyTrue(testCase, isfield(retLP, 'connectionPaths'));
            if isfield(retLP, 'connectionPaths')
                verifyFalse(testCase, isempty(retLP.connectionPaths));
            end
        else
            verifyTrue(testCase, isnan(result.returnLayer));
        end
    end
    if combos{k, 1} == 4
        for vk = 1:numel(result.vias)
            v = result.vias(vk);
            for li = 1:4
                if li == v.fromLayer || li == v.toLayer
                    continue;
                end
                dxfPath = fullfile(result.outputPath, 'dxf', sprintf('L%d', li), sprintf('%02d_copper_L%d.dxf', li, li));
                verifyTrue(testCase, isfile(dxfPath));
                if isfile(dxfPath)
                    txt = fileread(dxfPath);
                    verifyTrue(testCase, contains(txt, sprintf('ANTIPAD_L%d', li)));
                    verifyTrue(testCase, contains(txt, ['ANTIPAD_' v.name]));
                end
            end
        end
    end
end
end

function testAutomaticTerminalBridgeLayoutContract(testCase)
combos = {2, 1; 2, 2; 4, 1; 4, 2; 4, 4};
expectedOuterNames = {{'VRET'}; {'V12'}; {'VRET'}; {'V14'}; {'V12', 'V34'}};
expectedReturnNames = {{}; {}; {}; {}; {'V23'}};
outRoot = createTempOutput(testCase);
for k = 1:size(combos, 1)
    cfg = circular_fpc_default_config(struct('boardLayerCount', combos{k, 1}, 'coilLayerCount', combos{k, 2}, ...
        'outputRoot', outRoot, 'designName', sprintf('auto_bridge_%d_%d', combos{k, 1}, combos{k, 2})));
    result = circular_fpc_main(cfg);
    verifyAutomaticBridgeLayout(testCase, cfg, result, expectedOuterNames{k}, expectedReturnNames{k});
end
outRootBad = createTempOutput(testCase);
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRootBad, 'designName', 'pad_pair_infeasible', ...
    'padPairSpacing', 20)), 'CircularFPC:TerminalPlacementInvalid');
verifyFalse(testCase, isfolder(fullfile(outRootBad, 'pad_pair_infeasible')));
end

function testTerminalRotationAndScaleContract(testCase)
outRoot = createTempOutput(testCase);
angles = [0 45 135 225];
for a = angles
    cfg = circular_fpc_default_config(struct('boardLayerCount', 2, 'coilLayerCount', 1, ...
        'connectionAngleDeg', a, 'outputRoot', outRoot, 'designName', sprintf('rot_%d', a)));
    result = circular_fpc_main(cfg);
    verifyAutomaticBridgeLayout(testCase, cfg, result, {'VRET'}, {});
    verifyTrue(testCase, result.validation.passed);
    verifyGreaterThanOrEqual(testCase, result.validation.minCopperToSlotsMm, cfg.edgeClearance - 1e-9);
    verifyGreaterThanOrEqual(testCase, result.validation.minCopperSpacingMm, cfg.traceSpacing - 1e-9);
end
cfgScale = circular_fpc_default_config(struct('geometryScale', 2.0, ...
    'outputRoot', outRoot, 'designName', 'scale2'));
verifyTrue(testCase, isfield(cfgScale, 'padPairSpacing'), 'scaled config missing padPairSpacing');
if isfield(cfgScale, 'padPairSpacing')
    verifyEqual(testCase, cfgScale.padPairSpacing, 2.0, 'AbsTol', 1e-9);
end
resultScale = circular_fpc_main(cfgScale);
verifyAutomaticBridgeLayout(testCase, cfgScale, resultScale, {'VRET'}, {});
cfgPlatform = circular_fpc_default_config(struct('centerPlatformWidth', 12.0, 'centerPlatformHeight', 10.0, ...
    'outputRoot', outRoot, 'designName', 'platform_12x10'));
resultPlatform = circular_fpc_main(cfgPlatform);
verifyAutomaticBridgeLayout(testCase, cfgPlatform, resultPlatform, {'VRET'}, {});
end

function testManualCoordinatesRoundTrip(testCase)
outRoot = createTempOutput(testCase);
cfg0 = circular_fpc_default_config();
pitch = cfg0.traceWidth + cfg0.traceSpacing + cfg0.pitchMargin;
outerCenterRadius = cfg0.coilInnerDiameter / 2 + cfg0.traceWidth / 2 + (cfg0.turnsPerCoilLayer - 1) * pitch;
outerXY = outerCenterRadius * [cosd(cfg0.connectionAngleDeg), sind(cfg0.connectionAngleDeg)];
overrides = struct('boardLayerCount', 2, 'coilLayerCount', 2, ...
    'terminalPlacementMode', 'manual', ...
    'manualPadAXY', [-3 2.5], 'manualPadBXY', [3 2.5], ...
    'manualSeriesViaXY', [outerXY; 2.5 -2.5], ...
    'outputRoot', outRoot, 'designName', 'manual_ok');
result = circular_fpc_main(overrides);
padA = result.pads(strcmp({result.pads.name}, 'PAD_A'));
padB = result.pads(strcmp({result.pads.name}, 'PAD_B'));
verifyEqual(testCase, padA.xy, [-3 2.5], 'AbsTol', 1e-9);
verifyEqual(testCase, padB.xy, [3 2.5], 'AbsTol', 1e-9);
via12 = result.vias(strcmp({result.vias.name}, 'V12'));
viaOut = result.vias(strcmp({result.vias.name}, 'VOUT'));
verifyEqual(testCase, via12.xy, outerXY, 'AbsTol', 1e-9);
verifyEqual(testCase, viaOut.xy, [2.5 -2.5], 'AbsTol', 1e-9);
verifyTrue(testCase, isfield(padA, 'placementRegion'), 'PAD_A missing placementRegion');
if isfield(padA, 'placementRegion')
    verifyEqual(testCase, padA.placementRegion, 'MANUAL');
end
verifyTrue(testCase, isfield(padA, 'bridgeAngleDeg'), 'PAD_A missing bridgeAngleDeg');
if isfield(padA, 'bridgeAngleDeg')
    verifyTrue(testCase, isnan(padA.bridgeAngleDeg));
end
verifyTrue(testCase, isfield(padB, 'placementRegion'), 'PAD_B missing placementRegion');
if isfield(padB, 'placementRegion')
    verifyEqual(testCase, padB.placementRegion, 'MANUAL');
end
verifyTrue(testCase, isfield(padB, 'bridgeAngleDeg'), 'PAD_B missing bridgeAngleDeg');
if isfield(padB, 'bridgeAngleDeg')
    verifyTrue(testCase, isnan(padB.bridgeAngleDeg));
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    verifyTrue(testCase, isfield(v, 'placementRegion'), sprintf('%s missing placementRegion', v.name));
    if isfield(v, 'placementRegion')
        verifyEqual(testCase, v.placementRegion, 'MANUAL');
    end
    verifyTrue(testCase, isfield(v, 'bridgeAngleDeg'), sprintf('%s missing bridgeAngleDeg', v.name));
    if isfield(v, 'bridgeAngleDeg')
        verifyTrue(testCase, isnan(v.bridgeAngleDeg));
    end
end
verifyExportedTerminalMetadata(testCase, result);
verifyPhysicalSeriesRoute(testCase, result, [1 2]);
verifyError(testCase, @() circular_fpc_main(struct('boardLayerCount', 2, 'coilLayerCount', 2, ...
    'terminalPlacementMode', 'manual', 'manualPadAXY', [50 50], ...
    'outputRoot', outRoot, 'designName', 'manual_bad')), 'CircularFPC:TerminalPlacementInvalid');
end

function testExportContractAndDxfReadback(testCase)
outRoot = createTempOutput(testCase);
startEpochSecond = floor(now * 86400);
cfg = circular_fpc_default_config(struct('outputRoot', outRoot, 'designName', 'cfpc_red_export'));
result = circular_fpc_main(cfg);
out = fullfile(outRoot, 'cfpc_red_export');
boardDxf = fullfile(out, 'dxf', '00_board_outline.dxf');
verifyTrue(testCase, isfile(boardDxf), sprintf('missing %s', boardDxf));
for k = 1:cfg.boardLayerCount
    layerDxf = fullfile(out, 'dxf', sprintf('L%d', k), sprintf('%02d_copper_L%d.dxf', k, k));
    verifyTrue(testCase, isfile(layerDxf), sprintf('missing %s', layerDxf));
end
previewFull = fullfile(out, 'previews', '01_preview_full.svg');
previewZone = fullfile(out, 'previews', '02_preview_connection_zone.svg');
verifyTrue(testCase, isfile(previewFull));
verifyTrue(testCase, isfile(previewZone));
csvPadVia = fullfile(out, 'reports', '01_pad_via_coordinates.csv');
csvLayerMap = fullfile(out, 'reports', '02_layer_map.csv');
txtSummary = fullfile(out, 'reports', '03_design_summary.txt');
csvTurnScan = fullfile(out, 'reports', '04_turn_scan.csv');
txtValidation = fullfile(out, 'reports', '05_validation_report.txt');
statusFile = fullfile(out, 'generation_status.txt');
reportFiles = {csvPadVia, csvLayerMap, txtSummary, csvTurnScan, txtValidation, statusFile};
for r = 1:numel(reportFiles)
    verifyTrue(testCase, isfile(reportFiles{r}), sprintf('missing %s', reportFiles{r}));
    d = dir(reportFiles{r});
    verifyEqual(testCase, numel(d), 1);
    verifyGreaterThanOrEqual(testCase, round(d.datenum * 86400), startEpochSecond);
end
boardTxt = fileread(boardDxf);
lines = strtrim(strsplit(boardTxt, newline));
insIdx = find(strcmp(lines, '$INSUNITS'), 1);
verifyTrue(testCase, ~isempty(insIdx) && insIdx + 2 <= numel(lines));
verifyEqual(testCase, lines{insIdx + 1}, '70');
verifyEqual(testCase, str2double(lines{insIdx + 2}), 4);
closedCount = 0;
k = 1;
while k + 1 <= numel(lines)
    if strcmp(lines{k}, '0') && strcmp(lines{k + 1}, 'LWPOLYLINE')
        j = k + 2;
        closed = false;
        while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
            if strcmp(lines{j}, '70') && str2double(lines{j + 1}) == 1
                closed = true;
            end
            j = j + 2;
        end
        if closed
            closedCount = closedCount + 1;
        end
        k = j;
    else
        k = k + 1;
    end
end
verifyEqual(testCase, closedCount, 5);
l1Dxf = fullfile(out, 'dxf', 'L1', '01_copper_L1.dxf');
l1Txt = fileread(l1Dxf);
verifyTrue(testCase, numel(strfind(l1Txt, 'CIRCLE')) >= 2);
l1Lines = strtrim(strsplit(l1Txt, newline));
widthVals = [];
k = 1;
while k + 1 <= numel(l1Lines)
    if strcmp(l1Lines{k}, '0') && strcmp(l1Lines{k + 1}, 'LWPOLYLINE')
        j = k + 2;
        while j + 1 <= numel(l1Lines) && ~strcmp(l1Lines{j}, '0')
            if strcmp(l1Lines{j}, '40')
                widthVals(end + 1) = str2double(l1Lines{j + 1}); %#ok<AGROW>
            end
            j = j + 2;
        end
        k = j;
    else
        k = k + 1;
    end
end
verifyTrue(testCase, ~isempty(widthVals) && any(abs(widthVals - cfg.traceWidth) < 1e-9));
fullDoc = xmlread(previewFull);
rootFull = fullDoc.getDocumentElement;
verifyEqual(testCase, char(rootFull.getTagName), 'svg');
zoneDoc = xmlread(previewZone);
rootZone = zoneDoc.getDocumentElement;
verifyEqual(testCase, char(rootZone.getTagName), 'svg');
verifyExportedTerminalMetadata(testCase, result);
tPadVia = readtable(csvPadVia);
verifyGreaterThanOrEqual(testCase, height(tPadVia), 2);
verifyTrue(testCase, any(strcmp(tPadVia.Properties.VariableNames, 'antipadDiameterMm')));
verifyTrue(testCase, any(strcmp(tPadVia.Properties.VariableNames, 'role')));
tLayer = readtable(csvLayerMap);
verifyEqual(testCase, height(tLayer), cfg.boardLayerCount);
summaryTxt = fileread(txtSummary);
verifyTrue(testCase, contains(summaryTxt, 'boardOuterDiameter'));
verifyTrue(testCase, contains(summaryTxt, 'connectionAngleDeg'));
verifyTrue(testCase, contains(summaryTxt, 'padPairSpacing'));
verifyTrue(testCase, contains(summaryTxt, 'placementRegion='));
verifyTrue(testCase, contains(summaryTxt, 'bridgeAngleDeg='));
turnTxt = fileread(csvTurnScan);
verifyTrue(testCase, contains(turnTxt, '8'));
valTxt = fileread(txtValidation);
verifyTrue(testCase, contains(lower(valTxt), 'pass'));
statusTxt = fileread(statusFile);
verifyTrue(testCase, contains(lower(statusTxt), 'success'));
cfg2 = circular_fpc_default_config(struct('outputRoot', outRoot, 'designName', 'cfpc_red_nopreview', 'enablePreview', false));
circular_fpc_main(cfg2);
out2 = fullfile(outRoot, 'cfpc_red_nopreview');
verifyFalse(testCase, isfile(fullfile(out2, 'previews', '01_preview_full.svg')));
verifyFalse(testCase, isfile(fullfile(out2, 'previews', '02_preview_connection_zone.svg')));
verifyTrue(testCase, isfile(fullfile(out2, 'dxf', '00_board_outline.dxf')));
verifyTrue(testCase, isfile(fullfile(out2, 'reports', '05_validation_report.txt')));
verifyTrue(testCase, isfile(fullfile(out2, 'generation_status.txt')));
end

function testFailureLeavesNoFormalOutput(testCase)
outRoot = createTempOutput(testCase);
formalDir = fullfile(outRoot, 'cfpc_fail');
overrides = struct('outputRoot', outRoot, 'designName', 'cfpc_fail', 'geometryScale', 0.05);
verifyError(testCase, @() circular_fpc_main(overrides), 'CircularFPC:GeometryInfeasible');
verifyFalse(testCase, isfolder(formalDir));
if isfolder(outRoot)
    entries = dir(outRoot);
    verifyEqual(testCase, numel(entries), 2);
end
end

function testFigurePlotContract(testCase)
% circular_fpc_plot 弹出图像窗口（总览 + 每层视图），错误输入报错。
% 走公开入口 circular_fpc_main（private 的 engine/export 对 tests/ 不可见）。
outRoot = tempname;
result = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'plot_contract', ...
    'boardLayerCount', 4, 'coilLayerCount', 4));
close(findobj('Type', 'figure', 'Name', 'Circular FPC Coil'));
circular_fpc_plot(result);
fig = findobj('Type', 'figure', 'Name', 'Circular FPC Coil');
verifyEqual(testCase, numel(fig), 1);
verifyTrue(testCase, isgraphics(fig(1), 'figure'));
axesList = findobj(fig(1), 'Type', 'axes');
verifyEqual(testCase, numel(axesList), numel(result.layerPaths) + 1);
close(fig(1));
verifyError(testCase, @() circular_fpc_plot(), 'CircularFPC:Plot');
% enableFigure 配置默认开启且可显式关闭
cfg2 = circular_fpc_default_config(struct('enableFigure', false));
verifyFalse(testCase, cfg2.enableFigure);
end

function testExampleScriptAndDocumentation(testCase)
projectRoot = testCase.TestData.projectRoot;
scriptPath = fullfile(projectRoot, 'examples', 'generate_all_variants.m');
verifyTrue(testCase, isfile(scriptPath));
if ~isfile(scriptPath)
    return;
end
outRoot = createTempOutput(testCase);
outputRoot = outRoot;
run(scriptPath);
combos = [2 1; 2 2; 4 1; 4 2; 4 4];
expectedActive = {[1]; [1 2]; [1]; [1 4]; [1 2 3 4]};
verifyEqual(testCase, numel(variantResults), 5);
for k = 1:5
    r = variantResults{k};
    verifyEqual(testCase, r.boardLayerCount, combos(k, 1));
    verifyEqual(testCase, r.coilLayerCount, combos(k, 2));
    verifyEqual(testCase, r.activeCoilLayers, expectedActive{k});
    verifyTrue(testCase, r.validation.passed);
    verifyTrue(testCase, isfile(fullfile(r.outputPath, 'dxf', '00_board_outline.dxf')));
    for li = 1:r.boardLayerCount
        verifyTrue(testCase, isfile(fullfile(r.outputPath, 'dxf', sprintf('L%d', li), ...
            sprintf('%02d_copper_L%d.dxf', li, li))));
    end
    verifyTrue(testCase, isfile(fullfile(r.outputPath, 'previews', '01_preview_full.svg')));
    verifyTrue(testCase, isfile(fullfile(r.outputPath, 'previews', '02_preview_connection_zone.svg')));
    for li = 1:r.boardLayerCount
        if li == 1
            role = 'top';
        elseif li == r.boardLayerCount
            role = 'bottom';
        else
            role = sprintf('inner%d', li - 1);
        end
        verifyTrue(testCase, isfile(fullfile(r.outputPath, 'previews', ...
            sprintf('%02d_preview_layer_L%d_%s.svg', 2 + li, li, role))), ...
            sprintf('missing per-layer preview for L%d', li));
    end
    for f = {'01_pad_via_coordinates.csv', '02_layer_map.csv', '03_design_summary.txt', ...
            '04_turn_scan.csv', '05_validation_report.txt'}
        verifyTrue(testCase, isfile(fullfile(r.outputPath, 'reports', f{1})));
    end
    verifyTrue(testCase, isfile(fullfile(r.outputPath, 'generation_status.txt')));
    verifyExportedTerminalMetadata(testCase, r);
end
readmePath = fullfile(projectRoot, 'README.md');
gitignorePath = fullfile(projectRoot, '.gitignore');
verifyTrue(testCase, isfile(readmePath));
verifyTrue(testCase, isfile(gitignorePath));
if isfile(readmePath)
    readmeTxt = fileread(readmePath);
    for kw = {'geometryScale', 'manualSeriesViaXY', 'PAD_A', 'Gerber', '2/1', '2/2', '4/1', '4/2', '4/4', ...
            'padPairSpacing', 'placementRegion', 'bridgeAngleDeg', 'ENTRY_BRIDGE', 'RETURN_BRIDGE', ...
            'OUTER_COIL_ENDPOINT', '双通道'}
        verifyTrue(testCase, contains(readmeTxt, kw{1}));
    end
end
if isfile(gitignorePath)
    verifyTrue(testCase, contains(fileread(gitignorePath), '/outputs/'));
end
end

function outRoot = createTempOutput(testCase)
tmpRoot = tempname;
mkdir(tmpRoot);
testCase.addTeardown(@removeTempOutput, tmpRoot);
outRoot = fullfile(tmpRoot, 'out');
mkdir(outRoot);
end

function removeTempOutput(path)
if isfolder(path)
    rmdir(path, 's');
end
end

function verifyPhysicalSeriesRoute(testCase, result, activeLayers)
verifyTrue(testCase, isfield(result, 'seriesRoute'));
if ~isfield(result, 'seriesRoute')
    return;
end
route = result.seriesRoute;
verifyTrue(testCase, ~isempty(route));
if isempty(route)
    return;
end
reqFields = {'name', 'kind', 'startXY', 'endXY', 'startLayer', 'endLayer'};
haveFields = all(ismember(reqFields, fieldnames(route)));
verifyTrue(testCase, haveFields);
if ~haveFields
    return;
end
verifyEqual(testCase, route(1).kind, 'PAD');
verifyEqual(testCase, route(1).name, 'PAD_A');
verifyEqual(testCase, route(end).kind, 'PAD');
verifyEqual(testCase, route(end).name, 'PAD_B');
for k = 1:numel(route)
    verifyTrue(testCase, isnumeric(route(k).startXY) && isequal(size(route(k).startXY), [1 2]) && all(isfinite(route(k).startXY)));
    verifyTrue(testCase, isnumeric(route(k).endXY) && isequal(size(route(k).endXY), [1 2]) && all(isfinite(route(k).endXY)));
    verifyTrue(testCase, isnumeric(route(k).startLayer) && isscalar(route(k).startLayer));
    verifyTrue(testCase, isnumeric(route(k).endLayer) && isscalar(route(k).endLayer));
end
for k = 1:numel(route) - 1
    verifyTrue(testCase, norm(route(k).endXY - route(k + 1).startXY) <= 1e-9);
    verifyEqual(testCase, route(k).endLayer, route(k + 1).startLayer);
end
coilIdx = find(strcmp({route.kind}, 'COIL'));
verifyEqual(testCase, numel(coilIdx), numel(activeLayers));
for c = 1:numel(coilIdx)
    k = coilIdx(c);
    verifyEqual(testCase, route(k).name, sprintf('COIL_L%d', activeLayers(c)));
    rStart = norm(route(k).startXY);
    rEnd = norm(route(k).endXY);
    if mod(c, 2) == 1
        verifyTrue(testCase, rStart < rEnd);
    else
        verifyTrue(testCase, rStart > rEnd);
    end
end
verifyTrue(testCase, isfield(result, 'validation'));
if isfield(result, 'validation')
    verifyTrue(testCase, isfield(result.validation, 'maxSeriesContinuityErrorMm'));
    verifyTrue(testCase, isfield(result.validation, 'maxConnectionTurnDeg'));
    verifyTrue(testCase, result.validation.uniqueSeriesNetwork);
    if isfield(result.validation, 'maxSeriesContinuityErrorMm')
        verifyTrue(testCase, result.validation.maxSeriesContinuityErrorMm <= 1e-9);
    end
    if isfield(result.validation, 'maxConnectionTurnDeg')
        verifyTrue(testCase, result.validation.maxConnectionTurnDeg <= 10);
    end
end
end
function verifyAutomaticBridgeLayout(testCase, cfg, result, expectedOuterNames, expectedReturnNames)
theta = cfg.connectionAngleDeg;
u = [cosd(theta), sind(theta)];
t = [-sind(theta), cosd(theta)];
halfChannel = (cfg.traceWidth + cfg.traceSpacing) / 2;
padA = findTerminalByName(result.pads, 'PAD_A');
padB = findTerminalByName(result.pads, 'PAD_B');
verifyEqual(testCase, numel(padA), 1, 'PAD_A must be unique');
verifyEqual(testCase, numel(padB), 1, 'PAD_B must be unique');
if numel(padA) ~= 1 || numel(padB) ~= 1
    return;
end
verifyEqual(testCase, padA.layer, 1);
verifyTrue(testCase, padA.removable);
verifyEqual(testCase, padB.layer, 1);
verifyTrue(testCase, padB.removable);
verifyTrue(testCase, isfield(cfg, 'padPairSpacing'), 'config missing padPairSpacing');
verifyTrue(testCase, isfield(padA, 'placementRegion'), 'PAD_A missing placementRegion');
verifyTrue(testCase, isfield(padA, 'bridgeAngleDeg'), 'PAD_A missing bridgeAngleDeg');
verifyTrue(testCase, isfield(padB, 'placementRegion'), 'PAD_B missing placementRegion');
verifyTrue(testCase, isfield(padB, 'bridgeAngleDeg'), 'PAD_B missing bridgeAngleDeg');
d = norm(padB.xy - padA.xy);
if isfield(cfg, 'padPairSpacing')
    verifyEqual(testCase, d, cfg.padPairSpacing, 'AbsTol', 1e-6);
else
    verifyTrue(testCase, false, sprintf('PAD spacing %.6f cannot be checked: config missing padPairSpacing', d));
end
if d > 0
    dirAB = (padB.xy - padA.xy) / d;
    verifyEqual(testCase, dirAB, t, 'AbsTol', 1e-6);
end
pairCenter = (padA.xy + padB.xy) / 2;
verifyTrue(testCase, abs(dot(pairCenter, t)) <= 1e-6, ...
    sprintf('pairCenter must lie on bridge axis (tangent projection %.6f)', dot(pairCenter, t)));
verifyTrue(testCase, dot(pairCenter, u) > 0, ...
    sprintf('pairCenter must be on positive radial side (projection %.6f)', dot(pairCenter, u)));
if isfield(padA, 'placementRegion') && isfield(padB, 'placementRegion')
    verifyEqual(testCase, padA.placementRegion, 'CENTER_PLATFORM_NEAR_ENTRY_BRIDGE');
    verifyEqual(testCase, padB.placementRegion, 'CENTER_PLATFORM_NEAR_ENTRY_BRIDGE');
end
if isfield(padA, 'bridgeAngleDeg') && isfield(padB, 'bridgeAngleDeg')
    verifyAngleMod360(testCase, padA.bridgeAngleDeg, theta, 'PAD_A bridgeAngleDeg');
    verifyAngleMod360(testCase, padB.bridgeAngleDeg, theta, 'PAD_B bridgeAngleDeg');
end
vout = findTerminalByName(result.vias, 'VOUT');
verifyEqual(testCase, numel(vout), 1, 'exactly one VOUT via');
if numel(vout) ~= 1
    return;
end
verifyTrue(testCase, isfield(vout, 'placementRegion'), 'VOUT missing placementRegion');
verifyTrue(testCase, isfield(vout, 'bridgeAngleDeg'), 'VOUT missing bridgeAngleDeg');
if isfield(vout, 'placementRegion')
    verifyEqual(testCase, vout.placementRegion, 'ENTRY_BRIDGE');
end
if isfield(vout, 'bridgeAngleDeg')
    verifyAngleMod360(testCase, vout.bridgeAngleDeg, theta, 'VOUT bridgeAngleDeg');
end
verifyEqual(testCase, dot(vout.xy, t), halfChannel, 'AbsTol', 1e-6);
for k = 1:numel(expectedOuterNames)
    v = findTerminalByName(result.vias, expectedOuterNames{k});
    verifyEqual(testCase, numel(v), 1, sprintf('exactly one %s via', expectedOuterNames{k}));
    if numel(v) ~= 1
        continue;
    end
    verifyTrue(testCase, isfield(v, 'placementRegion'), sprintf('%s missing placementRegion', v.name));
    verifyTrue(testCase, isfield(v, 'bridgeAngleDeg'), sprintf('%s missing bridgeAngleDeg', v.name));
    if isfield(v, 'placementRegion')
        verifyEqual(testCase, v.placementRegion, 'OUTER_COIL_ENDPOINT');
    end
    if isfield(v, 'bridgeAngleDeg')
        if strcmp(v.name, 'V34')
            verifyAngleMod360(testCase, v.bridgeAngleDeg, theta + 180, 'V34 bridgeAngleDeg');
        else
            verifyAngleMod360(testCase, v.bridgeAngleDeg, theta, sprintf('%s bridgeAngleDeg', v.name));
        end
    end
    verifyEqual(testCase, v.xy, result.layerPaths(v.fromLayer).coilXY(end, :), 'AbsTol', 1e-9);
end
for k = 1:numel(expectedReturnNames)
    v = findTerminalByName(result.vias, expectedReturnNames{k});
    verifyEqual(testCase, numel(v), 1, sprintf('exactly one %s via', expectedReturnNames{k}));
    if numel(v) ~= 1
        continue;
    end
    verifyTrue(testCase, isfield(v, 'placementRegion'), sprintf('%s missing placementRegion', v.name));
    verifyTrue(testCase, isfield(v, 'bridgeAngleDeg'), sprintf('%s missing bridgeAngleDeg', v.name));
    if isfield(v, 'placementRegion')
        verifyEqual(testCase, v.placementRegion, 'RETURN_BRIDGE');
    end
    if isfield(v, 'bridgeAngleDeg')
        verifyAngleMod360(testCase, v.bridgeAngleDeg, theta + 180, sprintf('%s bridgeAngleDeg', v.name));
    end
    tReturn = [-sind(theta + 180), cosd(theta + 180)];
    verifyTrue(testCase, abs(dot(v.xy, tReturn)) <= 1e-6, ...
        sprintf('%s must lie on return bridge axis (tangent projection %.6f)', v.name, dot(v.xy, tReturn)));
end
verifyTrue(testCase, result.validation.passed, sprintf('validation.passed=false: %s', strjoin(result.validation.messages, ' | ')));
verifyGreaterThanOrEqual(testCase, result.validation.minCopperToSlotsMm, cfg.edgeClearance - 1e-9);
verifyGreaterThanOrEqual(testCase, result.validation.minCopperSpacingMm, cfg.traceSpacing - 1e-9);
verifyTrue(testCase, result.validation.uniqueSeriesNetwork);
verifyTrue(testCase, result.validation.viaOverlapFree);
verifyTrue(testCase, result.validation.noZeroLengthSegments);
entry = result.seriesRoute(strcmp({result.seriesRoute.name}, 'TRACE_L1_ENTRY'));
verifyEqual(testCase, numel(entry), 1, 'seriesRoute must contain exactly one TRACE_L1_ENTRY');
if numel(entry) ~= 1
    return;
end
path = findPathByEndpoints(result.layerPaths(1).connectionPaths, entry.startXY, entry.endXY);
verifyTrue(testCase, ~isempty(path), 'TRACE_L1_ENTRY path must exist in L1 connectionPaths');
if isempty(path)
    return;
end
rProj = path * u.';
rVout = dot(vout.xy, u);
[~, idx] = min(abs(rProj - rVout));
tProj = dot(path(idx, :), t);
verifyTrue(testCase, abs(tProj - (-halfChannel)) <= 0.03, ...
    sprintf('L1 entry must follow negative channel near VOUT radial section: tangent %.6f, expected %.6f', tProj, -halfChannel));
end

function t = findTerminalByName(terminals, name)
t = terminals(strcmp({terminals.name}, name));
end

function p = findPathByEndpoints(paths, startXY, endXY)
p = [];
for k = 1:numel(paths)
    q = paths{k};
    if size(q, 1) >= 2 && norm(q(1, :) - startXY) <= 1e-9 && norm(q(end, :) - endXY) <= 1e-9
        p = q;
        return;
    end
end
end

function verifyAngleMod360(testCase, actual, expected, label)
e = mod(expected, 360);
a = mod(actual, 360);
err = abs(a - e);
err = min(err, 360 - err);
ok = err <= 1e-6;
verifyTrue(testCase, ok, sprintf('%s must be %.6f deg mod 360 (got %.6f)', label, e, a));
end

function verifyExportedTerminalMetadata(testCase, result)
% Read back CSV and both SVG artifacts and require terminal metadata (RED R1/R2/R4).
csvPath = fullfile(result.outputPath, 'reports', '01_pad_via_coordinates.csv');
verifyTrue(testCase, isfile(csvPath), sprintf('missing %s', csvPath));
if ~isfile(csvPath)
    return;
end
t = readtable(csvPath);
expectedColumns = {'name', 'xMm', 'yMm', 'diameterMm', 'drillMm', 'antipadDiameterMm', ...
    'layer', 'fromLayer', 'toLayer', 'removable', 'role', ...
    'placementRegion', 'bridgeAngleDeg'};
verifyEqual(testCase, t.Properties.VariableNames, expectedColumns, ...
    'CSV columns must be the old 11 followed by placementRegion and bridgeAngleDeg');
if ~all(ismember({'placementRegion', 'bridgeAngleDeg'}, t.Properties.VariableNames))
    return;
end
expectedHeight = numel(result.pads) + numel(result.vias);
verifyEqual(testCase, height(t), expectedHeight, 'CSV row count must equal pads+vias');
verifyEqual(testCase, numel(unique(t.name)), expectedHeight, 'CSV terminal names must be unique');
for k = 1:numel(result.pads)
    p = result.pads(k);
    row = t(strcmp(t.name, p.name), :);
    verifyEqual(testCase, height(row), 1, sprintf('%s must occur exactly once in CSV', p.name));
    if height(row) ~= 1
        continue;
    end
    verifyEqual(testCase, row.xMm, p.xy(1), 'AbsTol', 1e-6, ...
        sprintf('%s xMm must match result', p.name));
    verifyEqual(testCase, row.yMm, p.xy(2), 'AbsTol', 1e-6, ...
        sprintf('%s yMm must match result', p.name));
    verifyEqual(testCase, char(row.placementRegion), p.placementRegion, ...
        sprintf('%s placementRegion must match result', p.name));
    verifyExportedAngle(testCase, row.bridgeAngleDeg, p.bridgeAngleDeg, ...
        sprintf('%s bridgeAngleDeg', p.name));
    verifyEqual(testCase, row.diameterMm, p.diameter, 'AbsTol', 1e-6, ...
        sprintf('%s diameterMm must match result', p.name));
    verifyEqual(testCase, row.layer, p.layer, ...
        sprintf('%s layer must match result', p.name));
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    row = t(strcmp(t.name, v.name), :);
    verifyEqual(testCase, height(row), 1, sprintf('%s must occur exactly once in CSV', v.name));
    if height(row) ~= 1
        continue;
    end
    verifyEqual(testCase, row.xMm, v.xy(1), 'AbsTol', 1e-6, ...
        sprintf('%s xMm must match result', v.name));
    verifyEqual(testCase, row.yMm, v.xy(2), 'AbsTol', 1e-6, ...
        sprintf('%s yMm must match result', v.name));
    verifyEqual(testCase, char(row.placementRegion), v.placementRegion, ...
        sprintf('%s placementRegion must match result', v.name));
    verifyExportedAngle(testCase, row.bridgeAngleDeg, v.bridgeAngleDeg, ...
        sprintf('%s bridgeAngleDeg', v.name));
    verifyEqual(testCase, row.diameterMm, v.padDiameter, 'AbsTol', 1e-6, ...
        sprintf('%s diameterMm must match result', v.name));
    verifyEqual(testCase, row.fromLayer, v.fromLayer, ...
        sprintf('%s fromLayer must match result', v.name));
    verifyEqual(testCase, row.toLayer, v.toLayer, ...
        sprintf('%s toLayer must match result', v.name));
end
svgFiles = {fullfile(result.outputPath, 'previews', '01_preview_full.svg'), ...
    fullfile(result.outputPath, 'previews', '02_preview_connection_zone.svg')};
for f = svgFiles
    verifyTrue(testCase, isfile(f{1}), sprintf('missing %s', f{1}));
    if ~isfile(f{1})
        continue;
    end
    verifyTrue(testCase, ~isempty(xmlread(f{1})), ...
        sprintf('SVG must be XML-parseable: %s', f{1}));
    svgTxt = fileread(f{1});
    for k = 1:numel(result.pads)
        p = result.pads(k);
        angleStr = sprintf('%.6f', p.bridgeAngleDeg);
        verifyTrue(testCase, contains(svgTxt, sprintf('data-name="%s"', p.name)), ...
            sprintf('SVG must contain data-name for %s', p.name));
        verifyTrue(testCase, contains(svgTxt, sprintf('data-placement-region="%s"', p.placementRegion)), ...
            sprintf('SVG must contain data-placement-region for %s', p.name));
        verifyTrue(testCase, contains(svgTxt, sprintf('data-bridge-angle-deg="%s"', angleStr)), ...
            sprintf('SVG must contain data-bridge-angle-deg for %s', p.name));
        verifyTrue(testCase, contains(svgTxt, sprintf('%s [%s] angle=', p.name, p.placementRegion)), ...
            sprintf('SVG must contain visible text label for %s', p.name));
    end
    for k = 1:numel(result.vias)
        v = result.vias(k);
        angleStr = sprintf('%.6f', v.bridgeAngleDeg);
        verifyTrue(testCase, contains(svgTxt, sprintf('data-name="%s"', v.name)), ...
            sprintf('SVG must contain data-name for %s', v.name));
        verifyTrue(testCase, contains(svgTxt, sprintf('data-placement-region="%s"', v.placementRegion)), ...
            sprintf('SVG must contain data-placement-region for %s', v.name));
        verifyTrue(testCase, contains(svgTxt, sprintf('data-bridge-angle-deg="%s"', angleStr)), ...
            sprintf('SVG must contain data-bridge-angle-deg for %s', v.name));
        verifyTrue(testCase, contains(svgTxt, sprintf('%s [%s] angle=', v.name, v.placementRegion)), ...
            sprintf('SVG must contain visible text label for %s', v.name));
    end
    verifySvgTerminalLegendLayout(testCase, result, f{1});
end
end

function verifySvgTerminalLegendLayout(testCase, result, svgPath)
% RED R1/R2: SVG top legend background, per-terminal label/leader rows and
% connection-zone viewBox containment (layout contract, not pixel boxes).
doc = xmlread(svgPath);
root = doc.getDocumentElement();
vb = strtrim(char(root.getAttribute('viewBox')));
nums = str2double(strsplit(vb));
if numel(nums) ~= 4 || any(~isfinite(nums)) || nums(3) <= 0 || nums(4) <= 0
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG viewBox must have 4 finite numbers with positive width/height (got "%s").', vb);
end
xMin = nums(1);
yMin = nums(2);
xMax = nums(1) + nums(3);
yMax = nums(2) + nums(4);
xp = javax.xml.xpath.XPathFactory.newInstance().newXPath();
bgExpr = xp.compile('//*[local-name()="rect" and @class="terminal-legend-bg"]');
bgNodes = bgExpr.evaluate(doc, javax.xml.xpath.XPathConstants.NODESET);
if bgNodes.getLength() ~= 1
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG terminal legend background missing: expected exactly 1 rect class=terminal-legend-bg, found %d in %s.', ...
        bgNodes.getLength(), svgPath);
end
labelExpr = xp.compile('//*[local-name()="text" and @class="terminal-label"]');
labelNodes = labelExpr.evaluate(doc, javax.xml.xpath.XPathConstants.NODESET);
leaderExpr = xp.compile('//*[local-name()="line" and @class="terminal-leader"]');
leaderNodes = leaderExpr.evaluate(doc, javax.xml.xpath.XPathConstants.NODESET);
nTerms = numel(result.pads) + numel(result.vias);
if labelNodes.getLength() ~= nTerms
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG terminal labels missing: expected %d text class=terminal-label, found %d in %s.', ...
        nTerms, labelNodes.getLength(), svgPath);
end
if leaderNodes.getLength() ~= nTerms
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG terminal leaders missing: expected %d line class=terminal-leader, found %d in %s.', ...
        nTerms, leaderNodes.getLength(), svgPath);
end
labelByTerm = containers.Map();
for i = 0:labelNodes.getLength() - 1
    el = labelNodes.item(i);
    nm = char(el.getAttribute('data-name'));
    if isKey(labelByTerm, nm)
        error('CircularFPC:ExportReadbackFailed', 'SVG duplicate terminal-label data-name %s.', nm);
    end
    labelByTerm(nm) = el;
end
leaderByTerm = containers.Map();
for i = 0:leaderNodes.getLength() - 1
    el = leaderNodes.item(i);
    nm = char(el.getAttribute('data-name'));
    if isKey(leaderByTerm, nm)
        error('CircularFPC:ExportReadbackFailed', 'SVG duplicate terminal-leader data-name %s.', nm);
    end
    leaderByTerm(nm) = el;
end
labelX = zeros(1, nTerms);
labelY = zeros(1, nTerms);
for k = 1:numel(result.pads)
    p = result.pads(k);
    nm = char(p.name);
    if ~isKey(labelByTerm, nm) || ~isKey(leaderByTerm, nm)
        error('CircularFPC:ExportReadbackFailed', ...
            'SVG terminal label/leader missing for %s in %s.', nm, svgPath);
    end
    el = labelByTerm(nm);
    angleStr = sprintf('%.6f', p.bridgeAngleDeg);
    if ~strcmp(char(el.getAttribute('data-placement-region')), char(p.placementRegion)) || ...
            ~strcmp(char(el.getAttribute('data-bridge-angle-deg')), angleStr) || ...
            ~contains(char(el.getTextContent()), sprintf('%s [%s] angle=', nm, char(p.placementRegion)))
        error('CircularFPC:ExportReadbackFailed', ...
            'SVG terminal-label metadata or visible text mismatch for %s in %s.', nm, svgPath);
    end
    fs = str2double(char(el.getAttribute('font-size')));
    if ~isfinite(fs) || abs(fs - 0.22) > 1e-12
        error('CircularFPC:ExportReadbackFailed', ...
            'SVG terminal-label font-size must be 0.22 for %s (got %g).', nm, fs);
    end
    labelX(k) = str2double(char(el.getAttribute('x')));
    labelY(k) = str2double(char(el.getAttribute('y')));
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    nm = char(v.name);
    if ~isKey(labelByTerm, nm) || ~isKey(leaderByTerm, nm)
        error('CircularFPC:ExportReadbackFailed', ...
            'SVG terminal label/leader missing for %s in %s.', nm, svgPath);
    end
    el = labelByTerm(nm);
    angleStr = sprintf('%.6f', v.bridgeAngleDeg);
    if ~strcmp(char(el.getAttribute('data-placement-region')), char(v.placementRegion)) || ...
            ~strcmp(char(el.getAttribute('data-bridge-angle-deg')), angleStr) || ...
            ~contains(char(el.getTextContent()), sprintf('%s [%s] angle=', nm, char(v.placementRegion)))
        error('CircularFPC:ExportReadbackFailed', ...
            'SVG terminal-label metadata or visible text mismatch for %s in %s.', nm, svgPath);
    end
    fs = str2double(char(el.getAttribute('font-size')));
    if ~isfinite(fs) || abs(fs - 0.22) > 1e-12
        error('CircularFPC:ExportReadbackFailed', ...
            'SVG terminal-label font-size must be 0.22 for %s (got %g).', nm, fs);
    end
    labelX(numel(result.pads) + k) = str2double(char(el.getAttribute('x')));
    labelY(numel(result.pads) + k) = str2double(char(el.getAttribute('y')));
end
if any(~isfinite(labelX)) || any(~isfinite(labelY))
    error('CircularFPC:ExportReadbackFailed', 'SVG terminal-label x/y must be finite in %s.', svgPath);
end
if any(abs(labelX(2:end) - labelX(1)) > 1e-9)
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG terminal-label x must be identical for all labels in %s.', svgPath);
end
if any(diff(labelY) < 0.35 - 1e-9)
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG terminal-label rows must advance at least 0.35 mm in %s.', svgPath);
end
if any(labelX < xMin | labelX > xMax | labelY < yMin | labelY > yMax)
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG terminal-label anchor must lie inside viewBox in %s.', svgPath);
end
bg = bgNodes.item(0);
bgX = str2double(char(bg.getAttribute('x')));
bgY = str2double(char(bg.getAttribute('y')));
bgW = str2double(char(bg.getAttribute('width')));
bgH = str2double(char(bg.getAttribute('height')));
if any(~isfinite([bgX bgY bgW bgH])) || bgW <= 0 || bgH <= 0
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG terminal legend background must have finite x/y/width/height with positive size in %s.', svgPath);
end
if any(labelX < bgX | labelX > bgX + bgW | labelY < bgY | labelY > bgY + bgH)
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG terminal legend background must contain all label anchors in %s.', svgPath);
end
[~, svgName] = fileparts(svgPath);
if strcmp(svgName, '02_preview_connection_zone')
    w = result.effectiveDimensions.centerPlatformWidth;
    h = result.effectiveDimensions.centerPlatformHeight;
    if xMin > -w / 2 - 2 || yMin > -h / 2 - 2 || ...
            xMax < w / 2 + 2 || yMax < h / 2 + 2
        error('CircularFPC:ExportReadbackFailed', ...
            'connection-zone viewBox must not shrink center platform +/-2 mm range (got x=[%.6f %.6f], y=[%.6f %.6f]).', ...
            xMin, xMax, yMin, yMax);
    end
    for k = 1:numel(result.pads)
        p = result.pads(k);
        r = p.diameter / 2;
        if p.xy(1) - r < xMin - 1e-9 || p.xy(1) + r > xMax + 1e-9 || ...
                p.xy(2) - r < yMin - 1e-9 || p.xy(2) + r > yMax + 1e-9
            error('CircularFPC:ExportReadbackFailed', ...
                'connection-zone viewBox clips pad %s (center [%.6f %.6f], r=%.6f).', ...
                p.name, p.xy(1), p.xy(2), r);
        end
    end
    for k = 1:numel(result.vias)
        v = result.vias(k);
        r = v.padDiameter / 2;
        if v.xy(1) - r < xMin - 1e-9 || v.xy(1) + r > xMax + 1e-9 || ...
                v.xy(2) - r < yMin - 1e-9 || v.xy(2) + r > yMax + 1e-9
            error('CircularFPC:ExportReadbackFailed', ...
                'connection-zone viewBox clips via %s (center [%.6f %.6f], r=%.6f).', ...
                v.name, v.xy(1), v.xy(2), r);
        end
    end
end
end

function verifyExportedAngle(testCase, actual, expected, label)
% Readback angle value must match result: NaN maps to NaN, finite within 1e-6.
if isnan(expected)
    verifyTrue(testCase, isnan(actual), sprintf('%s must read back as NaN', label));
else
    verifyEqual(testCase, actual, expected, 'AbsTol', 1e-6, label);
end
end
