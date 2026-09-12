function varargout = Dxf_Svg_Reports(operation, varargin)
% Atomic DXF/SVG/CSV/TXT export with lightweight readback (R4).
% Triple-track DXF: legacy centerline files (dxf/Ln/NN_copper_Ln.dxf) keep
% their byte contract; physical CAM-reference files
% (dxf/Ln/NN_copper_physical_Ln.dxf) add group-43 trace width and functional
% via-pad circles; COMSOL solid files
% (dxf/Ln/NN_copper_solid_Ln.dxf) contain only the closed main-coil outline
% so that a 2D DXF import can be selected as a domain or boundary. Terminal
% arcs, connection leads, pads, vias, and layer-transition geometry are
% intentionally omitted for COMSOL users to connect in their own model.
% Additive COMSOL terminal files
% (dxf/Ln/NN_copper_solid_with_terminals_Ln.dxf) repeat that closed
% main-coil outline unchanged and add the L1 center-region terminals: the two
% terminal leads as closed copper strips with straight short-edge caps plus
% the PAD_A/PAD_B disks. They still omit every via, drill, via annulus, and
% inter-layer transition shape, and they never modify the copper_solid files.
% Drills are through-holes; non-functional via pads are removed. The two
% independent electrode pads are explicit L1 copper and are retained in the
% physical DXF only.
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
if ~isfolder(cfg.outputRoot)
    mkdir(cfg.outputRoot);
end
tempDir = tempname(cfg.outputRoot);
mkdir(tempDir);
stagingCleanup = onCleanup(@() removeStagingFolder(tempDir));
writeAllFiles(cfg, result, tempDir, formal);
verifyWrittenOutputs(cfg, result, tempDir);
CircularFpc.Export.Publish_Atomically(tempDir, formal);
clear stagingCleanup;
outputPath = formal;
end

function writeAllFiles(cfg, result, outDir, formalPath)
% 输出文件树：
%   dxf/         板框 + 每物理层铜层 + 功能过孔焊环 + 贯穿钻孔图
%   preview/JLC/1_path_only/     走线路径（细线）
%   preview/JLC/2_trace_only/    实际线宽（无焊盘无过孔）
%   preview/JLC/3_trace_pad_via/ 实际线宽 + 焊盘 + 过孔
%   preview/COMSOL/          基于 copper_solid DXF 闭合铜实体的预览
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
    writeSolidCopperDxf(fullfile(layerDir, sprintf('%02d_copper_solid_L%d.dxf', li, li)), cfg, result, li);
    writeTerminalSolidCopperDxf(fullfile(layerDir, ...
        sprintf('%02d_copper_solid_with_terminals_L%d.dxf', li, li)), cfg, result, li);
end
if cfg.enablePreview
    previewRoot = fullfile(outDir, 'preview');
    % 目录名说明"这张图画了什么"，数字前缀固定排序：
    %   JLC/1_path_only     按走线路径画细线（不按线宽），无焊盘无过孔
    %   JLC/2_trace_only    按实际线宽画铜线，无焊盘无过孔
    %   JLC/3_trace_pad_via 实际线宽 + 焊盘 + 独立电极 + 过孔
    %   COMSOL/1_coil_only      闭合铜实体，只含主螺旋
    %   COMSOL/2_coil_with_lead 闭合铜实体 + 端子引线（每层一条连续轮廓，无焊盘）
    jlcPathDir = fullfile(previewRoot, 'JLC', '1_path_only');
    jlcTraceDir = fullfile(previewRoot, 'JLC', '2_trace_only');
    jlcPadViaDir = fullfile(previewRoot, 'JLC', '3_trace_pad_via');
    comsolDir = fullfile(previewRoot, 'COMSOL', '1_coil_only');
    comsolLeadDir = fullfile(previewRoot, 'COMSOL', '2_coil_with_lead');
    mkdir(jlcPathDir);
    mkdir(jlcTraceDir);
    mkdir(jlcPadViaDir);
    mkdir(comsolDir);
    mkdir(comsolLeadDir);
    % 统一命名：01 总览、02 连接区，逐层统一为 "1x_layer_Lx_<role>"，其中 x 就是
    % 物理层号。编号恒表示同一件事（L3 在任何层数下都是 13），不再按出现顺序重排，
    % 因此文件名可以安全写进文档与脚本。
    overviewName = '01_overview.svg';
    zoneName = '02_connection_zone.svg';
    [~, jlcKinds, ~] = jlcPreviewKinds();
    jlcDirs = {jlcPathDir, jlcTraceDir, jlcPadViaDir};
    for k = 1:numel(jlcKinds)
        writeSvgFull(fullfile(jlcDirs{k}, overviewName), cfg, result, jlcKinds{k});
        writeSvgConnectionZone(fullfile(jlcDirs{k}, zoneName), cfg, result, jlcKinds{k});
    end
    writeSvgComsolFull(fullfile(comsolDir, overviewName), cfg, result);
    writeSvgComsolLeadFull(fullfile(comsolLeadDir, overviewName), cfg, result);
    for li = 1:numel(result.layerPaths)
        role = svgLayerRole(result, li);
        fileName = layerFigureName(li, role);
        for k = 1:numel(jlcKinds)
            writeSvgLayer(fullfile(jlcDirs{k}, fileName), cfg, result, li, jlcKinds{k});
        end
        writeSvgComsolLayer(fullfile(comsolDir, fileName), cfg, result, li);
        writeSvgComsolLeadLayer(fullfile(comsolLeadDir, fileName), cfg, result, li);
    end
    % zh/ 与 en/ 是完整镜像：与上面 JLC/、COMSOL/ 同结构、同文件名，只把标注换成
    % 中文或英文。每张标注图都读回上面刚写出的预览再封装，几何同源、不存在第二套
    % 绘图代码。写在这里是为了让它们进入同一批原子发布与 manifest。
    CircularFpc.Export.Annotated_Previews('write', cfg, result, previewRoot);
end
writeReports(cfg, result, reportsDir);
writeStatus(cfg, formalPath, fullfile(outDir, 'generation_status.txt'));
writeFileManifest(fullfile(reportsDir, '08_file_manifest.csv'), outDir);
end

function name = layerFigureName(li, role)
% 逐层预览的统一文件名："1x_layer_Lx_<role>"，十位固定为 1、个位为物理层号，
% 因此 L3 在四层板与六层板下都叫 13，编号不随配置漂移。
if li > 9
    error('CircularFPC:ExportWriteFailed', ...
        'Layer figure numbering supports up to 9 layers, got L%d.', li);
end
name = sprintf('1%d_layer_L%d_%s.svg', li, li, role);
end

function writeBoardDxf(filename, cfg, boardLoops)
% 板框 DXF：9 个闭合、带可配置实际线宽的 LWPOLYLINE（1 外边界 +
% 4 个平台槽 + 4 个耳朵内置挖槽）。
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
    if ~isempty(result.electrodePads)
        layerNames{end + 1} = 'ELECTRODE_L1';
    end
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
    for p = 1:numel(result.electrodePads)
        writeCircle(fid, result.electrodePads(p).xy, result.electrodePads(p).diameter / 2, 'ELECTRODE_L1');
    end
end
for k = 1:numel(viaIds)
    v = result.vias(viaIds(k));
    writeCircle(fid, v.xy, v.padDiameter / 2, sprintf('VIA_PAD_L%d', li));
end
writeDxfFooter(fid);
end

function writeSolidCopperDxf(filename, cfg, result, li)
% COMSOL-oriented copper geometry: convert only the main coil centerline
% into a closed 2D copper strip outline. DXF LWPOLYLINE group 43 is only metadata
% for a variable-width line and is not reliably converted into a 2D domain
% by COMSOL's 2D DXF importer, so the outline is written explicitly. Open
% path ends are clipped with straight short caps (not round end arcs).
layerName = sprintf('COPPER_SOLID_L%d', li);
fid = openOutputFile(filename);
c = onCleanup(@() fclose(fid));
writeDxfHeader(fid, {layerName});
lp = result.layerPaths(li);
paths = {};
if ~isempty(lp.coilXY)
    paths{end + 1} = comsolMainCoilPath(cfg, result, li); %#ok<AGROW>
end
for k = 1:numel(paths)
    rings = {explicitComsolRing(cfg, result, li)};
    for r = 1:numel(rings)
        ring = rings{r};
        % Keep the LWPOLYLINE closed flag for CAD readers, and explicitly
        % write the final short-cap edge for COMSOL importers.
        writeLwPolyline(fid, ring, layerName, true);
    end
end
writeDxfFooter(fid);
end

function writeTerminalSolidCopperDxf(filename, cfg, result, li)
% Additive COMSOL variant of the solid copper DXF. 本层主螺旋与画在本层的端子铜
% 合并成**一条**闭合轮廓：每个活动层恰好一个连通体，COMSOL 2D 选中即一个域。
% copper_solid_Lli.dxf 保持原字节不变；本变体写出的是合并结果，因此不再与它顶点
% 相同——这是合并的必然代价，读回按合并后的规范轮廓核对。
% 不写 PAD_A/PAD_B 圆盘；任何层都不写 VIA/DRILL、过孔焊环或层间过渡几何。
layerName = sprintf('COPPER_SOLID_TERMINALS_L%d', li);
entities = comsolTerminalEntities(cfg, result, li);
fid = openOutputFile(filename);
c = onCleanup(@() fclose(fid));
writeDxfHeader(fid, {layerName});
for k = 1:numel(entities)
    % Keep the LWPOLYLINE closed flag for CAD readers, and explicitly write the
    % final short edge so a COMSOL importer sees a closed boundary.
    writeLwPolyline(fid, entities(k).ring, layerName, true);
end
writeDxfFooter(fid);
end

function entities = comsolTerminalEntities(cfg, result, li)
% Canonical copper entity list for *_copper_solid_with_terminals_Lli.dxf.
%
% 每个活动线圈层只输出**一条**闭合铜轮廓：本层主螺旋与画在本层的端子铜合并成
% 一个连通体。合并是这份文件对 COMSOL 2D 有用的前提——一个闭合环选中就是一个
% 域；不合并时线圈与引线各是独立实体、只能靠过孔在层间相连，而 2D 选域表达不
% 了这种连接。
%
% 引线归到哪一层：
%   入口引线 -> 它接触的那个线圈端所在层；
%   回流引线 -> 路线中最后一个层间过孔的起点层（电流从该层返回）。
% 4/2 下即 L1 = PAD_A + COIL_L1，L4 = COIL_L4 + VOUT 回流段 + PAD_B 引线。
% 回流引线若留在 L1，L1 会被切成两块只在过孔处相连的孤岛。
%
% 不写 PAD_A/PAD_B 圆盘：本变体只承载导体，端点如何终止交给求解器。
fieldNames = {'name', 'kind', 'ring', 'startXY', 'endXY', 'leads'};
entities = struct(fieldNames{1}, {}, fieldNames{2}, {}, fieldNames{3}, {}, ...
    fieldNames{4}, {}, fieldNames{5}, {}, fieldNames{6}, {});
if ~isempty(result.layerPaths(li).coilXY) && any(result.activeCoilLayers == li)
    parts = {explicitComsolRing(cfg, result, li)};
    leads = terminalLeadPaths(result);
    for k = 1:numel(result.layerPaths(li).connectionPaths)
        cp = result.layerPaths(li).connectionPaths{k};
        if isTerminalLeadPath(cp, leads)
            continue;   % 引线由下面的归属规则处理，避免重复并入
        end
        if touchesInterLayerVia(cp, result)
            % 本层从线圈端连到层间过孔的走线，是把引线接进线圈所必需的铜。
            parts{end + 1} = leadStripRing( ...
                extendForOverlap(cp, result, cfg.traceWidth), cfg.traceWidth / 2); %#ok<AGROW>
        end
    end
    leadLayer = terminalLeadLayers(result);
    absorbed = {};
    for k = 1:numel(leads)
        if leadLayer(k) ~= li
            continue;
        end
        parts{end + 1} = leadStripRing( ...
            extendForOverlap(leads{k}, result, cfg.traceWidth), cfg.traceWidth / 2); %#ok<AGROW>
        absorbed{end + 1} = terminalLeadName(k); %#ok<AGROW>
    end
    ring = mergeCopperRings(parts, li);
    % leads 记录本层吸收了哪几条端子引线。空表示该层只有主螺旋，读回据此判断
    % "面积必须变大"只适用于真的并入了引线的层。
    entities(end + 1) = struct('name', sprintf('COIL_WITH_LEAD_L%d', li), ...
        'kind', 'coil_with_lead', 'ring', ring, ...
        'startXY', ring(1, :), 'endXY', ring(end, :), ...
        'leads', strjoin(absorbed, '+'));
end
end

function ring = mergeCopperRings(parts, li)
% 把同一层的若干闭合铜带并成一条闭合轮廓，并 fail closed：合并不出一个无孔
% 连通域就说明端子铜没有真正接到线圈上，此时宁可报错也不要写出几何上不成立的
% 轮廓。
[px, py] = explodeRing(parts{1});
poly = polyshape(px, py, 'Simplify', false);
for k = 2:numel(parts)
    [qx, qy] = explodeRing(parts{k});
    poly = union(poly, polyshape(qx, qy, 'Simplify', false));
end
poly = simplify(poly);
if poly.NumRegions ~= 1 || poly.NumHoles ~= 0
    error('CircularFPC:ExportWriteFailed', ...
        ['COMSOL terminal copper on L%d must merge into one hole-free ring ' ...
         '(got %d region(s), %d hole(s)).'], li, poly.NumRegions, poly.NumHoles);
end
ring = poly.Vertices;
if norm(ring(1, :) - ring(end, :)) > 1e-12
    ring(end + 1, :) = ring(1, :);
end
end

function xy = extendForOverlap(xy, result, reach)
% 把"接线圈/过孔"的那一端沿自身切向延长 reach，让偏置后的铜条真正重叠。
% 焊盘那一端保持原样：它是引线的自由端，长度不该悄悄变。
%
% 为什么需要：线圈铜条的端帽是径向的，引线铜条的端帽垂直于引线切向。两段铜条
% 只在端点相切时，偏置后可能只共用一个角点，polyshape 并集便得到两个区域。
% 端子引线合并曾因此报 "got 2 region(s)"。
atPad = false(2, 1);
for e = 1:2
    if e == 1
        pt = xy(1, :);
    else
        pt = xy(end, :);
    end
    for p = 1:numel(result.pads)
        if norm(pt - result.pads(p).xy) < 1e-4
            atPad(e) = true;
        end
    end
end
if ~atPad(2) && ~atPad(1)
    atPad(2) = true;   % 两端都不在焊盘上：只延长起点端，保持结果确定
end
if ~atPad(2)
    d = xy(end, :) - xy(end - 1, :);
    d = d / norm(d);
    xy(end + 1, :) = xy(end, :) + reach * d;
elseif ~atPad(1)
    d = xy(1, :) - xy(2, :);
    d = d / norm(d);
    xy = [xy(1, :) + reach * d; xy];
end
end

function [x, y] = explodeRing(ring)
% 去掉闭合重复点与相邻重合点后再交给 polyshape。线圈铜带按密集采样的中线
% 偏置而来，相邻点可到 1e-9 量级，直接构造会让 polyshape 报"顶点近乎重复"并
% 静默简化；这里先自己清一遍，简化就只发生在下面那次显式 simplify。
xy = ring;
if size(xy, 1) > 1 && norm(xy(1, :) - xy(end, :)) <= 1e-12
    xy(end, :) = [];
end
keep = [true; vecnorm(diff(xy, 1, 1), 2, 2) > 1e-7];
xy = xy(keep, :);
x = xy(:, 1);
y = xy(:, 2);
end

function yn = isTerminalLeadPath(cp, leads)
yn = false;
for k = 1:numel(leads)
    if pathMatches(cp, leads{k})
        yn = true;
        return;
    end
end
end

function yn = pathMatches(a, b)
yn = (norm(a(1, :) - b(1, :)) < 1e-4 && norm(a(end, :) - b(end, :)) < 1e-4) || ...
     (norm(a(1, :) - b(end, :)) < 1e-4 && norm(a(end, :) - b(1, :)) < 1e-4);
end

function yn = touchesInterLayerVia(cp, result)
% 走线端点落在某个跨层过孔上，即视为"本层内接往层间过孔的铜"。
yn = false;
if size(cp, 1) < 2
    return;
end
ends = [cp(1, :); cp(end, :)];
for k = 1:size(ends, 1)
    for v = 1:numel(result.vias)
        via = result.vias(v);
        if via.fromLayer ~= via.toLayer && norm(ends(k, :) - via.xy) < 1e-4
            yn = true;
            return;
        end
    end
end
end

function layers = terminalLeadLayers(result)
% 每条端子引线画到哪一层，规则见 comsolTerminalEntities 的说明。单活动层组合
% 没有层间过孔，两条引线都落在唯一的活动层上。
route = result.seriesRoute;
leads = terminalLeadPaths(result);
layers = zeros(1, numel(leads));
layers(1) = coilLayerTouchedBy(route, leads{1});
returnLayer = lastInterLayerViaStartLayer(route);
if isempty(returnLayer)
    layers(2) = coilLayerTouchedBy(route, leads{2});
else
    layers(2) = returnLayer;
end
end

function li = coilLayerTouchedBy(route, leadPath)
% 引线端点与某个 COIL_L* 段端点重合时，返回该线圈段所在层。
li = 0;
for k = 1:numel(route)
    if ~strncmp(route(k).name, 'COIL_L', 6)
        continue;
    end
    for e = 1:2
        if e == 1
            pt = leadPath(1, :);
        else
            pt = leadPath(end, :);
        end
        if norm(pt - route(k).startXY) < 1e-4 || norm(pt - route(k).endXY) < 1e-4
            li = route(k).startLayer;
            return;
        end
    end
end
if li == 0
    error('CircularFPC:ExportWriteFailed', ...
        'Cannot resolve which coil layer a terminal lead attaches to.');
end
end

function li = lastInterLayerViaStartLayer(route)
% 路线中最后一个跨层过孔的起点层；没有跨层过孔时返回空。
li = [];
for k = 1:numel(route)
    if route(k).startLayer ~= route(k).endLayer
        li = route(k).startLayer;
    end
end
end

function leads = terminalLeadPaths(result)
% Resolve the two center leads from the series route by name, then match the
% stored L1 connection path by its endpoints. Route names stay the single
% source of truth for which geometry is a terminal lead, and the returned
% paths are oriented start-to-end so repeated exports stay byte-identical.
names = {terminalLeadName(1), terminalLeadName(2)};
route = result.seriesRoute;
leads = cell(1, numel(names));
for k = 1:numel(names)
    idx = find(strcmp({route.name}, names{k}), 1);
    if isempty(idx)
        error('CircularFPC:ExportWriteFailed', ...
            'COMSOL terminal copper requires the %s route on layer 1.', names{k});
    end
    [leads{k}, found] = matchConnectionPath(result.layerPaths(1).connectionPaths, ...
        route(idx).startXY, route(idx).endXY);
    if ~found
        error('CircularFPC:ExportWriteFailed', ...
            'COMSOL terminal copper cannot map %s to an L1 connection path.', names{k});
    end
end
end

function [xy, found] = matchConnectionPath(paths, startXY, endXY)
xy = [];
found = false;
for k = 1:numel(paths)
    p = paths{k};
    if size(p, 1) < 2
        continue;
    end
    direct = norm(p(1, :) - startXY) < 1e-4 && norm(p(end, :) - endXY) < 1e-4;
    reverse = norm(p(1, :) - endXY) < 1e-4 && norm(p(end, :) - startXY) < 1e-4;
    if direct || reverse
        if reverse
            p = flipud(p);
        end
        xy = p;
        found = true;
        return;
    end
end
end

function ring = leadStripRing(xy, halfWidth)
% Closed copper strip for one terminal lead: offset the sampled centerline by
% half the trace width and close both ends with one straight short edge
% perpendicular to the end tangent. Straight caps (never round end arcs) keep
% each lead a COMSOL-selectable 2D domain with an explicit first/last vertex.
keep = [true; vecnorm(diff(xy, 1, 1), 2, 2) > 1e-12];
xy = xy(keep, :);
if size(xy, 1) < 2
    error('CircularFPC:ExportWriteFailed', ...
        'COMSOL terminal lead needs at least two distinct centerline points.');
end
tangent = [xy(2, :) - xy(1, :); xy(3:end, :) - xy(1:end-2, :); xy(end, :) - xy(end-1, :)];
tangent = tangent ./ vecnorm(tangent, 2, 2);
normal = [-tangent(:, 2), tangent(:, 1)];
left = xy + halfWidth * normal;
right = xy - halfWidth * normal;
ring = [left; flipud(right); left(1, :)];
end

function a = polygonArea(xy)
% Shoelace area of a ring whose first vertex repeats as the last one.
x = xy(1:end-1, 1);
y = xy(1:end-1, 2);
a = abs(sum(x .* y([2:end, 1]) - y .* x([2:end, 1]))) / 2;
end

function xy = comsolMainCoilPath(cfg, result, li)
% Isolate the main Archimedean spiral for the COMSOL copy: both the outer
% via-contact arc and any inner via/terminal extension are trimmed, leaving
% the open spiral ends for the straight cap closure. The manufacturing and
% centerline DXFs continue to use the original layer path unchanged.
xy = result.layerPaths(li).coilXY;
activeIndex = find(result.activeCoilLayers == li, 1);
if isempty(xy) || isempty(activeIndex)
    return;
end
spanTurns = cfg.turnsPerCoilLayer;
is44 = cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4;
is66 = cfg.boardLayerCount == 6 && cfg.coilLayerCount == 6;
if is44
    spanExtra = [0, 0.25, 0, -0.25];
    spanTurns = spanTurns + spanExtra(activeIndex);
elseif is66
    spanExtra = [0, 0.25, 0, 0.50, 0, 0.25];
    spanTurns = spanTurns + spanExtra(activeIndex);
end
rStart = result.effectiveDimensions.coilInnerDiameter / 2 + cfg.traceWidth / 2;
phaseExtra = zeros(1, numel(result.activeCoilLayers));
if is44
    phaseExtra = [0 90 90 0];
elseif is66
    phaseExtra = [0 90 90 -90 -90 0];
end
phase = cfg.connectionAngleDeg + phaseExtra(activeIndex) ...
    + 90*floor((activeIndex-1)/2)*(~is44 && ~is66);
t = linspace(0, 2*pi*spanTurns, round(cfg.samplePointsPerTurn*spanTurns)+1).';
direction = 1 - 2*mod(activeIndex+1,2);
angle = deg2rad(phase) + direction*t;
radius = rStart + result.effectiveDimensions.coilPitch*t/(2*pi);
xy = radius .* [cos(angle), sin(angle)];
if direction < 0
    xy = flipud(xy);
end
end

function ring = comsolStrip(xy, halfWidth)
% Offset the spiral, preserving four explicit port corners. Radial ports
% coincide between mirrored layers; simplification never crosses a cap.
tangent = [xy(2,:)-xy(1,:); xy(3:end,:)-xy(1:end-2,:); xy(end,:)-xy(end-1,:)];
tangent = tangent ./ vecnorm(tangent,2,2);
normal = [-tangent(:,2), tangent(:,1)];
left = xy + halfWidth*normal;
right = xy - halfWidth*normal;
for k = [1 size(xy,1)]
    radial = xy(k,:)/norm(xy(k,:));
    radial = radial * sign(dot(radial,normal(k,:)));
    left(k,:) = xy(k,:) + halfWidth*radial;
    right(k,:) = xy(k,:) - halfWidth*radial;
end
% Retain sampled sides: each cap remains exactly one 0.2 mm edge.
ring = [left; flipud(right)];
end

function rings = traceOutlineRings(xy, halfWidth)
% Return closed polygon rings for a buffered open path. polybuffer is part
% of MATLAB's polyshape functionality in the supported R2026a runtime.
rings = {};
if isempty(xy) || size(xy, 1) < 2
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
                ring = flattenTraceEndCaps(ring, xy, halfWidth);
            end
            % The sampled spiral can otherwise create tens of thousands of
            % nearly collinear CAD edges. Keep the outline within 5 um of
            % the buffered geometry while making COMSOL Boolean operations
            % practical; the exact CAM reference remains in the physical DXF.
            rings{end + 1} = simplifyClosedRing(ring, 0.005); %#ok<AGROW>
        end
    end
    start = k + 1;
end
end

function ring = flattenTraceEndCaps(ring, xy, halfWidth)
% Replace each local semicircular cap of a buffered open path with a flat
% segment. Points farther than the cap radius are never modified, so other
% turns of the spiral remain untouched.
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
startLocal = startProjection < -tol & startDistanceSquared <= (halfWidth + tol) ^ 2;
ring(startLocal, :) = ring(startLocal, :) - startProjection(startLocal) .* startDirection;
endDelta = ring - xy(end, :);
endProjection = endDelta * endDirection.';
endDistanceSquared = sum(endDelta .^ 2, 2);
endLocal = endProjection > tol & endDistanceSquared <= (halfWidth + tol) ^ 2;
ring(endLocal, :) = ring(endLocal, :) - endProjection(endLocal) .* endDirection;
end

function reduced = simplifyClosedRing(points, tolerance)
% Iterative Ramer-Douglas-Peucker simplification for a closed polygon.
% The tolerance is in mm and is deliberately much smaller than the 0.2 mm
% copper width, so this only removes redundant sampled points.
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

function writeSvgFull(filename, cfg, result, previewKind)
if nargin < 4
    previewKind = 'trace_pad_via';
end
[tracePreviewWidth, previewKindAttr] = jlcPreviewStyle(cfg, previewKind);
fid = fopen(filename, 'w');
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = svgExtent(cfg, result);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" data-preview-kind="%s" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    previewKindAttr, -extent, -extent, 2 * extent, 2 * extent);
for k = 1:numel(result.boardLoops)
    if result.boardLoops(k).isHole
        cutoutRole = svgBoardCutoutRole(result.boardLoops(k));
        glassRole = svgBoardGlassRole(result.boardLoops(k));
        fprintf(fid, '<polygon points="%s" fill="#ffffff" fill-opacity="1" stroke="none" data-board-role="%s"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cutoutRole);
        fprintf(fid, '<polygon points="%s" fill="#8fcfdc" fill-opacity="0.32" stroke="#000000" stroke-width="%.4f" data-board-role="%s"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth, glassRole);
    else
        fprintf(fid, '<polygon points="%s" fill="#ffcc1a" fill-opacity="1" stroke="#8c1aa6" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    end
end
colors = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
for li = 1:numel(result.layerPaths)
    cidx = mod(li - 1, 4) + 1;
    if ~isempty(result.layerPaths(li).coilXY)
        fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
            pointsAttr(result.layerPaths(li).coilXY), colors{cidx}, tracePreviewWidth);
    end
    paths = result.layerPaths(li).connectionPaths;
    for k = 1:numel(paths)
        fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
            pointsAttr(paths{k}), colors{cidx}, tracePreviewWidth);
    end
end
if showsPadsAndVias(previewKind)
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
    for k = 1:numel(result.electrodePads)
        p = result.electrodePads(k);
        fprintf(fid, '<circle data-electrode-name="%s" cx="%.6f" cy="%.6f" r="%.6f" fill="#ff7f0e" stroke="#000000" stroke-width="0.15"/>\n', ...
            p.name, p.xy(1), -p.xy(2), p.diameter / 2);
    end
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function writeSvgLayer(filename, cfg, result, li, previewKind)
% 每层单独预览：板框 + 该层铜（线圈 + 连接路径）+ L1 焊盘 + 该层过孔。
if nargin < 5
    previewKind = 'trace_pad_via';
end
[tracePreviewWidth, previewKindAttr] = jlcPreviewStyle(cfg, previewKind);
fid = fopen(filename, 'w');
if fid < 0
    error('CircularFPC:ExportWriteFailed', 'Cannot open SVG for writing: %s', filename);
end
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = svgExtent(cfg, result);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" data-preview-kind="%s" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    previewKindAttr, -extent, -extent, 2 * extent, 2 * extent);
for k = 1:numel(result.boardLoops)
    if result.boardLoops(k).isHole
        cutoutRole = svgBoardCutoutRole(result.boardLoops(k));
        glassRole = svgBoardGlassRole(result.boardLoops(k));
        fprintf(fid, '<polygon points="%s" fill="#ffffff" fill-opacity="1" stroke="none" data-board-role="%s"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cutoutRole);
        fprintf(fid, '<polygon points="%s" fill="#8fcfdc" fill-opacity="0.32" stroke="#000000" stroke-width="%.4f" data-board-role="%s"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth, glassRole);
    else
        fprintf(fid, '<polygon points="%s" fill="#ffcc1a" fill-opacity="1" stroke="#8c1aa6" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    end
end
colors = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
cidx = mod(li - 1, 4) + 1;
if ~isempty(result.layerPaths(li).coilXY)
    fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
        pointsAttr(result.layerPaths(li).coilXY), colors{cidx}, tracePreviewWidth);
end
paths = result.layerPaths(li).connectionPaths;
for k = 1:numel(paths)
    fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
        pointsAttr(paths{k}), colors{cidx}, tracePreviewWidth);
end
if showsPadsAndVias(previewKind)
    if li == 1
        for k = 1:numel(result.pads)
            p = result.pads(k);
            fprintf(fid, '<circle cx="%.6f" cy="%.6f" r="%.6f" fill="#e61919" stroke="#000000" stroke-width="0.15"/>\n', ...
                p.xy(1), -p.xy(2), cfg.padDiameter / 2);
        end
        for k = 1:numel(result.electrodePads)
            p = result.electrodePads(k);
            fprintf(fid, '<circle data-electrode-name="%s" cx="%.6f" cy="%.6f" r="%.6f" fill="#ff7f0e" stroke="#000000" stroke-width="0.15"/>\n', ...
                p.name, p.xy(1), -p.xy(2), p.diameter / 2);
        end
    end
    for k = 1:numel(result.vias)
        writeSvgLayerVia(fid, cfg, result.vias(k));
    end
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function writeSvgComsolFull(filename, cfg, result)
% COMSOL preview of the same closed copper-strip rings written to
% copper_solid_L*.dxf. No terminals, vias, connection leads, or centerlines
% are drawn here; the board outline is a light reference only.
fid = fopen(filename, 'w');
if fid < 0
    error('CircularFPC:ExportWriteFailed', 'Cannot open SVG for writing: %s', filename);
end
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = svgExtent(cfg, result);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" data-preview-kind="comsol-dxf" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    -extent, -extent, 2 * extent, 2 * extent);
writeSvgComsolReferenceBoard(fid, cfg, result);
for li = 1:numel(result.layerPaths)
    writeSvgComsolRing(fid, cfg, result, li);
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function writeSvgComsolLayer(filename, cfg, result, li)
% Per-layer COMSOL preview. Inactive physical layers intentionally contain
% only the light board reference because their copper_solid DXF is empty.
fid = fopen(filename, 'w');
if fid < 0
    error('CircularFPC:ExportWriteFailed', 'Cannot open SVG for writing: %s', filename);
end
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = svgExtent(cfg, result);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" data-preview-kind="comsol-dxf" data-dxf-layer="L%d" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    li, -extent, -extent, 2 * extent, 2 * extent);
writeSvgComsolReferenceBoard(fid, cfg, result);
writeSvgComsolRing(fid, cfg, result, li);
fprintf(fid, '</svg>\n');
fclose(fid);
end

function writeSvgComsolLeadFull(filename, cfg, result)
% COMSOL preview of the copper_solid_with_terminals_L*.dxf variant: each active
% layer's main spiral merged with its own terminal lead into one closed ring.
% No pad disk, via, drill, via annulus, or inter-layer transition is drawn, so
% this preview shows exactly what those DXFs hold.
fid = fopen(filename, 'w');
if fid < 0
    error('CircularFPC:ExportWriteFailed', 'Cannot open SVG for writing: %s', filename);
end
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = svgExtent(cfg, result);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" data-preview-kind="comsol-dxf-with-terminals" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    -extent, -extent, 2 * extent, 2 * extent);
writeSvgComsolReferenceBoard(fid, cfg, result);
for li = 1:numel(result.layerPaths)
    writeSvgComsolLeadRing(fid, cfg, result, li);
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function writeSvgComsolLeadLayer(filename, cfg, result, li)
% Per-layer preview of the coil-with-lead variant: one merged closed ring on
% each active layer, matching the corresponding
% *_copper_solid_with_terminals_L*.dxf contents.
fid = fopen(filename, 'w');
if fid < 0
    error('CircularFPC:ExportWriteFailed', 'Cannot open SVG for writing: %s', filename);
end
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
extent = svgExtent(cfg, result);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" data-preview-kind="comsol-dxf-with-terminals" data-dxf-layer="L%d" viewBox="%.6f %.6f %.6f %.6f">\n', ...
    li, -extent, -extent, 2 * extent, 2 * extent);
writeSvgComsolReferenceBoard(fid, cfg, result);
writeSvgComsolLeadRing(fid, cfg, result, li);
fprintf(fid, '</svg>\n');
fclose(fid);
end

function writeSvgComsolLeadRing(fid, cfg, result, li)
% Copper geometry of one with-terminals DXF, in SVG display coordinates.
dxfName = sprintf('dxf/L%d/%02d_copper_solid_with_terminals_L%d.dxf', li, li, li);
entities = comsolTerminalEntities(cfg, result, li);
colors = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
c = colors{mod(li - 1, numel(colors)) + 1};
for k = 1:numel(entities)
    e = entities(k);
    fprintf(fid, '<polygon points="%s" fill="%s" fill-opacity="0.32" stroke="%s" stroke-width="0.025" data-copper-entity="%s" data-copper-kind="%s" data-dxf-layer="L%d" data-dxf-file="%s" data-dxf-closed="explicit" data-dxf-cap="straight-short-edge"/>\n', ...
        pointsAttr(e.ring), c, c, e.name, e.kind, li, dxfName);
end
end

function name = terminalLeadName(index)
% Stable lead names shared by the DXF write order, the SVG preview, and the
% geometry mapping report.
names = {'TRACE_L1_ENTRY', 'TRACE_L1_EXIT'};
name = names{index};
end

function writeComsolTerminalGeometryReport(filename, cfg, result)
% Terminal geometry mapping report for the coil-with-lead variant: one row per
% active layer, giving the merged closed ring's copper area and the first/last
% vertices that prove the body is closed. closed=1 means the body imports as a
% closed 2D region; capMode records how it is closed.
fid = openOutputFile(filename);
c = onCleanup(@() fclose(fid));
fprintf(fid, 'entity,kind,layer,routeNode,dxfFile,closed,vertexCount,areaMm2,capMode,startXMm,startYMm,endXMm,endYMm,firstXMm,firstYMm,lastXMm,lastYMm,firstLastMatch\n');
for li = 1:numel(result.layerPaths)
    dxfFile = sprintf('dxf/L%d/%02d_copper_solid_with_terminals_L%d.dxf', li, li, li);
    entities = comsolTerminalEntities(cfg, result, li);
    for k = 1:numel(entities)
        e = entities(k);
        vertexCount = size(e.ring, 1);
        areaMm2 = polygonArea(e.ring);
        capMode = 'merged_closed_ring';
        first = e.ring(1, :);
        last = e.ring(end, :);
        fprintf(fid, '%s,%s,%d,%s,%s,1,%d,%.6f,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d\n', ...
            e.name, e.kind, li, e.name, dxfFile, vertexCount, areaMm2, capMode, ...
            e.startXY(1), e.startXY(2), e.endXY(1), e.endXY(2), ...
            first(1), first(2), last(1), last(2), ...
            norm(first - last) <= 1e-9);
    end
end
end

function writeSvgComsolReferenceBoard(fid, cfg, result)
for k = 1:numel(result.boardLoops)
    if result.boardLoops(k).isHole
        fprintf(fid, '<polygon points="%s" fill="#f4f7f8" fill-opacity="0.55" stroke="#9aa5aa" stroke-width="%.4f" data-board-role="%s"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth, svgBoardReferenceRole(result.boardLoops(k)));
    else
        fprintf(fid, '<polygon points="%s" fill="none" stroke="#8c1aa6" stroke-width="%.4f" data-board-role="outline-reference"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    end
end

end

function writeSvgComsolRing(fid, cfg, result, li)
if isempty(result.layerPaths(li).coilXY)
    return;
end
ring = explicitComsolRing(cfg, result, li);
colors = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
c = colors{mod(li - 1, numel(colors)) + 1};
dxfName = sprintf('dxf/L%d/%02d_copper_solid_L%d.dxf', li, li, li);
fprintf(fid, '<polygon points="%s" fill="%s" fill-opacity="0.28" stroke="%s" stroke-width="0.025" data-dxf-layer="L%d" data-dxf-file="%s" data-dxf-closed="explicit"/>\n', ...
    pointsAttr(ring), c, c, li, dxfName);
end

function ring = explicitComsolRing(cfg, result, li)
% Keep SVG and COMSOL DXF previews geometrically equivalent.
xy = comsolMainCoilPath(cfg, result, li);
ring = comsolStrip(xy, cfg.traceWidth / 2);
if size(ring, 1) >= 2 && norm(ring(1, :) - ring(end, :)) > 1e-12
    ring(end + 1, :) = ring(1, :);
end
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

function [traceWidth, kindAttr] = jlcPreviewStyle(cfg, previewKind)
% 三种 JLC 预览共用同一批几何，只在"线画多细"和"画不画焊盘/过孔"上分档：
%   path_only     按走线路径画细线，不按线宽，不含焊盘与过孔
%   trace_only    按实际线宽画铜线，仍不含焊盘与过孔
%   trace_pad_via 按实际线宽画铜线，并画焊盘、独立电极与过孔
switch lower(char(previewKind))
    case 'path_only'
        % A centerline DXF has no physical width; use a thin display stroke
        % while preserving the engineering coordinates and path topology.
        traceWidth = 0.04;
        kindAttr = 'jlc-path-only';
    case 'trace_only'
        traceWidth = cfg.traceWidth;
        kindAttr = 'jlc-trace-only';
    case 'trace_pad_via'
        traceWidth = cfg.traceWidth;
        kindAttr = 'jlc-trace-pad-via';
    otherwise
        error('CircularFPC:ExportWriteFailed', 'Unknown JLC preview kind: %s', previewKind);
end
end

function yn = showsPadsAndVias(previewKind)
% 只有 trace_pad_via 画焊盘、独立电极与过孔；前两档只画铜线，避免用端子
% 图元遮住走线本身的形状。
yn = strcmpi(char(previewKind), 'trace_pad_via');
end

function [dirNames, kindNames, kindAttrs] = jlcPreviewKinds()
% JLC 预览的三个档位。目录名带数字前缀以固定排序，kindNames 是内部档位名，
% kindAttrs 是写进 SVG 的 data-preview-kind 值。三张表在这里一次给全，新增
% 档位时不会出现"目录改了、属性没改"的半套状态。
dirNames = {'1_path_only', '2_trace_only', '3_trace_pad_via'};
kindNames = {'path_only', 'trace_only', 'trace_pad_via'};
kindAttrs = {'jlc-path-only', 'jlc-trace-only', 'jlc-trace-pad-via'};
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

function writeSvgConnectionZone(filename, cfg, result, previewKind)
if nargin < 4
    previewKind = 'trace_pad_via';
end
[tracePreviewWidth, previewKindAttr] = jlcPreviewStyle(cfg, previewKind);
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
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" data-preview-kind="%s" viewBox="%.3f %.3f %.3f %.3f">\n', ...
    previewKindAttr, xMin, svgYMin, xMax - xMin, svgYMax - svgYMin);
for k = 1:numel(result.boardLoops)
    if result.boardLoops(k).isHole
        cutoutRole = svgBoardCutoutRole(result.boardLoops(k));
        glassRole = svgBoardGlassRole(result.boardLoops(k));
        fprintf(fid, '<polygon points="%s" fill="#ffffff" fill-opacity="1" stroke="none" data-board-role="%s"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cutoutRole);
        fprintf(fid, '<polygon points="%s" fill="#8fcfdc" fill-opacity="0.32" stroke="#000000" stroke-width="%.4f" data-board-role="%s"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth, glassRole);
    else
        fprintf(fid, '<polygon points="%s" fill="#ffcc1a" fill-opacity="1" stroke="#8c1aa6" stroke-width="%.4f"/>\n', ...
            pointsAttr(result.boardLoops(k).xy), cfg.boardOutlineLineWidth);
    end
end
colors = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
for li = 1:numel(result.layerPaths)
    paths = result.layerPaths(li).connectionPaths;
    for k = 1:numel(paths)
        cidx = mod(li - 1, numel(colors)) + 1;
        fprintf(fid, '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-opacity="0.85"/>\n', ...
            pointsAttr(paths{k}), colors{cidx}, tracePreviewWidth);
    end
end
if showsPadsAndVias(previewKind)
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
end
fprintf(fid, '</svg>\n');
fclose(fid);
end

function s = pointsAttr(xy)
s = sprintf('%.4f,%.4f ', [xy(:,1), -xy(:,2)].');
end

function extent = svgExtent(cfg, result)
if isfield(result.layoutRegions, 'boardExtent') && isfinite(result.layoutRegions.boardExtent)
    boardExtent = result.layoutRegions.boardExtent;
else
    boardExtent = result.effectiveDimensions.boardOuterDiameter / 2;
end
extent = boardExtent + max(cfg.edgeClearance, 0.5);
end

function role = svgBoardCutoutRole(loop)
if startsWith(loop.name, 'mounting_cutout')
    role = 'mounting-cutout';
else
    role = 'slot-cutout';
end
end

function role = svgBoardGlassRole(loop)
if startsWith(loop.name, 'mounting_cutout')
    role = 'mounting-glass';
else
    role = 'slot-glass';
end
end

function role = svgBoardReferenceRole(loop)
if startsWith(loop.name, 'mounting_cutout')
    role = 'mounting-cutout-reference';
else
    role = 'slot-reference';
end
end

function writeReports(cfg, result, reportsDir)
% 报告文件：
%   01_pad_via_coordinates.csv  焊盘/过孔坐标与端子元数据
%   02_layer_map.csv            每物理层是否活动线圈层及绕向
%   03_design_summary.txt       设计摘要（尺寸、总长、直流电阻、串联序列、端子位置）
%   04_turn_scan.csv            匝数可行性扫描（每匝所需径向宽度是否放得下）
%   05_validation_report.txt    验证报告（各 PASS 指标 + 失败信息）
%   10_electrode_pad_coordinates.csv  独立电极焊盘坐标（不属于线圈网络）
%   09_comsol_stackup.csv       COMSOL 三维建模层压表（厚度与 Z 坐标）
%   11_comsol_terminal_geometry.csv  COMSOL 带端子变体的实体几何映射（闭合面积/首尾顶点）
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
fid = fopen(fullfile(reportsDir, '10_electrode_pad_coordinates.csv'), 'w');
if fid < 0
    error('CircularFPC:ExportWriteFailed', 'Cannot open electrode pad report.');
end
fprintf(fid, 'name,xMm,yMm,diameterMm,layer,role,placementRegion,bridgeAngleDeg\n');
for k = 1:numel(result.electrodePads)
    p = result.electrodePads(k);
    fprintf(fid, '%s,%.6f,%.6f,%.6f,%d,%s,%s,%.6f\n', ...
        p.name, p.xy(1), p.xy(2), p.diameter, p.layer, p.role, ...
        p.placementRegion, p.bridgeAngleDeg);
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
fprintf(fid, 'manufacturingProfile: %s\n', result.manufacturing.profile);
fprintf(fid, 'qualificationStatus: %s\n', result.manufacturing.qualificationStatus);
fprintf(fid, 'fpcStackup: %s\n', result.manufacturing.stackup.name);
fprintf(fid, 'nominalFinishedBoardThickness: %.6f mm\n', result.manufacturing.stackup.nominalFinishedThicknessMm);
fprintf(fid, 'computedStackupThickness: %.6f mm\n', result.manufacturing.stackup.computedThicknessMm);
fprintf(fid, 'activeCopperCenterSpacing: %.6f mm\n', result.manufacturing.stackup.activeCopperCenterSpacingMm);
fprintf(fid, 'boardOuterDiameter: %.6f mm\n', eff.boardOuterDiameter);
fprintf(fid, 'boardOverallExtentDiameter: %.6f mm\n', 2 * result.layoutRegions.boardExtent);
fprintf(fid, 'boardSizingMode: %s\n', cfg.boardSizingMode);
fprintf(fid, 'viaEndExtension: %.6f mm\n', eff.viaEndExtension);
fprintf(fid, 'coilInnerDiameter: %.6f mm\n', eff.coilInnerDiameter);
fprintf(fid, 'centerPlatformWidth: %.6f mm\n', eff.centerPlatformWidth);
fprintf(fid, 'centerPlatformHeight: %.6f mm\n', eff.centerPlatformHeight);
fprintf(fid, 'bridgeTargetWidth: %.6f mm\n', eff.bridgeTargetWidth);
fprintf(fid, 'bridgeMinimumWidth: %.6f mm\n', result.layoutRegions.bridgeWidth);
fprintf(fid, 'actualBridgeWidth: %.6f mm\n', eff.actualBridgeWidth);
fprintf(fid, 'bridgeGoverningConstraint: %s\n', result.layoutRegions.bridgeGoverningConstraint);
fprintf(fid, 'routingEnvelopeWidth: %.6f mm\n', result.layoutRegions.routingEnvelopeWidth);
fprintf(fid, 'viaEnvelopeWidth: %.6f mm\n', result.layoutRegions.viaEnvelopeWidth);
fprintf(fid, 'terminalEnvelopeWidth: %.6f mm\n', result.layoutRegions.terminalEnvelopeWidth);
fprintf(fid, 'turnsPerCoilLayer: %d\n', eff.turnsPerCoilLayer);
fprintf(fid, 'coilPitch: %.6f mm\n', eff.coilPitch);
fprintf(fid, 'traceWidth: %.6f mm\n', cfg.traceWidth);
fprintf(fid, 'traceSpacing: %.6f mm\n', cfg.traceSpacing);
fprintf(fid, 'edgeClearance: %.6f mm\n', cfg.edgeClearance);
fprintf(fid, 'boardOutlineLineWidth: %.6f mm\n', cfg.boardOutlineLineWidth);
fprintf(fid, 'geometrySafetyMargin: %.6f mm\n', cfg.geometrySafetyMargin);
fprintf(fid, 'viaPadDiameter: %.6f mm\n', cfg.viaPadDiameter);
fprintf(fid, 'viaDrillDiameter: %.6f mm\n', cfg.viaDrillDiameter);
fprintf(fid, 'viaCoilSpacing: %.6f mm\n', cfg.viaCoilSpacing);
fprintf(fid, 'mountingSlotSpan: %.6f mm\n', cfg.mountingSlotSpan);
fprintf(fid, 'mountingSlotRise: %.6f mm\n', cfg.mountingSlotRise);
fprintf(fid, 'mountingSlotEdgeClearance: %.6f mm\n', cfg.mountingSlotEdgeClearance);
fprintf(fid, 'mountingSlotEndFilletRadius: %.6f mm\n', cfg.mountingSlotEndFilletRadius);
fprintf(fid, 'mountingSlotInnerArcRadius: %.6f mm\n', result.layoutRegions.mountingSlotInnerArcRadius);
fprintf(fid, 'mountingSlotMiddleArcRadius: %.6f mm\n', result.layoutRegions.mountingSlotMiddleArcRadius);
fprintf(fid, 'mountingSlotMiddleArcCenterRadius: %.6f mm\n', result.layoutRegions.mountingSlotMiddleArcCenterRadius);
fprintf(fid, 'mountingSlotOuterArcRadius: %.6f mm\n', result.layoutRegions.mountingSlotOuterArcRadius);
fprintf(fid, 'mountingSlotApexRadius: %.6f mm\n', result.layoutRegions.mountingSlotApexRadius);
fprintf(fid, 'mountingEarApexRadius: %.6f mm\n', result.layoutRegions.mountingEarApexRadius);
fprintf(fid, 'mountingSlotHalfSpanDeg: %.6f\n', result.layoutRegions.mountingSlotHalfSpanDeg);
fprintf(fid, 'viaLugRootOverlap: %.6f mm\n', cfg.viaLugRootOverlap);
fprintf(fid, 'mountingAnglesDeg: %s\n', mat2str(result.layoutRegions.mountingAnglesDeg));
fprintf(fid, 'electrodeAngleDeg: %.6f\n', cfg.electrodeAngleDeg);
fprintf(fid, 'electrodeArmLength: %.6f mm\n', cfg.electrodeArmLength);
fprintf(fid, 'electrodeArmWidth: %.6f mm\n', cfg.electrodeArmWidth);
fprintf(fid, 'electrodeArmGap: %.6f mm\n', cfg.electrodeArmGap);
fprintf(fid, 'electrodePadDiameter: %.6f mm\n', cfg.electrodePadDiameter);
fprintf(fid, 'electrodeRootOverlap: %.6f mm\n', cfg.electrodeRootOverlap);
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
fprintf(fid, 'copperThickness: %.6f mm\n', cfg.copperThickness);
fprintf(fid, 'copperType: %s\n', result.manufacturing.stackup.copperType);
fprintf(fid, 'coverlay: %s, %.6f mm per side\n', result.manufacturing.stackup.coverlayColor, ...
    result.manufacturing.stackup.coverlayThicknessMm);
if isfield(result, 'terminalRouting')
    fprintf(fid, 'terminalRoutingMode: %s\n', result.terminalRouting.mode);
    fprintf(fid, 'terminalEntrySweepDeg: %.6f\n', result.terminalRouting.entrySweepDeg);
    fprintf(fid, 'terminalOutputSweepDeg: %.6f\n', result.terminalRouting.outputSweepDeg);
else
    error('CircularFPC:ExportWriteFailed', ...
        'Terminal routing metadata is missing; terminal routing always runs.');
end
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
for k = 1:numel(result.electrodePads)
    p = result.electrodePads(k);
    fprintf(fid, 'independentElectrode: %s, x=%.6f, y=%.6f, diameter=%.6f mm\n', ...
        p.name, p.xy(1), p.xy(2), p.diameter);
end
% 建议性提示（如平台角部超出内接圆进入桥区走廊）随摘要落盘，便于离线复查。
for k = 1:numel(result.validation.advisories)
    fprintf(fid, 'advisory: %s\n', result.validation.advisories{k});
end
fclose(fid);
fid = fopen(fullfile(reportsDir, '04_turn_scan.csv'), 'w');
% 与配置校验保持一致（最少 2 匝），两种模式都从 2 匝开始扫描；
% t 即物理匝数（完整 360° 圈数），径向跨度 = 线宽 + t*节距。
if strcmp(cfg.boardSizingMode, 'auto')
    % auto 模式：主体圆随主螺旋最大匝数增长；局部凸耳不放大整圈。
    fprintf(fid, 'turns,requiredRadialWidthMm,requiredBoardDiameterMm\n');
    for t = 2:cfg.turnScanMax
        req = cfg.traceWidth + t * eff.coilPitch;
        spanMax = t;
        if cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4
            spanMax = t + 0.25; % 4/4 的 L2 多绕 1/4 圈
        elseif cfg.boardLayerCount == 6 && cfg.coilLayerCount == 6
            spanMax = t + 0.50; % 6/6 的 L4 半匝相位跳转
        end
        termFrac = eff.coilInnerDiameter / 2 + cfg.traceWidth / 2 + ...
            eff.coilPitch * spanMax + cfg.traceWidth / 2;
        boardD = 2 * (termFrac + cfg.edgeClearance + cfg.boardOutlineLineWidth / 2 + ...
            cfg.geometrySafetyMargin);
        fprintf(fid, '%d,%.6f,%.6f\n', t, req, boardD);
    end
else
    fprintf(fid, 'turns,requiredRadialWidthMm,fitsBoard\n');
    available = eff.boardOuterDiameter / 2 - cfg.boardOutlineLineWidth / 2 - ...
        cfg.edgeClearance - eff.coilInnerDiameter / 2;
    for t = 2:cfg.turnScanMax
        req = cfg.traceWidth + t * eff.coilPitch;
        fitsBoard = req <= available + 1e-9;
        if cfg.boardLayerCount == 4 && cfg.coilLayerCount == 4
            % 4/4 的 L2 多绕 0.25 圈：实际可容纳性按最大跨度层判定，
            % 与引擎 requiredBoardDiameter / auto 分支口径一致。
            reqFrac = cfg.traceWidth + (t + 0.25) * eff.coilPitch;
            fitsBoard = fitsBoard && (reqFrac <= available + 1e-9);
        elseif cfg.boardLayerCount == 6 && cfg.coilLayerCount == 6
            reqFrac = cfg.traceWidth + (t + 0.50) * eff.coilPitch;
            fitsBoard = fitsBoard && (reqFrac <= available + 1e-9);
        end
        fprintf(fid, '%d,%.6f,%d\n', t, req, fitsBoard);
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
fprintf(fid, 'PASS minTerminalToConnectionTraceMm: %.6f\n', ...
    v.minTerminalToConnectionTraceMm);
fprintf(fid, 'PASS actualBridgeWidthMm: %.6f\n', v.actualBridgeWidthMm);
fprintf(fid, 'PASS uniqueSeriesNetwork: %d\n', v.uniqueSeriesNetwork);
fprintf(fid, 'PASS maxSeriesContinuityErrorMm: %.9f\n', v.maxSeriesContinuityErrorMm);
fprintf(fid, 'PASS maxConnectionTurnDeg: %.6f\n', v.maxConnectionTurnDeg);
fprintf(fid, 'PASS minOuterViaContactSweepDeg: %.6f\n', v.minOuterViaContactSweepDeg);
fprintf(fid, 'PASS maxOuterViaContactSweepDeg: %.6f\n', v.maxOuterViaContactSweepDeg);
fprintf(fid, 'PASS viaOverlapFree: %d\n', v.viaOverlapFree);
fprintf(fid, 'PASS windingSuperpositionConsistent: %d\n', v.windingSuperpositionConsistent);
fprintf(fid, 'PASS minSignedCirculationDeg: %.6f\n', v.minSignedCirculationDeg);
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
fprintf(fid7, 'copperThickness: %.6f mm (1/3 oz nominal profile)\n', cfg.copperThickness);
fprintf(fid7, 'manufacturingProfile: %s\n', result.manufacturing.profile);
fprintf(fid7, 'manufacturingTier: %s\n', result.manufacturing.tier);
fprintf(fid7, 'qualificationStatus: %s\n', result.manufacturing.qualificationStatus);
fprintf(fid7, 'fpcStackup: %s\n', result.manufacturing.stackup.name);
fprintf(fid7, 'finishedBoardThickness: %.6f mm nominal\n', ...
    result.manufacturing.stackup.nominalFinishedThicknessMm);
fprintf(fid7, 'surfaceFinish: %s\n', result.manufacturing.stackup.surfaceFinish);
fprintf(fid7, 'coverlay: %s, PI12.5um + adhesive15um = %.6f mm per side\n', ...
    result.manufacturing.stackup.coverlayColor, result.manufacturing.stackup.coverlayThicknessMm);
fprintf(fid7, 'copperType: %s\n', result.manufacturing.stackup.copperType);
fprintf(fid7, 'coordinates: +X right, +Y up; SVG display only flips Y\n');
fprintf(fid7, ['mountingSlot: three-arc ear cutouts at 0/90/180/270 deg; inner arc is the main ' ...
    'body circle (r=%.6f mm), middle arc bulges %.6f mm (basis: main body circle apex) at ' ...
    'chord span %.6f mm, outer ear edge is the middle arc offset outward by %.6f mm\n'], ...
    result.layoutRegions.mountingSlotInnerArcRadius, cfg.mountingSlotRise, ...
    cfg.mountingSlotSpan, cfg.mountingSlotEdgeClearance);
fprintf(fid7, 'independentElectrodes: two top-layer pads at %.6f deg; no generated routing\n', ...
    cfg.electrodeAngleDeg);
fprintf(fid7, 'Physical DXF is a CAM reference and does not replace Gerber.\n');
fprintf(fid7, 'NOT_GENERATED: coverlay geometry, stiffener geometry, Gerber, panelization\n');
if strcmp(result.manufacturing.qualificationStatus, 'UNVERIFIED_LAYER_COUNT')
    fprintf(fid7, 'COMSOL: 09_comsol_stackup.csv contains unverified six-layer thickness inputs; Z coordinates are NaN until the fab stackup is confirmed.\n');
else
    fprintf(fid7, 'COMSOL: use 09_comsol_stackup.csv for the nominal layer Z coordinates; verify against the fab stackup.\n');
end
fprintf(fid7, 'COMSOL simulation DXFs: *_copper_solid_L*.dxf keeps only the closed main coil; *_copper_solid_with_terminals_L*.dxf merges each active layer''s spiral with that layer''s terminal lead into one closed ring and writes no pad disk.\n');
fprintf(fid7, 'COMSOL simulation DXFs never contain vias, drills, via annuli, or inter-layer transitions; map them with reports/11_comsol_terminal_geometry.csv.\n');
fprintf(fid7, 'File manifest 08_file_manifest.csv excludes itself.\n');
clear c7;
writeComsolStackupReport(fullfile(reportsDir, '09_comsol_stackup.csv'), result.manufacturing.stackup);
writeComsolTerminalGeometryReport(fullfile(reportsDir, '11_comsol_terminal_geometry.csv'), cfg, result);
end

function writeComsolStackupReport(filename, stack)
% 输出顶层到末层的 COMSOL 建模参考坐标，Z=0 位于计算层压厚度中心。
fid = openOutputFile(filename);
c = onCleanup(@() fclose(fid));
fprintf(fid, 'order,layerName,role,thicknessMm,zTopMm,zBottomMm,zCenterMm,material\n');
for k = 1:numel(stack.layers)
    layer = stack.layers(k);
    fprintf(fid, '%d,%s,%s,%.6f,%.6f,%.6f,%.6f,%s\n', ...
        layer.order, layer.name, layer.role, layer.thicknessMm, layer.zTopMm, ...
        layer.zBottomMm, layer.zCenterMm, layer.material);
end
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
elseif ~isempty(regexp(rel, '^dxf/L\d+/\d+_copper_solid_L\d+\.dxf$', 'once'))
    role = 'copper_solid';
elseif ~isempty(regexp(rel, '^dxf/L\d+/\d+_copper_solid_with_terminals_L\d+\.dxf$', 'once'))
    role = 'copper_solid_with_terminals';
elseif ~isempty(regexp(rel, '^preview/(zh|en)/(JLC|COMSOL)/', 'once'))
    role = 'preview_annotated';
elseif ~isempty(regexp(rel, '^preview/(JLC/(1_path_only|2_trace_only|3_trace_pad_via)|COMSOL)/', 'once'))
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

function writeStatus(cfg, formalPath, filename)
fid = fopen(filename, 'w');
fprintf(fid, 'SUCCESS\n');
fprintf(fid, 'designName: %s\n', cfg.designName);
fprintf(fid, 'outputPath: %s\n', formalPath);
fprintf(fid, 'generatedBy: Circular_FPC_Coil\n');
fclose(fid);
end

function removeStagingFolder(folder)
if isfolder(folder)
    rmdir(folder, 's');
end
end

function verifyWrittenOutputs(cfg, result, tempDir)
% 读回校验：确保写出的 DXF/SVG/CSV/TXT 可解析、内容符合契约
% （DXF 单位 mm、9 个闭合多段线、SVG 可被 xmlread 解析、CSV 列名正确等）。
boardFile = fullfile(tempDir, 'dxf', '00_board_outline.dxf');
txt = fileread(boardFile);
if ~checkInsUnitsMm(txt)
    error('CircularFPC:ExportReadbackFailed', 'Board DXF $INSUNITS is not 4.');
end
if countClosedLwpolylines(txt) ~= numel(result.boardLoops)
    error('CircularFPC:ExportReadbackFailed', ...
        'Board DXF must contain exactly %d closed LWPOLYLINE entities.', numel(result.boardLoops));
end
[~, boardWidths, boardPolyCount] = readDxfEntities(txt);
if boardPolyCount ~= numel(result.boardLoops) || numel(boardWidths) ~= numel(result.boardLoops) || ...
        any(abs(boardWidths - cfg.boardOutlineLineWidth) > 1e-9)
    error('CircularFPC:ExportReadbackFailed', ...
        'Board DXF outline width must be %.6f mm on all board loops.', cfg.boardOutlineLineWidth);
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
        electrodeC = pc(strcmp({pc.layer}, 'ELECTRODE_L1'));
        if ~isempty(result.electrodePads) && ~contains(physTxt, 'ELECTRODE_L1')
            error('CircularFPC:ExportReadbackFailed', ...
                'Physical L1 DXF must declare ELECTRODE_L1 layer.');
        end
        if numel(electrodeC) ~= numel(result.electrodePads) || ...
                (~isempty(electrodeC) && any(abs(sort([electrodeC.r]) - ...
                sort([result.electrodePads.diameter] / 2)) > 1e-9))
            error('CircularFPC:ExportReadbackFailed', ...
                'Physical L1 independent electrode pad mismatch: %s', physFile);
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
    electrodeCount = (li == 1) * numel(result.electrodePads);
    if numel(pc) ~= (li == 1) * 2 + numel(viaIds) + electrodeCount
        error('CircularFPC:ExportReadbackFailed', 'Physical circle count mismatch: %s', physFile);
    end
    solidFile = fullfile(layerDir, sprintf('%02d_copper_solid_L%d.dxf', li, li));
    if ~isfile(solidFile)
        error('CircularFPC:ExportReadbackFailed', 'Missing COMSOL solid copper DXF: %s', solidFile);
    end
    solidTxt = fileread(solidFile);
    checkDxfBase(solidTxt, solidFile);
    if ~contains(solidTxt, sprintf('COPPER_SOLID_L%d', li))
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL solid DXF must declare COPPER_SOLID_L%d.', li);
    end
    [solidCircles, solidWidths, solidPolyCount] = readDxfEntities(solidTxt);
    if ~isempty(solidCircles) || ~isempty(solidWidths) || ...
            countClosedLwpolylines(solidTxt) ~= solidPolyCount
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL solid DXF must contain only closed widthless LWPOLYLINE rings: %s', solidFile);
    end
    hasMainCoil = ~isempty(result.layerPaths(li).coilXY);
    if hasMainCoil && solidPolyCount ~= 1
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL solid DXF must contain exactly one main-coil ring: %s', solidFile);
    elseif ~hasMainCoil && solidPolyCount ~= 0
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL solid DXF must be empty for an inactive layer: %s', solidFile);
    end
    solidVertices = readDxfPolylineVertices(solidTxt);
    if hasMainCoil && (size(solidVertices, 1) < 2 || ...
            norm(solidVertices(1, :) - solidVertices(end, :)) > 1e-9)
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL solid DXF must explicitly repeat the first vertex to close the final short cap: %s', solidFile);
    elseif ~hasMainCoil && ~isempty(solidVertices)
        error('CircularFPC:ExportReadbackFailed', ...
            'Inactive COMSOL solid DXF must not contain vertices: %s', solidFile);
    end
    verifyTerminalSolidDxf(cfg, result, layerDir, li);
end

if cfg.enablePreview
    [jlcDirs, ~, jlcAttrs] = jlcPreviewKinds();
    for ki = 1:numel(jlcDirs)
        for f = {fullfile(tempDir, 'preview', 'JLC', jlcDirs{ki}, '01_overview.svg'), ...
                fullfile(tempDir, 'preview', 'JLC', jlcDirs{ki}, '02_connection_zone.svg')}
            if ~isfile(f{1})
                error('CircularFPC:ExportReadbackFailed', 'Missing SVG: %s', f{1});
            end
            svgTxt = fileread(f{1});
            if ~contains(svgTxt, sprintf('data-preview-kind="%s"', jlcAttrs{ki}))
                error('CircularFPC:ExportReadbackFailed', ...
                    'JLC preview kind metadata mismatch: %s', f{1});
            end
            xmlread(f{1});
        end
    end
    comsolFull = fullfile(tempDir, 'preview', 'COMSOL', '1_coil_only', '01_overview.svg');
    if ~isfile(comsolFull)
        error('CircularFPC:ExportReadbackFailed', 'Missing SVG: %s', comsolFull);
    end
    xmlread(comsolFull);
    for li = 1:cfg.boardLayerCount
        if li == 1
            role = 'top';
        elseif li == cfg.boardLayerCount
            role = 'bottom';
        else
            role = sprintf('inner%d', li - 1);
        end
        for ki = 1:numel(jlcDirs)
            f = fullfile(tempDir, 'preview', 'JLC', jlcDirs{ki}, ...
                sprintf('1%d_layer_L%d_%s.svg', li, li, role));
            if ~isfile(f)
                error('CircularFPC:ExportReadbackFailed', 'Missing SVG: %s', f);
            end
            svgTxt = fileread(f);
            if ~contains(svgTxt, sprintf('data-preview-kind="%s"', jlcAttrs{ki}))
                error('CircularFPC:ExportReadbackFailed', ...
                    'JLC preview kind metadata mismatch: %s', f);
            end
            xmlread(f);
        end
        comsolFile = fullfile(tempDir, 'preview', 'COMSOL', '1_coil_only', ...
            sprintf('1%d_layer_L%d_%s.svg', li, li, role));
        if ~isfile(comsolFile)
            error('CircularFPC:ExportReadbackFailed', 'Missing COMSOL DXF preview: %s', comsolFile);
        end
        comsolTxt = fileread(comsolFile);
        if ~contains(comsolTxt, 'data-preview-kind="comsol-dxf"') || ...
                ~contains(comsolTxt, sprintf('data-dxf-layer="L%d"', li))
            error('CircularFPC:ExportReadbackFailed', ...
                'COMSOL DXF preview metadata mismatch: %s', comsolFile);
        end
        xmlread(comsolFile);
    end
    comsolFullTxt = fileread(comsolFull);
    for li = result.activeCoilLayers
        if ~contains(comsolFullTxt, sprintf('data-dxf-layer="L%d"', li))
            error('CircularFPC:ExportReadbackFailed', ...
                'COMSOL full preview missing active layer L%d.', li);
        end
    end
    comsolTermFull = fullfile(tempDir, 'preview', 'COMSOL', '2_coil_with_lead', ...
        '01_overview.svg');
    if ~isfile(comsolTermFull)
        error('CircularFPC:ExportReadbackFailed', 'Missing SVG: %s', comsolTermFull);
    end
    comsolTermFullTxt = fileread(comsolTermFull);
    if ~contains(comsolTermFullTxt, 'data-preview-kind="comsol-dxf-with-terminals"')
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL terminal preview kind metadata mismatch: %s', comsolTermFull);
    end
    if ~contains(comsolTermFullTxt, 'data-copper-kind="coil_with_lead"') || ...
            contains(comsolTermFullTxt, 'data-copper-kind="pad"')
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL coil-with-lead preview must draw merged rings and no pads: %s', comsolTermFull);
    end
    xmlread(comsolTermFull);
    for li = 1:cfg.boardLayerCount
        if li == 1
            role = 'top';
        elseif li == cfg.boardLayerCount
            role = 'bottom';
        else
            role = sprintf('inner%d', li - 1);
        end
        comsolTermFile = fullfile(tempDir, 'preview', 'COMSOL', '2_coil_with_lead', ...
            sprintf('1%d_layer_L%d_%s.svg', li, li, role));
        if ~isfile(comsolTermFile)
            error('CircularFPC:ExportReadbackFailed', ...
                'Missing COMSOL terminal preview: %s', comsolTermFile);
        end
        comsolTermTxt = fileread(comsolTermFile);
        if ~contains(comsolTermTxt, 'data-preview-kind="comsol-dxf-with-terminals"') || ...
                ~contains(comsolTermTxt, sprintf('data-dxf-layer="L%d"', li))
            error('CircularFPC:ExportReadbackFailed', ...
                'COMSOL terminal preview metadata mismatch: %s', comsolTermFile);
        end
        % 每个活动层恰好一条合并后的闭合轮廓；非活动层没有铜体。焊盘在本变体里
        % 不再导出，出现 pad 图元反而是错误。
        expectedBodies = double(~isempty(result.layerPaths(li).coilXY));
        if numel(regexp(comsolTermTxt, 'data-copper-kind="coil_with_lead"', 'match')) ~= expectedBodies
            error('CircularFPC:ExportReadbackFailed', ...
                'COMSOL coil-with-lead preview must draw exactly one merged ring on L%d: %s', ...
                li, comsolTermFile);
        end
        if contains(comsolTermTxt, 'data-copper-kind="pad"')
            error('CircularFPC:ExportReadbackFailed', ...
                'COMSOL coil-with-lead preview must not draw pads on L%d: %s', li, comsolTermFile);
        end
        % An inactive layer legitimately has no copper body, so the preview
        % cites its DXF file only when the variant actually emits geometry.
        if ~isempty(result.layerPaths(li).coilXY) && ...
                ~contains(comsolTermTxt, sprintf('data-dxf-file="dxf/L%d/%02d_copper_solid_with_terminals_L%d.dxf"', li, li, li))
            error('CircularFPC:ExportReadbackFailed', ...
                'COMSOL terminal preview must cite its DXF file on L%d.', li);
        end
        xmlread(comsolTermFile);
    end
    % 附加预览集：base/zh/en 三组必须齐全，文字不得越界或重叠，且 base 组必须与
    % 上面校验过的 JLC/、COMSOL/ 预览逐字节一致。排版失败会阻止原子发布。
    CircularFpc.Export.Annotated_Previews('audit', fullfile(tempDir, 'preview'), cfg);
end
for f = {'01_pad_via_coordinates.csv', '02_layer_map.csv', '10_electrode_pad_coordinates.csv'}
    p = fullfile(tempDir, 'reports', f{1});
    t = readtable(p);
    if height(t) < 1
        error('CircularFPC:ExportReadbackFailed', 'Unreadable report: %s', p);
    end
end
electrodeReport = readtable(fullfile(tempDir, 'reports', '10_electrode_pad_coordinates.csv'));
expectedElectrodeColumns = {'name', 'xMm', 'yMm', 'diameterMm', 'layer', ...
    'role', 'placementRegion', 'bridgeAngleDeg'};
if ~isequal(electrodeReport.Properties.VariableNames, expectedElectrodeColumns) || ...
        height(electrodeReport) ~= numel(result.electrodePads)
    error('CircularFPC:ExportReadbackFailed', 'Independent electrode report mismatch.');
end
for k = 1:numel(result.electrodePads)
    p = result.electrodePads(k);
    row = electrodeReport(strcmp(electrodeReport.name, p.name), :);
    if height(row) ~= 1 || abs(row.xMm - p.xy(1)) > 1e-6 || ...
            abs(row.yMm - p.xy(2)) > 1e-6 || abs(row.diameterMm - p.diameter) > 1e-6 || ...
            row.layer ~= p.layer || ~strcmp(char(row.role), p.role) || ...
            ~strcmp(char(row.placementRegion), p.placementRegion) || ...
            abs(row.bridgeAngleDeg - p.bridgeAngleDeg) > 1e-6
        error('CircularFPC:ExportReadbackFailed', ...
            'Independent electrode report row mismatch for %s.', p.name);
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
csvStackup = fullfile(tempDir, 'reports', '09_comsol_stackup.csv');
if ~isfile(csvStackup)
    error('CircularFPC:ExportReadbackFailed', 'Missing COMSOL stackup report: %s', csvStackup);
end
t9 = readtable(csvStackup);
expCols9 = {'order', 'layerName', 'role', 'thicknessMm', 'zTopMm', 'zBottomMm', 'zCenterMm', 'material'};
if ~isequal(t9.Properties.VariableNames, expCols9)
    error('CircularFPC:ExportReadbackFailed', '09 COMSOL stackup columns mismatch.');
end
stackLayers = result.manufacturing.stackup.layers;
if height(t9) ~= numel(stackLayers)
    error('CircularFPC:ExportReadbackFailed', '09 COMSOL stackup row count mismatch.');
end
for k = 1:numel(stackLayers)
    layer = stackLayers(k);
    if t9.order(k) ~= layer.order || ~strcmp(char(t9.layerName(k)), layer.name) || ...
            ~strcmp(char(t9.role(k)), layer.role) || abs(t9.thicknessMm(k) - layer.thicknessMm) > 1e-9 || ...
            abs(t9.zTopMm(k) - layer.zTopMm) > 1e-9 || abs(t9.zBottomMm(k) - layer.zBottomMm) > 1e-9 || ...
            abs(t9.zCenterMm(k) - layer.zCenterMm) > 1e-9 || ~strcmp(char(t9.material(k)), layer.material)
        error('CircularFPC:ExportReadbackFailed', '09 COMSOL stackup row %d mismatch.', k);
    end
end
verifyComsolTerminalGeometryReport(cfg, result, tempDir);
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
roles8 = {'board_outline', 'drill_map', 'copper_centerline', 'copper_physical', 'copper_solid', ...
    'copper_solid_with_terminals', 'preview', 'preview_annotated', ...
    'report', 'generation_status'};
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
statusText = fileread(fullfile(tempDir, 'generation_status.txt'));
expectedOutputPath = fullfile(cfg.outputRoot, cfg.designName);
if isempty(statusText)
    error('CircularFPC:ExportReadbackFailed', 'Empty generation status.');
end
if ~contains(statusText, sprintf('outputPath: %s', expectedOutputPath))
    error('CircularFPC:ExportReadbackFailed', ...
        'Generation status outputPath does not match the formal directory.');
end
end

function verifyTerminalSolidDxf(cfg, result, layerDir, li)
% Readback for dxf/Ln/NN_copper_solid_with_terminals_Ln.dxf: exactly one closed
% body per active coil layer, being that layer's spiral merged with its terminal
% copper; every body repeats its first vertex; the body must be strictly larger
% than the plain copper_solid ring, otherwise the merge did not happen; no
% CIRCLE on any layer (pads are not exported), no VIA/DRILL marker, no via
% annulus layer, no group-43 width anywhere.
solidFile = fullfile(layerDir, sprintf('%02d_copper_solid_with_terminals_L%d.dxf', li, li));
if ~isfile(solidFile)
    error('CircularFPC:ExportReadbackFailed', 'Missing COMSOL terminal copper DXF: %s', solidFile);
end
txt = fileread(solidFile);
checkDxfBase(txt, solidFile);
verifyDxfEntityLayersDeclared(txt, solidFile);
if ~contains(txt, sprintf('COPPER_SOLID_TERMINALS_L%d', li))
    error('CircularFPC:ExportReadbackFailed', ...
        'COMSOL terminal DXF must declare COPPER_SOLID_TERMINALS_L%d: %s', li, solidFile);
end

if countClosedLwpolylines(txt) ~= numel(readDxfLwpolylines(txt))
    error('CircularFPC:ExportReadbackFailed', ...
        'COMSOL terminal DXF must contain only closed LWPOLYLINE bodies: %s', solidFile);
end
entities = comsolTerminalEntities(cfg, result, li);
polys = readDxfLwpolylines(txt);
[dc, w43, nPoly] = readDxfEntities(txt);
expectedPolys = numel(entities);
if nPoly ~= expectedPolys || numel(polys) ~= expectedPolys
    error('CircularFPC:ExportReadbackFailed', ...
        'COMSOL terminal DXF body count mismatch (expected %d closed rings): %s', ...
        expectedPolys, solidFile);
end
if ~isempty(w43) || any([polys.hasWidth])
    error('CircularFPC:ExportReadbackFailed', ...
        'COMSOL terminal DXF must not contain LWPOLYLINE group 43: %s', solidFile);
end
if ~isempty(dc)
    error('CircularFPC:ExportReadbackFailed', ...
        'COMSOL terminal DXF must not contain circles (pads are not exported): %s', ...
        solidFile);
end
for k = 1:numel(polys)
    if ~polys(k).closed
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL terminal DXF body %d must set the closed flag: %s', k, solidFile);
    end
    if size(polys(k).xy, 1) < 4
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL terminal DXF body %d is degenerate: %s', k, solidFile);
    end
    if norm(polys(k).xy(1, :) - polys(k).xy(end, :)) > 1e-9
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL terminal DXF body %d must explicitly repeat its first vertex: %s', k, solidFile);
    end
    if polygonArea(polys(k).xy) <= 0
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL terminal DXF body %d must enclose a positive area: %s', k, solidFile);
    end
end
% Every emitted body must be exactly the canonical merged copper ring. The
% variant carries conductor only, so the empty-circle check above already
% covers pads on every layer.
for k = 1:numel(polys)
    e = entities(k);
    if size(polys(k).xy, 1) ~= size(e.ring, 1) || ...
            max(abs(polys(k).xy - e.ring), [], 'all') > 1e-5
        error('CircularFPC:ExportReadbackFailed', ...
            'COMSOL terminal DXF body %d (%s) does not match the canonical copper ring: %s', ...
            k, e.name, solidFile);
    end
end
% The merged body must be strictly larger than the plain copper_solid ring it
% grew out of: equal area would mean the terminal copper never got merged, and
% carrying that copper is the whole point of this variant.
if ~isempty(result.layerPaths(li).coilXY)
    solidTxt = fileread(fullfile(layerDir, sprintf('%02d_copper_solid_L%d.dxf', li, li)));
    solidPolys = readDxfLwpolylines(solidTxt);
    if numel(solidPolys) ~= 1
        error('CircularFPC:ExportReadbackFailed', ...
            'copper_solid_L%d must contain exactly one ring: %s', li, solidFile);
    end
    mergedArea = polygonArea(polys(1).xy);
    plainArea = polygonArea(solidPolys(1).xy);
    absorbed = entities(1).leads;
    if mergedArea < plainArea - 1e-6
        error('CircularFPC:ExportReadbackFailed', ...
            ['COMSOL terminal DXF %.6f mm^2 is smaller than the plain ' ...
             'copper_solid ring %.6f mm^2, so the merge lost copper: %s'], ...
            mergedArea, plainArea, solidFile);
    end
    % 只有真的并入了引线的层才必须变大；没有端子铜的层（例如 4/4 的 L2/L3）
    % 合并环就等于原螺旋，面积理应相同。
    if ~isempty(absorbed) && mergedArea <= plainArea + 1e-9
        error('CircularFPC:ExportReadbackFailed', ...
            ['COMSOL terminal DXF %.6f mm^2 does not exceed the plain ' ...
             'copper_solid ring %.6f mm^2 although it absorbed %s: %s'], ...
            mergedArea, plainArea, absorbed, solidFile);
    end
end
if ~isempty(dc)
    error('CircularFPC:ExportReadbackFailed', ...
        'COMSOL terminal DXF must not contain circles on any layer: %s', solidFile);
end
if contains(txt, 'VIA') || contains(txt, 'DRILL')
    error('CircularFPC:ExportReadbackFailed', ...
        'COMSOL terminal DXF must not contain VIA/DRILL geometry: %s', solidFile);
end
end

function verifyDxfEntityLayersDeclared(txt, label)
% Every entity layer must be present in the DXF TABLES/LAYER table. This is
% especially important for the L1 COMSOL terminal variant, which uses the
% separate PAD_A/PAD_B circle layers in addition to the copper body layer.
lines = strtrim(strsplit(txt, newline));
declared = {};
used = {};
inTables = false;
inLayerTable = false;
captureLayerName = false;
inEntities = false;
k = 1;
while k + 1 <= numel(lines)
    code = lines{k};
    value = lines{k + 1};
    if strcmp(code, '2') && strcmp(value, 'TABLES')
        inTables = true;
    elseif inTables && strcmp(code, '0') && strcmp(value, 'ENDSEC')
        inTables = false;
        inLayerTable = false;
        captureLayerName = false;
    elseif inTables && strcmp(code, '2') && strcmp(value, 'LAYER')
        inLayerTable = true;
    elseif inTables && inLayerTable && strcmp(code, '0') && strcmp(value, 'LAYER')
        captureLayerName = true;
    elseif inTables && inLayerTable && strcmp(code, '0') && strcmp(value, 'ENDTAB')
        inLayerTable = false;
        captureLayerName = false;
    elseif inTables && captureLayerName && strcmp(code, '2')
        declared{end + 1} = value; %#ok<AGROW>
        captureLayerName = false;
    elseif strcmp(code, '2') && strcmp(value, 'ENTITIES')
        inEntities = true;
    elseif inEntities && strcmp(code, '0') && strcmp(value, 'ENDSEC')
        inEntities = false;
    elseif inEntities && strcmp(code, '8')
        used{end + 1} = value; %#ok<AGROW>
    end
    k = k + 2;
end
missing = setdiff(unique(used), unique(declared));
if ~isempty(missing)
    error('CircularFPC:ExportReadbackFailed', ...
        '%s references undeclared DXF layer(s): %s.', label, strjoin(missing, ', '));
end
end

function verifyComsolTerminalGeometryReport(cfg, result, tempDir)
% Readback for reports/11_comsol_terminal_geometry.csv: the mapping report must
% describe every emitted body of every with-terminals DXF, keep both center
% leads on L1, and agree with the canonical entity list on closure and area.
csvPath = fullfile(tempDir, 'reports', '11_comsol_terminal_geometry.csv');
if ~isfile(csvPath)
    error('CircularFPC:ExportReadbackFailed', 'Missing COMSOL terminal geometry report: %s', csvPath);
end
t = readtable(csvPath);
expCols = {'entity', 'kind', 'layer', 'routeNode', 'dxfFile', 'closed', ...
    'vertexCount', 'areaMm2', 'capMode', 'startXMm', 'startYMm', 'endXMm', ...
    'endYMm', 'firstXMm', 'firstYMm', 'lastXMm', 'lastYMm', 'firstLastMatch'};
if ~isequal(t.Properties.VariableNames, expCols)
    error('CircularFPC:ExportReadbackFailed', '11 COMSOL terminal geometry columns mismatch.');
end
expectedRows = 0;
for li = 1:numel(result.layerPaths)
    expectedRows = expectedRows + numel(comsolTerminalEntities(cfg, result, li));
end
if height(t) ~= expectedRows
    error('CircularFPC:ExportReadbackFailed', ...
        '11 COMSOL terminal geometry row count must match every emitted body.');
end
% 每个活动层一行合并轮廓；焊盘不再导出，出现 pad 行即为错误。
if sum(strcmp(t.kind, 'coil_with_lead')) ~= expectedRows || ...
        any(strcmp(t.kind, 'pad')) || any(strcmp(t.kind, 'terminal_lead'))
    error('CircularFPC:ExportReadbackFailed', ...
        '11 COMSOL terminal geometry must list one merged ring per active layer.');
end
for k = 1:height(t)
    if t.closed(k) ~= 1
        error('CircularFPC:ExportReadbackFailed', ...
            '11 COMSOL terminal geometry row %d must be a closed 2D body.', k);
    end
    if ~strcmp(char(t.capMode(k)), 'merged_closed_ring')
        error('CircularFPC:ExportReadbackFailed', ...
            '11 COMSOL terminal geometry capMode mismatch on row %d.', k);
    end
    if ~isfinite(t.areaMm2(k)) || t.areaMm2(k) <= 0
        error('CircularFPC:ExportReadbackFailed', ...
            '11 COMSOL terminal geometry must report a positive area on row %d.', k);
    end
    if t.firstLastMatch(k) ~= 1
        error('CircularFPC:ExportReadbackFailed', ...
            '11 COMSOL terminal geometry row %d must close on its first vertex.', k);
    end
    if t.vertexCount(k) < 4
        error('CircularFPC:ExportReadbackFailed', ...
            '11 COMSOL terminal geometry row %d copper ring is degenerate.', k);
    end
    absDxf = fullfile(tempDir, char(t.dxfFile(k)));
    if ~isfile(absDxf)
        error('CircularFPC:ExportReadbackFailed', ...
            '11 COMSOL terminal geometry cites a missing DXF on row %d.', k);
    end
end
% 每行必须落在对应层的合并轮廓上，实体名与层号一一对应，面积取自该轮廓。
for k = 1:height(t)
    li = t.layer(k);
    ents = comsolTerminalEntities(cfg, result, li);
    if numel(ents) ~= 1 || ~strcmp(t.entity(k), ents(1).name)
        error('CircularFPC:ExportReadbackFailed', ...
            '11 COMSOL terminal geometry row %d must name the layer merged ring.', k);
    end
    if abs(t.areaMm2(k) - polygonArea(ents(1).ring)) > 1e-6
        error('CircularFPC:ExportReadbackFailed', ...
            '11 COMSOL terminal geometry row %d area mismatch.', k);
    end
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

function xy = readDxfPolylineVertices(txt)
% Read every group-10/group-20 vertex from LWPOLYLINE entities.
lines = strtrim(strsplit(txt, newline));
xy = zeros(0, 2);
k = 1;
while k + 1 <= numel(lines)
    if strcmp(lines{k}, '0') && strcmp(lines{k + 1}, 'LWPOLYLINE')
        j = k + 2;
        x = NaN;
        y = NaN;
        while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
            code = str2double(lines{j});
            val = str2double(lines{j + 1});
            if code == 10
                if isfinite(x) && isfinite(y)
                    xy(end + 1, :) = [x, y]; %#ok<AGROW>
                end
                x = val;
                y = NaN;
            elseif code == 20
                y = val;
            end
            j = j + 2;
        end
        if isfinite(x) && isfinite(y)
            xy(end + 1, :) = [x, y]; %#ok<AGROW>
        end
        k = j;
    else
        k = k + 1;
    end
end
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

function polys = readDxfLwpolylines(txt)
% Per-entity LWPOLYLINE readback: layer, closed flag, group-43 width presence
% and the full vertex list. The with-terminals readback needs per-entity
% structure (not the flattened vertex stream) to prove each emitted copper
% body is separately closed and free of width metadata.
lines = strtrim(strsplit(txt, newline));
polys = struct('layer', {}, 'closed', {}, 'hasWidth', {}, 'xy', {});
k = 1;
while k + 1 <= numel(lines)
    if ~strcmp(lines{k}, '0') || ~strcmp(lines{k + 1}, 'LWPOLYLINE')
        k = k + 1;
        continue;
    end
    j = k + 2;
    layer = '';
    closed = false;
    hasWidth = false;
    xy = zeros(0, 2);
    x = NaN;
    y = NaN;
    while j + 1 <= numel(lines) && ~strcmp(lines{j}, '0')
        code = lines{j};
        val = lines{j + 1};
        switch code
            case '8'
                layer = val;
            case '43'
                hasWidth = true;
            case '70'
                closed = str2double(val) == 1;
            case '10'
                if isfinite(x) && isfinite(y)
                    xy(end + 1, :) = [x, y]; %#ok<AGROW>
                end
                x = str2double(val);
                y = NaN;
            case '20'
                y = str2double(val);
        end
        j = j + 2;
    end
    if isfinite(x) && isfinite(y)
        xy(end + 1, :) = [x, y];
    end
    polys(end + 1) = struct('layer', layer, 'closed', closed, ...
        'hasWidth', hasWidth, 'xy', xy); %#ok<AGROW>
    k = j;
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
    [jlcDirs, ~, jlcAttrs] = jlcPreviewKinds();
    for ki = 1:numel(jlcDirs)
        % 端子标注只由最高档（trace_pad_via）绘制；另两档按设计不画端子，
        % 因此只核对 kind 元数据，不去要求它们含有焊盘/过孔文字。
        for f = {fullfile(tempDir, 'preview', 'JLC', jlcDirs{ki}, '01_overview.svg'), ...
                fullfile(tempDir, 'preview', 'JLC', jlcDirs{ki}, '02_connection_zone.svg')}
        svgTxt = fileread(f{1});
        if ~contains(svgTxt, sprintf('data-preview-kind="%s"', jlcAttrs{ki}))
            error('CircularFPC:ExportReadbackFailed', ...
                'JLC preview kind metadata mismatch: %s', f{1});
        end
        if ~strcmp(jlcAttrs{ki}, 'jlc-trace-pad-via')
            continue;
        end
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
end
