function result = fpc_coil_engine(cfg)
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
%   生成几何 -> 全部检查 -> 检查通过 -> 输出DXF/CSV/TXT/SVG。

try

%% =========================================================
% 1. cfg字段完整性和参数合法性检查
%% =========================================================

cfg = fpc_coil_validation('config', cfg);

%% =========================================================
% 2. 派生参数计算
%% =========================================================

d = calculateDerivedParameters(cfg);
limits = fpc_coil_geometry('turn_limits', cfg);
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

analyticalMaxTurns = limits.analyticalMaximum;
widthBasedMaxTurns = limits.width;

% 理论宽度只回答“放不放得下”。正式推荐值还必须逐个候选执行
% 圆弧、角度、线距、自交、焊盘和过孔检查，因此两种上限分开保存。
boardXY = generateSmoothBoardOutline(cfg);
boardXY = removeDuplicatePoints(boardXY, tol);
boardXY = removeZeroLengthSegments(boardXY, tol);
if size(boardXY,1) > 1 && norm(boardXY(end,:)-boardXY(1,:)) < tol
    boardXY(end,:) = [];
end

[fullyValidatedMaxTurns, turnScan, validatedTurnCache] = ...
    calculateFullyValidatedMaximumTurns( ...
    cfg, d, boardXY, analyticalMaxTurns, limits);
if fullyValidatedMaxTurns < 1
    if isempty(turnScan)
        scanReason = '未生成候选结果';
    else
        scanReason = turnScan(end).failureReason;
    end
    % 手动过孔无效：直接以具体失败抛出（不降级为 NoValidTurnCount）
    if ~isempty(strfind(scanReason, '手动坐标')) %#ok<STREMP>
        error('FPC_Coil:ViaPlanningFailed', scanReason);
    end
    error('FPC_Coil:NoValidTurnCount', ...
        '当前层数与制造约束下没有能够通过全部几何检查的匝数。最后失败原因：%s', ...
        scanReason);
end

if cfg.useRecommendedTurns
    % 推荐匝数 = 完整验证上限 - recommendedTurnMargin（默认保留 1 匝裕量）。
    cfg.turnsPerLayer = max(1, fullyValidatedMaxTurns - cfg.recommendedTurnMargin);
end

% 用户显式匝数的多重解析约束检查：宽度、长度、圆角、内圈过孔区域。
if cfg.turnsPerLayer > limits.width
    error(['当前主体宽度%.2f mm无法容纳每层%d匝。\n' ...
        '当前线宽/线距为%.2f/%.2f mm。\n' ...
        '中心至少保留%.2f mm时，宽度允许最大%d匝/层。\n' ...
        '右侧尾部不参与匝数计算。'], ...
        cfg.plateWidth, cfg.turnsPerLayer, ...
        cfg.traceWidth, cfg.traceSpacing, ...
        cfg.minInnerWidth, limits.width);
end
if cfg.turnsPerLayer > limits.length
    error(['长度方向上每层%d匝超过理论上限。\n' ...
        '长度允许最大%d匝/层（中心空白长度至少%.2f mm）。'], ...
        cfg.turnsPerLayer, limits.length, cfg.minInnerLength);
end
if strcmp(cfg.cornerOffsetMode, 'strict_concentric') && ...
        cfg.turnsPerLayer > limits.cornerRadius
    error(['宽度允许 %d 匝，但严格同心圆角仅允许 %d 匝。\n' ...
        '当前线圈外圈圆角半径为 %.3f mm，\n' ...
        '最小允许内圈圆角为 %.3f mm。\n' ...
        '可增大线圈外圈圆角、减小匝数或切换 legacy_clamped 模式。'], ...
        limits.width, limits.cornerRadius, ...
        limits.coilOuterRadius, cfg.minSpiralCornerRadius);
end
if cfg.turnsPerLayer > limits.innerViaRegion
    error(['内圈过孔区域允许最大%d匝/层，当前为%d匝。\n' ...
        '新增层间过孔及逃逸引线占用中心空白空间。'], ...
        limits.innerViaRegion, cfg.turnsPerLayer);
end
if ~limits.tabCapacityPass
    error('右侧尾板可用长度不足，无法容纳全部偶数编号层间过孔；\n建议增大 tabLength、减小过孔数量、改变过孔布局或使用手动坐标。');
end

innerCenterInset = d.outerCenterInset + cfg.turnsPerLayer*d.pitch;
innerLength = cfg.plateLength - 2*innerCenterInset;
innerWidth  = cfg.plateWidth  - 2*innerCenterInset;

if innerLength <= cfg.traceWidth || innerWidth <= cfg.traceWidth
    error('内圈尺寸无效，请减少匝数或增大主体宽度。');
end

%% =========================================================
% 4. 各层螺旋生成
%% =========================================================

if isfinite(validatedTurnCache.turns) && ...
        validatedTurnCache.turns == cfg.turnsPerLayer
    layerXY = validatedTurnCache.layerXY;
    layerPaths = validatedTurnCache.layerPaths;
    vias = validatedTurnCache.vias;
    connectionErrors = validatedTurnCache.connectionErrors;
    escapeArcFallback = validatedTurnCache.escapeArcFallback;
else
    [layerXY, layerPaths, vias, connectionErrors, escapeArcFallback] = ...
        buildLayerGeometry(cfg, d, limits, boardXY);
end
viaXY = vertcat(vias.xy);

%% =========================================================
% 7. 去除重复点和零长度线段
%% =========================================================

for k = 1:cfg.layerCount
    for pathIndex = 1:numel(layerPaths{k})
        [layerPaths{k}{pathIndex}, ~] = ...
            removeDuplicatePoints(layerPaths{k}{pathIndex}, tol);
        [layerPaths{k}{pathIndex}, ~] = ...
            removeZeroLengthSegments(layerPaths{k}{pathIndex}, tol);
    end
    layerXY{k} = layerPaths{k}{1};
end

%% =========================================================
% 8. 闭合角、铜线角度、自交、线距、连接和尺寸检查
%% =========================================================

failures = {};
nanInfPass = true;
zeroLengthPass = true;

% 圆角构造器仍保留回退能力，便于诊断极端参数；生产默认不接受
% 这种回退，避免“数值检查通过但实际仍是90度尖角”。
if cfg.requireSmoothLeadTransitions && escapeArcFallback
    failures{end+1} = ...
        '逃逸引线圆弧生成失败，不允许回退为90度尖角';
end

allPaths = flattenLayerPaths(layerPaths);
if any(~isfinite(boardXY), 'all') || ...
        any(cellfun(@(c) any(~isfinite(c), 'all'), allPaths))
    nanInfPass = false;
    failures{end+1} = '存在NaN或Inf坐标';
end

if anyZeroLengthSegments(boardXY, tol) || ...
        any(cellfun(@(c) anyZeroLengthSegments(c, tol), allPaths))
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
    angleFailures = cell(1, cfg.layerCount);
    angleFailureCount = 0;
    for k = 1:cfg.layerCount
        pathAngles = cellfun(@(path) ...
            minimumOpenPolylineInteriorAngle(path, tol), layerPaths{k});
        copperMinAngles(k) = min(pathAngles);
        if copperMinAngles(k) <= ...
                cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg
            angleFailureCount = angleFailureCount + 1;
            angleFailures(angleFailureCount) = {sprintf( ...
                'L%d最小铜线内角%.3f度，必须严格大于%.3f度', ...
                k, copperMinAngles(k), ...
                cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg)};
        end
    end
    failures = [failures, angleFailures(1:angleFailureCount)];
end

% 精确自相交检查
boardSelfIntersectionPass = true;
copperSelfIntersectionPass = true;
if cfg.enableExactSelfIntersectionCheck
    if checkPolylineSelfIntersectionExact(boardXY, true, cfg)
        boardSelfIntersectionPass = false;
        failures{end+1} = '板框存在自相交';
    end

    pathCounts = cellfun(@numel, layerPaths);
    selfCapacity = sum(pathCounts) + sum(pathCounts.*(pathCounts-1)/2);
    selfFailures = cell(1, selfCapacity);
    selfFailureCount = 0;
    for k = 1:cfg.layerCount
        for pathIndex = 1:numel(layerPaths{k})
            if checkPolylineSelfIntersectionExact( ...
                    layerPaths{k}{pathIndex}, false, cfg)
                copperSelfIntersectionPass = false;
                selfFailureCount = selfFailureCount + 1;
                selfFailures(selfFailureCount) = {sprintf( ...
                    'L%d路径%d存在自相交', k, pathIndex)};
            end
        end
        for pathA = 1:numel(layerPaths{k})-1
            for pathB = pathA+1:numel(layerPaths{k})
                if minimumDistanceBetweenPolylines( ...
                        layerPaths{k}{pathA}, layerPaths{k}{pathB}) <= tol
                    copperSelfIntersectionPass = false;
                    selfFailureCount = selfFailureCount + 1;
                    selfFailures(selfFailureCount) = {sprintf( ...
                        'L%d路径%d与路径%d相交', k, pathA, pathB)};
                end
            end
        end
    end
    failures = [failures, selfFailures(1:selfFailureCount)];
end

% 实际最小线距
minCopperSpacing = NaN;
copperClearancePass = true;
if cfg.enableCopperClearanceCheck
    targetCenterline = cfg.traceWidth + cfg.traceSpacing;
    minIndexSeparation = max(16, ceil(cfg.pointsPerTurn/4));
    minCenterline = Inf;
    clearanceFailures = cell(1, cfg.layerCount);
    clearanceFailureCount = 0;

    for k = 1:cfg.layerCount
        layerMinDist = Inf;
        ok = true;
        for pathIndex = 1:numel(layerPaths{k})
            [pathMinDist, pathOk] = calculateMinimumNonAdjacentDistance( ...
                layerPaths{k}{pathIndex}, targetCenterline, ...
                cfg.clearanceTolerance, minIndexSeparation, tol);
            layerMinDist = min(layerMinDist, pathMinDist);
            ok = ok && pathOk;
        end
        for pathA = 1:numel(layerPaths{k})-1
            for pathB = pathA+1:numel(layerPaths{k})
                pathDistance = minimumDistanceBetweenPolylines( ...
                    layerPaths{k}{pathA}, layerPaths{k}{pathB});
                layerMinDist = min(layerMinDist, pathDistance);
                ok = ok && pathDistance >= ...
                    targetCenterline - cfg.clearanceTolerance;
            end
        end

        if ~ok
            copperClearancePass = false;
            clearanceFailureCount = clearanceFailureCount + 1;
            clearanceFailures(clearanceFailureCount) = {sprintf( ...
                'L%d实际最小线距%.6f mm，低于允许值%.6f mm', ...
                k, layerMinDist - cfg.traceWidth, ...
                cfg.traceSpacing - cfg.clearanceTolerance)};
        end

        minCenterline = min(minCenterline, layerMinDist);
    end
    failures = [failures, clearanceFailures(1:clearanceFailureCount)];

    minCopperSpacing = minCenterline - cfg.traceWidth;
end

% 层间连接检查（连接误差已在生成逃逸引线时检查）
connectionPass = all(connectionErrors <= cfg.connectionTolerance);

viaCoincidencePass = true;
if cfg.layerCount > 2
    coincidenceCapacity = size(viaXY,1)*(size(viaXY,1)-1)/2;
    coincidenceFailures = cell(1, coincidenceCapacity);
    coincidenceFailureCount = 0;
    for i = 1:size(viaXY,1)-1
        for j = i+1:size(viaXY,1)
            if norm(viaXY(i,:)-viaXY(j,:)) < cfg.geometryTolerance
                viaCoincidencePass = false;
                coincidenceFailureCount = coincidenceFailureCount + 1;
                coincidenceFailures(coincidenceFailureCount) = {sprintf( ...
                    '过孔V%d%d与V%d%d坐标重合', i, i+1, j, j+1)};
            end
        end
    end
    failures = [failures, coincidenceFailures(1:coincidenceFailureCount)];
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
        d.padA, d.padB, layerPaths, cfg, tol, padConnectionLength);
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
viaEscapeLengths = zeros(numel(vias), 1);
for viaIndex = 1:numel(vias)
    if isnan(vias(viaIndex).fromLeadLength)
        viaEscapeLengths(viaIndex) = 0;
    else
        % 真实引线长度：取两侧连接引线中的较长者作为验证排除长度
        viaEscapeLengths(viaIndex) = ...
            max(vias(viaIndex).fromLeadLength, vias(viaIndex).toLeadLength);
    end
end
viaEscapeLengths(end) = norm(d.padB - d.outputVia);
viaConnectedClearances = zeros(numel(vias), 1);
viaConnectedClearances(1:2:end) = cfg.viaLandingClearance;
viaConnectedClearances(2:2:cfg.layerCount-1) = cfg.viaOuterLandingClearance;
viaConnectedClearances(end) = cfg.outputViaToCopperClearance;

if cfg.enableViaClearanceCheck
    viaToViaPass = validateViaToVia(viaXY, cfg, tol);
    if ~viaToViaPass
        failures{end+1} = '过孔焊盘之间间距不足';
    end

    viaToBoardPass = validateViaToBoard(vias, boardXY, cfg, tol);
    if ~viaToBoardPass
        failures{end+1} = '过孔焊盘或钻孔距板框过近';
    end

    viaToPadPass = validateViaToPad( ...
        viaXY, d.padA, d.padB, cfg, tol);
    if ~viaToPadPass
        failures{end+1} = '过孔焊盘与PAD_A或PAD_B间距不足';
    end

    [viaConnectedPass, viaNonConnectedPass, viaCopperIssues] = validateViaToCopper( ...
        vias, layerPaths, cfg, tol, viaEscapeLengths, ...
        viaConnectedClearances);

    if ~viaConnectedPass
        failures = [failures, viaCopperIssues];
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
    cfg, passed, failures, limits, fullyValidatedMaxTurns, ...
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

for k = 1:cfg.layerCount
    if k == 1
        suffix = 'top';
        copperLayerNames{k} = 'COPPER_L1_TOP';
    elseif k == cfg.layerCount
        suffix = 'bottom';
        copperLayerNames{k} = sprintf('COPPER_L%d_BOTTOM', k);
    else
        suffix = sprintf('inner%d', k-1);
        copperLayerNames{k} = sprintf('COPPER_L%d_INNER%d', k, k-1);
    end
    copperFileNames{k} = sprintf('%02d_copper_l%d_%s.dxf', k, k, suffix);
end

for k = 1:cfg.layerCount
    layerDxfFolder = fullfile(dxfFolder, sprintf('L%d', k));
    if ~exist(layerDxfFolder, 'dir')
        mkdir(layerDxfFolder);
    end
    dxfFile = fullfile(layerDxfFolder, copperFileNames{k});
    writeDxfFile( ...
        dxfFile, ...
        layerPaths{k}, copperLayerNames{k}, false, ...
        cfg.maxVerticesPerDxfEntity);

    expectedDxfVertices = 0;
    expectedDxfEntities = 0;
    % 单条逻辑路径可能因 DXF 顶点上限被拆成多个实体。记录每条路径
    % 的实体数，回读时只检查路径内部连续性，不连接 L1 的两条独立路径。
    expectedPathEntityCounts = zeros(1, numel(layerPaths{k}));
    for pathIndex = 1:numel(layerPaths{k})
        pathVertexCount = size(layerPaths{k}{pathIndex},1);
        pathEntityCount = max(1, ceil( ...
            (pathVertexCount-1)/(cfg.maxVerticesPerDxfEntity-1)));
        expectedDxfVertices = expectedDxfVertices + ...
            pathVertexCount + max(0, pathEntityCount-1);
        expectedDxfEntities = expectedDxfEntities + pathEntityCount;
        expectedPathEntityCounts(pathIndex) = pathEntityCount;
    end
    if cfg.enableDxfReadbackCheck
        [dxfOk, dxfReason] = validateWrittenDxfFile( ...
            dxfFile, expectedDxfVertices, expectedDxfEntities, ...
            copperLayerNames{k}, false, expectedPathEntityCounts);
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
writeCoordinateCsv(csvFile, cfg, d, vias);
turnScanFile = fullfile(tempOutputFolder, 'reports', '04_turn_scan.csv');
writeTurnScanCsv(turnScanFile, turnScan, fullyValidatedMaxTurns);

%% =========================================================
% 12. 输出设计摘要
%% =========================================================

summaryFile = fullfile(tempOutputFolder, 'reports', '02_design_summary.txt');
writeDesignSummary(summaryFile, cfg, d, limits, ...
    fullyValidatedMaxTurns, ...
    innerLength, innerWidth, ...
    layerPaths, copperFileNames, boardFileName, ...
    boardMinAngle, copperMinAngles, minCopperSpacing, ...
    vias, connectionErrors);

%% =========================================================
% 13. 输出完整预览图
%% =========================================================

previewWritePass = true;

if cfg.enablePreview
    previewFolder = fullfile(tempOutputFolder, 'previews');
    fpc_coil_export('previews', cfg, boardXY, layerPaths, d.padA, d.padB, vias, previewFolder);
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
fprintf('Width-based maximum turns     : %d\n', limits.width);
fprintf('Length-based maximum turns    : %d\n', limits.length);
fprintf('Corner-radius maximum turns   : %d\n', limits.cornerRadius);
fprintf('Analytical maximum turns      : %d\n', limits.analyticalMaximum);
fprintf('Fully validated maximum turns : %d\n', fullyValidatedMaxTurns);
fprintf('Recommended turns (max - %d)  : %d\n', ...
    cfg.recommendedTurnMargin, max(1, fullyValidatedMaxTurns - cfg.recommendedTurnMargin));
fprintf('Limiting factor               : %s\n', ...
    strjoin(limits.limitingFactors, ', '));
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

layers = repmat(struct( ...
    'index', 0, 'name', '', 'paths', {{}}, 'dxfFile', ''), ...
    cfg.layerCount, 1);
for k = 1:cfg.layerCount
    layers(k).index = k;
    layers(k).name = copperLayerNames{k};
    layers(k).paths = layerPaths{k};
    layers(k).dxfFile = fullfile( ...
        outputFolder, 'dxf', sprintf('L%d', k), copperFileNames{k});
end

pads = struct( ...
    'name', {'PAD_A', 'PAD_B'}, ...
    'xy', {d.padA, d.padB}, ...
    'layer', {1, 1}, ...
    'type', {'external_pad', 'external_pad'}, ...
    'diameter', cfg.padDiameter);

layerLengthMm = zeros(cfg.layerCount, 1);
for k = 1:cfg.layerCount
    layerLengthMm(k) = sum(cellfun(@calculatePathLength, layerPaths{k}));
end
totalLengthMm = sum(layerLengthMm);
crossSectionM2 = (cfg.traceWidth/1000)*(cfg.copperThickness/1000);
totalResistanceOhm = cfg.copperResistivity* ...
    (totalLengthMm/1000)/crossSectionM2;

result = struct( ...
    'passed', true, ...
    'layerCount', cfg.layerCount, ...
    'turnsPerLayer', cfg.turnsPerLayer, ...
    'outputFolder', outputFolder, ...
    'boardXY', boardXY, ...
    'layers', layers, ...
    'vias', vias, ...
    'pads', pads, ...
    'coordinateCsv', fullfile(outputFolder, 'reports', ...
        '01_pad_via_coordinates.csv'), ...
    'summaryFile', fullfile(outputFolder, 'reports', ...
        '02_design_summary.txt'), ...
    'validationReport', fullfile(outputFolder, 'reports', ...
        '03_validation_report.txt'), ...
    'turnScanFile', fullfile(outputFolder, 'reports', ...
        '04_turn_scan.csv'), ...
    'recommendedTurns', max(1, fullyValidatedMaxTurns - cfg.recommendedTurnMargin), ...
    'widthBasedMaximumTurns', limits.width, ...
    'lengthBasedMaximumTurns', limits.length, ...
    'cornerRadiusMaximumTurns', limits.cornerRadius, ...
    'innerViaRegionMaximumTurns', limits.innerViaRegion, ...
    'analyticalMaximumTurns', limits.analyticalMaximum, ...
    'fullyValidatedMaximumTurns', fullyValidatedMaxTurns, ...
    'turnLimits', limits, ...
    'minBoardAngle', boardMinAngle, ...
    'minCopperAngle', min(copperMinAngles), ...
    'minCopperSpacing', minCopperSpacing, ...
    'layerLengthMm', layerLengthMm, ...
    'totalLengthMm', totalLengthMm, ...
    'totalResistanceOhm', totalResistanceOhm);

end

%% =========================================================
% 局部函数
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
% 连接相位已统一由 cfg.connectionPhase/connectionSide 控制，
% 不再通过随层数变化的 phaseStep 补偿；每层螺旋均为整数圈。

d.bodyRightX = cfg.plateLength/2;
d.tabTipX = d.bodyRightX + cfg.tabLength;
d.outerRightCenterX = d.bodyRightX - d.outerCenterInset;
d.requiredHalfWidth = abs(cfg.leadYOffset) + ...
    max(cfg.traceWidth/2, cfg.padDiameter/2) + cfg.tabEdgeMargin;

d.padA = [d.tabTipX - cfg.padTipInset, +cfg.leadYOffset];
d.padB = [d.tabTipX - cfg.padTipInset, -cfg.leadYOffset];
if strcmp(cfg.outputViaPlacementMode, 'manual')
    d.outputVia = fpc_coil_geometry('user_to_internal', cfg.manualOutputViaXY, cfg);
else
    d.outputVia = fpc_coil_geometry('auto_output_via', cfg);
end

end

%% =========================================================
function [layerXY, layerPaths, vias, connectionErrors, escapeArcFallback] = ...
    buildLayerGeometry(cfg, d, limits, boardXY)

tol = cfg.geometryTolerance;
escapeArcFallback = false;

% ---- 1) 每层螺旋：整数圈数 + 统一连接相位；相邻层内外锚点重合 ----
rawLayerXY = cell(cfg.layerCount, 1);
for k = 1:cfg.layerCount
    if mod(k,2) == 1
        direction = +1;      % 奇数层：外圈 → 内圈
    else
        direction = -1;      % 偶数层：内圈 → 外圈
    end
    rawLayerXY{k} = fpc_coil_geometry('spiral', cfg, limits, direction);
end

% 内圈锚点（奇层终点 = 偶层起点）与外圈锚点（偶层终点 = 奇层起点）
anchorInner = rawLayerXY{1}(end,:);
anchorOuter = rawLayerXY{1}(1,:);
for k = 2:cfg.layerCount
    if mod(k,2) == 1
        anchorErr = norm(rawLayerXY{k}(1,:) - anchorOuter);
    else
        anchorErr = norm(rawLayerXY{k}(1,:) - anchorInner);
    end
    if anchorErr > cfg.connectionTolerance
        error('L%d连接锚点误差%.6f mm，超过容差%.6f mm', ...
            k, anchorErr, cfg.connectionTolerance);
    end
end

% ---- 2) 过孔规划 ----
outerCenterInset = d.outerCenterInset;
innerCenterInset = outerCenterInset + cfg.turnsPerLayer*d.pitch;
innerLength = cfg.plateLength - 2*innerCenterInset;
innerWidth  = cfg.plateWidth  - 2*innerCenterInset;

innerRadiusStrict = limits.coilOuterRadius - cfg.turnsPerLayer*d.pitch;
if strcmp(cfg.cornerOffsetMode, 'legacy_clamped')
    innerRadius = max(innerRadiusStrict, cfg.minSpiralCornerRadius);
else
    innerRadius = innerRadiusStrict;
end

spiralInfo.innerHalfL = innerLength/2;
spiralInfo.innerHalfW = innerWidth/2;
spiralInfo.innerRadius = innerRadius;
spiralInfo.endPoints = struct('xy', cell(cfg.layerCount, 1));
for k = 1:cfg.layerCount-1
    if mod(k,2) == 1
        spiralInfo.endPoints(k).xy = anchorInner;
        tangent = rawLayerXY{k}(end,:) - rawLayerXY{k}(end-1,:);
        tnorm = norm(tangent);
        if tnorm < tol
            error('L%d末端切线无效。', k);
        end
        spiralInfo.endPoints(k).tangent = tangent/tnorm;
        inwardA = [-tangent(2), tangent(1)]/tnorm;
        inwardB = -inwardA;
        if dot(inwardA, -anchorInner) >= dot(inwardB, -anchorInner)
            spiralInfo.endPoints(k).inwardNormal = inwardA;
        else
            spiralInfo.endPoints(k).inwardNormal = inwardB;
        end
    else
        spiralInfo.endPoints(k).xy = anchorOuter;
        tangent = rawLayerXY{k}(end,:) - rawLayerXY{k}(end-1,:);
        tnorm = norm(tangent);
        if tnorm < tol
            error('L%d末端切线无效。', k);
        end
        spiralInfo.endPoints(k).tangent = tangent/tnorm;
        spiralInfo.endPoints(k).inwardNormal = [0, 0];
    end
end
[vias, viaFailCode, viaFailReason] = fpc_coil_geometry('plan_vias', cfg, spiralInfo);
if ~isempty(viaFailCode)
    error('FPC_Coil:ViaPlanningFailed', viaFailReason);
end

% 补全 vias 字段以保持下游验证/输出兼容
for k = 1:numel(vias)
    vias(k).connectedLayers = [k, k+1];
    if cfg.layerCount == 2
        vias(k).type = 'through_via';
    else
        vias(k).type = 'adjacent_layer_via';
    end
    vias(k).role = 'series_interconnect';
    vias(k).antipadDiameter = 0;
end

% ---- 3) 逃逸引线与焊盘引线（通用平滑布线）----
layerXY = rawLayerXY;

% L1 起点（外圈锚点）→ PAD_A
% 引线以 flipud 前置到 L1 起点：90° 型候选首段 = -t，flipud 后
% 到达 L1 起点方向 = +t，须 = spiralTangentStart，故布线沿 +spiralTangentStart。
[lead, okLead] = routeOrthogonalLeadByPriority( ...
    rawLayerXY{1}, d.padA, 'prepend', ...
    cfg.leadBendRadius, cfg.leadArcPointCount, boardXY, cfg);
escapeArcFallback = escapeArcFallback || ~okLead;
layerXY{1} = [flipud(lead(2:end,:)); layerXY{1}];

% 各层间过孔引线：内圈过孔（奇数编号）走中心空白，尾板过孔（偶数编号）走尾板
% 过孔两侧独立布线（alpha 恒负时圆弧实际首段 = -t）：
%   lead1（append 到 Lk 末端）沿 +tangentEnd 布线，首段实际 = -tangentEnd，
%   与 Lk 末端方向（tangentEnd）形成折角 —— 由 cosDir 候选选择最优近似；
%   lead2（prepend 到 L(k+1) 起点）沿 -tangentEnd 布线再 flipud，
%   flipud 后到达 L(k+1) 起点方向 = +tangentEnd，与螺旋平滑衔接。
for k = 1:cfg.layerCount-1
    if mod(k,2) == 1
        % Inner via (odd k): center region, bend radius viaInnerBendRadius
        bendRadius = cfg.viaInnerBendRadius;
    else
        % Tab via (even k): tab region, bend radius viaOuterBendRadius
        bendRadius = cfg.viaOuterBendRadius;
    end
    [lead1, ok1] = routeOrthogonalLeadByPriority( ...
        rawLayerXY{k}, vias(k).xy, 'append', ...
        bendRadius, cfg.leadArcPointCount, boardXY, cfg);
    [lead2raw, ok2] = routeOrthogonalLeadByPriority( ...
        rawLayerXY{k+1}, vias(k).xy, 'prepend', ...
        bendRadius, cfg.leadArcPointCount, boardXY, cfg);
    okLead = ok1 && ok2;
    escapeArcFallback = escapeArcFallback || ~okLead;
    lead = lead1;
    vias(k).fromLeadPath = lead;
    vias(k).fromLeadLength = calculatePathLength(lead);
    if ~isempty(lead) && size(lead, 2) == 2
        layerXY{k} = [layerXY{k}; lead(2:end,:)];
    end
    leadRev = flipud(lead2raw);
    vias(k).toLeadPath = leadRev;
    vias(k).toLeadLength = calculatePathLength(leadRev);
    % 布线失败（lead 为空）时跳过 prepend：两端停在共享锚点，
    % 连接误差仍为 0，由 escapeArcFallback 标志交给验证阶段裁决。
    if ~isempty(leadRev) && size(leadRev, 2) == 2
        layerXY{k+1} = [leadRev(1:end-1,:); layerXY{k+1}];
    end
end

% 最后一层（偶数层，终点为外圈锚点）→ VOUT
vout = struct( ...
    'name', 'VOUT', 'xy', d.outputVia, ...
    'fromLayer', cfg.layerCount, 'toLayer', 1, ...
    'connectedLayers', [cfg.layerCount, 1], ...
    'type', cfg.outputViaType, 'role', 'output_return', ...
    'drillDiameter', cfg.viaDrillDiameter, ...
    'padDiameter', cfg.viaPadDiameter, ...
    'antipadDiameter', cfg.outputViaAntiPadDiameter, ...
    'placementRegion', 'OUTPUT_TAB', 'placementMode', 'auto', ...
    'fromLeadLength', NaN, 'toLeadLength', NaN, ...
    'fromLeadPath', [], 'toLeadPath', []);
% VOUT lead is append (continues L_last end direction) via the orthogonal router.
[lead, okLead] = routeOrthogonalLeadByPriority( ...
    rawLayerXY{cfg.layerCount}, d.outputVia, 'append', ...
    cfg.leadBendRadius, cfg.leadArcPointCount, boardXY, cfg);
escapeArcFallback = escapeArcFallback || ~okLead;
vout.fromLeadPath = lead;
vout.fromLeadLength = calculatePathLength(lead);
if ~isempty(lead)
    layerXY{cfg.layerCount} = [layerXY{cfg.layerCount}; lead(2:end,:)];
end
vias(end+1) = vout;

% VOUT 将最后一层送回顶层：L1 第二条独立 polyline（VOUT → PAD_B）
topOutputLeadXY = [d.outputVia; d.padB];

% ---- 4) 整理与连接误差 ----
for k = 1:cfg.layerCount
    layerXY{k} = removeDuplicatePoints(layerXY{k}, tol);
    layerXY{k} = removeZeroLengthSegments(layerXY{k}, tol);
end

layerPaths = cell(cfg.layerCount, 1);
for k = 1:cfg.layerCount
    layerPaths{k} = layerXY(k);
end
layerPaths{1}{end+1} = topOutputLeadXY;

connectionErrors = zeros(cfg.layerCount+1, 1);
for k = 1:cfg.layerCount-1
    connectionErrors(k) = norm(layerXY{k}(end,:) - layerXY{k+1}(1,:));
end
connectionErrors(cfg.layerCount) = ...
    norm(layerXY{cfg.layerCount}(end,:) - d.outputVia);
connectionErrors(cfg.layerCount+1) = norm(topOutputLeadXY(1,:) - d.outputVia);

end

%% =========================================================
function [maxTurns, scan, validatedTurnCache] = ...
    calculateFullyValidatedMaximumTurns( ...
    cfg, d, boardXY, analyticalMaxTurns, limits)

maxTurns = 0;
scan = repmat(struct('turns', 0, 'passed', false, ...
    'failureReason', ''), analyticalMaxTurns, 1);
scanCount = 0;
validatedTurnCache = struct();
validatedTurnCache.turns = NaN;
validatedTurnCache.layerXY = cell(0, 1);
validatedTurnCache.layerPaths = cell(0, 1);
validatedTurnCache.vias = struct([]);
validatedTurnCache.connectionErrors = [];
validatedTurnCache.escapeArcFallback = false;
% 从理论上限向下扫描；首个通过者就是当前配置的完整几何上限。
for turns = analyticalMaxTurns:-1:1
    candidateCfg = cfg;
    candidateCfg.turnsPerLayer = turns;
    [candidatePass, failureReason, candidateGeometry] = ...
        isCandidateGeometryValid(candidateCfg, d, boardXY, limits);
    scanCount = scanCount + 1;
    scan(scanCount) = struct( ...
        'turns', turns, 'passed', candidatePass, ...
        'failureReason', failureReason);
    if candidatePass
        scan = scan(1:scanCount);
        maxTurns = turns;
        validatedTurnCache = candidateGeometry;
        validatedTurnCache.turns = turns;
        return;
    end
end

scan = scan(1:scanCount);

end

%% =========================================================
function [pass, reason, geometryCache] = isCandidateGeometryValid(cfg, d, boardXY, limits)

pass = false;
reason = '';
geometryCache = struct();
geometryCache.turns = NaN;
geometryCache.layerXY = cell(0, 1);
geometryCache.layerPaths = cell(0, 1);
geometryCache.vias = struct([]);
geometryCache.connectionErrors = [];
geometryCache.escapeArcFallback = false;
tol = cfg.geometryTolerance;

try
    [layerXY, layerPaths, vias, connectionErrors, escapeArcFallback] = ...
        buildLayerGeometry(cfg, d, limits, boardXY);
    geometryCache.layerXY = layerXY;
    geometryCache.layerPaths = layerPaths;
    geometryCache.vias = vias;
    geometryCache.connectionErrors = connectionErrors;
    geometryCache.escapeArcFallback = escapeArcFallback;
    viaXY = vertcat(vias.xy);
catch ME
    reason = ME.message;
    return;
end

if cfg.requireSmoothLeadTransitions && escapeArcFallback
    reason = '逃逸引线无法生成平滑圆弧，将回退为90度尖角';
    return;
end

candidatePaths = flattenLayerPaths(layerPaths);
if any(~isfinite(boardXY), 'all') || ...
        any(cellfun(@(xy) any(~isfinite(xy), 'all'), candidatePaths)) || ...
        any(cellfun(@(xy) anyZeroLengthSegments(xy, tol), candidatePaths)) || ...
        any(connectionErrors > cfg.connectionTolerance)
    reason = '存在无效坐标、零长度线段或连接误差';
    return;
end

for k = 1:cfg.layerCount
    minIndexSeparation = max(16, ceil(cfg.pointsPerTurn/4));
    for pathIndex = 1:numel(layerPaths{k})
        path = layerPaths{k}{pathIndex};
        % 加上角度容差后再作严格比较，确保90度及数值抖动均不能通过。
        if cfg.enableCopperAngleCheck && ...
                minimumOpenPolylineInteriorAngle(path, tol) <= ...
                cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg
            minAng = minimumOpenPolylineInteriorAngle(path, tol);
            reason = sprintf('L%d路径%d铜线角度不足（最小内角 %.3f°）', ...
                k, pathIndex, minAng);
            return;
        end
        if cfg.enableExactSelfIntersectionCheck && ...
                checkPolylineSelfIntersectionExact(path, false, cfg)
            reason = sprintf('L%d路径%d存在自相交', k, pathIndex);
            return;
        end
        if cfg.enableCopperClearanceCheck
            [~, spacingPass] = calculateMinimumNonAdjacentDistance( ...
                path, cfg.traceWidth + cfg.traceSpacing, ...
                cfg.clearanceTolerance, minIndexSeparation, tol, false);
            if ~spacingPass
                reason = sprintf('L%d路径%d铜线间距不足', k, pathIndex);
                return;
            end
        end
    end
    if cfg.enableCopperClearanceCheck || cfg.enableExactSelfIntersectionCheck
        for pathA = 1:numel(layerPaths{k})-1
            for pathB = pathA+1:numel(layerPaths{k})
                pathDistance = minimumDistanceBetweenPolylines( ...
                    layerPaths{k}{pathA}, layerPaths{k}{pathB});
                if cfg.enableExactSelfIntersectionCheck && pathDistance <= tol
                    reason = sprintf('L%d路径%d与路径%d相交', ...
                        k, pathA, pathB);
                    return;
                end
                if cfg.enableCopperClearanceCheck && pathDistance < ...
                        cfg.traceWidth + cfg.traceSpacing - cfg.clearanceTolerance
                    reason = sprintf('L%d路径%d与路径%d间距不足', ...
                        k, pathA, pathB);
                    return;
                end
            end
        end
    end
end

padConnectionLength = ...
    (d.padA(1) - (d.outerRightCenterX + cfg.leadBendRadius)) + ...
    (pi/2)*cfg.leadBendRadius;
if cfg.enablePadClearanceCheck
    if ~validatePadToBoard(d.padA, d.padB, boardXY, cfg, tol)
        reason = '焊盘未完整位于板框内';
        return;
    end
    if ~validatePadToPad(d.padA, d.padB, cfg, tol)
        reason = '焊盘间距不足';
        return;
    end
    if ~validatePadToCopper( ...
            d.padA, d.padB, layerPaths, cfg, tol, padConnectionLength)
        reason = '焊盘到顶层非连接铜线间距不足';
        return;
    end
end
if cfg.enableViaClearanceCheck
    if ~validateViaToVia(viaXY, cfg, tol)
        reason = '过孔间距不足';
        return;
    end
    if ~validateViaToBoard(vias, boardXY, cfg, tol)
        reason = '过孔到板框间距不足';
        return;
    end
    if ~validateViaToPad(viaXY, d.padA, d.padB, cfg, tol)
        reason = '过孔到焊盘间距不足';
        return;
    end

    viaEscapeLengths = zeros(numel(vias), 1);
    viaEscapeLengths(1:2:end) = cfg.viaLandingLeadLength;
    viaEscapeLengths(2:2:cfg.layerCount-1) = cfg.viaOuterLandingLeadLength;
    viaEscapeLengths(end) = norm(d.padB - d.outputVia);
    viaConnectedClearances = zeros(numel(vias), 1);
    viaConnectedClearances(1:2:end) = cfg.viaLandingClearance;
    viaConnectedClearances(2:2:cfg.layerCount-1) = cfg.viaOuterLandingClearance;
    viaConnectedClearances(end) = cfg.outputViaToCopperClearance;
    [connectedPass, nonConnectedPass] = validateViaToCopper( ...
        vias, layerPaths, cfg, tol, viaEscapeLengths, viaConnectedClearances);

    % 连接层冲突始终致命；非连接层是否允许仅告警由制造策略决定。
    % 候选扫描与正式验证必须使用同一严重级别，否则推荐匝数会漂移。
    nonConnectedAccepted = nonConnectedPass || ...
        strcmp(cfg.viaClearanceSeverity, 'warning');
    pass = connectedPass && nonConnectedAccepted;
    if ~connectedPass
        reason = '过孔与连接层其他铜线间距不足';
    elseif ~nonConnectedPass && ~nonConnectedAccepted
        reason = '通孔与中间非连接铜层反焊盘间距不足';
    else
        reason = '';
    end
else
    pass = true;
end

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
active = zeros(n, 1);
activeCount = 0;
tf = false;
tol2 = tol*tol;

for idx = 1:n
    i = order(idx);
    if activeCount > 0
        retained = active(1:activeCount);
        retained = retained(maxX(retained) >= minX(i) - tol);
        activeCount = numel(retained);
        active(1:activeCount) = retained;
    end

    if activeCount > 0
        j = active(1:activeCount);
        j = j(abs(j - i) > 1);

        if isClosed
            j = j(~((j == 1 & i == n) | (j == n & i == 1)));
        end

        if ~isempty(j)
            j = j(minY(j) <= maxY(i) + tol & maxY(j) >= minY(i) - tol);
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

    activeCount = activeCount + 1;
    active(activeCount) = i;
end

end

%% =========================================================
function [minDist, passed] = calculateMinimumNonAdjacentDistance( ...
    xy, targetDistance, clearanceTolerance, ...
    minIndexSeparation, tol, computeExactMinimum)

if nargin < 6
    computeExactMinimum = true;
end

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
if computeExactMinimum
    best = Inf;
else
    best = threshold;
end
passed = true;

[~, order] = sort(minX);
active = zeros(n, 1);
activeCount = 0;
tol2 = tol*tol;

for idx = 1:n
    i = order(idx);
    if activeCount > 0
        retained = active(1:activeCount);
        retained = retained(maxX(retained) >= minX(i) - best);
        activeCount = numel(retained);
        active(1:activeCount) = retained;
    end

    if activeCount > 0
        j = active(1:activeCount);
        j = j(abs(j - i) > minIndexSeparation);

        if ~isempty(j)
            j = j(maxY(j) >= minY(i) - best & minY(j) <= maxY(i) + best);
        end

        if ~isempty(j)
            shared = ...
                sum((p1(j,:) - p1(i,:)).^2, 2) < tol2 | ...
                sum((p1(j,:) - p2(i,:)).^2, 2) < tol2 | ...
                sum((p2(j,:) - p1(i,:)).^2, 2) < tol2 | ...
                sum((p2(j,:) - p2(i,:)).^2, 2) < tol2;
            j = j(~shared);
        end

        if ~isempty(j)
            dist = minimumSegmentPairDistance(i, j, p1, p2);
            best = min(best, min(dist));

            if best < threshold
                passed = false;
                if ~computeExactMinimum
                    minDist = best;
                    return;
                end
            end
        end
    end

    activeCount = activeCount + 1;
    active(activeCount) = i;
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
function paths = flattenLayerPaths(layerPaths)

paths = {};
for layerIndex = 1:numel(layerPaths)
    paths = horzcat(paths, layerPaths{layerIndex}); %#ok<AGROW>
end

end

%% =========================================================
function minDistance = minimumDistanceBetweenPolylines(pathA, pathB)

if size(pathA,1) < 2 || size(pathB,1) < 2
    minDistance = Inf;
    return;
end

b1 = pathB(1:end-1,:);
b2 = pathB(2:end,:);
bMinX = min(b1(:,1), b2(:,1));
bMaxX = max(b1(:,1), b2(:,1));
bMinY = min(b1(:,2), b2(:,2));
bMaxY = max(b1(:,2), b2(:,2));
minDistance = Inf;

for indexA = 1:size(pathA,1)-1
    a1 = pathA(indexA,:);
    a2 = pathA(indexA+1,:);
    aMinX = min(a1(1), a2(1));
    aMaxX = max(a1(1), a2(1));
    aMinY = min(a1(2), a2(2));
    aMaxY = max(a1(2), a2(2));

    if isinf(minDistance)
        candidate = (1:size(b1,1)).';
    else
        candidate = find( ...
            bMaxX >= aMinX - minDistance & bMinX <= aMaxX + minDistance & ...
            bMaxY >= aMinY - minDistance & bMinY <= aMaxY + minDistance);
    end

    if isempty(candidate)
        continue;
    end

    j = candidate;
    e1 = b1(j,:);
    e2 = b2(j,:);
    db = e2 - e1;
    relative = e1 - a1;
    da = a2 - a1;
    denominator = da(1).*db(:,2) - da(2).*db(:,1);
    numeratorT = relative(:,1).*db(:,2) - relative(:,2).*db(:,1);
    numeratorU = relative(:,1).*da(2) - relative(:,2).*da(1);
    nonParallel = abs(denominator) > 1e-12;
    t = NaN(size(denominator));
    u = NaN(size(denominator));
    t(nonParallel) = numeratorT(nonParallel)./denominator(nonParallel);
    u(nonParallel) = numeratorU(nonParallel)./denominator(nonParallel);
    if any(nonParallel & t >= 0 & t <= 1 & u >= 0 & u <= 1)
        minDistance = 0;
        return;
    end

    distance = min([ ...
        pointToSegmentDistance(a1, e1, e2), ...
        pointToSegmentDistance(a2, e1, e2), ...
        pointToSegmentDistance(e1, a1, a2), ...
        pointToSegmentDistance(e2, a1, a2)], [], 2);
    minDistance = min(minDistance, min(distance));
end

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
    padA, padB, layerPaths, cfg, tol, padConnectionLength)

pass = true;
requiredDistance = cfg.padDiameter/2 + cfg.traceWidth/2 + ...
    cfg.padToCopperClearance;
connectedExcludedLength = padConnectionLength + requiredDistance;

for layerIndex = 1:numel(layerPaths)
    for pathIndex = 1:numel(layerPaths{layerIndex})
        path = layerPaths{layerIndex}{pathIndex};
        if layerIndex == 1 && pathIndex == 1
            dA = minimumDistancePointToPolylineExcludingLength( ...
                padA, path, true, connectedExcludedLength);
        else
            dA = minimumDistancePointToPolyline(padA, path);
        end

        if dA < requiredDistance - tol
            pass = false;
            return;
        end

        if layerIndex == 1 && pathIndex == 2
            dB = Inf;
        else
            dB = minimumDistancePointToPolyline(padB, path);
        end

        if dB < requiredDistance - tol
            pass = false;
            return;
        end
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
function pass = validateViaToBoard(vias, boardXY, cfg, tol)

pass = true;

for k = 1:numel(vias)
    if strcmp(vias(k).role, 'output_return')
        boardClearance = cfg.outputViaToBoardClearance;
    else
        boardClearance = cfg.viaToBoardClearance;
    end
    requiredPadDistance = vias(k).padDiameter/2 + boardClearance;
    requiredDrillDistance = vias(k).drillDiameter/2 + boardClearance;
    [in, on] = inpolygon( ...
        vias(k).xy(1), vias(k).xy(2), boardXY(:,1), boardXY(:,2));
    d = minimumDistancePointToPolyline(vias(k).xy, boardXY);

    if ~(in || on) || d < requiredPadDistance - tol || ...
            d < requiredDrillDistance - tol
        pass = false;
        return;
    end
end

end

%% =========================================================
function [connectedPass, nonConnectedPass, issues] = validateViaToCopper( ...
    vias, layerPaths, cfg, tol, viaEscapeLengths, viaConnectedClearances)

connectedPass = true;
nonConnectedPass = true;
issues = {};
for k = 1:numel(vias)
    connectedRequired = cfg.viaPadDiameter/2 + cfg.traceWidth/2 + ...
        viaConnectedClearances(k);
    connectedExcludedLength = viaEscapeLengths(k) + connectedRequired;

    for layerIndex = 1:numel(layerPaths)
        for pathIndex = 1:numel(layerPaths{layerIndex})
            path = layerPaths{layerIndex}{pathIndex};
            isFromPath = layerIndex == vias(k).fromLayer && pathIndex == 1;
            isToPath = layerIndex == vias(k).toLayer && pathIndex == 1;
            if strcmp(vias(k).role, 'output_return')
                isToPath = layerIndex == 1 && pathIndex == 2;
            end

            if isFromPath
                d = minimumDistancePointToPolylineExcludingLength( ...
                    vias(k).xy, path, false, connectedExcludedLength);
                if d < connectedRequired - tol
                    connectedPass = false;
                    issues{end+1} = sprintf( ...
                        ['%s与连接层L%d路径%d间距%.6f mm不足%.6f mm' ...
                        '（排除长度%.6f mm）'], ...
                        vias(k).name, layerIndex, pathIndex, d, ...
                        connectedRequired, connectedExcludedLength); %#ok<AGROW>
                end
            elseif isToPath
                if strcmp(vias(k).role, 'output_return')
                    d = Inf;
                else
                    d = minimumDistancePointToPolylineExcludingLength( ...
                        vias(k).xy, path, true, connectedExcludedLength);
                end
                if d < connectedRequired - tol
                    connectedPass = false;
                    issues{end+1} = sprintf( ...
                        ['%s与连接层L%d路径%d间距%.6f mm不足%.6f mm' ...
                        '（排除长度%.6f mm）'], ...
                        vias(k).name, layerIndex, pathIndex, d, ...
                        connectedRequired, connectedExcludedLength); %#ok<AGROW>
                end
            else
                checksThisLayer = strcmp(vias(k).type, 'through_via') || ...
                    ismember(layerIndex, vias(k).connectedLayers);
                if checksThisLayer
                    genericRequired = vias(k).padDiameter/2 + ...
                        cfg.traceWidth/2 + cfg.viaToCopperClearance;
                    % VOUT 是贯穿所有层的通孔。对中间非连接层，既要满足
                    % 通用过孔净距，也要完整容纳配置的反焊盘开窗。
                    if strcmp(vias(k).role, 'output_return') && ...
                            strcmp(vias(k).type, 'through_via')
                        antipadRequired = vias(k).antipadDiameter/2 + ...
                            cfg.traceWidth/2;
                        otherRequired = max(genericRequired, antipadRequired);
                    else
                        otherRequired = genericRequired;
                    end
                    d = minimumDistancePointToPolyline(vias(k).xy, path);
                    if d < otherRequired - tol
                        nonConnectedPass = false;
                    end
                end
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
    cfg, passed, failures, limits, fullyValidatedMaxTurns, ...
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
lines{end+1} = sprintf('用户坐标原点             : %s', cfg.coordinateOrigin);
lines{end+1} = sprintf('过孔放置模式             : %s', cfg.viaPlacementMode);
lines{end+1} = sprintf('线圈外圈圆角模式         : %s', cfg.coilOuterCornerRadiusMode);
lines{end+1} = sprintf('实际线圈外圈圆角半径     : %.3f mm', limits.coilOuterRadius);
lines{end+1} = sprintf('圆角偏移模式             : %s', cfg.cornerOffsetMode);
lines{end+1} = sprintf('Width-based maximum turns     : %d', ...
    limits.width);
lines{end+1} = sprintf('Length-based maximum turns    : %d', ...
    limits.length);
lines{end+1} = sprintf('Corner-radius maximum turns   : %d', ...
    limits.cornerRadius);
lines{end+1} = sprintf('Inner-via-region maximum turns: %d', ...
    limits.innerViaRegion);
lines{end+1} = sprintf('Tab via capacity check        : %s', ...
    ternaryText(limits.tabCapacityPass, 'PASS', 'FAIL'));
lines{end+1} = sprintf('Analytical maximum turns      : %d', ...
    limits.analyticalMaximum);
lines{end+1} = sprintf('Fully validated maximum turns : %d', ...
    fullyValidatedMaxTurns);
lines{end+1} = sprintf('Recommended turns             : %d', ...
    max(1, fullyValidatedMaxTurns - cfg.recommendedTurnMargin));
lines{end+1} = sprintf('Limiting factor               : %s', ...
    strjoin(limits.limitingFactors, ', '));
lines{end+1} = sprintf('内圈过孔排列方式         : %s', cfg.innerViaLayout);
lines{end+1} = sprintf('尾板过孔排列方式         : %s', cfg.outerViaLayout);
lines{end+1} = sprintf('是否发生圆角半径截断     : %s', ...
    ternaryText(limits.cornerRadius < floor((limits.coilOuterRadius - cfg.minSpiralCornerRadius)/limits.pitch) ...
        && strcmp(cfg.cornerOffsetMode, 'legacy_clamped'), '是', '否'));
lines{end+1} = sprintf('Output topology                : L%d -> VOUT -> L1 -> PAD_B', ...
    cfg.layerCount);
lines{end+1} = sprintf('VOUT type / antipad            : %s / %.3f mm', ...
    cfg.outputViaType, cfg.outputViaAntiPadDiameter);
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

angleLines = cell(1, cfg.layerCount);
for k = 1:cfg.layerCount
    if cfg.enableCopperAngleCheck
        angleLines{k} = sprintf('L%d最小内角               : %.3f deg', ...
            k, copperMinAngles(k));
    else
        angleLines{k} = sprintf('L%d最小内角               : SKIP', k);
    end
end
lines = [lines, angleLines];

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
    failureLines = cell(1, numel(failures));
    for i = 1:numel(failures)
        failureLines{i} = sprintf('- %s', failures{i});
    end
    lines = [lines, failureLines];
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
    expectedLayerName, isClosed, expectedPathEntityCounts)

if nargin < 6
    expectedPathEntityCounts = expectedEntityCount;
end

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
entityNumbers = str2double(entityLines);
% '10'/'20' 统计需排除 '90' 声明值行（块顶点数可能恰为 10，会被误计为坐标）
previousIsVertexCount = [false; strcmp(entityLines(1:end-1), '90')];
vertexCount = nnz(strcmp(entityLines, '10') & ~previousIsVertexCount);
yCount = nnz(strcmp(entityLines, '20') & ~previousIsVertexCount);

if vertexCount ~= expectedVertexCount || yCount ~= expectedVertexCount
    reason = sprintf('X/Y顶点数不匹配，期望%d，实际X=%d Y=%d', ...
        expectedVertexCount, vertexCount, yCount);
    return;
end

flagCodeIndices = find(strcmp(entityLines(1:end-1), '70'));
flags = entityNumbers(flagCodeIndices + 1);
vertexDeclarationIndices = find(strcmp(entityLines(1:end-1), '90'));
entityVertexSums = sum(entityNumbers(vertexDeclarationIndices + 1));

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
    entityVertices = parseDxfEntityVertices(entityLines, entityNumbers);

    if numel(entityVertices) ~= expectedEntityCount
        reason = '解析出的LWPOLYLINE数量不一致';
        return;
    end

    % 只在同一逻辑 polyline 的分段之间检查公共端点；跨路径不应连续。
    firstEntity = 1;
    for pathIndex = 1:numel(expectedPathEntityCounts)
        lastEntity = firstEntity + expectedPathEntityCounts(pathIndex) - 1;
        for k = firstEntity:lastEntity-1
            if norm(entityVertices{k}(end,:) - ...
                    entityVertices{k+1}(1,:)) > 1e-9
                reason = sprintf('DXF路径%d分段公共端点不一致', pathIndex);
                return;
            end
        end
        firstEntity = lastEntity + 1;
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
function entities = parseDxfEntityVertices(entityLines, entityNumbers)

entityStarts = find(strcmp(entityLines, 'LWPOLYLINE'));
entityEnds = [entityStarts(2:end) - 1; numel(entityLines)];

if numel(entityLines) >= 4
    candidateStarts = (1:numel(entityLines) - 3).';
    coordinateStarts = candidateStarts( ...
        strcmp(entityLines(candidateStarts), '10') & ...
        strcmp(entityLines(candidateStarts + 2), '20'));
else
    coordinateStarts = zeros(0, 1);
end

xy = [entityNumbers(coordinateStarts + 1), entityNumbers(coordinateStarts + 3)];
finiteMask = ~isnan(xy(:,1)) & ~isnan(xy(:,2));
xy = xy(finiteMask, :);
coordinateStarts = coordinateStarts(finiteMask);

entities = cell(numel(entityStarts), 1);
entityCount = 0;
for k = 1:numel(entityStarts)
    entityMask = coordinateStarts > entityStarts(k) & ...
        coordinateStarts <= entityEnds(k);
    if any(entityMask)
        entityCount = entityCount + 1;
        entities{entityCount} = xy(entityMask, :);
    end
end
entities = entities(1:entityCount);

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
    if ~iscell(xy)
        xy = {xy};
    end
    for pathIndex = 1:numel(xy)
        writeOpenPolylineEntities( ...
            fid, xy{pathIndex}, layerName, maxVertices);
    end
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
function writeTurnScanCsv(filename, scan, fullyValidatedMaxTurns)

fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid == -1
    error('无法创建匝数扫描CSV：%s', filename);
end
cleanupCSV = onCleanup(@() fclose(fid));

fprintf(fid, ['turns,passed,is_fully_validated_maximum,failure_code,', ...
    'failure_reason\n']);
for index = 1:numel(scan)
    reason = strrep(scan(index).failureReason, '"', '""');
    if isfield(scan(index), 'failureCode')
        code = scan(index).failureCode;
    else
        code = classifyFailureCode(reason);
    end
    fprintf(fid, '%d,%d,%d,"%s","%s"\n', ...
        scan(index).turns, scan(index).passed, ...
        scan(index).turns == fullyValidatedMaxTurns, code, reason);
end

clear cleanupCSV;

end

%% =========================================================
function code = classifyFailureCode(reason)
% 从简洁失败原因中识别错误分类代码（任务十二要求）。
if isempty(reason)
    code = '';
elseif contains(reason, '内圈空白')
    code = 'INNER_VIA_CAPACITY';
elseif contains(reason, '尾板')
    code = 'TAB_VIA_CAPACITY';
elseif contains(reason, '手动')
    code = 'MANUAL_VIA_INVALID';
elseif contains(reason, '平滑圆弧') || contains(reason, '转向角') || ...
        contains(reason, '圆弧')
    code = 'ROUTING_ARC_FAILURE';
elseif contains(reason, '自相交')
    code = 'COPPER_SELF_INTERSECTION';
elseif contains(reason, '间距不足') || contains(reason, '线距')
    code = 'COPPER_SPACING';
else
    code = 'UNKNOWN';
end
end

%% =========================================================
function writeCoordinateCsv(filename, cfg, d, vias)

fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid == -1
    error('无法创建CSV：%s', filename);
end
cleanupCSV = onCleanup(@() fclose(fid));

fprintf(fid, ...
    ['name,x_body_lower_left_mm,y_body_lower_left_mm,', ...
    'x_internal_center_mm,y_internal_center_mm,', ...
    'from_layer,to_layer,object_type,placement_region,placement_mode,', ...
    'pad_diameter_mm,drill_diameter_mm,annular_ring_mm,', ...
    'antipad_diameter_mm,description\n']);

% 说明：x/y_body_lower_left_mm 以主体左下角为原点（用户坐标系）；
% x/y_internal_center_mm 以主体中心为原点（几何内部坐标系）。
padAUser = fpc_coil_geometry('internal_to_user', d.padA, cfg);
fprintf(fid, ...
    'PAD_A,%.6f,%.6f,%.6f,%.6f,L1,external,pad,EXTERNAL_PAD,fixed,%.3f,0,0,0,Top-layer input terminal\n', ...
    padAUser(1), padAUser(2), d.padA(1), d.padA(2), cfg.padDiameter);

for k = 1:numel(vias)
    annularRing = (vias(k).padDiameter - vias(k).drillDiameter)/2;
    xyUser = fpc_coil_geometry('internal_to_user', vias(k).xy, cfg);
    if isfield(vias(k), 'placementRegion')
        region = vias(k).placementRegion;
        mode = vias(k).placementMode;
    else
        region = '';
        mode = '';
    end
    if isempty(region)
        region = 'RIGHT_TAB';
    end
    if isempty(mode)
        mode = cfg.viaPlacementMode;
    end
    fprintf(fid, ...
        '%s,%.6f,%.6f,%.6f,%.6f,L%d,L%d,%s,%s,%s,%.3f,%.3f,%.3f,%.3f,%s\n', ...
        vias(k).name, xyUser(1), xyUser(2), vias(k).xy(1), vias(k).xy(2), ...
        vias(k).fromLayer, vias(k).toLayer, vias(k).type, ...
        region, mode, ...
        vias(k).padDiameter, vias(k).drillDiameter, annularRing, ...
        vias(k).antipadDiameter, vias(k).role);
end

padBUser = fpc_coil_geometry('internal_to_user', d.padB, cfg);
fprintf(fid, ...
    'PAD_B,%.6f,%.6f,%.6f,%.6f,L1,external,pad,EXTERNAL_PAD,fixed,%.3f,0,0,0,Top-layer output terminal\n', ...
    padBUser(1), padBUser(2), d.padB(1), d.padB(2), cfg.padDiameter);

clear cleanupCSV;

end

%% =========================================================
function writeDesignSummary( ...
    filename, cfg, d, limits, fullyValidatedMaxTurns, ...
    innerLength, innerWidth, layerPaths, copperFileNames, boardFileName, ...
    boardMinAngle, copperMinAngles, minCopperSpacing, ...
    vias, connectionErrors)

rhoCopper = cfg.copperResistivity;
crossSection_m2 = (cfg.traceWidth/1000)*(cfg.copperThickness/1000);

layerLength_mm = zeros(cfg.layerCount, 1);
layerRdc = zeros(cfg.layerCount, 1);

for k = 1:cfg.layerCount
    layerLength_mm(k) = sum(cellfun( ...
        @calculatePathLength, layerPaths{k}));
    layerRdc(k) = rhoCopper*(layerLength_mm(k)/1000)/crossSection_m2;
end

totalLength_mm = sum(layerLength_mm);
totalRdc = sum(layerRdc);

lines = {};
lines{end+1} = 'FPC coil design summary';
lines{end+1} = '=======================';
lines{end+1} = sprintf('Recommended turns (max - %d) : %d', ...
    cfg.recommendedTurnMargin, max(1, fullyValidatedMaxTurns - cfg.recommendedTurnMargin));
lines{end+1} = sprintf('Output topology             : L%d -> VOUT -> L1 -> PAD_B', ...
    cfg.layerCount);
lines{end+1} = sprintf('VOUT type / antipad         : %s / %.3f mm', ...
    cfg.outputViaType, cfg.outputViaAntiPadDiameter);
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
lines{end+1} = sprintf('用户坐标原点             : %s', cfg.coordinateOrigin);
lines{end+1} = sprintf('过孔放置模式             : %s', cfg.viaPlacementMode);
lines{end+1} = sprintf('线圈外圈圆角模式         : %s', cfg.coilOuterCornerRadiusMode);
lines{end+1} = sprintf('实际线圈外圈圆角半径     : %.3f mm', limits.coilOuterRadius);
lines{end+1} = sprintf('圆角偏移模式             : %s', cfg.cornerOffsetMode);
lines{end+1} = sprintf('宽度理论最大匝数         : %d', limits.width);
lines{end+1} = sprintf('长度理论最大匝数         : %d', limits.length);
lines{end+1} = sprintf('圆角理论最大匝数         : %d', limits.cornerRadius);
lines{end+1} = sprintf('内圈过孔区域最大匝数     : %d', limits.innerViaRegion);
lines{end+1} = sprintf('尾板过孔容量检查         : %s', ...
    ternaryText(limits.tabCapacityPass, 'PASS', 'FAIL'));
lines{end+1} = sprintf('综合理论上限             : %d', limits.analyticalMaximum);
lines{end+1} = sprintf('全部几何检查最大匝数     : %d', fullyValidatedMaxTurns);
lines{end+1} = sprintf('最终限制因素             : %s', ...
    strjoin(limits.limitingFactors, ', '));
lines{end+1} = sprintf('内圈过孔排列方式         : %s', cfg.innerViaLayout);
lines{end+1} = sprintf('尾板过孔排列方式         : %s', cfg.outerViaLayout);
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

layerLines = cell(3, cfg.layerCount);
for k = 1:cfg.layerCount
    if isnan(copperMinAngles(k))
        layerLines{1, k} = sprintf('L%d最小铜线内角          : SKIP', k);
    else
        layerLines{1, k} = sprintf('L%d最小铜线内角          : %.3f deg', ...
            k, copperMinAngles(k));
    end
    layerLines{2, k} = sprintf('L%d长度                   : %.3f mm', ...
        k, layerLength_mm(k));
    layerLines{3, k} = sprintf('L%d估算Rdc                : %.6f Ohm', ...
        k, layerRdc(k));
end
lines = [lines, reshape(layerLines, 1, [])];

lines{end+1} = sprintf('串联总长度               : %.3f mm', totalLength_mm);
lines{end+1} = sprintf('估算总Rdc                : %.6f Ohm', totalRdc);
lines{end+1} = '';
lines{end+1} = sprintf('PAD_A (L1)                : X=%.6f, Y=%.6f mm', ...
    d.padA(1), d.padA(2));

viaLines = cell(1, numel(vias));
for k = 1:numel(vias)
    viaLines{k} = sprintf( ...
        '%-10s : X=%.6f, Y=%.6f mm, L%d -> L%d, %s, antipad %.3f mm', ...
        vias(k).name, vias(k).xy(1), vias(k).xy(2), ...
        vias(k).fromLayer, vias(k).toLayer, vias(k).type, ...
        vias(k).antipadDiameter);
end
lines = [lines, viaLines];

lines{end+1} = sprintf('PAD_B (L1)                : X=%.6f, Y=%.6f mm', ...
    d.padB(1), d.padB(2));
lines{end+1} = sprintf('Output topology           : L%d -> VOUT -> L1 -> PAD_B', ...
    cfg.layerCount);
lines{end+1} = sprintf('层间最大连接误差         : %.6f mm', ...
    max(connectionErrors));
lines{end+1} = '';

dxfLines = cell(1, cfg.layerCount);
for k = 1:cfg.layerCount
    dxfLines{k} = sprintf('DXF_L%d                    : %s', ...
        k, copperFileNames{k});
end
lines = [lines, dxfLines];

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
lines{end+1} = sprintf('RecommendedTurns         : %d', ...
    max(1, fullyValidatedMaxTurns - cfg.recommendedTurnMargin));
lines{end+1} = sprintf('OutputTopology           : L%d -> VOUT -> L1 -> PAD_B', ...
    cfg.layerCount);
lines{end+1} = sprintf('OutputViaType            : %s', cfg.outputViaType);
lines{end+1} = sprintf('MinCopperSpacing         : %.4f mm', minCopperSpacing);
lines{end+1} = sprintf('MinBoardAngle            : %.3f deg', boardMinAngle);
lines{end+1} = sprintf('MinCopperAngle           : %.3f deg', minCopperAngle);
lines{end+1} = '本目录属于本次参数成功生成的版本。';

writeTextFile(fullfile(outputFolder, 'generation_status.txt'), lines);

end


%% =========================================================
function [path, ok] = routeLeadByPriority( ...
    basePath, endPt, mode, bendRadius, arcPointCount, boardXY, cfg)
% Priority lead routing: straight, then one fillet + straight, then two-leg
% dogleg; ties at the same priority use the shorter total length.
tol = cfg.geometryTolerance;
path = [];
ok = false;

if strcmp(mode, 'append')
    startPt = basePath(end,:);
    startTangent = basePath(end,:) - basePath(end-1,:);
else
    startPt = basePath(1,:);
    startTangent = -(basePath(2,:) - basePath(1,:));
end

direct = [startPt; endPt];
if candidateCompliant(basePath, direct, mode, boardXY, cfg)
    path = direct;
    ok = true;
    return;
end

[filletPath, filletOk] = fpc_coil_geometry('smooth_lead',  ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, tol);
if filletOk && candidateCompliant(basePath, filletPath, mode, boardXY, cfg)
    path = filletPath;
    ok = true;
    return;
end

waypoints = {[endPt(1), startPt(2)], [startPt(1), endPt(2)]};
bestLen = Inf;
bestPath = [];
for wpIndex = 1:numel(waypoints)
    wp = waypoints{wpIndex};
    [cand, candOk] = routeViaWaypoint( ...
        startPt, startTangent, wp, endPt, bendRadius, arcPointCount, tol);
    if ~candOk
        continue;
    end
    if ~candidateCompliant(basePath, cand, mode, boardXY, cfg)
        continue;
    end
    candLen = calculatePathLength(cand);
    if candLen < bestLen - tol
        bestLen = candLen;
        bestPath = cand;
    end
end
if ~isempty(bestPath)
    path = bestPath;
    ok = true;
end

end

function [path, ok] = routeOrthogonalLeadByPriority( ...
    basePath, endPt, mode, bendRadius, arcPointCount, boardXY, cfg)
% Orthogonal lead routing: axial straight, tangent arc plus axial
% straight, and two-arc orthogonal dogleg candidates; every candidate is
% judged by candidateCompliant in priority order.
path = [];
ok = false;

if strcmp(mode, 'append')
    startPt = basePath(end,:);
    startTangent = basePath(end,:) - basePath(end-1,:);
else
    startPt = basePath(1,:);
    startTangent = -(basePath(2,:) - basePath(1,:));
end

[candidates, priorities] = buildOrthogonalViaCandidates( ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, cfg.geometryTolerance);

for priority = 1:3
    candidateIndices = find(priorities == priority);
    if isempty(candidateIndices)
        continue;
    end
    lengths = zeros(numel(candidateIndices), 1);
    for k = 1:numel(candidateIndices)
        lengths(k) = calculatePathLength(candidates{candidateIndices(k)});
    end
    order = sortrows([lengths, candidateIndices(:)], [1, 2]);
    for k = 1:size(order, 1)
        cand = candidates{order(k, 2)};
        if candidateCompliant(basePath, cand, mode, boardXY, cfg)
            path = cand;
            ok = true;
            return;
        end
    end
end

if ~cfg.requireSmoothLeadTransitions
    [path, ok] = routeLeadByPriority( ...
        basePath, endPt, mode, bendRadius, arcPointCount, boardXY, cfg);
end

end

function [candidates, priorities] = buildOrthogonalViaCandidates( ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, tol)

candidates = {};
tangentNorm = norm(startTangent);
if tangentNorm <= tol
    return;
end
tu = startTangent / tangentNorm;
thetaStart = atan2(tu(2), tu(1));
axes = [1, 0; 0, 1; -1, 0; 0, -1];
candidateBuffer = cell(1, 29);
priorityBuffer = zeros(1, 29);
candidateCount = 0;

% 1) Axial straight line only.
if abs(endPt(1) - startPt(1)) <= tol || abs(endPt(2) - startPt(2)) <= tol
    candidateCount = candidateCount + 1;
    candidateBuffer{candidateCount} = [startPt; endPt];
    priorityBuffer(candidateCount) = 1;
end

% 2) Single tangent arc plus axial straight segment.
for axisIndex = 1:size(axes, 1)
    axis = axes(axisIndex, :);
    thetaAxis = atan2(axis(2), axis(1));
    sweep = atan2(sin(thetaAxis - thetaStart), cos(thetaAxis - thetaStart));
    if abs(sweep) >= pi - 1e-9
        continue;
    end
    if abs(sweep) <= 1e-12
        continue;
    end
    turnSign = sign(sweep);
    leftNormal = [-tu(2); tu(1)];
    radialUnit = -turnSign * leftNormal;
    rot = [cos(sweep), -sin(sweep); sin(sweep), cos(sweep)];
    offset = (rot - eye(2)) * radialUnit;
    if abs(axis(1)) == 1
        if abs(offset(2)) <= tol
            continue;
        end
        radius = (endPt(2) - startPt(2)) / offset(2);
    else
        if abs(offset(1)) <= tol
            continue;
        end
        radius = (endPt(1) - startPt(1)) / offset(1);
    end
    if radius <= tol || radius > bendRadius + tol
        continue;
    end
    arcEnd = startPt + radius * offset.';
    remaining = endPt - arcEnd;
    if abs(axis(1) * remaining(2) - axis(2) * remaining(1)) > tol
        continue;
    end
    if dot(axis, remaining) < -tol
        continue;
    end
    [arc, arcOk] = buildTangentArc( ...
        startPt, startTangent, axis, radius, arcPointCount);
    if ~arcOk
        continue;
    end
    candidateCount = candidateCount + 1;
    candidateBuffer{candidateCount} = appendPathPoints(arc, endPt, tol);
    priorityBuffer(candidateCount) = 2;
end

% 3) Two-arc orthogonal dogleg.
firstRadii = [bendRadius, bendRadius / 2, bendRadius / 4];
for radiusIndex = 1:numel(firstRadii)
    firstRadius = firstRadii(radiusIndex);
    if firstRadius <= tol
        continue;
    end
    for axisIndex = 1:size(axes, 1)
        d1 = axes(axisIndex, :);
        thetaAxis = atan2(d1(2), d1(1));
        sweep = atan2(sin(thetaAxis - thetaStart), cos(thetaAxis - thetaStart));
        if abs(sweep) >= pi - 1e-9
            continue;
        end
        turnSign = sign(sweep);
        leftNormal = [-tu(2); tu(1)];
        radialUnit = -turnSign * leftNormal;
        rot = [cos(sweep), -sin(sweep); sin(sweep), cos(sweep)];
        offset = (rot - eye(2)) * radialUnit;
        firstEnd = startPt + firstRadius * offset.';
        perps = [[-d1(2), d1(1)]; [d1(2), -d1(1)]];
        for perpIndex = 1:size(perps, 1)
            d2 = perps(perpIndex, :);
            s = dot(endPt - firstEnd, d1);
            q = dot(endPt - firstEnd, d2);
            if s < -tol || q < -tol
                continue;
            end
            cornerRadius = min([bendRadius, s, q]);
            if cornerRadius <= tol
                continue;
            end
            t1 = firstEnd + (s - cornerRadius) * d1;
            t2 = endPt - (q - cornerRadius) * d2;
            [arc1, arc1Ok] = buildTangentArc( ...
                startPt, startTangent, d1, firstRadius, arcPointCount);
            if ~arc1Ok
                continue;
            end
            [arc2, arc2Ok] = buildTangentArc( ...
                t1, d1, d2, cornerRadius, arcPointCount);
            if ~arc2Ok
                continue;
            end
            if norm(arc2(end,:) - t2) > 10 * tol
                continue;
            end
            candidateCount = candidateCount + 1;
            candidateBuffer{candidateCount} = appendPathPoints( ...
                appendPathPoints(appendPathPoints(arc1, t1, tol), arc2, tol), ...
                endPt, tol);
            priorityBuffer(candidateCount) = 3;
        end
    end
end

candidates = candidateBuffer(1:candidateCount);
priorities = priorityBuffer(1:candidateCount);

end

function [arc, ok] = buildTangentArc( ...
    startPt, startTangent, endTangent, radius, arcPointCount)

ok = false;
arc = [];
tangentNorm = norm(startTangent);
endNorm = norm(endTangent);
if tangentNorm <= eps || endNorm <= eps || radius <= eps
    return;
end
tu = startTangent / tangentNorm;
eu = endTangent / endNorm;
thetaStart = atan2(tu(2), tu(1));
thetaEnd = atan2(eu(2), eu(1));
sweep = atan2(sin(thetaEnd - thetaStart), cos(thetaEnd - thetaStart));
if abs(sweep) >= pi - 1e-9
    return;
end
if abs(sweep) <= 1e-12
    arc = startPt;
    ok = true;
    return;
end
turnSign = sign(sweep);
leftNormal = [-tu(2); tu(1)];
radialUnit = -turnSign * leftNormal;
phiStart = atan2(radialUnit(2), radialUnit(1));
center = startPt - radius * radialUnit.';
nArc = max(2, ceil(arcPointCount * abs(sweep) / (pi / 2)) + 1);
theta = linspace(phiStart, phiStart + sweep, nArc).';
arc = center + radius * [cos(theta), sin(theta)];
arc(1, :) = startPt;
arc(end, :) = center + radius * [cos(phiStart + sweep), sin(phiStart + sweep)];
ok = true;

end

function pts = appendPathPoints(a, b, tol)

pts = [a; b];
if size(pts, 1) < 2
    return;
end
keep = true(size(pts, 1), 1);
for k = 2:size(pts, 1)
    if norm(pts(k, :) - pts(k - 1, :)) <= tol
        keep(k) = false;
    end
end
pts = pts(keep, :);

end

function pass = candidateCompliant(basePath, candidate, mode, boardXY, cfg)
% Candidate compliance: finite points, board interior, half-width board
% clearance, combined-path interior angle, exact self-intersection and
% non-adjacent spacing. Board checks always run; optional geometry checks
% honor their validation switches.
tol = cfg.geometryTolerance;
pass = false;

if isempty(candidate) || size(candidate, 2) ~= 2 || size(candidate, 1) < 2
    return;
end
if any(~isfinite(candidate), 'all') || anyZeroLengthSegments(candidate, tol)
    return;
end

closedBoard = [boardXY; boardXY(1,:)];
[inPoly, onPoly] = inpolygon( ...
    candidate(:,1), candidate(:,2), closedBoard(:,1), closedBoard(:,2));
if any(~(inPoly | onPoly))
    return;
end
if minimumDistanceBetweenPolylines(candidate, closedBoard) < ...
        cfg.traceWidth/2 - tol
    return;
end

if strcmp(mode, 'append')
    combined = [basePath; candidate(2:end,:)];
else
    combined = [flipud(candidate(2:end,:)); basePath];
end

if cfg.enableCopperAngleCheck
    if minimumOpenPolylineInteriorAngle(combined, tol) <= ...
            cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg
        return;
    end
end
if cfg.enableExactSelfIntersectionCheck
    if checkPolylineSelfIntersectionExact(combined, false, cfg)
        return;
    end
end
if cfg.enableCopperClearanceCheck
    minIndexSeparation = max(16, ceil(cfg.pointsPerTurn/4));
    [~, spacingPass] = calculateMinimumNonAdjacentDistance( ...
        combined, cfg.traceWidth + cfg.traceSpacing, ...
        cfg.clearanceTolerance, minIndexSeparation, tol, false);
    if ~spacingPass
        return;
    end
end

pass = true;

end

function [path, ok] = routeViaWaypoint( ...
    startPt, startTangent, waypoint, endPt, bendRadius, arcPointCount, tol)
% Two-leg route: start -> waypoint along startTangent, then along the actual
% end direction of the first leg to endPt. No early skip between waypoints.
path = [];
ok = false;

[path1, ok1] = fpc_coil_geometry('smooth_lead',  ...
    startPt, startTangent, waypoint, bendRadius, arcPointCount, tol);
if ~ok1
    return;
end
if size(path1, 1) < 2
    return;
end
if norm(waypoint - endPt) <= tol
    path = path1;
    ok = true;
    return;
end
lastDir = path1(end,:) - path1(end-1,:);
if norm(lastDir) <= tol
    lastDir = [1, 0];
end
[path2, ok2] = fpc_coil_geometry('smooth_lead',  ...
    waypoint, lastDir, endPt, bendRadius, arcPointCount, tol);
if ~ok2
    return;
end
path = [path1; path2(2:end, :)];
ok = true;

end

%% =========================================================
function len = calculatePathLength(xy)

% 防御：空或非 Nx2 输入按 0 处理（正常路径始终为 Nx2）。
if isempty(xy) || size(xy, 2) ~= 2
    len = 0;
    return;
end
len = sum(hypot(diff(xy(:,1)), diff(xy(:,2))));

end
