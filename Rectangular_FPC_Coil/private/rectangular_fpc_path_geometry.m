function varargout = rectangular_fpc_path_geometry(operation, varargin)
%RECTANGULAR_FPC_PATH_GEOMETRY Shared polyline and coordinate primitives.

switch operation
    case 'normalize_layers'
        [varargout{1:nargout}] = normalizeLayerPaths(varargin{:});
    case 'user_to_internal'
        [varargout{1:nargout}] = userToInternalXY(varargin{:});
    case 'internal_to_user'
        [varargout{1:nargout}] = internalToUserXY(varargin{:});
    case 'remove_duplicates'
        [varargout{1:nargout}] = removeDuplicatePoints(varargin{:});
    case 'remove_zero_length'
        [varargout{1:nargout}] = removeZeroLengthSegments(varargin{:});
    case 'has_zero_length'
        [varargout{1:nargout}] = anyZeroLengthSegments(varargin{:});
    case 'path_length'
        [varargout{1:nargout}] = calculatePathLength(varargin{:});
    case 'candidate_compliant'
        [varargout{1:nargout}] = candidateCompliant(varargin{:});
    case 'minimum_open_angle'
        [varargout{1:nargout}] = minimumOpenPolylineInteriorAngle(varargin{:});
    case 'minimum_closed_angle'
        [varargout{1:nargout}] = minimumClosedPolylineInteriorAngle(varargin{:});
    case 'self_intersection'
        [varargout{1:nargout}] = checkPolylineSelfIntersectionExact(varargin{:});
    case 'minimum_nonadjacent_distance'
        [varargout{1:nargout}] = calculateMinimumNonAdjacentDistance(varargin{:});
    case 'flatten_layers'
        [varargout{1:nargout}] = flattenLayerPaths(varargin{:});
    case 'minimum_distance_polylines'
        [varargout{1:nargout}] = minimumDistanceBetweenPolylines(varargin{:});
    case 'minimum_distance_point_polyline'
        [varargout{1:nargout}] = minimumDistancePointToPolyline(varargin{:});
    case 'minimum_distance_point_polyline_excluding'
        [varargout{1:nargout}] = minimumDistancePointToPolylineExcludingLength(varargin{:});
    otherwise
        error('RectangularFPC:UnknownPathGeometryOperation', ...
            'Unknown path geometry operation: %s', operation);
end
end

function [layerXY, layerPaths] = normalizeLayerPaths( ...
    layerXY, layerPaths, tol)

for layerIndex = 1:numel(layerPaths)
    for pathIndex = 1:numel(layerPaths{layerIndex})
        layerPaths{layerIndex}{pathIndex} = removeDuplicatePoints( ...
            layerPaths{layerIndex}{pathIndex}, tol);
        layerPaths{layerIndex}{pathIndex} = removeZeroLengthSegments( ...
            layerPaths{layerIndex}{pathIndex}, tol);
    end
    layerXY{layerIndex} = layerPaths{layerIndex}{1};
end

end

function xyInternal = userToInternalXY(xyUser, cfg)
%USERTOINTERNALXY 将用户坐标（主体左下角原点）转换为内部坐标（主体中心原点）。
%   XYINTERNAL = USERTOINTERNALXY(XYUSER, CFG)
%   用户坐标系：主体接骨板左下角为 (0,0)，+X 朝右（右侧尾板），+Y 朝上。
%   内部坐标系：主体几何中心为原点，+X 朝右，+Y 朝上。
xyInternal = xyUser - [cfg.plateLength/2, cfg.plateWidth/2];
end

function xyUser = internalToUserXY(xyInternal, cfg)
%INTERNALTOUSERXY 将内部坐标（主体中心原点）转换为用户坐标（主体左下角原点）。
%   XYUSER = INTERNALTOUSERXY(XYINTERNAL, CFG)
xyUser = xyInternal + [cfg.plateLength/2, cfg.plateWidth/2];
end

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

function len = calculatePathLength(xy)

% 防御：空或非 Nx2 输入按 0 处理（正常路径始终为 Nx2）。
if isempty(xy) || size(xy, 2) ~= 2
    len = 0;
    return;
end
len = sum(hypot(diff(xy(:,1)), diff(xy(:,2))));

end

function pass = candidateCompliant(basePath, candidate, mode, boardXY, cfg)

tol = cfg.geometryTolerance;
pass = false;
if isempty(candidate) || size(candidate, 2) ~= 2 || ...
        size(candidate, 1) < 2 || any(~isfinite(candidate), 'all') || ...
        anyZeroLengthSegments(candidate, tol)
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
