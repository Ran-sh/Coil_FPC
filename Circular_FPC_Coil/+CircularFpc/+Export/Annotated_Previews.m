function varargout = Annotated_Previews(operation, varargin)
% ANNOTATEDPREVIEWS 中英双语标注预览集：preview/ 的完整镜像。
%
%   'write'  把 <previewRoot> 下 JLC/、COMSOL/ 里的每一张契约预览，按**同一相对
%            路径**镜像到 zh/（中文标注）与 en/（英文标注）。三组结构一致、文件名
%            相同，只有标注语言不同，因此规则只有一条"同名不同语言"。
%
%   'audit'  回读镜像并检查：每个契约预览都有对应的 zh/en 两份；XML 可解析；语言
%            元数据正确；每段文字不越出帧宽；同字号正文互不重叠；图例色块必须是其
%            标注源里真实出现过的颜色。
%
% 设计要点：标注图**不重新绘制几何**，而是读回已经写出的契约预览再封装（标题带 +
% 图例 + 说明），所以标注图与其说明对象使用同一批图元，不存在第二套绘图代码，也
% 就不可能画出与 DXF 不一致的图。契约组 JLC/、COMSOL/ 的文件字节不变。本函数在写
% manifest 之前被调用，故每个镜像文件都属于原子发布并登记 role。任何排版失败都会
% 报错，发布不会带着溢出的文字落到正式产物里。
if nargin < 1
    error('CircularFPC:InvalidOperation', 'Annotated preview requires an operation.');
end
switch operation
    case 'write'
        writeAll(varargin{1}, varargin{2}, varargin{3});
    case 'audit'
        auditAll(varargin{1}, varargin{2});
    otherwise
        error('CircularFPC:InvalidOperation', ...
            'Unknown annotated-preview operation: %s', operation);
end
end

function writeAll(cfg, result, previewRoot)
langs = {'zh', 'en'};
rels = contractPreviewList(previewRoot);
for k = 1:numel(langs)
    lang = langs{k};
    t = annotationText(lang, cfg, result);
    for q = 1:numel(rels)
        rel = rels{q};
        srcPath = fullfile(previewRoot, strrep(rel, '/', filesep));
        plan = figurePlan(rel, t, result);
        svg = renderAnnotated(srcPath, lang, plan);
        outPath = fullfile(previewRoot, lang, strrep(rel, '/', filesep));
        outDir = fileparts(outPath);
        if ~isfolder(outDir)
            mkdir(outDir);
        end
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

function rels = contractPreviewList(previewRoot)
% 契约预览清单取自磁盘，因此新增预览种类时镜像自动跟上，不会漏图。
rels = {};
for grp = {'JLC', 'COMSOL'}
    d = dir(fullfile(previewRoot, grp{1}, '**', '*.svg'));
    for k = 1:numel(d)
        full = fullfile(d(k).folder, d(k).name);
        rels{end + 1} = strrep(strrep(full, [previewRoot filesep], ''), '\', '/'); %#ok<AGROW>
    end
end
if isempty(rels)
    error('CircularFPC:ExportWriteFailed', ...
        'No contract previews found to mirror under %s.', previewRoot);
end
rels = sort(rels);
end

function plan = figurePlan(rel, t, result)
% 按统一命名判定图的种类并选标注文案。命名由 Dxf_Svg_Reports 产生：
%   01_overview / 02_connection_zone / 1x_layer_Lx_<role>
plan = struct('rel', rel, 'title', '', 'subtitle', '', 'legend', struct('color', {}, 'label', {}), ...
    'notes', {{}});
isComsol = startsWith(rel, 'COMSOL/');
isTerminals = contains(rel, 'with_terminals/');
isOverview = endsWith(rel, '01_overview.svg');
isZone = endsWith(rel, '02_connection_zone.svg');
isPhysical = contains(rel, '/physical/');
li = layerFromName(rel);
active = result.activeCoilLayers;

if isComsol
    if isOverview
        if isTerminals
            plan.title = t.ctTitle;
            plan.subtitle = t.ctSub;
        else
            plan.title = t.cmTitle;
            plan.subtitle = t.cmSub;
        end
        plan.legend = comsolLegend(t, result, isTerminals);
    elseif ~ismember(li, active)
        % 非活动层在仿真轨里确实是空图（无铜），如实说明，不硬套层图标题。
        plan.title = sprintf(t.cmEmptyTitle, li);
        plan.subtitle = t.cmEmptySub;
        plan.legend = item('#9aa5aa', t.lgReference);
    else
        m = measuredCirculation(result, li);
        plan.title = sprintf(t.cmLayerTitle, li);
        plan.subtitle = sprintf(t.cmLayerSub, li);
        plan.legend = comsolLayerLegend(t, li);
    end
    plan.notes = t.comsolNotes;
elseif isOverview
    if isPhysical
        plan.title = t.physTitle;
        plan.subtitle = t.physSub;
        plan.notes = t.physNotes;
    else
        plan.title = t.ovTitle;
        plan.subtitle = t.ovSub;
        plan.notes = t.ovNotes;
    end
    plan.legend = jlcLegend(t, result);
elseif isZone
    plan.title = t.zoneTitle;
    if isPhysical
        plan.subtitle = t.zoneSubPhysical;
    else
        plan.subtitle = t.zoneSubCenterline;
    end
    plan.notes = t.zoneNotes;
    plan.legend = zoneLegend(t, result);
else
    role = roleFromName(rel);
    if isfield(t.layerRoleName, role)
        roleLabel = t.layerRoleName.(role);
    else
        roleLabel = role;
    end
    plan.legend = layerLegend(t, result, li);
    plan.notes = t.layerNotes;
    if ~ismember(li, active) || isempty(result.layerPaths(li).coilXY)
        % 非活动层没有铜箔，也就没有匝数或环绕角可测；如实说明，不能印一个
        % "实测 NaN 匝"的假指标。
        plan.title = sprintf(t.layerInactiveTitle, li, roleLabel);
        plan.subtitle = t.layerInactiveSub;
    else
        m = measuredCirculation(result, li);
        plan.title = sprintf(t.layerTitle, li, roleLabel);
        plan.subtitle = sprintf(t.layerSub, m.turns, m.circ, ...
            senseSuffix(strcmp(t.lang, 'zh'), t.multiSenseZh));
    end
end
end

function role = roleFromName(rel)
tok = regexp(rel, '_L\d+_([a-z0-9]+)\.svg$', 'tokens', 'once');
if isempty(tok)
    role = 'unknown';
else
    role = tok{1};
end
end

function li = layerFromName(rel)
tok = regexp(rel, '_L(\d+)_', 'tokens', 'once');
if isempty(tok)
    li = NaN;
else
    li = str2double(tok{1});
end
end

function s = measuredCirculation(result, li)
turns = NaN;
circ = NaN;
if isfinite(li) && li >= 1 && li <= numel(result.layerPaths)
    xy = result.layerPaths(li).coilXY;
    if ~isempty(xy) && size(xy, 1) > 1
        dx = diff(xy(:, 1));
        dy = diff(xy(:, 2));
        xm = (xy(1:end - 1, 1) + xy(2:end, 1)) / 2;
        ym = (xy(1:end - 1, 2) + xy(2:end, 2)) / 2;
        r2 = xm.^2 + ym.^2;
        inc = zeros(numel(r2), 1);
        v = r2 > eps;
        inc(v) = (xm(v) .* dy(v) - ym(v) .* dx(v)) ./ r2(v);
        inc = inc(isfinite(inc));
        circ = rad2deg(sum(inc));
        turns = abs(circ) / 360;
    end
end
s = struct('turns', turns, 'circ', circ);
end

function leg = jlcLegend(t, result)
leg = struct('color', {}, 'label', {});
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
% 逐层预览只有 L1 画焊盘与独立电极（见 Dxf_Svg_Reports 的 writeSvgLayer），其余层
% 不画；图例跟着实际图元走，避免"图例有、画面无"的假说明。
leg = struct('color', {}, 'label', {});
leg(end + 1) = item('#ffcc1a', t.lgBoard);
leg(end + 1) = item('#8c1aa6', t.lgEdge);
% 该层是否真有铜箔决定要不要列铜色块：非活动层根本不画铜，列了就是假图例。
if ismember(li, result.activeCoilLayers) && ~isempty(result.layerPaths(li).coilXY)
    leg(end + 1) = item(layerColor(li), sprintf(t.lgLayer, li));
else
    leg(end + 1) = item('#8fcfdc', t.lgInactive);
end
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

function leg = zoneLegend(t, result)
% 端子连接区是局部放大图。它只画**真的有连接走线**的层（writeSvgConnectionZone
% 遍历 connectionPaths），也不画 315° 独立电极，因此图例只列实际会出现的走线
% 颜色、焊盘与过孔，避免"图例有、画面无"。
leg = struct('color', {}, 'label', {});
leg(end + 1) = item('#ffcc1a', t.lgBoard);
leg(end + 1) = item('#8c1aa6', t.lgEdge);
for li = 1:numel(result.layerPaths)
    if ~isempty(result.layerPaths(li).connectionPaths)
        leg(end + 1) = item(layerColor(li), sprintf(t.lgLayer, li)); %#ok<AGROW>
    end
end
if ~isempty(result.pads)
    leg(end + 1) = item('#e61919', t.lgPad);
end
if ~isempty(result.vias)
    leg(end + 1) = item('#474747', t.lgVia);
end
end

function leg = comsolLayerLegend(t, li)
% 单层仿真预览只画该层自己的闭合轮廓，图例因此只列该层，避免出现画面上没有的颜色。
leg = struct('color', {}, 'label', {});
leg(end + 1) = item('#9aa5aa', t.lgReference);
leg(end + 1) = item(layerColor(li), sprintf(t.lgLayer, li));
end

function leg = comsolLegend(t, result, withTerminals)
leg = struct('color', {}, 'label', {});
leg(end + 1) = item('#9aa5aa', t.lgReference);
for k = 1:numel(result.activeCoilLayers)
    li = result.activeCoilLayers(k);
    if withTerminals && li == 1
        % 带端子变体里端子焊盘与 L1 铜轮廓同色，并进 L1 条目说明，避免出现两个
        % 一模一样的色块。
        leg(end + 1) = item(layerColor(li), sprintf('%s · %s', ...
            sprintf(t.lgLayer, li), t.lgTermPad));
    else
        leg(end + 1) = item(layerColor(li), sprintf(t.lgLayer, li));
    end
end
end

function it = item(color, label)
it = struct('color', color, 'label', label);
end

function c = layerColor(li)
% 与 Dxf_Svg_Reports 的铜层调色板一致；audit 会回读源 SVG 实际颜色核对。
palette = {'#e61919', '#f2790a', '#1a9933', '#1a4de6'};
c = palette{mod(li - 1, 4) + 1};
end

function t = annotationText(lang, cfg, result)
t.lang = lang;
boardD = result.effectiveDimensions.boardOuterDiameter;
innerD = result.effectiveDimensions.coilInnerDiameter;
pitch = result.effectiveDimensions.coilPitch;
active = result.activeCoilLayers;
layerList = strjoin(arrayfun(@(v) sprintf('L%d', v), active, 'UniformOutput', false), ', ');
seq = strjoin(result.seriesSequence, ' -> ');
viaNames = strjoin(sort({result.vias.name}), ' / ');
nWarn = sum(strcmp({result.manufacturing.checks.status}, 'WARN'));
nCheck = numel(result.manufacturing.checks);
multi = numel(active) > 1 && result.validation.windingSuperpositionConsistent;

if strcmp(lang, 'zh')
    t.lgBoard = '板料（基材）';
    t.lgEdge = '板框轮廓';
    t.lgSlot = '挖槽：安装耳与平台槽';
    t.lgLayer = 'L%d 铜箔';
    t.lgPad = '端子焊盘 PAD_A / PAD_B（仅 L1）';
    t.lgInactive = '本层非活动线圈层，无铜箔';
    t.lgElec = '独立电极焊盘（仅 L1）';
    t.lgVia = sprintf('贯通过孔 %s', viaNames);
    t.lgSilk = '端子引线标注线';
    t.lgReference = '板框与挖槽轮廓（仿真参考）';
    t.lgTermPad = '含端子焊盘';

    t.ovTitle = sprintf('%d 层板 / %d 活动线圈层（%d/%d）— JLC 中心线总览', ...
        cfg.boardLayerCount, cfg.coilLayerCount, cfg.boardLayerCount, cfg.coilLayerCount);
    t.ovSub = sprintf('板外径 %.3f mm · 线圈内径 %.3f mm · 节距 %.3f mm · 每层约 %d 匝 · 活动层 %s', ...
        boardD, innerD, pitch, cfg.turnsPerCoilLayer, layerList);
    t.ovNotes = { sprintf('串联网络：%s', seq), ...
        sprintf('板层/活动层 %d/%d · 板厚 %.3f mm 标称 · 铜厚 %.3f mm · 工艺档案 %s', ...
            cfg.boardLayerCount, cfg.coilLayerCount, ...
            result.manufacturing.stackup.nominalFinishedThicknessMm, ...
            cfg.copperThickness, result.manufacturing.profile), ...
        sprintf('校验 passed=%d，制造检查 %d 项通过、其中 %d 项近限值警告（明细见 reports/）', ...
            result.validation.passed, nCheck, nWarn), ...
        'DXF 是工程几何，不是 Gerber；投产前请复核叠层、材料与电气参数。', ...
        '端子标注文字经放大与转写，几何与 DXF 同源，未改动任何图元。' };

    t.zoneTitle = '端子连接区局部';
    t.zoneSubCenterline = '中心线轨：入口单相切圆弧与 VOUT 直出引线，不改动螺旋采样点';
    t.zoneSubPhysical = '物理铜轨：按实际线宽绘制端子引线与焊盘';
    t.zoneNotes = { sprintf('串联网络：%s', seq), ...
        '端子走线使用由原始螺旋端点切线确定的单一相切圆弧，不通过第二圆弧或微折线补端点。' };

    t.layerTitle = 'L%d 铜箔（%s）';
    t.layerInactiveTitle = 'L%d（%s）— 非活动线圈层';
    t.layerInactiveSub = '本层不是活动线圈层，不含铜箔：图中只有板框、挖槽与贯通过孔，无走线与焊盘';
    t.layerSub = '实测 %.4f 匝 · 有向环绕角 %+.1f°%s';
    t.layerNotes = { sprintf('活动线圈层：%s', layerList), ...
        '有向环绕角由生成的线圈折线实测；各活动层同向即磁场叠加而非相消。' };

    t.physTitle = sprintf('%d 层板 / %d 活动线圈层（%d/%d）— JLC 物理铜总览', ...
        cfg.boardLayerCount, cfg.coilLayerCount, cfg.boardLayerCount, cfg.coilLayerCount);
    t.physSub = '按实际线宽、焊盘与过孔尺寸绘制，供嘉立创与 CAM 参考（不是 Gerber）';
    t.physNotes = { sprintf('串联网络：%s', seq), ...
        '非活动层不含铜箔；物理铜 DXF 移除未连接层的非功能焊盘。', ...
        'DXF 是工程几何，不是 Gerber；投产前请复核叠层、材料与电气参数。' };

    t.cmTitle = 'COMSOL 仿真几何 — 闭合铜轮廓总览';
    t.cmSub = '仅主阿基米德螺旋的闭合轮廓；不含过孔、钻孔、焊盘、端子与层间转换';
    t.cmLayerTitle = 'COMSOL 仿真几何 — L%d 闭合铜轮廓';
    t.cmLayerSub = '仅主螺旋闭合轮廓，可在 COMSOL 中选作域或边界线圈';
    t.cmEmptyTitle = 'COMSOL 仿真几何 — L%d（非活动层，无铜）';
    t.cmEmptySub = '该层不是活动线圈层，仿真 DXF 中不含铜轮廓';
    t.ctTitle = 'COMSOL 仿真几何 — 带端子变体总览';
    t.ctSub = '在主螺旋上追加 L1 的 PAD_A / PAD_B 圆盘与中心短边引线；仍不含过孔与钻孔';
    t.comsolNotes = { '闭合主螺旋轮廓，可在 COMSOL 中选作域或边界线圈，厚度取 0.012 mm。', ...
        '本图仅说明导出的仿真几何，不代表已通过 COMSOL 实际导入或求解验证。' };
    t.layerRoleName = struct('top', '顶层', 'bottom', '底层', 'inner1', '内层1', ...
        'inner2', '内层2', 'inner3', '内层3', 'inner4', '内层4');
else
    t.lgBoard = 'Board substrate';
    t.lgEdge = 'Board outline';
    t.lgSlot = 'Cut-outs: mounting ears and platform slots';
    t.lgLayer = 'L%d copper';
    t.lgPad = 'Terminal pads PAD_A / PAD_B (L1 only)';
    t.lgInactive = 'inactive coil layer: no copper';
    t.lgElec = 'Electrode pads (L1 only)';
    t.lgVia = sprintf('Through-vias %s', viaNames);
    t.lgSilk = 'Terminal leader lines';
    t.lgReference = 'Board and cut-out outlines (simulation reference)';
    t.lgTermPad = 'includes terminal pads';

    t.ovTitle = sprintf('%d-layer board / %d active coil layers (%d/%d) - JLC centerline overview', ...
        cfg.boardLayerCount, cfg.coilLayerCount, cfg.boardLayerCount, cfg.coilLayerCount);
    t.ovSub = sprintf(['Board d %.3f mm - coil inner d %.3f mm - pitch %.3f mm - ' ...
        'about %d turns per layer - active %s'], ...
        boardD, innerD, pitch, cfg.turnsPerCoilLayer, layerList);
    t.ovNotes = { sprintf('Series network: %s', seq), ...
        sprintf('Board/active layers %d/%d - board %.3f mm nominal - copper %.3f mm - profile %s', ...
            cfg.boardLayerCount, cfg.coilLayerCount, ...
            result.manufacturing.stackup.nominalFinishedThicknessMm, ...
            cfg.copperThickness, result.manufacturing.profile), ...
        sprintf(['Validation passed=%d; %d manufacturing checks pass, %d of them ' ...
            'near-limit warnings (see reports/).'], ...
            result.validation.passed, nCheck, nWarn), ...
        'DXF is engineering geometry, not Gerber; review stackup, material and electrical data before fabrication.', ...
        'Terminal labels are enlarged and reworded for this render; geometry comes from the same source.' };

    t.zoneTitle = 'Terminal connection zone';
    t.zoneSubCenterline = 'Centerline track: single tangent entry arc and the straight VOUT lead; spiral samples unchanged';
    t.zoneSubPhysical = 'Physical track: terminal leads and pads drawn at real width';
    t.zoneNotes = { sprintf('Series network: %s', seq), ...
        'Terminal routing uses one tangent arc fixed by the raw spiral endpoint; no second arc or micro-jog.' };

    t.layerTitle = 'L%d copper (%s)';
    t.layerInactiveTitle = 'L%d (%s) - inactive coil layer';
    t.layerInactiveSub = 'Not an active coil layer, so it carries no copper: only the board outline, cut-outs and through-vias appear here.';
    t.layerSub = 'Measured %.4f turns - signed circulation %+.1f deg%s';
    t.layerNotes = { sprintf('Active coil layers: %s', layerList), ...
        ['The signed circulation is measured from the generated polyline; one shared ' ...
         'sign across active layers means the fields add rather than cancel.'] };

    t.physTitle = sprintf('%d-layer board / %d active coil layers (%d/%d) - JLC physical copper overview', ...
        cfg.boardLayerCount, cfg.coilLayerCount, cfg.boardLayerCount, cfg.coilLayerCount);
    t.physSub = 'Drawn at real trace, pad and via sizes as a CAM reference (not Gerber)';
    t.physNotes = { sprintf('Series network: %s', seq), ...
        'Inactive layers carry no copper; the physical DXF drops non-functional pads on unconnected layers.', ...
        'DXF is engineering geometry, not Gerber; review stackup, material and electrical data before fabrication.' };

    t.cmTitle = 'COMSOL simulation geometry - closed copper contours';
    t.cmSub = 'Closed Archimedean spiral outlines only; no vias, drills, pads, terminals or layer transitions';
    t.cmLayerTitle = 'COMSOL simulation geometry - L%d closed contour';
    t.cmLayerSub = 'Closed main-spiral contour only; select as a domain or boundary coil in COMSOL';
    t.cmEmptyTitle = 'COMSOL simulation geometry - L%d (inactive layer, no copper)';
    t.cmEmptySub = 'This is not an active coil layer, so the simulation DXF holds no copper contour';
    t.ctTitle = 'COMSOL simulation geometry - with-terminals variant';
    t.ctSub = ['Adds the L1 PAD_A / PAD_B disks and center short-edge leads to the ' ...
        'main spiral; still no vias or drills'];
    t.comsolNotes = { 'Closed main-spiral contour; select it as a domain or boundary coil in COMSOL, thickness 0.012 mm.', ...
        'This figure documents the exported simulation geometry only; it does not claim a successful COMSOL import or solve.' };
    t.layerRoleName = struct('top', 'top', 'bottom', 'bottom', 'inner1', 'inner 1', ...
        'inner2', 'inner 2', 'inner3', 'inner 3', 'inner4', 'inner 4');
end
t.multiSenseZh = multi;
end

function s = senseSuffix(zh, multi)
if ~multi
    s = '';
elseif zh
    s = '，与其余活动层同向（磁场叠加）';
else
    s = ', same sense as the other active layers (fields add)';
end
end

function svg = renderAnnotated(srcPath, lang, plan)
[~, inner] = readSvgParts(srcPath);
b = svgContentBounds(inner);
pad = 1.15;
vx = b(1) - pad;
vy = b(2) - pad;
vw = (b(3) - b(1)) + 2 * pad;
vh = (b(4) - b(2)) + 2 * pad;
% 端子标注是否存在由源文件决定：总览与端子连接区都带 artifact 的 leader/label，
% 逐层图只有 L1 有。按内容判断可以避免"新增带标注的视图却忘了翻译"。
if ~isempty(terminalNames(inner))
    inner = rewriteTerminalLabels(inner, lang, [vx, vy, vw, vh]);
    % artifact 自带的半透明图例底板在为标注带预留的空间里会显得突兀，去掉它；
    % 标注图有自己的图例区。
    inner = regexprep(inner, '<rect class="terminal-legend-bg"[^>]*/>\s*', '');
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

titleLines = wrapText(plan.title, szTitle, usable);
subLines = wrapText(plan.subtitle, szSub, usable);
headH = 2.0 + numel(titleLines) * 2.0 * kk + 0.30 + numel(subLines) * 1.20 * kk + 1.0;

lg = legendLayout(plan.legend, szBody, kk, vx + m, usable, 0, font);
noteLines = {};
for q = 1:numel(plan.notes)
    noteLines = [noteLines, wrapText(plan.notes{q}, szBody, usable - 0.6 * kk)]; %#ok<AGROW>
end
footH = 1.5 * kk + lg.height + 0.55 * kk + 1.5 * kk + ...
    numel(noteLines) * linePitch + 1.2 * kk;

ny = vy - headH;
nh = headH + vh + footH;
out = cell(0, 1);
out{end + 1} = sprintf(['<svg xmlns="http://www.w3.org/2000/svg" ' ...
    'data-annotated-lang="%s" data-annotated-source="%s" ' ...
    'viewBox="%.6f %.6f %.6f %.6f" width="%d" height="%d">'], ...
    lang, xmlEscape(plan.rel), vx, ny, vw, nh, round(vw * 40), round(nh * 40));
out{end + 1} = sprintf(['<rect x="%.6f" y="%.6f" width="%.6f" height="%.6f" ' ...
    'fill="#ffffff"/>'], vx, ny, vw, nh);

y = ny + 2.0;
for q = 1:numel(titleLines)
    out{end + 1} = text(...
        sprintf('%.6f', vx + m), sprintf('%.6f', y), font, szTitle, ...
        '#111111', 'bold', titleLines{q}); %#ok<AGROW>
    y = y + 2.0 * kk;
end
y = y + 0.30;
for q = 1:numel(subLines)
    out{end + 1} = text(...
        sprintf('%.6f', vx + m), sprintf('%.6f', y), font, szSub, ...
        '#555555', '', subLines{q}); %#ok<AGROW>
    y = y + 1.20 * kk;
end
out{end + 1} = sprintf(['<line x1="%.6f" y1="%.6f" x2="%.6f" y2="%.6f" ' ...
    'stroke="#cccccc" stroke-width="0.06"/>'], ...
    vx + m, vy - 0.45 * kk, vx + vw - m, vy - 0.45 * kk);

% 绘制内容保持原始坐标：不得再叠加 translate，否则会与页脚重叠。clipPath 只覆盖
% 绘图区，因此端子引线伸到框外的部分不会在标题带里留下悬空短线。
clipId = sprintf('clip%s%s', lang, regexprep(plan.rel, '\W', ''));
out{end + 1} = sprintf(['<defs><clipPath id="%s"><rect x="%.6f" y="%.6f" ' ...
    'width="%.6f" height="%.6f"/></clipPath></defs>'], clipId, vx, vy, vw, vh);
out{end + 1} = sprintf('<g clip-path="url(#%s)">', clipId);
out{end + 1} = inner;
out{end + 1} = '</g>';

fy = vy + vh + 1.3 * kk;
out{end + 1} = text(sprintf('%.6f', vx + m), sprintf('%.6f', fy), font, szHead, ...
    '#111111', 'bold', headingText(lang, 'legend'));
lg = legendLayout(plan.legend, szBody, kk, vx + m, usable, fy + 0.55 * kk, font);
out = [out, lg.ops];
nyy = fy + 0.55 * kk + lg.height + 0.55 * kk;
out{end + 1} = text(sprintf('%.6f', vx + m), sprintf('%.6f', nyy), font, szHead, ...
    '#111111', 'bold', headingText(lang, 'notes'));
yy = nyy + 1.35 * kk;
for q = 1:numel(noteLines)
    out{end + 1} = text(...
        sprintf('%.6f', vx + m + 0.3 * kk), sprintf('%.6f', yy), font, szBody, ...
        '#444444', '', noteLines{q}); %#ok<AGROW>
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

function lg = legendLayout(items, szBody, kk, x0, width, y0, font)
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
for k = 1:numel(items)
    lines = wrapText(items(k).label, szBody, txtW);
    cells{end + 1} = struct('color', items(k).color, 'lines', {lines}); %#ok<AGROW>
    if numel(cells) == cols
        [ops, y] = emitRow(ops, cells, x0, colW, y, sw, sh, gap, linePitch, szBody, kk, font);
        cells = {};
    end
end
if ~isempty(cells)
    [ops, y] = emitRow(ops, cells, x0, colW, y, sw, sh, gap, linePitch, szBody, kk, font);
end
lg = struct('ops', {ops}, 'height', y - y0);
end

function [ops, y] = emitRow(ops, cells, x0, colW, y, sw, sh, gap, linePitch, szBody, kk, font)
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
% MATLAB 的 regexp 在此不能用 \b 词边界（会匹配失败），改用非贪婪 [^>]*? 限定标签头。
txt = fileread(path);
tok = regexp(txt, '(?s)<svg[^>]*?viewBox="([^"]+)"[^>]*>(.*)</svg>', 'tokens', 'once');
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
% 保留 data-* 机器可读属性与引线设计，只把显示文字与锚点搬到裁剪后的框内左上角并
% 放大字号，避免端子标注与图面脱节或不可读。
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
toks = regexp(inner, '<text class="terminal-label"[^>]*data-name="([^"]+)"', 'tokens');
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
% 中文行末句号若被折到下一行会孤立成"。"，读起来像排版错误；并回上一行。
lines = pullTrailingPunctuation(lines);
end

function lines = pullTrailingPunctuation(lines)
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

function auditAll(previewRoot, cfg)
% 回读校验：镜像完整性、语言元数据、文字不越界、正文不重叠、图例颜色真实。
rels = contractPreviewList(previewRoot);
langs = {'zh', 'en'};
for k = 1:numel(langs)
    for q = 1:numel(rels)
        p = fullfile(previewRoot, langs{k}, strrep(rels{q}, '/', filesep));
        if ~isfile(p)
            error('CircularFPC:ExportReadbackFailed', ...
                'Missing annotated mirror of %s (%s).', rels{q}, langs{k});
        end
        txt = fileread(p);
        xmlread(p);
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
% 镜像不应有契约组之外的多余文件。
extra = dir(fullfile(previewRoot, 'zh', '**', '*.svg'));
if numel(extra) ~= numel(rels)
    error('CircularFPC:ExportReadbackFailed', ...
        'zh mirror holds %d figures but the contract set has %d.', ...
        numel(extra), numel(rels));
end
end

function checkNoOverflow(inner, vb, path)
x0 = vb(1);
x1 = vb(1) + vb(3);
toks = regexp(inner, '<text\b([^>]*)>([^<]*)</text>', 'tokens');
for k = 1:numel(toks)
    attrs = toks{k}{1};
    body = decode(toks{k}{2});
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
toks = regexp(inner, '<text\b([^>]*)>([^<]*)</text>', 'tokens');
boxes = zeros(0, 6);
for k = 1:numel(toks)
    attrs = toks{k}{1};
    body = decode(toks{k}{2});
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

function checkLegendColors(fullTxt, inner, path, previewRoot)
% 图例色块必须是被标注源 SVG 里真实出现过的颜色，否则图例在撒谎。
src = regexp(fullTxt, 'data-annotated-source="([^"]+)"', 'tokens', 'once');
if isempty(src)
    error('CircularFPC:ExportReadbackFailed', ...
        'Annotated preview lacks its source reference: %s', path);
end
srcPath = fullfile(previewRoot, strrep(src{1}, '/', filesep));
if ~isfile(srcPath)
    error('CircularFPC:ExportReadbackFailed', ...
        'Annotated preview cites a missing source: %s', srcPath);
end
srcTxt = fileread(srcPath);
srcColors = string(lower([ ...
    flattenTokens(regexp(srcTxt, 'fill="(#[0-9a-fA-F]{6})"', 'tokens')), ...
    flattenTokens(regexp(srcTxt, 'stroke="(#[0-9a-fA-F]{6})"', 'tokens')) ]));
swatch = flattenTokens(regexp(inner, ['<rect x="[^"]*" y="[^"]*" width="[^"]*" ' ...
    'height="[^"]*" fill="(#[0-9a-fA-F]{6})" stroke="#333333"'], 'tokens'));
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
out = {};
for k = 1:numel(tok)
    out{end + 1} = tok{k}{1}; %#ok<AGROW>
end
end

function s = decode(s)
s = strrep(strrep(strrep(s, '&amp;', '&'), '&lt;', '<'), '&gt;', '>');
end
