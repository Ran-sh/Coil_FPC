function varargout = rectangular_fpc_validation(operation, varargin)
%FPC_COIL_VALIDATION Private validation dispatcher for the FPC runtime.
%   Supported operations:
%     'config' -> validateConfig(cfg)
%     'candidate' -> isCandidateGeometryValid(cfg, d, boardXY, limits)
%     'design' -> validateDesign(cfg, d, boardXY, layerPaths, vias, ...)
%     'route_candidate' -> candidateCompliant(...)

switch operation
    case 'config'
        [varargout{1:nargout}] = validateConfig(varargin{:});
    case 'candidate'
        [varargout{1:nargout}] = isCandidateGeometryValid(varargin{:});
    case 'design'
        [varargout{1:nargout}] = validateDesign(varargin{:});
    case 'route_candidate'
        [varargout{1:nargout}] = candidateCompliant(varargin{:});
    otherwise
        error('RectangularFPC:UnknownValidationOperation', ...
            'Unknown validation operation: %s', operation);
end

end
function cfg = validateConfig(cfg)
%FPC_COIL_VALIDATE_CONFIG Validate and normalize a complete configuration.

if ~isstruct(cfg) || ~isscalar(cfg)
    error('RectangularFPC:InvalidConfig', 'cfg must be a scalar struct.');
end

required = fieldnames(rectangular_fpc_default_config());
for k = 1:numel(required)
    if ~isfield(cfg, required{k})
        error('RectangularFPC:MissingConfigField', ...
            'cfg is missing required field "%s".', required{k});
    end
end

scalarNumeric = { ...
    'layerCount', 'maxLayerCount', 'turnsPerLayer', ...
    'plateLength', 'plateWidth', 'plateCornerRadius', ...
    'tabLength', 'tabWidth', 'tabOuterCornerRadius', ...
    'tabTransitionRadius', 'tabEdgeMargin', ...
    'traceWidth', 'traceSpacing', 'pitchMargin', 'edgeClearance', ...
    'minInnerWidth', 'minInnerLength', 'minSpiralCornerRadius', ...
    'leadYOffset', 'leadBendRadius', 'leadArcPointCount', ...
    'padTipInset', 'padDiameter', 'padTipMargin', 'leadTabClearance', ...
    'padToPadClearance', 'padToCopperClearance', ...
    'viaDrillDiameter', 'viaPadDiameter', ...
    'viaToCopperClearance', 'viaToBoardClearance', ...
    'viaToViaClearance', 'viaToPadClearance', ...
    'viaLandingLeadLength', 'viaLandingClearance', 'viaInnerBendRadius', ...
    'viaOuterLandingLeadLength', 'viaOuterLandingClearance', ...
    'viaOuterBendRadius', 'outputViaTipInset', ...
    'outputViaAntiPadDiameter', 'outputViaToCopperClearance', ...
    'outputViaToBoardClearance', ...
    'innerViaPitch', 'innerViaRowOffsetY', ...
    'outerViaPitch', 'outerViaRowOffsetY', ...
    'viaKeepoutMargin', 'autoViaGridStep', 'recommendedTurnMargin', ...
    'connectionPhase', ...
    'copperThickness', 'copperResistivity', 'minAnnularRing', ...
    'minCopperInteriorAngleDeg', ...
    'minBoardInteriorAngleDeg', 'angleToleranceDeg', ...
    'geometryTolerance', 'connectionTolerance', 'clearanceTolerance', ...
    'crossProductTolerance', 'parameterTolerance', ...
    'pointsPerTurn', 'minTurnPointCount', 'boardArcPointCount', ...
    'maxVerticesPerDxfEntity'};
for k = 1:numel(scalarNumeric)
    name = scalarNumeric{k};
    value = cfg.(name);
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value)
        error('RectangularFPC:InvalidConfigValue', ...
            'cfg.%s must be a finite real numeric scalar.', name);
    end
end

if cfg.layerCount < 2 || cfg.layerCount ~= floor(cfg.layerCount) || ...
        mod(cfg.layerCount, 2) ~= 0 || cfg.layerCount > cfg.maxLayerCount
    error('RectangularFPC:InvalidLayerCount', ...
        ['layerCount=%g is invalid; layerCount must be an even value ', ...
         '(偶数) from 2 through maxLayerCount=%g.'], ...
        cfg.layerCount, cfg.maxLayerCount);
end
if cfg.maxLayerCount < 2 || cfg.maxLayerCount ~= floor(cfg.maxLayerCount) || ...
        mod(cfg.maxLayerCount, 2) ~= 0
    error('RectangularFPC:InvalidLayerCount', ...
        'maxLayerCount=%g must be an even value (偶数) of at least 2.', ...
        cfg.maxLayerCount);
end
if cfg.turnsPerLayer < 1 || cfg.turnsPerLayer ~= floor(cfg.turnsPerLayer)
    error('RectangularFPC:InvalidTurns', 'turnsPerLayer must be a positive integer.');
end

% New turn-limit and via-planning scalar constraints.
if cfg.connectionPhase < 0 || cfg.connectionPhase > 1
    error('RectangularFPC:InvalidConfigValue', ...
        'connectionPhase must be within [0, 1] (normalized phase).');
end
if cfg.recommendedTurnMargin < 0 || cfg.recommendedTurnMargin ~= floor(cfg.recommendedTurnMargin)
    error('RectangularFPC:InvalidConfigValue', ...
        'recommendedTurnMargin must be a non-negative integer.');
end

% String enumeration fields.
enumFields = { ...
    'connectionSide', {'right_center'}; ...
    'coilOuterCornerRadiusMode', {'follow_board','maximize','manual'}; ...
    'cornerOffsetMode', {'strict_concentric','legacy_clamped'}; ...
    'coordinateOrigin', {'body_lower_left'}; ...
    'viaPlacementMode', {'legacy_auto','hybrid_auto','manual'}; ...
    'innerViaLayout', {'horizontal'}; ...
    'outerViaLayout', {'horizontal'}; ...
    'outputViaPlacementMode', {'auto','manual'}; ...
    'manufacturingProfile', {'jlc_fpc_1oz'}; ...
    'manufacturingTier', {'standard','extreme'}};
for k = 1:size(enumFields, 1)
    name = enumFields{k,1};
    value = cfg.(name);
    if ~isTextScalar(value) || ~ismember(char(value), enumFields{k,2})
        allowed = strjoin(enumFields{k,2}, ', ');
        error('RectangularFPC:InvalidConfigValue', ...
            'cfg.%s must be one of: %s.', name, allowed);
    end
    cfg.(name) = char(value);
end

% coilOuterCornerRadius: empty by default; manual mode requires a valid scalar.
if isempty(cfg.coilOuterCornerRadius)
    if strcmp(cfg.coilOuterCornerRadiusMode, 'manual')
        error('RectangularFPC:InvalidConfigValue', ...
            'coilOuterCornerRadius must be provided when coilOuterCornerRadiusMode is ''manual''.');
    end
else
    if ~isnumeric(cfg.coilOuterCornerRadius) || ...
            ~isscalar(cfg.coilOuterCornerRadius) || ...
            ~isreal(cfg.coilOuterCornerRadius) || ...
            ~isfinite(cfg.coilOuterCornerRadius) || ...
            cfg.coilOuterCornerRadius <= 0
        error('RectangularFPC:InvalidConfigValue', ...
            'cfg.coilOuterCornerRadius must be a positive finite real scalar.');
    end
    outerCenterInset = cfg.edgeClearance + cfg.traceWidth/2;
    outerLength = cfg.plateLength - 2*outerCenterInset;
    outerWidth = cfg.plateWidth - 2*outerCenterInset;
    if cfg.coilOuterCornerRadius > min(outerLength, outerWidth)/2
        error('RectangularFPC:InvalidConfigValue', ...
            'coilOuterCornerRadius=%g exceeds min(outerLength,outerWidth)/2=%g.', ...
            cfg.coilOuterCornerRadius, min(outerLength, outerWidth)/2);
    end
end

% Manual via coordinate matrices: empty allowed when not in manual mode.
for name = {'manualSeriesViaXY', 'manualOutputViaXY'}
    value = cfg.(name{1});
    if isempty(value)
        continue
    end
    if ~isnumeric(value) || size(value, 2) ~= 2 || ~all(isfinite(value), 'all')
        error('RectangularFPC:InvalidConfigValue', ...
            'cfg.%s must be an Nx2 finite numeric matrix (mm).', name{1});
    end
    cfg.(name{1}) = double(value);
end

% Manual mode row-count checks.
if strcmp(cfg.viaPlacementMode, 'manual')
    if size(cfg.manualSeriesViaXY, 1) ~= cfg.layerCount - 1
        error('RectangularFPC:InvalidManualVias', ...
            ['manualSeriesViaXY must have exactly layerCount-1=%d rows ', ...
             '(V12, V23, ...) when viaPlacementMode is ''manual''; got %d.'], ...
            cfg.layerCount - 1, size(cfg.manualSeriesViaXY, 1));
    end
end
if strcmp(cfg.outputViaPlacementMode, 'manual')
    if ~isequal(size(cfg.manualOutputViaXY), [1, 2])
        error('RectangularFPC:InvalidManualVias', ...
            'manualOutputViaXY must be a 1x2 matrix when outputViaPlacementMode is ''manual''.');
    end
end

positive = {'plateLength','plateWidth','tabLength','tabWidth','traceWidth', ...
    'minInnerWidth','minInnerLength','minSpiralCornerRadius','leadYOffset','leadBendRadius','padTipInset', ...
    'padDiameter','viaDrillDiameter','viaPadDiameter', ...
    'viaLandingLeadLength','viaInnerBendRadius', ...
    'viaOuterLandingLeadLength','viaOuterBendRadius', ...
    'outputViaTipInset','copperThickness', ...
    'copperResistivity','geometryTolerance','connectionTolerance', ...
    'crossProductTolerance','parameterTolerance','pitchMargin', ...
    'innerViaPitch','outerViaPitch','autoViaGridStep'};
for k = 1:numel(positive)
    if cfg.(positive{k}) <= 0
        error('RectangularFPC:InvalidConfigValue', 'cfg.%s must be greater than zero.', positive{k});
    end
end

nonnegative = {'plateCornerRadius','tabOuterCornerRadius','tabEdgeMargin', ...
    'traceSpacing','edgeClearance','padTipMargin','leadTabClearance', ...
    'padToPadClearance','padToCopperClearance','viaToCopperClearance', ...
    'viaToBoardClearance','viaToViaClearance','viaToPadClearance', ...
    'viaLandingClearance','viaOuterLandingClearance', ...
    'outputViaToCopperClearance','outputViaToBoardClearance', ...
    'minAnnularRing','clearanceTolerance'};
for k = 1:numel(nonnegative)
    if cfg.(nonnegative{k}) < 0
        error('RectangularFPC:InvalidConfigValue', 'cfg.%s cannot be negative.', nonnegative{k});
    end
end

if cfg.viaPadDiameter <= cfg.viaDrillDiameter || ...
        (cfg.viaPadDiameter - cfg.viaDrillDiameter)/2 + ...
        cfg.geometryTolerance < cfg.minAnnularRing
    error('RectangularFPC:InvalidViaGeometry', ...
        'Via pad/drill dimensions do not provide minAnnularRing.');
end
if cfg.outputViaAntiPadDiameter <= cfg.viaPadDiameter
    error('RectangularFPC:InvalidViaGeometry', ...
        'outputViaAntiPadDiameter must exceed viaPadDiameter.');
end
if ~isTextScalar(cfg.outputViaType) || ...
        ~strcmp(char(cfg.outputViaType), 'through_via')
    error('RectangularFPC:InvalidConfigValue', ...
        'outputViaType must be ''through_via'' for the L%d-to-L1 output.', cfg.layerCount);
end
if ~isTextScalar(cfg.viaClearanceSeverity) || ...
        ~ismember(char(cfg.viaClearanceSeverity), {'warning','error'})
    error('RectangularFPC:InvalidConfigValue', ...
        'viaClearanceSeverity must be ''warning'' or ''error''.');
end
cfg.outputViaType = char(cfg.outputViaType);
cfg.viaClearanceSeverity = char(cfg.viaClearanceSeverity);

integerAtLeast = { ...
    'leadArcPointCount', 8; 'pointsPerTurn', 100; ...
    'minTurnPointCount', 100; 'boardArcPointCount', 8; ...
    'maxVerticesPerDxfEntity', 2};
for k = 1:size(integerAtLeast, 1)
    name = integerAtLeast{k,1};
    lowerBound = integerAtLeast{k,2};
    if cfg.(name) < lowerBound || cfg.(name) ~= floor(cfg.(name))
        error('RectangularFPC:InvalidConfigValue', ...
            'cfg.%s must be an integer >= %d.', name, lowerBound);
    end
end

booleanFields = {'useRecommendedTurns','enablePreview','enableFigure','analysisOnly', ...
    'requireSmoothLeadTransitions', ...
    'enableExactSelfIntersectionCheck','enableCopperClearanceCheck', ...
    'enableBoardAngleCheck','enableCopperAngleCheck', ...
    'enablePadClearanceCheck','enableViaClearanceCheck', ...
    'enableDxfReadbackCheck'};
for k = 1:numel(booleanFields)
    value = cfg.(booleanFields{k});
    if ~isscalar(value) || (~islogical(value) && ...
            ~(isnumeric(value) && ismember(value, [0, 1])))
        error('RectangularFPC:InvalidConfigValue', ...
            'cfg.%s must be logical or numeric 0/1.', booleanFields{k});
    end
    cfg.(booleanFields{k}) = logical(value);
end

rectangular_fpc_manufacturing('validate_config', cfg);

if ~isTextScalar(cfg.outputRoot) || ~isTextScalar(cfg.designName)
    error('RectangularFPC:InvalidOutputName', ...
        'outputRoot and designName must be character vectors or string scalars.');
end
cfg.outputRoot = char(cfg.outputRoot);
cfg.designName = char(cfg.designName);
if isempty(cfg.outputRoot) || isempty(cfg.designName) || ...
        isempty(regexp(cfg.designName, '^[A-Za-z0-9_-]+$', 'once'))
    error('RectangularFPC:InvalidOutputName', ...
        'outputRoot must be nonempty and designName may contain only letters, numbers, _ and -.');
end

end

function tf = isTextScalar(value)

tf = ischar(value) || (isstring(value) && isscalar(value));

end

function validation = validateDesign( ...
    cfg, d, boardXY, layerPaths, vias, connectionErrors, ...
    escapeArcFallback, limits, fullyValidatedMaxTurns)

tol = cfg.geometryTolerance;
viaXY = vertcat(vias.xy);
failures = {};
nanInfPass = true;
zeroLengthPass = true;
if cfg.requireSmoothLeadTransitions && escapeArcFallback
    failures{end+1} = ...
        '逃逸引线圆弧生成失败，不允许回退为90度尖角';
end

allPaths = flattenLayerPaths(layerPaths);
if any(~isfinite(boardXY), 'all') || ...
        any(cellfun(@(path) any(~isfinite(path), 'all'), allPaths))
    nanInfPass = false;
    failures{end+1} = '存在NaN或Inf坐标';
end
if rectangular_fpc_geometry('has_zero_length', boardXY, tol) || ...
        any(cellfun(@(path) rectangular_fpc_geometry( ...
        'has_zero_length', path, tol), allPaths))
    zeroLengthPass = false;
    failures{end+1} = '存在零长度线段';
end

boardMinAngle = NaN;
if cfg.enableBoardAngleCheck
    boardMinAngle = minimumClosedPolylineInteriorAngle(boardXY, tol);
    if boardMinAngle <= cfg.minBoardInteriorAngleDeg + cfg.angleToleranceDeg
        failures{end+1} = sprintf( ...
            '板框最小内角%.3f度，必须严格大于%.3f度', ...
            boardMinAngle, ...
            cfg.minBoardInteriorAngleDeg + cfg.angleToleranceDeg);
    end
end

copperMinAngles = NaN(cfg.layerCount, 1);
if cfg.enableCopperAngleCheck
    for layerIndex = 1:cfg.layerCount
        pathAngles = cellfun(@(path) ...
            minimumOpenPolylineInteriorAngle(path, tol), ...
            layerPaths{layerIndex});
        copperMinAngles(layerIndex) = min(pathAngles);
        if copperMinAngles(layerIndex) <= ...
                cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg
            failures{end+1} = sprintf( ...
                'L%d最小铜线内角%.3f度，必须严格大于%.3f度', ...
                layerIndex, copperMinAngles(layerIndex), ...
                cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg); %#ok<AGROW>
        end
    end
end

boardSelfIntersectionPass = true;
copperSelfIntersectionPass = true;
if cfg.enableExactSelfIntersectionCheck
    if checkPolylineSelfIntersectionExact(boardXY, true, cfg)
        boardSelfIntersectionPass = false;
        failures{end+1} = '板框存在自相交';
    end
    for layerIndex = 1:cfg.layerCount
        for pathIndex = 1:numel(layerPaths{layerIndex})
            if checkPolylineSelfIntersectionExact( ...
                    layerPaths{layerIndex}{pathIndex}, false, cfg)
                copperSelfIntersectionPass = false;
                failures{end+1} = sprintf( ...
                    'L%d路径%d存在自相交', layerIndex, pathIndex); %#ok<AGROW>
            end
        end
        for pathA = 1:numel(layerPaths{layerIndex})-1
            for pathB = pathA+1:numel(layerPaths{layerIndex})
                if minimumDistanceBetweenPolylines( ...
                        layerPaths{layerIndex}{pathA}, ...
                        layerPaths{layerIndex}{pathB}) <= tol
                    copperSelfIntersectionPass = false;
                    failures{end+1} = sprintf( ...
                        'L%d路径%d与路径%d相交', ...
                        layerIndex, pathA, pathB); %#ok<AGROW>
                end
            end
        end
    end
end

minCopperSpacing = NaN;
copperClearancePass = true;
if cfg.enableCopperClearanceCheck
    targetCenterline = cfg.traceWidth + cfg.traceSpacing;
    minIndexSeparation = max(16, ceil(cfg.pointsPerTurn/4));
    minCenterline = Inf;
    for layerIndex = 1:cfg.layerCount
        layerMinDistance = Inf;
        layerPass = true;
        for pathIndex = 1:numel(layerPaths{layerIndex})
            [pathDistance, pathPass] = ...
                calculateMinimumNonAdjacentDistance( ...
                layerPaths{layerIndex}{pathIndex}, targetCenterline, ...
                cfg.clearanceTolerance, minIndexSeparation, tol);
            layerMinDistance = min(layerMinDistance, pathDistance);
            layerPass = layerPass && pathPass;
        end
        for pathA = 1:numel(layerPaths{layerIndex})-1
            for pathB = pathA+1:numel(layerPaths{layerIndex})
                pathDistance = minimumDistanceBetweenPolylines( ...
                    layerPaths{layerIndex}{pathA}, ...
                    layerPaths{layerIndex}{pathB});
                layerMinDistance = min(layerMinDistance, pathDistance);
                layerPass = layerPass && pathDistance >= ...
                    targetCenterline - cfg.clearanceTolerance;
            end
        end
        if ~layerPass
            copperClearancePass = false;
            failures{end+1} = sprintf( ...
                'L%d实际最小线距%.6f mm，低于允许值%.6f mm', ...
                layerIndex, layerMinDistance - cfg.traceWidth, ...
                cfg.traceSpacing - cfg.clearanceTolerance); %#ok<AGROW>
        end
        minCenterline = min(minCenterline, layerMinDistance);
    end
    minCopperSpacing = minCenterline - cfg.traceWidth;
end

connectionPass = all(connectionErrors <= cfg.connectionTolerance);
viaCoincidencePass = true;
for firstVia = 1:size(viaXY, 1)-1
    for secondVia = firstVia+1:size(viaXY, 1)
        if norm(viaXY(firstVia,:) - viaXY(secondVia,:)) < ...
                cfg.geometryTolerance
            viaCoincidencePass = false;
            failures{end+1} = sprintf( ...
                '过孔V%d%d与V%d%d坐标重合', firstVia, firstVia + 1, ...
                secondVia, secondVia + 1); %#ok<AGROW>
        end
    end
end

boardClosurePass = validateBoardClosure(boardXY, tol);
bodyDimensionPass = validateBodyDimensions(boardXY, cfg, tol);
tabDimensionPass = validateTabDimensions(boardXY, cfg, tol);
overallDimensionPass = validateBoardDimensions(boardXY, cfg, tol);
if ~boardClosurePass
    failures{end+1} = '板框闭合检查失败';
end
if ~bodyDimensionPass
    failures{end+1} = '主体尺寸检查失败';
end
if ~tabDimensionPass
    failures{end+1} = '尾部尺寸检查失败';
end
if ~overallDimensionPass
    failures{end+1} = '总尺寸检查失败';
end

padBoardPass = true;
padPadPass = true;
padCopperPass = true;
padConnectionLength = ...
    (d.padA(1) - (d.outerRightCenterX + cfg.leadBendRadius)) + ...
    (pi/2) * cfg.leadBendRadius;
% 板框按开放点列存储（首尾不重复），最后一条 last→first 闭合边真实存在；
% 所有到板框的距离计算必须使用显式闭合形式，否则闭合边附近会高估净距。
closedBoardXY = [boardXY; boardXY(1, :)];
if cfg.enablePadClearanceCheck
    padBoardPass = validatePadToBoard( ...
        d.padA, d.padB, closedBoardXY, cfg, tol);
    padPadPass = validatePadToPad(d.padA, d.padB, cfg, tol);
    padCopperPass = validatePadToCopper( ...
        d.padA, d.padB, layerPaths, cfg, tol, padConnectionLength);
    if ~padBoardPass
        failures{end+1} = '焊盘完整圆形区域未完全位于板框内';
    end
    if ~padPadPass
        failures{end+1} = 'PAD_A与PAD_B间距不足';
    end
    if ~padCopperPass
        failures{end+1} = '焊盘到非连接铜线间距不足';
    end
end

viaToViaPass = true;
viaToBoardPass = true;
viaToPadPass = true;
viaConnectedPass = true;
viaNonConnectedPass = true;
if cfg.enableViaClearanceCheck
    viaToViaPass = validateViaToVia(viaXY, cfg, tol);
    viaToBoardPass = validateViaToBoard(vias, closedBoardXY, cfg, tol);
    viaToPadPass = validateViaToPad(viaXY, d.padA, d.padB, cfg, tol);
    viaEscapeLengths = zeros(numel(vias), 1);
    for viaIndex = 1:numel(vias)
        if ~isnan(vias(viaIndex).fromLeadLength)
            viaEscapeLengths(viaIndex) = max( ...
                vias(viaIndex).fromLeadLength, vias(viaIndex).toLeadLength);
        end
    end
    viaEscapeLengths(end) = norm(d.padB - d.outputVia);
    viaConnectedClearances = zeros(numel(vias), 1);
    viaConnectedClearances(1:2:end) = cfg.viaLandingClearance;
    viaConnectedClearances(2:2:cfg.layerCount-1) = ...
        cfg.viaOuterLandingClearance;
    viaConnectedClearances(end) = cfg.outputViaToCopperClearance;
    [viaConnectedPass, viaNonConnectedPass, viaIssues] = ...
        validateViaToCopper(vias, layerPaths, cfg, tol, ...
        viaEscapeLengths, viaConnectedClearances);
    if ~viaToViaPass
        failures{end+1} = '过孔焊盘之间间距不足';
    end
    if ~viaToBoardPass
        failures{end+1} = '过孔焊盘或钻孔距板框过近';
    end
    if ~viaToPadPass
        failures{end+1} = '过孔焊盘与PAD_A或PAD_B间距不足';
    end
    if ~viaConnectedPass
        failures = [failures, viaIssues];
    end
    if ~viaNonConnectedPass && (ismember(cfg.layerCount, [2, 4]) || ...
            strcmp(cfg.viaClearanceSeverity, 'error'))
        failures{end+1} = '过孔焊盘与不应连接的铜层间距不足';
    end
end

% 最终几何实测的最小铜到板边距离：全部走线中心线按半线宽缩边、PAD_A/PAD_B
% 焊盘与过孔焊环逐点测量。该值供制造报告 COPPER_TO_BOARD 使用，
% 配置值 edgeClearance 只是布线设计目标，不能充当最终实测值。
minCopperToBoardMm = measureMinCopperToBoardMm(closedBoardXY, allPaths, cfg, d, vias);

% 独立记录 PAD/VIA/DRILL 的最终铜边净距；制造报告只能使用这些
% 生成后实测值，不能用配置目标冒充测量结果。
[viaEscapeLengths, viaConnectedClearances] = terminalClearanceInputs( ...
    cfg, d, vias);
minPadToUnrelatedTraceMm = measureMinPadToUnrelatedTraceMm( ...
    d.padA, d.padB, layerPaths, cfg, padConnectionLength);
minViaToUnrelatedCopperMm = measureMinViaToUnrelatedCopperMm( ...
    vias, layerPaths, cfg, viaEscapeLengths, viaConnectedClearances);
minDrillToNonConnectedCopperMm = measureMinDrillToNonConnectedCopperMm( ...
    vias, layerPaths, cfg);
minDrillToBoardMm = measureMinDrillToBoardMm(vias, closedBoardXY);
manufacturingRules = rectangular_fpc_manufacturing('resolve', cfg).rules;
padTraceMeasuredPass = minPadToUnrelatedTraceMm >= ...
    cfg.padToCopperClearance - tol;
viaTraceMeasuredPass = minViaToUnrelatedCopperMm >= ...
    min(cfg.viaToCopperClearance, cfg.outputViaToCopperClearance) - tol;
drillCopperMeasuredPass = minDrillToNonConnectedCopperMm >= ...
    manufacturingRules.minDrillToCopperMm - tol;
drillBoardMeasuredPass = minDrillToBoardMm >= ...
    manufacturingRules.minDrillToBoardMm - tol;
if cfg.enablePadClearanceCheck && ~padTraceMeasuredPass
    failures{end+1} = '焊盘到无关连接走线的实测净距不足'; %#ok<AGROW>
end
if cfg.enableViaClearanceCheck && ~viaTraceMeasuredPass
    failures{end+1} = '过孔焊环到无关连接走线的实测净距不足'; %#ok<AGROW>
end
if cfg.enableViaClearanceCheck && ismember(cfg.layerCount, [2, 4]) && ...
        ~drillCopperMeasuredPass
    failures{end+1} = '钻孔到非连接层铜的实测净距不足'; %#ok<AGROW>
end
if cfg.enableViaClearanceCheck && ~drillBoardMeasuredPass
    failures{end+1} = '钻孔到板框的实测净距不足'; %#ok<AGROW>
end

passed = isempty(failures);
reportLines = buildValidationReportLines( ...
    cfg, passed, failures, limits, fullyValidatedMaxTurns, ...
    boardMinAngle, copperMinAngles, minCopperSpacing, ...
    connectionErrors, viaCoincidencePass, nanInfPass, ...
    zeroLengthPass, boardClosurePass, bodyDimensionPass, ...
    tabDimensionPass, overallDimensionPass, ...
    boardSelfIntersectionPass, copperSelfIntersectionPass, ...
    padBoardPass, padPadPass, padCopperPass, viaToViaPass, ...
    viaToBoardPass, viaToPadPass, viaConnectedPass, ...
    viaNonConnectedPass, copperClearancePass, connectionPass);
validation = struct( ...
    'passed', passed, 'messages', {failures}, 'advisories', {{}}, ...
    'reportLines', {reportLines}, 'minBoardAngleDeg', boardMinAngle, ...
    'minCopperAngleDeg', min(copperMinAngles), ...
    'minCopperSpacingMm', minCopperSpacing, ...
    'minCopperToBoardMm', minCopperToBoardMm, ...
    'minPadToUnrelatedTraceMm', minPadToUnrelatedTraceMm, ...
    'minViaToUnrelatedCopperMm', minViaToUnrelatedCopperMm, ...
    'minDrillToNonConnectedCopperMm', minDrillToNonConnectedCopperMm, ...
    'minDrillToBoardMm', minDrillToBoardMm, ...
    'connectionErrorsMm', connectionErrors, ...
    'viaConnectedCopperPassed', viaConnectedPass, ...
    'viaNonConnectedCopperPassed', viaNonConnectedPass);

end

function pass = candidateCompliant(basePath, candidate, mode, boardXY, cfg)

tol = cfg.geometryTolerance;
pass = false;
if isempty(candidate) || size(candidate, 2) ~= 2 || ...
        size(candidate, 1) < 2 || any(~isfinite(candidate), 'all') || ...
        rectangular_fpc_geometry('has_zero_length', candidate, tol)
    return;
end
closedBoard = [boardXY; boardXY(1,:)];
[inPoly, onPoly] = inpolygon(candidate(:,1), candidate(:,2), ...
    closedBoard(:,1), closedBoard(:,2));
if any(~(inPoly | onPoly)) || ...
        minimumDistanceBetweenPolylines(candidate, closedBoard) < ...
        cfg.traceWidth/2 - tol
    return;
end
if strcmp(mode, 'append')
    combined = [basePath; candidate(2:end,:)];
else
    combined = [flipud(candidate(2:end,:)); basePath];
end
if cfg.enableCopperAngleCheck && ...
        minimumOpenPolylineInteriorAngle(combined, tol) <= ...
        cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg
    return;
end
if cfg.enableExactSelfIntersectionCheck && ...
        checkPolylineSelfIntersectionExact(combined, false, cfg)
    return;
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
        rectangular_fpc_geometry('build_layers', cfg, d, limits, boardXY);
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
        any(cellfun(@(xy) rectangular_fpc_geometry( ...
        'has_zero_length', xy, tol), candidatePaths)) || ...
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

% 候选扫描与最终验证一致：板框按开放点列存储，距离计算必须用显式闭合形式。
closedBoardXY = [boardXY; boardXY(1, :)];
padConnectionLength = ...
    (d.padA(1) - (d.outerRightCenterX + cfg.leadBendRadius)) + ...
    (pi/2)*cfg.leadBendRadius;
if cfg.enablePadClearanceCheck
    if ~validatePadToBoard(d.padA, d.padB, closedBoardXY, cfg, tol)
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
    if ~validateViaToBoard(vias, closedBoardXY, cfg, tol)
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
    manufacturingQualificationRequired = ismember(cfg.layerCount, [2, 4]);
    nonConnectedAccepted = nonConnectedPass || ...
        (~manufacturingQualificationRequired && ...
        strcmp(cfg.viaClearanceSeverity, 'warning'));
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

function minAngle = minimumOpenPolylineInteriorAngle(xy, tol)

xy = rectangular_fpc_geometry('remove_duplicates', xy, tol);
xy = rectangular_fpc_geometry('remove_zero_length', xy, tol);

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

xy = rectangular_fpc_geometry('remove_duplicates', xy, tol);
xy = rectangular_fpc_geometry('remove_zero_length', xy, tol);

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

xy = rectangular_fpc_geometry('remove_duplicates', xy, tol);
xy = rectangular_fpc_geometry('remove_zero_length', xy, tol);

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

[xy, ~] = rectangular_fpc_geometry('remove_duplicates', xy, tol);
[xy, ~] = rectangular_fpc_geometry('remove_zero_length', xy, tol);

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
                    % Every plated through hole must clear copper on each
                    % non-connected layer by both the generic pad spacing
                    % and the exported antipad diameter.
                    if strcmp(vias(k).type, 'through_via') && ...
                            ~ismember(layerIndex, vias(k).connectedLayers)
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
function minCopperToBoard = measureMinCopperToBoardMm( ...
    boardXY, allPaths, cfg, d, vias)
% 最终成品全铜对象到板框的实测最小距离（mm）：
%   1) 每条走线与板框之间做完整 segment-to-segment 最小距离，减半线宽
%      得到铜边距离（最近点可落在线段内部，仅测顶点会高估净距）；
%   2) PAD_A/PAD_B 圆盘：圆心距离减半径（精确）；
%   3) 过孔焊环：圆心距离减焊环半径（精确）。
% 结果供制造资格判定 fail-closed 使用。
minCopperToBoard = Inf;
halfTrace = cfg.traceWidth / 2;
for pathIndex = 1:numel(allPaths)
    path = allPaths{pathIndex};
    if isempty(path) || size(path, 1) < 2
        continue;
    end
    minCopperToBoard = min(minCopperToBoard, ...
        minimumDistanceBetweenPolylines(path, boardXY) - halfTrace);
end
minCopperToBoard = min(minCopperToBoard, ...
    minimumDistancePointToPolyline(d.padA, boardXY) - cfg.padDiameter / 2);
minCopperToBoard = min(minCopperToBoard, ...
    minimumDistancePointToPolyline(d.padB, boardXY) - cfg.padDiameter / 2);
for viaIndex = 1:numel(vias)
    minCopperToBoard = min(minCopperToBoard, ...
        minimumDistancePointToPolyline(vias(viaIndex).xy, boardXY) - ...
        vias(viaIndex).padDiameter / 2);
end
end

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
function [viaEscapeLengths, viaConnectedClearances] = ...
    terminalClearanceInputs(cfg, d, vias)

viaEscapeLengths = zeros(numel(vias), 1);
for viaIndex = 1:numel(vias)
    if ~isnan(vias(viaIndex).fromLeadLength)
        viaEscapeLengths(viaIndex) = max( ...
            vias(viaIndex).fromLeadLength, vias(viaIndex).toLeadLength);
    end
end
viaEscapeLengths(end) = norm(d.padB - d.outputVia);
viaConnectedClearances = zeros(numel(vias), 1);
viaConnectedClearances(1:2:end) = cfg.viaLandingClearance;
viaConnectedClearances(2:2:cfg.layerCount-1) = ...
    cfg.viaOuterLandingClearance;
viaConnectedClearances(end) = cfg.outputViaToCopperClearance;
end

function dMin = measureMinPadToUnrelatedTraceMm( ...
    padA, padB, layerPaths, cfg, padConnectionLength)

dMin = Inf;
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
        dMin = min(dMin, dA - cfg.padDiameter/2 - cfg.traceWidth/2);

        if layerIndex == 1 && pathIndex == 2
            dB = Inf;
        else
            dB = minimumDistancePointToPolyline(padB, path);
        end
        dMin = min(dMin, dB - cfg.padDiameter/2 - cfg.traceWidth/2);
    end
end
end

function dMin = measureMinViaToUnrelatedCopperMm( ...
    vias, layerPaths, cfg, viaEscapeLengths, viaConnectedClearances)

dMin = Inf;
for viaIndex = 1:numel(vias)
    via = vias(viaIndex);
    requiredDistance = via.padDiameter/2 + cfg.traceWidth/2 + ...
        viaConnectedClearances(viaIndex);
    excludedLength = viaEscapeLengths(viaIndex) + requiredDistance;
    connectedLayers = unique([via.fromLayer, via.toLayer]);
    for layerIndex = connectedLayers
        for pathIndex = 1:numel(layerPaths{layerIndex})
            path = layerPaths{layerIndex}{pathIndex};
            isFromPath = layerIndex == via.fromLayer && pathIndex == 1;
            isToPath = layerIndex == via.toLayer && pathIndex == 1;
            if strcmp(via.role, 'output_return')
                isToPath = layerIndex == 1 && pathIndex == 2;
            end
            if isFromPath
                centerDistance = minimumDistancePointToPolylineExcludingLength( ...
                    via.xy, path, false, excludedLength);
            elseif isToPath
                if strcmp(via.role, 'output_return')
                    centerDistance = Inf;
                else
                    centerDistance = minimumDistancePointToPolylineExcludingLength( ...
                        via.xy, path, true, excludedLength);
                end
            else
                centerDistance = minimumDistancePointToPolyline(via.xy, path);
            end
            dMin = min(dMin, centerDistance - via.padDiameter/2 - ...
                cfg.traceWidth/2);
        end
    end
end
end

function dMin = measureMinDrillToNonConnectedCopperMm(vias, layerPaths, cfg)

dMin = Inf;
for viaIndex = 1:numel(vias)
    via = vias(viaIndex);
    if ~strcmp(via.type, 'through_via')
        continue;
    end
    connectedLayers = unique(via.connectedLayers);
    for layerIndex = setdiff(1:numel(layerPaths), connectedLayers)
        for pathIndex = 1:numel(layerPaths{layerIndex})
            path = layerPaths{layerIndex}{pathIndex};
            dMin = min(dMin, minimumDistancePointToPolyline( ...
                via.xy, path) - via.drillDiameter/2 - cfg.traceWidth/2);
        end
    end
end
end

function dMin = measureMinDrillToBoardMm(vias, boardXY)

dMin = Inf;
for viaIndex = 1:numel(vias)
    dMin = min(dMin, minimumDistancePointToPolyline( ...
        vias(viaIndex).xy, boardXY) - vias(viaIndex).drillDiameter/2);
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
if ismember(cfg.layerCount, [2, 4])
    lines{end+1} = 'Via technology                 : plated through-hole (all vias)';
    lines{end+1} = sprintf('Series-via antipad diameter    : %.3f mm', ...
        cfg.viaPadDiameter + 2 * cfg.viaToCopperClearance);
else
    lines{end+1} = ['Via technology                 : adjacent-layer series vias ', ...
        '(UNVERIFIED)'];
end
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
    elseif ismember(cfg.layerCount, [2, 4]) || ...
            strcmp(cfg.viaClearanceSeverity, 'error')
        viaNonConnectedStatus = 'FAIL';
    else
        viaNonConnectedStatus = 'WARN';
    end

    lines{end+1} = sprintf('过孔非连接层间距检查     : %s', ...
        viaNonConnectedStatus);

    if ~viaNonConnectedPass
        lines{end+1} = '注意：通孔与非连接铜层净距不足；请修正几何后重新生成。';
        lines{end+1} = '逐层 antipad DXF 是必须导入的禁铜开窗。';
        lines{end+1} = '不得将本设计中的通孔解释为盲孔或埋孔。';
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
