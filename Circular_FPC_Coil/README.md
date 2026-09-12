# Circular_FPC_Coil

MATLAB 圆形多层 FPC 螺旋线圈生成器，支持 `2/1`、`2/2`、`4/1`、`4/2`、`4/4`、`6/6` 六种“板层数/活动线圈层数”组合。

## 使用

```matlab
cd('Circular_FPC_Coil');

result = circular_fpc_main();

result = circular_fpc_main(struct( ...
    'boardLayerCount', 4, ...
    'coilLayerCount', 4, ...
    'turnsPerCoilLayer', 7, ...
    'geometryScale', 1.0, ...
    'terminalLeadSpacing', 2.0, ...
    'terminalLeadLength', 1.5, ...
    'connectionAngleDeg', 135));
```

公共入口：`circular_fpc_default_config(overrides)`、`circular_fpc_main(overrides)`。
全部六种组合可运行 `examples/generate_all_variants.m`。

当前圆形默认工艺按嘉立创 4 层 FPC `FPC0420TT-121A` 配置：成品厚度标称
0.20 mm，内外层均为 1/3 oz（0.012 mm）电解铜，黄色覆盖膜为 PI 12.5 μm
+ 胶 15 μm。导出目录中的 `reports/09_comsol_stackup.csv` 提供顶层到末层的
层厚度、Z 坐标和材料标识，适用于 COMSOL 三维建模；各活动线圈层的实际
几何应导入对应的 `*_copper_solid_L*.dxf`，这些文件仅服务于仿真：只保留主螺旋，
将 0.2 mm 走线写成带直短边封口的闭合轮廓，不含端子弧线、层间连接弧线、
焊盘或过孔位置。可在 COMSOL 中选择二维域后作为边界线圈使用，厚度设为
0.012 mm。`*_copper_physical_L*.dxf` 仍保留原有嘉立创/CAM 参考用途，不受仿真
文件优化影响。

## COMSOL 带端子变体

除主螺旋版本外，每层另输出一份 `*_copper_solid_with_terminals_L*.dxf`。它是在
`*_copper_solid_L*.dxf` 基础上**追加**的仿真变体：主螺旋闭合轮廓逐点不变，L1 额外
加入中心区域的 PAD_A、PAD_B 圆盘和两条中心短边引线；引线写成闭合铜条（线宽
等于 `traceWidth`），两端各用一条垂直于走线的**直短边**封口，不使用圆头端弧。
所有层都不输出过孔、钻孔、过孔焊环或层间转换几何：变体的 `ENTITIES` 段只有闭合
轮廓（和 L1 的两个焊盘圆），因此不存在 VIA/DRILL 图元，也没有 LWPOLYLINE group 43。
其它层与其它区域保持原样：4/2 的 L2/L3 仍为空，L4 仍是原主螺旋。

选择建议：需要在线圈上直接加激励而自己在模型里画端子时用 `*_copper_solid_L*.dxf`；
希望端子（焊盘位置与引线走向）随 DXF 一起导入时用带端子版本。两者都只是几何，
不是 Gerber，也不替代制造文件。

配套产物：

- `preview/COMSOL/with_terminals/`：带端子变体的全板与每层 SVG 预览；
- `reports/10_*` 之外的 `reports/11_comsol_terminal_geometry.csv`：每个 DXF 实体的
  几何映射（实体名、类型、层、来源 route 节点、闭合标志、顶点数、面积、封口方式、
  首尾坐标），用于核对引线闭合与焊盘尺寸；
- `reports/08_file_manifest.csv` 中该文件角色为 `copper_solid_with_terminals`；
- 导出后立即做原子回读校验：实体数量、闭合标志、首尾坐标一致、引线宽度、焊盘
  直径与 `result.pads` 一致、无 VIA/DRILL、无 group 43。

`turnsPerCoilLayer` 是每层物理匝数（完整 360° 圈数），默认 7，最少 2；4/4 模式下
L2 多绕 0.25 圈、L4 少绕 0.25 圈，6/6 模式下 L2/L4/L6 分别多绕
0.25/0.50/0.25 圈，用于把层间过孔落在约 135°/225°/45°；改变匝数后板框主体圆会自动随最大跨度重算。
默认 4/4 下四层实测为 7 / 7.25 / 7 / 6.75 圈，平均恰为 `turnsPerCoilLayer`。

奇数活动层从内向外绕制、偶数层从外向内绕制，但四层的**电流环绕方向一致**，
使各层磁场在板法向上同向叠加而非相消。该性质由 `validate_result` 的
`windingSuperpositionConsistent` 独立测量（对生成的线圈折线求有向环绕角
`Σ (x·dy − y·dx)/r²`，不读取 `windingDirection` 标签），四层环绕角必须同号且
幅值大于半圈；`minSignedCirculationDeg` 给出幅值最小那层的带符号环绕角，
一并写入 `reports/05_validation_report.txt` 供核对。任一层被反向都会使校验失败、
拒绝导出。

`terminalLeadSpacing` 和 `terminalLeadLength` 分别控制平行端子引线的中心距和直线长度；
自动端子使用由原始阿基米德螺旋端点切线确定的单一相切圆弧，不改变线圈点，
也不会通过第二圆弧或微折线补端点。
`connectionAngleDeg` 控制整体连接方向。手动模式可使用 `manualPadAXY`、
`manualPadBXY` 和 `manualSeriesViaXY`。

自动端子按 `PAD_A → 线圈串联网络 → VOUT → PAD_B` 排列。`geometryScale`
只缩放板框、中心平台、内径和桥宽等主体几何，线宽、间距、焊盘、过孔和
嘉立创制造净距保持实际毫米值。默认所有过孔均为相同的 0.55/0.31 mm 贯通过孔，
每层预览都以同样的深灰焊环显示；不生成 antipad/禁铜圈。物理铜 DXF 移除
非连接层的非功能焊盘，贯穿钻孔仍按 0.176 mm 钻孔到铜净距与板边规则检查。

板框主体圆按线圈最外铜边 + `edgeClearance` 自动定径，外侧局部结构不会把整圈
放大：活动线圈外端过孔在实际存在的层间位置生成小圆弧凸耳；6/6 的外端过孔
依次位于 135°、225°、45°。

0°、90°、180°、270°（360° 与 0° 为同一处）默认生成安装耳朵，由三段弧定义
（每个方向一处挖槽，不含独立圆孔，也不先伸出直边）：

- 内侧弧直接取主体外径圆上的一段圆弧，与该圆精确重合；主体外径随匝数变化时
  这段弧自动跟随，没有独立半径参数。
- 中间弧与内侧弧共享两个端点，在耳朵中央径向轴上向板外鼓起，与内侧弧共同围成
  闭合挖槽。两端点位于主体外径圆上并关于耳朵径向轴对称。
- 最外侧弧是中间弧的同心等距外偏弧（半径加 `mountingSlotEdgeClearance`），构成
  耳朵外边界；中间弧与最外侧弧之间保留板料。耳朵根部与主体圆横切相接，折角由
  板框统一的相切圆角规则平滑，不存在尖角或零宽连接。

三个参数：`mountingSlotSpan`（槽口两端点弦长，默认 4.0 mm；不是弧长）、
`mountingSlotRise`（耳朵中央径向轴上从主体外径圆到中间弧的外凸高度，默认
1.0 mm；基准是主体圆弧中央点而不是端点弦中点）、`mountingSlotEdgeClearance`
（中间弧到最外侧板框的板料宽度，默认 `NaN` = 沿用 `edgeClearance`）。
`mountingSlotEndFilletRadius`（默认 0.3 mm）给出挖槽两端的相切圆角。跨度超出主体圆
可容纳范围、外凸高度无效、板料不足或挖槽与铜/过孔碰撞时会明确报错，生成器不会
通过降低净距来出图。

旧参数 `mountingNotchDiameter`、`mountingLugLength`、`mountingNotchWall` 已弃用：
`mountingNotchDiameter` 曾同时表达槽宽、槽深与圆孔直径三种语义，无法唯一映射到
「槽口跨度 + 外凸高度」，因此显式报错 `CircularFPC:DeprecatedConfigField` 并指出
替代参数，不做静默映射。

315°（工程坐标右下角）另生成两个 L1 独立电极焊盘；它们由
`electrodeAngleDeg`、`electrodeArmLength`、`electrodeArmWidth`、`electrodeArmGap`、
`electrodePadDiameter` 调节，不进入线圈串联网络，也不自动生成电极走线。

## 输出

默认根目录为 `circular_fpc_output/`。`designName='auto'` 时使用：

```text
Circular_FPC_<板层>L_<线圈层>C__yyyyMMdd_HHmmss/
```

输出包括板框（1 个外边界、4 个平台槽、4 个耳朵挖槽）、各层中心线/物理铜/闭合实体铜 DXF、COMSOL 带端子仿真 DXF、端子坐标、独立电极坐标、验证报告、设计摘要和清单；
预览**统一命名**为 `01` 总览、`02` 端子连接区，逐层固定为 `1x_layer_Lx_<role>`
（`x` 就是物理层号，例如 L3 在任何层数下都是 `13`），因此文件名可以安全写进文档与
脚本：

```text
preview/
├── JLC/centerline/   01_overview.svg  02_connection_zone.svg  11..1N_layer_Lx_<role>.svg
├── JLC/physical/     同上（按实际线宽/焊盘/过孔绘制）
├── COMSOL/main/      由 *_copper_solid_L*.dxf 闭合铜实体生成
├── COMSOL/with_terminals/  由 *_copper_solid_with_terminals_L*.dxf 生成，含 L1 焊盘与中心引线
├── zh/               上述四组的**完整镜像**，同名文件、中文标注
└── en/               同上，英文标注
```

`zh/` 与 `en/` 是 `JLC/`、`COMSOL/` 的完整镜像：同一相对路径、同一文件名，只有
标注语言不同，因此规则只有"同名不同语言"一条，不需要记哪些图有标注版。两组结构
一致，各含上述两个 JLC 子目录与两个 COMSOL 子目录。

4 层工艺另输出 COMSOL 层压参考表 `reports/09_comsol_stackup.csv`；6/6 暂无已验证的
六层制造叠层，因此该表保留铜层厚度输入但 Z 坐标标为 `NaN`，摘要和制造检查会标记
`UNVERIFIED_LAYER_COUNT`，不能直接当作已确认的六层厂商叠层。
当前不生成 Gerber，physical DXF 不能替代 Gerber。

### 标注预览（`preview/zh/`、`preview/en/`）

标注图**不重新绘制几何**：每张都由上面已经写出的契约预览读回后封装（加标题带、
图例、说明），因此与它所说明的预览使用同一批图元，不可能画出与 DXF 不一致的图。
端子标注只搬动锚点、放大字号并转写文字，`data-name` 等机器可读属性原样保留。

图例**严格跟着该层实际画出的图元**：逐层预览只有 L1 画焊盘与独立电极，非活动层
没有铜箔，这些情况都不列对应色块；导出时会回读被标注源 SVG 的实际 fill/stroke 颜色
逐一核对，色块不在画面里就拒绝发布——这条校验在开发中确实拦下过"图例有、画面无"
的错误。

镜像文件属于**原子发布**并登记 manifest role（`preview_annotated`），契约组
`preview/JLC/`、`preview/COMSOL/` 的文件字节不变。导出时回读校验每个契约预览都有
zh、en 两份、文字不越出帧宽、正文互不重叠，排版失败会阻止发布。本组图片只说明
导出几何，不代表已通过 COMSOL 实际导入或求解验证。

## 测试

```matlab
addpath('tests');
run_all_verification();
```

安装耳朵的三段弧可用 `CircularFpc.Export.Ear_Zoom_Figure` 出局部放大图核对（标注内侧弧、中间弧、
最外侧弧、`mountingSlotSpan`、`mountingSlotRise`、`mountingSlotEdgeClearance`，
并标出共享端点 P± 与根部交点 J±）：

```matlab
CircularFpc.Export.Ear_Zoom_Figure('ear_zoom.png', 'ear_zoom.svg');
```

DXF 是工程几何，不是完整生产文件；制造前请复核叠层、材料和电气参数。
