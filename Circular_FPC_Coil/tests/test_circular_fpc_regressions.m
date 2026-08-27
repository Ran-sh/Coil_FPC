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
verifyEqual(testCase, cfg.turnsPerCoilLayer, 8);
verifyEqual(testCase, cfg.traceWidth, 0.20, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.traceSpacing, 0.15, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.pitchMargin, 0.005, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.edgeClearance, 0.30, 'AbsTol', 1e-9); % = DRC 铜-板框
verifyEqual(testCase, cfg.connectionAngleDeg, 135.0, 'AbsTol', 1e-9);
verifyEqual(testCase, cfg.viaPadDiameter, 0.55, 'AbsTol', 1e-9); % 过孔默认外径（JLC 常规推荐）
verifyEqual(testCase, cfg.viaDrillDiameter, 0.3, 'AbsTol', 1e-9); % 过孔默认内径
verifyEqual(testCase, cfg.viaCoilSpacing, 0.152, 'AbsTol', 1e-9); % 过孔-线圈净距 = DRC 6mil
verifyEqual(testCase, cfg.padDiameter, 0.6096, 'AbsTol', 1e-9); % 焊盘 24 mil
verifyEqual(testCase, cfg.minCopperInteriorAngleDeg, 90.0, 'AbsTol', 1e-9); % 走线最小内角阈值（>= 合法，含直角）
verifyEqual(testCase, cfg.minBoardInteriorAngleDeg, 90.0, 'AbsTol', 1e-9); % 板框最小内角阈值（>= 合法）
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
verifyEqual(testCase, cfg.platformCornerRadius, 0.2, 'AbsTol', 1e-9); % 平台轻微工艺圆角
verifyEqual(testCase, cfg.platformSlotMargin, 0.25, 'AbsTol', 1e-9); % ADVISORY 建议值用槽宽余量
verifyTrue(testCase, cfg.enablePreview);
verifyTrue(testCase, isfield(cfg, 'padPairSpacing'), 'default config missing padPairSpacing');
if isfield(cfg, 'padPairSpacing')
    verifyEqual(testCase, cfg.padPairSpacing, 2.0, 'AbsTol', 1e-9);
end
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', 0)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', NaN)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', Inf)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('padPairSpacing', [1 2])), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('platformCornerRadius', -0.1)), 'CircularFPC:InvalidConfig');
verifyError(testCase, @() circular_fpc_default_config(struct('platformSlotMargin', 0)), 'CircularFPC:InvalidConfig');
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

function testRejectsUnsupportedLayerMatrix(testCase)
verifyError(testCase, @() circular_fpc_default_config(struct('unknownField', 1)), 'CircularFPC:UnknownConfigField');
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 3)), 'CircularFPC:UnsupportedLayerCombination');
verifyError(testCase, @() circular_fpc_default_config(struct('boardLayerCount', 4, 'coilLayerCount', 3)), 'CircularFPC:UnsupportedLayerCombination');
verifyError(testCase, @() circular_fpc_default_config(struct('boardOuterDiameter', 0)), 'CircularFPC:InvalidConfig');
end

function testBoardSizingMode(testCase)
% 板框定尺寸：'auto'（默认）由匝数计算板框外径并在输出中报告；'fixed' 使用 boardOuterDiameter。
verifyError(testCase, @() circular_fpc_default_config(struct('boardSizingMode', 'weird')), ...
    'CircularFPC:InvalidConfig');
outRoot = createTempOutput(testCase);
rAuto = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'auto_board'));
verifyEqual(testCase, rAuto.effectiveDimensions.boardOuterDiameter, 25.294, 'AbsTol', 1e-6);
verifyTrue(testCase, contains(fileread(fullfile(rAuto.outputPath, 'reports', '03_design_summary.txt')), 'boardSizingMode: auto'));
turnTxt = fileread(fullfile(rAuto.outputPath, 'reports', '04_turn_scan.csv'));
verifyTrue(testCase, contains(turnTxt, 'requiredBoardDiameterMm'));
verifyTrue(testCase, contains(turnTxt, sprintf('6,%.6f', 0.2 + 5 * 0.355))); % 6 匝所需径向宽度
% 匝数扫描只列出几何生成器支持的范围：至少两个径向采样层级。
verifyEmpty(testCase, regexp(turnTxt, '(?m)^1,', 'once'));
verifyNotEmpty(testCase, regexp(turnTxt, '(?m)^2,', 'once'));
% fixed 25.0（小于 auto 所需 25.294）：强制 0.30 mm 板边制造规则失败，原子导出不留正式目录。
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRoot, ...
    'designName', 'fixed_board', 'boardSizingMode', 'fixed')), 'CircularFPC:ValidationFailed');
verifyFalse(testCase, isfolder(fullfile(outRoot, 'fixed_board')));
% fixed 25.3（大于 auto 所需 25.294）：成功，板径/制造报告/扫描契约保持。
rFixed = circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'fixed_board_253', ...
    'boardSizingMode', 'fixed', 'boardOuterDiameter', 25.3));
verifyEqual(testCase, rFixed.effectiveDimensions.boardOuterDiameter, 25.3, 'AbsTol', 1e-9);
verifyTrue(testCase, rFixed.manufacturing.passed);
verifyTrue(testCase, contains(fileread(fullfile(rFixed.outputPath, 'reports', '03_design_summary.txt')), 'boardSizingMode: fixed'));
fixedTurnTxt = fileread(fullfile(rFixed.outputPath, 'reports', '04_turn_scan.csv'));
verifyEmpty(testCase, regexp(fixedTurnTxt, '(?m)^1,', 'once'));
verifyNotEmpty(testCase, regexp(fixedTurnTxt, '(?m)^2,', 'once'));
end

function testPlatformRectangleBridgeCorridorAndAdvisory(testCase)
% 平台矩形化 + 软内接判据（>=90° 角度规则配套）：
%   1) 13x14 平台尖角伸入桥区走廊：应能生成，ADVISORY 提示超出量，
%      实测铜-槽净距仍须达标（角部被桥走廊覆盖）；
%   2) 平台远超板外半径：预检硬错误 GeometryInfeasible；
%   3) 超大平台越过走廊（20x11）：预检放行，由实测铜-槽净距在结果验证阶段拒绝。
res = circular_fpc_analyze(struct('centerPlatformWidth', 13.0, 'centerPlatformHeight', 14.0));
verifyTrue(testCase, res.validation.passed);
verifyGreaterThanOrEqual(testCase, res.validation.minCopperToSlotsMm, cfgEdgeClearanceForCheck(testCase) - 1e-9);
verifyFalse(testCase, isempty(res.validation.advisories), '13x14 should emit an inscribed-circle advisory');
verifyTrue(testCase, any(contains(res.validation.advisories, 'inscribed circle')));
verifyEqual(testCase, res.effectiveDimensions.centerPlatformHeight, 14.0, 'AbsTol', 1e-9);
verifyError(testCase, @() circular_fpc_analyze(struct('centerPlatformWidth', 30.0, ...
    'centerPlatformHeight', 30.0)), 'CircularFPC:GeometryInfeasible');
% 超大平台（20x11）：预检放行、实测铜-槽净距仍达标，仅输出 ADVISORY 量化建议。
resBig = circular_fpc_analyze(struct('centerPlatformWidth', 20.0, 'centerPlatformHeight', 11.0));
verifyTrue(testCase, resBig.validation.passed);
verifyTrue(testCase, any(contains(resBig.validation.advisories, 'inscribed circle')));
verifyGreaterThanOrEqual(testCase, resBig.validation.minCopperToSlotsMm, cfgEdgeClearanceForCheck(testCase) - 1e-9);
end

function ec = cfgEdgeClearanceForCheck(~)
ec = 0.30; % 默认 edgeClearance（与嘉立创铜-板框 DRC 对应）
end

function testInnerTransitionDetour(testCase)
% 4/4 分数匝直连方案（用户设计约定）：L2 绕 8.25 匝使内端直接落到 225° 的
% V23、L4 绕 7.75 匝使内端直接落到 135° 的 VOUT——内端无任何过渡走线
% （L3 无连接路径，L2/L4 仅剩外端 ≤0.3mm 的径向微调段），
% 四层平均匝数恰为 turnsPerCoilLayer。
res = circular_fpc_analyze(struct('boardLayerCount', 4, 'coilLayerCount', 4));
verifyTrue(testCase, res.validation.passed, ...
    sprintf('4/4 validation failed: %s', strjoin(res.validation.messages, ' | ')));
verifyEmpty(testCase, res.layerPaths(3).connectionPaths, 'L3 must have no transition traces');
for li = [2, 4]
    for k = 1:numel(res.layerPaths(li).connectionPaths)
        p = res.layerPaths(li).connectionPaths{k};
        pathLen = sum(sqrt(sum(diff(p, 1, 1).^2, 2)));
        verifyLessThanOrEqual(testCase, pathLen, 0.3, ...
            sprintf('L%d connection traces must be micro jogs only (len %.3f)', li, pathLen));
    end
end
% 分数匝：L2 外半径多 0.25 节距、L4 外半径少 0.25 节距（内半径均 = rStart），
% 均含外端过孔延伸区 E
rStart = res.effectiveDimensions.coilInnerDiameter / 2 + res.config.traceWidth / 2;
pitch = res.effectiveDimensions.coilPitch;
ext = res.effectiveDimensions.viaEndExtension;
rMaxL2 = max(sqrt(sum(res.layerPaths(2).coilXY.^2, 2)));
rMaxL4 = max(sqrt(sum(res.layerPaths(4).coilXY.^2, 2)));
verifyEqual(testCase, rMaxL2, rStart + 7.25 * pitch + ext, 'AbsTol', 1e-6);
verifyEqual(testCase, rMaxL4, rStart + 6.75 * pitch + ext, 'AbsTol', 1e-6);
% V23 位置：theta+90 桥轴、半径 = rStart - (viaCoil + 焊环/2 + 线宽/2 - 0.25节距)
v23 = res.vias(strcmp({res.vias.name}, 'V23'));
verifyEqual(testCase, numel(v23), 1);
uAxis = [cosd(res.config.connectionAngleDeg), sind(res.config.connectionAngleDeg)];
verifyTrue(testCase, abs(dot(v23.xy, uAxis)) <= 1e-6, ...
    'V23 must lie on the theta+90 bridge axis');
expectedRV23 = rStart - (res.config.viaCoilSpacing + res.config.viaPadDiameter / 2 + ...
    res.config.traceWidth / 2 - 0.25 * pitch);
verifyEqual(testCase, norm(v23.xy), expectedRV23, 'AbsTol', 1e-6);
% 13x14 平台下 4/4 仍可生成
resBig = circular_fpc_analyze(struct('boardLayerCount', 4, 'coilLayerCount', 4, ...
    'centerPlatformWidth', 13.0, 'centerPlatformHeight', 14.0));
verifyTrue(testCase, resBig.validation.passed, ...
    sprintf('4/4 + 13x14 validation failed: %s', strjoin(resBig.validation.messages, ' | ')));
% 极限档小过孔（分数匝 + 板框按最大外端定径 + 端子附着带间距判定）：应通过
resX = circular_fpc_analyze(struct('boardLayerCount', 4, 'coilLayerCount', 4, ...
    'manufacturingTier', 'extreme', 'viaPadDiameter', 0.35, 'viaDrillDiameter', 0.15));
verifyTrue(testCase, resX.validation.passed, ...
    sprintf('4/4 extreme validation failed: %s', strjoin(resX.validation.messages, ' | ')));
verifyGreaterThanOrEqual(testCase, resX.validation.minCopperSpacingMm, 0.15 - 1e-9);
% 手动模式 4/4 往返：从 auto 结果取端子坐标回填
names = {res.vias.name};
[~, i1] = ismember('V12', names);
[~, i2] = ismember('V23', names);
[~, i3] = ismember('V34', names);
[~, i4] = ismember('VOUT', names);
mxy = [res.vias(i1).xy; res.vias(i2).xy; res.vias(i3).xy; res.vias(i4).xy];
resM = circular_fpc_analyze(struct('boardLayerCount', 4, 'coilLayerCount', 4, ...
    'terminalPlacementMode', 'manual', ...
    'manualPadAXY', res.pads(1).xy, ...
    'manualPadBXY', res.pads(2).xy, ...
    'manualSeriesViaXY', mxy));
verifyTrue(testCase, resM.validation.passed, ...
    sprintf('4/4 manual round-trip failed: %s', strjoin(resM.validation.messages, ' | ')));
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
verifyEqual(testCase, cfgDef.viaDrillDiameter, 0.3, 'AbsTol', 1e-9);
verifyEqual(testCase, cfgDef.viaPadDiameter, 0.55, 'AbsTol', 1e-9);
cfgOK = circular_fpc_default_config(struct('traceSpacing', 0.15, 'turnsPerCoilLayer', 8, 'viaPadDiameter', 0.55));
verifyEqual(testCase, cfgOK.viaCoilSpacing, 0.152, 'AbsTol', 1e-9);
end

function testManufacturingProfileRules(testCase)
% R1 制造档案契约：默认 profile/tier/overrides；非法取值与未知规则覆盖；
% trace 宽度、过孔、铜厚边界；analyze 制造报告字段与 WARN/HIGH_COST_EXTREME 语义。
cfg = circular_fpc_default_config();
verifyEqual(testCase, cfg.manufacturingProfile, 'jlc_fpc_1oz');
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
resOv = circular_fpc_analyze(struct('traceWidth', 0.15, 'manufacturingRuleOverrides', ruleOv));
chkOv = findManufacturingCheck(resOv.manufacturing, 'TRACE_WIDTH');
verifyEqual(testCase, chkOv.limitMm, 0.15, 'AbsTol', 1e-9);
verifyEqual(testCase, chkOv.source, 'override');
% 默认 analyze 制造报告结构
res = circular_fpc_analyze();
mf = res.manufacturing;
verifyEqual(testCase, mf.profile, 'jlc_fpc_1oz');
verifyEqual(testCase, mf.tier, 'standard');
verifyTrue(testCase, isfield(mf, 'rules') && isfield(mf, 'checks') && isfield(mf, 'passed') ...
    && isfield(mf, 'warnings') && isfield(mf, 'failures'));
verifyTrue(testCase, mf.passed);
verifyTrue(testCase, isempty(mf.failures));
ids = {mf.checks.id};
verifyTrue(testCase, all(ismember({'TRACE_WIDTH', 'TRACE_SPACING', 'VIA_DRILL', 'VIA_PAD', ...
    'VIA_PAD_DRILL_DIFFERENCE', 'COPPER_THICKNESS'}, ids)));
% 默认 TRACE_WIDTH 有余量 -> PASS；VIA_DRILL 恰在 standard 极限 -> WARN
chkTw = findManufacturingCheck(mf, 'TRACE_WIDTH');
verifyEqual(testCase, chkTw.limitMm, 0.102, 'AbsTol', 1e-9);
verifyEqual(testCase, chkTw.source, 'profile');
verifyEqual(testCase, chkTw.status, 'PASS');
chkVd = findManufacturingCheck(mf, 'VIA_DRILL');
verifyEqual(testCase, chkVd.status, 'WARN');
% extreme 层 2L 0.10/0.30、4L 0.15/0.35：analyze 成功且对应 via 检查为 WARN + HIGH_COST_EXTREME
    resX2 = circular_fpc_analyze(struct('manufacturingTier', 'extreme', 'boardLayerCount', 2, ...
        'coilLayerCount', 1, 'viaDrillDiameter', 0.1, 'viaPadDiameter', 0.3));
verifyTrue(testCase, resX2.manufacturing.passed);
chkX2d = findManufacturingCheck(resX2.manufacturing, 'VIA_DRILL');
chkX2p = findManufacturingCheck(resX2.manufacturing, 'VIA_PAD');
verifyEqual(testCase, chkX2d.status, 'WARN');
verifyEqual(testCase, chkX2p.status, 'WARN');
verifyTrue(testCase, contains(chkX2d.message, 'HIGH_COST_EXTREME') || contains(chkX2d.code, 'HIGH_COST_EXTREME'));
verifyTrue(testCase, contains(chkX2p.message, 'HIGH_COST_EXTREME') || contains(chkX2p.code, 'HIGH_COST_EXTREME'));
resX4 = circular_fpc_analyze(struct('manufacturingTier', 'extreme', 'boardLayerCount', 4, ...
    'viaDrillDiameter', 0.15, 'viaPadDiameter', 0.35));
verifyTrue(testCase, resX4.manufacturing.passed);
chkX4d = findManufacturingCheck(resX4.manufacturing, 'VIA_DRILL');
chkX4p = findManufacturingCheck(resX4.manufacturing, 'VIA_PAD');
verifyEqual(testCase, chkX4d.status, 'WARN');
verifyEqual(testCase, chkX4p.status, 'WARN');
verifyTrue(testCase, contains(chkX4d.message, 'HIGH_COST_EXTREME') || contains(chkX4d.code, 'HIGH_COST_EXTREME'));
verifyTrue(testCase, contains(chkX4p.message, 'HIGH_COST_EXTREME') || contains(chkX4p.code, 'HIGH_COST_EXTREME'));
% 铜厚匹配：0.035 +/- 0.001 边界合法，超出容差 0.001 mm 失败
verifyEqual(testCase, circular_fpc_default_config(struct('copperThickness', 0.034)).copperThickness, 0.034, 'AbsTol', 1e-9);
verifyEqual(testCase, circular_fpc_default_config(struct('copperThickness', 0.036)).copperThickness, 0.036, 'AbsTol', 1e-9);
verifyError(testCase, @() circular_fpc_default_config(struct('copperThickness', 0.036001)), 'CircularFPC:InvalidConfig');
end

function testAnalyzeIsReadOnlyAndLayerMatrix(testCase)
% R2 契约：analyze 只计算不写文件；支持层矩阵与角度旋转；无效配置传播。
combos = [2 1; 2 2; 4 1; 4 2; 4 4];
for k = 1:size(combos, 1)
    root = nonexistentTempRoot();
    res = circular_fpc_analyze(struct('outputRoot', root, 'designName', 'red_readonly', ...
        'boardLayerCount', combos(k, 1), 'coilLayerCount', combos(k, 2)));
    verifyEqual(testCase, res.outputPath, '');
    verifyEqual(testCase, res.boardLayerCount, combos(k, 1));
    verifyEqual(testCase, res.coilLayerCount, combos(k, 2));
    verifyTrue(testCase, isfield(res, 'validation') && res.validation.passed);
    verifyTrue(testCase, isfield(res, 'manufacturing') && res.manufacturing.passed);
    verifyTrue(testCase, exist(root, 'dir') ~= 7, 'analyze must not create the output root');
end
% 角度旋转保持（显式 2/1 + 13x11 安全平台：4/4 的绕行过渡在非默认连接角下
% 可能实测铜-槽净距不足而报错，属预期保护；旋转覆盖用无绕行的 2/1 组合）
for ang = [0 45 135 225]
    resA = circular_fpc_analyze(struct('connectionAngleDeg', ang, 'boardLayerCount', 2, ...
        'coilLayerCount', 1, 'centerPlatformHeight', 11.0, 'outputRoot', nonexistentTempRoot()));
    verifyEqual(testCase, resA.effectiveDimensions.centerPlatformWidth, 13.0, 'AbsTol', 1e-9);
    verifyEqual(testCase, resA.effectiveDimensions.centerPlatformHeight, 11.0, 'AbsTol', 1e-9);
end
res135 = circular_fpc_analyze(struct('connectionAngleDeg', 135, 'outputRoot', nonexistentTempRoot()));
padA = findTerminalByName(res135.pads, 'PAD_A');
verifyTrue(testCase, padA.xy(1) < 0 && padA.xy(2) > 0);
% 无效配置沿 analyze 传播
verifyError(testCase, @() circular_fpc_analyze(struct('traceWidth', 0.101)), 'CircularFPC:InvalidConfig');
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
verifyEqual(testCase, result.effectiveDimensions.boardOuterDiameter, 25.294, 'AbsTol', 1e-6); % auto：2*(9.415+0.1+0.355*7+0.172+0.275+0.3)
verifyEqual(testCase, result.effectiveDimensions.coilInnerDiameter, 18.63, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformWidth, 13.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformHeight, 14.0, 'AbsTol', 1e-9);
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
verifyGreaterThanOrEqual(testCase, result.validation.minCopperToBoardMm, cfg.edgeClearance);
verifyGreaterThanOrEqual(testCase, result.validation.minCopperToSlotsMm, cfg.edgeClearance);
verifyTrue(testCase, result.validation.minCopperInteriorAngleDeg >= 89.9, ...
    sprintf('copper path min interior angle must be >= 90 - tolerance (got %.3f)', result.validation.minCopperInteriorAngleDeg));
verifyTrue(testCase, result.validation.minBoardInteriorAngleDeg >= 89.9, ...
    sprintf('board min interior angle must be >= 90 - tolerance (got %.3f)', result.validation.minBoardInteriorAngleDeg));
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
verifyEqual(testCase, result.effectiveDimensions.boardOuterDiameter, 43.924, 'AbsTol', 1e-6); % auto+scale2：2*(18.63+0.1+0.355*7+0.172+0.275+0.3)
verifyEqual(testCase, result.effectiveDimensions.coilInnerDiameter, 37.26, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformWidth, 26.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.centerPlatformHeight, 28.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.bridgeTargetWidth, 3.0, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.coilPitch, 0.355, 'AbsTol', 1e-9);
verifyEqual(testCase, result.effectiveDimensions.turnsPerCoilLayer, 8);
fullSvg = fullfile(result.outputPath, 'previews', '01_preview_full.svg');
verifyTrue(testCase, isfile(fullSvg));
if isfile(fullSvg)
    svgTxt = fileread(fullSvg);
    verifyTrue(testCase, contains(svgTxt, 'viewBox="-22.462000 -22.462000 44.924000 44.924000"')); % auto+scale2 板径 43.924/2+0.5
end
end

function testInvalidGeometryRejected(testCase)
outRoot = createTempOutput(testCase);
% 平台远超板外半径：可行性预检快速失败，不留正式输出目录。
% （超大但有限的平台如 20x11 现已合法并带 ADVISORY，见
%   testPlatformRectangleBridgeCorridorAndAdvisory。）
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'invalid_platform', ...
    'centerPlatformWidth', 30.0, 'centerPlatformHeight', 30.0)), 'CircularFPC:GeometryInfeasible');
verifyError(testCase, @() circular_fpc_main(struct('outputRoot', outRoot, 'designName', 'invalid_scale', 'geometryScale', 0.05)), 'CircularFPC:GeometryInfeasible');
verifyFalse(testCase, isfolder(fullfile(outRoot, 'invalid_platform')));
verifyFalse(testCase, isfolder(fullfile(outRoot, 'invalid_scale')));
% 当前 (turns-1) 螺旋模型在 1 匝时只有单个采样点，应在配置阶段拒绝。
verifyError(testCase, @() circular_fpc_default_config(struct('turnsPerCoilLayer', 1)), ...
    'CircularFPC:InvalidConfig');
cfgMinTurns = circular_fpc_default_config(struct('turnsPerCoilLayer', 2));
verifyEqual(testCase, cfgMinTurns.turnsPerCoilLayer, 2);
% >=90° 角度规则下，60° 连接角不再产生尖角失败：应正常生成并通过全部实测验证。
r60 = circular_fpc_main(struct('outputRoot', outRoot, ...
    'designName', 'sharp_angle_60', 'connectionAngleDeg', 60, 'centerPlatformHeight', 11.0));
verifyTrue(testCase, r60.validation.passed);
verifyTrue(testCase, isfolder(fullfile(outRoot, 'sharp_angle_60')));
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
            verifyEqual(testCase, numel(pc), (li == 1) * 2 + numel(viaIds), ...
                sprintf('physical %s total circle count', physFile));
        end
        keepFile = fullfile(layerDir, sprintf('%02d_antipad_keepout_L%d.dxf', li, li));
        verifyTrue(testCase, isfile(keepFile), sprintf('missing keepout %s', keepFile));
        if isfile(keepFile)
            keepTxt = fileread(keepFile);
            verifyDxfBase(testCase, keepTxt, keepFile);
            verifyFalse(testCase, contains(keepTxt, 'COPPER_PHYSICAL'), ...
                sprintf('keepout %s must not contain copper traces', keepFile));
            keepLayer = sprintf('ANTIPAD_KEEPOUT_L%d', li);
            verifyTrue(testCase, contains(keepTxt, keepLayer), ...
                sprintf('keepout %s must declare %s layer even with 0 circles', keepFile, keepLayer));
            kc = dxfCircles(keepTxt);
            keepIds = find(~([result.vias.fromLayer] == li | [result.vias.toLayer] == li));
            verifyEqual(testCase, numel(kc), numel(keepIds), ...
                sprintf('keepout %s circle count', keepFile));
            verifyTrue(testCase, all(strcmp({kc.layer}, keepLayer)), ...
                'keepout circles must use ANTIPAD_KEEPOUT_Ln layer');
            if ~isempty(kc)
                verifyTrue(testCase, all(abs([kc.r] - result.config.antipadDiameter / 2) <= 1e-9), ...
                    'keepout circle radii must equal antipadDiameter/2');
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
    'padPairSpacing', 20)), 'CircularFPC:TerminalPlacementInvalid');
verifyFalse(testCase, isfolder(fullfile(outRootBad, 'pad_pair_infeasible')));
end

function testTerminalRotationAndScaleContract(testCase)
outRoot = createTempOutput(testCase);
angles = [0 45 135 225];
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

function testManualCoordinatesRoundTrip(testCase)
outRoot = createTempOutput(testCase);
cfg0 = circular_fpc_default_config();
pitch = cfg0.traceWidth + cfg0.traceSpacing + cfg0.pitchMargin;
outerCenterRadius = cfg0.coilInnerDiameter / 2 + cfg0.traceWidth / 2 + (cfg0.turnsPerCoilLayer - 1) * pitch;
% 外端过孔延伸区：线圈端点沿径向向外延伸 viaEndExtension（与引擎公式一致）
ext = max(0, cfg0.viaCoilSpacing + cfg0.viaPadDiameter / 2 + cfg0.traceWidth / 2 - pitch);
outerXY = (outerCenterRadius + ext) * [cosd(cfg0.connectionAngleDeg), sind(cfg0.connectionAngleDeg)];
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
verifyEqual(testCase, closedCount, 5);
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
    for kw = {'boardLayerCount', 'coilLayerCount', 'activeCoilLayers', 'copperThickness', '1 oz', ...
            'jlc_fpc_1oz', 'standard', 'TO_BE_SELECTED', '+X', '+Y', 'NOT_GENERATED', ...
            'coverlay', 'stiffener', 'Gerber', 'panelization'}
        verifyTrue(testCase, contains(notes, kw{1}), ...
            sprintf('07 notes missing keyword %s', kw{1}));
    end
    verifyTrue(testCase, contains(lower(notes), 'not replace gerber') || ...
        contains(lower(notes), 'cam reference'), ...
        '07 notes must state physical DXF is a CAM reference and does not replace Gerber');
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
    roles8 = {'board_outline', 'drill_map', 'copper_centerline', 'copper_physical', ...
        'antipad_keepout', 'preview', 'report', 'generation_status'};
    verifyTrue(testCase, all(ismember(string(t8.role), roles8)), ...
        '08 manifest roles must come from the fixed vocabulary');
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
verifyFalse(testCase, isfile(fullfile(out2, 'previews', '01_preview_full.svg')));
verifyFalse(testCase, isfile(fullfile(out2, 'previews', '02_preview_connection_zone.svg')));
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
    verifyFalse(testCase, any(startsWith(string(t8np.relativePath), 'previews/')), ...
        'no-preview manifest must not list previews/');
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

function testFigurePlotContract(testCase)
% circular_fpc_plot 已移入 private/（内部函数，仅由 circular_fpc_main 调用，
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
            verifyAngleMod360(testCase, v.bridgeAngleDeg, theta + 90, 'V34 bridgeAngleDeg');
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
        verifyAngleMod360(testCase, v.bridgeAngleDeg, theta + 90, sprintf('%s bridgeAngleDeg', v.name));
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
if strcmp(svgName, '02_preview_connection_zone')
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

function verifyExportedAngle(testCase, actual, expected, label)
% Readback angle value must match result: NaN maps to NaN, finite within 1e-6.
if isnan(expected)
    verifyTrue(testCase, isnan(actual), sprintf('%s must read back as NaN', label));
else
    verifyEqual(testCase, actual, expected, 'AbsTol', 1e-6, label);
end
end
