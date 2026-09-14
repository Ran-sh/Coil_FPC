function varargout = Copper_Outline(operation, varargin)
%COPPER_OUTLINE Closed 2D copper outlines for the COMSOL-oriented DXF export.
%   矩形线圈的中线折线（主螺旋，以及逃逸/过孔/端子引线）按半个线宽向两侧
%   偏置，端部用一条垂直于端点切向的直线端帽封口，得到 COMSOL 2D 可以直接
%   选成域（domain）的闭合轮廓。DXF 的 group-43 常量线宽只是"可变宽线"的
%   显示元数据，2D DXF 导入器不会可靠地把它变成面，因此这里显式写出闭合
%   多段线，而不是依赖线宽。
%
%   与 CircularFPC 的同名能力保持同一套算法与常量：polybuffer 缓冲 +
%   端部圆帽拉平 + RDP 简化（5 µm，远小于 0.2 mm 线宽）。任何一条中线缓冲
%   不出"恰好一个环、单连通、无孔"的轮廓时一律 fail closed（抛
%   RectangularFPC:ExportWriteFailed），绝不写出几何上不成立的轮廓。
%
%   偏置在折角处按 polybuffer 的圆角连接生成（半径 = 半个线宽），与蚀刻铜箔
%   的实际圆角一致；这不是走线的"制造参考轮廓"——真正的制造参考仍是
%   dxf/Ln/NN_copper_physical_Ln.dxf。
%
%   操作：
%     'coil_rings'      (spiralXY, traceWidth)
%         只含主螺旋的闭合环：不含引线、焊盘、过孔。
%     'conductor_rings' (layerPaths, traceWidth)
%         该层全部导体中线（螺旋 + 本层引线）的闭合环，每条路径一个环。
%     'area'            (ring)
%         闭合环的鞋带面积（mm^2），供导出校验比较"合并后必须更大"。

switch operation
    case 'coil_rings'
        varargout{1} = {singleRing(varargin{1}, varargin{2}, 'coil')};
    case 'conductor_rings'
        varargout{1} = buildLayerRings(varargin{1}, varargin{2});
    case 'area'
        varargout{1} = ringArea(varargin{1});
    otherwise
        error('RectangularFPC:UnknownGeometryOperation', ...
            'Unknown copper-outline operation: %s', operation);
end
end

%% =========================================================
function rings = buildLayerRings(layerPaths, traceWidth)
% 一层内每条存储路径各自成一个闭合环。矩形线圈层内导体本来就是一条连续
% 折线（螺旋与引线共用端点），所以不像 CircularFPC 那样需要并集合并：
% L1 的回程引线（VOUT → PAD_B）是与主链不相连的第二条路径，因此 L1 有两个环，
% 其余层各一个。

rings = cell(numel(layerPaths), 1);
for pathIndex = 1:numel(layerPaths)
    rings{pathIndex} = singleRing(layerPaths{pathIndex}, traceWidth, ...
        sprintf('layer path %d', pathIndex));
end
end

%% =========================================================
function ring = singleRing(xy, traceWidth, label)
% 一条中线 → 恰好一个闭合环。缓冲出多个环或带孔环说明该路径自相接触，
% 轮廓在 2D 上就不是单连通域，此时宁可报错。

candidates = bufferedRings(xy, traceWidth);
if numel(candidates) ~= 1
    error('RectangularFPC:ExportWriteFailed', ...
        ['COMSOL solid copper must buffer into exactly one closed ring per ' ...
         'centerline (%s produced %d rings).'], label, numel(candidates));
end
ring = candidates{1};
end

%% =========================================================
function rings = bufferedRings(xy, traceWidth)
% Return closed polygon rings for one buffered open centerline. polybuffer is
% part of MATLAB's polyshape functionality in the supported R2026a runtime.

halfWidth = traceWidth / 2;
rings = {};
if size(xy, 2) ~= 2 || size(xy, 1) < 2
    return;
end
xy = double(xy);
keep = [true; vecnorm(diff(xy, 1, 1), 2, 2) > 1e-12];
xy = xy(keep, :);
if size(xy, 1) < 2
    return;
end
buffered = polybuffer(xy, 'lines', halfWidth);
[bx, by] = boundary(buffered);
if isempty(bx)
    return;
end
start = 1;
for k = 1:(numel(bx) + 1)
    isBreak = k > numel(bx) || isnan(bx(k)) || isnan(by(k));
    if ~isBreak
        continue;
    end
    if k - start >= 3
        ring = [bx(start:k - 1), by(start:k - 1)];
        if size(ring, 1) >= 2 && norm(ring(1, :) - ring(end, :)) <= 1e-10
            ring(end, :) = [];
        end
        if size(ring, 1) >= 3
            if norm(xy(1, :) - xy(end, :)) > 1e-10
                ring = flattenEndCaps(ring, xy, halfWidth);
            end
            ring = simplifyClosedRing(ring, 0.005);
            ring = closeRing(ring);
            requireSingleRegion(ring);
            rings{end + 1} = ring; %#ok<AGROW>
        end
    end
    start = k + 1;
end
end

%% =========================================================
function ring = flattenEndCaps(ring, xy, halfWidth)
% Replace each local semicircular cap of a buffered open path with a flat
% segment. Points farther than the cap radius are never modified, so other
% turns of the spiral remain untouched. Straight caps (never round end arcs)
% keep both ends explicit for a COMSOL importer.

tol = 1e-7;
if size(xy, 1) < 2
    return;
end
startDirection = xy(2, :) - xy(1, :);
startDirection = startDirection / norm(startDirection);
endDirection = xy(end, :) - xy(end - 1, :);
endDirection = endDirection / norm(endDirection);
startDelta = ring - xy(1, :);
startProjection = startDelta * startDirection.';
startDistanceSquared = sum(startDelta .^ 2, 2);
startLocal = startProjection < -tol & ...
    startDistanceSquared <= (halfWidth + tol) ^ 2;
ring(startLocal, :) = ring(startLocal, :) - ...
    startProjection(startLocal) .* startDirection;
endDelta = ring - xy(end, :);
endProjection = endDelta * endDirection.';
endDistanceSquared = sum(endDelta .^ 2, 2);
endLocal = endProjection > tol & ...
    endDistanceSquared <= (halfWidth + tol) ^ 2;
ring(endLocal, :) = ring(endLocal, :) - ...
    endProjection(endLocal) .* endDirection;
end

%% =========================================================
function ring = closeRing(points)
% 显式重复首顶点，让 2D DXF 导入器拿到一条真正闭合的边界；同时清掉相邻
% 重合点，避免下游 polyshape/DXF 读出"顶点近乎重复"。

if size(points, 1) > 1 && norm(points(1, :) - points(end, :)) <= 1e-10
    points(end, :) = [];
end
keep = [true; vecnorm(diff(points, 1, 1), 2, 2) > 1e-7];
points = points(keep, :);
if size(points, 1) < 3
    error('RectangularFPC:ExportWriteFailed', ...
        'COMSOL solid copper ring collapsed to fewer than three vertices.');
end
ring = [points; points(1, :)];
end

%% =========================================================
function requireSingleRegion(ring)
% fail closed：写出前确认这条轮廓就是一个单连通、无孔的域。

[px, py] = explodeRing(ring);
poly = [];
try
    poly = polyshape(px, py, 'Simplify', false);
catch ME
    error('RectangularFPC:ExportWriteFailed', ...
        'COMSOL solid copper ring is not a valid polygon: %s', ME.message);
end
if poly.NumRegions ~= 1 || poly.NumHoles ~= 0
    error('RectangularFPC:ExportWriteFailed', ...
        ['COMSOL solid copper must stay one hole-free region per ring ' ...
         '(got %d region(s), %d hole(s)).'], poly.NumRegions, poly.NumHoles);
end
end

%% =========================================================
function [x, y] = explodeRing(ring)
% 去掉闭合重复点与相邻重合点后再交给 polyshape。缓冲轮廓来自折线采样，
% 相邻点可到 1e-9 量级，直接构造会让 polyshape 报"顶点近乎重复"。

xy = ring;
if size(xy, 1) > 1 && norm(xy(1, :) - xy(end, :)) <= 1e-12
    xy(end, :) = [];
end
keep = [true; vecnorm(diff(xy, 1, 1), 2, 2) > 1e-7];
xy = xy(keep, :);
x = xy(:, 1);
y = xy(:, 2);
end

%% =========================================================
function reduced = simplifyClosedRing(points, tolerance)
% Iterative Ramer-Douglas-Peucker simplification for a closed polygon. The
% tolerance is in mm and stays far below the 0.2 mm copper width, so this only
% removes redundant sampled points while keeping the outline within 5 µm of
% the buffered geometry.

if size(points, 1) < 4
    reduced = points;
    return;
end
closed = [points; points(1, :)];
n = size(closed, 1);
keep = false(n, 1);
keep([1, n]) = true;
stack = [1, n];
while ~isempty(stack)
    j = stack(end);
    i = stack(end - 1);
    stack(end - 1:end) = [];
    if j <= i + 1
        continue;
    end
    p0 = closed(i, :);
    p1 = closed(j, :);
    segment = p1 - p0;
    segmentLengthSquared = dot(segment, segment);
    candidates = (i + 1):(j - 1);
    delta = closed(candidates, :) - p0;
    if segmentLengthSquared <= eps
        distances = sqrt(sum(delta .^ 2, 2));
    else
        projection = (delta * segment.') / segmentLengthSquared;
        projection = max(0, min(1, projection));
        nearest = p0 + projection .* segment;
        distances = sqrt(sum((closed(candidates, :) - nearest) .^ 2, 2));
    end
    [maxDistance, relativeIndex] = max(distances);
    if maxDistance > tolerance
        split = candidates(relativeIndex);
        keep(split) = true;
        stack = [stack, i, split, split, j]; %#ok<AGROW>
    end
end
reduced = closed(keep, :);
if size(reduced, 1) >= 2 && norm(reduced(1, :) - reduced(end, :)) <= 1e-10
    reduced(end, :) = [];
end
end

%% =========================================================
function a = ringArea(ring)
% Shoelace area of a ring whose first vertex repeats as the last one.

x = ring(1:end-1, 1);
y = ring(1:end-1, 2);
a = abs(sum(x .* y([2:end, 1]) - y .* x([2:end, 1]))) / 2;
end
