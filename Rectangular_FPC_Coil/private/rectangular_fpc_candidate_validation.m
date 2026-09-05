function varargout = rectangular_fpc_candidate_validation(operation, varargin)
%RECTANGULAR_FPC_CANDIDATE_VALIDATION Turn-candidate qualification.

switch operation
    case 'candidate'
        [varargout{1:nargout}] = isCandidateGeometryValid(varargin{:});
    otherwise
        error('RectangularFPC:UnknownCandidateValidationOperation', ...
            'Unknown candidate-validation operation: %s', operation);
end
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
    expectedFeasibilityErrors = { ...
        'RectangularFPC:RoutingFailed', ...
        'RectangularFPC:ViaPlanningFailed'};
    if ismember(ME.identifier, expectedFeasibilityErrors)
        reason = ME.message;
        return;
    end
    rethrow(ME);
end

[topologyPass, topologyIssues] = ...
    rectangular_fpc_validation_report('electrical_topology', cfg, d, layerPaths, vias);
if ~topologyPass
    reason = strjoin(topologyIssues, '; ');
    return;
end

if cfg.requireSmoothLeadTransitions && escapeArcFallback
    reason = '逃逸引线无法生成平滑圆弧，将回退为90度尖角';
    return;
end

candidatePaths = rectangular_fpc_path_geometry('flatten_layers', layerPaths);
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
                rectangular_fpc_path_geometry('minimum_open_angle', path, tol) <= ...
                cfg.minCopperInteriorAngleDeg + cfg.angleToleranceDeg
            minAng = rectangular_fpc_path_geometry('minimum_open_angle', path, tol);
            reason = sprintf('L%d路径%d铜线角度不足（最小内角 %.3f°）', ...
                k, pathIndex, minAng);
            return;
        end
        if cfg.enableExactSelfIntersectionCheck && ...
                rectangular_fpc_path_geometry('self_intersection', path, false, cfg)
            reason = sprintf('L%d路径%d存在自相交', k, pathIndex);
            return;
        end
        if cfg.enableCopperClearanceCheck
            [~, spacingPass] = rectangular_fpc_path_geometry('minimum_nonadjacent_distance',  ...
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
                pathDistance = rectangular_fpc_path_geometry('minimum_distance_polylines',  ...
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
    if ~rectangular_fpc_design_checks('pad_to_board', d.padA, d.padB, closedBoardXY, cfg, tol)
        reason = '焊盘未完整位于板框内';
        return;
    end
    if ~rectangular_fpc_design_checks('pad_to_pad', d.padA, d.padB, cfg, tol)
        reason = '焊盘间距不足';
        return;
    end
    if ~rectangular_fpc_design_checks('pad_to_copper',  ...
            d.padA, d.padB, layerPaths, cfg, tol, padConnectionLength)
        reason = '焊盘到顶层非连接铜线间距不足';
        return;
    end
end
if cfg.enableViaClearanceCheck
    if ~rectangular_fpc_design_checks('via_to_via', viaXY, cfg, tol)
        reason = '过孔间距不足';
        return;
    end
    if ~rectangular_fpc_design_checks('via_to_board', vias, closedBoardXY, cfg, tol)
        reason = '过孔到板框间距不足';
        return;
    end
    if ~rectangular_fpc_design_checks('via_to_pad', viaXY, d.padA, d.padB, cfg, tol)
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
    [connectedPass, nonConnectedPass] = rectangular_fpc_design_checks('via_to_copper',  ...
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
