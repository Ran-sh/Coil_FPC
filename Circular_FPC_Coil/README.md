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

## COMSOL 带引线变体

除主螺旋版本外，每层另输出一份 `*_copper_solid_with_terminals_L*.dxf`。**每个活动
线圈层恰好一条闭合轮廓**：本层主螺旋与该层的端子引线合并成一个连通体。合并是这份
文件对 COMSOL 2D 有用的前提——一个闭合环选中就是一个域；不合并时线圈与引线各是
独立实体、只能靠过孔在层间相连，而 2D 选域表达不了这种连接。

引线归到哪一层由电气拓扑决定，不是写死的：

- 入口引线（PAD_A 侧）跟着它接触的那个线圈端走；
- 回流引线（PAD_B 侧）跟着路线中最后一个层间过孔的**起点层**走（电流从该层返回）。

4/2 下即 L1 = 主螺旋 + PAD_A 引线，L4 = 主螺旋 + VOUT 回流段 + PAD_B 引线。
回流引线若留在 L1，L1 会被切成两块只在过孔处相连的孤岛。合并后每层的铜都是一条
连通体，两层在 V14 与 VOUT 两处首尾相接。

**不导出 PAD_A/PAD_B 焊盘圆盘**：本变体只承载导体，端点如何终止交给求解器。引线写成
闭合铜条（线宽等于 `traceWidth`），末端用垂直于走线的直短边封口，不用圆头端弧。
所有层都不输出过孔、钻孔、过孔焊环或层间转换几何，也没有 LWPOLYLINE group 43。
4/2 的 L2/L3 仍为空。`*_copper_solid_L*.dxf` 保持原字节不变（合并后的轮廓不再与它
顶点相同，这是合并的必然代价）。

选择建议：需要在线圈上直接加激励、自己在模型里画端子时用 `*_copper_solid_L*.dxf`；
希望线圈与引线连成一体、每层一个域时用带引线版本。两者都只是几何，不是 Gerber，
也不替代制造文件。

配套产物：

- `preview/COMSOL/2_coil_with_lead/`：带引线变体的全板与每层 SVG 预览；
- `reports/11_comsol_terminal_geometry.csv`：每个活动层一行的几何映射（实体名、
  类型、层、来源 route 节点、闭合标志、顶点数、面积、封口方式、首尾坐标），
  用于核对合并轮廓闭合且面积大于纯螺旋；
- `reports/08_file_manifest.csv` 中该文件角色为 `copper_solid_with_terminals`；
- 导出后立即做原子回读校验：每层恰好一条闭合轮廓、顶点与规范轮廓逐点一致、
  面积严格大于对应的 `copper_solid` 环（否则说明端子铜没并进去）、任何层都不得
  出现 CIRCLE、无 VIA/DRILL、无 group 43。

`turnsPerCoilLayer` 是每层物理匝数（完整 360° 圈数），默认 7，最少 2；4/4 模式下
L2 多绕 0.25 圈、L4 少绕 0.25 圈，6/6 模式下 L2/L4/L6 分别多绕
0.25/0.50/0.25 圈，用于把层间过孔落在约 135°/225°/45°；改变匝数后板框主体圆会自动随最大跨度重算。
默认 4/4 下四层实测为 7 / 7.25 / 7 / 6.75 圈，平均恰为 `turnsPerCoilLayer`。

`samplePointsPerTurn` 是每匝采样点数，默认 360、最少 8：更粗的折线无法表征
螺旋，且端子切向的旋向判定要求相邻采样点的极角差严格小于半圈。

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
外端过孔两侧的接触弧（奇数层螺旋→过孔、过孔→偶数层螺旋）都用单段切向圆弧，
两侧扫角必须落在 (90°, 150°]、弧半径不小于一个线宽；扫角与半径都会写入
过孔数据与验证报告，板径自动定径回路在不可行时继续增大过孔外延伸展区，
仍不可行则明确报错。
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

每次成功发布新产物后会自动整理输出根（`archivePreviousArtifacts`，默认开启）：
**按类型各自保留最新一份**——类型 = 设计名词干（`auto` 命名去掉 `__yyyyMMdd_HHmmss`
时间戳后的部分），只把与本次产物**同词干**的旧完整产物（含
`reports/08_file_manifest.csv` 的目录）移入 `archive/`，其他类型（如 2L/1C 与
4L/1C）无论新旧都留在原处；`LATEST.txt` 指向最新发布的产物。归档目标重名时追加
`_2`、`_3`…… 后缀，绝不覆盖。非完整目录（临时目录等）保持原位；单个目录移动失败
只告警、不回滚已发布的新产物。要并排保留同一类型的多份产物（如
`examples/generate_all_variants.m` 批量生成六种层叠），把该开关设为 `false`。

输出包括板框（1 个外边界、4 个平台槽、4 个耳朵挖槽）、各层中心线/物理铜/闭合实体铜 DXF、COMSOL 带端子仿真 DXF、端子坐标、独立电极坐标、验证报告、设计摘要和清单；
预览**统一命名**为 `01` 总览、`02` 端子连接区，逐层固定为 `1x_layer_Lx_<role>`
（`x` 就是物理层号，例如 L3 在任何层数下都是 `13`），因此文件名可以安全写进文档与
脚本：

```text
preview/
├── JLC/1_path_only/     01_overview.svg  02_connection_zone.svg  11..1N_layer_Lx_<role>.svg
│                        只画走线路径（细线，不按线宽），无焊盘无过孔
├── JLC/2_trace_only/    同上，按实际线宽画铜线，仍无焊盘无过孔
├── JLC/3_trace_pad_via/ 同上，再加焊盘、独立电极与过孔（CAM 参考）
├── COMSOL/1_coil_only/      由 *_copper_solid_L*.dxf 闭合铜实体生成
├── COMSOL/2_coil_with_lead/ 由 *_copper_solid_with_terminals_L*.dxf 生成，每层一条合并轮廓
├── zh/               上述五组的**完整镜像**，同名文件、中文标注
└── en/               同上，英文标注
```

`zh/` 与 `en/` 是 `JLC/`、`COMSOL/` 的完整镜像：同一相对路径、同一文件名，只有
标注语言不同，因此规则只有"同名不同语言"一条，不需要记哪些图有标注版。数字前缀
固定排序，JLC 三档是"路径 → 线宽 → 线宽+焊盘+过孔"递进，看名字就知道该翻哪张。

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
