function varargout = rectangular_fpc_board_geometry(operation, varargin)
%RECTANGULAR_FPC_BOARD_GEOMETRY Board outline construction primitives.

switch operation
    case 'board_outline'
        [varargout{1:nargout}] = generateSmoothBoardOutline(varargin{:});
    case 'perimeter'
        [varargout{1:nargout}] = roundedRectPerimeter(varargin{:});
    otherwise
        error('RectangularFPC:UnknownBoardGeometryOperation', ...
            'Unknown board geometry operation: %s', operation);
end
end

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
    error('RectangularFPC:BoardGeometryFailed', ...
        'tabTransitionRadius必须大于0。');
end

if tabHalfWidth + 2*transitionRadius > hy + tol
    error('RectangularFPC:BoardGeometryFailed', ...
        'tabTransitionRadius过大，无法保持在主体上下边界内。');
end

bodyTopRightCenter = [hx-R, hy-R];
bodyBottomRightCenter = [hx-R, -hy+R];

dyTop = tabHalfWidth + transitionRadius - (hy-R);
distTransition = R + transitionRadius;

if abs(dyTop) >= distTransition - tol
    error('RectangularFPC:BoardGeometryFailed', ...
        'tabTransitionRadius无法与主体右上圆角形成相切过渡。');
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
    error('RectangularFPC:BoardGeometryFailed', ...
        'tabTransitionRadius过大或tabLength过短，过渡圆弧会越过尾部外圆角。');
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
outlineXY = rectangular_fpc_path_geometry('remove_duplicates', outlineXY, tol);
outlineXY = rectangular_fpc_path_geometry('remove_zero_length', outlineXY, tol);

if norm(outlineXY(end,:) - outlineXY(1,:)) < tol
    outlineXY(end,:) = [];
end

if size(outlineXY,1) < 12
    error('RectangularFPC:BoardGeometryFailed', ...
        '生成的板框点数异常。');
end

if any(~isfinite(outlineXY), 'all')
    error('RectangularFPC:BoardGeometryFailed', ...
        '生成的板框包含无效坐标。');
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
