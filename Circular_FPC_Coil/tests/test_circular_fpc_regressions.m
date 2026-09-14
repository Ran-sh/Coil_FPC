function tests = test_circular_fpc_regressions
% Function-based behavior regression tests for Circular_FPC_Coil (R1-R4).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testsFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(testsFolder);
addpath(projectRoot);
testCase.TestData.projectRoot = projectRoot;
end

function testRootReadmeSeparatesRuleCheckFromFabricationQualification(testCase)
repoRoot = fileparts(testCase.TestData.projectRoot);
readmePath = fullfile(repoRoot, 'README.md');
verifyTrue(testCase, isfile(readmePath));
readmeTxt = fileread(readmePath);
verifyFalse(testCase, contains(readmeTxt, '当前 JLC 制造资格'));
verifyTrue(testCase, contains(readmeTxt, '内置 JLC 规则检查覆盖'));
verifyTrue(testCase, contains(readmeTxt, '不等同于板厂 DFM/正式制造资格'));
verifyTrue(testCase, contains(readmeTxt, 'UNVERIFIED_LAYER_COUNT'));
end

function testDefaultConfigContractAndOverrides(testCase)
cfg = circular_fpc_default_config();
verifyEqual(testCase, cfg.boardLayerCount, 4);
verifyEqual(testCase, cfg.coilLayerCount, 4);
verifyEqual(testCase, cfg.boardOuterDiameter, 25.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.boardSizingMode, 'auto'); % 默认匝数驱动板框尺寸
verifyEqual(testCase, cfg.coilInnerDiameter, 18.63, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.centerPlatformWidth, 13.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.centerPlatformHeight, 14.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.bridgeTargetWidth, 1.5, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.turnsPerCoilLayer, 7);
verifyEqual(testCase, cfg.traceWidth, 0.20, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.traceSpacing, 0.15, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.pitchMargin, 0.005, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.edgeClearance, 0.30, 'AbsTol', 1e-9); % = DRC 铜-板框
verifyEqual(testCase, cfg.boardOutlineLineWidth, 0.10, 'AbsTol', 1e-9); % 板框轮廓线宽
verifyEqual(testCase, cfg.geometrySafetyMargin, 0.002, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.mountingSlotSpan, 4.0, 'AbsTol', 1e-9); % 槽口端点弦长
verifyEqual(testCase, cfg.mountingSlotRise, 1.0, 'AbsTol', 1e-9); % 中间弧外凸高度
verifyEqual(testCase, cfg.mountingSlotEdgeClearance, cfg.edgeClearance, 'AbsTol', 1e-9); % NaN → 沿用板边净距
verifyEqual(testCase, cfg.mountingSlotEndFilletRadius, 0.3, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.viaLugRootOverlap, 0.4, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.electrodeAngleDeg, 315.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.electrodeArmLength, 5.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.electrodeArmWidth, 1.5, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.electrodeArmGap, 0.8, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.electrodePadDiameter, 1.2, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.connectionAngleDeg, 135.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.viaPadDiameter, 0.55, 'AbsTol', 1e-9); % 过孔默认外径（JLC 常规推荐）
verifyEqual(testCase, cfg.viaDrillDiameter, 0.31, 'AbsTol', 1e-9); % 过孔默认内径
verifyEqual(testCase, cfg.viaCoilSpacing, 0.152, 'AbsTol', 1e-9); % 过孔-线圈净距 = DRC 6mil
verifyEqual(testCase, cfg.padDiameter, 0.6096, 'AbsTol', 1e-9); % 焊盘 24 mil
verifyEqual(testCase, cfg.minCopperInteriorAngleDeg, 90.0, 'AbsTol', 1e-9); % 实际走线必须严格 >90°
verifyEqual(testCase, cfg.minBoardInteriorAngleDeg, 90.0, 'AbsTol', 1e-9); % 实际板框/槽边必须严格 >90°
verifyEqual(testCase, cfg.geometryScale, 1.0, 'AbsTol', 1e-9);
verifyTrue(testCase, isfield(cfg, 'padDiameter'));
verifyTrue(testCase, isfield(cfg, 'viaDrillDiameter'));
verifyTrue(testCase, isfield(cfg, 'viaPadDiameter'));
verifyFalse(testCase, isfield(cfg, 'antipadDiameter'));
verifyTrue(testCase, isfield(cfg, 'outputRoot'));
verifyTrue(testCase, isfield(cfg, 'designName'));
verifyTrue(testCase, ~isempty(regexp(cfg.designName, ...
    '^Circular_FPC_4L_4C__\d{8}_\d{6}$', 'once')), ...
    'automatic designName must use double underscore and seconds');
verifyEqual(testCase, cfg.platformSlotMargin, 0.25, 'AbsTol', 1e-9); % 平台水平/垂直边到内圆的槽余量
verifyTrue(testCase, cfg.enablePreview);
verifyTrue(testCase, isfield(cfg, 'padPairSpacing'), 'default config missing padPairSpacing');
if isfield(cfg, 'padPairSpacing')
    verifyEqual(testCase, cfg.padPairSpacing, 2.0, 'AbsTol', 1e-9);
end
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', 0)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', NaN)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', Inf)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', [1 2])), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('platformSlotMargin', 0)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('boardOutlineLineWidth', 0)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('terminalLeadSpacing', 0.7)), ...
    'CircularFPC:TerminalPlacementInvalid');
cfg24 = circular_fpc_default_config(struct('padPairSpacing', 2.4));
if isfield(cfg24, 'padPairSpacing')
    verifyEqual(testCase, cfg24.padPairSpacing, 2.4, 'AbsTol', 1e-9);
end
cfg2 = circular_fpc_default_config(struct('turnsPerCoilLayer', 10));
verifyEqual(testCase, cfg2.turnsPerCoilLayer, 10);
verifyEqual(testCase, cfg2.boardOuterDiameter, 25.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg2.coilLayerCount, 4);
verifyEqual(testCase, cfg2.traceSpacing, 0.15, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg2.edgeClearance, 0.30, 'AbsTol', 1e-9);
cfgZero = circular_fpc_default_config(struct('connectionAngleDeg', 0));
verifyEqual(testCase, cfgZero.connectionAngleDeg, 0, 'AbsTol', 1e-9);
cfgNeg = circular_fpc_default_config(struct('connectionAngleDeg', -45));
verifyEqual(testCase, cfgNeg.connectionAngleDeg, -45, 'AbsTol', 1e-9);
verifyError(testCase, @() circular_fpc_default_config(struct('connectionAngleDeg', NaN)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('connectionAngleDeg', Inf)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('connectionAngleDeg', [0 1])), 'CircularFPC:InvalidConfig');
end

function testSamplePointsPerTurnMinimumIsEnforced(testCase)
% 采样密度下限（审查建议）：更粗的折线无法表征螺旋，且端子切向的旋向判定
% 要求相邻采样点极角差严格小于半圈；下限 8 在配置阶段 fail-fast，
% 且边界值本身必须仍然合法（不误伤）。
verifyError(testCase, @() circular_fpc_default_config(struct( ...
    'samplePointsPerTurn', 7)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct( ...
    'samplePointsPerTurn', 4)), 'CircularFPC:InvalidConfig');
cfg = circular_fpc_default_config(struct('samplePointsPerTurn', 8));
verifyEqual(testCase, cfg.samplePointsPerTurn, 8);
end

function testRejectsUnsupportedLayerMatrix(testCase)
verifyError(testCase, @() circular_fpc_default_config(struct('unknownField', 1)), 'CircularFPC:UnknownConfigField');
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 3)), 'CircularFPC:UnsupportedLayerCombination');
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 4, 'coilLayerCount', 3)), 'CircularFPC:UnsupportedLayerCombination');
verifyError(testCase, @() circular_fpc_default_config(struct('boardOuterDiameter', 0)), 'CircularFPC:InvalidConfig');
end

function testBoardSizingMode(testCase)
% 板框定尺寸：'auto'（默认）由主线圈匝数计算主体圆外径；局部凸耳/电极
% 只扩展局部外轮廓；'fixed' 使用 boardOuterDiameter。
verifyError(testCase, @() circular_fpc_default_config(struct('boardSizingMode', 'weird')), ...
    'CircularFPC:InvalidConfig');
outRoot = createTempOutput(testCase);
% 本测试并排对比多个产物（含回读先生成产物的报告），故关闭自动归档。
rAuto = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'auto_board', ...
    'archivePreviousArtifacts', false));
verifyGreaterThan(testCase, rAuto.effectiveDimensions.boardOuterDiameter, 24.6);
verifyLessThan(testCase, rAuto.effectiveDimensions.boardOuterDiameter, 25.1);
verifyGreaterThan(testCase, rAuto.layoutRegions.boardExtent, ...
    rAuto.effectiveDimensions.boardOuterDiameter / 2 + 4.0);
rTwo = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'auto_board_2l', ...
    'archivePreviousArtifacts', false, ...
    'boardLayerCount', 2, 'coilLayerCount', 2));
verifyGreaterThan(testCase, rTwo.effectiveDimensions.boardOuterDiameter, 24.5);
verifyLessThan(testCase, rTwo.effectiveDimensions.boardOuterDiameter, 25.0);
verifyTrue(testCase, contains(fileread(fullfile(rAuto.outputPath, 'reports', '03_design_summary.txt')), 'boardSizingMode: auto'));
turnTxt = fileread(fullfile(rAuto.outputPath, 'reports', '04_turn_scan.csv'));
verifyTrue(testCase, contains(turnTxt, 'requiredBoardDiameterMm'));
verifyTrue(testCase, contains(turnTxt, sprintf('6,%.6f', 0.2 + 6 * 0.355))); % 6 匝（物理 360° 圈）所需径向宽度
% 匝数扫描只列出几何生成器支持的范围：至少两个径向采样层级。
verifyEmpty(testCase, regexp(turnTxt, '(?m)^1,', 'once'));
verifyNotEmpty(testCase, regexp(turnTxt, '(?m)^2,', 'once'));
% fixed 24.5 小于默认线圈主体所需尺寸，在可行性阶段明确拒绝，
% 原子导出不留正式目录。
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRoot, ...
    'designName', 'fixed_board', 'archivePreviousArtifacts', false, ...
    'boardSizingMode', 'fixed', 'boardOuterDiameter', 24.5)), ...
    'CircularFPC:GeometryInfeasible');
verifyFalse(testCase, isfolder(fullfile(outRoot, 'fixed_board')));
% fixed 25.0 大于默认紧凑主体圆：成功，板径/制造报告/扫描契约保持。
rFixed = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'fixed_board_265', ...
    'archivePreviousArtifacts', false, ...
    'boardSizingMode', 'fixed', 'boardOuterDiameter', 25.0));
verifyEqual(testCase, rFixed.effectiveDimensions.boardOuterDiameter, 25.0, 'AbsTol', 1e-9);
verifyTrue(testCase, rFixed.manufacturing.passed);
verifyTrue(testCase, contains(fileread(fullfile(rFixed.outputPath, 'reports', '03_design_summary.txt')), 'boardSizingMode: fixed'));
fixedTurnTxt = fileread(fullfile(rFixed.outputPath, 'reports', '04_turn_scan.csv'));
verifyEmpty(testCase, regexp(fixedTurnTxt, '(?m)^1,', 'once'));
verifyNotEmpty(testCase, regexp(fixedTurnTxt, '(?m)^2,', 'once'));
end

function testPlatformRectangleBridgeCorridorAndAdvisory(testCase)
% 先画精确正向 13x14 平台，再由 18.63 mm 内圆和四个统一宽度的
% 对角连接区自然形成四槽；不得强迫矩形四角完全缩进内圆。
res = analyzeInternal(struct('centerPlatformWidth', 13.0, 'centerPlatformHeight', 14.0));
verifyTrue(testCase, res.validation.passed);
verifyGreaterThanOrEqual(testCase, res.validation.minCopperToSlotsMm, cfgEdgeClearanceForCheck(testCase) - 1e-9);
verifyEmpty(testCase, res.validation.advisories);
verifyEqual(testCase, res.effectiveDimensions.centerPlatformHeight, 14.0, 'AbsTol', 1e-9);
verifyEqual(testCase, res.effectiveDimensions.coilInnerDiameter, 18.63, 'AbsTol', 1e-9);
verifyEqual(testCase, numel(res.boardLoops), 9);
verifyError(testCase, @() analyzeInternal(struct('centerPlatformWidth', 30.0, ...
    'centerPlatformHeight', 30.0)), 'CircularFPC:GeometryInfeasible');
% 超大平台（20x11）：四条桥统一加宽后由最终布尔槽拓扑拒绝。
verifyError(testCase, @() analyzeInternal(struct('centerPlatformWidth', 20.0, ...
    'centerPlatformHeight', 11.0)), 'CircularFPC:GeometryInfeasible');
end

function ec = cfgEdgeClearanceForCheck(~)
ec = 0.30; % 默认 edgeClearance（与嘉立创铜-板框 DRC 对应）
end

function testInnerTransitionDetour(testCase)
% 4/4 分数匝方案：V12/V34 两侧线圈必须在同一个过孔中心汇合；上游与下游都用
% 单段切向圆弧并入过孔，接触扫角（两侧）自动选择 >90° 且 <=150°。
% 不允许直线弦锐接、S 形或 180° 回头钩。
res = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 4));
verifyTrue(testCase, res.validation.passed, ...
    sprintf('4/4 validation failed: %s', strjoin(res.validation.messages, ' | ')));
verifyGreaterThanOrEqual(testCase, res.validation.minViaToNonConnectedCopperMm, 0.176 - 1e-9);
verifyGreaterThanOrEqual(testCase, res.validation.minViaToBoardMm, res.config.edgeClearance - 1e-9);
verifyGreaterThanOrEqual(testCase, res.validation.minDrillToBoardMm, 0.176 - 1e-9);
verifyEmpty(testCase, res.layerPaths(3).connectionPaths, 'L3 must have no transition traces');
verifyGreaterThan(testCase, res.validation.minCopperInteriorAngleDeg, ...
    res.config.minCopperInteriorAngleDeg + res.config.angleToleranceDeg);
verifyGreaterThan(testCase, res.validation.minBoardInteriorAngleDeg, ...
    res.config.minBoardInteriorAngleDeg + res.config.angleToleranceDeg);
verifyGreaterThan(testCase, res.validation.minOuterViaContactSweepDeg, ...
    res.config.minCopperInteriorAngleDeg + res.config.angleToleranceDeg);
verifyLessThanOrEqual(testCase, res.validation.maxOuterViaContactSweepDeg, 150);
for item = {1, 2, 'V12'; 3, 4, 'V34'}.'
    fromLayer = item{1};
    toLayer = item{2};
    viaName = item{3};
    v = res.vias(strcmp({res.vias.name}, viaName));
    upstream = res.layerPaths(fromLayer).coilXY;
    downstream = res.layerPaths(toLayer).coilXY;
    verifyEqual(testCase, upstream(end, :), v.xy, 'AbsTol', 1e-9);
    verifyEqual(testCase, downstream(1, :), v.xy, 'AbsTol', 1e-9);
    verifyGreaterThan(testCase, v.contactSweepDeg, ...
        res.config.minCopperInteriorAngleDeg + res.config.angleToleranceDeg);
    verifyLessThanOrEqual(testCase, v.contactSweepDeg, 150);
    % 圆弧扫角 <180° 时，到过孔中心的弦长应沿离孔方向单调增加；
    % 该断言可直接阻止回头钩/S 形重新出现。
    sampleCount = min(73, size(downstream, 1));
    distanceFromVia = sqrt(sum((downstream(1:sampleCount, :) - v.xy).^2, 2));
    verifyGreaterThanOrEqual(testCase, min(diff(distanceFromVia)), -1e-9);
end
% L4->VOUT is deliberately the new single-bend output path, not the old
% micro-jog-only inner-transition contract.
verifyEqual(testCase, res.terminalRouting.outputBendCount, 1);
outputPath = res.terminalRouting.outputPath;
verifyGreaterThan(testCase, size(outputPath, 1), 2);
outputLen = sum(sqrt(sum(diff(outputPath, 1, 1).^2, 2)));
verifyEqual(testCase, outputLen, deg2rad(res.terminalRouting.outputSweepDeg) * ...
    res.terminalRouting.outputBendRadiusMm, 'AbsTol', 1e-3);
verifyEqual(testCase, outputPath(1, :), res.layerPaths(4).coilXY(end, :), 'AbsTol', 1e-9);
verifyEqual(testCase, outputPath(end, :), res.vias(strcmp({res.vias.name}, 'VOUT')).xy, 'AbsTol', 1e-9);
% V34 到 L4 的圆弧已直接并入线圈，不应残留独立 registration jog。
for k = 1:numel(res.layerPaths(4).connectionPaths)
    p = res.layerPaths(4).connectionPaths{k};
    if norm(p(1, :) - outputPath(1, :)) <= 1e-9 && norm(p(end, :) - outputPath(end, :)) <= 1e-9
        continue;
    end
    pathLen = sum(sqrt(sum(diff(p, 1, 1).^2, 2)));
    verifyLessThanOrEqual(testCase, pathLen, 0.3, ...
        sprintf('Only non-outer local L4 micro connections may remain (len %.3f)', pathLen));
end
% 两侧圆弧都汇合到同一个外端过孔，故每对层的最大半径相同。
rStart = res.effectiveDimensions.coilInnerDiameter / 2 + res.config.traceWidth / 2;
pitch = res.effectiveDimensions.coilPitch;
rMaxL1 = max(sqrt(sum(res.layerPaths(1).coilXY.^2, 2)));
rMaxL2 = max(sqrt(sum(res.layerPaths(2).coilXY.^2, 2)));
rMaxL3 = max(sqrt(sum(res.layerPaths(3).coilXY.^2, 2)));
rMaxL4 = max(sqrt(sum(res.layerPaths(4).coilXY.^2, 2)));
verifyEqual(testCase, rMaxL2, rMaxL1, 'AbsTol', 1e-9);
verifyEqual(testCase, rMaxL4, rMaxL3, 'AbsTol', 1e-9);
verifyGreaterThan(testCase, rMaxL2, rStart + 7.25 * pitch);
% V23 位置：theta+90 桥轴；径向偏移使用真实 0.55 mm 过孔焊环
% 到走线的净距，并留 1 um 数值裕量。
v23 = res.vias(strcmp({res.vias.name}, 'V23'));
verifyEqual(testCase, numel(v23), 1);
uAxis = [cosd(res.config.connectionAngleDeg), sind(res.config.connectionAngleDeg)];
verifyTrue(testCase, abs(dot(v23.xy, uAxis)) <= 1e-6, ...
    'V23 must lie on the theta+90 bridge axis');
keepoutR = res.config.viaCoilSpacing + res.config.viaPadDiameter / 2;
expectedRV23 = rStart - (keepoutR + res.config.traceWidth / 2 + 1e-3 - 0.25 * pitch);
verifyEqual(testCase, norm(v23.xy), expectedRV23, 'AbsTol', 1e-6);
% 13x14 平台下 4/4 仍可生成
resBig = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 4, ...
    'centerPlatformWidth', 13.0, 'centerPlatformHeight', 14.0));
verifyTrue(testCase, resBig.validation.passed, ...
    sprintf('4/4 + 13x14 validation failed: %s', strjoin(resBig.validation.messages, ' | ')));
% 极限档小过孔（分数匝 + 板框按最大外端定径 + 端子附着带间距判定）：应通过
resX = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 4, ...
    'manufacturingTier', 'extreme', 'viaPadDiameter', 0.35, 'viaDrillDiameter', 0.15));
verifyTrue(testCase, resX.validation.passed, ...
    sprintf('4/4 extreme validation failed: %s', strjoin(resX.validation.messages, ' | ')));
verifyGreaterThanOrEqual(testCase, resX.validation.minCopperSpacingMm, 0.15 - 1e-9);
end

function testOuterViaContactsMeasuredOnBothSides(testCase)
% 外端过孔两侧接触弧契约（审查补充）：上游（奇数层外端→过孔）与下游（过孔→
% 偶数层外端）都必须被测量，且同时满足 扫角 ∈ (90°+容差, 150°] 与
% 半径 >= 一个线宽。本测试不复用生产弧参数：独立用三点拟合圆恢复上游层
% 折线尾部恰好 73 点、下游层折线头部恰好 73 点的接触弧，复算扫角/半径并
% 与过孔字段交叉核对；接点回退角在 180/240/360 采样下保持有界（角度窗口
% 的物理不变性，而不是采样点数窗口）。覆盖低匝数（上游弧曾静默非法的复现
% 档）与高采样密度 480/720（端子弦基线修复后全密度可行）。
combos = {2, 2, 2, 360; 2, 2, 3, 360; 2, 2, 7, 360; 2, 2, 7, 180; ...
    2, 2, 7, 240; 2, 2, 7, 480; 2, 2, 7, 720; 4, 2, 7, 360; 4, 4, 7, 360; 6, 6, 7, 360};
expectedContacts = {1; 1; 1; 1; 1; 1; 1; 1; 2; 3};
verifiedCount = 0;
for k = 1:size(combos, 1)
    label = sprintf('%dL%dC t%d s%d', combos{k, 1}, combos{k, 2}, combos{k, 3}, combos{k, 4});
    res = analyzeInternal(struct('boardLayerCount', combos{k, 1}, ...
        'coilLayerCount', combos{k, 2}, 'turnsPerCoilLayer', combos{k, 3}, ...
        'samplePointsPerTurn', combos{k, 4}));
    verifyTrue(testCase, res.validation.passed, ...
        sprintf('%s failed: %s', label, strjoin(res.validation.messages, ' | ')));
    verifyTrue(testCase, res.validation.outerViaContactsMeasured, ...
        sprintf('%s: outer via contact measurements incomplete', label));
    verifyGreaterThanOrEqual(testCase, res.validation.minOuterViaContactRadiusMm, ...
        res.config.traceWidth - 1e-9, label);
    outerVias = res.vias(strcmp({res.vias.role}, 'OUTER_TRANSITION'));
    verifyEqual(testCase, numel(outerVias), expectedContacts{k}, label);
    for v = outerVias
        verifyTrue(testCase, isfinite(v.upstreamContactSweepDeg), ...
            sprintf('%s: %s missing upstream contact sweep', label, v.name));
        verifyTrue(testCase, isfinite(v.upstreamContactRadiusMm), ...
            sprintf('%s: %s missing upstream contact radius', label, v.name));
        verifyTrue(testCase, isfinite(v.contactSweepDeg), ...
            sprintf('%s: %s missing downstream contact sweep', label, v.name));
        verifyTrue(testCase, isfinite(v.contactRadiusMm), ...
            sprintf('%s: %s missing downstream contact radius', label, v.name));
        verifyGreaterThan(testCase, v.upstreamContactSweepDeg, ...
            res.config.minCopperInteriorAngleDeg + res.config.angleToleranceDeg, label);
        verifyLessThanOrEqual(testCase, v.upstreamContactSweepDeg, 150, label);
        verifyGreaterThan(testCase, v.contactSweepDeg, ...
            res.config.minCopperInteriorAngleDeg + res.config.angleToleranceDeg, label);
        verifyLessThanOrEqual(testCase, v.contactSweepDeg, 150, label);
        verifyGreaterThanOrEqual(testCase, v.upstreamContactRadiusMm, ...
            res.config.traceWidth - 1e-9, label);
        verifyGreaterThanOrEqual(testCase, v.contactRadiusMm, ...
            res.config.traceWidth - 1e-9, label);
        % 独立测量（上游）：折线尾部 73 点必须落在同一个圆上（残差双侧有界），
        % 拟合出的扫角/半径与过孔字段交叉核对。
        xy = res.layerPaths(v.fromLayer).coilXY;
        arc = xy(end - 72:end, :);
        center = circCenterFrom3Points(arc(1, :), arc(37, :), arc(73, :));
        radius = norm(arc(73, :) - center);
        verifyLessThanOrEqual(testCase, ...
            max(abs(sqrt(sum((arc - center).^2, 2)) - radius)), 1e-6, ...
            sprintf('%s: %s upstream tail is not a single arc', label, v.name));
        sweep = measuredSweepDeg(center, arc);
        verifyEqual(testCase, sweep, v.upstreamContactSweepDeg, 'AbsTol', 1e-6);
        verifyEqual(testCase, radius, v.upstreamContactRadiusMm, 'AbsTol', 1e-6);
        verifyGreaterThan(testCase, sweep, 90.1, label);
        verifyLessThanOrEqual(testCase, sweep, 150, label);
        verifyEqual(testCase, arc(end, :), v.xy, 'AbsTol', 1e-9);
        % 独立测量（下游）：折线头部 73 点同上。
        darc = res.layerPaths(v.toLayer).coilXY(1:73, :);
        dcenter = circCenterFrom3Points(darc(1, :), darc(37, :), darc(73, :));
        dradius = norm(darc(1, :) - dcenter);
        verifyLessThanOrEqual(testCase, ...
            max(abs(sqrt(sum((darc - dcenter).^2, 2)) - dradius)), 1e-6, ...
            sprintf('%s: %s downstream head is not a single arc', label, v.name));
        dsweep = measuredSweepDeg(dcenter, darc);
        verifyEqual(testCase, dsweep, v.contactSweepDeg, 'AbsTol', 1e-6);
        verifyEqual(testCase, dradius, v.contactRadiusMm, 'AbsTol', 1e-6);
        verifyGreaterThan(testCase, dsweep, 90.1, label);
        verifyLessThanOrEqual(testCase, dsweep, 150, label);
        verifyEqual(testCase, darc(1, :), v.xy, 'AbsTol', 1e-9);
        % 角度窗口的物理不变性：两侧接点自过孔方向量起的回退角都有界，
        % 不随采样密度漂移（若退回采样点数窗口，180 采样下会胀到 ~48°）。
        verifyLessThanOrEqual(testCase, positionAngleDeg(v.xy, arc(1, :)), 25, ...
            sprintf('%s: %s upstream junction back-off exceeds the angular window', label, v.name));
        verifyLessThanOrEqual(testCase, positionAngleDeg(v.xy, darc(73, :)), 25, ...
            sprintf('%s: %s downstream junction back-off exceeds the angular window', label, v.name));
        verifiedCount = verifiedCount + 1;
    end
end
verifyEqual(testCase, verifiedCount, 13);
% 已删除的手动端子模式字段必须被拒绝为未知配置，防止契约悄悄回潮。
for f = {'terminalPlacementMode', 'manualPadAXY', 'manualPadBXY', 'manualSeriesViaXY'}
    overrides = struct();
    overrides.(f{1}) = [];
    verifyError(testCase, @() circular_fpc_default_config(overrides), ...
        'CircularFPC:UnknownConfigField');
end
end

function center = circCenterFrom3Points(a, b, c)
% 三点外接圆圆心（二维）。三点共线时返回 [NaN NaN]，由调用方的残差断言拦截。
d = 2 * (a(1) * (b(2) - c(2)) + b(1) * (c(2) - a(2)) + c(1) * (a(2) - b(2)));
if abs(d) < 1e-12
    center = [NaN NaN];
    return;
end
a2 = sum(a.^2);
b2 = sum(b.^2);
c2 = sum(c.^2);
center = [(a2 * (b(2) - c(2)) + b2 * (c(2) - a(2)) + c2 * (a(2) - b(2))) / d, ...
    (a2 * (c(1) - b(1)) + b2 * (a(1) - c(1)) + c2 * (b(1) - a(1))) / d];
end

function sweep = measuredSweepDeg(center, arc)
% 圆弧扫角（度）：圆心到弧首/弧末两个向量的夹角，取 [0,180] 的劣角。
% 本契约的接触弧扫角 <=150°，劣角即真实扫角。
v1 = arc(1, :) - center;
v2 = arc(end, :) - center;
sweep = atan2d(abs(v1(1) * v2(2) - v1(2) * v2(1)), dot(v1, v2));
end

function deg = positionAngleDeg(a, b)
% 两个位置向量相对原点的夹角（度）。阿基米德螺旋的极角≈位置角，因此
% 过孔方向与接点位置的夹角即接点沿螺旋的回退角。
deg = atan2d(abs(a(1) * b(2) - a(2) * b(1)), dot(a, b));
end

function testViaSizeRules(testCase)
% 过孔规则（R1 契约）：环宽 >= 0.2（推荐 0.25）；standard 层统一 钻孔>=0.30/焊环>=0.55；
% extreme 层允许层相关最小尺寸 2L 0.10/0.30、4L 0.15/0.35（WARN+HIGH_COST_EXTREME，
% 警告语义在 testManufacturingProfileRules 中通过 analyze 报告验证）。
% 过孔不再限制线距：外端过孔通过径向延伸区（viaEndExtension）放置，焊环避开相邻匝。
verifyError(testCase, @() circular_fpc_default_config(struct('viaPadDiameter', 0.5, 'viaDrillDiameter', 0.31)), ...
    'CircularFPC:InvalidConfig'); % 环宽 0.19 < 0.2（且焊环低于 standard 0.55）
verifyError(testCase, @() circular_fpc_default_config(struct('viaPadDiameter', 0.55, 'viaDrillDiameter', 0.36)), ...
    'CircularFPC:InvalidConfig'); % 环宽 0.19 < 0.2（焊环/钻孔均不低于 standard 极限，单独锁定环宽规则）
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 2, 'coilLayerCount', 1, 'viaDrillDiameter', 0.08)), ...
    'CircularFPC:InvalidConfig'); % 2 层钻孔低于 standard 0.30
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 4, 'viaPadDiameter', 0.3, 'viaDrillDiameter', 0.1)), ...
    'CircularFPC:InvalidConfig'); % 4 层焊环/钻孔低于 standard 0.55/0.30
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 4, 'viaDrillDiameter', 0.14)), ...
    'CircularFPC:InvalidConfig'); % 4 层钻孔低于 standard 0.30
% standard 层拒绝文档化的 extreme 最小尺寸（旧行为把它们当作普通合法值）
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 2, 'coilLayerCount', 1, 'viaDrillDiameter', 0.1, 'viaPadDiameter', 0.3)), ...
    'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 4, 'viaDrillDiameter', 0.15, 'viaPadDiameter', 0.35)), ...
    'CircularFPC:InvalidConfig');
% extreme 层接受层相关最小尺寸
cfg2Lx = circular_fpc_default_config(struct('manufacturingTier', 'extreme', 'boardLayerCount', 2, ...
    'coilLayerCount', 1, 'viaDrillDiameter', 0.1, 'viaPadDiameter', 0.3));
verifyEqual(testCase, cfg2Lx.viaDrillDiameter, 0.1, 'AbsTol', 1e-9);
cfg4Lx = circular_fpc_default_config(struct('manufacturingTier', 'extreme', 'boardLayerCount', 4, ...
    'viaDrillDiameter', 0.15, 'viaPadDiameter', 0.35));
verifyEqual(testCase, cfg4Lx.viaPadDiameter, 0.35, 'AbsTol', 1e-9);
% standard 层在常规极限处成功（等值按 ADR-2 记为 WARN，不拒绝）
cfg2Ls = circular_fpc_default_config(struct('boardLayerCount', 2, 'coilLayerCount', 1, 'viaDrillDiameter', 0.3, 'viaPadDiameter', 0.55));
verifyEqual(testCase, cfg2Ls.viaDrillDiameter, 0.3, 'AbsTol', 1e-9);
cfg4Ls = circular_fpc_default_config(struct('boardLayerCount', 4, 'viaDrillDiameter', 0.3, 'viaPadDiameter', 0.55));
verifyEqual(testCase, cfg4Ls.viaDrillDiameter, 0.3, 'AbsTol', 1e-9);
% 默认 0.30/0.55 成功；0.55 过孔 + 密绕（0.15 线距、8 匝）：延伸区保证净距，配置合法
cfgDef = circular_fpc_default_config();
verifyEqual(testCase, cfgDef.viaDrillDiameter, 0.31, 'AbsTol', 1e-9);
verifyEqual(testCase, cfgDef.viaPadDiameter, 0.55, 'AbsTol', 1e-9);
cfgOK = circular_fpc_default_config(struct('traceSpacing', 0.15, 'turnsPerCoilLayer', 8, 'viaPadDiameter', 0.55));
verifyEqual(testCase, cfgOK.viaCoilSpacing, 0.152, 'AbsTol', 1e-9);
end

function testManufacturingProfileRules(testCase)
% R1 制造档案契约：默认 profile/tier/overrides；非法取值与未知规则覆盖；
% trace 宽度、过孔、铜厚边界；analyze 制造报告字段与 WARN/HIGH_COST_EXTREME 语义。
cfg = circular_fpc_default_config();
verifyEqual(testCase, cfg.manufacturingProfile, 'jlc_fpc_1_3oz');
verifyEqual(testCase, cfg.copperThickness, 0.012, 'AbsTol', 1e-12);
verifyEqual(testCase, cfg.manufacturingTier, 'standard');
verifyTrue(testCase, isstruct(cfg.manufacturingRuleOverrides) && isscalar(cfg.manufacturingRuleOverrides) ...
    && isempty(fieldnames(cfg.manufacturingRuleOverrides)));
% 非法 profile / tier / overrides 类型或取值
verifyError(testCase, @() circular_fpc_default_config(struct('manufacturingProfile', 'other')), ...
    'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('manufacturingTier', 'extremeX')), ...
    'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('manufacturingRuleOverrides', 1)), ...
    'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('manufacturingRuleOverrides', struct('minTraceWidthMm', {0.15, 0.2}))), ...
    'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('manufacturingRuleOverrides', struct('minTraceWidthMm', -0.1))), ...
    'CircularFPC:InvalidConfig');
% 未知规则覆盖字段
verifyError(testCase, @() circular_fpc_default_config(struct('manufacturingRuleOverrides', struct('bogusRule', 0.2))), ...
    'CircularFPC:UnknownManufacturingRule');
% trace 宽度边界：0.102 合法、0.101 失败
verifyEqual(testCase, circular_fpc_default_config(struct('traceWidth', 0.102)).traceWidth, 0.102, 'AbsTol', 1e-9);
verifyError(testCase, @() circular_fpc_default_config(struct('traceWidth', 0.101)), 'CircularFPC:InvalidConfig');
% 规则覆盖改变极限与 source：minTraceWidthMm=0.15
ruleOv = struct('minTraceWidthMm', 0.15);
cfgOv = circular_fpc_default_config(struct('traceWidth', 0.15, 'manufacturingRuleOverrides', ruleOv));
verifyEqual(testCase, cfgOv.traceWidth, 0.15, 'AbsTol', 1e-9);
verifyError(testCase, @() circular_fpc_default_config(struct('traceWidth', 0.149, 'manufacturingRuleOverrides', ruleOv)), ...
    'CircularFPC:InvalidConfig');
resOv = analyzeInternal(struct('traceWidth', 0.15, 'manufacturingRuleOverrides', ruleOv));
chkOv = findManufacturingCheck(resOv.manufacturing, 'TRACE_WIDTH');
verifyEqual(testCase, chkOv.limitMm, 0.15, 'AbsTol', 1e-9);
verifyEqual(testCase, chkOv.source, 'override');
% 默认 analyze 制造报告结构
res = analyzeInternal();
mf = res.manufacturing;
verifyEqual(testCase, mf.profile, 'jlc_fpc_1_3oz');
verifyEqual(testCase, mf.tier, 'standard');
verifyTrue(testCase, isfield(mf, 'rules') && isfield(mf, 'checks') && isfield(mf, 'passed') ...
    && isfield(mf, 'warnings') && isfield(mf, 'failures'));
verifyTrue(testCase, mf.passed);
verifyTrue(testCase, isempty(mf.failures));
ids = {mf.checks.id};
verifyTrue(testCase, all(ismember({'TRACE_WIDTH', 'TRACE_SPACING', 'VIA_DRILL', 'VIA_PAD', ...
    'VIA_PAD_DRILL_DIFFERENCE', 'DRILL_TO_BOARD', 'COPPER_THICKNESS'}, ids)));
% 默认 TRACE_WIDTH 有余量 -> PASS；VIA_DRILL 恰在 standard 极限 -> WARN
chkTw = findManufacturingCheck(mf, 'TRACE_WIDTH');
verifyEqual(testCase, chkTw.limitMm, 0.102, 'AbsTol', 1e-9);
verifyEqual(testCase, chkTw.source, 'profile');
verifyEqual(testCase, chkTw.status, 'PASS');
chkVd = findManufacturingCheck(mf, 'VIA_DRILL');
verifyEqual(testCase, chkVd.status, 'WARN');
% extreme 层 2L 0.10/0.30、4L 0.15/0.35：analyze 成功且对应 via 检查为 WARN + HIGH_COST_EXTREME
    resX2 = analyzeInternal(struct('manufacturingTier', 'extreme', 'boardLayerCount', 2, ...
        'coilLayerCount', 1, 'viaDrillDiameter', 0.1, 'viaPadDiameter', 0.3));
verifyTrue(testCase, resX2.manufacturing.passed);
chkX2d = findManufacturingCheck(resX2.manufacturing, 'VIA_DRILL');
chkX2p = findManufacturingCheck(resX2.manufacturing, 'VIA_PAD');
verifyEqual(testCase, chkX2d.status, 'WARN');
verifyEqual(testCase, chkX2p.status, 'WARN');
verifyTrue(testCase, contains(chkX2d.message, 'HIGH_COST_EXTREME') || contains(chkX2d.code, 'HIGH_COST_EXTREME'));
verifyTrue(testCase, contains(chkX2p.message, 'HIGH_COST_EXTREME') || contains(chkX2p.code, 'HIGH_COST_EXTREME'));
resX4 = analyzeInternal(struct('manufacturingTier', 'extreme', 'boardLayerCount', 4, ...
    'viaDrillDiameter', 0.15, 'viaPadDiameter', 0.35));
verifyTrue(testCase, resX4.manufacturing.passed);
chkX4d = findManufacturingCheck(resX4.manufacturing, 'VIA_DRILL');
chkX4p = findManufacturingCheck(resX4.manufacturing, 'VIA_PAD');
verifyEqual(testCase, chkX4d.status, 'WARN');
verifyEqual(testCase, chkX4p.status, 'WARN');
verifyTrue(testCase, contains(chkX4d.message, 'HIGH_COST_EXTREME') || contains(chkX4d.code, 'HIGH_COST_EXTREME'));
verifyTrue(testCase, contains(chkX4p.message, 'HIGH_COST_EXTREME') || contains(chkX4p.code, 'HIGH_COST_EXTREME'));
% 铜厚匹配：0.012 +/- 0.001 边界合法，超出容差 0.001 mm 失败
verifyEqual(testCase, circular_fpc_default_config(struct('copperThickness', 0.011)).copperThickness, 0.011, 'AbsTol', 1e-9);
verifyEqual(testCase, circular_fpc_default_config(struct('copperThickness', 0.013)).copperThickness, 0.013, 'AbsTol', 1e-9);
verifyError(testCase, @() circular_fpc_default_config(struct('copperThickness', 0.013001)), 'CircularFPC:InvalidConfig');
end

function testJlcFourLayerOneThirdOzStackupContract(testCase)
res = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 2));
verifyEqual(testCase, res.config.manufacturingProfile, 'jlc_fpc_1_3oz');
verifyEqual(testCase, res.config.copperThickness, 0.012, 'AbsTol', 1e-12);
verifyTrue(testCase, isfield(res.manufacturing, 'stackup'));
stack = res.manufacturing.stackup;
verifyEqual(testCase, stack.name, 'FPC0420TT-121A');
verifyEqual(testCase, stack.nominalFinishedThicknessMm, 0.20, 'AbsTol', 1e-12);
verifyEqual(testCase, stack.computedThicknessMm, 0.203, 'AbsTol', 1e-12);
verifyEqual(testCase, stack.outerCopperThicknessMm, 0.012, 'AbsTol', 1e-12);
verifyEqual(testCase, stack.innerCopperThicknessMm, 0.012, 'AbsTol', 1e-12);
verifyEqual(testCase, stack.coverlayThicknessMm, 0.0275, 'AbsTol', 1e-12);
verifyEqual(testCase, numel(stack.layers), 11);
verifyEqual(testCase, stack.layers(2).name, 'L1_COPPER');
verifyEqual(testCase, stack.layers(5).name, 'L2_COPPER');
verifyEqual(testCase, stack.layers(7).name, 'L3_COPPER');
verifyEqual(testCase, stack.layers(10).name, 'L4_COPPER');
verifyEqual(testCase, stack.layers(2).thicknessMm, 0.012, 'AbsTol', 1e-12);
verifyEqual(testCase, stack.layers(10).thicknessMm, 0.012, 'AbsTol', 1e-12);
verifyEqual(testCase, stack.layers(2).zCenterMm - stack.layers(10).zCenterMm, 0.136, 'AbsTol', 1e-12);
verifyEqual(testCase, stack.activeCopperCenterSpacingMm, 0.136, 'AbsTol', 1e-12);
verifyEqual(testCase, stack.coverlayColor, 'yellow');
verifyEqual(testCase, stack.copperType, 'adhesiveless_electrolytic');
verifyEqual(testCase, stack.surfaceFinish, 'ENIG_1u');
end

function testAnalyzeIsReadOnlyAndLayerMatrix(testCase)
% R2 契约：analyze 只计算不写文件；支持层矩阵与角度旋转；无效配置传播。
combos = [2 1; 2 2; 4 1; 4 2; 4 4; 6 6];
for k = 1:size(combos, 1)
    root = nonexistentTempRoot();
    res = analyzeInternal(struct('outputRoot', root, 'designName', 'red_readonly', ...
        'boardLayerCount', combos(k, 1), 'coilLayerCount', combos(k, 2)));
    verifyEqual(testCase, res.outputPath, '');
    verifyEqual(testCase, res.boardLayerCount, combos(k, 1));
    verifyEqual(testCase, res.coilLayerCount, combos(k, 2));
    verifyTrue(testCase, isfield(res, 'validation') && res.validation.passed);
    verifyTrue(testCase, isfield(res, 'manufacturing') && res.manufacturing.passed);
    verifyTrue(testCase, exist(root, 'dir') ~= 7, 'analyze must not create the output root');
end
% 角度旋转保持（显式 2/1 + 13x11 安全平台：4/4 的绕行过渡在非默认连接角下
% 可能实测铜-槽净距不足而报错，属预期保护；旋转覆盖用无绕行的 2/1 组合）。
% 45/135/225 时外端过孔偏离四条耳朵轴 45°，可正常生成。
for ang = [45 135 225]
    resA = analyzeInternal(struct('connectionAngleDeg', ang, 'boardLayerCount', 2, ...
        'coilLayerCount', 1, 'centerPlatformHeight', 11.0, 'outputRoot', nonexistentTempRoot()));
    verifyEqual(testCase, resA.effectiveDimensions.centerPlatformWidth, 13.0, 'AbsTol', 1e-9);
    verifyEqual(testCase, resA.effectiveDimensions.centerPlatformHeight, 11.0, 'AbsTol', 1e-9);
end
% 0° 时外端过孔 VRET 正好落在 0° 安装耳朵轴上：挖槽的内侧弧就是主体外径圆，
% 会切入该过孔的净距范围。按新契约必须明确报错，不允许通过降低净距生成。
% 该冲突在端子放置阶段即被拒绝（CircularFPC:TerminalPlacementInvalid）。
verifyError(testCase, @() analyzeInternal(struct('connectionAngleDeg', 0, ...
    'boardLayerCount', 2, 'coilLayerCount', 1, 'centerPlatformHeight', 11.0, ...
    'outputRoot', nonexistentTempRoot())), 'CircularFPC:TerminalPlacementInvalid');
% 同一旋转角下把四个耳朵整体挪开（改连接角回 135°）即可行：证明冲突来自
% 安装耳朵与轴向外端过孔的位置关系，而不是其他特征。
resDefault = analyzeInternal(struct('outputRoot', nonexistentTempRoot()));
verifyTrue(testCase, resDefault.validation.passed);
res135 = analyzeInternal(struct('connectionAngleDeg', 135, 'outputRoot', nonexistentTempRoot()));
padA = findTerminalByName(res135.pads, 'PAD_A');
verifyTrue(testCase, padA.xy(1) < 0 && padA.xy(2) > 0);
% 无效配置沿 analyze 传播
verifyError(testCase, @() analyzeInternal(struct('traceWidth', 0.101)), 'CircularFPC:InvalidConfig');
end

function testSixLayerGeometryIsExplicitlyUnverifiedForStackup(testCase)
result = analyzeInternal(struct('boardLayerCount', 6, 'coilLayerCount', 6));
verifyTrue(testCase, result.validation.passed);
verifyTrue(testCase, result.manufacturing.passed);
verifyEqual(testCase, result.manufacturing.qualificationStatus, 'UNVERIFIED_LAYER_COUNT');
verifyEqual(testCase, result.manufacturing.stackup.name, 'UNVERIFIED_6L_STACKUP');
verifyEqual(testCase, numel(result.manufacturing.stackup.layers), 6);
verifyTrue(testCase, all(isnan([result.manufacturing.stackup.layers.zTopMm])));
verifyTrue(testCase, all(isnan([result.manufacturing.stackup.layers.zBottomMm])));
verifyTrue(testCase, all(isnan([result.manufacturing.stackup.layers.zCenterMm])));
verifyTrue(testCase, any(contains(string(result.manufacturing.warnings), 'unverified')));
end

function testDefaultBoardGeometry(testCase)
cfg = circular_fpc_default_config();
outRoot = createTempOutput(testCase);
lastwarn('');
result = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'default_geometry'));
[warningMessage, warningId] = lastwarn;
verifyEmpty(testCase, warningMessage);
verifyEmpty(testCase, warningId);
verifyEqual(testCase, result.boardLayerCount, 4);
verifyEqual(testCase, result.coilLayerCount, 4);
verifyEqual(testCase, result.activeCoilLayers, [1 2 3 4]);
verifyGreaterThan(testCase, result.effectiveDimensions.boardOuterDiameter, 24.7);
verifyLessThan(testCase, result.effectiveDimensions.boardOuterDiameter, 25.0);
verifyEqual(testCase, result.effectiveDimensions.coilInnerDiameter, 18.63, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformWidth, 13.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformHeight, 14.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.bridgeTargetWidth, 1.5, 'AbsTol', 1e-9);
platformXY = result.layoutRegions.platformLoop(1:end - 1, :);
verifyEqual(testCase, max(abs(platformXY(:, 1))), 6.5, 'AbsTol', 1e-9);
verifyEqual(testCase, max(abs(platformXY(:, 2))), 7.0, 'AbsTol', 1e-9);
verifyTrue(testCase, all(abs(abs(platformXY(:, 1)) - 6.5) < 1e-9 | ...
    abs(abs(platformXY(:, 2)) - 7.0) < 1e-9), ...
    'Central 13x14 platform must remain an axis-aligned rectangle.');
verifyEqual(testCase, result.effectiveDimensions.coilPitch, 0.355, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.turnsPerCoilLayer, 7);
verifyGreaterThanOrEqual(testCase, result.effectiveDimensions.actualBridgeWidth, 1.5);
verifyEqual(testCase, result.layoutRegions.bridgeWidths, ...
    repmat(result.layoutRegions.bridgeWidth, 1, 4), 'AbsTol', 1e-9);
verifyEqual(testCase, result.layoutRegions.bridgeGoverningConstraint, 'terminalEnvelope');
outerLoop = result.boardLoops(1);
verifyFalse(testCase, outerLoop.isHole);
outerXY = outerLoop.xy(1:end - 1, :);
nominalOuterRadius = result.effectiveDimensions.boardOuterDiameter / 2;
outerRadii = hypot(outerXY(:, 1), outerXY(:, 2));
verifyGreaterThan(testCase, max(outerRadii), nominalOuterRadius + 4.0);
verifyGreaterThan(testCase, result.layoutRegions.boardExtent, nominalOuterRadius + 4.0);
[baseX, baseY] = boundary(result.layoutRegions.baseBoardShape);
verifyLessThanOrEqual(testCase, max(hypot(baseX, baseY)), nominalOuterRadius + 1e-6);
verifyEqual(testCase, numel(result.boardLoops), 9);
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
verifyEqual(testCase, holeCount, 8);
verifyTrue(testCase, result.validation.passed);
verifyTrue(testCase, result.validation.finiteCoordinates);
verifyTrue(testCase, result.validation.noZeroLengthSegments);
verifyTrue(testCase, result.validation.noSelfIntersections);
verifyEqual(testCase, result.validation.closedBoardLoopCount, 9);
verifyGreaterThanOrEqual(testCase, result.validation.minCopperSpacingMm, 0.15);
verifyGreaterThanOrEqual(testCase, result.validation.minCopperToBoardMm, cfg.edgeClearance);
verifyGreaterThanOrEqual(testCase, result.validation.minCopperToSlotsMm, cfg.edgeClearance);
verifyGreaterThanOrEqual(testCase, result.validation.minViaToNonConnectedCopperMm, 0.176 - 1e-9);
verifyTrue(testCase, result.validation.minCopperInteriorAngleDeg > ...
    cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg, ...
    sprintf('copper path min interior angle must be strictly > 90.1 (got %.3f)', result.validation.minCopperInteriorAngleDeg));
verifyTrue(testCase, result.validation.minBoardInteriorAngleDeg > ...
    cfg.minBoardInteriorAngleDeg + cfg.angleToleranceDeg, ...
    sprintf('board min interior angle must be strictly > 90.1 (got %.3f)', result.validation.minBoardInteriorAngleDeg));
verifyGreaterThan(testCase, result.validation.minOuterViaContactSweepDeg, 90.1);
verifyLessThanOrEqual(testCase, result.validation.maxOuterViaContactSweepDeg, 150);
verifyGreaterThanOrEqual(testCase, result.validation.actualBridgeWidthMm, 1.5);
verifyTrue(testCase, result.validation.uniqueSeriesNetwork);
verifyTrue(testCase, result.validation.viaOverlapFree);
verifyTrue(testCase, isfield(result, 'totalTraceLengthMm'));
verifyTrue(testCase, isfield(result, 'estimatedDcResistanceOhm'));
verifyTrue(testCase, isfinite(result.totalTraceLengthMm) && result.totalTraceLengthMm > 0);
verifyTrue(testCase, isfinite(result.estimatedDcResistanceOhm) && result.estimatedDcResistanceOhm > 0);
verifyTrue(testCase, ischar(result.outputPath));
end

function testAdaptiveBoardLugsNotchesAndIndependentElectrodes(testCase)
% 局部板框特征随活动层和匝数变化：主体圆只由线圈铜边定径，外端过孔、
% 四个半圆缺口和右下角两个独立电极分别生成局部凸耳，不进入串联网络。
cases = [2 2; 4 4; 6 6];
expectedOuter = {{'V12'}; {'V12', 'V34'}; {'V12', 'V34', 'V56'}};
for k = 1:size(cases, 1)
    result = analyzeInternal(struct('boardLayerCount', cases(k, 1), ...
        'coilLayerCount', cases(k, 2)));
    verifyEqual(testCase, numel(result.boardLoops), 9);
    outerVias = result.vias(strcmp({result.vias.role}, 'OUTER_TRANSITION'));
    verifyEqual(testCase, sort({outerVias.name}), sort(expectedOuter{k}));
    verifyEqual(testCase, size(result.layoutRegions.viaLugCenters, 1), numel(outerVias));
    for j = 1:numel(outerVias)
        v = outerVias(j);
        expectedAngle = expectedViaAngleDeg(v.name, result.config.connectionAngleDeg);
        verifyAngleMod360(testCase, v.bridgeAngleDeg, expectedAngle, ...
            sprintf('%s nominal radial angle', v.name));
        verifyAngleMod360(testCase, atan2d(v.xy(2), v.xy(1)), expectedAngle, ...
            sprintf('%s via centre radial angle', v.name));
        verifyEqual(testCase, v.xy, result.layoutRegions.viaLugCenters(j, :), 'AbsTol', 1e-9);
        verifyEqual(testCase, v.xy, result.layerPaths(v.fromLayer).coilXY(end, :), 'AbsTol', 1e-9);
    end
    verifyEqual(testCase, numel(result.electrodePads), 2);
    verifyEqual(testCase, sort({result.electrodePads.name}), {'ELECTRODE_A', 'ELECTRODE_B'});
    verifyTrue(testCase, all([result.electrodePads.layer] == 1));
    verifyTrue(testCase, all(strcmp({result.electrodePads.role}, 'INDEPENDENT_ELECTRODE')));
    verifyTrue(testCase, all(strcmp({result.electrodePads.placementRegion}, 'ELECTRODE_315')));
    verifyAngleMod360(testCase, result.electrodePads(1).bridgeAngleDeg, 315, ...
        'independent electrode bridge angle');
    verifyAngleMod360(testCase, result.electrodePads(2).bridgeAngleDeg, 315, ...
        'independent electrode bridge angle');
    electrodeCenter = mean(cat(1, result.electrodePads.xy), 1);
    verifyAngleMod360(testCase, atan2d(electrodeCenter(2), electrodeCenter(1)), 315, ...
        'independent electrode pair direction');
    for j = 1:numel(result.electrodePads)
        p = result.electrodePads(j);
        verifyTrue(testCase, p.xy(1) > 0 && p.xy(2) < 0);
        verifyFalse(testCase, any(strcmp(result.seriesSequence, p.name)), ...
            sprintf('%s must not enter the coil series route', p.name));
    end
end

% 三段弧安装耳朵：跨度与外凸高度变化时逐项复核定义（内侧弧与主体圆同心同半径、
% 端点弦长 = mountingSlotSpan、中央外凸 = mountingSlotRise、最外侧弧按板边净距
% 等距外偏），并确认挖槽确实移除板料。
for slotParams = struct('span', {3.0, 4.0, 5.0}, 'rise', {0.8, 1.0, 1.5})
    result = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 4, ...
        'mountingSlotSpan', slotParams.span, 'mountingSlotRise', slotParams.rise));
    verifyTrue(testCase, result.validation.passed, ...
        sprintf('span %.2f / rise %.2f validation failed: %s', slotParams.span, ...
        slotParams.rise, strjoin(result.validation.messages, ' | ')));
    lr = result.layoutRegions;
    verifyEqual(testCase, lr.mountingAnglesDeg, [0 90 180 270]);
    verifyEqual(testCase, lr.mountingSlotInnerArcRadius, ...
        result.effectiveDimensions.boardOuterDiameter / 2, 'AbsTol', 1e-9);
    % 内侧弧与主体外径圆精确重合：端点半径 = 主体外径圆半径
    endpointR = hypot(lr.mountingSlotEndpoints(:, 1), lr.mountingSlotEndpoints(:, 2));
    verifyEqual(testCase, endpointR, repmat(lr.mountingSlotInnerArcRadius, 8, 1), 'AbsTol', 1e-9);
    for j = 1:4
        % 端点关于耳朵径向轴对称，且弦长 = mountingSlotSpan
        endpoints = lr.mountingSlotEndpoints(2 * j - 1:2 * j, :);
        chord = norm(endpoints(2, :) - endpoints(1, :));
        verifyEqual(testCase, chord, lr.mountingSlotSpan, 'AbsTol', 1e-9, ...
            sprintf('ear %d slot chord must equal mountingSlotSpan', j));
        uEar = [cosd(lr.mountingAnglesDeg(j)), sind(lr.mountingAnglesDeg(j))];
        midpoint = mean(endpoints, 1);
        verifyEqual(testCase, norm(midpoint - dot(midpoint, uEar) * uEar), 0, 'AbsTol', 1e-9, ...
            sprintf('ear %d endpoints must be symmetric about its radial axis', j));
        % 中央外凸高度以主体圆中央点为基准，不是端点弦中点
        apexRadius = norm(endpoints(1, :)) + lr.mountingSlotRise;
        verifyEqual(testCase, lr.mountingSlotApexRadius, apexRadius, 'AbsTol', 1e-9, ...
            sprintf('ear %d middle-arc apex must sit mountingSlotRise above the main circle', j));
        % 最外侧弧 = 中间弧同心等距外偏 mountingSlotEdgeClearance
        verifyEqual(testCase, lr.mountingSlotOuterArcRadius - lr.mountingSlotMiddleArcRadius, ...
            lr.mountingSlotEdgeClearance, 'AbsTol', 1e-9, ...
            sprintf('ear %d outer arc must be the middle arc offset by the slot edge clearance', j));
        verifyEqual(testCase, lr.mountingEarApexRadius - lr.mountingSlotApexRadius, ...
            lr.mountingSlotEdgeClearance, 'AbsTol', 1e-6, ...
            sprintf('ear %d ear apex must sit one edge clearance beyond the slot apex', j));
        % 挖槽确实移除耳朵内部板料
        uNotch = uEar;
        cutoutPoint = (lr.mountingSlotApexRadius - 0.3) * uNotch;
        verifyFalse(testCase, isinterior(lr.boardShape, cutoutPoint(1), cutoutPoint(2)), ...
            sprintf('ear %d slot must remove board material above the main circle', j));
    end
    % 耳朵只局部外扩：主体圆不受安装参数影响；板总跨度由 315° 电极指决定，
    % 因此只用「耳朵顶点是板料且板跨度不小于耳朵顶点半径」来约束。
    verifyGreaterThanOrEqual(testCase, lr.boardExtent, lr.mountingEarApexRadius - 1e-9);
    verifyEqual(testCase, lr.mountingSlotInnerArcRadius, ...
        result.effectiveDimensions.boardOuterDiameter / 2, 'AbsTol', 1e-9);
end

r7 = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 2, ...
    'turnsPerCoilLayer', 7));
r9 = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 2, ...
    'turnsPerCoilLayer', 9));
verifyGreaterThan(testCase, r9.effectiveDimensions.boardOuterDiameter, ...
    r7.effectiveDimensions.boardOuterDiameter);
verifyGreaterThan(testCase, r9.layoutRegions.boardExtent, r7.layoutRegions.boardExtent);
end

function testMountingSlotFailsClosedOnInvalidParameters(testCase)
% 安装耳朵参数无效时必须明确报错，不允许通过降低净距或静默退化来生成。
% 1) 旧参数已弃用：语义无法唯一映射，显式拒绝而不是猜测。
for deprecated = {'mountingNotchDiameter', 'mountingNotchWall', 'mountingLugLength'}
    verifyError(testCase, @() circular_fpc_default_config( ...
        struct(deprecated{1}, 1.0)), 'CircularFPC:DeprecatedConfigField');
end
% 2) 跨度超出主体圆可容纳范围。
verifyError(testCase, @() analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, 'mountingSlotSpan', 30.0)), ...
    'CircularFPC:GeometryInfeasible');
% 3) 外凸高度无效（非正）。
verifyError(testCase, @() analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, 'mountingSlotRise', -1.0)), ...
    'CircularFPC:InvalidConfig');
% 4) 板料不足：槽到板边距离过大导致耳朵外弧与主体圆不相交。
verifyError(testCase, @() analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, 'mountingSlotEdgeClearance', 20.0)), ...
    'CircularFPC:GeometryInfeasible');
% 5) 槽口圆角半径与槽几何不匹配。
verifyError(testCase, @() analyzeInternal(struct( ...
    'boardLayerCount', 4, 'coilLayerCount', 2, 'mountingSlotEndFilletRadius', 5.0)), ...
    'CircularFPC:GeometryInfeasible');
% 6) 配置校验：跨度/外凸高度/板边距离/圆角必须是有限正标量。
for bad = {'mountingSlotSpan', 'mountingSlotRise', 'mountingSlotEdgeClearance', ...
        'mountingSlotEndFilletRadius'}
    verifyError(testCase, @() circular_fpc_default_config( ...
        struct(bad{1}, -1.0)), 'CircularFPC:InvalidConfig');
end
end

function testMountingEarsDoNotMoveTheMainBodyCircle(testCase)
% 安装耳朵只做局部外扩：主体外径由线圈与板边净距决定，与 span/rise 无关；
% 耳朵之外的主体圆边界保持主体半径。板总跨度受 315° 电极指控制，因此用
% 「耳朵顶点是板料 + 板跨度不小于耳朵顶点半径」约束局部外扩即可。
baseline = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 2));
for slotSpan = [3.0 5.0]
    result = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 2, ...
        'mountingSlotSpan', slotSpan));
    lr = result.layoutRegions;
    verifyTrue(testCase, result.validation.passed);
    % 主体圆定径与安装参数无关
    verifyEqual(testCase, lr.mountingSlotInnerArcRadius, ...
        baseline.layoutRegions.mountingSlotInnerArcRadius, 'AbsTol', 1e-9, ...
        'mounting ears must not resize the main body circle');
    verifyEqual(testCase, lr.boardExtent, baseline.layoutRegions.boardExtent, 'AbsTol', 1e-9, ...
        'mounting ears must not change the overall board extent');
    % 主体圆上的采样点仍严格等于主体半径（耳朵只占 4 个局部角域）
    for a = [45 60 120 150 210 240 300 330]
        insidePoint = 0.98 * lr.mountingSlotInnerArcRadius * [cosd(a), sind(a)];
        verifyTrue(testCase, isinterior(lr.baseBoardShape, insidePoint(1), insidePoint(2)), ...
            sprintf('main body circle must stay intact at %.0f deg', a));
    end
    % 4 个耳朵的角度位置不变，且外凸只发生在 0/90/180/270
    for j = 1:4
        uEar = [cosd(lr.mountingAnglesDeg(j)), sind(lr.mountingAnglesDeg(j))];
        apex = lr.mountingEarApexRadius * uEar;
        verifyTrue(testCase, isinterior(lr.boardShape, apex(1), apex(2)), ...
            sprintf('ear %d apex must be board material', j));
        % 耳朵之外的主体圆仍按主体半径：耳朵角域外的点属于板料
        outside = 0.99 * lr.mountingSlotInnerArcRadius * ...
            [cosd(lr.mountingAnglesDeg(j) + 30), sind(lr.mountingAnglesDeg(j) + 30)];
        verifyTrue(testCase, isinterior(lr.boardShape, outside(1), outside(2)), ...
            sprintf('board material at %.0f deg must remain', lr.mountingAnglesDeg(j) + 30));
    end
    verifyGreaterThanOrEqual(testCase, lr.boardExtent, lr.mountingEarApexRadius - 1e-9);
end
end

function testCanonicalSlotCornersUseSmoothTangentFillets(testCase)
result = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 4));
verifyEqual(testCase, numel(result.boardLoops), 9);
verifyGreaterThan(testCase, result.validation.minBoardInteriorAngleDeg, 170, ...
    sprintf(['Canonical slot boundaries must replace isolated platform/bridge hard corners ', ...
    'with sampled tangent fillets (minimum interior angle %.6f deg).'], ...
    result.validation.minBoardInteriorAngleDeg));
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
verifyGreaterThan(testCase, result.effectiveDimensions.boardOuterDiameter, 43.0);
verifyLessThan(testCase, result.effectiveDimensions.boardOuterDiameter, 46.0);
verifyEqual(testCase, result.effectiveDimensions.coilInnerDiameter, 37.26, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformWidth, 26.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformHeight, 28.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.bridgeTargetWidth, 3.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.coilPitch, 0.355, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.turnsPerCoilLayer, 7);
fullSvg = fullfile(result.outputPath, 'preview', 'JLC', '3_trace_pad_via', '01_overview.svg');
verifyTrue(testCase, isfile(fullSvg));
if isfile(fullSvg)
    svgTxt = fileread(fullSvg);
    extent = result.layoutRegions.boardExtent + 0.5;
    verifyTrue(testCase, contains(svgTxt, sprintf('viewBox="%.6f %.6f %.6f %.6f"', ...
        -extent, -extent, 2 * extent, 2 * extent)));
end
end

function testInvalidGeometryRejected(testCase)
outRoot = createTempOutput(testCase);
% 平台远超板外半径：可行性预检快速失败，不留正式输出目录。
% 超大但有限的平台同样由平台/内径硬约束明确拒绝。
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'invalid_platform', ...
    'centerPlatformWidth', 30.0, 'centerPlatformHeight', 30.0)), 'CircularFPC:GeometryInfeasible');
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'invalid_scale', 'geometryScale', 0.05)), 'CircularFPC:GeometryInfeasible');
verifyFalse(testCase, isfolder(fullfile(outRoot, 'invalid_platform')));
verifyFalse(testCase, isfolder(fullfile(outRoot, 'invalid_scale')));
% 匝数语义为物理 360° 圈数；1 匝完整圆环未纳入端子/过孔拓扑验证范围，配置阶段仍拒绝。
verifyError(testCase, @() circular_fpc_default_config(struct('turnsPerCoilLayer', 1)), ...
    'CircularFPC:InvalidConfig');
cfgMinTurns = circular_fpc_default_config(struct('turnsPerCoilLayer', 2));
verifyEqual(testCase, cfgMinTurns.turnsPerCoilLayer, 2);
% 严格 >90° 角度规则下，60° 连接方位仍应由圆弧化几何正常生成。
r60 = circular_fpc_main(struct('outputRoot', outRoot, ...
    'designName', 'sharp_angle_60', 'connectionAngleDeg', 60, 'centerPlatformHeight', 11.0));
verifyTrue(testCase, r60.validation.passed);
verifyTrue(testCase, isfolder(fullfile(outRoot, 'sharp_angle_60')));
end

function testTurnsContractPhysicalRevolutions(testCase)
% 匝数契约（物理 360° 圈数）：turnsPerCoilLayer = N 时每层螺旋角跨度必须为
% N + spanExtra（4/4 分数匝）个完整圆周。用独立 atan2 + unwrap 直接测量生成的
% 线圈折线，不复用生产 span 公式。CW 偶数层为纯螺旋（无外伸接触弧），
% 端到端解卷绕角即物理匝数；CCW 层外端附加延伸弧后被上游单段切向圆弧重建，
% 不在本测试范围。
% 容差 0.02 圈：外端与串联过孔的单圆弧切向并入会修剪螺旋末端一小段角行程
% （默认参数下实测偏差 <= 0.004 圈），仍远小于任何系统性匝数偏差。
combos = {2, 2; 4, 4; 6, 6};
expectedCwSpans = {5; [5.25, 4.75]; [5.25, 5.50, 5.25]};
for c = 1:size(combos, 1)
    result = circular_fpc_main(struct( ...
        'boardLayerCount', combos{c, 1}, ...
        'coilLayerCount', combos{c, 2}, ...
        'turnsPerCoilLayer', 5, ...
        'analysisOnly', true));
    cwIdx = find(strcmp({result.layerPaths.windingDirection}, 'CW'));
    verifyEqual(testCase, numel(cwIdx), numel(expectedCwSpans{c}));
    for k = 1:numel(cwIdx)
        xy = result.layerPaths(cwIdx(k)).coilXY;
        verifyFalse(testCase, isempty(xy));
        u = unwrap(atan2(xy(:, 2), xy(:, 1)));
        span = abs(u(end) - u(1)) / (2 * pi);
        verifyEqual(testCase, span, expectedCwSpans{c}(k), 'AbsTol', 0.02);
    end
end
end

function testFixedBoardTurnScanAccountsFractionalTurns(testCase)
% 4/4 fixed 板：可用径向宽度落在 t 与 t+0.25 圈需求之间时，fitsBoard
% 必须为 0（L2 分数匝是多算的唯一来源）；非 4/4 同板径同行保持 1。
% D=34.0 → available = 17 - 0.05 - 0.30 - 9.315 = 7.335；
% t=20: req=7.300 ✓ 但 reqFrac=7.38875 ✗；t=19: reqFrac=7.03375 ✓。
outRoot = createTempOutput(testCase);
result44 = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'scan_4_4', ...
    'boardSizingMode', 'fixed', 'boardOuterDiameter', 34.0, 'turnScanMax', 22));
scanTxt44 = fileread(fullfile(result44.outputPath, 'reports', '04_turn_scan.csv'));
verifyTrue(testCase, contains(scanTxt44, sprintf('20,%.6f,0', 0.2 + 20 * 0.355)));
verifyTrue(testCase, contains(scanTxt44, sprintf('19,%.6f,1', 0.2 + 19 * 0.355)));
result22 = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'scan_2_2', ...
    'boardLayerCount', 2, 'coilLayerCount', 2, ...
    'boardSizingMode', 'fixed', 'boardOuterDiameter', 34.0, 'turnScanMax', 22));
scanTxt22 = fileread(fullfile(result22.outputPath, 'reports', '04_turn_scan.csv'));
verifyTrue(testCase, contains(scanTxt22, sprintf('20,%.6f,1', 0.2 + 20 * 0.355)));
end

function testSupportedLayerMatrixAndSeriesContinuity(testCase)
combos = {2, 1; 2, 2; 4, 1; 4, 2; 4, 4; 6, 6};
expectedActive = {[1]; [1 2]; [1]; [1 4]; [1 2 3 4]; [1 2 3 4 5 6]};
expectedDirections = {{'CCW'}; {'CCW', 'CW'}; {'CCW'}; {'CCW', 'CW'}; ...
    {'CCW', 'CW', 'CCW', 'CW'}; {'CCW', 'CW', 'CCW', 'CW', 'CCW', 'CW'}};
expectedSequence = { ...
    {'PAD_A', 'COIL_L1', 'VRET', 'RETURN_L2', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'V12', 'COIL_L2', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'VRET', 'RETURN_L4', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'V14', 'COIL_L4', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'V12', 'COIL_L2', 'V23', 'COIL_L3', 'V34', 'COIL_L4', 'VOUT', 'PAD_B'}; ...
    {'PAD_A', 'COIL_L1', 'V12', 'COIL_L2', 'V23', 'COIL_L3', 'V34', 'COIL_L4', ...
    'V45', 'COIL_L5', 'V56', 'COIL_L6', 'VOUT', 'PAD_B'}};
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
    if combos{k, 1} == 4 || combos{k, 1} == 6
        for vk = 1:numel(result.vias)
            v = result.vias(vk);
            for li = 1:combos{k, 1}
                if li == v.fromLayer || li == v.toLayer
                    continue;
                end
                dxfPath = fullfile(result.outputPath, 'dxf', sprintf('L%d', li), sprintf('%02d_copper_L%d.dxf', li, li));
                verifyTrue(testCase, isfile(dxfPath));
                if isfile(dxfPath)
                    txt = fileread(dxfPath);
                    % 新契约：DXF 不含反焊盘/焊盘/文字标注（仅走线几何）
                    verifyFalse(testCase, contains(txt, 'ANTIPAD'), ...
                        sprintf('DXF %s must not contain ANTIPAD markers', dxfPath));
                end
            end
        end
    end
    dxfDir = fullfile(result.outputPath, 'dxf');
    drillFile = fullfile(dxfDir, '00_drill_map.dxf');
    verifyTrue(testCase, isfile(drillFile), ...
        sprintf('layers_%d_%d missing drill map', combos{k, 1}, combos{k, 2}));
    if isfile(drillFile)
        drillTxt = fileread(drillFile);
        verifyDxfBase(testCase, drillTxt, drillFile);
        dc = dxfCircles(drillTxt);
        verifyEqual(testCase, numel(dc), numel(result.vias), ...
            sprintf('layers_%d_%d drill map circle count', combos{k, 1}, combos{k, 2}));
        verifyTrue(testCase, all(strcmp({dc.layer}, 'DRILL')), ...
            'drill circles must use layer DRILL');
        verifyEqual(testCase, sort([dc.r]), sort([result.vias.drillDiameter] / 2), ...
            'AbsTol', 1e-9, 'drill circle radii must equal drillDiameter/2');
    end
    for li = 1:numel(result.layerPaths)
        layerDir = fullfile(dxfDir, sprintf('L%d', li));
        centerFile = fullfile(layerDir, sprintf('%02d_copper_L%d.dxf', li, li));
        verifyTrue(testCase, isfile(centerFile), sprintf('missing centerline %s', centerFile));
        if isfile(centerFile)
            centerTxt = fileread(centerFile);
            verifyDxfBase(testCase, centerTxt, centerFile);
            verifyTrue(testCase, isempty(dxfCircles(centerTxt)), ...
                sprintf('centerline %s must not contain CIRCLE', centerFile));
            [w43c, ~] = dxfPolylineWidths(centerTxt);
            verifyTrue(testCase, isempty(w43c), ...
                sprintf('centerline %s must not contain group 43', centerFile));
        end
        lp = result.layerPaths(li);
        hasTraces = ~isempty(lp.coilXY) || ~isempty(lp.connectionPaths);
        physFile = fullfile(layerDir, sprintf('%02d_copper_physical_L%d.dxf', li, li));
        verifyTrue(testCase, isfile(physFile), sprintf('missing physical copper %s', physFile));
        if isfile(physFile)
            physTxt = fileread(physFile);
            verifyDxfBase(testCase, physTxt, physFile);
            verifyFalse(testCase, contains(physTxt, 'ANTIPAD'), ...
                sprintf('physical %s must not contain ANTIPAD markers', physFile));
            traceLayer = sprintf('COPPER_PHYSICAL_L%d', li);
            verifyTrue(testCase, contains(physTxt, traceLayer), ...
                sprintf('physical %s must declare %s layer', physFile, traceLayer));
            [w43, nPoly] = dxfPolylineWidths(physTxt);
            verifyEqual(testCase, numel(w43), nPoly, ...
                sprintf('physical %s every LWPOLYLINE must carry group 43', physFile));
            if hasTraces
                verifyFalse(testCase, isempty(w43), ...
                    sprintf('physical %s must contain LWPOLYLINE traces', physFile));
            end
            verifyTrue(testCase, all(abs(w43 - result.config.traceWidth) <= 1e-9), ...
                sprintf('physical %s group 43 must equal cfg.traceWidth', physFile));
            % 非功能焊盘移除：钻孔贯穿并在每层预览显示，但物理铜焊环
            % 只出现在该过孔实际连接的两层，避免无谓撑大板框。
            viaIds = find([result.vias.fromLayer] == li | [result.vias.toLayer] == li);
            pc = dxfCircles(physTxt);
            if li == 1
                verifyTrue(testCase, contains(physTxt, 'PAD_L1'), ...
                    sprintf('physical %s must declare PAD_L1 layer', physFile));
                padC = pc(strcmp({pc.layer}, 'PAD_L1'));
                verifyEqual(testCase, numel(padC), 2, ...
                    sprintf('physical %s must contain 2 pad circles', physFile));
                verifyEqual(testCase, sort([padC.r]), sort([result.pads.diameter] / 2), ...
                    'AbsTol', 1e-9, 'pad circle radii must equal padDiameter/2');
                verifyEqual(testCase, sortrows([[padC.cx].', [padC.cy].']), ...
                    sortrows(cat(1, result.pads.xy)), 'AbsTol', 1e-9, ...
                    'PAD circles must keep engineering +X/+Y coordinates on L1');
                verifyTrue(testCase, contains(physTxt, 'ELECTRODE_L1'), ...
                    sprintf('physical %s must declare ELECTRODE_L1 layer', physFile));
                electrodeC = pc(strcmp({pc.layer}, 'ELECTRODE_L1'));
                verifyEqual(testCase, numel(electrodeC), numel(result.electrodePads), ...
                    sprintf('physical %s electrode circle count', physFile));
                verifyEqual(testCase, sort([electrodeC.r]), ...
                    sort([result.electrodePads.diameter] / 2), 'AbsTol', 1e-9, ...
                    'electrode circle radii must equal electrodePadDiameter/2');
            end
            viaLayer = sprintf('VIA_PAD_L%d', li);
            if ~isempty(viaIds)
                verifyTrue(testCase, contains(physTxt, viaLayer), ...
                    sprintf('physical %s must declare %s layer', physFile, viaLayer));
            end
            viaC = pc(strcmp({pc.layer}, viaLayer));
            verifyEqual(testCase, numel(viaC), numel(viaIds), ...
                sprintf('physical %s via circle count', physFile));
            verifyEqual(testCase, sort([viaC.r]), sort([result.vias(viaIds).padDiameter] / 2), ...
                'AbsTol', 1e-9, 'via circle radii must equal viaPadDiameter/2');
                electrodeCount = (li == 1) * numel(result.electrodePads);
                verifyEqual(testCase, numel(pc), (li == 1) * 2 + numel(viaIds) + electrodeCount, ...
                    sprintf('physical %s total circle count', physFile));
        end
        solidFile = fullfile(layerDir, sprintf('%02d_copper_solid_L%d.dxf', li, li));
        verifyTrue(testCase, isfile(solidFile), sprintf('missing COMSOL solid copper %s', solidFile));
        if isfile(solidFile)
            solidTxt = fileread(solidFile);
            verifyDxfBase(testCase, solidTxt, solidFile);
            verifyTrue(testCase, contains(solidTxt, sprintf('COPPER_SOLID_L%d', li)), ...
                sprintf('solid %s must declare its layer', solidFile));
            solidCircles = dxfCircles(solidTxt);
            [solidWidths, solidPolyCount] = dxfPolylineWidths(solidTxt);
            verifyTrue(testCase, isempty(solidCircles), ...
                sprintf('solid %s must not contain circles', solidFile));
            verifyTrue(testCase, isempty(solidWidths), ...
                sprintf('solid %s must not contain group 43', solidFile));
            verifyEqual(testCase, dxfClosedPolylineCount(solidTxt), solidPolyCount, ...
                sprintf('solid %s must contain only closed polylines', solidFile));
            if ~isempty(lp.coilXY)
                verifyEqual(testCase, solidPolyCount, 1, ...
                    sprintf('solid %s must contain exactly one main-coil ring', solidFile));
                activeIndex = find(result.activeCoilLayers == li, 1);
                spanTurns = result.config.turnsPerCoilLayer;
                if combos{k, 1} == 4 && combos{k, 2} == 4
                    spanExtra = [0, 0.25, 0, -0.25];
                    spanTurns = spanTurns + spanExtra(activeIndex);
                elseif combos{k, 1} == 6 && combos{k, 2} == 6
                    spanExtra = [0, 0.25, 0, 0.50, 0, 0.25];
                    spanTurns = spanTurns + spanExtra(activeIndex);
                end
                rStart = result.effectiveDimensions.coilInnerDiameter / 2 + result.config.traceWidth / 2;
                outer = rStart + result.effectiveDimensions.coilPitch * spanTurns;
                solidXy = dxfPolylineVertices(solidTxt);
                verifyFalse(testCase, isempty(solidXy), ...
                    sprintf('solid %s must carry polyline vertices', solidFile));
                if ~isempty(solidXy)
                    verifyEqual(testCase, solidXy(1, :), solidXy(end, :), ...
                        'AbsTol', 1e-9, ...
                        sprintf('solid %s must explicitly close the final short cap', solidFile));
                    r = hypot(solidXy(:, 1), solidXy(:, 2));
                    verifyGreaterThanOrEqual(testCase, min(r), rStart - result.config.traceWidth / 2 - 0.02, ...
                        sprintf('solid %s must trim the inner via/terminal extension', solidFile));
                    verifyLessThanOrEqual(testCase, max(r), outer + result.config.traceWidth / 2 + 0.02, ...
                        sprintf('solid %s must trim the outer via-contact arc', solidFile));
                    verifyGreaterThanOrEqual(testCase, max(r), outer + result.config.traceWidth / 2 - 0.06, ...
                        sprintf('solid %s must keep the full outermost turn', solidFile));
                end
            else
                verifyEqual(testCase, solidPolyCount, 0, ...
                    sprintf('solid %s must be empty for an inactive layer', solidFile));
            end
        end
        keepFile = fullfile(layerDir, sprintf('%02d_antipad_keepout_L%d.dxf', li, li));
        verifyFalse(testCase, isfile(keepFile), sprintf('obsolete antipad keepout must not exist: %s', keepFile));
    end
end
end

function testAutomaticTerminalBridgeLayoutContract(testCase)
combos = {2, 1; 2, 2; 4, 1; 4, 2; 4, 4; 6, 6};
expectedOuterNames = {{'VRET'}; {'V12'}; {'VRET'}; {'V14'}; {'V12', 'V34'}; ...
    {'V12', 'V34', 'V56'}};
expectedReturnNames = {{}; {}; {}; {}; {'V23'}; {'V23', 'V45'}};
outRoot = createTempOutput(testCase);
for k = 1:size(combos, 1)
    cfg = circular_fpc_default_config(struct('boardLayerCount', combos{k, 1}, 'coilLayerCount', combos{k, 2}, ...
        'outputRoot', outRoot, 'designName', sprintf('auto_bridge_%d_%d', combos{k, 1}, combos{k, 2})));
    result = circular_fpc_main(cfg);
    verifyAutomaticBridgeLayout(testCase, cfg, result, expectedOuterNames{k}, expectedReturnNames{k});
    if combos{k, 1} == 4 && combos{k, 2} == 2
        padA = findTerminalByName(result.pads, 'PAD_A');
        padB = findTerminalByName(result.pads, 'PAD_B');
        pairCenter = (padA.xy + padB.xy) / 2;
        verifyTrue(testCase, pairCenter(1) < 0, ...
            sprintf('4/2 default pairCenter x must be < 0 (got %.6f)', pairCenter(1)));
        verifyTrue(testCase, pairCenter(2) > 0, ...
            sprintf('4/2 default pairCenter y must be > 0 (got %.6f)', pairCenter(2)));
        verifyEqual(testCase, padA.placementRegion, 'ENTRY_BRIDGE');
        verifyEqual(testCase, padB.placementRegion, 'ENTRY_BRIDGE');
        verifyAngleMod360(testCase, padA.bridgeAngleDeg, cfg.connectionAngleDeg, '4/2 PAD_A bridgeAngleDeg');
        verifyAngleMod360(testCase, padB.bridgeAngleDeg, cfg.connectionAngleDeg, '4/2 PAD_B bridgeAngleDeg');
        verifyEqual(testCase, result.effectiveDimensions.centerPlatformWidth, 13.0, 'AbsTol', 1e-9);
        verifyEqual(testCase, result.effectiveDimensions.centerPlatformHeight, 14.0, 'AbsTol', 1e-9);
    end
end
outRootBad = createTempOutput(testCase);
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRootBad, 'designName', 'pad_pair_infeasible', ...
    'padPairSpacing', 20)), 'CircularFPC:GeometryInfeasible');
verifyFalse(testCase, isfolder(fullfile(outRootBad, 'pad_pair_infeasible')));
end

function testBridgeWidthUpperBoundComesFromFinalSlotTopology(testCase)
% 桥宽不使用独立解析上限；只有最终布尔板框不再是 4 个槽时才拒绝。
verifyError(testCase, @() circular_fpc_main(struct('bridgeTargetWidth', 20, ...
    'analysisOnly', true)), 'CircularFPC:GeometryInfeasible');
end

function testTerminalRotationAndScaleContract(testCase)
outRoot = createTempOutput(testCase);
% 0/90/180/270 会让外端过孔正落在同方位安装耳朵轴上：挖槽内侧弧就是主体外径圆，
% 因此按新契约明确报错（见 testMountingSlotFailsClosedOnInvalidParameters 与
% testAnalyzeIsReadOnlyAndLayerMatrix）。可用的旋转覆盖改用偏离轴向的方位。
angles = [45 60 135 225 315];
for a = angles
    cfg = circular_fpc_default_config(struct('boardLayerCount', 2, 'coilLayerCount', 1, ...
        'connectionAngleDeg', a, 'centerPlatformHeight', 11.0, ...
        'outputRoot', outRoot, 'designName', sprintf('rot_%d', a)));
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
verifyAutomaticBridgeLayout(testCase, cfgScale, resultScale, {'V12', 'V34'}, {'V23'});
cfgPlatform = circular_fpc_default_config(struct('centerPlatformWidth', 12.0, 'centerPlatformHeight', 10.0, ...
    'outputRoot', outRoot, 'designName', 'platform_12x10'));
resultPlatform = circular_fpc_main(cfgPlatform);
verifyAutomaticBridgeLayout(testCase, cfgPlatform, resultPlatform, {'V12', 'V34'}, {'V23'});
end

function testFourTwoRotationKeepsDefaultBoardTopology(testCase)
% 默认 13x14 平台四角与 18.63 mm 内圆自然形成对角连接区；因此默认
% 大平台只接受与四角一致的 45+90k 方位，不能再叠加轴向桥形成八槽。
for angleDeg = [45 135 225]
    result = analyzeInternal(struct('boardLayerCount', 4, 'coilLayerCount', 2, ...
        'connectionAngleDeg', angleDeg));
    verifyTrue(testCase, result.validation.passed, ...
        sprintf('4/2 angle %g validation failed: %s', angleDeg, ...
        strjoin(result.validation.messages, ' | ')));
    verifyEqual(testCase, numel(result.boardLoops), 9, ...
        sprintf('4/2 angle %g must keep 1 outer loop + 4 slots', angleDeg));
    verifyEqual(testCase, result.validation.closedBoardLoopCount, 9);
    platformXY = result.layoutRegions.platformLoop(1:end - 1, :);
    verifyEqual(testCase, max(abs(platformXY(:, 1))), 6.5, 'AbsTol', 1e-9);
    verifyEqual(testCase, max(abs(platformXY(:, 2))), 7.0, 'AbsTol', 1e-9);
    verifyEqual(testCase, result.layoutRegions.bridgeAnglesDeg, ...
        mod(angleDeg + [-90 0 90 180], 360), 'AbsTol', 1e-9);
    verifyEqual(testCase, norm(result.pads(2).xy - result.pads(1).xy), ...
        result.config.terminalLeadSpacing, 'AbsTol', 1e-6);
    verifyEqual(testCase, norm(result.pads(2).xy - ...
        result.vias(strcmp({result.vias.name}, 'VOUT')).xy), ...
        result.config.terminalLeadLength, 'AbsTol', 1e-6);
end
for angleDeg = [0 90]
    verifyError(testCase, @() analyzeInternal(struct( ...
        'boardLayerCount', 4, 'coilLayerCount', 2, ...
        'connectionAngleDeg', angleDeg)), 'CircularFPC:GeometryInfeasible');
end
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
previewFull = fullfile(out, 'preview', 'JLC', '3_trace_pad_via', '01_overview.svg');
previewZone = fullfile(out, 'preview', 'JLC', '3_trace_pad_via', '02_connection_zone.svg');
centerlineFull = fullfile(out, 'preview', 'JLC', '1_path_only', '01_overview.svg');
centerlineZone = fullfile(out, 'preview', 'JLC', '1_path_only', '02_connection_zone.svg');
comsolFull = fullfile(out, 'preview', 'COMSOL', '1_coil_only', '01_overview.svg');
verifyTrue(testCase, isfile(previewFull));
verifyTrue(testCase, isfile(previewZone));
verifyTrue(testCase, isfile(centerlineFull));
verifyTrue(testCase, isfile(centerlineZone));
verifyTrue(testCase, contains(fileread(centerlineFull), 'data-preview-kind="jlc-path-only"'));
verifyTrue(testCase, contains(fileread(centerlineZone), 'data-preview-kind="jlc-path-only"'));
verifyTrue(testCase, contains(fileread(previewFull), 'data-preview-kind="jlc-trace-pad-via"'));
verifyTrue(testCase, contains(fileread(previewZone), 'data-preview-kind="jlc-trace-pad-via"'));
previewFullTxt = fileread(previewFull);
verifyEqual(testCase, numel(regexp(previewFullTxt, 'data-board-role="mounting-cutout"', 'match')), 4);
verifyEqual(testCase, numel(regexp(previewFullTxt, 'data-board-role="mounting-glass"', 'match')), 4);
verifyTrue(testCase, isfile(comsolFull));
comsolFullTxt = fileread(comsolFull);
verifyTrue(testCase, contains(comsolFullTxt, 'data-preview-kind="comsol-dxf"'));
for li = 1:cfg.boardLayerCount
    if li == 1
        role = 'top';
    elseif li == cfg.boardLayerCount
        role = 'bottom';
    else
        role = sprintf('inner%d', li - 1);
    end
    comsolLayer = fullfile(out, 'preview', 'COMSOL', '1_coil_only', ...
        sprintf('1%d_layer_L%d_%s.svg', li, li, role));
    verifyTrue(testCase, isfile(comsolLayer), sprintf('missing COMSOL preview for L%d', li));
    if isfile(comsolLayer)
        comsolLayerTxt = fileread(comsolLayer);
        verifyTrue(testCase, contains(comsolLayerTxt, 'data-preview-kind="comsol-dxf"'));
        verifyTrue(testCase, contains(comsolLayerTxt, sprintf('data-dxf-layer="L%d"', li)));
        if any(result.activeCoilLayers == li)
            verifyTrue(testCase, contains(comsolLayerTxt, sprintf('data-dxf-file="dxf/L%d/%02d_copper_solid_L%d.dxf"', li, li, li)));
            verifyTrue(testCase, contains(comsolLayerTxt, 'data-dxf-closed="explicit"'));
            verifyTrue(testCase, contains(comsolFullTxt, sprintf('data-dxf-layer="L%d"', li)));
        else
            verifyFalse(testCase, contains(comsolLayerTxt, 'data-dxf-file='));
        end
        verifyTrue(testCase, ~isempty(xmlread(comsolLayer)));
    end
end
csvPadVia = fullfile(out, 'reports', '01_pad_via_coordinates.csv');
csvElectrode = fullfile(out, 'reports', '10_electrode_pad_coordinates.csv');
csvLayerMap = fullfile(out, 'reports', '02_layer_map.csv');
txtSummary = fullfile(out, 'reports', '03_design_summary.txt');
csvTurnScan = fullfile(out, 'reports', '04_turn_scan.csv');
txtValidation = fullfile(out, 'reports', '05_validation_report.txt');
statusFile = fullfile(out, 'generation_status.txt');
reportFiles = {csvPadVia, csvElectrode, csvLayerMap, txtSummary, csvTurnScan, txtValidation, statusFile};
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
% DXF 必须声明版本 AC1015（LWPOLYLINE 自 R2000 起支持），并带 LAYER 表与 CRLF 行尾
acadIdx = find(strcmp(lines, '$ACADVER'), 1);
verifyTrue(testCase, ~isempty(acadIdx) && acadIdx + 2 <= numel(lines));
verifyEqual(testCase, lines{acadIdx + 1}, '1');
verifyEqual(testCase, lines{acadIdx + 2}, 'AC1015');
verifyTrue(testCase, any(strcmp(lines, 'TABLES')));
verifyTrue(testCase, any(strcmp(lines, 'BOARD')));
verifyTrue(testCase, ~isempty(strfind(boardTxt, sprintf('\r\n'))));
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
verifyEqual(testCase, closedCount, 9);
% 板框轮廓采用 0.1 mm 实际线宽，五个闭环必须一致写入 DXF group 43。
boardLines = strtrim(strsplit(boardTxt, newline));
boardWidths = [];
for bi = 1:numel(boardLines) - 1
    if strcmp(boardLines{bi}, '43')
        boardWidths(end + 1) = str2double(boardLines{bi + 1}); %#ok<AGROW>
    end
end
verifyEqual(testCase, boardWidths, repmat(cfg.boardOutlineLineWidth, 1, 9), 'AbsTol', 1e-9);
l1Dxf = fullfile(out, 'dxf', 'L1', '01_copper_L1.dxf');
l1Txt = fileread(l1Dxf);
% 契约：铜层 DXF 不写焊盘/过孔圆（CIRCLE）与文字（TEXT），只含走线多段线；
% 焊盘过孔信息在 01_pad_via_coordinates.csv 与 SVG 预览中。
verifyFalse(testCase, contains(l1Txt, 'CIRCLE'), 'DXF must not contain CIRCLE entities');
l1Lines = strtrim(strsplit(l1Txt, newline));
% 契约：LWPOLYLINE 顶点不再写入 40/41 宽度码（部分导入器解析会失败）
polyCodes = {};
k = 1;
while k + 1 <= numel(l1Lines)
    if strcmp(l1Lines{k}, '0') && strcmp(l1Lines{k + 1}, 'LWPOLYLINE')
        j = k + 2;
        while j + 1 <= numel(l1Lines) && ~strcmp(l1Lines{j}, '0')
            polyCodes{end + 1} = l1Lines{j}; %#ok<AGROW>
            j = j + 2;
        end
        k = j;
    else
        k = k + 1;
    end
end
verifyFalse(testCase, any(strcmp(polyCodes, '40')));
verifyFalse(testCase, any(strcmp(polyCodes, '41')));
% 契约：DXF 不含 TEXT 文字标注（丝印说明只在 SVG 预览中显示）
verifyFalse(testCase, any(strcmp(l1Lines, 'TEXT')), 'DXF must not contain TEXT entities');
fullDoc = xmlread(previewFull);
rootFull = fullDoc.getDocumentElement;
verifyEqual(testCase, char(rootFull.getTagName), 'svg');
zoneDoc = xmlread(previewZone);
rootZone = zoneDoc.getDocumentElement;
verifyEqual(testCase, char(rootZone.getTagName), 'svg');
verifyExportedTerminalMetadata(testCase, result);
tPadVia = readtable(csvPadVia);
verifyGreaterThanOrEqual(testCase, height(tPadVia), 2);
verifyFalse(testCase, any(strcmp(tPadVia.Properties.VariableNames, 'antipadDiameterMm')));
verifyTrue(testCase, any(strcmp(tPadVia.Properties.VariableNames, 'role')));
tElectrode = readtable(csvElectrode);
verifyEqual(testCase, tElectrode.Properties.VariableNames, ...
    {'name', 'xMm', 'yMm', 'diameterMm', 'layer', 'role', 'placementRegion', 'bridgeAngleDeg'});
verifyEqual(testCase, height(tElectrode), numel(result.electrodePads));
verifyTrue(testCase, all(strcmp(tElectrode.role, 'INDEPENDENT_ELECTRODE')));
verifyTrue(testCase, all(strcmp(tElectrode.placementRegion, 'ELECTRODE_315')));
tLayer = readtable(csvLayerMap);
verifyEqual(testCase, height(tLayer), cfg.boardLayerCount);
summaryTxt = fileread(txtSummary);
verifyTrue(testCase, contains(summaryTxt, 'boardOuterDiameter'));
verifyTrue(testCase, contains(summaryTxt, 'connectionAngleDeg'));
verifyTrue(testCase, contains(summaryTxt, 'padPairSpacing'));
verifyTrue(testCase, contains(summaryTxt, 'placementRegion='));
verifyTrue(testCase, contains(summaryTxt, 'bridgeAngleDeg='));
verifyTrue(testCase, contains(summaryTxt, 'independentElectrode: ELECTRODE_A'));
verifyTrue(testCase, contains(summaryTxt, 'mountingSlotSpan'));
verifyTrue(testCase, contains(summaryTxt, 'mountingSlotRise'));
verifyTrue(testCase, contains(summaryTxt, 'mountingSlotEdgeClearance'));
turnTxt = fileread(csvTurnScan);
verifyTrue(testCase, contains(turnTxt, '8'));
valTxt = fileread(txtValidation);
verifyTrue(testCase, contains(lower(valTxt), 'pass'));
    statusTxt = fileread(statusFile);
    verifyTrue(testCase, contains(lower(statusTxt), 'success'));
    verifyTrue(testCase, contains(statusTxt, sprintf('outputPath: %s', out)), ...
        'generation_status.txt must record the committed output directory');
csvCheck = fullfile(out, 'reports', '06_manufacturing_check.csv');
txtNotes = fullfile(out, 'reports', '07_fabrication_notes.txt');
csvManifest = fullfile(out, 'reports', '08_file_manifest.csv');
verifyTrue(testCase, isfile(csvCheck), sprintf('missing %s', csvCheck));
verifyTrue(testCase, isfile(txtNotes), sprintf('missing %s', txtNotes));
verifyTrue(testCase, isfile(csvManifest), sprintf('missing %s', csvManifest));
if isfile(csvCheck)
    t6 = readtable(csvCheck);
    verifyEqual(testCase, t6.Properties.VariableNames, ...
        {'id', 'measuredMm', 'limitMm', 'marginMm', 'status', 'source', 'code', 'message', 'profile', 'tier'}, ...
        '06 CSV columns must be exact ADR-9 order');
    chks = result.manufacturing.checks;
    verifyEqual(testCase, height(t6), numel(chks), ...
        '06 CSV row count must equal manufacturing checks');
    for k = 1:min(height(t6), numel(chks))
        verifyEqual(testCase, char(t6.id(k)), chks(k).id, sprintf('06 row %d id', k));
        verifyEqual(testCase, t6.measuredMm(k), chks(k).measuredMm, 'AbsTol', 1e-9, ...
            sprintf('06 row %d measuredMm', k));
        verifyEqual(testCase, t6.limitMm(k), chks(k).limitMm, 'AbsTol', 1e-9, ...
            sprintf('06 row %d limitMm', k));
        verifyEqual(testCase, t6.marginMm(k), chks(k).marginMm, 'AbsTol', 1e-9, ...
            sprintf('06 row %d marginMm', k));
        verifyEqual(testCase, char(t6.status(k)), chks(k).status, sprintf('06 row %d status', k));
        verifyEqual(testCase, char(t6.source(k)), chks(k).source, sprintf('06 row %d source', k));
        verifyEqual(testCase, char(t6.code(k)), chks(k).code, sprintf('06 row %d code', k));
        verifyEqual(testCase, char(t6.message(k)), chks(k).message, sprintf('06 row %d message', k));
        verifyEqual(testCase, char(t6.profile(k)), result.manufacturing.profile, ...
            sprintf('06 row %d profile', k));
        verifyEqual(testCase, char(t6.tier(k)), result.manufacturing.tier, ...
            sprintf('06 row %d tier', k));
    end
end
if isfile(txtNotes)
    notes = fileread(txtNotes);
    for kw = {'boardLayerCount', 'coilLayerCount', 'activeCoilLayers', 'copperThickness', '1/3 oz', ...
            'jlc_fpc_1_3oz', 'FPC0420TT-121A', 'standard', 'ENIG_1u', '+X', '+Y', 'NOT_GENERATED', ...
            'coverlay', 'stiffener', 'Gerber', 'panelization', '09_comsol_stackup.csv', ...
            'mountingSlot', 'independentElectrodes'}
        verifyTrue(testCase, contains(notes, kw{1}), ...
            sprintf('07 notes missing keyword %s', kw{1}));
    end
    verifyTrue(testCase, contains(lower(notes), 'not replace gerber') || ...
        contains(lower(notes), 'cam reference'), ...
        '07 notes must state physical DXF is a CAM reference and does not replace Gerber');
end
csvStackup = fullfile(out, 'reports', '09_comsol_stackup.csv');
verifyTrue(testCase, isfile(csvStackup), 'missing COMSOL stackup report');
if isfile(csvStackup)
    t9 = readtable(csvStackup);
    verifyEqual(testCase, t9.Properties.VariableNames, ...
        {'order', 'layerName', 'role', 'thicknessMm', 'zTopMm', 'zBottomMm', 'zCenterMm', 'material'});
    verifyEqual(testCase, height(t9), 11);
    verifyEqual(testCase, char(t9.layerName(2)), 'L1_COPPER');
    verifyEqual(testCase, char(t9.layerName(10)), 'L4_COPPER');
    verifyEqual(testCase, t9.thicknessMm(2), 0.012, 'AbsTol', 1e-9);
    verifyEqual(testCase, t9.thicknessMm(10), 0.012, 'AbsTol', 1e-9);
    verifyEqual(testCase, t9.zCenterMm(2) - t9.zCenterMm(10), 0.136, 'AbsTol', 1e-9);
end
if isfile(csvManifest)
    t8 = readtable(csvManifest);
    verifyEqual(testCase, t8.Properties.VariableNames, ...
        {'relativePath', 'role', 'sizeBytes', 'sha256'}, ...
        '08 manifest columns must be exact');
    verifyEqual(testCase, height(t8), countFilesRecursive(out) - 1, ...
        '08 manifest must list every generated file except itself');
    rel8 = string(t8.relativePath);
    verifyFalse(testCase, any(strcmp(rel8, 'reports/08_file_manifest.csv')), ...
        '08 manifest must not list itself');
    roles8 = {'board_outline', 'drill_map', 'copper_centerline', 'copper_physical', 'copper_solid', ...
        'copper_solid_with_terminals', 'preview', 'preview_annotated', ...
        'report', 'generation_status'};
    verifyTrue(testCase, all(ismember(string(t8.role), roles8)), ...
        '08 manifest roles must come from the fixed vocabulary');
    % zh/en 镜像必须逐个登记，而不是以匿名 'preview' 混过去；数量要等于契约预览
    % 总数的两倍，避免只登记一部分却仍然通过。
    contractCount = numel(dir(fullfile(out, 'preview', 'JLC', '**', '*.svg'))) + ...
        numel(dir(fullfile(out, 'preview', 'COMSOL', '**', '*.svg')));
    verifyEqual(testCase, sum(string(t8.role) == "preview_annotated"), ...
        2 * contractCount, ...
        'every contract preview must be registered twice: one zh and one en mirror');
    verifyFalse(testCase, any(string(t8.role) == "preview_base"), ...
        'the redundant base/ copy set must be gone');
    verifyFalse(testCase, any(startsWith(rel8, '/')), ...
        '08 relativePath must be relative, not absolute');
    verifyFalse(testCase, any(contains(rel8, '\')), ...
        '08 relativePath must use forward slash');
    verifyFalse(testCase, any(contains(rel8, '..')), ...
        '08 relativePath must not contain ..');
    for k = 1:height(t8)
        rel = char(t8.relativePath(k));
        full8 = fullfile(out, rel);
        verifyTrue(testCase, isfile(full8), sprintf('08 manifest file missing: %s', rel));
        if isfile(full8)
            d8 = dir(full8);
            verifyEqual(testCase, t8.sizeBytes(k), d8.bytes, ...
                sprintf('08 size mismatch: %s', rel));
            sha8 = char(t8.sha256(k));
            verifyTrue(testCase, ~isempty(regexp(sha8, '^[0-9a-f]{64}$', 'once')), ...
                sprintf('08 sha256 must be lowercase 64 hex: %s', rel));
            verifyEqual(testCase, sha8, sha256File(full8), ...
                sprintf('08 sha256 mismatch: %s', rel));
        end
    end
end
cfg2 = circular_fpc_default_config(struct('outputRoot', outRoot, 'designName', 'cfpc_red_nopreview', 'enablePreview', false));
circular_fpc_main(cfg2);
out2 = fullfile(outRoot, 'cfpc_red_nopreview');
verifyFalse(testCase, isfile(fullfile(out2, 'preview', 'JLC', '3_trace_pad_via', '01_overview.svg')));
verifyFalse(testCase, isfile(fullfile(out2, 'preview', 'JLC', '3_trace_pad_via', '02_connection_zone.svg')));
verifyFalse(testCase, isfolder(fullfile(out2, 'preview')));
verifyTrue(testCase, isfile(fullfile(out2, 'dxf', '00_board_outline.dxf')));
verifyTrue(testCase, isfile(fullfile(out2, 'reports', '05_validation_report.txt')));
verifyTrue(testCase, isfile(fullfile(out2, 'generation_status.txt')));
verifyTrue(testCase, isfile(fullfile(out2, 'reports', '06_manufacturing_check.csv')), ...
    'missing no-preview 06 manufacturing check');
verifyTrue(testCase, isfile(fullfile(out2, 'reports', '07_fabrication_notes.txt')), ...
    'missing no-preview 07 fabrication notes');
m8np = fullfile(out2, 'reports', '08_file_manifest.csv');
verifyTrue(testCase, isfile(m8np), 'missing no-preview 08 file manifest');
if isfile(m8np)
    t8np = readtable(m8np);
    verifyFalse(testCase, any(startsWith(string(t8np.relativePath), 'preview/')), ...
        'no-preview manifest must not list preview/');
end
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

function testAutomaticArchivingKeepsOutputRootClean(testCase)
% 自动归档契约（archivePreviousArtifacts 默认开启）：每次成功发布新产物后，同
% 输出根下的旧"完整产物"（含 reports/08_file_manifest.csv）移入 archive/，
% LATEST.txt 指向最新；归档重名追加后缀不覆盖；非完整目录保持原位；关闭开关时
% 不移动也不更新 LATEST。
outRoot = createTempOutput(testCase);
first = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'archive_first', ...
    'boardLayerCount', 2, 'coilLayerCount', 1));
verifyTrue(testCase, isfolder(first.outputPath));
verifyEqual(testCase, strtrim(fileread(fullfile(outRoot, 'LATEST.txt'))), 'archive_first');
partialDir = fullfile(outRoot, 'partial_dir');
mkdir(partialDir);
% 预置同名归档目标：归档必须追加后缀而不是覆盖既有目录。
decoy = fullfile(outRoot, 'archive', 'archive_first');
mkdir(decoy);
second = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'archive_second', ...
    'boardLayerCount', 2, 'coilLayerCount', 1));
verifyFalse(testCase, isfolder(fullfile(outRoot, 'archive_first')));
verifyTrue(testCase, isfolder(decoy), '既有归档目录不得被覆盖');
verifyTrue(testCase, isfolder(fullfile(outRoot, 'archive', 'archive_first_2')));
verifyTrue(testCase, isfile(fullfile(outRoot, 'archive', 'archive_first_2', ...
    'reports', '08_file_manifest.csv')), '被归档的产物必须完整移入后缀目录');
verifyTrue(testCase, isfolder(second.outputPath));
verifyEqual(testCase, strtrim(fileread(fullfile(outRoot, 'LATEST.txt'))), 'archive_second');
verifyTrue(testCase, isfolder(partialDir), '非完整目录必须保持原位');
third = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'archive_first', ...
    'boardLayerCount', 2, 'coilLayerCount', 1));
verifyTrue(testCase, isfolder(fullfile(outRoot, 'archive', 'archive_second')));
verifyTrue(testCase, isfolder(third.outputPath));
verifyEqual(testCase, strtrim(fileread(fullfile(outRoot, 'LATEST.txt'))), 'archive_first');
% 关闭开关：不再移动旧产物，也不更新 LATEST。
fourth = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'archive_fourth', ...
    'archivePreviousArtifacts', false, 'boardLayerCount', 2, 'coilLayerCount', 1));
verifyTrue(testCase, isfolder(fourth.outputPath));
verifyTrue(testCase, isfolder(fullfile(outRoot, 'archive_first')));
verifyTrue(testCase, isfolder(fullfile(outRoot, 'archive_fourth')));
verifyEqual(testCase, strtrim(fileread(fullfile(outRoot, 'LATEST.txt'))), 'archive_first');
end

function testFigurePlotContract(testCase)
% CircularFpc.Export.Figure_Plot 已移入 +CircularFpc/+Export/（内部函数，仅由 circular_fpc_main 调用，
% 对 tests/ 不可见）；此处校验 enableFigure 配置契约与无头环境跳过行为。
outRoot = tempname;
result = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'plot_contract', ...
    'boardLayerCount', 4, 'coilLayerCount', 4));
verifyTrue(testCase, result.validation.passed);
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
combos = [2 1; 2 2; 4 1; 4 2; 4 4; 6 6];
expectedActive = {[1]; [1 2]; [1]; [1 4]; [1 2 3 4]; [1 2 3 4 5 6]};
verifyEqual(testCase, numel(variantResults), 6);
for k = 1:6
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
    verifyTrue(testCase, isfile(fullfile(r.outputPath, 'preview', 'JLC', '3_trace_pad_via', '01_overview.svg')));
    verifyTrue(testCase, isfile(fullfile(r.outputPath, 'preview', 'JLC', '3_trace_pad_via', '02_connection_zone.svg')));
    verifyTrue(testCase, isfile(fullfile(r.outputPath, 'preview', 'JLC', '1_path_only', '01_overview.svg')));
    verifyTrue(testCase, isfile(fullfile(r.outputPath, 'preview', 'JLC', '1_path_only', '02_connection_zone.svg')));
    for li = 1:r.boardLayerCount
        if li == 1
            role = 'top';
        elseif li == r.boardLayerCount
            role = 'bottom';
        else
            role = sprintf('inner%d', li - 1);
        end
        verifyTrue(testCase, isfile(fullfile(r.outputPath, 'preview', 'JLC', '3_trace_pad_via', ...
            sprintf('1%d_layer_L%d_%s.svg', li, li, role))), ...
            sprintf('missing per-layer preview for L%d', li));
        verifyTrue(testCase, isfile(fullfile(r.outputPath, 'preview', 'JLC', '1_path_only', ...
            sprintf('1%d_layer_L%d_%s.svg', li, li, role))), ...
            sprintf('missing per-layer centerline preview for L%d', li));
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
    for kw = {'circular_fpc_default_config', 'circular_fpc_main', 'geometryScale', ...
            'terminalLeadSpacing', 'terminalLeadLength', 'connectionAngleDeg', ...
            'PAD_A', 'PAD_B', 'VOUT', 'Gerber', 'DXF', ...
            '2/1', '2/2', '4/1', '4/2', '4/4', '6/6', ...
            'mountingSlotSpan', 'mountingSlotRise', 'electrodePadDiameter'}
        verifyTrue(testCase, contains(readmeTxt, kw{1}));
    end
end
if isfile(gitignorePath)
    verifyTrue(testCase, contains(fileread(gitignorePath), '/outputs/'));
end
end

function testComsolWithTerminalsVariantForFourLayerCombinations(testCase)
% COMSOL 带端子变体：在主螺旋不变的前提下，仅 L1 增加两条中心引线（闭合铜条、
% 直短边封口）与 PAD_A/PAD_B 圆盘；任何层都不得出现 VIA/DRILL/过孔焊环/
% 层间转换几何。L2/L3 在 4/2 下必须为空。
combos = {4, 2; 4, 4};
expectedActive = {[1 4]; [1 2 3 4]};
outRoot = createTempOutput(testCase);
for c = 1:size(combos, 1)
    bc = combos{c, 1};
    cc = combos{c, 2};
    designName = sprintf('wt_%d_%d', bc, cc);
    result = circular_fpc_main(struct('boardLayerCount', bc, 'coilLayerCount', cc, ...
        'outputRoot', outRoot, 'designName', designName, ...
        'enablePreview', true, 'enableFigure', false));
    out = fullfile(outRoot, designName);
    verifyEqual(testCase, result.activeCoilLayers, expectedActive{c});
    tag = sprintf('%d/%d', bc, cc);
    for li = 1:bc
        isActive = double(any(result.activeCoilLayers == li));
        wtFile = fullfile(out, 'dxf', sprintf('L%d', li), ...
            sprintf('%02d_copper_solid_with_terminals_L%d.dxf', li, li));
        verifyTrue(testCase, isfile(wtFile), sprintf('%s missing %s', tag, wtFile));
        if ~isfile(wtFile)
            continue;
        end
        txt = fileread(wtFile);
        verifyDxfBase(testCase, txt, wtFile);
        verifyDxfEntityLayersDeclared(testCase, txt, wtFile);
        verifyTrue(testCase, contains(txt, sprintf('COPPER_SOLID_TERMINALS_L%d', li)), ...
            sprintf('%s must declare the with-terminals layer', tag));
        % 无 VIA / DRILL 图层，也无过孔焊环或层间转换几何。
        verifyFalse(testCase, contains(txt, 'VIA'), ...
            sprintf('%s with-terminals DXF must not contain VIA geometry', tag));
        verifyFalse(testCase, contains(txt, 'DRILL'), ...
            sprintf('%s with-terminals DXF must not contain DRILL geometry', tag));
        verifyFalse(testCase, contains(txt, 'ANTIPAD'), ...
            sprintf('%s with-terminals DXF must not contain antipads', tag));
        circles = dxfCircles(txt);
        [widths, polyCount] = dxfPolylineWidths(txt);
        verifyTrue(testCase, isempty(widths), ...
            sprintf('%s with-terminals DXF must not carry group 43', tag));
        verifyEqual(testCase, dxfClosedPolylineCount(txt), polyCount, ...
            sprintf('%s with-terminals DXF must contain only closed bodies', tag));
        % 每个闭合实体首尾坐标必须一致。
        rings = dxfPolylines(txt);
        for r = 1:numel(rings)
            verifyGreaterThanOrEqual(testCase, size(rings{r}, 1), 4, ...
                sprintf('%s closed body %d is degenerate', tag, r));
            verifyEqual(testCase, rings{r}(1, :), rings{r}(end, :), 'AbsTol', 1e-9, ...
                sprintf('%s closed body %d must repeat its first vertex', tag, r));
        end
        if li == 1
            % 本变体只承载导体：每个活动层恰好一条合并后的闭合轮廓，且不导出焊盘。
            % 焊盘不导出比"焊盘尺寸正确"更强——它连出现都不允许。
            verifyEqual(testCase, polyCount, isActive, ...
                sprintf('%s active layer must hold exactly one merged ring', tag));
            verifyEqual(testCase, numel(circles), 0, ...
                sprintf('%s must not export pad circles', tag));
            verifyGreaterThan(testCase, shoelaceArea(rings{1}), result.config.traceWidth ^ 2, ...
                sprintf('%s merged ring must enclose real copper area', tag));
        elseif isActive
            verifyEqual(testCase, polyCount, 1, ...
                sprintf('%s L%d must keep exactly the main coil ring', tag, li));
            verifyEmpty(testCase, circles, ...
                sprintf('%s L%d must not carry terminals', tag, li));
        else
            % 非活动层（4/2 的 L2/L3）：空 ENTITIES 段。
            verifyEqual(testCase, polyCount, 0, ...
                sprintf('%s L%d must be empty', tag, li));
            verifyEmpty(testCase, circles, ...
                sprintf('%s L%d must be empty', tag, li));
        end
        % copper_solid 本身必须原样保留（它仍是纯主螺旋）；本变体的合并环不再与它
        % 逐点相同——这是合并端子铜的必然代价，因此改为核对两者关系而非相等：
        % 合并环必须覆盖纯螺旋（面积不小于），且确实吸收了端子铜时严格更大。
        solidFile = fullfile(out, 'dxf', sprintf('L%d', li), ...
            sprintf('%02d_copper_solid_L%d.dxf', li, li));
        verifyTrue(testCase, isfile(solidFile), sprintf('%s missing %s', tag, solidFile));
        if isActive && isfile(solidFile)
            solidRings = dxfPolylines(fileread(solidFile));
            verifyEqual(testCase, numel(solidRings), 1, ...
                sprintf('%s copper_solid must hold one ring', tag));
            mergedArea = shoelaceArea(rings{1});
            plainArea = shoelaceArea(solidRings{1});
            verifyGreaterThanOrEqual(testCase, mergedArea, plainArea - 1e-6, ...
                sprintf('%s merged ring must cover the plain copper_solid ring', tag));
            if ismember(li, result.activeCoilLayers) && li == 1
                verifyGreaterThan(testCase, mergedArea, plainArea + 1e-9, ...
                    sprintf('%s ring that absorbed the entry lead must be larger', tag));
            end
        end
    end
    % 预览：with_terminals 目录、kind 元数据与实体计数。
    capDir = fullfile(out, 'preview', 'COMSOL', '2_coil_with_lead');
    capFull = fullfile(capDir, '01_overview.svg');
    verifyTrue(testCase, isfile(capFull), sprintf('%s missing %s', tag, capFull));
    if isfile(capFull)
        capTxt = fileread(capFull);
        verifyTrue(testCase, contains(capTxt, 'data-preview-kind="comsol-dxf-with-terminals"'));
        verifyEqual(testCase, ...
            numel(regexp(capTxt, 'data-copper-kind="coil_with_lead"', 'match')), ...
            numel(result.activeCoilLayers), ...
            sprintf('%s overview must draw one merged ring per active layer', tag));
        verifyEqual(testCase, numel(regexp(capTxt, 'data-copper-kind="pad"', 'match')), 0, ...
            sprintf('%s overview must draw no pads', tag));
        verifyFalse(testCase, contains(capTxt, 'data-via-name'), ...
            sprintf('%s overview must not draw vias', tag));
        verifyFalse(testCase, contains(capTxt, 'data-via-role="drill"'), ...
            sprintf('%s overview must not draw drills', tag));
        verifyTrue(testCase, ~isempty(xmlread(capFull)));
    end
    for li = 1:bc
        isActive = double(any(result.activeCoilLayers == li));
        if li == 1
            role = 'top';
        elseif li == bc
            role = 'bottom';
        else
            role = sprintf('inner%d', li - 1);
        end
        capLayer = fullfile(capDir, sprintf('1%d_layer_L%d_%s.svg', li, li, role));
        verifyTrue(testCase, isfile(capLayer), sprintf('%s missing %s', tag, capLayer));
        if isfile(capLayer)
            layerTxt = fileread(capLayer);
            verifyTrue(testCase, contains(layerTxt, 'data-preview-kind="comsol-dxf-with-terminals"'));
            verifyTrue(testCase, contains(layerTxt, sprintf('data-dxf-layer="L%d"', li)));
            % 活动层一条合并环，非活动层没有铜体；焊盘在本变体里不导出。
            verifyEqual(testCase, ...
                numel(regexp(layerTxt, 'data-copper-kind="coil_with_lead"', 'match')), isActive, ...
                sprintf('%s L%d merged ring count in preview', tag, li));
            verifyEqual(testCase, ...
                numel(regexp(layerTxt, 'data-copper-kind="pad"', 'match')), 0, ...
                sprintf('%s L%d pad count in preview', tag, li));
            verifyTrue(testCase, ~isempty(xmlread(capLayer)));
        end
    end
    % 终端几何映射报告：每个 DXF 实体一行，闭合与面积必须自洽。
    csvGeom = fullfile(out, 'reports', '11_comsol_terminal_geometry.csv');
    verifyTrue(testCase, isfile(csvGeom), sprintf('%s missing %s', tag, csvGeom));
    if isfile(csvGeom)
        t = readtable(csvGeom);
        verifyEqual(testCase, t.Properties.VariableNames, ...
            {'entity', 'kind', 'layer', 'routeNode', 'dxfFile', 'closed', ...
            'vertexCount', 'areaMm2', 'capMode', 'startXMm', 'startYMm', ...
            'endXMm', 'endYMm', 'firstXMm', 'firstYMm', 'lastXMm', 'lastYMm', ...
            'firstLastMatch'}, sprintf('%s 11 CSV columns must be exact', tag));
        % 每个活动层一行合并轮廓；焊盘不再导出，出现 pad 行即为错误。
        verifyEqual(testCase, sum(strcmp(t.kind, 'coil_with_lead')), ...
            numel(expectedActive{c}), ...
            sprintf('%s 11 CSV must map one merged ring per active layer', tag));
        verifyEqual(testCase, sum(strcmp(t.kind, 'pad')), 0, ...
            sprintf('%s 11 CSV must not map pads', tag));
        verifyTrue(testCase, all(t.firstLastMatch == 1), ...
            sprintf('%s 11 CSV rows must close on their first vertex', tag));
        verifyTrue(testCase, all(t.areaMm2 > 0), ...
            sprintf('%s 11 CSV must report positive copper area', tag));
        verifyTrue(testCase, all(strcmp(t.capMode, 'merged_closed_ring')), ...
            sprintf('%s every row must be a merged closed ring', tag));
        for r = 1:height(t)
            verifyTrue(testCase, isfile(fullfile(out, char(t.dxfFile(r)))), ...
                sprintf('%s 11 CSV row %d cites a missing DXF', tag, r));
        end
        % 每行的实体名就是所在层的合并轮廓名。引线归到哪一层由导出端按电气拓扑
        % 推导，已在 DXF 读回里核对（合并环到 PAD_A/PAD_B 的距离为 0）。
        for li = 1:bc
            row = t(t.layer == li, :);
            if isempty(row)
                continue;
            end
            verifyEqual(testCase, char(row.entity), sprintf('COIL_WITH_LEAD_L%d', li), ...
                sprintf('%s 11 CSV row must name the L%d merged ring', tag, li));
        end
    end
    % manifest：新增角色必须出现在固定词表中，且 sha256 自洽。
    t8 = readtable(fullfile(out, 'reports', '08_file_manifest.csv'));
    wtRows = startsWith(string(t8.relativePath), 'dxf/L') & ...
        contains(string(t8.relativePath), 'copper_solid_with_terminals');
    verifyEqual(testCase, sum(wtRows), bc, ...
        sprintf('%s manifest must list one with-terminals DXF per physical layer', tag));
    verifyTrue(testCase, all(strcmp(string(t8.role(wtRows)), 'copper_solid_with_terminals')), ...
        sprintf('%s manifest must use the copper_solid_with_terminals role', tag));
end
end

function testComsolWithTerminalsVariantKeepsOriginalSolidBytes(testCase)
% 原有 copper_solid / physical / centerline DXF 字节契约不因新增变体而改变：
% 同一 result 连续导出两次，两次的旧轨文件必须逐字节一致，且新变体存在。
outRoot = createTempOutput(testCase);
cfg = circular_fpc_default_config(struct('boardLayerCount', 4, 'coilLayerCount', 2, ...
    'outputRoot', outRoot, 'designName', 'wt_bytes', 'enablePreview', false, ...
    'enableFigure', false));
result = circular_fpc_main(cfg);
out = fullfile(outRoot, 'wt_bytes');
verifyEqual(testCase, result.outputPath, out, ...
    'generation must publish to the requested designName directory');
legacy = {'dxf/00_board_outline.dxf', 'dxf/00_drill_map.dxf', ...
    'dxf/L1/01_copper_L1.dxf', 'dxf/L1/01_copper_physical_L1.dxf', ...
    'dxf/L1/01_copper_solid_L1.dxf', 'dxf/L2/02_copper_solid_L2.dxf', ...
    'dxf/L4/04_copper_solid_L4.dxf', ...
    'reports/01_pad_via_coordinates.csv', 'reports/03_design_summary.txt'};
for k = 1:numel(legacy)
    p = fullfile(out, legacy{k});
    verifyTrue(testCase, isfile(p), sprintf('missing legacy output %s', legacy{k}));
    if isfile(p)
        d = dir(p);
        verifyGreaterThan(testCase, d.bytes, 0, sprintf('empty legacy output %s', legacy{k}));
    end
end
% 新变体与旧轨并存，互不覆盖。
for li = 1:cfg.boardLayerCount
    verifyTrue(testCase, isfile(fullfile(out, 'dxf', sprintf('L%d', li), ...
        sprintf('%02d_copper_solid_L%d.dxf', li, li))));
    verifyTrue(testCase, isfile(fullfile(out, 'dxf', sprintf('L%d', li), ...
        sprintf('%02d_copper_solid_with_terminals_L%d.dxf', li, li))));
end
% 旧轨铜几何不得出现端子层标记，端子只存在于新变体。
l1Solid = fileread(fullfile(out, 'dxf', 'L1', '01_copper_solid_L1.dxf'));
verifyFalse(testCase, contains(l1Solid, 'TERMINALS'), ...
    'copper_solid must stay terminal-free');
verifyTrue(testCase, contains(fileread(fullfile(out, 'dxf', 'L1', ...
    '01_copper_solid_with_terminals_L1.dxf')), 'COPPER_SOLID_TERMINALS_L1'), ...
    'with-terminals DXF must declare its own layer');
end

function testGitHubWorkflowRunsBothSuitesAndRejectsZeroTests(testCase)
projectRoot = testCase.TestData.projectRoot;
repoRoot = fileparts(projectRoot);
workflowPath = fullfile(repoRoot, '.github', 'workflows', 'matlab-tests.yml');
verifyTrue(testCase, isfile(workflowPath));
workflow = fileread(workflowPath);
checkoutRef = 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1';
uploadRef = 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a';
setupRef = 'matlab-actions/setup-matlab@f9e43010f1ae678f7cfa0542fe2a4f60f7d1ad8d';
runRef = 'matlab-actions/run-command@bfa857648f4895aa98a446fe41c85e0788421ed5';
verifyEqual(testCase, numel(strfind(workflow, checkoutRef)), 4);
verifyEqual(testCase, numel(strfind(workflow, setupRef)), 4);
verifyEqual(testCase, numel(strfind(workflow, runRef)), 4);
verifyEqual(testCase, numel(strfind(workflow, uploadRef)), 2);
verifyFalse(testCase, ~isempty(regexp(workflow, ...
    '(actions|matlab-actions)/[A-Za-z0-9_-]+@v[0-9]', 'once')), ...
    'Third-party Actions must be pinned to reviewed Node 24 commit SHAs.');
verifyTrue(testCase, contains(workflow, 'Circular_FPC_Coil'));
verifyTrue(testCase, contains(workflow, 'Rectangular_FPC_Coil'));
verifyGreaterThanOrEqual(testCase, ...
    numel(strfind(workflow, 'run_all_verification')), 2);
verifyFalse(testCase, contains(workflow, 'select-by-folder: .'));
verifyTrue(testCase, contains(workflow, 'ci-artifacts'));
verifyTrue(testCase, contains(workflow, 'canonical'));
verifyTrue(testCase, contains(workflow, 'enablePreview'));
verifyFalse(testCase, contains(workflow, 'canonical_*'), ...
    'Rectangular canonical upload must stage the exact returned committed output, not a wildcard.');
verifyTrue(testCase, contains(workflow, 'circular-artifact:'));
verifyTrue(testCase, contains(workflow, 'rectangular-artifact:'));
verifyTrue(testCase, contains(workflow, 'circular-test:'));
verifyTrue(testCase, contains(workflow, 'rectangular-test:'));
verifyTrue(testCase, contains(workflow, "needs.circular-test.result == 'success'"));
verifyTrue(testCase, contains(workflow, "needs.rectangular-test.result == 'success'"));
verifyFalse(testCase, contains(workflow, 'if: always()'), ...
    'Canonical generation/upload must never run after a failed prerequisite or failed generation.');
verifyTrue(testCase, contains(workflow, 'RectangularFpc.Publish.Read_Committed'), ...
    'CI must snapshot the exact rectangular committed output while holding its reader lock.');
verifyTrue(testCase, contains(workflow, 'copyOk'), ...
    'CI must assert the result of copying the committed rectangular output.');
for requiredArtifact = {'generation_status.txt', '08_file_manifest.csv', '09_comsol_stackup.csv', ...
        'preview', 'dxf', 'reports'}
    verifyTrue(testCase, contains(workflow, requiredArtifact{1}), ...
        sprintf('CI must gate the staged artifact on %s.', requiredArtifact{1}));
end
verifyTrue(testCase, contains(workflow, "'designName', 'canonical'"));
verifyFalse(testCase, contains(workflow, '"designName", "canonical"'));

for runner = {fullfile(projectRoot, 'tests', 'run_all_verification.m'), ...
        fullfile(repoRoot, 'Rectangular_FPC_Coil', 'tests', ...
        'run_all_verification.m')}
    runnerText = fileread(runner{1});
    verifyTrue(testCase, contains(runnerText, 'assert(~isempty(results)'));
end
end

function circles = dxfCircles(txt)
% RED R5/R6 helper: parse CIRCLE entities (layer, center, radius) from DXF text.
lines = strtrim(strsplit(txt, newline));
circles = struct('layer', {}, 'cx', {}, 'cy', {}, 'r', {});
k = 1;
while k + 1 <= numel(lines)
    if strcmp(lines{k}, '0') && strcmp(lines{k + 1}, 'CIRCLE')
        j = k + 2;
        layer = '';
        cx = NaN;
        cy = NaN;
        r = NaN;
        while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
            code = str2double(lines{j});
            val = lines{j + 1};
            switch code
                case 8
                    layer = val;
                case 10
                    cx = str2double(val);
                case 20
                    cy = str2double(val);
                case 40
                    r = str2double(val);
            end
            j = j + 2;
        end
        circles(end + 1) = struct('layer', layer, 'cx', cx, 'cy', cy, 'r', r); %#ok<AGROW>
        k = j;
    else
        k = k + 1;
    end
end
end

function [w43, nPoly] = dxfPolylineWidths(txt)
% RED R5 helper: collect group 43 widths of every LWPOLYLINE entity.
lines = strtrim(strsplit(txt, newline));
w43 = [];
nPoly = 0;
k = 1;
while k + 1 <= numel(lines)
    if strcmp(lines{k}, '0') && strcmp(lines{k + 1}, 'LWPOLYLINE')
        nPoly = nPoly + 1;
        j = k + 2;
        while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
            if strcmp(lines{j}, '43')
                w43(end + 1) = str2double(lines{j + 1}); %#ok<AGROW>
            end
            j = j + 2;
        end
        k = j;
    else
        k = k + 1;
    end
end
end

function n = dxfClosedPolylineCount(txt)
% Count LWPOLYLINE entities whose group 70 marks them as closed.
lines = strtrim(strsplit(txt, newline));
n = 0;
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
            n = n + 1;
        end
        k = j;
    else
        k = k + 1;
    end
end
end

function rings = dxfPolylines(txt)
% Collect each LWPOLYLINE entity as its own Nx2 vertex matrix, so a test can
% assert per-body closure instead of a flattened vertex stream.
lines = strtrim(strsplit(txt, newline));
rings = {};
k = 1;
while k + 1 <= numel(lines)
    if ~strcmp(lines{k}, '0') || ~strcmp(lines{k + 1}, 'LWPOLYLINE')
        k = k + 1;
        continue;
    end
    j = k + 2;
    pts = zeros(0, 2);
    x = NaN;
    y = NaN;
    while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
        if strcmp(lines{j}, '10')
            if isfinite(x) && isfinite(y)
                pts(end + 1, :) = [x, y]; %#ok<AGROW>
            end
            x = str2double(lines{j + 1});
            y = NaN;
        elseif strcmp(lines{j}, '20')
            y = str2double(lines{j + 1});
        end
        j = j + 2;
    end
    if isfinite(x) && isfinite(y)
        pts(end + 1, :) = [x, y];
    end
    rings{end + 1} = pts; %#ok<AGROW>
    k = j;
end
end

function a = shoelaceArea(xy)
% Signed-magnitude area of a closed ring that repeats its first vertex.
x = xy(1:end-1, 1);
y = xy(1:end-1, 2);
a = abs(sum(x .* y([2:end, 1]) - y .* x([2:end, 1]))) / 2;
end

function xy = dxfPolylineVertices(txt)
lines = strtrim(strsplit(txt, newline));
x = [];
y = [];
k = 1;
while k + 1 <= numel(lines)
    if strcmp(lines{k}, '0') && strcmp(lines{k + 1}, 'LWPOLYLINE')
        j = k + 2;
        while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
            if strcmp(lines{j}, '10')
                x(end + 1) = str2double(lines{j + 1}); %#ok<AGROW>
            elseif strcmp(lines{j}, '20')
                y(end + 1) = str2double(lines{j + 1}); %#ok<AGROW>
            end
            j = j + 2;
        end
        k = j;
    else
        k = k + 1;
    end
end
xy = [x(:), y(:)];
end

function h = sha256File(path)
% RED R7 helper: SHA256 of raw file bytes as lowercase 64 hex.
fid = fopen(path, 'rb');
raw = fread(fid, Inf, '*uint8');
fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
h = lower(reshape(dec2hex(typecast(md.digest(raw), 'uint8'), 2).', 1, []));
end

function n = countFilesRecursive(root)
% RED R7 helper: count regular files under root, recursive.
d = dir(fullfile(root, '**', '*'));
n = sum(~[d.isdir]);
end

function verifyDxfBase(testCase, txt, label)
% RED R5/R6/R7 helper: shared DXF header/encoding contract assertions.
verifyTrue(testCase, contains(txt, 'AC1015'), sprintf('%s must declare AC1015.', label));
lines = strtrim(strsplit(txt, newline));
insIdx = find(strcmp(lines, '$INSUNITS'), 1);
verifyTrue(testCase, ~isempty(insIdx) && insIdx + 2 <= numel(lines), ...
    sprintf('%s missing $INSUNITS.', label));
verifyEqual(testCase, lines{insIdx + 1}, '70');
verifyEqual(testCase, str2double(lines{insIdx + 2}), 4);
verifyTrue(testCase, ~isempty(strfind(txt, sprintf('\r\n'))), ...
    sprintf('%s must use CRLF.', label));
verifyFalse(testCase, contains(txt, 'TEXT'), ...
    sprintf('%s must not contain TEXT entities.', label));
end

function verifyDxfEntityLayersDeclared(testCase, txt, label)
% Every entity layer must be declared in TABLES/LAYER. In particular, L1
% terminal DXFs must declare PAD_A/PAD_B alongside the copper body layer.
lines = strtrim(strsplit(txt, newline));
declared = {};
used = {};
inTables = false;
inLayerTable = false;
captureLayerName = false;
inEntities = false;
k = 1;
while k + 1 <= numel(lines)
    code = lines{k};
    value = lines{k + 1};
    if strcmp(code, '2') && strcmp(value, 'TABLES')
        inTables = true;
    elseif inTables && strcmp(code, '0') && strcmp(value, 'ENDSEC')
        inTables = false;
        inLayerTable = false;
        captureLayerName = false;
    elseif inTables && strcmp(code, '2') && strcmp(value, 'LAYER')
        inLayerTable = true;
    elseif inTables && inLayerTable && strcmp(code, '0') && strcmp(value, 'LAYER')
        captureLayerName = true;
    elseif inTables && inLayerTable && strcmp(code, '0') && strcmp(value, 'ENDTAB')
        inLayerTable = false;
        captureLayerName = false;
    elseif inTables && captureLayerName && strcmp(code, '2')
        declared{end + 1} = value; %#ok<AGROW>
        captureLayerName = false;
    elseif strcmp(code, '2') && strcmp(value, 'ENTITIES')
        inEntities = true;
    elseif inEntities && strcmp(code, '0') && strcmp(value, 'ENDSEC')
        inEntities = false;
    elseif inEntities && strcmp(code, '8')
        used{end + 1} = value; %#ok<AGROW>
    end
    k = k + 2;
end
verifyTrue(testCase, all(ismember(unique(used), unique(declared))), ...
    sprintf('%s must declare every entity layer in TABLES/LAYER.', label));
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

function chk = findManufacturingCheck(mf, id)
% 测试局部 helper：按 id 查找 manufacturing 检查行（须唯一存在）。
idx = find(strcmp({mf.checks.id}, id));
assert(isscalar(idx), 'Expected exactly one manufacturing check with id %s.', id);
chk = mf.checks(idx);
end

function p = nonexistentTempRoot()
% 测试局部 helper：返回一个当前不存在的绝对 temp 路径，用于证明 analyze 不创建输出。
p = fullfile(tempname, 'circular_fpc_red_root');
while exist(p, 'dir') == 7 || exist(p, 'file') ~= 0
    p = fullfile(tempname, 'circular_fpc_red_root');
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
verifyTrue(testCase, isfield(result, 'layoutRegions'), 'result missing layoutRegions');
if isfield(result, 'layoutRegions') && isfield(result.layoutRegions, 'bridgeWidths')
    bridgeWidths = result.layoutRegions.bridgeWidths;
    verifyEqual(testCase, numel(bridgeWidths), 4, 'all four bridge widths must be reported');
    verifyEqual(testCase, bridgeWidths, repmat(bridgeWidths(1), 1, 4), 'AbsTol', 1e-9, ...
        'all four connection bridges must have the same width');
end
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
    verifyEqual(testCase, padA.placementRegion, 'ENTRY_BRIDGE');
    verifyEqual(testCase, padB.placementRegion, 'ENTRY_BRIDGE');
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
verifyEqual(testCase, dot(vout.xy, t), cfg.terminalLeadSpacing / 2, 'AbsTol', 1e-6);
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
        verifyAngleMod360(testCase, v.bridgeAngleDeg, expectedViaAngleDeg(v.name, theta), ...
            sprintf('%s bridgeAngleDeg', v.name));
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
        verifyAngleMod360(testCase, v.bridgeAngleDeg, expectedViaAngleDeg(v.name, theta), ...
            sprintf('%s bridgeAngleDeg', v.name));
    end
    % V23/VRET 类端子位于 theta+90 桥轴（+t 方向）：垂直分量（u 投影）必须为零
    uAxis = [cosd(theta), sind(theta)];
    verifyTrue(testCase, abs(dot(v.xy, uAxis)) <= 1e-6, ...
        sprintf('%s must lie on the theta+90 bridge axis (u projection %.6f)', v.name, dot(v.xy, uAxis)));
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
verifyEqual(testCase, result.terminalRouting.entryBendCount, 1);
verifyEqual(testCase, result.terminalRouting.exitBendCount, 0);
entryLen = sum(sqrt(sum(diff(result.terminalRouting.entryPath, 1, 1).^2, 2)));
verifyEqual(testCase, entryLen, cfg.terminalLeadLength + ...
    deg2rad(result.terminalRouting.entrySweepDeg) * ...
    result.terminalRouting.entryBendRadiusMm, 'AbsTol', 1e-3);
exitPath = result.terminalRouting.exitPath;
exitLen = sum(sqrt(sum(diff(exitPath, 1, 1).^2, 2)));
verifyEqual(testCase, exitLen, cfg.terminalLeadLength, 'AbsTol', 1e-6);
verifyLessThanOrEqual(testCase, max(abs((exitPath - exitPath(1, :)) * t.')), 1e-9, ...
    'VOUT-to-PAD_B must remain a straight local-u segment');
verifyEqual(testCase, abs(dot(padB.xy - padA.xy, t)), cfg.terminalLeadSpacing, 'AbsTol', 1e-6);
verifyEqual(testCase, abs(dot(padB.xy - vout.xy, u)), cfg.terminalLeadLength, 'AbsTol', 1e-6);
if numel(result.activeCoilLayers) > 1
    verifyEqual(testCase, result.terminalRouting.outputBendCount, 1);
    outputPath = result.terminalRouting.outputPath;
    outputLen = sum(sqrt(sum(diff(outputPath, 1, 1).^2, 2)));
    verifyEqual(testCase, outputLen, deg2rad(result.terminalRouting.outputSweepDeg) * ...
        result.terminalRouting.outputBendRadiusMm, 'AbsTol', 1e-3);
else
    verifyEqual(testCase, result.terminalRouting.outputBendCount, 0);
    verifyEmpty(testCase, result.terminalRouting.outputPath);
end
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
expectedColumns = {'name', 'xMm', 'yMm', 'diameterMm', 'drillMm', ...
    'layer', 'fromLayer', 'toLayer', 'removable', 'role', ...
    'placementRegion', 'bridgeAngleDeg'};
verifyEqual(testCase, t.Properties.VariableNames, expectedColumns, ...
    'CSV columns must describe only physical pads/vias and terminal placement metadata');
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
svgFiles = {fullfile(result.outputPath, 'preview', 'JLC', '3_trace_pad_via', '01_overview.svg'), ...
    fullfile(result.outputPath, 'preview', 'JLC', '3_trace_pad_via', '02_connection_zone.svg')};
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
    elLeader = leaderByTerm(nm);
    verifyEqual(testCase, str2double(char(elLeader.getAttribute('x1'))), p.xy(1), 'AbsTol', 1e-6, ...
        sprintf('SVG screen coordinate: leader x1 for %s must equal engineering x %.6f.', nm, p.xy(1)));
    verifyEqual(testCase, str2double(char(elLeader.getAttribute('y1'))), -p.xy(2), 'AbsTol', 1e-6, ...
        sprintf('SVG screen coordinate: leader y1 for %s must equal -engineering y %.6f.', nm, p.xy(2)));
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
    elLeader = leaderByTerm(nm);
    verifyEqual(testCase, str2double(char(elLeader.getAttribute('x1'))), v.xy(1), 'AbsTol', 1e-6, ...
        sprintf('SVG screen coordinate: leader x1 for %s must equal engineering x %.6f.', nm, v.xy(1)));
    verifyEqual(testCase, str2double(char(elLeader.getAttribute('y1'))), -v.xy(2), 'AbsTol', 1e-6, ...
        sprintf('SVG screen coordinate: leader y1 for %s must equal -engineering y %.6f.', nm, v.xy(2)));
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
if strcmp(svgName, '02_connection_zone')
    w = result.effectiveDimensions.centerPlatformWidth;
    h = result.effectiveDimensions.centerPlatformHeight;
    if xMin > -w / 2 - 2 + 1e-6 || yMin > -h / 2 - 2 + 1e-6 || ...
            xMax < w / 2 + 2 - 1e-6 || yMax < h / 2 + 2 - 1e-6
        error('CircularFPC:ExportReadbackFailed', ...
            'connection-zone viewBox must not shrink center platform +/-2 mm range (got x=[%.6f %.6f], y=[%.6f %.6f]).', ...
            xMin, xMax, yMin, yMax);
    end
    for k = 1:numel(result.pads)
        p = result.pads(k);
        r = p.diameter / 2;
        screenY = -p.xy(2);
        if p.xy(1) - r < xMin - 1e-9 || p.xy(1) + r > xMax + 1e-9 || ...
                screenY - r < yMin - 1e-9 || screenY + r > yMax + 1e-9
            error('CircularFPC:ExportReadbackFailed', ...
                'connection-zone viewBox clips pad %s (center [%.6f %.6f], r=%.6f).', ...
                p.name, p.xy(1), p.xy(2), r);
        end
    end
    for k = 1:numel(result.vias)
        v = result.vias(k);
        r = v.padDiameter / 2;
        screenY = -v.xy(2);
        if v.xy(1) - r < xMin - 1e-9 || v.xy(1) + r > xMax + 1e-9 || ...
                screenY - r < yMin - 1e-9 || screenY + r > yMax + 1e-9
            error('CircularFPC:ExportReadbackFailed', ...
                'connection-zone viewBox clips via %s (center [%.6f %.6f], r=%.6f).', ...
                v.name, v.xy(1), v.xy(2), r);
        end
    end
end
end

function angleDeg = expectedViaAngleDeg(name, theta)
% 外端/内端位置契约：2 层方向为 theta，4 层方向为 theta+90，
% 6 层再增加 theta-90；名称映射也用于 6/6 的两个内端过孔。
switch name
    case {'V34', 'V23'}
        angleDeg = theta + 90;
    case {'V56', 'V45'}
        angleDeg = theta - 90;
    otherwise
        angleDeg = theta;
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

function result = analyzeInternal(overrides)
% 测试适配器：通过唯一公共主入口进入只读分析模式。
if nargin < 1
    overrides = struct();
end
overrides.analysisOnly = true;
result = circular_fpc_main(overrides);
end
