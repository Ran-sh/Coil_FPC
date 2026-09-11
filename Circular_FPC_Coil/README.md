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
预览按用途分为 `preview/JLC/centerline/`（`*_copper_L*.dxf` 中心线）、
`preview/JLC/physical/`（`*_copper_physical_L*.dxf` 实际线宽/焊盘/过孔）、
`preview/COMSOL/`（由 `*_copper_solid_L*.dxf` 闭合铜实体生成的预览）与
`preview/COMSOL/with_terminals/`（由 `*_copper_solid_with_terminals_L*.dxf` 生成，
含 L1 焊盘与中心引线）。
4 层工艺另输出 COMSOL 层压参考表 `reports/09_comsol_stackup.csv`；6/6 暂无已验证的
六层制造叠层，因此该表保留铜层厚度输入但 Z 坐标标为 `NaN`，摘要和制造检查会标记
`UNVERIFIED_LAYER_COUNT`，不能直接当作已确认的六层厂商叠层。
当前不生成 Gerber，physical DXF 不能替代 Gerber。

## 测试

```matlab
addpath('tests');
run_all_verification();
```

安装耳朵的三段弧可用 `ear_zoom_figure` 出局部放大图核对（标注内侧弧、中间弧、
最外侧弧、`mountingSlotSpan`、`mountingSlotRise`、`mountingSlotEdgeClearance`，
并标出共享端点 P± 与根部交点 J±）：

```matlab
ear_zoom_figure('ear_zoom.png', 'ear_zoom.svg');
```

DXF 是工程几何，不是完整生产文件；制造前请复核叠层、材料和电气参数。
