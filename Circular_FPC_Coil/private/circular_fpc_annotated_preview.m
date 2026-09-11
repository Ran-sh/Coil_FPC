function varargout = circular_fpc_annotated_preview(operation, varargin)
% CIRCULAR_FPC_ANNOTATED_PREVIEW 附加预览集：基础版 + 中英双语标注版。
%
%   'write'  在 <previewRoot> 下写出三组平行预览，每组含 JLC 与 COMSOL 子目录：
%              base/  基础预览（与 JLC/、COMSOL/ 同源，逐字节副本，便于对照）
%              zh/    中文标注版（标题带 + 图例 + 说明）
%              en/    英文标注版（同上）
%
%   'audit'  回读全部附加预览并检查：XML 可解析、语言元数据正确、每段文字都不
%            越出帧宽、正文互不重叠、base 与既有预览逐字节一致。
%
% 设计要点：标注图**不重新绘制几何**，而是读回已经写出的基础预览再封装，因此
% 标注图与其说明对象使用同一批图元，不存在第二套绘图代码；JLC/ 与 COMSOL/ 下
% 既有文件保持原字节契约。本函数在写 manifest 之前被调用，所以每个附加文件都
% 属于原子发布并登记自己的 role。任何排版失败都会报错，发布不会带着溢出的文字
% 落到正式产物里。
if nargin < 1
    error('CircularFPC:InvalidOperation', 'Annotated preview requires an operation.');
end
switch operation
    case 'write'
        writeAll(varargin{1}, varargin{2}, varargin{3}, varargin{4}, varargin{5});
    case 'audit'
        auditAll(varargin{1});
    otherwise
        error('CircularFPC:InvalidOperation', ...
            'Unknown annotated-preview operation: %s', operation);
end
end

function writeAll(cfg, result, previewRoot, firstRole, lastRole)
langs = {'base', 'zh', 'en'};
for k = 1:numel(langs)
    figures = figurePlan(cfg, result, langs{k}, firstRole, lastRole);
    for q = 1:numel(figures)
        f = figures(q);
        srcPath = fullfile(previewRoot, f.src);
        if ~isfile(srcPath)
            error('CircularFPC:ExportWriteFailed', ...
                'Annotated preview source is missing: %s', srcPath);
        end
        outPath = fullfile(previewRoot, langs{k}, f.out);
        outDir = fileparts(outPath);
        if ~isfolder(outDir)
            mkdir(outDir);
        end
        if f.isCopy
            copyfile(srcPath, outPath);
            continue;
        end
        svg = renderAnnotated(srcPath, langs{k}, f, ...
            sprintf('clip%s%02d', langs{k}, q));
        fid = fopen(outPath, 'w');
        if fid < 0
            error('CircularFPC:ExportWriteFailed', ...
                'Cannot open annotated preview for writing: %s', outPath);
        end
        fprintf(fid, '%s', svg);
        fclose(fid);
    end
end
end

function figures = figurePlan(cfg, result, lang, firstRole, lastRole)
% base 组是逐字节副本；zh/en 组是标注版。两组文件同名，便于并排对照。
isCopy = strcmp(lang, 'base');
t = annotationText(lang, cfg, result);
active = result.activeCoilLayers;
firstLi = active(1);
lastLi = active(end);

figures = struct('src', {}, 'out', {}, 'title', {}, 'subtitle', {}, ...
    'legendColor', {}, 'legendLabel', {}, 'notes', {}, ...
    'hasTerminalLabels', {}, 'isCopy', {});

figures(end + 1) = mk(fullfile('JLC', 'centerline', '01_preview_full.svg'), ...
    fullfile('JLC', '01_centerline_overview.svg'), t.ovTitle, t.ovSub, ...
    jlcLegend(t, result), t.ovNotes, true, isCopy);

figures(end + 1) = mk( ...
    fullfile('JLC', 'centerline', sprintf('%02d_preview_layer_L%d_%s.svg', ...
        2 + firstLi, firstLi, firstRole)), ...
    fullfile('JLC', sprintf('02_centerline_layer_L%d_%s.svg', firstLi, firstRole)), ...
    t.firstTitle, t.firstSub, layerLegend(t, result, firstLi), t.layerNotes, ...
    false, isCopy);

if numel(active) > 1
    figures(end + 1) = mk( ...
        fullfile('JLC', 'centerline', sprintf('%02d_preview_layer_L%d_%s.svg', ...
            2 + lastLi, lastLi, lastRole)), ...
        fullfile('JLC', sprintf('03_centerline_layer_L%d_%s.svg', lastLi, lastRole)), ...
        t.lastTitle, t.lastSub, layerLegend(t, result, lastLi), t.layerNotes, ...
        false, isCopy);
end

physIdx = 4 - double(numel(active) == 1);
figures(end + 1) = mk(fullfile('JLC', 'physical', '01_preview_full.svg'), ...
    fullfile('JLC', sprintf('%02d_physical_overview.svg', physIdx)), ...
    t.physTitle, t.physSub, jlcLegend(t, result), t.physNotes, true, isCopy);

figures(end + 1) = mk(fullfile('COMSOL', '01_comsol_dxf_full.svg'), ...
    fullfile('COMSOL', '01_main_overview.svg'), t.cmTitle, t.cmSub, ...
    comsolLegend(t, result, false), t.comsolNotes, false, isCopy);

figures(end + 1) = mk( ...
    fullfile('COMSOL', 'with_terminals', '01_comsol_with_terminals_full.svg'), ...
    fullfile('COMSOL', '02_with_terminals_overview.svg'), t.ctTitle, t.ctSub, ...
    comsolLegend(t, result, true), t.comsolNotes, false, isCopy);
end

function f = mk(src, out, title, subtitle, legend, notes, hasTerms, isCopy)
% legend 是 1xN 结构体数组，legend.color / legend.label 是多元素逗号分隔列表；
% 直接赋值只会取到第一个元素（且类型会退化成 char）。必须用 {} 收成 cell，
% 才能在字段里完整保留整份图例。
f = struct();
f.src = src;
f.out = out;
f.title = title;
f.subtitle = subtitle;
f.legendColor = {legend.color};
f.legendLabel = {legend.label};
f.notes = notes;
f.hasTerminalLabels = hasTerms;
f.isCopy = isCopy;
end

function leg = jlcLegend(t, result)
leg = emptyLegend();
leg(end + 1) = item('#ffcc1a', t.lgBoard);
leg(end + 1) = item('#8c1aa6', t.lgEdge);
leg(end + 1) = item('#8fcfdc', t.lgSlot);
for k = 1:numel(result.activeCoilLayers)
    li = result.activeCoilLayers(k);
    leg(end + 1) = item(layerColor(li), sprintf(t.lgLayer, li));
end
if ~isempty(result.electrodePads)
    leg(end + 1) = item('#ff7f0e', t.lgElec);
end
if ~isempty(result.vias)
    leg(end + 1) = item('#474747', t.lgVia);
end
leg(end + 1) = item('#666666', t.lgSilk);
end

function leg = layerLegend(t, result, li)
% 分层预览只有 L1 画焊盘与独立电极（见圆形导出器的 writeSvgLayer），其余层
% 不画；图例必须跟着实际图元走，否则会出现"图例有、画面无"的假说明。
leg = emptyLegend();
leg(end + 1) = item('#ffcc1a', t.lgBoard);
leg(end + 1) = item('#8c1aa6', t.lgEdge);
leg(end + 1) = item(layerColor(li), sprintf(t.lgLayer, li));
if li == 1
    if ~isempty(result.pads)
        leg(end + 1) = item('#e61919', t.lgPad);
    end
    if ~isempty(result.electrodePads)
        leg(end + 1) = item('#ff7f0e', t.lgElec);
    end
end
if ~isempty(result.vias)
    leg(end + 1) = item('#474747', t.lgVia);
end
end

function leg = comsolLegend(t, result, withTerminals)
leg = emptyLegend();
leg(end + 1) = item('#9aa5aa', t.lgReference);
for k = 1:numel(result.activeCoilLayers)
    li = result.activeCoilLayers(k);
    if withTerminals && li == 1
        % 带端子变体里端子焊盘与 L1 铜轮廓同色（源 SVG 就是一个 #e61919），
        % 因此并进 L1 条目说明，避免图例出现两个一模一样的色块。
        leg(end + 1) = item(layerColor(li), sprintf('%s · %s', ...
            sprintf(t.lgLayer, li), t.lgTermPad));
    else
        leg(end + 1) = item(layerColor(li), sprintf(t.lgLayer, li));
    end
end
end

function leg = emptyLegend()
leg = struct('color', {}, 'label', {});
end

function it = item(color, label)
it = struct('color', color, 'label', label);
end

function c = layerColor(li)
% 与 circular_fpc_export 的铜层调色板一致；audit 会回读确认该颜色确实出现在
% 被标注的源 SVG 中，避免图例与画面不符。
palette = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
c = palette{mod(li - 1, 4) + 1};
end

function t = annotationText(lang, cfg, result)
boardD = result.effectiveDimensions.boardOuterDiameter;
innerD = result.effectiveDimensions.coilInnerDiameter;
pitch = result.effectiveDimensions.coilPitch;
active = result.activeCoilLayers;
layerList = strjoin(arrayfun(@(v) sprintf('L%d', v), active, 'UniformOutput', false), ', ');
seq = strjoin(result.seriesSequence, ' -> ');
viaNames = strjoin(sort({result.vias.name}), ' / ');
nWarn = sum(strcmp({result.manufacturing.checks.status}, 'WARN'));
nCheck = numel(result.manufacturing.checks);
[turns1, circ1] = measureLayer(result, active(1));
[turnsN, circN] = measureLayer(result, active(end));
multi = numel(active) > 1 && result.validation.windingSuperpositionConsistent;

if strcmp(lang, 'zh')
    t.lgBoard = '板料（基材）';
    t.lgEdge = '板框轮廓';
    t.lgSlot = '挖槽：安装耳与平台槽';
    t.lgLayer = 'L%d 铜箔';
    t.lgElec = '独立电极焊盘（仅 L1）';
    t.lgPad = '端子焊盘 PAD_A / PAD_B（仅 L1）';
    t.lgVia = sprintf('贯通过孔 %s', viaNames);
    t.lgSilk = '端子引线标注线';
    t.lgReference = '板框与挖槽轮廓（仿真参考）';
    t.lgTermPad = '含端子焊盘';
    t.ovTitle = sprintf('%d 层板 / %d 活动线圈层（%d/%d）— JLC 中心线总览', ...
        cfg.boardLayerCount, cfg.coilLayerCount, cfg.boardLayerCount, cfg.coilLayerCount);
    t.ovSub = sprintf(['板外径 %.3f mm · 线圈内径 %.3f mm · 节距 %.3f mm · ' ...
        '每层约 %d 匝 · 活动层 %s'], boardD, innerD, pitch, cfg.turnsPerCoilLayer, layerList);
    t.firstTitle = sprintf('L%d 铜箔（活动线圈层）', active(1));
    t.firstSub = sprintf('实测 %.4f 匝 · 有向环绕角 %+.1f°%s', turns1, circ1, ...
        senseZh(multi));
    t.lastTitle = sprintf('L%d 铜箔（活动线圈层）', active(end));
    t.lastSub = sprintf('实测 %.4f 匝 · 有向环绕角 %+.1f°%s', turnsN, circN, ...
        senseZh(multi));
    t.physTitle = sprintf('%d 层板 / %d 活动线圈层（%d/%d）— JLC 物理铜总览', ...
        cfg.boardLayerCount, cfg.coilLayerCount, cfg.boardLayerCount, cfg.coilLayerCount);
    t.physSub = '按实际线宽、焊盘与过孔尺寸绘制，供嘉立创与 CAM 参考（不是 Gerber）';
    t.cmTitle = 'COMSOL 仿真几何 — 闭合铜轮廓';
    t.cmSub = '仅主阿基米德螺旋的闭合轮廓；不含过孔、钻孔、焊盘、端子与层间转换';
    t.ctTitle = 'COMSOL 仿真几何 — 带端子变体';
    t.ctSub = '在主螺旋上追加 L1 的 PAD_A / PAD_B 圆盘与中心短边引线；仍不含过孔与钻孔';
    t.ovNotes = { sprintf('串联网络：%s', seq), ...
        sprintf('板层/活动层 %d/%d · 板厚 %.3f mm 标称 · 铜厚 %.3f mm · 工艺档案 %s', ...
            cfg.boardLayerCount, cfg.coilLayerCount, ...
            result.manufacturing.stackup.nominalFinishedThicknessMm, ...
            cfg.copperThickness, result.manufacturing.profile), ...
        sprintf('校验 passed=%d，制造检查 %d 项通过、其中 %d 项近限值警告（明细见 reports/）', ...
            result.validation.passed, nCheck, nWarn), ...
        'DXF 是工程几何，不是 Gerber；投产前请复核叠层、材料与电气参数。', ...
        '端子标注文字经放大与转写，几何与 DXF 同源，未改动任何图元。' };
    t.layerNotes = { sprintf('活动线圈层：%s', layerList), ...
        '有向环绕角由生成的线圈折线实测；各活动层同向即磁场叠加而非相消。' };
    t.physNotes = { sprintf('串联网络：%s', seq), ...
        '非活动层不含铜箔；物理铜 DXF 移除未连接层的非功能焊盘。', ...
        'DXF 是工程几何，不是 Gerber；投产前请复核叠层、材料与电气参数。' };
    t.comsolNotes = { '闭合主螺旋轮廓，可在 COMSOL 中选作域或边界线圈，厚度取 0.012 mm。', ...
        '本图仅说明导出的仿真几何，不代表已通过 COMSOL 实际导入或求解验证。' };
else
    t.lgBoard = 'Board substrate';
    t.lgEdge = 'Board outline';
    t.lgSlot = 'Cut-outs: mounting ears and platform slots';
    t.lgLayer = 'L%d copper';
    t.lgElec = 'Electrode pads (L1 only)';
    t.lgPad = 'Terminal pads PAD_A / PAD_B (L1 only)';
    t.lgVia = sprintf('Through-vias %s', viaNames);
    t.lgSilk = 'Terminal leader lines';
    t.lgReference = 'Board and cut-out outlines (simulation reference)';
    t.lgTermPad = 'includes terminal pads';
    t.ovTitle = sprintf('%d-layer board / %d active coil layers (%d/%d) - JLC centerline overview', ...
        cfg.boardLayerCount, cfg.coilLayerCount, cfg.boardLayerCount, cfg.coilLayerCount);
    t.ovSub = sprintf(['Board d %.3f mm - coil inner d %.3f mm - pitch %.3f mm - ' ...
        'about %d turns per layer - active %s'], ...
        boardD, innerD, pitch, cfg.turnsPerCoilLayer, layerList);
    t.firstTitle = sprintf('L%d copper (active coil layer)', active(1));
    t.firstSub = sprintf('Measured %.4f turns - signed circulation %+.1f deg%s', ...
        turns1, circ1, senseEn(multi));
    t.lastTitle = sprintf('L%d copper (active coil layer)', active(end));
    t.lastSub = sprintf('Measured %.4f turns - signed circulation %+.1f deg%s', ...
        turnsN, circN, senseEn(multi));
    t.physTitle = sprintf('%d-layer board / %d active coil layers (%d/%d) - JLC physical copper overview', ...
        cfg.boardLayerCount, cfg.coilLayerCount, cfg.boardLayerCount, cfg.coilLayerCount);
    t.physSub = 'Drawn at real trace, pad and via sizes as a CAM reference (not Gerber)';
    t.cmTitle = 'COMSOL simulation geometry - closed copper contours';
    t.cmSub = 'Closed Archimedean spiral outlines only; no vias, drills, pads, terminals or layer transitions';
    t.ctTitle = 'COMSOL simulation geometry - with-terminals variant';
    t.ctSub = ['Adds the L1 PAD_A / PAD_B disks and center short-edge leads to the ' ...
        'main spiral; still no vias or drills'];
    t.ovNotes = { sprintf('Series network: %s', seq), ...
        sprintf(['Board/active layers %d/%d - board %.3f mm nominal - copper %.3f mm ' ...
            '- profile %s'], cfg.boardLayerCount, cfg.coilLayerCount, ...
            result.manufacturing.stackup.nominalFinishedThicknessMm, ...
            cfg.copperThickness, result.manufacturing.profile), ...
        sprintf(['Validation passed=%d; %d manufacturing checks pass, %d of them ' ...
            'near-limit warnings (see reports/).'], ...
            result.validation.passed, nCheck, nWarn), ...
        'DXF is engineering geometry, not Gerber; review stackup, material and electrical data before fabrication.', ...
        'Terminal labels are enlarged and reworded for this render; geometry comes from the same source.' };
    t.layerNotes = { sprintf('Active coil layers: %s', layerList), ...
        ['The signed circulation is measured from the generated polyline; one shared ' ...
         'sign across active layers means the fields add rather than cancel.'] };
    t.physNotes = { sprintf('Series network: %s', seq), ...
        'Inactive layers carry no copper; the physical DXF drops non-functional pads on unconnected layers.', ...
        'DXF is engineering geometry, not Gerber; review stackup, material and electrical data before fabrication.' };
    t.comsolNotes = { 'Closed main-spiral contour; select it as a domain or boundary coil in COMSOL, thickness 0.012 mm.', ...
        'This figure documents the exported simulation geometry only; it does not claim a successful COMSOL import or solve.' };
end
end

function s = senseZh(multi)
if multi
    s = '，与其余活动层同向（磁场叠加）';
else
    s = '';
end
end

function s = senseEn(multi)
if multi
    s = ', same sense as the other active layers (fields add)';
else
    s = '';
end
end

function [turns, circDeg] = measureLayer(result, li)
xy = result.layerPaths(li).coilXY;
turns = 0;
circDeg = 0;
if isempty(xy) || size(xy, 1) < 2
    return;
end
dx = diff(xy(:, 1));
dy = diff(xy(:, 2));
xm = (xy(1:end - 1, 1) + xy(2:end, 1)) / 2;
ym = (xy(1:end - 1, 2) + xy(2:end, 2)) / 2;
r2 = xm.^2 + ym.^2;
valid = r2 > eps;
inc = zeros(numel(r2), 1);
inc(valid) = (xm(valid) .* dy(valid) - ym(valid) .* dx(valid)) ./ r2(valid);
inc = inc(isfinite(inc));
circDeg = rad2deg(sum(inc));
turns = abs(circDeg) / 360;
end

function svg = renderAnnotated(srcPath, lang, f, clipId)
[~, inner] = readSvgParts(srcPath);
b = svgContentBounds(inner);
pad = 1.15;
vx = b(1) - pad;
vy = b(2) - pad;
vw = (b(3) - b(1)) + 2 * pad;
vh = (b(4) - b(2)) + 2 * pad;
if f.hasTerminalLabels
    inner = rewriteTerminalLabels(inner, lang, [vx, vy, vw, vh]);
end

% 字号随帧宽等比缩放，使不同层数/缩放下的可读性一致。
kk = min(max(vw / 29.99, 0.8), 1.8);
m = 0.9 * kk;
szTitle = 1.62 * kk;
szSub = 0.86 * kk;
szHead = 1.06 * kk;
szBody = 0.86 * kk;
linePitch = 1.28 * kk;
font = fontStack(lang);
usable = vw - 2 * m;

titleLines = wrapText(f.title, szTitle, usable);
subLines = wrapText(f.subtitle, szSub, usable);
headH = 2.0 + numel(titleLines) * 2.0 * kk + 0.30 + numel(subLines) * 1.20 * kk + 1.0;

lg = legendLayout(f.legendLabel, f.legendColor, szBody, kk, vx + m, usable, 0, font);
noteLines = {};
for q = 1:numel(f.notes)
    noteLines = [noteLines, wrapText(f.notes{q}, szBody, usable - 0.6 * kk)]; %#ok<AGROW>
end
footH = 1.5 * kk + lg.height + 0.55 * kk + 1.5 * kk + ...
    numel(noteLines) * linePitch + 1.2 * kk;

ny = vy - headH;
nh = headH + vh + footH;
out = cell(0, 1);
out{end + 1} = sprintf(['<svg xmlns="http://www.w3.org/2000/svg" ' ...
    'data-annotated-lang="%s" data-annotated-source="%s" ' ...
    'viewBox="%.6f %.6f %.6f %.6f" width="%d" height="%d">'], ...
    lang, xmlEscape(strrep(f.src, '\', '/')), vx, ny, vw, nh, ...
    round(vw * 40), round(nh * 40));
out{end + 1} = sprintf(['<rect x="%.6f" y="%.6f" width="%.6f" height="%.6f" ' ...
    'fill="#ffffff"/>'], vx, ny, vw, nh);

y = ny + 2.0;
for q = 1:numel(titleLines)
    out{end + 1} = text(sprintf('%.6f', vx + m), sprintf('%.6f', y), font, ...
        szTitle, '#111111', 'bold', titleLines{q}); %#ok<AGROW>
    y = y + 2.0 * kk;
end
y = y + 0.30;
for q = 1:numel(subLines)
    out{end + 1} = text(sprintf('%.6f', vx + m), sprintf('%.6f', y), font, ...
        szSub, '#555555', '', subLines{q}); %#ok<AGROW>
    y = y + 1.20 * kk;
end
out{end + 1} = sprintf(['<line x1="%.6f" y1="%.6f" x2="%.6f" y2="%.6f" ' ...
    'stroke="#cccccc" stroke-width="0.06"/>'], ...
    vx + m, vy - 0.45 * kk, vx + vw - m, vy - 0.45 * kk);

% 绘制内容保持原始坐标：不得再叠加 translate，否则会与页脚重叠。clipPath 只覆盖
% 绘图区，因此端子引线伸到框外的部分（原基线预览把它们引到很大的 extent 角落）
% 不会在标题带里留下悬空的短线。
out{end + 1} = sprintf(['<defs><clipPath id="%s"><rect x="%.6f" y="%.6f" ' ...
    'width="%.6f" height="%.6f"/></clipPath></defs>'], clipId, vx, vy, vw, vh);
out{end + 1} = sprintf('<g clip-path="url(#%s)">', clipId);
out{end + 1} = inner;
out{end + 1} = '</g>';

fy = vy + vh + 1.3 * kk;
out{end + 1} = text(sprintf('%.6f', vx + m), sprintf('%.6f', fy), font, szHead, ...
    '#111111', 'bold', headingText(lang, 'legend'));
lg = legendLayout(f.legendLabel, f.legendColor, szBody, kk, vx + m, usable, ...
    fy + 0.55 * kk, font);
% out 与 lg.ops 都是行 cell（由 {end+1} 增长而来），必须横向拼接。
out = [out, lg.ops];
nyy = fy + 0.55 * kk + lg.height + 0.55 * kk;
out{end + 1} = text(sprintf('%.6f', vx + m), sprintf('%.6f', nyy), font, szHead, ...
    '#111111', 'bold', headingText(lang, 'notes'));
yy = nyy + 1.35 * kk;
for q = 1:numel(noteLines)
    out{end + 1} = text(sprintf('%.6f', vx + m + 0.3 * kk), sprintf('%.6f', yy), ...
        font, szBody, '#444444', '', noteLines{q}); %#ok<AGROW>
    yy = yy + linePitch;
end
out{end + 1} = '</svg>';
svg = strjoin(out, sprintf('\n'));
end

function s = text(x, y, font, size, fill, weight, body)
if isempty(weight)
    w = '';
else
    w = sprintf(' font-weight="%s"', weight);
end
s = sprintf(['<text x="%s" y="%s" font-family="%s" font-size="%.3f"%s ' ...
    'fill="%s">%s</text>'], x, y, font, size, w, fill, xmlEscape(body));
end

function s = headingText(lang, which)
if strcmp(which, 'legend')
    if strcmp(lang, 'zh'), s = '图例'; else, s = 'Legend'; end
else
    if strcmp(lang, 'zh'), s = '说明'; else, s = 'Notes'; end
end
end

function s = fontStack(lang)
if strcmp(lang, 'zh')
    s = 'Microsoft YaHei, Noto Sans CJK SC, Source Han Sans SC, SimHei, sans-serif';
else
    s = 'Segoe UI, Helvetica Neue, Arial, sans-serif';
end
end

function lg = legendLayout(labels, colors, szBody, kk, x0, width, y0, font)
% 两列流式布局：条目按列宽折行，行高取该行最高单元，因此不会越界或压字。
cols = 2;
sw = 1.35 * kk;
sh = 0.72 * kk;
gap = 0.55 * kk;
linePitch = 1.28 * kk;
colW = (width - 0.8 * kk) / cols;
txtW = colW - sw - gap;
ops = cell(0, 1);
y = y0;
cells = {};
for k = 1:numel(labels)
    lines = wrapText(labels{k}, szBody, txtW);
    cells{end + 1} = struct('color', colors{k}, 'lines', {lines}); %#ok<AGROW>
    if numel(cells) == cols
        [ops, y] = emitRow(ops, cells, x0, colW, y, sw, sh, gap, linePitch, ...
            szBody, kk, font);
        cells = {};
    end
end
if ~isempty(cells)
    [ops, y] = emitRow(ops, cells, x0, colW, y, sw, sh, gap, linePitch, ...
        szBody, kk, font);
end
lg = struct('ops', {ops}, 'height', y - y0);
end

function [ops, y] = emitRow(ops, cells, x0, colW, y, sw, sh, gap, linePitch, ...
    szBody, kk, font)
rowH = 0;
for i = 1:numel(cells)
    rowH = max(rowH, numel(cells{i}.lines) * linePitch);
end
for i = 1:numel(cells)
    cx = x0 + (i - 1) * (colW + 0.8 * kk);
    ops{end + 1} = sprintf(['<rect x="%.6f" y="%.6f" width="%.6f" ' ...
        'height="%.6f" fill="%s" stroke="#333333" stroke-width="0.05"/>'], ...
        cx, y, sw, sh, cells{i}.color);
    for j = 1:numel(cells{i}.lines)
        ops{end + 1} = text(sprintf('%.6f', cx + sw + gap), ...
            sprintf('%.6f', y + 0.62 * kk + (j - 1) * linePitch), font, szBody, ...
            '#222222', '', cells{i}.lines{j});
    end
end
y = y + rowH + 0.30 * kk;
end

function [vb, inner] = readSvgParts(path)
% 注意：MATLAB 的 regexp 在此处不能用 \b 词边界（会匹配失败），改用非贪婪的
% [^>]*? 限定标签头，再用贪婪 (.*) 取到最后一个 </svg> 之间的内容。
txt = fileread(path);
tok = regexp(txt, '(?s)<svg[^>]*?viewBox="([^"]+)"[^>]*>(.*)</svg>', ...
    'tokens', 'once');
if isempty(tok)
    error('CircularFPC:ExportReadbackFailed', 'Cannot parse SVG: %s', path);
end
vb = sscanf(tok{1}, '%f', 4).';
inner = tok{2};
end

function b = svgContentBounds(inner)
xs = [];
ys = [];
tok = regexp(inner, 'points="([^"]+)"', 'tokens');
for k = 1:numel(tok)
    v = sscanf(strrep(tok{k}{1}, ',', ' '), '%f');
    if numel(v) >= 4
        xs = [xs; v(1:2:end)]; %#ok<AGROW>
        ys = [ys; v(2:2:end)]; %#ok<AGROW>
    end
end
tok = regexp(inner, '<circle[^>]*\bcx="([-0-9.eE+]+)"[^>]*\bcy="([-0-9.eE+]+)"', 'tokens');
for k = 1:numel(tok)
    xs(end + 1, 1) = str2double(tok{k}{1}); %#ok<AGROW>
    ys(end + 1, 1) = str2double(tok{k}{2}); %#ok<AGROW>
end
if isempty(xs)
    error('CircularFPC:ExportReadbackFailed', ...
        'Annotated preview source has no drawable bounds.');
end
b = [min(xs), min(ys), max(xs), max(ys)];
end

function inner = rewriteTerminalLabels(inner, lang, box)
% 保留 data-* 机器可读属性与引线设计，只把显示文字与锚点搬到裁剪后的框内左上
% 角并放大字号，避免端子标注与图面脱节或不可读。
names = terminalNames(inner);
if isempty(names)
    return;
end
lx = box(1) + 0.45;
ty0 = box(2) + 1.5;
pitch = 0.62;
anchor = struct();
for k = 1:numel(names)
    anchor.(names{k}) = [lx, ty0 + (k - 1) * pitch];
end
disp_ = terminalDisplayText(lang, names);

pat = '<text class="terminal-label"([^>]*)>([^<]*)</text>';
toks = regexp(inner, pat, 'tokens');
for k = 1:numel(toks)
    attrs = toks{k}{1};
    nm = regexp(attrs, 'data-name="([^"]+)"', 'tokens', 'once');
    if isempty(nm) || ~isfield(anchor, nm{1})
        continue;
    end
    a = anchor.(nm{1});
    newAttrs = regexprep(attrs, 'x="[^"]*"', sprintf('x="%.6f"', a(1)), 'once');
    newAttrs = regexprep(newAttrs, 'y="[^"]*"', sprintf('y="%.6f"', a(2)), 'once');
    newAttrs = regexprep(newAttrs, 'font-size="[^"]*"', 'font-size="0.42"', 'once');
    inner = strrep(inner, ['<text class="terminal-label"' attrs '>' toks{k}{2} '</text>'], ...
        ['<text class="terminal-label"' newAttrs '>' xmlEscape(disp_.(nm{1})) '</text>']);
end

pat = '<line class="terminal-leader"([^>]*)/>';
toks = regexp(inner, pat, 'tokens');
for k = 1:numel(toks)
    attrs = toks{k}{1};
    nm = regexp(attrs, 'data-name="([^"]+)"', 'tokens', 'once');
    if isempty(nm) || ~isfield(anchor, nm{1})
        continue;
    end
    a = anchor.(nm{1});
    newAttrs = regexprep(attrs, 'x2="[^"]*"', sprintf('x2="%.6f"', a(1)), 'once');
    newAttrs = regexprep(newAttrs, 'y2="[^"]*"', sprintf('y2="%.6f"', a(2) + 0.12), 'once');
    newAttrs = regexprep(newAttrs, 'stroke-width="[^"]*"', 'stroke-width="0.045"', 'once');
    newAttrs = regexprep(newAttrs, 'opacity="[^"]*"', 'opacity="0.6"', 'once');
    inner = strrep(inner, ['<line class="terminal-leader"' attrs '/>'], ...
        ['<line class="terminal-leader"' newAttrs '/>']);
end
end

function names = terminalNames(inner)
toks = regexp(inner, '<text class="terminal-label"[^>]*data-name="([^"]+)"', ...
    'tokens');
names = {};
for k = 1:numel(toks)
    if ~ismember(toks{k}{1}, names)
        names{end + 1} = toks{k}{1}; %#ok<AGROW>
    end
end
end

function d = terminalDisplayText(lang, names)
d = struct();
for k = 1:numel(names)
    nm = names{k};
    entry = any(strcmp(nm, {'PAD_A', 'PAD_B', 'VOUT'}));
    if strcmp(lang, 'zh')
        if entry
            d.(nm) = sprintf('%s · 入口桥', nm);
        else
            d.(nm) = sprintf('%s · 线圈外端', nm);
        end
    else
        if entry
            d.(nm) = sprintf('%s - entry bridge', nm);
        else
            d.(nm) = sprintf('%s - coil outer end', nm);
        end
    end
end
end

function s = xmlEscape(s)
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
s = strrep(s, '"', '&quot;');
s = strrep(s, '''', '&apos;');
end

function lines = wrapText(s, size, maxW)
toks = wrapTokens(s);
lines = {};
cur = '';
for k = 1:numel(toks)
    cand = [cur toks{k}]; %#ok<AGROW>
    if textWidth(cand, size) <= maxW
        cur = cand;
        continue;
    end
    if ~isempty(strtrim(cur))
        lines{end + 1} = strtrim(cur); %#ok<AGROW>
    end
    cur = strtrim(toks{k});
    while textWidth(cur, size) > maxW && ~isempty(cur)
        n = longestPrefix(cur, size, maxW);
        lines{end + 1} = cur(1:n); %#ok<AGROW>
        cur = cur(n + 1:end);
    end
end
if ~isempty(strtrim(cur))
    lines{end + 1} = strtrim(cur);
end
if isempty(lines)
    lines = {''};
end
% 中文行末的句号若被折到下一行会孤立成"。"，读起来像排版错误；把它并回上一行。
lines = pullTrailingPunctuation(lines);
end

function lines = pullTrailingPunctuation(lines)
% 允许行尾略微超出列宽（仍远小于帧宽），避免全角句号单独占一行。
if numel(lines) < 2
    return;
end
for k = 1:numel(lines) - 1
    nxt = lines{k + 1};
    if ~isempty(nxt) && any(double(nxt(1)) == [12290, 65281, 65311, 65292, 12289])
        lines{k} = [lines{k} nxt(1)];
        lines{k + 1} = strtrim(nxt(2:end));
    end
end
lines = lines(~cellfun(@(x) isempty(strtrim(x)), lines));
if isempty(lines)
    lines = {''};
end
end

function n = longestPrefix(s, size, maxW)
n = 1;
while n < numel(s) && textWidth(s(1:n + 1), size) <= maxW
    n = n + 1;
end
end

function toks = wrapTokens(s)
% CJK 逐字可断行，拉丁词按空格分组，使中英混排都能贴列宽折行。
toks = {};
buf = '';
for k = 1:numel(s)
    ch = s(k);
    if isWideCode(double(ch))
        if ~isempty(buf)
            toks{end + 1} = buf; %#ok<AGROW>
            buf = '';
        end
        toks{end + 1} = ch; %#ok<AGROW>
    elseif ch == ' '
        if ~isempty(buf)
            toks{end + 1} = buf; %#ok<AGROW>
            buf = '';
        end
        toks{end + 1} = ' '; %#ok<AGROW>
    else
        buf = [buf ch]; %#ok<AGROW>
    end
end
if ~isempty(buf)
    toks{end + 1} = buf;
end
end

function w = textWidth(s, size)
c = double(s);
if isempty(c)
    w = 0;
    return;
end
w = sum(size * (0.56 + 0.44 * isWideCode(c)));
end

function tf = isWideCode(cp)
tf = (cp >= 4352 & cp <= 4447) | ...      % Hangul Jamo
    (cp >= 11904 & cp <= 42191) | ...     % CJK radicals, Kana, CJK, Yi
    (cp >= 44032 & cp <= 55215) | ...     % Hangul syllables
    (cp >= 63744 & cp <= 64255) | ...     % CJK compatibility ideographs
    (cp >= 65072 & cp <= 65103) | ...     % CJK compatibility forms
    (cp >= 65280 & cp <= 65519);          % Fullwidth forms
end

function auditAll(previewRoot)
% 回读校验：语言元数据、文字不越界、正文不重叠、base 与既有预览逐字节一致。
% 图数量随活动层数变化（单活动层组合少一张分层图），因此不与固定数字比较，而是
% 要求 base/zh/en 三组文件集合完全相同、且至少含总览/物理铜/两种 COMSOL 四张。
langs = {'base', 'zh', 'en'};
lists = cell(1, numel(langs));
for k = 1:numel(langs)
    langDir = fullfile(previewRoot, langs{k});
    if ~isfolder(langDir)
        error('CircularFPC:ExportReadbackFailed', ...
            'Missing annotated preview folder: %s', langDir);
    end
    files = dir(fullfile(langDir, '**', '*.svg'));
    for q = 1:numel(files)
        % 相对路径参与比较，避免 JLC/ 与 COMSOL/ 同名文件互换而未被发现。
        files(q).rel = strrep(strrep(fullfile(files(q).folder, files(q).name), ...
            [langDir filesep], ''), '\', '/');
    end
    rel = sort({files.rel});
    if isempty(rel)
        error('CircularFPC:ExportReadbackFailed', ...
            'Annotated preview folder is empty: %s', langDir);
    end
    lists{k} = rel;
end
for k = 2:numel(langs)
    if ~isequal(lists{k}, lists{1})
        error('CircularFPC:ExportReadbackFailed', ...
            ['Annotated preview sets must hold the same figures; %s differs ' ...
             'from %s.'], strjoin(langs(k), ''), strjoin(langs(1), ''));
    end
end
for req = {'_centerline_overview.svg', '_physical_overview.svg', ...
        '_main_overview.svg', '_with_terminals_overview.svg'}
    % 用 endsWith 逐个文件判断：把文件名拼接后再用 $ 锚定只会匹配到最后一个。
    if ~any(endsWith(string(lists{1}), req{1}))
        error('CircularFPC:ExportReadbackFailed', ...
            'Annotated preview set is missing a required figure: *%s', req{1});
    end
end
for k = 1:numel(langs)
    langDir = fullfile(previewRoot, langs{k});
    files = dir(fullfile(langDir, '**', '*.svg'));
    for q = 1:numel(files)
        p = fullfile(files(q).folder, files(q).name);
        txt = fileread(p);
        xmlread(p);
        if strcmp(langs{k}, 'base')
            continue;
        end
        if ~contains(txt, sprintf('data-annotated-lang="%s"', langs{k}))
            error('CircularFPC:ExportReadbackFailed', ...
                'Annotated language metadata mismatch: %s', p);
        end
        [vb, inner] = readSvgParts(p);
        checkNoOverflow(inner, vb, p);
        checkNoOverlap(inner, p);
        checkLegendColors(txt, inner, p, previewRoot);
    end
end
% base 组必须与既有 JLC/、COMSOL/ 预览逐字节一致，否则"基础预览"会变成另一份图。
% 物理铜总览的序号随活动层数变化（单活动层组合少一张分层图，物理铜是 03 而非
% 04），因此按后缀定位而不是写死文件名。
physBase = dir(fullfile(previewRoot, 'base', 'JLC', '*_physical_overview.svg'));
if numel(physBase) ~= 1
    error('CircularFPC:ExportReadbackFailed', ...
        'Expected exactly one base physical overview, found %d.', numel(physBase));
end
pairs = { ...
    fullfile('JLC', 'centerline', '01_preview_full.svg'), ...
        fullfile('base', 'JLC', '01_centerline_overview.svg'); ...
    fullfile('JLC', 'physical', '01_preview_full.svg'), ...
        fullfile('base', 'JLC', physBase(1).name); ...
    fullfile('COMSOL', '01_comsol_dxf_full.svg'), ...
        fullfile('base', 'COMSOL', '01_main_overview.svg'); ...
    fullfile('COMSOL', 'with_terminals', '01_comsol_with_terminals_full.svg'), ...
        fullfile('base', 'COMSOL', '02_with_terminals_overview.svg')};
for k = 1:size(pairs, 1)
    a = fullfile(previewRoot, pairs{k, 1});
    b = fullfile(previewRoot, pairs{k, 2});
    if ~isfile(a) || ~isfile(b)
        error('CircularFPC:ExportReadbackFailed', ...
            'Base preview pair missing: %s / %s', a, b);
    end
    if ~strcmp(sha256File(a), sha256File(b))
        error('CircularFPC:ExportReadbackFailed', ...
            'Base preview is not a byte copy of the contract preview: %s', b);
    end
end
end

function checkLegendColors(fullTxt, inner, path, previewRoot)
% 图例色块必须是被标注源 SVG 中真实使用过的颜色，否则图例在撒谎。这里读回源
% 文件按 fill=/stroke= 实测，而不是相信生成端的调色板常量。
% data-annotated-source 写在 <svg> 标签上，因此要从完整文本取，不能只看 inner。
src = regexp(fullTxt, 'data-annotated-source="([^"]+)"', 'tokens', 'once');
if isempty(src)
    error('CircularFPC:ExportReadbackFailed', ...
        'Annotated preview lacks its source reference: %s', path);
end
srcPath = fullfile(previewRoot, src{1});
if ~isfile(srcPath)
    error('CircularFPC:ExportReadbackFailed', ...
        'Annotated preview cites a missing source: %s', srcPath);
end
srcTxt = fileread(srcPath);
% regexp(...,'tokens') 返回嵌套 cell（每个匹配是一个 {1x1 cell}），先展平。
srcColors = string(lower([ ...
    flattenTokens(regexp(srcTxt, 'fill="(#[0-9a-fA-F]{6})"', 'tokens')), ...
    flattenTokens(regexp(srcTxt, 'stroke="(#[0-9a-fA-F]{6})"', 'tokens')) ]));
swatch = regexp(inner, ['<rect x="[^"]*" y="[^"]*" width="[^"]*" height="[^"]*" ' ...
    'fill="(#[0-9a-fA-F]{6})" stroke="#333333"'], 'tokens');
swatch = flattenTokens(swatch);
if isempty(swatch)
    error('CircularFPC:ExportReadbackFailed', ...
        'Annotated preview has no legend swatches: %s', path);
end
for k = 1:numel(swatch)
    c = lower(string(swatch{k}));
    if ~ismember(c, srcColors)
        error('CircularFPC:ExportReadbackFailed', ...
            ['Legend swatch %s in %s does not appear in its annotated source; ' ...
             'the legend would misdescribe the drawing.'], c, path);
    end
end
end

function out = flattenTokens(tok)
% 把 regexp 'tokens' 的嵌套 cell 展平成字符串 cell。
out = {};
for k = 1:numel(tok)
    out{end + 1} = tok{k}{1}; %#ok<AGROW>
end
end

function checkNoOverflow(inner, vb, path)
% 每段文字用与生成端一致的宽度估算，超出帧宽即失败。
x0 = vb(1);
x1 = vb(1) + vb(3);
toks = regexp(inner, '<text\b([^>]*)>([^<]*)</text>', 'tokens');
for k = 1:numel(toks)
    attrs = toks{k}{1};
    body = toks{k}{2};
    body = strrep(strrep(strrep(body, '&amp;', '&'), '&lt;', '<'), '&gt;', '>');
    sz = regexp(attrs, 'font-size="([^"]+)"', 'tokens', 'once');
    xa = regexp(attrs, 'x="([^"]+)"', 'tokens', 'once');
    if isempty(sz) || isempty(xa)
        continue;
    end
    x = str2double(xa{1});
    w = textWidth(body, str2double(sz{1}));
    if x < x0 - 1e-6 || x + w > x1 + 1e-6
        error('CircularFPC:ExportReadbackFailed', ...
            'Annotated text overflows the frame in %s: "%s" x=[%.3f %.3f] frame=[%.3f %.3f]', ...
            path, body, x, x + w, x0, x1);
    end
end
end

function checkNoOverlap(inner, path)
% 正文互不压字。端子标注本来就在图形空白处，这里只比较同字号文本框，
% 并用半行高作为容差，避免把正常行距误判为重叠。
toks = regexp(inner, '<text\b([^>]*)>([^<]*)</text>', 'tokens');
boxes = zeros(0, 6);
for k = 1:numel(toks)
    attrs = toks{k}{1};
    body = toks{k}{2};
    body = strrep(strrep(strrep(body, '&amp;', '&'), '&lt;', '<'), '&gt;', '>');
    sz = regexp(attrs, 'font-size="([^"]+)"', 'tokens', 'once');
    xa = regexp(attrs, 'x="([^"]+)"', 'tokens', 'once');
    ya = regexp(attrs, 'y="([^"]+)"', 'tokens', 'once');
    if isempty(sz) || isempty(xa) || isempty(ya)
        continue;
    end
    s = str2double(sz{1});
    x = str2double(xa{1});
    y = str2double(ya{1});
    boxes(end + 1, :) = [x, y - s * 0.8, x + textWidth(body, s), y + s * 0.25, s, k]; %#ok<AGROW>
end
for i = 1:size(boxes, 1)
    for j = i + 1:size(boxes, 1)
        if abs(boxes(i, 5) - boxes(j, 5)) > 1e-9
            continue;
        end
        ox = min(boxes(i, 3), boxes(j, 3)) - max(boxes(i, 1), boxes(j, 1));
        oy = min(boxes(i, 4), boxes(j, 4)) - max(boxes(i, 2), boxes(j, 2));
        if ox > 0.15 && oy > 0.15
            error('CircularFPC:ExportReadbackFailed', ...
                'Annotated text boxes overlap in %s (rows %d and %d).', ...
                path, boxes(i, 6), boxes(j, 6));
        end
    end
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
md.update(raw);
d = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(d, 2).', 1, []));
end
