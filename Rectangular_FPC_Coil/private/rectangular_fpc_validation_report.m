function varargout = rectangular_fpc_validation_report(operation, varargin)
%RECTANGULAR_FPC_VALIDATION_REPORT Validation report and topology helpers.

switch operation
    case 'build'
        [varargout{1:nargout}] = buildValidationReportLines(varargin{:});
    case 'electrical_topology'
        [varargout{1:nargout}] = validateElectricalTopology(varargin{:});
    otherwise
        error('RectangularFPC:UnknownValidationReportOperation', ...
            'Unknown validation-report operation: %s', operation);
end
end

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
    copperClearancePass, connectionPass, topologyPass)

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
lines{end+1} = sprintf('电气拓扑端点检查         : %s', ...
    passText(topologyPass));
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

function [passed, issues, endpointErrors] = ...
    validateElectricalTopology(cfg, d, layerPaths, vias)

tol = cfg.connectionTolerance;
issues = {};
seriesMask = strcmp({vias.role}, 'series_interconnect');
seriesVias = vias(seriesMask);
endpointErrors = struct( ...
    'seriesFromMm', nan(numel(seriesVias), 1), ...
    'seriesToMm', nan(numel(seriesVias), 1), ...
    'padAMm', NaN, ...
    'voutFromMm', NaN, ...
    'voutReturnMm', NaN, ...
    'padBMm', NaN);

if numel(seriesVias) ~= cfg.layerCount - 1
    issues{end+1} = sprintf( ...
        '串联过孔数量%d与预期%d不一致', ...
        numel(seriesVias), cfg.layerCount - 1);
end
for viaIndex = 1:numel(seriesVias)
    via = seriesVias(viaIndex);
    [fromPass, fromError] = endpointPathPass( ...
        via.fromLeadPath, 'end', via.xy, tol);
    [toPass, toError] = endpointPathPass( ...
        via.toLeadPath, 'start', via.xy, tol);
    endpointErrors.seriesFromMm(viaIndex) = fromError;
    endpointErrors.seriesToMm(viaIndex) = toError;
    if ~fromPass
        issues{end+1} = sprintf( ...
            '%s 的 fromLeadPath 为空、无效或未连接到过孔', ...
            via.name); %#ok<AGROW>
    end
    if ~toPass
        issues{end+1} = sprintf( ...
            '%s 的 toLeadPath 为空、无效或未连接到过孔', ...
            via.name); %#ok<AGROW>
    end
end

if isempty(layerPaths) || isempty(layerPaths{1})
    issues{end+1} = 'L1 主路径缺失，PAD_A 无物理连接';
else
    [padAPass, endpointErrors.padAMm] = endpointPathPass( ...
        layerPaths{1}{1}, 'start', d.padA, tol);
    if ~padAPass
        issues{end+1} = 'L1 主路径未连接到 PAD_A';
    end
end

voutMask = strcmp({vias.name}, 'VOUT');
if nnz(voutMask) ~= 1
    issues{end+1} = 'VOUT 数量必须恰好为 1';
else
    vout = vias(voutMask);
    if numel(layerPaths) < cfg.layerCount || ...
            isempty(layerPaths{cfg.layerCount})
        issues{end+1} = sprintf( ...
            'L%d 主路径缺失，VOUT 无物理连接', ...
            cfg.layerCount);
    else
        [voutFromPass, endpointErrors.voutFromMm] = endpointPathPass( ...
            layerPaths{cfg.layerCount}{1}, 'end', vout.xy, tol);
        if ~voutFromPass
            issues{end+1} = sprintf( ...
                'L%d 主路径未连接到 VOUT', cfg.layerCount);
        end
    end
    if isempty(layerPaths) || numel(layerPaths{1}) < 2
        issues{end+1} = 'L1 VOUT 返回路径缺失';
    else
        returnPath = layerPaths{1}{2};
        [returnPass, endpointErrors.voutReturnMm] = endpointPathPass( ...
            returnPath, 'start', vout.xy, tol);
        [padBPass, endpointErrors.padBMm] = endpointPathPass( ...
            returnPath, 'end', d.padB, tol);
        if ~returnPass
            issues{end+1} = 'L1 返回路径未从 VOUT 起始';
        end
        if ~padBPass
            issues{end+1} = 'L1 返回路径未连接到 PAD_B';
        end
    end
end
passed = isempty(issues);
end

function [passed, endpointError] = endpointPathPass( ...
    path, endpointName, targetXY, tol)

passed = false;
endpointError = Inf;
if isempty(path) || ~isnumeric(path) || size(path, 2) ~= 2 || ...
        size(path, 1) < 2 || any(~isfinite(path), 'all')
    return;
end
if strcmp(endpointName, 'start')
    endpoint = path(1, :);
else
    endpoint = path(end, :);
end
endpointError = norm(endpoint - targetXY);
passed = endpointError <= tol;
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
