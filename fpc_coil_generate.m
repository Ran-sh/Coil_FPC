function result = fpc_coil_generate(cfg)
% FPC_COIL_GENERATE
% 两层/四层FPC线圈共享生成核心。
%
% 输入：
%   cfg - 由 fpc_coil_main 传入的参数结构体。
%
% 输出：
%   result - 包含验证结论和输出目录的结构体。
%
% 流程：
%   生成几何 -> 全部检查 -> 检查通过 -> 输出DXF/CSV/TXT/PNG。

try

%% =========================================================
% 1. cfg字段完整性和参数合法性检查
%% =========================================================

validateConfiguration(cfg);

%% =========================================================
% 2. 派生参数计算
%% =========================================================

d = calculateDerivedParameters(cfg);
tol = cfg.geometryTolerance;

tempOutputFolder = fullfile(cfg.outputRoot, [cfg.designName '_temp']);
prepareTempOutputDirectory(cfg, tempOutputFolder);

if cfg.tabWidth/2 < d.requiredHalfWidth
    error('尾部宽度不足，无法容纳焊盘和边缘裕量。');
end

if cfg.padTipInset < cfg.padDiameter/2 + cfg.padTipMargin
    error('焊盘距离尾部最右端过近。');
end

horizontalLeadLength = ...
    d.padA(1) - (d.outerRightCenterX + cfg.leadBendRadius);
if horizontalLeadLength < cfg.leadTabClearance
    error('尾部水平引线长度不足。');
end

if d.padA(1) - cfg.padDiameter/2 < d.bodyRightX
    error('焊盘超出尾部左边界。');
end

%% =========================================================
% 3. 最大匝数计算
%% =========================================================

widthBasedMaxTurns = calculateMaximumTurns(cfg, d);

if cfg.turnsPerLayer > widthBasedMaxTurns
    error(['当前主体宽度%.2f mm无法容纳每层%d匝。\n' ...
        '当前线宽/线距为%.2f/%.2f mm。\n' ...
        '中心至少保留%.2f mm时，建议最大为%d匝/层。\n' ...
        '右侧尾部不参与匝数计算。'], ...
        cfg.plateWidth, cfg.turnsPerLayer, ...
        cfg.traceWidth, cfg.traceSpacing, ...
        cfg.minInnerWidth, widthBasedMaxTurns);
end

effectiveTurnsPerLayer = cfg.turnsPerLayer + d.phaseStep;
innerCenterInset = d.outerCenterInset + effectiveTurnsPerLayer*d.pitch;
innerLength = cfg.plateLength - 2*innerCenterInset;
innerWidth  = cfg.plateWidth  - 2*innerCenterInset;

if innerLength <= cfg.traceWidth || innerWidth <= cfg.traceWidth
    error('内圈尺寸无效，请减少匝数或增大主体宽度。');
end

%% =========================================================
% 4. 各层螺旋生成
%% =========================================================

[layerXY, viaXY, connectionErrors, escapeArcFallback] = ...
    buildLayerGeometry(cfg, d);

%% =========================================================
% 6. 平滑板框生成
%% =========================================================

boardXY = generateSmoothBoardOutline(cfg);

%% =========================================================
% 7. 去除重复点和零长度线段
%% =========================================================

for k = 1:cfg.layerCount
    [layerXY{k}, ~] = removeDuplicatePoints(layerXY{k}, tol);
    [layerXY{k}, ~] = removeZeroLengthSegments(layerXY{k}, tol);
end

boardXY = removeDuplicatePoints(boardXY, tol);
boardXY = removeZeroLengthSegments(boardXY, tol);

if size(boardXY,1) > 1 && norm(boardXY(end,:)-boardXY(1,:)) < tol
    boardXY(end,:) = [];
end

fullyValidatedMaxTurns = calculateFullyValidatedMaximumTurns( ...
    cfg, d, boardXY, widthBasedMaxTurns);

%% =========================================================
% 8. 闭合角、铜线角度、自交、线距、连接和尺寸检查
%% =========================================================

failures = {};
nanInfPass = true;
zeroLengthPass = true;

if any(~isfinite(boardXY), 'all') || ...
        any(cellfun(@(c) any(~isfinite(c), 'all'), layerXY))
    nanInfPass = false;
    failures{end+1} = '存在NaN或Inf坐标';
end

if anyZeroLengthSegments(boardXY, tol) || ...
        any(cellfun(@(c) anyZeroLengthSegments(c, tol), layerXY))
    zeroLengthPass = false;
    failures{end+1} = '存在零长度线段';
end

% 板框闭合角
boardMinAngle = NaN;
if cfg.enableBoardAngleCheck
    boardMinAngle = minimumClosedPolylineInteriorAngle(boardXY, tol);
    if boardMinAngle <= cfg.minBoardInteriorAngleDeg + cfg.angleToleranceDeg
        failures{end+1} = sprintf( ...
            '板框最小内角%.3f度，必须严格大于%.3f度', ...
            boardMinAngle, cfg.minBoardInteriorAngleDeg + cfg.angleToleranceDeg);
    end
end

% 每层铜线内角
copperMinAngles = NaN(cfg.layerCount, 1);
if cfg.enableCopperAngleCheck
    for k = 1:cfg.layerCount
        copperMinAngles(k) = minimumOpenPolylineInteriorAngle(layerXY{k}, tol);
        if copperMinAngles(k) < cfg.minCopperInteriorAngleDeg - cfg.angleToleranceDeg
            failures{end+1} = sprintf( ...
                'L%d最小铜线内角%.3f度，低于%.3f度', ...
                k, copperMinAngles(k), cfg.minCopperInteriorAngleDeg);
        end
    end
end

% 精确自相交检查
boardSelfIntersectionPass = true;
copperSelfIntersectionPass = true;
if cfg.enableExactSelfIntersectionCheck
    if checkPolylineSelfIntersectionExact(boardXY, true, cfg)
        boardSelfIntersectionPass = false;
        failures{end+1} = '板框存在自相交';
    end

    for k = 1:cfg.layerCount
        if checkPolylineSelfIntersectionExact(layerXY{k}, false, cfg)
            copperSelfIntersectionPass = false;
            failures{end+1} = sprintf('L%d线圈存在自相交', k);
        end
    end
end

% 实际最小线距
minCopperSpacing = NaN;
copperClearancePass = true;
if cfg.enableCopperClearanceCheck
    targetCenterline = cfg.traceWidth + cfg.traceSpacing;
    minIndexSeparation = max(16, ceil(cfg.pointsPerTurn/4));
    minCenterline = Inf;

    for k = 1:cfg.layerCount
        [layerMinDist, ok] = calculateMinimumNonAdjacentDistance( ...
            layerXY{k}, targetCenterline, ...
            cfg.clearanceTolerance, minIndexSeparation, tol);

        if ~ok
            copperClearancePass = false;
            failures{end+1} = sprintf( ...
                'L%d实际最小线距%.6f mm，低于允许值%.6f mm', ...
                k, layerMinDist - cfg.traceWidth, ...
                cfg.traceSpacing - cfg.clearanceTolerance);
        end

        minCenterline = min(minCenterline, layerMinDist);
    end

    minCopperSpacing = minCenterline - cfg.traceWidth;
end

% 层间连接检查（连接误差已在生成逃逸引线时检查）
connectionPass = all(connectionErrors <= cfg.connectionTolerance);

viaCoincidencePass = true;
if cfg.layerCount > 2
    for i = 1:size(viaXY,1)-1
        for j = i+1:size(viaXY,1)
            if norm(viaXY(i,:)-viaXY(j,:)) < cfg.geometryTolerance
                viaCoincidencePass = false;
                failures{end+1} = sprintf('过孔V%d%d与V%d%d坐标重合', ...
                    i, i+1, j, j+1);
            end
        end
    end
end

% 板框闭合、主体尺寸、尾部尺寸和总尺寸
boardClosurePass = validateBoardClosure(boardXY, tol);
if ~boardClosurePass
    failures{end+1} = '板框闭合检查失败';
end

bodyDimensionPass = validateBodyDimensions(boardXY, cfg, tol);
if ~bodyDimensionPass
    failures{end+1} = '主体尺寸检查失败';
end

tabDimensionPass = validateTabDimensions(boardXY, cfg, tol);
if ~tabDimensionPass
    failures{end+1} = '尾部尺寸检查失败';
end

overallDimensionPass = validateBoardDimensions(boardXY, cfg, tol);
if ~overallDimensionPass
    failures{end+1} = '总尺寸检查失败';
end

% 焊盘检查
padBoardPass = true;
padPadPass = true;
padCopperPass = true;
padConnectionLength = ...
    (d.padA(1) - (d.outerRightCenterX + cfg.leadBendRadius)) + ...
    (pi/2)*cfg.leadBendRadius;

if cfg.enablePadClearanceCheck
    padBoardPass = validatePadToBoard( ...
        d.padA, d.padB, boardXY, cfg, tol);
    if ~padBoardPass
        failures{end+1} = '焊盘完整圆形区域未完全位于板框内';
    end

    padPadPass = validatePadToPad(d.padA, d.padB, cfg, tol);
    if ~padPadPass
        failures{end+1} = 'PAD_A与PAD_B间距不足';
    end

    padCopperPass = validatePadToCopper( ...
        d.padA, d.padB, layerXY, cfg, tol, padConnectionLength);
    if ~padCopperPass
        failures{end+1} = '焊盘到非连接铜线间距不足';
    end
end

% 过孔检查
viaToViaPass = true;
viaToBoardPass = true;
viaToPadPass = true;
viaConnectedPass = true;
viaNonConnectedPass = true;
viaEscapeLengths = zeros(cfg.layerCount-1, 1);
viaEscapeLengths(1:2:end) = cfg.viaLandingLeadLength;
viaEscapeLengths(2:2:end) = cfg.viaOuterLandingLeadLength;
viaConnectedClearances = zeros(cfg.layerCount-1, 1);
viaConnectedClearances(1:2:end) = cfg.viaLandingClearance;
viaConnectedClearances(2:2:end) = cfg.viaOuterLandingClearance;

if cfg.enableViaClearanceCheck
    viaToViaPass = validateViaToVia(viaXY, cfg, tol);
    if ~viaToViaPass
        failures{end+1} = '过孔焊盘之间间距不足';
    end

    viaToBoardPass = validateViaToBoard(viaXY, boardXY, cfg, tol);
    if ~viaToBoardPass
        failures{end+1} = '过孔焊盘或钻孔距板框过近';
    end

    viaToPadPass = validateViaToPad( ...
        viaXY, d.padA, d.padB, cfg, tol);
    if ~viaToPadPass
        failures{end+1} = '过孔焊盘与PAD_A或PAD_B间距不足';
    end

    [viaConnectedPass, viaNonConnectedPass] = validateViaToCopper( ...
        viaXY, layerXY, cfg, tol, viaEscapeLengths, ...
        viaConnectedClearances);

    if ~viaConnectedPass
        failures{end+1} = '过孔焊盘与连接层相邻匝冲突';
    end

    if ~viaNonConnectedPass && strcmp(cfg.viaClearanceSeverity, 'error')
        failures{end+1} = '过孔焊盘与不应连接的铜层间距不足';
    end
end

%% =========================================================
% 9. 生成验证结果
%% =========================================================

passed = isempty(failures);
outputFolder = fullfile(cfg.outputRoot, cfg.designName);

reportLines = buildValidationReportLines( ...
    cfg, passed, failures, widthBasedMaxTurns, fullyValidatedMaxTurns, ...
    boardMinAngle, copperMinAngles, ...
    minCopperSpacing, connectionErrors, viaCoincidencePass, ...
    nanInfPass, zeroLengthPass, boardClosurePass, ...
    bodyDimensionPass, tabDimensionPass, overallDimensionPass, ...
    boardSelfIntersectionPass, copperSelfIntersectionPass, ...
    padBoardPass, padPadPass, padCopperPass, ...
    viaToViaPass, viaToBoardPass, viaToPadPass, ...
    viaConnectedPass, viaNonConnectedPass, ...
    copperClearancePass, connectionPass);

if ~passed
    reportLines{end+1} = '输出阶段                 : 未执行';
    writeTextFile( ...
        fullfile(tempOutputFolder, 'reports', '03_validation_report.txt'), ...
        reportLines);
    cleanTempOnFailure(tempOutputFolder);
    error('FPC线圈验证失败：%s', strjoin(failures, '；'));
end

%% =========================================================
% 10. 输出DXF
%% =========================================================

dxfFolder = fullfile(tempOutputFolder, 'dxf');
copperFileNames = cell(cfg.layerCount, 1);
copperLayerNames = cell(cfg.layerCount, 1);
dxfValidationPass = true;
dxfFailReason = '';

if cfg.layerCount == 2
    copperFileNames{1} = '01_copper_l1_top.dxf';
    copperFileNames{2} = '02_copper_l2_bottom.dxf';
    copperLayerNames{1} = 'COPPER_L1_TOP';
    copperLayerNames{2} = 'COPPER_L2_BOTTOM';
else
    copperFileNames{1} = '01_copper_l1_top.dxf';
    copperFileNames{2} = '02_copper_l2_inner1.dxf';
    copperFileNames{3} = '03_copper_l3_inner2.dxf';
    copperFileNames{4} = '04_copper_l4_bottom.dxf';
    copperLayerNames{1} = 'COPPER_L1_TOP';
    copperLayerNames{2} = 'COPPER_L2_INNER1';
    copperLayerNames{3} = 'COPPER_L3_INNER2';
    copperLayerNames{4} = 'COPPER_L4_BOTTOM';
end

for k = 1:cfg.layerCount
    layerDxfFolder = fullfile(dxfFolder, sprintf('L%d', k));
    if ~exist(layerDxfFolder, 'dir')
        mkdir(layerDxfFolder);
    end
    dxfFile = fullfile(layerDxfFolder, copperFileNames{k});
    writeDxfFile( ...
        dxfFile, ...
        layerXY{k}, copperLayerNames{k}, false, ...
        cfg.maxVerticesPerDxfEntity);

    expectedDxfVertices = size(layerXY{k},1) + max(0, ...
        ceil((size(layerXY{k},1)-1)/(cfg.maxVerticesPerDxfEntity-1)) - 1);
    expectedDxfEntities = max(1, ...
        ceil((size(layerXY{k},1)-1)/(cfg.maxVerticesPerDxfEntity-1)));
    if cfg.enableDxfReadbackCheck
        [dxfOk, dxfReason] = validateWrittenDxfFile( ...
            dxfFile, expectedDxfVertices, expectedDxfEntities, ...
            copperLayerNames{k}, false);
    else
        dxfOk = true;
        dxfReason = 'SKIP';
    end
    if ~dxfOk
        dxfValidationPass = false;
        dxfFailReason = sprintf('%s：%s', copperFileNames{k}, dxfReason);
    end
end

boardFileName = sprintf('%02d_board_outline.dxf', cfg.layerCount + 1);
boardDxfFile = fullfile(dxfFolder, boardFileName);
writeDxfFile( ...
    boardDxfFile, ...
    boardXY, 'BOARD_OUTLINE', true, cfg.maxVerticesPerDxfEntity);

if cfg.enableDxfReadbackCheck
    [dxfOk, dxfReason] = validateWrittenDxfFile( ...
        boardDxfFile, size(boardXY,1), 1, 'BOARD_OUTLINE', true);
else
    dxfOk = true;
    dxfReason = 'SKIP';
end
if ~dxfOk
    dxfValidationPass = false;
    if isempty(dxfFailReason)
        dxfFailReason = sprintf('%s：%s', boardFileName, dxfReason);
    end
end

if ~dxfValidationPass
    reportLines{end+1} = sprintf( ...
        'DXF基础完整性检查     : FAIL - %s', dxfFailReason);
    writeTextFile( ...
        fullfile(tempOutputFolder, 'reports', '03_validation_report.txt'), ...
        reportLines);
    cleanTempOnFailure(tempOutputFolder);
    error('DXF写出后回读验证失败：%s', dxfFailReason);
end

%% =========================================================
% 11. 输出CSV
%% =========================================================

csvFile = fullfile(tempOutputFolder, 'reports', '01_pad_via_coordinates.csv');
writeCoordinateCsv(csvFile, cfg, d, viaXY);

%% =========================================================
% 12. 输出设计摘要
%% =========================================================

summaryFile = fullfile(tempOutputFolder, 'reports', '02_design_summary.txt');
writeDesignSummary(summaryFile, cfg, d, ...
    widthBasedMaxTurns, fullyValidatedMaxTurns, ...
    effectiveTurnsPerLayer, innerLength, innerWidth, ...
    layerXY, copperFileNames, boardFileName, ...
    boardMinAngle, copperMinAngles, minCopperSpacing, ...
    viaXY, connectionErrors);

%% =========================================================
% 13. 输出完整预览图
%% =========================================================

previewWritePass = true;

if cfg.enablePreview
    previewFolder = fullfile(tempOutputFolder, 'previews');
    fig = plotFullPreview(cfg, boardXY, layerXY, d.padA, d.padB, viaXY);
    print(fig, fullfile(previewFolder, '01_preview_full.png'), '-dpng', ...
        sprintf('-r%d', cfg.previewDpi));

    %% =========================================================
    % 14. 输出右侧局部预览图
    %% =========================================================

    figDetail = plotRightTabPreview( ...
        cfg, boardXY, layerXY, d.padA, d.padB, viaXY);
    print(figDetail, fullfile(previewFolder, '02_preview_right_tab.png'), ...
        '-dpng', sprintf('-r%d', cfg.previewDpi));
else
    previewWritePass = false;
end

reportLines{end+1} = 'DXF写入                 : PASS';
if cfg.enableDxfReadbackCheck
    dxfReadbackText = ternaryText(dxfValidationPass, 'PASS', 'FAIL');
else
    dxfReadbackText = 'SKIP';
end
reportLines{end+1} = sprintf( ...
    'DXF基础完整性检查     : %s', dxfReadbackText);
reportLines{end+1} = 'CSV写入                 : PASS';
reportLines{end+1} = '摘要写入                : PASS';
if escapeArcFallback
    escapeArcText = 'FALLBACK_TO_SHARP_CORNER';
else
    escapeArcText = 'PASS';
end
reportLines{end+1} = sprintf('逃逸引线圆角             : %s', escapeArcText);
if cfg.enablePreview
    previewWriteText = ternaryText(previewWritePass, 'PASS', 'FAIL');
else
    previewWriteText = 'SKIP';
end
reportLines{end+1} = sprintf('预览图写入              : %s', previewWriteText);
reportLines{end+1} = '最终输出完整性          : PASS';

writeTextFile( ...
    fullfile(tempOutputFolder, 'reports', '03_validation_report.txt'), ...
    reportLines);

writeGenerationStatus(tempOutputFolder, cfg, ...
    widthBasedMaxTurns, fullyValidatedMaxTurns, ...
    minCopperSpacing, boardMinAngle, min(copperMinAngles));
promoteTempOutput(tempOutputFolder, outputFolder);

%% =========================================================
% 15. 命令窗口摘要
%% =========================================================

fprintf('\n');
fprintf('========== FPC coil generation completed ==========\n');
fprintf('Design                 : %s\n', cfg.designName);
fprintf('Layers                 : %d\n', cfg.layerCount);
fprintf('Body size              : %.2f x %.2f mm\n', ...
    cfg.plateLength, cfg.plateWidth);
fprintf('Right tab              : %.2f x %.2f mm\n', ...
    cfg.tabLength, cfg.tabWidth);
fprintf('Overall size           : %.2f x %.2f mm\n', ...
    cfg.plateLength + cfg.tabLength, cfg.plateWidth);
fprintf('Trace width / spacing  : %.2f / %.2f mm\n', ...
    cfg.traceWidth, cfg.traceSpacing);
fprintf('Turns per layer        : %d\n', cfg.turnsPerLayer);
fprintf('Width-based maximum turns     : %d\n', widthBasedMaxTurns);
fprintf('Fully validated maximum turns : %d\n', fullyValidatedMaxTurns);
fprintf('Minimum board angle    : %.3f deg\n', boardMinAngle);
fprintf('Minimum copper angle   : %.3f deg\n', min(copperMinAngles));
fprintf('Minimum copper spacing : %.3f mm\n', minCopperSpacing);
fprintf('Self-intersection      : %s\n', ...
    ternaryText(boardSelfIntersectionPass && copperSelfIntersectionPass, ...
        'PASS', 'FAIL'));
fprintf('Connection check       : %s\n', ...
    ternaryText(connectionPass, 'PASS', 'FAIL'));
if cfg.enableDxfReadbackCheck
    dxfConsoleText = ternaryText(dxfValidationPass, 'PASS', 'FAIL');
else
    dxfConsoleText = 'SKIP';
end
fprintf('DXF基础完整性检查   : %s\n', dxfConsoleText);
fprintf('Output folder          : %s\n', outputFolder);
fprintf('=====================================================\n');

catch ME
    try
        tempFolder = fullfile(cfg.outputRoot, [cfg.designName '_temp']);
        if ~exist(tempFolder, 'dir')
            ensureOutputDirectories(tempFolder);
        end

        reportPath = fullfile(tempFolder, 'reports', '03_validation_report.txt');

        if ~exist(reportPath, 'file')
            writeTextFile(reportPath, { ...
                'FPC coil validation report', ...
                '========================', ...
                sprintf('Design                   : %s', cfg.designName), ...
                '最终结论                 : FAIL', ...
                sprintf('失败原因                 : %s', ME.message)});
        end

        cleanTempOnFailure(tempFolder);
    catch
    end

    rethrow(ME);
end

result = struct( ...
    'passed', true, ...
    'outputFolder', outputFolder, ...
    'widthBasedMaximumTurns', widthBasedMaxTurns, ...
    'fullyValidatedMaximumTurns', fullyValidatedMaxTurns, ...
    'minBoardAngle', boardMinAngle, ...
    'minCopperAngle', min(copperMinAngles), ...
    'minCopperSpacing', minCopperSpacing);

end

%% =========================================================
% 局部函数
%% =========================================================

function validateConfiguration(cfg)

requiredFields = { ...
    'layerCount', 'turnsPerLayer', 'useRecommendedTurns', ...
    'plateLength', 'plateWidth', 'plateCornerRadius', ...
    'tabLength', 'tabWidth', 'tabOuterCornerRadius', ...
    'tabTransitionRadius', 'tabEdgeMargin', ...
    'traceWidth', 'traceSpacing', 'edgeClearance', ...
    'minInnerWidth', 'minSpiralCornerRadius', ...
    'leadYOffset', 'leadBendRadius', 'leadArcPointCount', ...
    'padTipInset', 'padDiameter', 'padTipMargin', 'leadTabClearance', ...
    'padToPadClearance', 'padToCopperClearance', ...
    'viaDrillDiameter', 'viaPadDiameter', ...
    'viaToCopperClearance', 'viaToBoardClearance', ...
    'viaToViaClearance', 'viaToPadClearance', 'viaClearanceSeverity', ...
    'viaLandingLeadLength', 'viaLandingClearance', ...
    'viaInnerBendRadius', ...
    'viaOuterLandingLeadLength', 'viaOuterLandingClearance', ...
    'viaOuterBendRadius', ...
    'copperThickness', 'copperResistivity', ...
    'minCopperInteriorAngleDeg', 'minBoardInteriorAngleDeg', ...
    'angleToleranceDeg', 'crossProductTolerance', ...
    'parameterTolerance', 'geometryTolerance', ...
    'connectionTolerance', 'clearanceTolerance', ...
    'pitchMargin', ...
    'pointsPerTurn', 'minTurnPointCount', 'boardArcPointCount', ...
    'maxVerticesPerDxfEntity', 'previewDpi', 'enablePreview', ...
    'enableExactSelfIntersectionCheck', ...
    'enableCopperClearanceCheck', ...
    'enableBoardAngleCheck', ...
    'enableCopperAngleCheck', ...
    'enablePadClearanceCheck', ...
    'enableViaClearanceCheck', ...
    'enableDxfReadbackCheck', ...
    'outputRoot', 'designName'};

for i = 1:numel(requiredFields)
    if ~isfield(cfg, requiredFields{i})
        error('cfg缺少必需字段：%s', requiredFields{i});
    end
end

numericFields = { ...
    'layerCount', 'turnsPerLayer', ...
    'plateLength', 'plateWidth', 'plateCornerRadius', ...
    'tabLength', 'tabWidth', 'tabOuterCornerRadius', ...
    'tabTransitionRadius', 'tabEdgeMargin', ...
    'traceWidth', 'traceSpacing', 'edgeClearance', ...
    'minInnerWidth', 'minSpiralCornerRadius', ...
    'leadYOffset', 'leadBendRadius', 'leadArcPointCount', ...
    'padTipInset', 'padDiameter', 'padTipMargin', 'leadTabClearance', ...
    'padToPadClearance', 'padToCopperClearance', ...
    'viaDrillDiameter', 'viaPadDiameter', ...
    'viaToCopperClearance', 'viaToBoardClearance', ...
    'viaToViaClearance', 'viaToPadClearance', ...
    'viaLandingLeadLength', 'viaLandingClearance', ...
    'viaInnerBendRadius', ...
    'viaOuterLandingLeadLength', 'viaOuterLandingClearance', ...
    'viaOuterBendRadius', ...
    'copperThickness', 'copperResistivity', ...
    'minCopperInteriorAngleDeg', 'minBoardInteriorAngleDeg', ...
    'angleToleranceDeg', 'crossProductTolerance', ...
    'parameterTolerance', 'geometryTolerance', ...
    'connectionTolerance', 'clearanceTolerance', 'pitchMargin', ...
    'pointsPerTurn', 'minTurnPointCount', 'boardArcPointCount', ...
    'maxVerticesPerDxfEntity', 'previewDpi'};

for i = 1:numel(numericFields)
    validateattributes(cfg.(numericFields{i}), ...
        {'numeric'}, {'scalar', 'real', 'finite'});
end

if ~ischar(cfg.outputRoot) || ~ischar(cfg.designName)
    error('cfg.outputRoot和cfg.designName必须是字符数组。');
end

if ~(cfg.layerCount == 2 || cfg.layerCount == 4)
    error('cfg.layerCount必须为2或4。');
end

if cfg.turnsPerLayer < 1 || cfg.turnsPerLayer ~= floor(cfg.turnsPerLayer)
    error('cfg.turnsPerLayer必须是正整数。');
end

if cfg.plateLength <= 0 || cfg.plateWidth <= 0
    error('主体长度和宽度必须大于0。');
end

if cfg.plateCornerRadius < 0 || ...
        cfg.plateCornerRadius > min(cfg.plateLength, cfg.plateWidth)/2
    error('cfg.plateCornerRadius无效。');
end

if cfg.tabLength <= 0 || cfg.tabWidth <= 0
    error('尾部长度和宽度必须大于0。');
end

if cfg.tabOuterCornerRadius < 0 || ...
        cfg.tabOuterCornerRadius > min(cfg.tabLength, cfg.tabWidth)/2
    error('cfg.tabOuterCornerRadius无效。');
end

if cfg.tabTransitionRadius <= 0
    error('cfg.tabTransitionRadius必须大于0。');
end

if cfg.tabEdgeMargin < 0 || cfg.padTipMargin < 0 || ...
        cfg.leadTabClearance < 0
    error('tabEdgeMargin、padTipMargin和leadTabClearance不得小于0。');
end

if cfg.traceWidth <= 0 || cfg.traceSpacing < 0 || cfg.edgeClearance < 0
    error('线宽必须大于0，线距和边距不得小于0。');
end

if cfg.minInnerWidth <= 0
    error('cfg.minInnerWidth必须大于0。');
end

if cfg.minSpiralCornerRadius < cfg.traceWidth
    warning('cfg.minSpiralCornerRadius小于线宽，建议适当增大。');
end

if cfg.leadYOffset <= 0 || cfg.leadBendRadius <= 0
    error('引出线Y偏移和圆弧半径必须大于0。');
end

if cfg.leadArcPointCount < 8 || cfg.leadArcPointCount ~= floor(cfg.leadArcPointCount)
    error('cfg.leadArcPointCount必须是大于等于8的整数。');
end

if cfg.padTipInset <= 0 || cfg.padDiameter <= 0
    error('焊盘相关参数必须大于0。');
end

if cfg.viaDrillDiameter <= 0 || cfg.viaPadDiameter <= cfg.viaDrillDiameter
    error('过孔尺寸无效：钻孔必须大于0，焊盘必须大于钻孔。');
end

if cfg.copperThickness <= 0 || cfg.copperResistivity <= 0
    error('铜厚和铜电阻率必须大于0。');
end

if cfg.minCopperInteriorAngleDeg < 90 || cfg.minCopperInteriorAngleDeg > 180
    error('cfg.minCopperInteriorAngleDeg必须位于90到180度之间。');
end

if cfg.minBoardInteriorAngleDeg < 90 || cfg.minBoardInteriorAngleDeg >= 180
    error('cfg.minBoardInteriorAngleDeg必须位于90到180度之间。');
end

if cfg.angleToleranceDeg < 0 || cfg.angleToleranceDeg >= 90
    error('cfg.angleToleranceDeg必须大于等于0且小于90。');
end

if cfg.geometryTolerance <= 0 || cfg.connectionTolerance <= 0 || ...
        cfg.clearanceTolerance < 0
    error('几何/连接/线距容差必须有效。');
end

if cfg.pitchMargin <= 0
    error('cfg.pitchMargin必须大于0。');
end

if cfg.crossProductTolerance <= 0 || cfg.parameterTolerance <= 0
    error('cfg.crossProductTolerance和cfg.parameterTolerance必须大于0。');
end

if cfg.padToPadClearance < 0 || cfg.padToCopperClearance < 0
    error('焊盘间距和焊盘到铜线间距不得小于0。');
end

if cfg.viaToCopperClearance < 0 || cfg.viaToBoardClearance < 0 || ...
        cfg.viaToViaClearance < 0 || cfg.viaToPadClearance < 0
    error('过孔相关间距参数不得小于0。');
end

if cfg.viaLandingLeadLength <= 0 || cfg.viaLandingClearance < 0 || ...
        cfg.viaInnerBendRadius <= 0
    error('V12/V34内侧过孔引出参数无效。');
end

if cfg.viaOuterLandingLeadLength <= 0 || ...
        cfg.viaOuterLandingClearance < 0 || ...
        cfg.viaOuterBendRadius <= 0
    error('V23外侧过孔引出参数无效。');
end

if ~ismember(cfg.viaClearanceSeverity, {'warning', 'error'})
    error('cfg.viaClearanceSeverity必须是warning或error。');
end

if cfg.pointsPerTurn < 100 || cfg.pointsPerTurn ~= floor(cfg.pointsPerTurn)
    error('cfg.pointsPerTurn必须是大于等于100的整数。');
end

if cfg.minTurnPointCount < 100 || ...
        cfg.minTurnPointCount ~= floor(cfg.minTurnPointCount)
    error('cfg.minTurnPointCount必须是大于等于100的整数。');
end

if cfg.boardArcPointCount < 8 || ...
        cfg.boardArcPointCount ~= floor(cfg.boardArcPointCount)
    error('cfg.boardArcPointCount必须是大于等于8的整数。');
end

if cfg.maxVerticesPerDxfEntity < 2 || ...
        cfg.maxVerticesPerDxfEntity ~= floor(cfg.maxVerticesPerDxfEntity)
    error('cfg.maxVerticesPerDxfEntity必须是大于等于2的整数。');
end

if cfg.previewDpi <= 0
    error('cfg.previewDpi必须大于0。');
end

checkBooleanField(cfg, 'enableExactSelfIntersectionCheck');
checkBooleanField(cfg, 'enableCopperClearanceCheck');
checkBooleanField(cfg, 'enableBoardAngleCheck');
checkBooleanField(cfg, 'enableCopperAngleCheck');
checkBooleanField(cfg, 'useRecommendedTurns');
checkBooleanField(cfg, 'enablePadClearanceCheck');
checkBooleanField(cfg, 'enableViaClearanceCheck');
checkBooleanField(cfg, 'enableDxfReadbackCheck');
checkBooleanField(cfg, 'enablePreview');

if isempty(cfg.outputRoot) || isempty(cfg.designName)
    error('cfg.outputRoot和cfg.designName不能为空。');
end

if isempty(regexp(cfg.designName, '^[A-Za-z0-9_-]+$', 'once'))
    error('cfg.designName只能包含英文、数字、下划线和连字符。');
end

if contains(cfg.designName, '..') || ...
        contains(cfg.designName, '/') || ...
        contains(cfg.designName, '\')
    error('cfg.designName不得包含路径分隔符或连续点。');
end

end

function checkBooleanField(cfg, fieldName)

value = cfg.(fieldName);
if ~isscalar(value) || ...
        (~islogical(value) && ~ismember(value, [0,1]))
    error('cfg.%s必须是逻辑值或0/1。', fieldName);
end

end

%% =========================================================
function d = calculateDerivedParameters(cfg)

d.pitch = cfg.traceWidth + cfg.traceSpacing + cfg.pitchMargin;
d.outerCenterInset = cfg.edgeClearance + cfg.traceWidth/2;

d.outerLength = cfg.plateLength - 2*d.outerCenterInset;
d.outerWidth  = cfg.plateWidth  - 2*d.outerCenterInset;
d.outerRadius = min( ...
    max(cfg.plateCornerRadius - d.outerCenterInset, cfg.minSpiralCornerRadius), ...
    min(d.outerLength, d.outerWidth)/2);

d.rightStraightHalf = d.outerWidth/2 - d.outerRadius;
d.outerPerimeter = roundedRectPerimeter( ...
    d.outerLength, d.outerWidth, d.outerRadius);

d.leadJoinAbsY = abs(cfg.leadYOffset) + cfg.leadBendRadius;
d.padAPhase = d.leadJoinAbsY / d.outerPerimeter;
d.padBPhase = mod(1 - d.leadJoinAbsY / d.outerPerimeter, 1);
d.totalExitDelta = forwardPhaseDelta( ...
    d.padAPhase, d.padBPhase, cfg.geometryTolerance);
routingDelta = d.totalExitDelta;

% 四层额外增加一整圈相位，使V23落在右侧中部
if cfg.layerCount == 4
    routingDelta = routingDelta + 1;
end

d.phaseStep = routingDelta / cfg.layerCount;

d.bodyRightX = cfg.plateLength/2;
d.tabTipX = d.bodyRightX + cfg.tabLength;
d.outerRightCenterX = d.bodyRightX - d.outerCenterInset;
d.requiredHalfWidth = abs(cfg.leadYOffset) + ...
    max(cfg.traceWidth/2, cfg.padDiameter/2) + cfg.tabEdgeMargin;

d.padA = [d.tabTipX - cfg.padTipInset, +cfg.leadYOffset];
d.padB = [d.tabTipX - cfg.padTipInset, -cfg.leadYOffset];

end

%% =========================================================
function maxTurns = calculateMaximumTurns(cfg, d)

maxEffectiveTurns = ...
    (cfg.plateWidth - 2*d.outerCenterInset - cfg.minInnerWidth) / ...
    (2*d.pitch);
maxTurns = floor(maxEffectiveTurns - d.phaseStep);
maxTurns = max(maxTurns, 0);

end

%% =========================================================
function [layerXY, viaXY, connectionErrors, escapeArcFallback] = ...
    buildLayerGeometry(cfg, d)

tol = cfg.geometryTolerance;
phaseNodes = mod(d.padAPhase + (0:cfg.layerCount)*d.phaseStep, 1);
rawLayerXY = cell(cfg.layerCount, 1);

for k = 1:cfg.layerCount
    if mod(k,2) == 1
        radialMode = 'outerToInner';
    else
        radialMode = 'innerToOuter';
    end

    [rawLayerXY{k}, ~] = generateRoundedRectSpiral( ...
        cfg, d, phaseNodes(k), phaseNodes(k+1), radialMode);
end

layerXY = rawLayerXY;
[layerXY{1}, ~] = generateTangentLead( ...
    layerXY{1}, d.padA, d.outerRightCenterX, ...
    cfg.leadYOffset, cfg.leadBendRadius, cfg.leadArcPointCount, ...
    'prepend', tol);
[layerXY{cfg.layerCount}, ~] = generateTangentLead( ...
    layerXY{cfg.layerCount}, d.padB, d.outerRightCenterX, ...
    -cfg.leadYOffset, cfg.leadBendRadius, cfg.leadArcPointCount, ...
    'append', tol);

viaXY = zeros(cfg.layerCount-1, 2);
escapeArcFallback = false;

for k = 1:cfg.layerCount-1
    endPoint = rawLayerXY{k}(end,:);
    startPoint = rawLayerXY{k+1}(1,:);
    rawConnectionError = norm(endPoint - startPoint);
    if rawConnectionError > cfg.connectionTolerance
        error('L%d与L%d原始连接误差%.6f mm，超过容差%.6f mm', ...
            k, k+1, rawConnectionError, cfg.connectionTolerance);
    end

    if mod(k,2) == 1
        if size(rawLayerXY{k},1) < 2
            error('L%d螺旋点数不足，无法生成逃逸引线。', k);
        end

        tangent = endPoint - rawLayerXY{k}(end-1,:);
        tangentLength = norm(tangent);
        if tangentLength < tol
            error('L%d末端切线无效。', k);
        end
        tangent = tangent/tangentLength;
        inwardA = [-tangent(2), tangent(1)];
        inwardB = -inwardA;
        if dot(inwardA, -endPoint) >= dot(inwardB, -endPoint)
            inward = inwardA;
        else
            inward = inwardB;
        end

        landing = endPoint + inward*cfg.viaLandingLeadLength;
        bendRadius = cfg.viaInnerBendRadius;
    else
        landing = endPoint + [cfg.viaOuterLandingLeadLength, 0];
        bendRadius = cfg.viaOuterBendRadius;
    end

    [layerXY{k}, usedArc] = appendEscapeLead( ...
        layerXY{k}, landing, tol, cfg.leadArcPointCount, bendRadius);
    escapeArcFallback = escapeArcFallback || ~usedArc;

    [layerXY{k+1}, usedArc] = prependEscapeLead( ...
        layerXY{k+1}, landing, tol, cfg.leadArcPointCount, bendRadius);
    escapeArcFallback = escapeArcFallback || ~usedArc;
    viaXY(k,:) = landing;
end

for k = 1:cfg.layerCount
    layerXY{k} = removeDuplicatePoints(layerXY{k}, tol);
    layerXY{k} = removeZeroLengthSegments(layerXY{k}, tol);
end

connectionErrors = zeros(cfg.layerCount-1, 1);
for k = 1:cfg.layerCount-1
    connectionErrors(k) = norm(layerXY{k}(end,:) - layerXY{k+1}(1,:));
end

end

%% =========================================================
function maxTurns = calculateFullyValidatedMaximumTurns( ...
    cfg, d, boardXY, widthBasedMaxTurns)

maxTurns = 0;
for turns = widthBasedMaxTurns:-1:1
    candidateCfg = cfg;
    candidateCfg.turnsPerLayer = turns;
    if isCandidateGeometryValid(candidateCfg, d, boardXY)
        maxTurns = turns;
        return;
    end
end

end

%% =========================================================
function pass = isCandidateGeometryValid(cfg, d, boardXY)

pass = false;
tol = cfg.geometryTolerance;

try
    [layerXY, viaXY, connectionErrors] = buildLayerGeometry(cfg, d);
catch
    return;
end

if any(~isfinite(boardXY), 'all') || ...
        any(cellfun(@(xy) any(~isfinite(xy), 'all'), layerXY)) || ...
        any(cellfun(@(xy) anyZeroLengthSegments(xy, tol), layerXY)) || ...
        any(connectionErrors > cfg.connectionTolerance)
    return;
end

for k = 1:cfg.layerCount
    if minimumOpenPolylineInteriorAngle(layerXY{k}, tol) < ...
            cfg.minCopperInteriorAngleDeg - cfg.angleToleranceDeg
        return;
    end
    if checkPolylineSelfIntersectionExact(layerXY{k}, false, cfg)
        return;
    end

    minIndexSeparation = max(16, ceil(cfg.pointsPerTurn/4));
    [~, spacingPass] = calculateMinimumNonAdjacentDistance( ...
        layerXY{k}, cfg.traceWidth + cfg.traceSpacing, ...
        cfg.clearanceTolerance, minIndexSeparation, tol);
    if ~spacingPass
        return;
    end
end

padConnectionLength = ...
    (d.padA(1) - (d.outerRightCenterX + cfg.leadBendRadius)) + ...
    (pi/2)*cfg.leadBendRadius;
if ~validatePadToBoard(d.padA, d.padB, boardXY, cfg, tol) || ...
        ~validatePadToPad(d.padA, d.padB, cfg, tol) || ...
        ~validatePadToCopper( ...
            d.padA, d.padB, layerXY, cfg, tol, padConnectionLength) || ...
        ~validateViaToVia(viaXY, cfg, tol) || ...
        ~validateViaToBoard(viaXY, boardXY, cfg, tol) || ...
        ~validateViaToPad(viaXY, d.padA, d.padB, cfg, tol)
    return;
end

viaEscapeLengths = zeros(cfg.layerCount-1, 1);
viaEscapeLengths(1:2:end) = cfg.viaLandingLeadLength;
viaEscapeLengths(2:2:end) = cfg.viaOuterLandingLeadLength;
viaConnectedClearances = zeros(cfg.layerCount-1, 1);
viaConnectedClearances(1:2:end) = cfg.viaLandingClearance;
viaConnectedClearances(2:2:end) = cfg.viaOuterLandingClearance;
[connectedPass, nonConnectedPass] = validateViaToCopper( ...
    viaXY, layerXY, cfg, tol, viaEscapeLengths, viaConnectedClearances);

pass = connectedPass && nonConnectedPass;

end

%% =========================================================
function [xy, turnIndex] = generateRoundedRectSpiral( ...
    cfg, d, startPhase, endPhase, radialMode)

deltaPhase = forwardPhaseDelta( ...
    startPhase, endPhase, cfg.geometryTolerance);
effectiveTurns = cfg.turnsPerLayer + deltaPhase;
radialSpan = effectiveTurns*d.pitch;

pointCount = max(cfg.minTurnPointCount, ...
    ceil(cfg.pointsPerTurn*effectiveTurns) + 1);
t = linspace(0, 1, pointCount).';
phaseUnwrapped = startPhase + effectiveTurns*t;
phase = mod(phaseUnwrapped, 1);
turnIndex = floor(phaseUnwrapped);

switch lower(radialMode)
    case 'outertoinner'
        inset = d.outerCenterInset + radialSpan*t;
    case 'innertoouter'
        inset = d.outerCenterInset + radialSpan*(1-t);
    otherwise
        error('radialMode必须为outerToInner或innerToOuter。');
end

localLength = cfg.plateLength - 2*inset;
localWidth  = cfg.plateWidth  - 2*inset;

if any(localLength <= 0 | localWidth <= 0)
    error('内缩过程中轮廓消失，请减少匝数。');
end

localRadius = max(cfg.plateCornerRadius - inset, cfg.minSpiralCornerRadius);
localRadius = min(localRadius, min(localLength, localWidth)/2);

xy = roundedRectPoints( ...
    localLength, localWidth, localRadius, phase, cfg.geometryTolerance);

end

%% =========================================================
function [xy, turnIndex] = generateTangentLead( ...
    coilXY, padXY, outerRightCenterX, leadLineY, ...
    bendRadius, pointCount, mode, tol)

switch lower(mode)
    case 'prepend'
        expectedJoin = [outerRightCenterX, leadLineY + bendRadius];
        if norm(coilXY(1,:) - expectedJoin) > tol
            error('顶层线圈起点与圆弧终点不一致。');
        end

        arcCenter = [outerRightCenterX + bendRadius, ...
                     leadLineY + bendRadius];
        theta = linspace(-pi/2, -pi, pointCount).';
        arcXY = [arcCenter(1) + bendRadius*cos(theta), ...
                 arcCenter(2) + bendRadius*sin(theta)];

        xy = [padXY; arcXY; coilXY(2:end,:)];

    case 'append'
        expectedJoin = [outerRightCenterX, leadLineY - bendRadius];
        if norm(coilXY(end,:) - expectedJoin) > tol
            error('末层线圈终点与圆弧起点不一致。');
        end

        arcCenter = [outerRightCenterX + bendRadius, ...
                     leadLineY - bendRadius];
        theta = linspace(-pi, -3*pi/2, pointCount).';
        arcXY = [arcCenter(1) + bendRadius*cos(theta), ...
                 arcCenter(2) + bendRadius*sin(theta)];

        xy = [coilXY; arcXY(2:end,:); padXY];

    otherwise
        error('mode必须为prepend或append。');
end

xy = removeDuplicatePoints(xy, tol);
turnIndex = [];

end

%% =========================================================
function [xy, usedArc] = appendEscapeLead( ...
    xy, landing, tol, arcPointCount, maxRadius)

usedArc = false;

if size(xy,1) < 2
    xy = [xy; landing];
    return;
end

corner = xy(end,:);
lastDir = corner - xy(end-1,:);
lastLength = norm(lastDir);

if lastLength <= tol
    xy = [xy; landing];
    return;
end

t0 = lastDir/lastLength;
toLanding = landing - corner;
leadLength = norm(toLanding);

if leadLength <= tol
    return;
end

t1 = toLanding/leadLength;
crossVal = cross2(t0, t1);
dotVal = dot(t0, t1);

if abs(crossVal) <= 1e-9 && dotVal > 0
    xy = [xy; landing];
    usedArc = true;
    return;
end

sweep = atan2(crossVal, dotVal);
tanHalf = tan(abs(sweep)/2);
availableBackLength = calculatePathLength(xy);

if tanHalf <= 1e-9 || ~isfinite(tanHalf)
    xy = [xy; landing];
    return;
end

radius = min([maxRadius, ...
    0.95*availableBackLength/tanHalf, 0.95*leadLength/tanHalf]);

if radius <= tol*10
    xy = [xy; landing];
    return;
end

trimDistance = radius * tan(abs(sweep)/2);
[trimmedXY, arcStart, trimSegmentIndex] = ...
    trimPolylineEndByDistance(xy, trimDistance, tol);
if trimSegmentIndex < 1
    xy = [xy; landing];
    return;
end

turnSign = sign(crossVal);
leftNormal = [-t0(2), t0(1)];
center = arcStart + turnSign*radius*leftNormal;
arcEnd = corner + trimDistance*t1;
thetaStart = atan2(arcStart(2) - center(2), arcStart(1) - center(1));
thetaEnd = atan2(arcEnd(2) - center(2), arcEnd(1) - center(1));

if turnSign > 0
    sweepAngle = mod(thetaEnd - thetaStart, 2*pi);
else
    sweepAngle = -mod(thetaStart - thetaEnd, 2*pi);
end

if abs(abs(sweepAngle) - abs(sweep)) > 1e-6
    xy = [xy; landing];
    return;
end

theta = thetaStart + sweepAngle*linspace(0, 1, arcPointCount).';
arcXY = [center(1) + radius*cos(theta), ...
         center(2) + radius*sin(theta)];

xy = [trimmedXY(1:trimSegmentIndex,:); arcXY; landing];
xy = removeDuplicatePoints(xy, tol);
usedArc = true;

end

%% =========================================================
function [trimmedXY, trimPoint, trimSegmentIndex] = ...
    trimPolylineEndByDistance(xy, trimDistance, tol)

trimmedXY = xy;
trimPoint = xy(end,:);
trimSegmentIndex = 0;
remaining = trimDistance;

for i = size(xy,1)-1:-1:1
    segment = xy(i+1,:) - xy(i,:);
    segmentLength = norm(segment);
    if segmentLength <= tol
        continue;
    end

    if remaining <= segmentLength + tol
        fraction = min(max(remaining/segmentLength, 0), 1);
        trimPoint = xy(i+1,:) - fraction*segment;
        trimmedXY = [xy(1:i,:); trimPoint];
        trimSegmentIndex = size(trimmedXY,1);
        return;
    end

    remaining = remaining - segmentLength;
end

end

%% =========================================================
function [xy, usedArc] = prependEscapeLead( ...
    xy, landing, tol, arcPointCount, maxRadius)

xy = flipud(xy);
[xy, usedArc] = appendEscapeLead( ...
    xy, landing, tol, arcPointCount, maxRadius);
xy = flipud(xy);

end

%% =========================================================
function c = cross2(a, b)

c = a(1)*b(2) - a(2)*b(1);

end

%% =========================================================
function outlineXY = generateSmoothBoardOutline(cfg)

L = cfg.plateLength;
W = cfg.plateWidth;
R = cfg.plateCornerRadius;
tabLength = cfg.tabLength;
tabHalfWidth = cfg.tabWidth/2;
tabRadius = cfg.tabOuterCornerRadius;
transitionRadius = cfg.tabTransitionRadius;
arcPointCount = cfg.boardArcPointCount;
tol = cfg.geometryTolerance;

hx = L/2;
hy = W/2;

R = max(0, min(R, min(hx, hy)));
tabRadius = max(0, min(tabRadius, min(tabLength, cfg.tabWidth)/2));

if transitionRadius <= 0
    error('tabTransitionRadius必须大于0。');
end

if tabHalfWidth + 2*transitionRadius > hy + tol
    error('tabTransitionRadius过大，无法保持在主体上下边界内。');
end

bodyTopRightCenter = [hx-R, hy-R];
bodyBottomRightCenter = [hx-R, -hy+R];

dyTop = tabHalfWidth + transitionRadius - (hy-R);
distTransition = R + transitionRadius;

if abs(dyTop) >= distTransition - tol
    error('tabTransitionRadius无法与主体右上圆角形成相切过渡。');
end

dxTop = sqrt(distTransition^2 - dyTop^2);
ctTop = [bodyTopRightCenter(1) + dxTop, tabHalfWidth + transitionRadius];
unitTop = [dxTop, dyTop]/distTransition;
pTop = bodyTopRightCenter + R*unitTop;
qTop = [ctTop(1), tabHalfWidth];

bodyThetaTopEnd = atan2(pTop(2) - bodyTopRightCenter(2), ...
                        pTop(1) - bodyTopRightCenter(1));
thetaPTop = atan2(pTop(2) - ctTop(2), pTop(1) - ctTop(1));
thetaQTop = -pi/2;
sweepTop = mod(thetaQTop - thetaPTop, 2*pi);
if sweepTop > pi
    sweepTop = sweepTop - 2*pi;
end

thetaTop = thetaPTop + sweepTop*linspace(0,1,arcPointCount).';
arcTop = [ctTop(1) + transitionRadius*cos(thetaTop), ...
          ctTop(2) + transitionRadius*sin(thetaTop)];

dyBottom = (-tabHalfWidth - transitionRadius) - (-hy + R);
dxBottom = sqrt(distTransition^2 - dyBottom^2);
ctBottom = [bodyBottomRightCenter(1) + dxBottom, ...
            -tabHalfWidth - transitionRadius];
unitBottom = [dxBottom, dyBottom]/distTransition;
pBottom = bodyBottomRightCenter + R*unitBottom;
qBottom = [ctBottom(1), -tabHalfWidth];

bodyThetaBottomEnd = atan2(pBottom(2) - bodyBottomRightCenter(2), ...
                           pBottom(1) - bodyBottomRightCenter(1));
thetaPBottom = atan2(pBottom(2) - ctBottom(2), ...
                     pBottom(1) - ctBottom(1));
thetaQBottom = pi/2;
sweepBottom = mod(thetaQBottom - thetaPBottom, 2*pi);
if sweepBottom > pi
    sweepBottom = sweepBottom - 2*pi;
end

thetaBottom = thetaPBottom + sweepBottom*linspace(0,1,arcPointCount).';
arcBottomP2Q = [ctBottom(1) + transitionRadius*cos(thetaBottom), ...
                ctBottom(2) + transitionRadius*sin(thetaBottom)];
arcBottomQ2P = flipud(arcBottomP2Q);

xTabRight = hx + tabLength;
xTabArcCenter = xTabRight - tabRadius;
yTabTop = tabHalfWidth;
yTabBottom = -tabHalfWidth;
yTabUpperArcCenter = yTabTop - tabRadius;
yTabLowerArcCenter = yTabBottom + tabRadius;

if qTop(1) >= xTabArcCenter - tol
    error('tabTransitionRadius过大或tabLength过短，过渡圆弧会越过尾部外圆角。');
end

parts = cell(14,1);

parts{1} = [qTop; xTabArcCenter, yTabTop];
parts{2} = sampleArc(xTabArcCenter, yTabUpperArcCenter, tabRadius, ...
    pi/2, 0, arcPointCount, tol);
parts{3} = [xTabRight, yTabUpperArcCenter; ...
            xTabRight, yTabLowerArcCenter];
parts{4} = sampleArc(xTabArcCenter, yTabLowerArcCenter, tabRadius, ...
    0, -pi/2, arcPointCount, tol);
parts{5} = [xTabArcCenter, yTabBottom; qBottom];
parts{6} = arcBottomQ2P;
parts{7} = sampleArc(bodyBottomRightCenter(1), bodyBottomRightCenter(2), R, ...
    bodyThetaBottomEnd, -pi/2, arcPointCount, tol);
parts{8} = [hx-R, -hy; -hx+R, -hy];
parts{9} = sampleArc(-hx+R, -hy+R, R, -pi/2, -pi, arcPointCount, tol);
parts{10} = [-hx, -hy+R; -hx, hy-R];
parts{11} = sampleArc(-hx+R, hy-R, R, pi, pi/2, arcPointCount, tol);
parts{12} = [-hx+R, hy; hx-R, hy];
parts{13} = sampleArc(bodyTopRightCenter(1), bodyTopRightCenter(2), R, ...
    pi/2, bodyThetaTopEnd, arcPointCount, tol);
parts{14} = arcTop;

outlineXY = vertcat(parts{:});
outlineXY = removeDuplicatePoints(outlineXY, tol);
outlineXY = removeZeroLengthSegments(outlineXY, tol);

if norm(outlineXY(end,:) - outlineXY(1,:)) < tol
    outlineXY(end,:) = [];
end

if size(outlineXY,1) < 12
    error('生成的板框点数异常。');
end

if any(~isfinite(outlineXY), 'all')
    error('生成的板框包含无效坐标。');
end

end

%% =========================================================
function xy = sampleArc(cx, cy, r, thetaStart, thetaEnd, pointCount, tol)

if r <= tol
    xy = [cx, cy];
    return;
end

theta = linspace(thetaStart, thetaEnd, pointCount).';
xy = [cx + r*cos(theta), cy + r*sin(theta)];

end

%% =========================================================
function xy = roundedRectPoints(L, W, R, phase, tol)

n = numel(phase);
L = expandColumn(L, n);
W = expandColumn(W, n);
R = expandColumn(R, n);
phase = phase(:);

hx = L/2;
hy = W/2;
R = max(0, min(R, min(hx, hy)));

a = hy - R;
b = 2*(hx - R);
q = pi*R/2;

segmentLengths = [a, q, b, q, 2*a, q, b, q, a];
perimeter = sum(segmentLengths, 2);

if any(perimeter <= 0)
    error('圆角矩形周长无效。');
end

d = mod(phase,1).*perimeter;
boundary = cumsum(segmentLengths, 2);

seg = sum(d > boundary(:,1:end-1), 2) + 1;
seg = min(seg, 9);

row = (1:n).';
startBoundary = [zeros(n,1), boundary(:,1:8)];
localD = d - startBoundary(sub2ind([n,9], row, seg));

xy = zeros(n,2);

idx = seg == 1;
xy(idx,:) = [hx(idx), localD(idx)];

idx = seg == 2;
theta = localD(idx)./R(idx);
xy(idx,:) = [hx(idx)-R(idx)+R(idx).*cos(theta), ...
             hy(idx)-R(idx)+R(idx).*sin(theta)];

idx = seg == 3;
xy(idx,:) = [hx(idx)-R(idx)-localD(idx), hy(idx)];

idx = seg == 4;
theta = pi/2 + localD(idx)./R(idx);
xy(idx,:) = [-hx(idx)+R(idx)+R(idx).*cos(theta), ...
             hy(idx)-R(idx)+R(idx).*sin(theta)];

idx = seg == 5;
xy(idx,:) = [-hx(idx), hy(idx)-R(idx)-localD(idx)];

idx = seg == 6;
theta = pi + localD(idx)./R(idx);
xy(idx,:) = [-hx(idx)+R(idx)+R(idx).*cos(theta), ...
             -hy(idx)+R(idx)+R(idx).*sin(theta)];

idx = seg == 7;
xy(idx,:) = [-hx(idx)+R(idx)+localD(idx), -hy(idx)];

idx = seg == 8;
theta = 3*pi/2 + localD(idx)./R(idx);
xy(idx,:) = [hx(idx)-R(idx)+R(idx).*cos(theta), ...
             -hy(idx)+R(idx)+R(idx).*sin(theta)];

idx = seg == 9;
xy(idx,:) = [hx(idx), -hy(idx)+R(idx)+localD(idx)];

xy(abs(xy) < tol) = 0;

end

%% =========================================================
function x = expandColumn(x, n)

x = x(:);
if isscalar(x) && n > 1
    x = repmat(x, n, 1);
end

end

%% =========================================================
function delta = forwardPhaseDelta(startPhase, endPhase, tol)

delta = mod(endPhase - startPhase, 1);
if delta < tol
    delta = 0;
end

end

%% =========================================================
function perimeter = roundedRectPerimeter(L, W, R)

R = min(max(R,0), min(L,W)/2);
perimeter = 2*(L+W-4*R) + 2*pi*R;

end

%% =========================================================
function [xy, keep] = removeDuplicatePoints(xy, tol)

if size(xy,1) < 2
    keep = true(size(xy,1),1);
    return;
end

distance = hypot(diff(xy(:,1)), diff(xy(:,2)));
keep = [true; distance > tol];
xy = xy(keep,:);

end

%% =========================================================
function [xy, keep] = removeZeroLengthSegments(xy, tol)

if size(xy,1) < 2
    keep = true(size(xy,1),1);
    return;
end

distance = hypot(diff(xy(:,1)), diff(xy(:,2)));
keep = [true; distance > tol];
xy = xy(keep,:);

end

%% =========================================================
function tf = anyZeroLengthSegments(xy, tol)

tf = false;
if size(xy,1) < 2
    return;
end

tf = any(hypot(diff(xy(:,1)), diff(xy(:,2))) <= tol);

end

%% =========================================================
function minAngle = minimumOpenPolylineInteriorAngle(xy, tol)

xy = removeDuplicatePoints(xy, tol);
xy = removeZeroLengthSegments(xy, tol);

if size(xy,1) < 3
    minAngle = 180;
    return;
end

v1 = xy(1:end-2,:) - xy(2:end-1,:);
v2 = xy(3:end,:) - xy(2:end-1,:);

n1 = hypot(v1(:,1), v1(:,2));
n2 = hypot(v2(:,1), v2(:,2));
valid = n1 > tol & n2 > tol;

cosAngle = sum(v1(valid,:).*v2(valid,:), 2) ./ (n1(valid).*n2(valid));
cosAngle = max(-1, min(1, cosAngle));
angles = acosd(cosAngle);

if isempty(angles)
    minAngle = 180;
else
    minAngle = min(angles);
end

end

%% =========================================================
function minAngle = minimumClosedPolylineInteriorAngle(xy, tol)

xy = removeDuplicatePoints(xy, tol);
xy = removeZeroLengthSegments(xy, tol);

if size(xy,1) > 1 && norm(xy(end,:) - xy(1,:)) <= tol
    xy(end,:) = [];
end

m = size(xy,1);

if m < 3
    minAngle = 180;
    return;
end

prev = circshift(xy, 1, 1);
next = circshift(xy, -1, 1);

v1 = prev - xy;
v2 = next - xy;

n1 = hypot(v1(:,1), v1(:,2));
n2 = hypot(v2(:,1), v2(:,2));
valid = n1 > tol & n2 > tol;

cosAngle = sum(v1(valid,:).*v2(valid,:), 2) ./ (n1(valid).*n2(valid));
cosAngle = max(-1, min(1, cosAngle));
angles = acosd(cosAngle);

if isempty(angles)
    minAngle = 180;
else
    minAngle = min(angles);
end

end

%% =========================================================
function tf = checkPolylineSelfIntersectionExact(xy, isClosed, cfg)

tol = cfg.geometryTolerance;
crossTol = cfg.crossProductTolerance;
paramTol = cfg.parameterTolerance;

xy = removeDuplicatePoints(xy, tol);
xy = removeZeroLengthSegments(xy, tol);

if isClosed && size(xy,1) > 1 && norm(xy(end,:) - xy(1,:)) > tol
    xy = [xy; xy(1,:)];
end

n = size(xy,1) - 1;

if n < 2
    tf = false;
    return;
end

p1 = xy(1:end-1,:);
p2 = xy(2:end,:);

minX = min(p1(:,1), p2(:,1));
maxX = max(p1(:,1), p2(:,1));
minY = min(p1(:,2), p2(:,2));
maxY = max(p1(:,2), p2(:,2));

[~, order] = sort(minX);
active = zeros(0,1);
tf = false;
tol2 = tol*tol;

for idx = 1:n
    i = order(idx);
    active = active(maxX(active) >= minX(i) - tol);

    if ~isempty(active)
        j = active(abs(active - i) > 1);

        if isClosed
            j = j(~((j == 1 & i == n) | (j == n & i == 1)));
        end

        if ~isempty(j)
            shared = ...
                sum((p1(j,:) - p1(i,:)).^2, 2) < tol2 | ...
                sum((p1(j,:) - p2(i,:)).^2, 2) < tol2 | ...
                sum((p2(j,:) - p1(i,:)).^2, 2) < tol2 | ...
                sum((p2(j,:) - p2(i,:)).^2, 2) < tol2;

            % 非相邻线段共用端点属于自接触，直接判为自相交
            if any(shared)
                tf = true;
                return;
            end
        end

        if ~isempty(j)
            j = j(minY(j) <= maxY(i) + tol & maxY(j) >= minY(i) - tol);
        end

        if ~isempty(j)
            r = p1(j,:) - p1(i,:);
            d1 = p2(i,:) - p1(i,:);
            d2 = p2(j,:) - p1(j,:);

            den = d1(:,1).*d2(:,2) - d1(:,2).*d2(:,1);
            s1 = r(:,1).*d2(:,2) - r(:,2).*d2(:,1);
            s2 = r(:,1).*d1(:,2) - r(:,2).*d1(:,1);

            nonParallel = abs(den) > crossTol;
            t = NaN(size(den));
            u = NaN(size(den));
            t(nonParallel) = s1(nonParallel)./den(nonParallel);
            u(nonParallel) = s2(nonParallel)./den(nonParallel);

            % 非相邻候选采用包含端点的判断，可捕获T形接触
            hit = nonParallel & ...
                t >= -paramTol & t <= 1 + paramTol & ...
                u >= -paramTol & u <= 1 + paramTol;

            if any(hit)
                tf = true;
                return;
            end

            col = abs(den) <= crossTol & ...
                abs(s1) <= crossTol & abs(s2) <= crossTol;

            if any(col)
                jc = j(col);
                e1 = p1(jc,:);
                e2 = p2(jc,:);
                q1 = p1(i,:);
                q2 = p2(i,:);
                dvec = q2 - q1;
                denom = sum(dvec.*dvec, 2);

                t1 = sum((e1 - q1).*dvec, 2)./denom;
                t2 = sum((e2 - q1).*dvec, 2)./denom;

                ov = max(0, min(max(t1,t2), 1) - max(min(t1,t2), 0));

                if any(ov > paramTol)
                    tf = true;
                    return;
                end
            end
        end
    end

    active(end+1,1) = i;
end

end

%% =========================================================
function [minDist, passed] = calculateMinimumNonAdjacentDistance( ...
    xy, targetDistance, clearanceTolerance, ...
    minIndexSeparation, tol)

[xy, ~] = removeDuplicatePoints(xy, tol);
[xy, ~] = removeZeroLengthSegments(xy, tol);

n = size(xy,1) - 1;

if n < 2
    minDist = Inf;
    passed = true;
    return;
end

p1 = xy(1:end-1,:);
p2 = xy(2:end,:);

minX = min(p1(:,1), p2(:,1));
maxX = max(p1(:,1), p2(:,1));
minY = min(p1(:,2), p2(:,2));
maxY = max(p1(:,2), p2(:,2));

threshold = targetDistance - clearanceTolerance;
best = Inf;
passed = true;

[~, order] = sort(minX);
active = zeros(0,1);
tol2 = tol*tol;

for idx = 1:n
    i = order(idx);
    active = active(maxX(active) >= minX(i) - best);

    if ~isempty(active)
        j = active(abs(active - i) > minIndexSeparation);

        if ~isempty(j)
            shared = ...
                sum((p1(j,:) - p1(i,:)).^2, 2) < tol2 | ...
                sum((p1(j,:) - p2(i,:)).^2, 2) < tol2 | ...
                sum((p2(j,:) - p1(i,:)).^2, 2) < tol2 | ...
                sum((p2(j,:) - p2(i,:)).^2, 2) < tol2;
            j = j(~shared);
        end

        if ~isempty(j)
            j = j(maxY(j) >= minY(i) - best & minY(j) <= maxY(i) + best);
        end

        if ~isempty(j)
            dist = minimumSegmentPairDistance(i, j, p1, p2);
            best = min(best, min(dist));

            if best < threshold
                passed = false;
            end
        end
    end

    active(end+1,1) = i;
end

minDist = best;

end

%% =========================================================
function d = minimumSegmentPairDistance(i, j, p1, p2)

q1 = p1(i,:);
q2 = p2(i,:);
e1 = p1(j,:);
e2 = p2(j,:);

d1 = pointToSegmentDistance(q1, e1, e2);
d2 = pointToSegmentDistance(q2, e1, e2);
d3 = pointToSegmentDistance(e1, q1, q2);
d4 = pointToSegmentDistance(e2, q1, q2);

d = min([d1, d2, d3, d4], [], 2);

end

%% =========================================================
function dist = pointToSegmentDistance(p, a, b)

ab = b - a;
ap = p - a;
len2 = sum(ab.*ab, 2);
t = sum(ap.*ab, 2)./len2;
t = max(0, min(1, t));
proj = a + t.*ab;
dist = hypot(p(:,1) - proj(:,1), p(:,2) - proj(:,2));

end

%% =========================================================
function pass = validateBoardDimensions(boardXY, cfg, tol)

actualMinX = min(boardXY(:,1));
actualMaxX = max(boardXY(:,1));
actualMinY = min(boardXY(:,2));
actualMaxY = max(boardXY(:,2));

expectedMinX = -cfg.plateLength/2;
expectedMaxX = cfg.plateLength/2 + cfg.tabLength;
expectedMinY = -cfg.plateWidth/2;
expectedMaxY = cfg.plateWidth/2;

dimensionError = max(abs([ ...
    actualMinX - expectedMinX, ...
    actualMaxX - expectedMaxX, ...
    actualMinY - expectedMinY, ...
    actualMaxY - expectedMaxY]));

pass = dimensionError <= tol;

end

%% =========================================================
function pass = validateBoardClosure(boardXY, tol)

pass = false;

if size(boardXY,1) < 3
    return;
end

closingLength = norm(boardXY(end,:) - boardXY(1,:));
if closingLength <= tol
    return;
end

area = abs(sum( ...
    boardXY(1:end-1,1).*boardXY(2:end,2) - ...
    boardXY(2:end,1).*boardXY(1:end-1,2)) + ...
    boardXY(end,1)*boardXY(1,2) - ...
    boardXY(1,1)*boardXY(end,2))/2;

if area <= tol^2
    return;
end

pass = true;

end

%% =========================================================
function pass = validateBodyDimensions(boardXY, cfg, tol)

actualMinX = min(boardXY(:,1));
actualMinY = min(boardXY(:,2));
actualMaxY = max(boardXY(:,2));

pass = abs(actualMinX + cfg.plateLength/2) <= tol && ...
    abs(actualMinY + cfg.plateWidth/2) <= tol && ...
    abs(actualMaxY - cfg.plateWidth/2) <= tol;

if ~pass
    return;
end

topX = boardXY(abs(boardXY(:,2) - cfg.plateWidth/2) <= tol, 1);
bottomX = boardXY(abs(boardXY(:,2) + cfg.plateWidth/2) <= tol, 1);

bodyEdgeMinX = -cfg.plateLength/2 + cfg.plateCornerRadius;
bodyEdgeMaxX =  cfg.plateLength/2 - cfg.plateCornerRadius;

pass = ~isempty(topX) && ~isempty(bottomX) && ...
    min(topX) <= bodyEdgeMinX + tol && ...
    max(topX) >= bodyEdgeMaxX - tol && ...
    min(bottomX) <= bodyEdgeMinX + tol && ...
    max(bottomX) >= bodyEdgeMaxX - tol;

end

%% =========================================================
function pass = validateTabDimensions(boardXY, cfg, tol)

tabTipX = cfg.plateLength/2 + cfg.tabLength;

pass = abs(max(boardXY(:,1)) - tabTipX) <= tol;

if ~pass
    return;
end

rightY = boardXY(abs(boardXY(:,1) - tabTipX) <= tol, 2);
tabStraightHalf = cfg.tabWidth/2 - cfg.tabOuterCornerRadius;

pass = ~isempty(rightY) && ...
    min(rightY) <= -tabStraightHalf + tol && ...
    max(rightY) >= tabStraightHalf - tol;

end

%% =========================================================
function pass = validatePadToBoard(padA, padB, boardXY, cfg, tol)

radius = cfg.padDiameter/2;
[inA, onA] = inpolygon(padA(1), padA(2), boardXY(:,1), boardXY(:,2));
[inB, onB] = inpolygon(padB(1), padB(2), boardXY(:,1), boardXY(:,2));
pass = (inA || onA) && (inB || onB) && ...
       minimumDistancePointToPolyline(padA, boardXY) >= radius - tol && ...
       minimumDistancePointToPolyline(padB, boardXY) >= radius - tol;

end

%% =========================================================
function pass = validatePadToPad(padA, padB, cfg, tol)

requiredCenterDistance = cfg.padDiameter + cfg.padToPadClearance;
pass = norm(padA - padB) >= requiredCenterDistance - tol;

end

%% =========================================================
function pass = validatePadToCopper( ...
    padA, padB, layerXY, cfg, tol, padConnectionLength)

pass = true;
requiredDistance = cfg.padDiameter/2 + cfg.traceWidth/2 + ...
    cfg.padToCopperClearance;
connectedExcludedLength = padConnectionLength + requiredDistance;

for m = 1:numel(layerXY)
    if m == 1
        dA = minimumDistancePointToPolylineExcludingLength( ...
            padA, layerXY{m}, true, connectedExcludedLength);
    else
        dA = minimumDistancePointToPolyline(padA, layerXY{m});
    end

    if dA < requiredDistance - tol
        pass = false;
        return;
    end

    if m == numel(layerXY)
        dB = minimumDistancePointToPolylineExcludingLength( ...
            padB, layerXY{m}, false, connectedExcludedLength);
    else
        dB = minimumDistancePointToPolyline(padB, layerXY{m});
    end

    if dB < requiredDistance - tol
        pass = false;
        return;
    end
end

end

%% =========================================================
function pass = validateViaToVia(viaXY, cfg, tol)

pass = true;
requiredCenterDistance = cfg.viaPadDiameter + cfg.viaToViaClearance;

for i = 1:size(viaXY,1)-1
    for j = i+1:size(viaXY,1)
        if norm(viaXY(i,:) - viaXY(j,:)) < requiredCenterDistance - tol
            pass = false;
            return;
        end
    end
end

end

%% =========================================================
function pass = validateViaToPad(viaXY, padA, padB, cfg, tol)

pass = true;
requiredCenterDistance = cfg.viaPadDiameter/2 + cfg.padDiameter/2 + ...
    cfg.viaToPadClearance;

for k = 1:size(viaXY,1)
    if norm(viaXY(k,:) - padA) < requiredCenterDistance - tol || ...
            norm(viaXY(k,:) - padB) < requiredCenterDistance - tol
        pass = false;
        return;
    end
end

end

%% =========================================================
function pass = validateViaToBoard(viaXY, boardXY, cfg, tol)

pass = true;
requiredPadDistance = cfg.viaPadDiameter/2 + cfg.viaToBoardClearance;
requiredDrillDistance = cfg.viaDrillDiameter/2 + cfg.viaToBoardClearance;

for k = 1:size(viaXY,1)
    [in, on] = inpolygon( ...
        viaXY(k,1), viaXY(k,2), boardXY(:,1), boardXY(:,2));
    d = minimumDistancePointToPolyline(viaXY(k,:), boardXY);

    if ~(in || on) || d < requiredPadDistance - tol || ...
            d < requiredDrillDistance - tol
        pass = false;
        return;
    end
end

end

%% =========================================================
function [connectedPass, nonConnectedPass] = validateViaToCopper( ...
    viaXY, layerXY, cfg, tol, viaEscapeLengths, viaConnectedClearances)

connectedPass = true;
nonConnectedPass = true;
otherRequired = cfg.viaPadDiameter/2 + cfg.traceWidth/2 + ...
    cfg.viaToCopperClearance;

for k = 1:size(viaXY,1)
    connectedRequired = cfg.viaPadDiameter/2 + cfg.traceWidth/2 + ...
        viaConnectedClearances(k);
    connectedExcludedLength = viaEscapeLengths(k) + connectedRequired;

    for m = 1:numel(layerXY)
        if m == k
            d = minimumDistancePointToPolylineExcludingLength( ...
                viaXY(k,:), layerXY{m}, false, connectedExcludedLength);
            if d < connectedRequired - tol
                connectedPass = false;
            end
        elseif m == k+1
            d = minimumDistancePointToPolylineExcludingLength( ...
                viaXY(k,:), layerXY{m}, true, connectedExcludedLength);
            if d < connectedRequired - tol
                connectedPass = false;
            end
        else
            d = minimumDistancePointToPolyline(viaXY(k,:), layerXY{m});
            if d < otherRequired - tol
                nonConnectedPass = false;
            end
        end
    end
end

end

%% =========================================================
function d = minimumDistancePointToPolyline(point, xy)

if size(xy,1) < 2
    d = Inf;
    return;
end

p = repmat(point, size(xy,1)-1, 1);
a = xy(1:end-1,:);
b = xy(2:end,:);
d = min(pointToSegmentDistance(p, a, b));

end

%% =========================================================
function d = minimumDistancePointToPolylineExcludingLength( ...
    point, xy, fromStart, excludedLength)

n = size(xy,1) - 1;

if n < 1
    d = Inf;
    return;
end

d = Inf;
remaining = max(0, excludedLength);

if fromStart
    for i = 1:n
        a = xy(i,:);
        b = xy(i+1,:);
        segLen = norm(b - a);

        if remaining >= segLen
            remaining = remaining - segLen;
            continue;
        end

        if segLen > 1e-12
            frac = max(0, remaining/segLen);
            a2 = a + frac*(b - a);
            d = min(d, pointToSegmentDistance(point, a2, b));
        end

        for j = i+1:n
            d = min(d, pointToSegmentDistance( ...
                point, xy(j,:), xy(j+1,:)));
        end

        break;
    end
else
    for i = n:-1:1
        a = xy(i,:);
        b = xy(i+1,:);
        segLen = norm(b - a);

        if remaining >= segLen
            remaining = remaining - segLen;
            continue;
        end

        if segLen > 1e-12
            frac = max(0, remaining/segLen);
            b2 = b - frac*(b - a);
            d = min(d, pointToSegmentDistance(point, a, b2));
        end

        for j = i-1:-1:1
            d = min(d, pointToSegmentDistance( ...
                point, xy(j,:), xy(j+1,:)));
        end

        break;
    end
end

if isinf(d)
    d = minimumDistancePointToPolyline(point, xy);
end

end

%% =========================================================
function prepareTempOutputDirectory(cfg, tempOutputFolder)

if ~exist(cfg.outputRoot, 'dir')
    mkdir(cfg.outputRoot);
end

if exist(tempOutputFolder, 'dir')
    rmdir(tempOutputFolder, 's');
end

ensureOutputDirectories(tempOutputFolder);

end

%% =========================================================
function ensureOutputDirectories(outputFolder)

folders = { ...
    outputFolder, ...
    fullfile(outputFolder, 'dxf'), ...
    fullfile(outputFolder, 'reports'), ...
    fullfile(outputFolder, 'previews')};

for i = 1:numel(folders)
    if ~exist(folders{i}, 'dir')
        mkdir(folders{i});
    end
end

end

%% =========================================================
function cleanTempOnFailure(tempOutputFolder)

if exist(fullfile(tempOutputFolder, 'dxf'), 'dir')
    rmdir(fullfile(tempOutputFolder, 'dxf'), 's');
end

if exist(fullfile(tempOutputFolder, 'previews'), 'dir')
    rmdir(fullfile(tempOutputFolder, 'previews'), 's');
end

reportsFolder = fullfile(tempOutputFolder, 'reports');
if exist(reportsFolder, 'dir')
    reportFile = fullfile(reportsFolder, '03_validation_report.txt');
    files = dir(fullfile(reportsFolder, '*'));

    for i = 1:numel(files)
        if files(i).isdir
            continue;
        end

        candidate = fullfile(reportsFolder, files(i).name);
        if ~strcmp(candidate, reportFile)
            delete(candidate);
        end
    end
end

end

%% =========================================================
function promoteTempOutput(tempOutputFolder, outputFolder)

backupFolder = [outputFolder '_backup'];

if exist(backupFolder, 'dir')
    rmdir(backupFolder, 's');
end

if exist(outputFolder, 'dir')
    movefile(outputFolder, backupFolder);
end

try
    movefile(tempOutputFolder, outputFolder);

    if exist(backupFolder, 'dir')
        rmdir(backupFolder, 's');
    end
catch ME
    if exist(outputFolder, 'dir')
        rmdir(outputFolder, 's');
    end

    if exist(backupFolder, 'dir')
        movefile(backupFolder, outputFolder);
    end

    rethrow(ME);
end

end

%% =========================================================
function lines = buildValidationReportLines( ...
    cfg, passed, failures, widthBasedMaxTurns, fullyValidatedMaxTurns, ...
    boardMinAngle, copperMinAngles, ...
    minCopperSpacing, connectionErrors, viaCoincidencePass, ...
    nanInfPass, zeroLengthPass, boardClosurePass, ...
    bodyDimensionPass, tabDimensionPass, overallDimensionPass, ...
    boardSelfIntersectionPass, copperSelfIntersectionPass, ...
    padBoardPass, padPadPass, padCopperPass, ...
    viaToViaPass, viaToBoardPass, viaToPadPass, ...
    viaConnectedPass, viaNonConnectedPass, ...
    copperClearancePass, connectionPass)

passText = @(flag) ternaryText(flag, 'PASS', 'FAIL');

lines = {};
lines{end+1} = 'FPC coil validation report';
lines{end+1} = '========================';
lines{end+1} = sprintf('Design                   : %s', cfg.designName);
lines{end+1} = sprintf('Width-based maximum turns     : %d', ...
    widthBasedMaxTurns);
lines{end+1} = sprintf('Fully validated maximum turns : %d', ...
    fullyValidatedMaxTurns);
lines{end+1} = sprintf('参数检查                 : %s', 'PASS');
lines{end+1} = sprintf('主体尺寸检查             : %s', ...
    passText(bodyDimensionPass));
lines{end+1} = sprintf('尾部尺寸检查             : %s', ...
    passText(tabDimensionPass));
lines{end+1} = sprintf('总尺寸检查               : %s', ...
    passText(overallDimensionPass));
lines{end+1} = sprintf('板框闭合检查             : %s', ...
    passText(boardClosurePass));
lines{end+1} = sprintf('板框自相交检查           : %s', ...
    checkStatus(cfg.enableExactSelfIntersectionCheck, ...
        boardSelfIntersectionPass));

if cfg.enableBoardAngleCheck
    lines{end+1} = sprintf('板框最小内角             : %.3f deg', boardMinAngle);
else
    lines{end+1} = sprintf('板框最小内角             : SKIP');
end

for k = 1:cfg.layerCount
    if cfg.enableCopperAngleCheck
        lines{end+1} = sprintf('L%d最小内角               : %.3f deg', ...
            k, copperMinAngles(k));
    else
        lines{end+1} = sprintf('L%d最小内角               : SKIP', k);
    end
end

lines{end+1} = sprintf('铜线自相交检查           : %s', ...
    checkStatus(cfg.enableExactSelfIntersectionCheck, ...
        copperSelfIntersectionPass));

if cfg.enableCopperClearanceCheck
    lines{end+1} = sprintf('实际最小线距             : %.4f mm', minCopperSpacing);
    lines{end+1} = sprintf('目标最小线距             : %.4f mm', ...
        cfg.traceSpacing - cfg.clearanceTolerance);
    lines{end+1} = sprintf('铜线线距检查             : %s', ...
        passText(copperClearancePass));
else
    lines{end+1} = sprintf('铜线线距检查             : SKIP');
end

lines{end+1} = sprintf('层间连接误差             : %.6f mm', ...
    max(connectionErrors));
lines{end+1} = sprintf('层间连接检查             : %s', ...
    passText(connectionPass));
lines{end+1} = sprintf('过孔重合检查             : %s', ...
    passText(viaCoincidencePass));

if cfg.enablePadClearanceCheck
    lines{end+1} = sprintf('焊盘到板框检查           : %s', ...
        passText(padBoardPass));
    lines{end+1} = sprintf('焊盘到焊盘检查           : %s', ...
        passText(padPadPass));
    lines{end+1} = sprintf('焊盘到铜线检查           : %s', ...
        passText(padCopperPass));
else
    lines{end+1} = '焊盘检查                 : SKIP';
end

if cfg.enableViaClearanceCheck
    lines{end+1} = sprintf('过孔到过孔检查           : %s', ...
        passText(viaToViaPass));
    lines{end+1} = sprintf('过孔到板框检查           : %s', ...
        passText(viaToBoardPass));
    lines{end+1} = sprintf('过孔到焊盘检查           : %s', ...
        passText(viaToPadPass));
    lines{end+1} = sprintf('过孔连接层间距检查       : %s', ...
        passText(viaConnectedPass));

    if viaNonConnectedPass
        viaNonConnectedStatus = 'PASS';
    elseif strcmp(cfg.viaClearanceSeverity, 'error')
        viaNonConnectedStatus = 'FAIL';
    else
        viaNonConnectedStatus = 'WARN';
    end

    lines{end+1} = sprintf('过孔非连接层间距检查     : %s', ...
        viaNonConnectedStatus);

    if ~viaNonConnectedPass
        lines{end+1} = '注意：中层过孔可能穿过非连接铜层，请在EDA中设置反焊盘/禁布区。';
        lines{end+1} = '四层DXF只包含铜层轮廓。';
        lines{end+1} = '真实盲孔、埋孔或反焊盘需要在EDA和厂家工艺中完成。';
    end
else
    lines{end+1} = '过孔检查                 : SKIP';
end
lines{end+1} = sprintf('NaN/Inf检查              : %s', passText(nanInfPass));
lines{end+1} = sprintf('零长度线段检查           : %s', passText(zeroLengthPass));
lines{end+1} = sprintf('最终结论                 : %s', ...
    ternaryText(passed, 'PASS', 'FAIL'));

if ~passed
    lines{end+1} = '失败原因：';
    for i = 1:numel(failures)
        lines{end+1} = sprintf('- %s', failures{i});
    end
end

end

function s = ternaryText(flag, trueText, falseText)

if flag
    s = trueText;
else
    s = falseText;
end

end

function s = checkStatus(enabled, checkPassed)

if ~enabled
    s = 'SKIP';
elseif checkPassed
    s = 'PASS';
else
    s = 'FAIL';
end

end

%% =========================================================
function writeTextFile(filename, lines)

fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid == -1
    error('无法创建文本文件：%s', filename);
end
cleanup = onCleanup(@() fclose(fid));

for i = 1:numel(lines)
    fprintf(fid, '%s\n', lines{i});
end

clear cleanup;

end

%% =========================================================
function [pass, reason] = validateWrittenDxfFile( ...
    filename, expectedVertexCount, expectedEntityCount, ...
    expectedLayerName, isClosed)

pass = false;
reason = '';

if ~exist(filename, 'file')
    reason = '文件不存在';
    return;
end

info = dir(filename);
if info.bytes < 200
    reason = '文件过小';
    return;
end

fid = fopen(filename, 'r', 'n', 'US-ASCII');
if fid == -1
    reason = '无法打开文件';
    return;
end
txt = fread(fid, '*char')';
fclose(fid);

if ~contains(txt, '$INSUNITS') || ~contains(txt, 'EOF')
    reason = '缺少$INSUNITS或EOF';
    return;
end

if contains(txt, 'NaN') || contains(txt, 'Inf')
    reason = 'DXF包含NaN或Inf';
    return;
end

lines = splitlines(txt);

insunitsIdx = find(strcmp(lines, '$INSUNITS'), 1, 'first');
if isempty(insunitsIdx) || numel(lines) < insunitsIdx + 2 || ...
        ~strcmp(lines{insunitsIdx+1}, '70') || ...
        str2double(lines{insunitsIdx+2}) ~= 4
    reason = '$INSUNITS值不是4';
    return;
end

if ~contains(txt, expectedLayerName)
    reason = sprintf('缺少图层名%s', expectedLayerName);
    return;
end

entitiesStart = find(strcmp(lines, 'ENTITIES'), 1, 'first');
if isempty(entitiesStart)
    reason = '缺少ENTITIES';
    return;
end

tailAfterEntities = lines(entitiesStart+1:end);
endsIdx = find(strcmp(tailAfterEntities, 'ENDSEC'), 1, 'first');
endsAfterEntities = entitiesStart + endsIdx;
if isempty(endsAfterEntities) || endsAfterEntities <= entitiesStart
    reason = '缺少ENTITIES后的ENDSEC';
    return;
end

entityLines = lines(entitiesStart+1:endsAfterEntities-1);
vertexCount = sum(strcmp(entityLines, '10'));
yCount = sum(strcmp(entityLines, '20'));

if vertexCount ~= expectedVertexCount || yCount ~= expectedVertexCount
    reason = sprintf('X/Y顶点数不匹配，期望%d，实际X=%d Y=%d', ...
        expectedVertexCount, vertexCount, yCount);
    return;
end

flags = [];
entityVertexSums = 0;
for i = 1:numel(entityLines)-1
    if strcmp(entityLines{i}, '70')
        flags(end+1,1) = str2double(entityLines{i+1}); %#ok<AGROW>
    end
    if strcmp(entityLines{i}, '90')
        entityVertexSums = entityVertexSums + str2double(entityLines{i+1});
    end
end

if numel(flags) ~= expectedEntityCount
    reason = sprintf('LWPOLYLINE数量%d不等于期望值%d', ...
        numel(flags), expectedEntityCount);
    return;
end

if entityVertexSums ~= vertexCount
    reason = '实体声明顶点数与实际坐标数不一致';
    return;
end

if ~isClosed
    entityVertices = parseDxfEntityVertices(entityLines);

    if numel(entityVertices) ~= expectedEntityCount
        reason = '解析出的LWPOLYLINE数量不一致';
        return;
    end

    for k = 1:numel(entityVertices)-1
        if norm(entityVertices{k}(end,:) - entityVertices{k+1}(1,:)) > 1e-9
            reason = 'DXF分段公共端点不一致';
            return;
        end
    end
end

if isClosed
    if ~any(flags == 1)
        reason = '板框缺少闭合标志';
        return;
    end
elseif any(flags == 1)
    reason = '开放多段线出现闭合标志';
    return;
end

pass = true;

end

%% =========================================================
function entities = parseDxfEntityVertices(entityLines)

entities = {};
current = zeros(0,2);
i = 1;

while i <= numel(entityLines)
    if strcmp(entityLines{i}, 'LWPOLYLINE')
        if ~isempty(current)
            entities{end+1} = current; %#ok<AGROW>
        end
        current = zeros(0,2);
        i = i + 1;
        continue;
    end

    if strcmp(entityLines{i}, '10') && i + 3 <= numel(entityLines) && ...
            strcmp(entityLines{i+2}, '20')
        x = str2double(entityLines{i+1});
        y = str2double(entityLines{i+3});

        if ~isnan(x) && ~isnan(y)
            current(end+1,:) = [x, y]; %#ok<AGROW>
        end

        i = i + 4;
        continue;
    end

    i = i + 1;
end

if ~isempty(current)
    entities{end+1} = current;
end

end

%% =========================================================
function writeDxfFile(filename, xy, layerName, isClosed, maxVertices)

fid = fopen(filename, 'w', 'n', 'US-ASCII');
if fid == -1
    error('无法创建DXF：%s', filename);
end
cleanupDXF = onCleanup(@() fclose(fid));

dxfPair(fid, 0, 'SECTION');
dxfPair(fid, 2, 'HEADER');
dxfPair(fid, 9, '$ACADVER');
dxfPair(fid, 1, 'AC1015');
dxfPair(fid, 9, '$INSUNITS');
dxfPair(fid, 70, 4);
dxfPair(fid, 0, 'ENDSEC');

dxfPair(fid, 0, 'SECTION');
dxfPair(fid, 2, 'TABLES');
dxfPair(fid, 0, 'TABLE');
dxfPair(fid, 2, 'LAYER');
dxfPair(fid, 70, 1);
dxfPair(fid, 0, 'LAYER');
dxfPair(fid, 2, layerName);
dxfPair(fid, 70, 0);
dxfPair(fid, 62, 7);
dxfPair(fid, 6, 'CONTINUOUS');
dxfPair(fid, 0, 'ENDTAB');
dxfPair(fid, 0, 'ENDSEC');

dxfPair(fid, 0, 'SECTION');
dxfPair(fid, 2, 'ENTITIES');

if isClosed
    writeClosedPolylineEntity(fid, xy, layerName);
else
    writeOpenPolylineEntities(fid, xy, layerName, maxVertices);
end

dxfPair(fid, 0, 'ENDSEC');
dxfPair(fid, 0, 'EOF');

clear cleanupDXF;

end

%% =========================================================
function writeOpenPolylineEntities(fid, xy, layerName, maxVertices)

firstIndex = 1;

while firstIndex < size(xy,1)
    lastIndex = min(firstIndex + maxVertices - 1, size(xy,1));
    chunkXY = xy(firstIndex:lastIndex,:);
    writeOnePolyline(fid, chunkXY, layerName, false);

    if lastIndex == size(xy,1)
        break;
    end

    firstIndex = lastIndex;
end

end

%% =========================================================
function writeClosedPolylineEntity(fid, xy, layerName)

writeOnePolyline(fid, xy, layerName, true);

end

%% =========================================================
function writeOnePolyline(fid, xy, layerName, isClosed)

dxfPair(fid, 0, 'LWPOLYLINE');
dxfPair(fid, 100, 'AcDbEntity');
dxfPair(fid, 8, layerName);
dxfPair(fid, 100, 'AcDbPolyline');
dxfPair(fid, 90, size(xy,1));
dxfPair(fid, 70, double(isClosed));
dxfPair(fid, 38, 0.0);

values = reshape(xy.', 1, []);
fprintf(fid, '10\n%.9f\n20\n%.9f\n', values);

end

%% =========================================================
function dxfPair(fid, groupCode, value)

persistent integerCodes
if isempty(integerCodes)
    integerCodes = [60:79, 90:99, 170:179, 270:289, ...
        370:389, 400:409, 1060:1071];
end

fprintf(fid, '%d\n', groupCode);

if isnumeric(value)
    if any(groupCode == integerCodes)
        fprintf(fid, '%d\n', round(value));
    else
        fprintf(fid, '%.9f\n', value);
    end
else
    fprintf(fid, '%s\n', char(value));
end

end

%% =========================================================
function writeCoordinateCsv(filename, cfg, d, viaXY)

fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid == -1
    error('无法创建CSV：%s', filename);
end
cleanupCSV = onCleanup(@() fclose(fid));

fprintf(fid, ...
    'name,x_mm,y_mm,from_layer,to_layer,object_type,pad_diameter_mm,drill_diameter_mm,description\n');

fprintf(fid, ...
    'PAD_A,%.6f,%.6f,L1,external,pad,%.3f,0,Top-layer input terminal\n', ...
    d.padA(1), d.padA(2), cfg.padDiameter);

for k = 1:cfg.layerCount-1
    if cfg.layerCount == 2
        objectType = 'through_via';
    else
        objectType = 'adjacent_layer_via';
    end

    fprintf(fid, ...
        'V%d%d,%.6f,%.6f,L%d,L%d,%s,%.3f,%.3f,Layer-to-layer series connection\n', ...
        k, k+1, viaXY(k,1), viaXY(k,2), k, k+1, ...
        objectType, cfg.viaPadDiameter, cfg.viaDrillDiameter);
end

fprintf(fid, ...
    'PAD_B,%.6f,%.6f,L%d,external,pad,%.3f,0,Last-layer output terminal\n', ...
    d.padB(1), d.padB(2), cfg.layerCount, cfg.padDiameter);

clear cleanupCSV;

end

%% =========================================================
function writeDesignSummary( ...
    filename, cfg, d, widthBasedMaxTurns, fullyValidatedMaxTurns, ...
    effectiveTurnsPerLayer, ...
    innerLength, innerWidth, layerXY, copperFileNames, boardFileName, ...
    boardMinAngle, copperMinAngles, minCopperSpacing, ...
    viaXY, connectionErrors)

rhoCopper = cfg.copperResistivity;
crossSection_m2 = (cfg.traceWidth/1000)*(cfg.copperThickness/1000);

layerLength_mm = zeros(cfg.layerCount, 1);
layerRdc = zeros(cfg.layerCount, 1);

for k = 1:cfg.layerCount
    layerLength_mm(k) = calculatePathLength(layerXY{k});
    layerRdc(k) = rhoCopper*(layerLength_mm(k)/1000)/crossSection_m2;
end

totalLength_mm = sum(layerLength_mm);
totalRdc = sum(layerRdc);

lines = {};
lines{end+1} = 'FPC coil design summary';
lines{end+1} = '=======================';
lines{end+1} = sprintf('设计名称                 : %s', cfg.designName);
lines{end+1} = sprintf('层数                     : %d', cfg.layerCount);
lines{end+1} = sprintf('主体长度/宽度            : %.3f / %.3f mm', ...
    cfg.plateLength, cfg.plateWidth);
lines{end+1} = sprintf('主体圆角半径             : %.3f mm', ...
    cfg.plateCornerRadius);
lines{end+1} = sprintf('尾部长度/宽度            : %.3f / %.3f mm', ...
    cfg.tabLength, cfg.tabWidth);
lines{end+1} = sprintf('尾部外圆角/过渡圆角      : %.3f / %.3f mm', ...
    cfg.tabOuterCornerRadius, cfg.tabTransitionRadius);
lines{end+1} = sprintf('含尾部总长度/宽度        : %.3f / %.3f mm', ...
    cfg.plateLength + cfg.tabLength, cfg.plateWidth);
lines{end+1} = sprintf('铜厚                     : %.3f mm', cfg.copperThickness);
lines{end+1} = sprintf('线宽/线距                : %.3f / %.3f mm', ...
    cfg.traceWidth, cfg.traceSpacing);
lines{end+1} = sprintf('中心线节距               : %.3f mm', d.pitch);
lines{end+1} = sprintf('附加节距裕量             : %.3f mm', cfg.pitchMargin);
lines{end+1} = sprintf('实际生成节距             : %.3f mm', d.pitch);
lines{end+1} = sprintf('板边距                   : %.3f mm', cfg.edgeClearance);
lines{end+1} = sprintf('每层完整匝数             : %d', cfg.turnsPerLayer);
lines{end+1} = sprintf('每层有效匝数             : %.6f', effectiveTurnsPerLayer);
lines{end+1} = sprintf('宽度理论最大匝数         : %d', widthBasedMaxTurns);
lines{end+1} = sprintf('全部几何检查最大匝数     : %d', fullyValidatedMaxTurns);
lines{end+1} = sprintf('内圈剩余长度/宽度        : %.3f / %.3f mm', ...
    innerLength, innerWidth);
lines{end+1} = sprintf('目标线距                 : %.3f mm', cfg.traceSpacing);
if isnan(minCopperSpacing)
    lines{end+1} = '实际最小线距             : SKIP';
    lines{end+1} = sprintf('线距容差                 : %.4f mm', cfg.clearanceTolerance);
    lines{end+1} = '线距检查结果             : SKIP';
else
    lines{end+1} = sprintf('实际最小线距             : %.4f mm', minCopperSpacing);
    lines{end+1} = sprintf('线距容差                 : %.4f mm', cfg.clearanceTolerance);
    lines{end+1} = sprintf('线距检查结果             : %s', ...
        ternaryText(minCopperSpacing >= cfg.traceSpacing - cfg.clearanceTolerance, ...
            'PASS', 'FAIL'));
end

if isnan(boardMinAngle)
    lines{end+1} = '板框最小内角             : SKIP';
else
    lines{end+1} = sprintf('板框最小内角             : %.3f deg', boardMinAngle);
end
lines{end+1} = '';

for k = 1:cfg.layerCount
    if isnan(copperMinAngles(k))
        lines{end+1} = sprintf('L%d最小铜线内角          : SKIP', k);
    else
        lines{end+1} = sprintf('L%d最小铜线内角          : %.3f deg', ...
            k, copperMinAngles(k));
    end
    lines{end+1} = sprintf('L%d长度                   : %.3f mm', ...
        k, layerLength_mm(k));
    lines{end+1} = sprintf('L%d估算Rdc                : %.6f Ohm', ...
        k, layerRdc(k));
end

lines{end+1} = sprintf('串联总长度               : %.3f mm', totalLength_mm);
lines{end+1} = sprintf('估算总Rdc                : %.6f Ohm', totalRdc);
lines{end+1} = '';
lines{end+1} = sprintf('PAD_A                     : X=%.6f, Y=%.6f mm', ...
    d.padA(1), d.padA(2));

for k = 1:cfg.layerCount-1
    lines{end+1} = sprintf('V%d%d                       : X=%.6f, Y=%.6f mm', ...
        k, k+1, viaXY(k,1), viaXY(k,2));
end

lines{end+1} = sprintf('PAD_B                     : X=%.6f, Y=%.6f mm', ...
    d.padB(1), d.padB(2));
lines{end+1} = sprintf('层间最大连接误差         : %.6f mm', ...
    max(connectionErrors));
lines{end+1} = '';

for k = 1:cfg.layerCount
    lines{end+1} = sprintf('DXF_L%d                    : %s', ...
        k, copperFileNames{k});
end

lines{end+1} = sprintf('DXF_Board                  : %s', boardFileName);
lines{end+1} = '';
lines{end+1} = '嘉立创EDA导入说明：';
lines{end+1} = sprintf('铜线导入线宽统一设置为 %.3f mm。', cfg.traceWidth);
lines{end+1} = '底层DXF不需要手动镜像。';
lines{end+1} = 'CSV只提供焊盘和过孔坐标，程序不直接生成真实焊盘、钻孔和覆盖膜。';

writeTextFile(filename, lines);

end

%% =========================================================
function writeGenerationStatus( ...
    outputFolder, cfg, widthBasedMaxTurns, fullyValidatedMaxTurns, ...
    minCopperSpacing, ...
    boardMinAngle, minCopperAngle)

lines = {};
lines{end+1} = 'FPC coil generation status';
lines{end+1} = '==========================';
lines{end+1} = sprintf('Status                   : SUCCESS');
lines{end+1} = sprintf('Generated                : %s', ...
    char(datetime('now'), 'yyyy-MM-dd HH:mm:ss'));
lines{end+1} = sprintf('Design                   : %s', cfg.designName);
lines{end+1} = sprintf('LayerCount               : %d', cfg.layerCount);
lines{end+1} = sprintf('TurnsPerLayer            : %d', cfg.turnsPerLayer);
lines{end+1} = sprintf('WidthBasedMaximumTurns   : %d', widthBasedMaxTurns);
lines{end+1} = sprintf('FullyValidatedMaximumTurns: %d', fullyValidatedMaxTurns);
lines{end+1} = sprintf('MinCopperSpacing         : %.4f mm', minCopperSpacing);
lines{end+1} = sprintf('MinBoardAngle            : %.3f deg', boardMinAngle);
lines{end+1} = sprintf('MinCopperAngle           : %.3f deg', minCopperAngle);
lines{end+1} = '本目录属于本次参数成功生成的版本。';

writeTextFile(fullfile(outputFolder, 'generation_status.txt'), lines);

end

%% =========================================================
function len = calculatePathLength(xy)

len = sum(hypot(diff(xy(:,1)), diff(xy(:,2))));

end

%% =========================================================
function fig = plotFullPreview( ...
    cfg, boardXY, layerXY, padA, padB, viaXY)

titleText = sprintf( ...
    '%d-layer FPC coil | body %.0fx%.0f mm | tab %.0fx%.0f mm | %d turns/layer | %.2f/%.2f mm', ...
    cfg.layerCount, cfg.plateLength, cfg.plateWidth, ...
    cfg.tabLength, cfg.tabWidth, cfg.turnsPerLayer, ...
    cfg.traceWidth, cfg.traceSpacing);

fig = plotLayout( ...
    boardXY, layerXY, padA, padB, viaXY, titleText, true, []);

end

%% =========================================================
function fig = plotRightTabPreview( ...
    cfg, boardXY, layerXY, padA, padB, viaXY)

titleText = sprintf( ...
    'Right tab detail | body %.0f mm + tab %.0f mm | %d turns/layer', ...
    cfg.plateLength, cfg.tabLength, cfg.turnsPerLayer);

fig = plotLayout( ...
    boardXY, layerXY, padA, padB, viaXY, titleText, true, ...
    [cfg.plateLength/2 - 8, cfg.plateLength/2 + cfg.tabLength + 2]);

ylim([-cfg.plateWidth/2 - 1, cfg.plateWidth/2 + 1]);

end

%% =========================================================
function fig = plotLayout( ...
    boardXY, layerXY, padA, padB, viaXY, titleText, addLegend, xRange)

if usejava('desktop')
    fig = figure('Name', titleText, 'Color', 'w');
else
    fig = figure('Name', titleText, 'Color', 'w', 'Visible', 'off');
end

hold on;
axis equal;
grid on;
box on;

plot([boardXY(:,1); boardXY(1,1)], ...
     [boardXY(:,2); boardXY(1,2)], ...
     '--', 'LineWidth', 1.0, 'DisplayName', 'Board outline');

for k = 1:numel(layerXY)
    plot(layerXY{k}(:,1), layerXY{k}(:,2), ...
        'LineWidth', 0.8, 'DisplayName', sprintf('L%d', k));
end

plot(padA(1), padA(2), 'o', ...
    'MarkerSize', 7, 'LineWidth', 1.2, 'DisplayName', 'PAD A');

for k = 1:size(viaXY,1)
    plot(viaXY(k,1), viaXY(k,2), 's', ...
        'MarkerSize', 6, 'LineWidth', 1.0, ...
        'DisplayName', sprintf('V%d%d', k, k+1));
end

plot(padB(1), padB(2), 'o', ...
    'MarkerSize', 7, 'LineWidth', 1.2, 'DisplayName', 'PAD B');

xlabel('X / mm');
ylabel('Y / mm');
title(titleText);

if ~isempty(xRange)
    xlim(xRange);
end

if addLegend
    legend('Location', 'bestoutside');
end

end
