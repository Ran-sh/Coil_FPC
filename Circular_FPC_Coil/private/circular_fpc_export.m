function varargout = circular_fpc_export(operation, varargin)
% Atomic DXF/SVG/CSV/TXT export with lightweight readback (R4).
% Dual-track DXF: legacy centerline files (dxf/Ln/NN_copper_Ln.dxf) keep
% their byte contract; physical CAM-reference files
% (dxf/Ln/NN_copper_physical_Ln.dxf) add group-43 trace width and functional
% via-pad circles. Drills are through-holes; non-functional pads are removed.
% Engineering coordinates are +X right,
% +Y up; only SVG display flips Y. The file manifest
% (reports/08_file_manifest.csv) lists every generated regular file except
% itself.
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
%   dxf/         板框 + 每物理层铜层 + 功能过孔焊环 + 贯穿钻孔图
%   previews/    全板/连接区/每层 SVG 预览（enablePreview=true 时）
%   reports/     坐标 CSV、层映射、摘要、匝数扫描、验证报告
%   generation_status.txt
dxfDir = fullfile(outDir, 'dxf');
reportsDir = fullfile(outDir, 'reports');
mkdir(dxfDir);
mkdir(reportsDir);
writeBoardDxf(fullfile(dxfDir, '00_board_outline.dxf'), cfg, result.boardLoops);
writeDrillMapDxf(fullfile(dxfDir, '00_drill_map.dxf'), result);
for li = 1:cfg.boardLayerCount
    layerDir = fullfile(dxfDir, sprintf('L%d', li));
    mkdir(layerDir);
    writeCopperDxf(fullfile(layerDir, sprintf('%02d_copper_L%d.dxf', li, li)), result, li);
    writePhysicalCopperDxf(fullfile(layerDir, sprintf('%02d_copper_physical_L%d.dxf', li, li)), cfg, result, li);
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
writeFileManifest(fullfile(reportsDir, '08_file_manifest.csv'), outDir);
end

function writeBoardDxf(filename, cfg, boardLoops)
% 板框 DXF：5 个闭合、带可配置实际线宽的 LWPOLYLINE（1 外边界 + 4 孔槽）。
fid = openOutputFile(filename);
writeDxfHeader(fid, {'BOARD'});
for k = 1:numel(boardLoops)
    writeLwPolyline(fid, boardLoops(k).xy, 'BOARD', true, cfg.boardOutlineLineWidth);
end
writeDxfFooter(fid);
fclose(fid);
end

function writeCopperDxf(filename, result, li)
% 单层铜 DXF：仅线圈折线 + 连接路径（LWPOLYLINE）。
% 不写入焊盘/过孔圆与任何文字标注（焊盘、过孔信息见 01_pad_via_coordinates.csv 与 SVG 预览）。
fid = openOutputFile(filename);
layerName = sprintf('COPPER_L%d', li);
writeDxfHeader(fid, {layerName});
lp = result.layerPaths(li);
if ~isempty(lp.coilXY)
    writeLwPolyline(fid, lp.coilXY, layerName, false);
end
paths = lp.connectionPaths;
for k = 1:numel(paths)
    writeLwPolyline(fid, paths{k}, layerName, false);
end
writeDxfFooter(fid);
fclose(fid);
end

function writeDxfHeader(fid, layerNames)
% DXF 头：声明版本(AC1015, LWPOLYLINE 自 R2000 起支持)与单位(mm)，
% 并写入 TABLES/LAYER 图层表；行尾统一 CRLF。
fprintf(fid, '0\r\nSECTION\r\n2\r\nHEADER\r\n');
fprintf(fid, '9\r\n$ACADVER\r\n1\r\nAC1015\r\n');
fprintf(fid, '9\r\n$INSUNITS\r\n70\r\n4\r\n');
fprintf(fid, '9\r\n$DWGCODEPAGE\r\n3\r\nANSI_1252\r\n');
fprintf(fid, '0\r\nENDSEC\r\n');
fprintf(fid, '0\r\nSECTION\r\n2\r\nTABLES\r\n');
fprintf(fid, '0\r\nTABLE\r\n2\r\nLAYER\r\n70\r\n%d\r\n', numel(layerNames));
for k = 1:numel(layerNames)
    fprintf(fid, '0\r\nLAYER\r\n2\r\n%s\r\n70\r\n0\r\n62\r\n7\r\n6\r\nCONTINUOUS\r\n', layerNames{k});
end
fprintf(fid, '0\r\nENDTAB\r\n0\r\nENDSEC\r\n');
fprintf(fid, '0\r\nSECTION\r\n2\r\nENTITIES\r\n');
end

function writeDxfFooter(fid)
fprintf(fid, '0\r\nENDSEC\r\n0\r\nEOF\r\n');
end

function writeLwPolyline(fid, xy, layerName, isClosed, constantWidth)
% Optional 5th argument writes group 43 once per LWPOLYLINE (physical trace
% width). Legacy centerline/board callers pass 4 args and keep old bytes.
n = size(xy, 1);
fprintf(fid, '0\r\nLWPOLYLINE\r\n8\r\n%s\r\n90\r\n%d\r\n70\r\n%d\r\n', layerName, n, double(isClosed));
if nargin >= 5 && ~isempty(constantWidth)
    fprintf(fid, '43\r\n%.6f\r\n', constantWidth);
end
for k = 1:n
    fprintf(fid, '10\r\n%.6f\r\n20\r\n%.6f\r\n', xy(k, 1), xy(k, 2));
end
end

function writeDrillMapDxf(filename, result)
% Drill map: one DRILL CIRCLE per via at engineering coordinates.
fid = openOutputFile(filename);
c = onCleanup(@() fclose(fid));
writeDxfHeader(fid, {'DRILL'});
for k = 1:numel(result.vias)
    writeCircle(fid, result.vias(k).xy, result.vias(k).drillDiameter / 2, 'DRILL');
end
writeDxfFooter(fid);
end

function writePhysicalCopperDxf(filename, cfg, result, li)
% Physical CAM-reference copper for layer li: constant-width traces plus
% pad/via circle boundaries. Centerline files remain unchanged.
layerName = sprintf('COPPER_PHYSICAL_L%d', li);
layerNames = {layerName};
if li == 1
    layerNames{end + 1} = 'PAD_L1';
end
viaIds = find([result.vias.fromLayer] == li | [result.vias.toLayer] == li);
if ~isempty(viaIds)
    layerNames{end + 1} = sprintf('VIA_PAD_L%d', li);
end
fid = openOutputFile(filename);
c = onCleanup(@() fclose(fid));
writeDxfHeader(fid, layerNames);
lp = result.layerPaths(li);
if ~isempty(lp.coilXY)
    writeLwPolyline(fid, lp.coilXY, layerName, false, cfg.traceWidth);
end
paths = lp.connectionPaths;
for k = 1:numel(paths)
    writeLwPolyline(fid, paths{k}, layerName, false, cfg.traceWidth);
end
if li == 1
    for p = 1:numel(result.pads)
        writeCircle(fid, result.pads(p).xy, result.pads(p).diameter / 2, 'PAD_L1');
    end
end
for k = 1:numel(viaIds)
    v = result.vias(viaIds(k));
    writeCircle(fid, v.xy, v.padDiameter / 2, sprintf('VIA_PAD_L%d', li));
end
writeDxfFooter(fid);
end

function writeCircle(fid, xy, radius, layer)
% CIRCLE with engineering +X/+Y coordinates (no display Y flip).
fprintf(fid, '0\r\nCIRCLE\r\n8\r\n%s\r\n10\r\n%.9f\r\n20\r\n%.9f\r\n40\r\n%.9f\r\n', ...
    layer, xy(1), xy(2), radius);
end

function fid = openOutputFile(filename)
fid = fopen(filename, 'wb');
if fid < 0
    error('CircularFPC:ExportReadbackFailed', 'Cannot open output file: %s', filename);
end
end

function writeSvgFull(filename, cfg, result)
fid = fopen(filename, 'w');
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = result.effectiveDimensions.boardOuterDiameter / 2 + max(cfg.edgeClearance, 0.5);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    -extent, -extent, 2 * extent, 2 * extent);
for k = 1:numel(result.boardLoops)
    if result.boardLoops(k).isHole
        fprintf(fid, '<polygon points="%s" fill="#8fcfdc" fill-opacity="0.32" stroke="#000000" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    else
        fprintf(fid, '<polygon points="%s" fill="#ffcc1a" fill-opacity="0.45" stroke="#8c1aa6" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    end
end
colors = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
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
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#e61919" stroke="#000000" stroke-width="0.15"/>\n', ...
        p.xy(1), -p.xy(2), cfg.padDiameter / 2);
    idx = idx + 1;
    writeSvgTerminalText(fid, p, labelX, labelY(idx));
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#474747" stroke="#000000" stroke-width="0.12"/>\n', ...
        v.xy(1), -v.xy(2), cfg.viaPadDiameter / 2);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#ffffff" stroke="#000000" stroke-width="0.10"/>\n', ...
        v.xy(1), -v.xy(2), cfg.viaDrillDiameter / 2);
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
    if result.boardLoops(k).isHole
        fprintf(fid, '<polygon points="%s" fill="#8fcfdc" fill-opacity="0.32" stroke="#000000" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    else
        fprintf(fid, '<polygon points="%s" fill="#ffcc1a" fill-opacity="0.45" stroke="#8c1aa6" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    end
end
colors = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
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
        fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#e61919" stroke="#000000" stroke-width="0.15"/>\n', ...
            p.xy(1), -p.xy(2), cfg.padDiameter / 2);
    end
end
for k = 1:numel(result.vias)
    writeSvgLayerVia(fid, cfg, result.vias(k));
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function writeSvgLayerVia(fid, cfg, v)
% Every layer preview shows the same nominal through-via annulus and drill.
% Physical DXF may remove non-functional pads, but never draws a larger keepout.
fprintf(fid, ['<circle data-via-name="%s" data-via-role="copper-ring" ', ...
    'cx="%.6f" cy="%.6f" r="%.6f" fill="#474747" stroke="#000000" stroke-width="0.12"/>\n'], ...
    v.name, v.xy(1), -v.xy(2), cfg.viaPadDiameter / 2);
fprintf(fid, ['<circle data-via-name="%s" data-via-role="drill" ', ...
    'cx="%.6f" cy="%.6f" r="%.6f" fill="#ffffff" stroke="#000000" stroke-width="0.10"/>\n'], ...
    v.name, v.xy(1), -v.xy(2), cfg.viaDrillDiameter / 2);
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
svgYMin = -yMax;
svgYMax = -yMin;
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.3f %.3f %.3f %.3f">\n', ...
    xMin, svgYMin, xMax - xMin, svgYMax - svgYMin);
for k = 1:numel(result.boardLoops)
    if result.boardLoops(k).isHole
        fprintf(fid, '<polygon points="%s" fill="#8fcfdc" fill-opacity="0.32" stroke="#000000" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    else
        fprintf(fid, '<polygon points="%s" fill="#ffcc1a" fill-opacity="0.45" stroke="#8c1aa6" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    end
end
colors = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
for li = 1:numel(result.layerPaths)
    paths = result.layerPaths(li).connectionPaths;
    for k = 1:numel(paths)
        cidx = mod(li - 1, numel(colors)) + 1;
        fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
            pointsAttr(paths{k}), colors{cidx}, cfg.traceWidth);
    end
end
[labelX, labelY, bg] = svgLegendLayout(xMin, svgYMin, xMax, svgYMax, numel(result.pads) + numel(result.vias));
writeSvgLegendBackground(fid, bg);
idx = 0;
for k = 1:numel(result.pads)
    p = result.pads(k);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#e61919" stroke="#000000" stroke-width="0.15"/>\n', ...
        p.xy(1), -p.xy(2), cfg.padDiameter / 2);
    idx = idx + 1;
    writeSvgTerminalText(fid, p, labelX, labelY(idx));
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#474747" stroke="#000000" stroke-width="0.12"/>\n', ...
        v.xy(1), -v.xy(2), cfg.viaPadDiameter / 2);
    fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#ffffff" stroke="#000000" stroke-width="0.10"/>\n', ...
        v.xy(1), -v.xy(2), cfg.viaDrillDiameter / 2);
    idx = idx + 1;
    writeSvgTerminalText(fid, v, labelX, labelY(idx));
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function s = pointsAttr(xy)
s = sprintf('%.4f,%.4f ', [xy(:,1), -xy(:,2)].');
end

function writeReports(cfg, result, reportsDir)
% 报告文件：
%   01_pad_via_coordinates.csv  焊盘/过孔坐标与端子元数据
%   02_layer_map.csv            每物理层是否活动线圈层及绕向
%   03_design_summary.txt       设计摘要（尺寸、总长、直流电阻、串联序列、端子位置）
%   04_turn_scan.csv            匝数可行性扫描（每匝所需径向宽度是否放得下）
%   05_validation_report.txt    验证报告（各 PASS 指标 + 失败信息）
fid = fopen(fullfile(reportsDir, '01_pad_via_coordinates.csv'), 'w');
fprintf(fid, 'name,xMm,yMm,diameterMm,drillMm,layer,fromLayer,toLayer,removable,role,placementRegion,bridgeAngleDeg\n');
for k = 1:numel(result.pads)
    p = result.pads(k);
    fprintf(fid, '%s,%.6f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%s,%s,%.6f\n', ...
        p.name, p.xy(1), p.xy(2), p.diameter, 0, p.layer, p.layer, p.layer, p.removable, 'REMOVABLE_PAD', p.placementRegion, p.bridgeAngleDeg);
end
for k = 1:numel(result.vias)
    v = result.vias(k);
    fprintf(fid, '%s,%.6f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%s,%s,%.6f\n', ...
        v.name, v.xy(1), v.xy(2), v.padDiameter, v.drillDiameter, ...
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
fprintf(fid, 'boardSizingMode: %s\n', cfg.boardSizingMode);
fprintf(fid, 'viaEndExtension: %.6f mm\n', eff.viaEndExtension);
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
fprintf(fid, 'boardOutlineLineWidth: %.6f mm\n', cfg.boardOutlineLineWidth);
fprintf(fid, 'viaPadDiameter: %.6f mm\n', cfg.viaPadDiameter);
fprintf(fid, 'viaDrillDiameter: %.6f mm\n', cfg.viaDrillDiameter);
fprintf(fid, 'viaCoilSpacing: %.6f mm\n', cfg.viaCoilSpacing);
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
fprintf(fid, 'minOuterViaContactSweepDeg: %.6f\n', result.validation.minOuterViaContactSweepDeg);
fprintf(fid, 'maxOuterViaContactSweepDeg: %.6f\n', result.validation.maxOuterViaContactSweepDeg);
fprintf(fid, 'connectionAngleDeg: %.6f\n', cfg.connectionAngleDeg);
fprintf(fid, 'terminalLeadSpacing: %.6f\n', cfg.terminalLeadSpacing);
fprintf(fid, 'terminalLeadLength: %.6f\n', cfg.terminalLeadLength);
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
% 建议性提示（如平台角部超出内接圆进入桥区走廊）随摘要落盘，便于离线复查。
for k = 1:numel(result.validation.advisories)
    fprintf(fid, 'advisory: %s\n', result.validation.advisories{k});
end
fclose(fid);
fid = fopen(fullfile(reportsDir, '04_turn_scan.csv'), 'w');
% 与配置校验保持一致：1 匝会退化为单采样点，两种模式都从 2 匝开始扫描。
if strcmp(cfg.boardSizingMode, 'auto')
    % auto 模式：板框随匝数增长，报告每个匝数对应的板框外径。
    % 4/4 分数匝（L2 多绕 1/4 圈）下按各层最大外端取 max，与引擎 requiredBoardDiameter 一致。
    fprintf(fid, 'turns,requiredRadialWidthMm,requiredBoardDiameterMm\n');
    for t = 2:cfg.turnScanMax
        req = cfg.traceWidth + (t - 1) * eff.coilPitch;
        spanMax = (t - 1);
        if cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4
            spanMax = (t - 1) + 0.25; % 4/4 的 L2 多绕 1/4 圈
        end
        baseR = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2 + ...
            eff.coilPitch * (t - 1);
        termBase = hypot(baseR + eff.viaEndExtension, eff.viaEndExtension) + ...
            cfg.viaPadDiameter / 2;
        termFrac = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2 + ...
            eff.coilPitch * spanMax + cfg.traceWidth / 2;
        boardD = 2 * (max(termBase, termFrac) + cfg.edgeClearance + cfg.boardOutlineLineWidth / 2);
        fprintf(fid, '%d,%.6f,%.6f\n', t, req, boardD);
    end
else
    fprintf(fid, 'turns,requiredRadialWidthMm,fitsBoard\n');
    available = eff.boardOuterDiameter / 2 - cfg.boardOutlineLineWidth / 2 - ...
        cfg.edgeClearance - eff.coilInnerDiameter / 2;
    for t = 2:cfg.turnScanMax
        req = cfg.traceWidth + (t - 1) * eff.coilPitch;
        fprintf(fid, '%d,%.6f,%d\n', t, req, req <= available + 1e-9);
    end
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
fprintf(fid, 'PASS minViaToBoardMm: %.6f\n', v.minViaToBoardMm);
fprintf(fid, 'PASS minDrillToBoardMm: %.6f\n', v.minDrillToBoardMm);
fprintf(fid, 'PASS minViaToNonConnectedCopperMm: %.6f\n', v.minViaToNonConnectedCopperMm);
fprintf(fid, 'PASS minCopperToSlotsMm: %.6f\n', v.minCopperToSlotsMm);
fprintf(fid, 'PASS minPadViaClearanceMm: %.6f\n', v.minPadViaClearanceMm);
fprintf(fid, 'PASS actualBridgeWidthMm: %.6f\n', v.actualBridgeWidthMm);
fprintf(fid, 'PASS uniqueSeriesNetwork: %d\n', v.uniqueSeriesNetwork);
fprintf(fid, 'PASS maxSeriesContinuityErrorMm: %.9f\n', v.maxSeriesContinuityErrorMm);
fprintf(fid, 'PASS maxConnectionTurnDeg: %.6f\n', v.maxConnectionTurnDeg);
fprintf(fid, 'PASS minOuterViaContactSweepDeg: %.6f\n', v.minOuterViaContactSweepDeg);
fprintf(fid, 'PASS maxOuterViaContactSweepDeg: %.6f\n', v.maxOuterViaContactSweepDeg);
fprintf(fid, 'PASS viaOverlapFree: %d\n', v.viaOverlapFree);
for m = v.messages
    fprintf(fid, 'FAIL %s\n', m{1});
end
fprintf(fid, 'passed: %d\n', v.passed);
fclose(fid);
fid6 = openOutputFile(fullfile(reportsDir, '06_manufacturing_check.csv'));
c6 = onCleanup(@() fclose(fid6));
fprintf(fid6, 'id,measuredMm,limitMm,marginMm,status,source,code,message,profile,tier\n');
for k = 1:numel(result.manufacturing.checks)
    chk = result.manufacturing.checks(k);
    fprintf(fid6, '%s,%.9f,%.9f,%.9f,%s,%s,%s,%s,%s,%s\n', ...
        chk.id, chk.measuredMm, chk.limitMm, chk.marginMm, ...
        chk.status, chk.source, chk.code, csvEscape(chk.message), ...
        result.manufacturing.profile, result.manufacturing.tier);
end
fid7 = openOutputFile(fullfile(reportsDir, '07_fabrication_notes.txt'));
c7 = onCleanup(@() fclose(fid7));
fprintf(fid7, 'Circular_FPC_Coil fabrication notes\n');
fprintf(fid7, 'boardLayerCount: %d\n', cfg.boardLayerCount);
fprintf(fid7, 'coilLayerCount: %d\n', cfg.coilLayerCount);
fprintf(fid7, 'activeCoilLayers: %s\n', mat2str(result.activeCoilLayers));
fprintf(fid7, 'copperThickness: %.6f mm (1 oz nominal profile)\n', cfg.copperThickness);
fprintf(fid7, 'manufacturingProfile: %s\n', result.manufacturing.profile);
fprintf(fid7, 'manufacturingTier: %s\n', result.manufacturing.tier);
fprintf(fid7, 'surfaceFinish: TO_BE_SELECTED\n');
fprintf(fid7, 'coordinates: +X right, +Y up; SVG display only flips Y\n');
fprintf(fid7, 'Physical DXF is a CAM reference and does not replace Gerber.\n');
fprintf(fid7, 'NOT_GENERATED: coverlay, stiffener, Gerber, panelization\n');
fprintf(fid7, 'File manifest 08_file_manifest.csv excludes itself.\n');
end

function s = csvEscape(s)
% RFC4180 minimal escaping for CSV text fields.
if any(s == ',') || any(s == '"') || any(s == newline) || any(double(s) == 13)
    s = ['"' strrep(s, '"', '""') '"'];
end
end

function writeFileManifest(filename, outDir)
% Manifest of every generated regular file except itself, sorted by
% forward-slash relative path; raw-byte SHA256 via Java MessageDigest.
entries = struct('rel', {}, 'role', {}, 'sizeBytes', {}, 'sha256', {});
d = dir(fullfile(outDir, '**', '*'));
for k = 1:numel(d)
    if d(k).isdir
        continue;
    end
    absPath = fullfile(d(k).folder, d(k).name);
    rel = strrep(strrep(absPath, outDir, ''), '\', '/');
    if strcmp(rel, '/reports/08_file_manifest.csv')
        continue;
    end
    entries(end + 1) = struct('rel', rel(2:end), 'role', manifestRole(rel(2:end)), ...
        'sizeBytes', d(k).bytes, 'sha256', sha256File(absPath)); %#ok<AGROW>
end
[~, order] = sort({entries.rel});
entries = entries(order);
fid = openOutputFile(filename);
c = onCleanup(@() fclose(fid));
fprintf(fid, 'relativePath,role,sizeBytes,sha256\n');
for k = 1:numel(entries)
    fprintf(fid, '%s,%s,%d,%s\n', entries(k).rel, entries(k).role, entries(k).sizeBytes, entries(k).sha256);
end
end

function role = manifestRole(rel)
if strcmp(rel, 'dxf/00_board_outline.dxf')
    role = 'board_outline';
elseif strcmp(rel, 'dxf/00_drill_map.dxf')
    role = 'drill_map';
elseif ~isempty(regexp(rel, '^dxf/L\d+/\d+_copper_L\d+\.dxf$', 'once'))
    role = 'copper_centerline';
elseif ~isempty(regexp(rel, '^dxf/L\d+/\d+_copper_physical_L\d+\.dxf$', 'once'))
    role = 'copper_physical';
elseif ~isempty(regexp(rel, '^previews/', 'once'))
    role = 'preview';
elseif ~isempty(regexp(rel, '^reports/', 'once'))
    role = 'report';
elseif strcmp(rel, 'generation_status.txt')
    role = 'generation_status';
else
    error('CircularFPC:ExportReadbackFailed', 'Unmappable manifest file: %s', rel);
end
end

function h = sha256File(path)
fid = fopen(path, 'rb');
if fid < 0
    error('CircularFPC:ExportReadbackFailed', 'Cannot open file for hashing: %s', path);
end
c = onCleanup(@() fclose(fid));
raw = fread(fid, Inf, '*uint8');
md = java.security.MessageDigest.getInstance('SHA-256');
h = lower(reshape(dec2hex(typecast(md.digest(raw), 'uint8'), 2).', 1, []));
end

function n = countFilesRecursive(root)
d = dir(fullfile(root, '**', '*'));
n = sum(~[d.isdir]);
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
[~, boardWidths, boardPolyCount] = readDxfEntities(txt);
if boardPolyCount ~= 5 || numel(boardWidths) ~= 5 || ...
        any(abs(boardWidths - cfg.boardOutlineLineWidth) > 1e-9)
    error('CircularFPC:ExportReadbackFailed', ...
        'Board DXF outline width must be %.6f mm on all five loops.', cfg.boardOutlineLineWidth);
end
drillFile = fullfile(tempDir, 'dxf', '00_drill_map.dxf');
if ~isfile(drillFile)
    error('CircularFPC:ExportReadbackFailed', 'Missing drill map DXF: %s', drillFile);
end
drillTxt = fileread(drillFile);
checkDxfBase(drillTxt, drillFile);
if ~contains(drillTxt, 'DRILL')
    error('CircularFPC:ExportReadbackFailed', 'Drill map DXF must declare DRILL layer.');
end
[dc, ~, ~] = readDxfEntities(drillTxt);
expDrillR = sort([result.vias.drillDiameter] / 2);
if numel(dc) ~= numel(result.vias) || any(~strcmp({dc.layer}, 'DRILL')) || ...
        (~isempty(dc) && any(abs(sort([dc.r]) - expDrillR) > 1e-9))
    error('CircularFPC:ExportReadbackFailed', 'Drill map circle mismatch: %s', drillFile);
end
for li = 1:cfg.boardLayerCount
    layerDir = fullfile(tempDir, 'dxf', sprintf('L%d', li));
    centerFile = fullfile(layerDir, sprintf('%02d_copper_L%d.dxf', li, li));
    if ~isfile(centerFile)
        error('CircularFPC:ExportReadbackFailed', 'Missing copper DXF: %s', centerFile);
    end
    centerTxt = fileread(centerFile);
    checkDxfBase(centerTxt, centerFile);
    [cc, w43c, ~] = readDxfEntities(centerTxt);
    if ~isempty(cc) || ~isempty(w43c)
        error('CircularFPC:ExportReadbackFailed', 'Centerline DXF must not contain CIRCLE/group43: %s', centerFile);
    end
    physFile = fullfile(layerDir, sprintf('%02d_copper_physical_L%d.dxf', li, li));
    if ~isfile(physFile)
        error('CircularFPC:ExportReadbackFailed', 'Missing physical copper DXF: %s', physFile);
    end
    physTxt = fileread(physFile);
    checkDxfBase(physTxt, physFile);
    if contains(physTxt, 'ANTIPAD')
        error('CircularFPC:ExportReadbackFailed', 'Physical DXF must not contain ANTIPAD: %s', physFile);
    end
    physLayer = sprintf('COPPER_PHYSICAL_L%d', li);
    if ~contains(physTxt, physLayer)
        error('CircularFPC:ExportReadbackFailed', 'Physical DXF must declare %s layer.', physLayer);
    end
    [pc, w43, nPoly] = readDxfEntities(physTxt);
    if numel(w43) ~= nPoly || any(abs(w43 - cfg.traceWidth) > 1e-9)
        error('CircularFPC:ExportReadbackFailed', 'Physical DXF group 43 mismatch: %s', physFile);
    end
    viaIds = find([result.vias.fromLayer] == li | [result.vias.toLayer] == li);
    if li == 1
        if ~contains(physTxt, 'PAD_L1')
            error('CircularFPC:ExportReadbackFailed', 'Physical L1 DXF must declare PAD_L1 layer.');
        end
        padC = pc(strcmp({pc.layer}, 'PAD_L1'));
        if numel(padC) ~= 2 || any(abs(sort([padC.r]) - sort([result.pads.diameter] / 2)) > 1e-9)
            error('CircularFPC:ExportReadbackFailed', 'Physical L1 pad circle mismatch: %s', physFile);
        end
    end
    viaLayer = sprintf('VIA_PAD_L%d', li);
    if ~isempty(viaIds) && ~contains(physTxt, viaLayer)
        error('CircularFPC:ExportReadbackFailed', 'Physical DXF must declare %s layer.', viaLayer);
    end
    viaC = pc(strcmp({pc.layer}, viaLayer));
    if numel(viaC) ~= numel(viaIds) || ...
            (~isempty(viaC) && any(abs(sort([viaC.r]) - sort([result.vias(viaIds).padDiameter] / 2)) > 1e-9))
        error('CircularFPC:ExportReadbackFailed', 'Physical via circle mismatch: %s', physFile);
    end
    if numel(pc) ~= (li == 1) * 2 + numel(viaIds)
        error('CircularFPC:ExportReadbackFailed', 'Physical circle count mismatch: %s', physFile);
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
csvCheck = fullfile(tempDir, 'reports', '06_manufacturing_check.csv');
if ~isfile(csvCheck)
    error('CircularFPC:ExportReadbackFailed', 'Missing manufacturing check CSV: %s', csvCheck);
end
t6 = readtable(csvCheck);
expCols6 = {'id', 'measuredMm', 'limitMm', 'marginMm', 'status', 'source', 'code', 'message', 'profile', 'tier'};
if ~isequal(t6.Properties.VariableNames, expCols6)
    error('CircularFPC:ExportReadbackFailed', '06 CSV columns mismatch.');
end
chks = result.manufacturing.checks;
if height(t6) ~= numel(chks)
    error('CircularFPC:ExportReadbackFailed', '06 CSV row count mismatch.');
end
for k = 1:numel(chks)
    if ~strcmp(char(t6.id(k)), chks(k).id) || ...
            abs(t6.measuredMm(k) - chks(k).measuredMm) > 1e-9 || ...
            abs(t6.limitMm(k) - chks(k).limitMm) > 1e-9 || ...
            abs(t6.marginMm(k) - chks(k).marginMm) > 1e-9 || ...
            ~strcmp(char(t6.status(k)), chks(k).status) || ...
            ~strcmp(char(t6.source(k)), chks(k).source) || ...
            ~strcmp(char(t6.code(k)), chks(k).code) || ...
            ~strcmp(char(t6.message(k)), chks(k).message) || ...
            ~strcmp(char(t6.profile(k)), result.manufacturing.profile) || ...
            ~strcmp(char(t6.tier(k)), result.manufacturing.tier)
        error('CircularFPC:ExportReadbackFailed', '06 CSV row %d mismatch.', k);
    end
end
txtNotes = fullfile(tempDir, 'reports', '07_fabrication_notes.txt');
if ~isfile(txtNotes)
    error('CircularFPC:ExportReadbackFailed', 'Missing fabrication notes: %s', txtNotes);
end
notes = fileread(txtNotes);
if isempty(notes) || ~contains(notes, 'NOT_GENERATED') || ~contains(notes, 'Gerber')
    error('CircularFPC:ExportReadbackFailed', '07 fabrication notes content mismatch.');
end
csvManifest = fullfile(tempDir, 'reports', '08_file_manifest.csv');
if ~isfile(csvManifest)
    error('CircularFPC:ExportReadbackFailed', 'Missing file manifest: %s', csvManifest);
end
t8 = readtable(csvManifest);
if ~isequal(t8.Properties.VariableNames, {'relativePath', 'role', 'sizeBytes', 'sha256'})
    error('CircularFPC:ExportReadbackFailed', '08 manifest columns mismatch.');
end
if height(t8) ~= countFilesRecursive(tempDir) - 1
    error('CircularFPC:ExportReadbackFailed', '08 manifest row count mismatch.');
end
rel8 = string(t8.relativePath);
if any(strcmp(rel8, 'reports/08_file_manifest.csv'))
    error('CircularFPC:ExportReadbackFailed', '08 manifest must not list itself.');
end
if any(startsWith(rel8, '/')) || any(contains(rel8, '\')) || any(contains(rel8, '..'))
    error('CircularFPC:ExportReadbackFailed', '08 manifest relativePath invalid.');
end
roles8 = {'board_outline', 'drill_map', 'copper_centerline', 'copper_physical', ...
    'preview', 'report', 'generation_status'};
for k = 1:height(t8)
    rel = char(t8.relativePath(k));
    if ~ismember(char(t8.role(k)), roles8)
        error('CircularFPC:ExportReadbackFailed', '08 manifest invalid role for %s.', rel);
    end
    abs8 = fullfile(tempDir, rel);
    if ~isfile(abs8)
        error('CircularFPC:ExportReadbackFailed', '08 manifest file missing: %s', rel);
    end
    d8 = dir(abs8);
    if t8.sizeBytes(k) ~= d8.bytes
        error('CircularFPC:ExportReadbackFailed', '08 manifest size mismatch: %s', rel);
    end
    sha8 = char(t8.sha256(k));
    if isempty(regexp(sha8, '^[0-9a-f]{64}$', 'once')) || ~strcmp(sha8, sha256File(abs8))
        error('CircularFPC:ExportReadbackFailed', '08 manifest sha256 mismatch: %s', rel);
    end
end
if isempty(fileread(fullfile(tempDir, 'generation_status.txt')))
    error('CircularFPC:ExportReadbackFailed', 'Empty generation status.');
end
end

function checkDxfBase(txt, label)
% Readback: DXF must declare AC1015, mm (INSUNITS 4), CRLF and no TEXT.
if ~contains(txt, 'AC1015')
    error('CircularFPC:ExportReadbackFailed', '%s must declare AC1015.', label);
end
lines = strtrim(strsplit(txt, newline));
insIdx = find(strcmp(lines, '$INSUNITS'), 1);
if isempty(insIdx) || insIdx + 2 > numel(lines) || ...
        ~strcmp(lines{insIdx + 1}, '70') || str2double(lines{insIdx + 2}) ~= 4
    error('CircularFPC:ExportReadbackFailed', '%s $INSUNITS must be 4 (mm).', label);
end
if ~contains(txt, sprintf('\r\n'))
    error('CircularFPC:ExportReadbackFailed', '%s must use CRLF line endings.', label);
end
if contains(txt, 'TEXT')
    error('CircularFPC:ExportReadbackFailed', '%s must not contain TEXT entities.', label);
end
end

function [circles, w43, nPoly] = readDxfEntities(txt)
% Readback parser: CIRCLE entities (layer/center/radius) and LWPOLYLINE
% group-43 widths plus polyline count.
lines = strtrim(strsplit(txt, newline));
circles = struct('layer', {}, 'cx', {}, 'cy', {}, 'r', {});
w43 = [];
nPoly = 0;
k = 1;
while k + 1 <= numel(lines)
    if strcmp(lines{k}, '0')
        entType = lines{k + 1};
        j = k + 2;
        if strcmp(entType, 'CIRCLE')
            layer = '';
            cx = NaN;
            cy = NaN;
            r = NaN;
            while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
                code = str2double(lines{j});
                val = lines{j + 1};
                switch code
                    case 8
                        layer = val;
                    case 10
                        cx = str2double(val);
                    case 20
                        cy = str2double(val);
                    case 40
                        r = str2double(val);
                end
                j = j + 2;
            end
            circles(end + 1) = struct('layer', layer, 'cx', cx, 'cy', cy, 'r', r); %#ok<AGROW>
            k = j;
        elseif strcmp(entType, 'LWPOLYLINE')
            nPoly = nPoly + 1;
            while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
                if strcmp(lines{j}, '43')
                    w43(end + 1) = str2double(lines{j + 1}); %#ok<AGROW>
                end
                j = j + 2;
            end
            k = j;
        else
            k = k + 1;
        end
    else
        k = k + 1;
    end
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
    escName, term.xy(1), -term.xy(2), labelX - 0.05, labelY - 0.06);
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
expectedColumns = {'name', 'xMm', 'yMm', 'diameterMm', 'drillMm', ...
    'layer', 'fromLayer', 'toLayer', 'removable', 'role', ...
    'placementRegion', 'bridgeAngleDeg'};
if ~isequal(t.Properties.VariableNames, expectedColumns)
    error('CircularFPC:ExportReadbackFailed', ...
        'CSV columns must describe physical pads/vias and terminal placement metadata.');
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
