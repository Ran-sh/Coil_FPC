function varargout = rectangular_fpc_lead_router(operation, varargin)
%RECTANGULAR_FPC_LEAD_ROUTER Smooth and orthogonal lead routing.

switch operation
    case 'smooth_lead'
        [varargout{1:nargout}] = routeSmoothLead(varargin{:});
    case 'orthogonal'
        [varargout{1:nargout}] = routeOrthogonalLeadByPriority(varargin{:});
    case 'through_keepouts'
        [varargout{1:nargout}] = throughViaKeepoutsForLayer(varargin{:});
    otherwise
        error('RectangularFPC:UnknownLeadRouterOperation', ...
            'Unknown lead-router operation: %s', operation);
end
end

function [path, ok, failReason] = routeSmoothLead( ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, tol)
%FPC_COIL_ROUTE_SMOOTH_LEAD Deterministic tangent fillet lead (arc + straight).
%   [PATH, OK, FAILREASON] = FPC_COIL_ROUTE_SMOOTH_LEAD(STARTPT, STARTTANGENT, ...
%   ENDPT, BENDRADIUS, ARCPOINTCOUNT, TOL)
%
%   STARTTANGENT is the exact travel direction at STARTPT. The path is a
%   single fillet arc of radius BENDRADIUS tangent to STARTTANGENT followed by
%   the required straight segment to ENDPT. Semicircle/reversal sweeps
%   (|sweep| >= pi) are rejected. Among valid candidates the shortest
%   arc+straight length wins; ties keep the earlier enumeration order
%   (left turn first, then right turn; negative offset first per side).
%   PATH is Nx2 with PATH(1,:) == STARTPT and PATH(end,:) == ENDPT.

path = [];
ok = false;
failReason = '';

t = startTangent(:)';
tnorm = norm(t);
if tnorm < tol
    failReason = 'zero start tangent';
    return;
end
t = t / tnorm;

v = endPt - startPt;
d = norm(v);
if d < tol
    path = startPt;
    ok = true;
    return;
end
dvec = v / d;

% Start direction and target direction almost aligned: plain straight lead.
if dot(t, dvec) > 1 - 1e-9
    path = [startPt; endPt];
    ok = true;
    return;
end

if bendRadius <= tol
    failReason = 'nonpositive bend radius';
    return;
end

R = bendRadius;
nLeft = [-t(2), t(1)];
bestLen = Inf;
bestPath = [];

for signIndex = 1:2
    if signIndex == 1
        sgn = 1;
    else
        sgn = -1;
    end
    center = startPt + sgn*R*nLeft;
    w = endPt - center;
    dist = norm(w);
    if dist < R - tol
        continue;
    end
    beta = atan2(w(2), w(1));
    ratio = R / dist;
    offset = acos(max(-1, min(1, ratio)));
    thetaStart = atan2(startPt(2) - center(2), startPt(1) - center(1));
    thetaEValues = [beta - offset, beta + offset];
    for offsetIndex = 1:2
        thetaE = thetaEValues(offsetIndex);
        if sgn == 1
            sweep = mod(thetaE - thetaStart, 2*pi);
        else
            sweep = -mod(thetaStart - thetaE, 2*pi);
        end
        if abs(sweep) >= pi - 1e-9 || abs(sweep) <= tol
            continue;
        end
        E = center + R*[cos(thetaE), sin(thetaE)];
        dirToEnd = endPt - E;
        straightLen = norm(dirToEnd);
        pureArc = straightLen <= tol;
        if ~pureArc
            tanEnd = sgn*[-sin(thetaE), cos(thetaE)];
            cosDir = dot(tanEnd, dirToEnd) / straightLen;
            if cosDir <= 1 - 1e-9
                continue;
            end
        end
        nArc = max(2, ceil(arcPointCount*abs(sweep)/(pi/2)) + 1);
        thetaArc = linspace(thetaStart, thetaStart + sweep, nArc)';
        arcXY = center + R*[cos(thetaArc), sin(thetaArc)];
        arcXY(1,:) = startPt;
        if pureArc
            arcXY(end,:) = endPt;
            path = arcXY;
        else
            path = [arcXY; endPt];
        end
        candidateLen = abs(sweep)*R + straightLen;
        if candidateLen < bestLen - tol
            bestLen = candidateLen;
            bestPath = path;
        end
    end
end

if ~isempty(bestPath)
    path = bestPath;
    ok = true;
else
    failReason = 'no under-180-degree tangent candidate';
end

end

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
if rectangular_fpc_path_geometry('candidate_compliant', basePath, direct, mode, boardXY, cfg)
    path = direct;
    ok = true;
    return;
end

[filletPath, filletOk] = rectangular_fpc_lead_router('smooth_lead',  ...
    startPt, startTangent, endPt, bendRadius, arcPointCount, tol);
if filletOk && rectangular_fpc_path_geometry('candidate_compliant', basePath, filletPath, mode, boardXY, cfg)
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
    if ~rectangular_fpc_path_geometry('candidate_compliant', basePath, cand, mode, boardXY, cfg)
        continue;
    end
    candLen = rectangular_fpc_path_geometry('path_length', cand);
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
    basePath, endPt, mode, bendRadius, arcPointCount, boardXY, cfg, ...
    keepoutXY, keepoutRadii)
% Orthogonal lead routing: axial straight, tangent arc plus axial
% straight, and two-arc orthogonal dogleg candidates; every candidate is
% judged by candidateCompliant in priority order.
path = [];
ok = false;
if nargin < 8
    keepoutXY = zeros(0, 2);
    keepoutRadii = zeros(0, 1);
end

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
        lengths(k) = rectangular_fpc_path_geometry('path_length', candidates{candidateIndices(k)});
    end
    order = sortrows([lengths, candidateIndices(:)], [1, 2]);
    for k = 1:size(order, 1)
        cand = candidates{order(k, 2)};
        if rectangular_fpc_path_geometry('candidate_compliant', basePath, cand, mode, boardXY, cfg) && ...
                pathClearsKeepouts(cand, keepoutXY, keepoutRadii, ...
                cfg.geometryTolerance)
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

function [xy, radii] = throughViaKeepoutsForLayer(vias, layerIndex, cfg)
if isempty(vias)
    xy = zeros(0, 2);
    radii = zeros(0, 1);
    return
end
isKeepout = arrayfun(@(via) ...
    strcmp(via.type, 'through_via') && ...
    ~ismember(layerIndex, via.connectedLayers), vias);
selected = vias(isKeepout);
if isempty(selected)
    xy = zeros(0, 2);
    radii = zeros(0, 1);
    return
end
xy = vertcat(selected.xy);
radii = [selected.antipadDiameter].' / 2 + cfg.traceWidth / 2;
end

function clears = pathClearsKeepouts(path, keepoutXY, keepoutRadii, tol)
clears = true;
for keepoutIndex = 1:size(keepoutXY, 1)
    distance = inf;
    for segmentIndex = 1:size(path, 1) - 1
        distance = min(distance, distancePointToSegment( ...
            keepoutXY(keepoutIndex, :), path(segmentIndex, :), ...
            path(segmentIndex + 1, :)));
    end
    if distance < keepoutRadii(keepoutIndex) - tol
        clears = false;
        return
    end
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

function [path, ok] = routeViaWaypoint( ...
    startPt, startTangent, waypoint, endPt, bendRadius, arcPointCount, tol)
% Two-leg route: start -> waypoint along startTangent, then along the actual
% end direction of the first leg to endPt. No early skip between waypoints.
path = [];
ok = false;

[path1, ok1] = rectangular_fpc_lead_router('smooth_lead',  ...
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
[path2, ok2] = rectangular_fpc_lead_router('smooth_lead',  ...
    waypoint, lastDir, endPt, bendRadius, arcPointCount, tol);
if ~ok2
    return;
end
path = [path1; path2(2:end, :)];
ok = true;

end

%% =========================================================

function d = distancePointToSegment(p, a, b)
v = b - a;
w = p - a;
c = max(0, min(1, dot(w, v)/dot(v, v)));
d = norm(w - c*v);
end
