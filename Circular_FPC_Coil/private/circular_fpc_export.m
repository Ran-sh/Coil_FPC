function varargout = circular_fpc_export(operation, varargin)
% Atomic DXF/SVG/CSV/TXT export with lightweight readback (R4).
switch operation
    case 'write_all'
        varargout{1} = exportAll(varargin{1}, varargin{2});
    otherwise
        error('CircularFPC:InvalidOperation', 'Unknown export operation: %s', operation);
end
end

function outputPath = exportAll(cfg, result)
% 原子导出：先在 <outputRoot> 下写临时目录，全部写完后做读回校验，
% 通过后整体改名为正式目录 <outputRoot>/<designName>。
% 任一步失败都会删除临时目录，不留下半成品，也不覆盖已存在的正式输出。
formal = fullfile(cfg.outputRoot, cfg.designName);
if isfolder(formal)
    error('CircularFPC:OutputExists', 'Output directory already exists: %s', formal);
end
if ~isfolder(cfg.outputRoot)
    mkdir(cfg.outputRoot);
end
tempDir = tempname(cfg.outputRoot);
mkdir(tempDir);
try
    writeAllFiles(cfg, result, tempDir);
    verifyWrittenOutputs(cfg, result, tempDir);
catch err
    if isfolder(tempDir)
        rmdir(tempDir, 's');
    end
    rethrow(err);
end
movefile(tempDir, formal);
outputPath = formal;
end

function writeAllFiles(cfg, result, outDir)
% 输出文件树：
%   dxf/         板框 + 每物理层铜层（4 层板含反焊盘层）
%   previews/    全板/连接区/每层 SVG 预览（enablePreview=true 时）
%   reports/     坐标 CSV、层映射、摘要、匝数扫描、验证报告
%   generation_status.txt
dxfDir = fullfile(outDir, 'dxf');
reportsDir = fullfile(outDir, 'reports');
mkdir(dxfDir);
mkdir(reportsDir);
writeBoardDxf(fullfile(dxfDir, '00_board_outline.dxf'), result.boardLoops);
for li = 1:cfg.boardLayerCount
    layerDir = fullfile(dxfDir, sprintf('L%d', li));
    mkdir(layerDir);
    writeCopperDxf(fullfile(layerDir, sprintf('%02d_copper_L%d.dxf', li, li)), cfg, result, li);
end
if cfg.enablePreview
    prevDir = fullfile(outDir, 'previews');
    mkdir(prevDir);
    writeSvgFull(fullfile(prevDir, '01_preview_full.svg'), cfg, result);
    writeSvgConnectionZone(fullfile(prevDir, '02_preview_connection_zone.svg'), cfg, result);
    for li = 1:numel(result.layerPaths)
        fileName = sprintf('%02d_preview_layer_L%d_%s.svg', 2 + li, li, svgLayerRole(result, li));
        writeSvgLayer(fullfile(prevDir, fileName), cfg, result, li);
    end
end
writeReports(cfg, result, reportsDir);
writeStatus(cfg, result, fullfile(outDir, 'generation_status.txt'));
end

function writeBoardDxf(filename, boardLoops)
% 板框 DXF：5 个闭合 LWPOLYLINE（1 外边界 + 4 孔槽）。
fid = fopen(filename, 'w');
writeDxfHeader(fid);
for k = 1:numel(boardLoops)
    writeLwPolyline(fid, boardLoops(k).xy, 'BOARD', true, 0);
end
writeDxfFooter(fid);
fclose(fid);
end

function writeCopperDxf(filename, cfg, result, li)
% 单层铜 DXF：线圈折线 + 连接路径（LWPOLYLINE，宽度 = traceWidth）；
% L1 额外画 PAD_A/PAD_B 圆；与该层相连的过孔画焊环圆，
% 不与该层相连的过孔画 ANTIPAD 圆（4 层板才有）。
fid = fopen(filename, 'w');
writeDxfHeader(fid);
layerName = sprintf('COPPER_L%d', li);
lp = result.layerPaths(li);
if ~isempty(lp.coilXY)
    writeLwPolyline(fid, lp.coilXY, layerName, false, cfg.traceWidth);
end
paths = lp.connectionPaths;
for k = 1:numel(paths)
    writeLwPolyline(fid, paths{k}, layerName, false, cfg.traceWidth);
end
if li == 1
    for k = 1:numel(result.pads)
        writeCircle(fid, layerName, result.pads(k).xy(1), result.pads(k).xy(2), cfg.padDiameter / 2);
        writeText(fid, layerName, result.pads(k).xy(1), result.pads(k).xy(2), result.pads(k).name);
    end
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    if v.fromLayer == li || v.toLayer == li
        writeCircle(fid, layerName, v.xy(1), v.xy(2), cfg.viaPadDiameter / 2);
        writeText(fid, layerName, v.xy(1), v.xy(2), v.name);
    else
        antipadLayer = sprintf('ANTIPAD_L%d', li);
        writeCircle(fid, antipadLayer, v.xy(1), v.xy(2), cfg.antipadDiameter / 2);
        writeText(fid, antipadLayer, v.xy(1), v.xy(2), sprintf('ANTIPAD_%s', v.name));
    end
end
writeDxfFooter(fid);
fclose(fid);
end

function writeDxfHeader(fid)
fprintf(fid, '0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n4\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n');
end

function writeDxfFooter(fid)
fprintf(fid, '0\nENDSEC\n0\nEOF\n');
end

function writeLwPolyline(fid, xy, layerName, isClosed, width)
n = size(xy, 1);
fprintf(fid, '0\nLWPOLYLINE\n8\n%s\n90\n%d\n70\n%d\n', layerName, n, double(isClosed));
for k = 1:n
    fprintf(fid, '10\n%.6f\n20\n%.6f\n40\n%.6f\n41\n%.6f\n', xy(k, 1), xy(k, 2), width, width);
end
end

function writeCircle(fid, layerName, cx, cy, r)
fprintf(fid, '0\nCIRCLE\n8\n%s\n10\n%.6f\n20\n%.6f\n40\n%.6f\n', layerName, cx, cy, r);
end

function writeText(fid, layerName, x, y, txt)
fprintf(fid, '0\nTEXT\n8\n%s\n10\n%.6f\n20\n%.6f\n40\n0.5\n1\n%s\n', layerName, x, y, txt);
end

function writeSvgFull(filename, cfg, result)
fid = fopen(filename, 'w');
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = result.effectiveDimensions.boardOuterDiameter / 2 + max(cfg.edgeClearance, 0.5);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    -extent, -extent, 2 * extent, 2 * extent);
for k = 1:numel(result.boardLoops)
    fprintf(fid, '<polygon points="%s" fill="none" stroke="black" stroke-width="0.15"/>\n', pointsAttr(result.boardLoops(k).xy));
end
colors = {'#d62728', '#1f77b4', '#2ca02c', '#9467bd'};
for li = 1:numel(result.layerPaths)
    cidx = mod(li - 1, 4) + 1;
    if ~isempty(result.layerPaths(li).coilXY)
        fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
            pointsAttr(result.layerPaths(li).coilXY), colors{cidx}, cfg.traceWidth);
    end
    paths = result.layerPaths(li).connectionPaths;
    for k = 1:numel(paths)
        fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
            pointsAttr(paths{k}), colors{cidx}, cfg.traceWidth);
    end
end
[labelX, labelY, bg] = svgLegendLayout(-extent, -extent, extent, extent, numel(result.pads) + numel(result.vias));
writeSvgLegendBackground(fid, bg);
idx = 0;
for k = 1:numel(result.pads)
    p = result.pads(k);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#d62728"/>\n', ...
        p.xy(1), p.xy(2), cfg.padDiameter / 2);
    idx = idx + 1;
    writeSvgTerminalText(fid, p, labelX, labelY(idx));
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="none" stroke="#7f7f7f" stroke-width="0.1"/>\n', ...
        v.xy(1), v.xy(2), cfg.viaPadDiameter / 2);
    idx = idx + 1;
    writeSvgTerminalText(fid, v, labelX, labelY(idx));
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function writeSvgLayer(filename, cfg, result, li)
% 每层单独预览：板框 + 该层铜（线圈 + 连接路径）+ L1 焊盘 + 该层过孔。
fid = fopen(filename, 'w');
if fid < 0
    error('CircularFPC:ExportWriteFailed', 'Cannot open SVG for writing: %s', filename);
end
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = result.effectiveDimensions.boardOuterDiameter / 2 + max(cfg.edgeClearance, 0.5);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    -extent, -extent, 2 * extent, 2 * extent);
for k = 1:numel(result.boardLoops)
    fprintf(fid, '<polygon points="%s" fill="none" stroke="black" stroke-width="0.15"/>\n', pointsAttr(result.boardLoops(k).xy));
end
colors = {'#d62728', '#1f77b4', '#2ca02c', '#9467bd'};
cidx = mod(li - 1, 4) + 1;
if ~isempty(result.layerPaths(li).coilXY)
    fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
        pointsAttr(result.layerPaths(li).coilXY), colors{cidx}, cfg.traceWidth);
end
paths = result.layerPaths(li).connectionPaths;
for k = 1:numel(paths)
    fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
        pointsAttr(paths{k}), colors{cidx}, cfg.traceWidth);
end
if li == 1
    for k = 1:numel(result.pads)
        p = result.pads(k);
        fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#d62728"/>\n', ...
            p.xy(1), p.xy(2), cfg.padDiameter / 2);
    end
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    if li ~= v.fromLayer && li ~= v.toLayer
        continue;
    end
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="none" stroke="#7f7f7f" stroke-width="0.1"/>\n', ...
        v.xy(1), v.xy(2), cfg.viaPadDiameter / 2);
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function role = svgLayerRole(result, li)
if li == 1
    role = 'top';
elseif li == numel(result.layerPaths)
    role = 'bottom';
else
    role = sprintf('inner%d', li - 1);
end
end

function writeSvgConnectionZone(filename, cfg, result)
w = result.effectiveDimensions.centerPlatformWidth;
h = result.effectiveDimensions.centerPlatformHeight;
fid = fopen(filename, 'w');
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
xMin = -w / 2 - 2;
xMax = w / 2 + 2;
yMin = -h / 2 - 2;
yMax = h / 2 + 2;
for k = 1:numel(result.pads)
    p = result.pads(k);
    r = p.diameter / 2;
    xMin = min(xMin, p.xy(1) - r - 0.75);
    xMax = max(xMax, p.xy(1) + r + 0.75);
    yMin = min(yMin, p.xy(2) - r - 0.75);
    yMax = max(yMax, p.xy(2) + r + 0.75);
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    r = v.padDiameter / 2;
    xMin = min(xMin, v.xy(1) - r - 0.75);
    xMax = max(xMax, v.xy(1) + r + 0.75);
    yMin = min(yMin, v.xy(2) - r - 0.75);
    yMax = max(yMax, v.xy(2) + r + 0.75);
end
% Round outward so %.3f output cannot clip any terminal circle (R2).
xMin = floor(xMin * 1000) / 1000;
xMax = ceil(xMax * 1000) / 1000;
yMin = floor(yMin * 1000) / 1000;
yMax = ceil(yMax * 1000) / 1000;
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.3f %.3f %.3f %.3f">\n', ...
    xMin, yMin, xMax - xMin, yMax - yMin);
for k = 1:numel(result.boardLoops)
    fprintf(fid, '<polygon points="%s" fill="none" stroke="black" stroke-width="0.15"/>\n', pointsAttr(result.boardLoops(k).xy));
end
for li = 1:numel(result.layerPaths)
    paths = result.layerPaths(li).connectionPaths;
    for k = 1:numel(paths)
        fprintf(fid, '<polyline points="%s" fill="none" stroke="#1f77b4" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
            pointsAttr(paths{k}), cfg.traceWidth);
    end
end
[labelX, labelY, bg] = svgLegendLayout(xMin, yMin, xMax, yMax, numel(result.pads) + numel(result.vias));
writeSvgLegendBackground(fid, bg);
idx = 0;
for k = 1:numel(result.pads)
    p = result.pads(k);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#d62728"/>\n', ...
        p.xy(1), p.xy(2), cfg.padDiameter / 2);
    idx = idx + 1;
    writeSvgTerminalText(fid, p, labelX, labelY(idx));
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="none" stroke="#7f7f7f" stroke-width="0.1"/>\n', ...
        v.xy(1), v.xy(2), cfg.viaPadDiameter / 2);
    idx = idx + 1;
    writeSvgTerminalText(fid, v, labelX, labelY(idx));
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function s = pointsAttr(xy)
s = sprintf('%.4f,%.4f ', xy.');
end

function writeReports(cfg, result, reportsDir)
% 报告文件：
%   01_pad_via_coordinates.csv  焊盘/过孔坐标与端子元数据
%   02_layer_map.csv            每物理层是否活动线圈层及绕向
%   03_design_summary.txt       设计摘要（尺寸、总长、直流电阻、串联序列、端子位置）
%   04_turn_scan.csv            匝数可行性扫描（每匝所需径向宽度是否放得下）
%   05_validation_report.txt    验证报告（各 PASS 指标 + 失败信息）
fid = fopen(fullfile(reportsDir, '01_pad_via_coordinates.csv'), 'w');
fprintf(fid, 'name,xMm,yMm,diameterMm,drillMm,antipadDiameterMm,layer,fromLayer,toLayer,removable,role,placementRegion,bridgeAngleDeg\n');
for k = 1:numel(result.pads)
    p = result.pads(k);
    fprintf(fid, '%s,%.6f,%.6f,%.6f,%.6f,NaN,%d,%d,%d,%d,%s,%s,%.6f\n', ...
        p.name, p.xy(1), p.xy(2), p.diameter, 0, p.layer, p.layer, p.layer, p.removable, 'REMOVABLE_PAD', p.placementRegion, p.bridgeAngleDeg);
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    fprintf(fid, '%s,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%s,%s,%.6f\n', ...
        v.name, v.xy(1), v.xy(2), v.padDiameter, v.drillDiameter, cfg.antipadDiameter, ...
        0, v.fromLayer, v.toLayer, 0, v.role, v.placementRegion, v.bridgeAngleDeg);
end
fclose(fid);
fid = fopen(fullfile(reportsDir, '02_layer_map.csv'), 'w');
fprintf(fid, 'layerNumber,isActiveCoilLayer,windingDirection\n');
for li = 1:numel(result.layerPaths)
    fprintf(fid, '%d,%d,%s\n', li, result.layerPaths(li).isActiveCoilLayer, result.layerPaths(li).windingDirection);
end
fclose(fid);
fid = fopen(fullfile(reportsDir, '03_design_summary.txt'), 'w');
eff = result.effectiveDimensions;
fprintf(fid, 'Circular_FPC_Coil design summary\n');
fprintf(fid, 'designName: %s\n', cfg.designName);
fprintf(fid, 'boardLayerCount: %d\n', cfg.boardLayerCount);
fprintf(fid, 'coilLayerCount: %d\n', cfg.coilLayerCount);
fprintf(fid, 'boardOuterDiameter: %.6f mm\n', eff.boardOuterDiameter);
fprintf(fid, 'coilInnerDiameter: %.6f mm\n', eff.coilInnerDiameter);
fprintf(fid, 'centerPlatformWidth: %.6f mm\n', eff.centerPlatformWidth);
fprintf(fid, 'centerPlatformHeight: %.6f mm\n', eff.centerPlatformHeight);
fprintf(fid, 'bridgeTargetWidth: %.6f mm\n', eff.bridgeTargetWidth);
fprintf(fid, 'actualBridgeWidth: %.6f mm\n', eff.actualBridgeWidth);
fprintf(fid, 'turnsPerCoilLayer: %d\n', eff.turnsPerCoilLayer);
fprintf(fid, 'coilPitch: %.6f mm\n', eff.coilPitch);
fprintf(fid, 'traceWidth: %.6f mm\n', cfg.traceWidth);
fprintf(fid, 'traceSpacing: %.6f mm\n', cfg.traceSpacing);
fprintf(fid, 'edgeClearance: %.6f mm\n', cfg.edgeClearance);
fprintf(fid, 'totalTraceLengthMm: %.6f\n', result.totalTraceLengthMm);
fprintf(fid, 'estimatedDcResistanceOhm: %.9f\n', result.estimatedDcResistanceOhm);
fprintf(fid, 'geometry-only estimate; no electrical performance claim (NG-2/INV-5).\n');
fprintf(fid, 'seriesSequence: %s\n', strjoin(result.seriesSequence, ','));
if isnan(result.returnLayer)
    fprintf(fid, 'returnLayer: NaN\n');
else
    fprintf(fid, 'returnLayer: %d\n', result.returnLayer);
end
fprintf(fid, 'maxSeriesContinuityErrorMm: %.9f\n', result.validation.maxSeriesContinuityErrorMm);
fprintf(fid, 'maxConnectionTurnDeg: %.6f\n', result.validation.maxConnectionTurnDeg);
fprintf(fid, 'connectionAngleDeg: %.6f\n', cfg.connectionAngleDeg);
fprintf(fid, 'padPairSpacing: %.6f\n', cfg.padPairSpacing);
for k = 1:numel(result.pads)
    p = result.pads(k);
    fprintf(fid, 'terminal: %s, placementRegion=%s, bridgeAngleDeg=%.6f\n', ...
        p.name, p.placementRegion, p.bridgeAngleDeg);
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    fprintf(fid, 'terminal: %s, placementRegion=%s, bridgeAngleDeg=%.6f\n', ...
        v.name, v.placementRegion, v.bridgeAngleDeg);
end
fclose(fid);
fid = fopen(fullfile(reportsDir, '04_turn_scan.csv'), 'w');
fprintf(fid, 'turns,requiredRadialWidthMm,fitsBoard\n');
available = eff.boardOuterDiameter / 2 - cfg.edgeClearance - eff.coilInnerDiameter / 2;
for t = 1:cfg.turnScanMax
    req = cfg.traceWidth + (t - 1) * eff.coilPitch;
    fprintf(fid, '%d,%.6f,%d\n', t, req, req <= available + 1e-9);
end
fclose(fid);
fid = fopen(fullfile(reportsDir, '05_validation_report.txt'), 'w');
v = result.validation;
fprintf(fid, 'PASS finiteCoordinates: %d\n', v.finiteCoordinates);
fprintf(fid, 'PASS noZeroLengthSegments: %d\n', v.noZeroLengthSegments);
fprintf(fid, 'PASS noSelfIntersections: %d\n', v.noSelfIntersections);
fprintf(fid, 'PASS closedBoardLoopCount: %d\n', v.closedBoardLoopCount);
fprintf(fid, 'PASS minCopperSpacingMm: %.6f\n', v.minCopperSpacingMm);
fprintf(fid, 'PASS minCopperToBoardMm: %.6f\n', v.minCopperToBoardMm);
fprintf(fid, 'PASS minCopperToSlotsMm: %.6f\n', v.minCopperToSlotsMm);
fprintf(fid, 'PASS minPadViaClearanceMm: %.6f\n', v.minPadViaClearanceMm);
fprintf(fid, 'PASS actualBridgeWidthMm: %.6f\n', v.actualBridgeWidthMm);
fprintf(fid, 'PASS uniqueSeriesNetwork: %d\n', v.uniqueSeriesNetwork);
fprintf(fid, 'PASS maxSeriesContinuityErrorMm: %.9f\n', v.maxSeriesContinuityErrorMm);
fprintf(fid, 'PASS maxConnectionTurnDeg: %.6f\n', v.maxConnectionTurnDeg);
fprintf(fid, 'PASS viaOverlapFree: %d\n', v.viaOverlapFree);
for m = v.messages
    fprintf(fid, 'FAIL %s\n', m{1});
end
fprintf(fid, 'passed: %d\n', v.passed);
fclose(fid);
end

function writeStatus(cfg, result, filename)
fid = fopen(filename, 'w');
fprintf(fid, 'SUCCESS\n');
fprintf(fid, 'designName: %s\n', cfg.designName);
fprintf(fid, 'outputPath: %s\n', result.outputPath);
fprintf(fid, 'generatedBy: Circular_FPC_Coil\n');
fclose(fid);
end

function verifyWrittenOutputs(cfg, result, tempDir)
% 读回校验：确保写出的 DXF/SVG/CSV/TXT 可解析、内容符合契约
% （DXF 单位 mm、5 个闭合多段线、SVG 可被 xmlread 解析、CSV 列名正确等）。
boardFile = fullfile(tempDir, 'dxf', '00_board_outline.dxf');
txt = fileread(boardFile);
if ~checkInsUnitsMm(txt)
    error('CircularFPC:ExportReadbackFailed', 'Board DXF $INSUNITS is not 4.');
end
if countClosedLwpolylines(txt) ~= 5
    error('CircularFPC:ExportReadbackFailed', 'Board DXF must contain exactly 5 closed LWPOLYLINE entities.');
end
for li = 1:cfg.boardLayerCount
    f = fullfile(tempDir, 'dxf', sprintf('L%d', li), sprintf('%02d_copper_L%d.dxf', li, li));
    if ~isfile(f)
        error('CircularFPC:ExportReadbackFailed', 'Missing copper DXF: %s', f);
    end
end
if cfg.enablePreview
    for f = {fullfile(tempDir, 'previews', '01_preview_full.svg'), ...
            fullfile(tempDir, 'previews', '02_preview_connection_zone.svg')}
        if ~isfile(f{1})
            error('CircularFPC:ExportReadbackFailed', 'Missing SVG: %s', f{1});
        end
        xmlread(f{1});
    end
    for li = 1:cfg.boardLayerCount
        if li == 1
            role = 'top';
        elseif li == cfg.boardLayerCount
            role = 'bottom';
        else
            role = sprintf('inner%d', li - 1);
        end
        f = fullfile(tempDir, 'previews', ...
            sprintf('%02d_preview_layer_L%d_%s.svg', 2 + li, li, role));
        if ~isfile(f)
            error('CircularFPC:ExportReadbackFailed', 'Missing SVG: %s', f);
        end
        xmlread(f);
    end
end
for f = {'01_pad_via_coordinates.csv', '02_layer_map.csv'}
    p = fullfile(tempDir, 'reports', f{1});
    t = readtable(p);
    if height(t) < 1
        error('CircularFPC:ExportReadbackFailed', 'Unreadable report: %s', p);
    end
end
verifyExportedTerminalMetadata(cfg, result, tempDir);
for f = {'03_design_summary.txt', '04_turn_scan.csv', '05_validation_report.txt'}
    p = fullfile(tempDir, 'reports', f{1});
    if isempty(fileread(p))
        error('CircularFPC:ExportReadbackFailed', 'Empty report: %s', p);
    end
end
if isempty(fileread(fullfile(tempDir, 'generation_status.txt')))
    error('CircularFPC:ExportReadbackFailed', 'Empty generation status.');
end
end

function tf = checkInsUnitsMm(txt)
lines = strtrim(strsplit(txt, newline));
idx = find(strcmp(lines, '$INSUNITS'), 1);
tf = ~isempty(idx) && idx + 2 <= numel(lines) && strcmp(lines{idx + 1}, '70') && str2double(lines{idx + 2}) == 4;
end

function n = countClosedLwpolylines(txt)
lines = strtrim(strsplit(txt, newline));
n = 0;
k = 1;
while k + 1 <= numel(lines)
    if strcmp(lines{k}, '0') && strcmp(lines{k + 1}, 'LWPOLYLINE')
        j = k + 2;
        closed = false;
        while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
            if strcmp(lines{j}, '70') && str2double(lines{j + 1}) == 1
                closed = true;
            end
            j = j + 2;
        end
        if closed
            n = n + 1;
        end
        k = j;
    else
        k = k + 1;
    end
end
end

function writeSvgTerminalText(fid, term, labelX, labelY)
% Emit XML-safe SVG leader line and legend label with terminal metadata (R1/R2).
escName = xmlEscapeText(term.name);
escRegion = xmlEscapeText(term.placementRegion);
escAngle = xmlEscapeText(sprintf('%.6f', term.bridgeAngleDeg));
fprintf(fid, '<line class="terminal-leader" data-name="%s" x1="%.6f" y1="%.6f" x2="%.6f" y2="%.6f" stroke="#666666" stroke-width="0.025" opacity="0.45"/>\n', ...
    escName, term.xy(1), term.xy(2), labelX - 0.05, labelY - 0.06);
fprintf(fid, '<text class="terminal-label" x="%.6f" y="%.6f" font-size="0.22" fill="#000000" data-name="%s" data-placement-region="%s" data-bridge-angle-deg="%s">%s [%s] angle=%sdeg</text>\n', ...
    labelX, labelY, escName, escRegion, escAngle, ...
    escName, escRegion, escAngle);
end

function [labelX, labelY, bg] = svgLegendLayout(xMin, yMin, xMax, yMax, nTerms)
labelX = xMin + 0.35;
labelY = yMin + 0.35 + (0:nTerms - 1) * 0.35;
bg = [xMin + 0.15, yMin + 0.15, (xMax - xMin) - 0.30, 0.35 * nTerms + 0.35];
if bg(3) <= 0 || bg(4) <= 0 || labelX > xMax || labelY(end) > yMax
    error('CircularFPC:ExportReadbackFailed', ...
        'SVG legend layout does not fit viewBox (nTerms=%d, x=[%.6f %.6f], y=[%.6f %.6f]).', ...
        nTerms, xMin, xMax, yMin, yMax);
end
end

function writeSvgLegendBackground(fid, bg)
fprintf(fid, '<rect class="terminal-legend-bg" x="%.6f" y="%.6f" width="%.6f" height="%.6f" fill="#ffffff" opacity="0.88"/>\n', ...
    bg(1), bg(2), bg(3), bg(4));
end

function s = xmlEscapeText(s)
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
s = strrep(s, '"', '&quot;');
s = strrep(s, '''', '&apos;');
end

function verifyExportedTerminalMetadata(cfg, result, tempDir)
% Internal readback: CSV columns/rows and SVG labels must match result (R1/R2/R4).
csvPath = fullfile(tempDir, 'reports', '01_pad_via_coordinates.csv');
t = readtable(csvPath);
expectedColumns = {'name', 'xMm', 'yMm', 'diameterMm', 'drillMm', 'antipadDiameterMm', ...
    'layer', 'fromLayer', 'toLayer', 'removable', 'role', ...
    'placementRegion', 'bridgeAngleDeg'};
if ~isequal(t.Properties.VariableNames, expectedColumns)
    error('CircularFPC:ExportReadbackFailed', ...
        'CSV columns must be the old 11 followed by placementRegion and bridgeAngleDeg.');
end
expectedHeight = numel(result.pads) + numel(result.vias);
if height(t) ~= expectedHeight
    error('CircularFPC:ExportReadbackFailed', 'CSV row count must equal pads+vias.');
end
if numel(unique(t.name)) ~= expectedHeight
    error('CircularFPC:ExportReadbackFailed', 'CSV terminal names must be unique.');
end
for k = 1:numel(result.pads)
    p = result.pads(k);
    row = t(strcmp(t.name, p.name), :);
    if height(row) ~= 1
        error('CircularFPC:ExportReadbackFailed', 'CSV must contain exactly one row for %s.', p.name);
    end
    if abs(row.xMm - p.xy(1)) > 1e-6 || abs(row.yMm - p.xy(2)) > 1e-6
        error('CircularFPC:ExportReadbackFailed', 'CSV coordinates mismatch for %s.', p.name);
    end
    if ~strcmp(char(row.placementRegion), p.placementRegion)
        error('CircularFPC:ExportReadbackFailed', 'CSV placementRegion mismatch for %s.', p.name);
    end
    if isnan(p.bridgeAngleDeg)
        if ~isnan(row.bridgeAngleDeg)
            error('CircularFPC:ExportReadbackFailed', 'CSV bridgeAngleDeg must be NaN for %s.', p.name);
        end
    elseif abs(row.bridgeAngleDeg - p.bridgeAngleDeg) > 1e-6
        error('CircularFPC:ExportReadbackFailed', 'CSV bridgeAngleDeg mismatch for %s.', p.name);
    end
    if abs(row.diameterMm - p.diameter) > 1e-6 || row.layer ~= p.layer
        error('CircularFPC:ExportReadbackFailed', 'CSV pad legacy column mismatch for %s.', p.name);
    end
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    row = t(strcmp(t.name, v.name), :);
    if height(row) ~= 1
        error('CircularFPC:ExportReadbackFailed', 'CSV must contain exactly one row for %s.', v.name);
    end
    if abs(row.xMm - v.xy(1)) > 1e-6 || abs(row.yMm - v.xy(2)) > 1e-6
        error('CircularFPC:ExportReadbackFailed', 'CSV coordinates mismatch for %s.', v.name);
    end
    if ~strcmp(char(row.placementRegion), v.placementRegion)
        error('CircularFPC:ExportReadbackFailed', 'CSV placementRegion mismatch for %s.', v.name);
    end
    if isnan(v.bridgeAngleDeg)
        if ~isnan(row.bridgeAngleDeg)
            error('CircularFPC:ExportReadbackFailed', 'CSV bridgeAngleDeg must be NaN for %s.', v.name);
        end
    elseif abs(row.bridgeAngleDeg - v.bridgeAngleDeg) > 1e-6
        error('CircularFPC:ExportReadbackFailed', 'CSV bridgeAngleDeg mismatch for %s.', v.name);
    end
    if abs(row.diameterMm - v.padDiameter) > 1e-6 || ...
            row.fromLayer ~= v.fromLayer || row.toLayer ~= v.toLayer
        error('CircularFPC:ExportReadbackFailed', 'CSV via legacy column mismatch for %s.', v.name);
    end
end
if cfg.enablePreview
    for f = {fullfile(tempDir, 'previews', '01_preview_full.svg'), ...
            fullfile(tempDir, 'previews', '02_preview_connection_zone.svg')}
        svgTxt = fileread(f{1});
        for k = 1:numel(result.pads)
            p = result.pads(k);
            angleStr = sprintf('%.6f', p.bridgeAngleDeg);
            if ~contains(svgTxt, sprintf('data-name="%s"', p.name)) || ...
                    ~contains(svgTxt, sprintf('data-placement-region="%s"', p.placementRegion)) || ...
                    ~contains(svgTxt, sprintf('data-bridge-angle-deg="%s"', angleStr)) || ...
                    ~contains(svgTxt, sprintf('%s [%s] angle=', p.name, p.placementRegion))
                error('CircularFPC:ExportReadbackFailed', ...
                    'SVG missing terminal metadata for %s.', p.name);
            end
        end
        for k = 1:numel(result.vias)
            v = result.vias(k);
            angleStr = sprintf('%.6f', v.bridgeAngleDeg);
            if ~contains(svgTxt, sprintf('data-name="%s"', v.name)) || ...
                    ~contains(svgTxt, sprintf('data-placement-region="%s"', v.placementRegion)) || ...
                    ~contains(svgTxt, sprintf('data-bridge-angle-deg="%s"', angleStr)) || ...
                    ~contains(svgTxt, sprintf('%s [%s] angle=', v.name, v.placementRegion))
                error('CircularFPC:ExportReadbackFailed', ...
                    'SVG missing terminal metadata for %s.', v.name);
            end
        end
    end
end
end
