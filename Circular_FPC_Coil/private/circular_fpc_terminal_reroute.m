function result = circular_fpc_terminal_reroute(cfg, result)
% CIRCULAR_FPC_TERMINAL_REROUTE
% Auto-mode terminal post-router for the circular FPC generator.
%
% New deterministic terminal contract:
%   d = cfg.terminalLeadSpacing
%   L = cfg.terminalLeadLength
%
% In the local connection frame (u = radial axis, t = transverse axis):
%   PAD_A -- straight L --> one >90-deg tangent arc --> L1 inner endpoint
%   last active layer --> one >90-deg tangent arc --> VOUT -- straight L --> PAD_B
%
% PAD_A/PAD_B are therefore fixed by d and L.  Manual terminal placement is
% intentionally left unchanged.

if strcmp(cfg.terminalPlacementMode, 'manual')
    return;
end

u = [cosd(cfg.connectionAngleDeg), sind(cfg.connectionAngleDeg)];
t = [-sind(cfg.connectionAngleDeg), cosd(cfg.connectionAngleDeg)];
d = cfg.terminalLeadSpacing;
L = cfg.terminalLeadLength;

minPadPitch = cfg.padDiameter + cfg.terminalClearance;
if d < minPadPitch - 1e-9
    error('CircularFPC:TerminalPlacementInvalid', ...
        'terminalLeadSpacing %.6f mm is too small; PAD_A/PAD_B require at least %.6f mm.', ...
        d, minPadPitch);
end
minExitLength = cfg.padDiameter/2 + cfg.viaPadDiameter/2 + cfg.terminalClearance;
if L < minExitLength - 1e-9
    error('CircularFPC:TerminalPlacementInvalid', ...
        'terminalLeadLength %.6f mm is too small; VOUT-to-PAD_B requires at least %.6f mm.', ...
        L, minExitLength);
end

active = result.activeCoilLayers;
firstLi = active(1);
lastLi = active(end);
coil1 = result.layerPaths(firstLi).coilXY;
if size(coil1, 1) < 3
    error('CircularFPC:TerminalPlacementInvalid', 'L1 active coil geometry is missing.');
end
oldSIn = coil1(1, :);
entryPhaseOffsetDeg = 0;
sIn = coil1(1, :);

oldPadA = result.pads(strcmp({result.pads.name}, 'PAD_A')).xy;
oldPadB = result.pads(strcmp({result.pads.name}, 'PAD_B')).xy;
oldVout = result.vias(strcmp({result.vias.name}, 'VOUT')).xy;

% Input lane: Q_A is the tangent point at the end of the straight section.
% Preserve the Archimedean coil exactly. Its sampled endpoint tangent and
% the radial lead direction uniquely define one tangent circular arc.
entryTangent = unitVector(coil1(2, :) - coil1(1, :), 'L1 entry tangent');
[entryArc, qA, entryBendRadius, entrySweepDeg] = tangentArcEndingAtLane( ...
    sIn, u, entryTangent, t, -d / 2, 49);
padA = qA - L * u;
entryPath = [sampleSegment(padA, qA, 0.05); entryArc(2:end, :)];
entryPath(1, :) = padA;
entryPath(end, :) = sIn;

% Output lane uses the opposite transverse offset.  For multilayer designs
% the final active coil ends at the same inner phase as L1.  4/4 previously
% appended a Bezier stub to VOUT inside coilXY; trim that stub first.
outputPath = [];
outputBendRadius = NaN;
outputSweepDeg = NaN;
outputPhaseOffsetDeg = 0;
if numel(active) > 1
    lastCoil = result.layerPaths(lastLi).coilXY;
    oldLastEnd = lastCoil(end, :);
    rStart = result.effectiveDimensions.coilInnerDiameter/2 + cfg.traceWidth/2;
    lastCoil = trimInnerStub(lastCoil, rStart);
    result.layerPaths(lastLi).coilXY = lastCoil;
    sOut = lastCoil(end, :);
    outputTangent = unitVector(lastCoil(end, :) - lastCoil(end - 1, :), ...
        'last active layer output tangent');
    [outputPath, voutXY, outputBendRadius, outputSweepDeg] = ...
        tangentArcStartingAtLane(sOut, outputTangent, -u, t, d / 2, 49);
else
    % Single-coil variants return on the opposite physical layer.  Keep the
    % same PAD geometry and place VOUT on the positive lane; the return path
    % is re-terminated to this point below.
    voutXY = dot(qA, u) * u + (d / 2) * t;
end
padB = voutXY - L * u;
exitPath = sampleSegment(voutXY, padB, 0.05);
terminalSweepFloor = 90 + cfg.angleToleranceDeg;
if entrySweepDeg <= terminalSweepFloor || ...
        (numel(active) > 1 && outputSweepDeg <= terminalSweepFloor)
    error('CircularFPC:TerminalPlacementInvalid', ...
        'Single terminal bends must be strictly greater than %.6f deg.', terminalSweepFloor);
end

% Both pad disks must remain wholly on the positive entry side of the coil.
% Otherwise increasing L silently pulls the pads through the centre and
% reverses the intended PAD_A/PAD_B/VOUT arrangement.
sideFloor = cfg.padDiameter / 2;
minPadProjection = min(dot(padA, u), dot(padB, u));
if minPadProjection <= sideFloor + 1e-9
    maxLeadLength = min(dot(qA, u), dot(voutXY, u)) - sideFloor;
    error('CircularFPC:TerminalPlacementInvalid', ...
        ['terminalLeadLength %.6f mm moves a pad across the positive entry-side ', ...
         'boundary; maximum for this d/geometry is %.6f mm.'], L, maxLeadLength);
end

% Update terminal coordinates.
idxA = find(strcmp({result.pads.name}, 'PAD_A'), 1);
idxB = find(strcmp({result.pads.name}, 'PAD_B'), 1);
idxV = find(strcmp({result.vias.name}, 'VOUT'), 1);
result.pads(idxA).xy = padA;
result.pads(idxB).xy = padB;
result.vias(idxV).xy = voutXY;

% Replace L1 entry and exit paths by endpoint identity.
paths1 = result.layerPaths(1).connectionPaths;
[paths1, foundEntry] = replacePath(paths1, oldPadA, oldSIn, entryPath);
[paths1, foundExit] = replacePath(paths1, oldVout, oldPadB, exitPath);
if ~foundEntry
    paths1{end+1} = entryPath;
end
if ~foundExit
    paths1{end+1} = exitPath;
end
result.layerPaths(1).connectionPaths = paths1;

if numel(active) > 1
    pathsLast = result.layerPaths(lastLi).connectionPaths;
    [pathsLast, foundOut] = replacePath(pathsLast, oldLastEnd, oldVout, outputPath);
    if ~foundOut
        % 4/4 old topology embedded the VOUT stub in coilXY, so after trim
        % there is no standalone TRACE_L4_OUT to replace.
        pathsLast{end+1} = outputPath;
    end
    result.layerPaths(lastLi).connectionPaths = pathsLast;
else
    retLi = result.returnLayer;
    vret = result.vias(strcmp({result.vias.name}, 'VRET'));
    retPath = sampleSegment(vret.xy, voutXY, 0.08);
    pathsRet = result.layerPaths(retLi).connectionPaths;
    [pathsRet, foundRet] = replacePath(pathsRet, vret.xy, oldVout, retPath);
    if ~foundRet
        pathsRet{end+1} = retPath;
    end
    result.layerPaths(retLi).connectionPaths = pathsRet;
end

% Rebuild route endpoints so the continuity validator sees the new network.
route = result.seriesRoute;
for k = 1:numel(route)
    switch route(k).name
        case 'PAD_A'
            route(k).startXY = padA; route(k).endXY = padA;
        case 'PAD_B'
            route(k).startXY = padB; route(k).endXY = padB;
        case 'TRACE_L1_ENTRY'
            route(k).startXY = padA; route(k).endXY = sIn;
        case 'VOUT'
            route(k).startXY = voutXY; route(k).endXY = voutXY;
        case 'TRACE_L1_EXIT'
            route(k).startXY = voutXY; route(k).endXY = padB;
    end
end
idxFirstCoil = find(strcmp({route.name}, sprintf('COIL_L%d', firstLi)), 1);
if ~isempty(idxFirstCoil)
    route(idxFirstCoil).startXY = sIn;
end

if numel(active) > 1
    lastName = sprintf('COIL_L%d', lastLi);
    idxCoil = find(strcmp({route.name}, lastName), 1);
    if ~isempty(idxCoil)
        route(idxCoil).endXY = result.layerPaths(lastLi).coilXY(end, :);
    end
    outName = sprintf('TRACE_L%d_OUT', lastLi);
    idxOut = find(strcmp({route.name}, outName), 1);
    idxVoutRoute = find(strcmp({route.name}, 'VOUT'), 1);
    if isempty(idxOut)
        newRoute = routeTemplate(outName, 'TRACE', result.layerPaths(lastLi).coilXY(end, :), ...
            voutXY, lastLi, lastLi);
        route = [route(1:idxVoutRoute-1), newRoute, route(idxVoutRoute:end)]; %#ok<AGROW>
    else
        route(idxOut).startXY = result.layerPaths(lastLi).coilXY(end, :);
        route(idxOut).endXY = voutXY;
    end
else
    retName = sprintf('RETURN_L%d', result.returnLayer);
    idxRet = find(strcmp({route.name}, retName), 1);
    if ~isempty(idxRet)
        route(idxRet).endXY = voutXY;
    end
end
result.seriesRoute = route;
result.seriesSequence = buildSeriesSequence(route);

% The engine sizes the board before this deterministic post-route exists.
% Close auto sizing over the final copper envelope and regenerate the board
% loops if d/L moved any terminal or route farther out than the base network.
result = closeAutoBoardAroundFinalCopper(cfg, result);

% Re-run the same result/manufacturing checks used by the engine after the
% post-route change, so invalid d/L values can never be exported.
coils = cell(1, cfg.boardLayerCount);
connectionPaths = cell(1, cfg.boardLayerCount);
for li = 1:cfg.boardLayerCount
    coils{li} = result.layerPaths(li).coilXY;
    connectionPaths{li} = result.layerPaths(li).connectionPaths;
end
geom = struct('boardLoops', result.boardLoops, ...
    'actualBridgeWidth', result.effectiveDimensions.actualBridgeWidth, ...
    'coils', {coils}, 'connectionPaths', {connectionPaths}, ...
    'pads', result.pads, 'vias', result.vias, ...
    'seriesRoute', result.seriesRoute, 'activeLayers', active);
validation = circular_fpc_validation('validate_result', cfg, result.effectiveDimensions, geom);
if ~validation.passed
    error('CircularFPC:ValidationFailed', ...
        'Single-bend terminal routing failed validation: %s', strjoin(validation.messages, '; '));
end
manufacturing = circular_fpc_manufacturing('check_result', cfg, validation);
if ~manufacturing.passed
    error('CircularFPC:ValidationFailed', ...
        'Single-bend terminal routing failed manufacturing checks: %s', strjoin(manufacturing.failures, '; '));
end
if isfield(result.validation, 'advisories')
    validation.advisories = result.validation.advisories;
else
    validation.advisories = {};
end
result.validation = validation;
result.manufacturing = manufacturing;

[result.totalTraceLengthMm, result.estimatedDcResistanceOhm] = recomputeLengthAndResistance(cfg, result.layerPaths);
result.terminalRouting = struct( ...
    'mode', 'single_bend_parallel_leads', ...
    'leadSpacingMm', d, ...
    'leadLengthMm', L, ...
    'bendRadiusMm', entryBendRadius, ... % compatibility alias for entry radius
    'entryBendRadiusMm', entryBendRadius, ...
    'outputBendRadiusMm', outputBendRadius, ...
    'entrySweepDeg', entrySweepDeg, ...
    'outputSweepDeg', outputSweepDeg, ...
    'entryPhaseOffsetDeg', entryPhaseOffsetDeg, ...
    'outputPhaseOffsetDeg', outputPhaseOffsetDeg, ...
    'padAXY', padA, ...
    'padBXY', padB, ...
    'voutXY', voutXY, ...
    'entryPath', entryPath, ...
    'outputPath', outputPath, ...
    'exitPath', exitPath, ...
    'entryBendCount', 1, ...
    'outputBendCount', double(numel(active) > 1), ...
    'exitBendCount', 0);
result.config = cfg;
end

function result = closeAutoBoardAroundFinalCopper(cfg, result)
if ~strcmp(cfg.boardSizingMode, 'auto')
    return;
end
maxCopperR = 0;
for li = 1:numel(result.layerPaths)
    xy = result.layerPaths(li).coilXY;
    if ~isempty(xy)
        maxCopperR = max(maxCopperR, max(sqrt(sum(xy.^2, 2))) + cfg.traceWidth / 2);
    end
    for k = 1:numel(result.layerPaths(li).connectionPaths)
        xy = result.layerPaths(li).connectionPaths{k};
        if ~isempty(xy)
            maxCopperR = max(maxCopperR, max(sqrt(sum(xy.^2, 2))) + cfg.traceWidth / 2);
        end
    end
end
for k = 1:numel(result.pads)
    maxCopperR = max(maxCopperR, norm(result.pads(k).xy) + result.pads(k).diameter / 2);
end
for k = 1:numel(result.vias)
    maxCopperR = max(maxCopperR, norm(result.vias(k).xy) + result.vias(k).padDiameter / 2);
end
requiredDiameter = 2 * (maxCopperR + cfg.edgeClearance + cfg.boardOutlineLineWidth / 2);
if requiredDiameter <= result.effectiveDimensions.boardOuterDiameter + 1e-9
    return;
end
eff = result.effectiveDimensions;
eff.boardOuterDiameter = requiredDiameter;
circular_fpc_validation('validate_feasibility', cfg, eff);
[boardLoops, actualBridgeWidth, layoutRegions] = circular_fpc_geometry('board', cfg, eff);
eff.actualBridgeWidth = actualBridgeWidth;
result.effectiveDimensions = eff;
result.boardLoops = boardLoops;
result.layoutRegions = layoutRegions;
end

function [arc, startPoint, radius, sweepDeg] = tangentArcEndingAtLane( ...
        endPoint, startTangent, endTangent, laneNormal, laneValue, n)
startTangent = unitVector(startTangent, 'entry arc start tangent');
endTangent = unitVector(endTangent, 'entry arc end tangent');
sweepDeg = positiveTurnDeg(startTangent, endTangent);
[displacement, startNormal] = leftTurnDisplacement(startTangent, endTangent);
denom = dot(displacement, laneNormal);
radius = (dot(endPoint, laneNormal) - laneValue) / denom;
if ~isfinite(radius) || radius <= 0 || sweepDeg <= 90
    error('CircularFPC:TerminalPlacementInvalid', ...
        'Entry tangent arc is infeasible (R=%.6f, sweep=%.6f deg).', radius, sweepDeg);
end
startPoint = endPoint - radius * displacement;
center = startPoint + radius * startNormal;
arc = sampleLeftTurnArc(startPoint, center, sweepDeg, n);
arc(1, :) = startPoint;
arc(end, :) = endPoint;
end

function [arc, endPoint, radius, sweepDeg] = tangentArcStartingAtLane( ...
        startPoint, startTangent, endTangent, laneNormal, laneValue, n)
startTangent = unitVector(startTangent, 'output arc start tangent');
endTangent = unitVector(endTangent, 'output arc end tangent');
sweepDeg = positiveTurnDeg(startTangent, endTangent);
[displacement, startNormal] = leftTurnDisplacement(startTangent, endTangent);
denom = dot(displacement, laneNormal);
radius = (laneValue - dot(startPoint, laneNormal)) / denom;
if ~isfinite(radius) || radius <= 0 || sweepDeg <= 90
    error('CircularFPC:TerminalPlacementInvalid', ...
        'Output tangent arc is infeasible (R=%.6f, sweep=%.6f deg).', radius, sweepDeg);
end
endPoint = startPoint + radius * displacement;
center = startPoint + radius * startNormal;
arc = sampleLeftTurnArc(startPoint, center, sweepDeg, n);
arc(1, :) = startPoint;
arc(end, :) = endPoint;
end

function [displacement, startNormal] = leftTurnDisplacement(startTangent, endTangent)
startNormal = [-startTangent(2), startTangent(1)];
endNormal = [-endTangent(2), endTangent(1)];
displacement = startNormal - endNormal;
end

function arc = sampleLeftTurnArc(startPoint, center, sweepDeg, n)
v0 = startPoint - center;
angles = deg2rad(sweepDeg) * (0:n - 1).' / (n - 1);
c = cos(angles);
s = sin(angles);
rotated = [c * v0(1) - s * v0(2), s * v0(1) + c * v0(2)];
arc = center + rotated;
end

function sweepDeg = positiveTurnDeg(a, b)
a = unitVector(a, 'turn start tangent');
b = unitVector(b, 'turn end tangent');
turn = atan2(a(1) * b(2) - a(2) * b(1), dot(a, b));
if turn <= 0
    turn = turn + 2 * pi;
end
sweepDeg = rad2deg(turn);
if sweepDeg >= 180
    error('CircularFPC:TerminalPlacementInvalid', ...
        'Single terminal bend would require %.6f deg; expected a minor left-turn arc.', sweepDeg);
end
end

function v = unitVector(v, label)
n = norm(v);
if ~isfinite(n) || n <= 1e-12
    error('CircularFPC:TerminalPlacementInvalid', '%s is degenerate.', label);
end
v = v / n;
end

function pts = sampleSegment(p0, p1, spacing)
d = norm(p1 - p0);
ratio = d / spacing;
% Exact multiples such as 1.5/0.05 can land a few ulps above the integer on
% one platform and below it on another. Remove only roundoff-scale excess so
% equivalent geometry always receives the same point count and SVG hash.
ratioTolerance = 64 * eps(max(1, abs(ratio)));
n = max(2, ceil(ratio - ratioTolerance) + 1);
s = linspace(0, 1, n).';
pts = p0 + s * (p1 - p0);
end

function xy = trimInnerStub(xy, rStart)
if isempty(xy)
    return;
end
r = sqrt(sum(xy.^2, 2));
firstInside = find(r < rStart - 1e-5, 1, 'first');
if ~isempty(firstInside) && firstInside > 1
    xy = xy(1:firstInside-1, :);
end
end

function [paths, found] = replacePath(paths, a, b, replacement)
found = false;
for k = 1:numel(paths)
    p = paths{k};
    if isempty(p)
        continue;
    end
    direct = norm(p(1,:) - a) < 1e-4 && norm(p(end,:) - b) < 1e-4;
    reverse = norm(p(1,:) - b) < 1e-4 && norm(p(end,:) - a) < 1e-4;
    if direct || reverse
        if reverse
            paths{k} = flipud(replacement);
        else
            paths{k} = replacement;
        end
        found = true;
        return;
    end
end
end

function r = routeTemplate(name, kind, p0, p1, l0, l1)
r = struct('name', name, 'kind', kind, 'startXY', p0, 'endXY', p1, ...
    'startLayer', l0, 'endLayer', l1);
end

function seq = buildSeriesSequence(route)
keep = true(1, numel(route));
for k = 1:numel(route)
    if strcmp(route(k).kind, 'TRACE') && ~strncmp(route(k).name, 'RETURN_', 7)
        keep(k) = false;
    end
end
seq = {route(keep).name};
end

function [Lmm, Rohm] = recomputeLengthAndResistance(cfg, layerPaths)
Lmm = 0;
for li = 1:numel(layerPaths)
    xy = layerPaths(li).coilXY;
    if ~isempty(xy)
        Lmm = Lmm + sum(sqrt(sum(diff(xy, 1, 1).^2, 2)));
    end
    for k = 1:numel(layerPaths(li).connectionPaths)
        p = layerPaths(li).connectionPaths{k};
        Lmm = Lmm + sum(sqrt(sum(diff(p, 1, 1).^2, 2)));
    end
end
Rohm = cfg.copperResistivity * (Lmm / 1000) / ...
    ((cfg.traceWidth / 1000) * (cfg.copperThickness / 1000));
end
