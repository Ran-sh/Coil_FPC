function varargout = rectangular_fpc_design_checks(operation, varargin)
%RECTANGULAR_FPC_DESIGN_CHECKS Final design and manufacturing-clearance checks.

switch operation
    case 'design'
        [varargout{1:nargout}] = validateDesign(varargin{:});
    case 'pad_to_board'
        [varargout{1:nargout}] = validatePadToBoard(varargin{:});
    case 'pad_to_pad'
        [varargout{1:nargout}] = validatePadToPad(varargin{:});
    case 'pad_to_copper'
        [varargout{1:nargout}] = validatePadToCopper(varargin{:});
    case 'via_to_via'
        [varargout{1:nargout}] = validateViaToVia(varargin{:});
    case 'via_to_pad'
        [varargout{1:nargout}] = validateViaToPad(varargin{:});
    case 'via_to_board'
        [varargout{1:nargout}] = validateViaToBoard(varargin{:});
    case 'via_to_copper'
        [varargout{1:nargout}] = validateViaToCopper(varargin{:});
    otherwise
        error('RectangularFPC:UnknownDesignCheckOperation', ...
            'Unknown design-check operation: %s', operation);
end
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

allPaths = rectangular_fpc_path_geometry('flatten_layers', layerPaths);
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

[topologyPass, topologyIssues, topologyEndpointErrors] = ...
    rectangular_fpc_validation_report('electrical_topology', cfg, d, layerPaths, vias);
if ~topologyPass
    for issueIndex = 1:numel(topologyIssues)
        failures{end+1} = topologyIssues{issueIndex}; %#ok<AGROW>
    end
end

boardMinAngle = NaN;
if cfg.enableBoardAngleCheck
    boardMinAngle = rectangular_fpc_path_geometry('minimum_closed_angle', boardXY, tol);
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
            rectangular_fpc_path_geometry('minimum_open_angle', path, tol), ...
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
    if rectangular_fpc_path_geometry('self_intersection', boardXY, true, cfg)
        boardSelfIntersectionPass = false;
        failures{end+1} = '板框存在自相交';
    end
    for layerIndex = 1:cfg.layerCount
        for pathIndex = 1:numel(layerPaths{layerIndex})
            if rectangular_fpc_path_geometry('self_intersection',  ...
                    layerPaths{layerIndex}{pathIndex}, false, cfg)
                copperSelfIntersectionPass = false;
                failures{end+1} = sprintf( ...
                    'L%d路径%d存在自相交', layerIndex, pathIndex); %#ok<AGROW>
            end
        end
        for pathA = 1:numel(layerPaths{layerIndex})-1
            for pathB = pathA+1:numel(layerPaths{layerIndex})
                if rectangular_fpc_path_geometry('minimum_distance_polylines',  ...
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
                rectangular_fpc_path_geometry('minimum_nonadjacent_distance',  ...
                layerPaths{layerIndex}{pathIndex}, targetCenterline, ...
                cfg.clearanceTolerance, minIndexSeparation, tol);
            layerMinDistance = min(layerMinDistance, pathDistance);
            layerPass = layerPass && pathPass;
        end
        for pathA = 1:numel(layerPaths{layerIndex})-1
            for pathB = pathA+1:numel(layerPaths{layerIndex})
                pathDistance = rectangular_fpc_path_geometry('minimum_distance_polylines',  ...
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
minViaToBoardMm = measureMinViaToBoardMm(vias, closedBoardXY);
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
    failures{end+1} = '焊盘到无关连接走线的实测净距不足';
end
if cfg.enableViaClearanceCheck && ~viaTraceMeasuredPass
    failures{end+1} = '过孔焊环到无关连接走线的实测净距不足';
end
if cfg.enableViaClearanceCheck && ismember(cfg.layerCount, [2, 4]) && ...
        ~drillCopperMeasuredPass
    failures{end+1} = '钻孔到非连接层铜的实测净距不足';
end
if cfg.enableViaClearanceCheck && ~drillBoardMeasuredPass
    failures{end+1} = '钻孔到板框的实测净距不足';
end

passed = isempty(failures);
reportLines = rectangular_fpc_validation_report('build',  ...
    cfg, passed, failures, limits, fullyValidatedMaxTurns, ...
    boardMinAngle, copperMinAngles, minCopperSpacing, ...
    connectionErrors, viaCoincidencePass, nanInfPass, ...
    zeroLengthPass, boardClosurePass, bodyDimensionPass, ...
    tabDimensionPass, overallDimensionPass, ...
    boardSelfIntersectionPass, copperSelfIntersectionPass, ...
    padBoardPass, padPadPass, padCopperPass, viaToViaPass, ...
    viaToBoardPass, viaToPadPass, viaConnectedPass, ...
    viaNonConnectedPass, copperClearancePass, connectionPass, ...
    topologyPass);
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
    'minViaToBoardMm', minViaToBoardMm, ...
    'connectionErrorsMm', connectionErrors, ...
    'topologyPassed', topologyPass, ...
    'topologyIssues', {topologyIssues}, ...
    'topologyEndpointErrorsMm', topologyEndpointErrors, ...
    'viaConnectedCopperPassed', viaConnectedPass, ...
    'viaNonConnectedCopperPassed', viaNonConnectedPass);

end

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
       rectangular_fpc_path_geometry('minimum_distance_point_polyline', padA, boardXY) >= radius - tol && ...
       rectangular_fpc_path_geometry('minimum_distance_point_polyline', padB, boardXY) >= radius - tol;

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
            dA = rectangular_fpc_path_geometry('minimum_distance_point_polyline_excluding',  ...
                padA, path, true, connectedExcludedLength);
        else
            dA = rectangular_fpc_path_geometry('minimum_distance_point_polyline', padA, path);
        end

        if dA < requiredDistance - tol
            pass = false;
            return;
        end

        if layerIndex == 1 && pathIndex == 2
            dB = Inf;
        else
            dB = rectangular_fpc_path_geometry('minimum_distance_point_polyline', padB, path);
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
    d = rectangular_fpc_path_geometry('minimum_distance_point_polyline', vias(k).xy, boardXY);

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
                d = rectangular_fpc_path_geometry('minimum_distance_point_polyline_excluding',  ...
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
                    d = rectangular_fpc_path_geometry('minimum_distance_point_polyline_excluding',  ...
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
                    d = rectangular_fpc_path_geometry('minimum_distance_point_polyline', vias(k).xy, path);
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
        rectangular_fpc_path_geometry('minimum_distance_polylines', path, boardXY) - halfTrace);
end
minCopperToBoard = min(minCopperToBoard, ...
    rectangular_fpc_path_geometry('minimum_distance_point_polyline', d.padA, boardXY) - cfg.padDiameter / 2);
minCopperToBoard = min(minCopperToBoard, ...
    rectangular_fpc_path_geometry('minimum_distance_point_polyline', d.padB, boardXY) - cfg.padDiameter / 2);
for viaIndex = 1:numel(vias)
    minCopperToBoard = min(minCopperToBoard, ...
        rectangular_fpc_path_geometry('minimum_distance_point_polyline', vias(viaIndex).xy, boardXY) - ...
        vias(viaIndex).padDiameter / 2);
end
end

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
            dA = rectangular_fpc_path_geometry('minimum_distance_point_polyline_excluding',  ...
                padA, path, true, connectedExcludedLength);
        else
            dA = rectangular_fpc_path_geometry('minimum_distance_point_polyline', padA, path);
        end
        dMin = min(dMin, dA - cfg.padDiameter/2 - cfg.traceWidth/2);

        if layerIndex == 1 && pathIndex == 2
            dB = Inf;
        else
            dB = rectangular_fpc_path_geometry('minimum_distance_point_polyline', padB, path);
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
                centerDistance = rectangular_fpc_path_geometry('minimum_distance_point_polyline_excluding',  ...
                    via.xy, path, false, excludedLength);
            elseif isToPath
                if strcmp(via.role, 'output_return')
                    centerDistance = Inf;
                else
                    centerDistance = rectangular_fpc_path_geometry('minimum_distance_point_polyline_excluding',  ...
                        via.xy, path, true, excludedLength);
                end
            else
                centerDistance = rectangular_fpc_path_geometry('minimum_distance_point_polyline', via.xy, path);
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
            dMin = min(dMin, rectangular_fpc_path_geometry('minimum_distance_point_polyline',  ...
                via.xy, path) - via.drillDiameter/2 - cfg.traceWidth/2);
        end
    end
end
end

function dMin = measureMinDrillToBoardMm(vias, boardXY)

dMin = Inf;
for viaIndex = 1:numel(vias)
    dMin = min(dMin, rectangular_fpc_path_geometry('minimum_distance_point_polyline',  ...
        vias(viaIndex).xy, boardXY) - vias(viaIndex).drillDiameter/2);
end
end

function dMin = measureMinViaToBoardMm(vias, boardXY)

dMin = Inf;
for viaIndex = 1:numel(vias)
    dMin = min(dMin, rectangular_fpc_path_geometry('minimum_distance_point_polyline',  ...
        vias(viaIndex).xy, boardXY) - vias(viaIndex).padDiameter/2);
end
end

%% =========================================================
