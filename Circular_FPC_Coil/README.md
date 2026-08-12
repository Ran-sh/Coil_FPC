# Circular_FPC_Coil 圆环柔性线圈生成器

本项目用 MATLAB 基础功能生成圆环螺旋 FPC 线圈的板框、铜层、连接区预览与验证报告，支持 2 层/4 层板的五种活动层组合。

## 快速开始（MATLAB R2026a）

1. 将项目根目录加入 MATLAB 路径（或先运行示例脚本，脚本会自动 `addpath`）：

   ```matlab
   addpath('D:/A_Bone_healing/bone_healing_simulink/Coil/Circular_FPC_Coil');
   ```

2. 单版本生成（默认 2 层 1 线圈，输出到 `outputRoot/designName`）：

   ```matlab
   cfg = circular_fpc_default_config(struct('outputRoot', 'D:/tmp/fpc_out', 'designName', 'my_coil'));
   result = circular_fpc_main(cfg);
   ```

   也可以直接用 overrides 结构体调用：

   ```matlab
   result = circular_fpc_main(struct('outputRoot', 'D:/tmp/fpc_out', 'designName', 'my_coil'));
   ```

   生成完成后（默认 `enableFigure=true`）会在 MATLAB 桌面弹出图像窗口：左上为全部层叠放总览，其余为每物理层单独视图（板框、线圈、连接路径、焊盘与过孔）。可在窗口内通过 File > Save As 另存为 PNG/SVG/PDF 等格式；无头环境（如 `-batch`）自动跳过弹窗，之后仍可手动调用 `circular_fpc_plot(result)`。

3. 一键生成全部五种层叠（2/1、2/2、4/1、4/2、4/4）：

   ```matlab
   run('D:/A_Bone_healing/bone_healing_simulink/Coil/Circular_FPC_Coil/examples/generate_all_variants.m');
   ```

   脚本默认输出到项目根目录下的 `outputs/`；若你的工作区已存在非空变量 `outputRoot`，脚本会使用该路径。正式输出目录已存在时生成会报错且不会覆盖。

## 默认参数

| 参数 | 默认值 | 含义 |
|---|---|---|
| boardLayerCount / coilLayerCount | 2 / 1 | 板层数 / 活动线圈层数 |
| boardOuterDiameter | 25.0 mm | 板外径 |
| coilInnerDiameter | 18.63 mm | 线圈内径 |
| centerPlatformWidth / Height | 13.0 / 11.0 mm | 中央连接平台尺寸 |
| bridgeTargetWidth | 1.5 mm | 连接桥目标宽度 |
| geometryScale | 1.0 | 宏观几何缩放 |
| turnsPerCoilLayer | 8 | 每活动层匝数 |
| traceWidth | 0.20 mm | 铜线宽 |
| traceSpacing | 0.15 mm | 铜间净距 |
| pitchMargin | 0.005 mm | 节距余量 |
| edgeClearance | 0.50 mm | 铜到板边/槽净距 |
| connectionAngleDeg | 135.0 度 | 连接位置角度 |
| padDiameter | 1.2 mm | 外接焊盘直径 |
| viaPadDiameter / viaDrillDiameter | 0.8 / 0.3 mm | 过孔焊环/钻孔直径 |
| antipadDiameter | 1.2 mm | 非连接层反焊盘直径 |
| terminalClearance | 0.25 mm | 端子间最小净距 |
| copperThickness | 0.035 mm | 铜厚（仅用于直流估算） |
| copperResistivity | 1.724e-8 Ohm·m | 铜电阻率（仅用于直流估算） |
| samplePointsPerTurn | 360 | 每匝采样点数 |
| turnScanMax | 16 | 匝数扫描上限 |
| enablePreview | true | 是否生成 SVG 预览 |
| enableFigure | true | 运行完成后是否在 MATLAB 弹出图像窗口 |

除上表外，还支持 `terminalPlacementMode`（auto/manual）、`manualPadAXY`、`manualPadBXY`、`manualSeriesViaXY`、`outputRoot`、`designName` 等字段。

## geometryScale 语义

`geometryScale` 只缩放宏观几何：boardOuterDiameter、coilInnerDiameter、centerPlatformWidth/Height、bridgeTargetWidth，以及槽与桥臂等宏观结构。以下制造参数**不随缩放改变**：traceWidth、traceSpacing、pitchMargin、edgeClearance、padDiameter、viaPadDiameter、viaDrillDiameter、antipadDiameter。非法尺寸会明确报错，不会静默改匝数、线距或位置。

## 层映射与绕向

| 组合 | 活动线圈层 | 说明 |
|---|---|---|
| 2/1 | L1 | 单线圈，L2 作为必要回流层（非活动线圈层） |
| 2/2 | L1, L2 | 两活动层 |
| 4/1 | L1 | 单线圈，L4 作为必要回流层（非活动线圈层） |
| 4/2 | L1, L4 | 两活动层 |
| 4/4 | L1, L2, L3, L4 | 四活动层 |

- 奇数序号活动线圈按 CCW（逆时针）由内向外绕；偶数序号按 CW（顺时针）由外向内绕。
- 2/1 与 4/1 因 PAD_A/PAD_B 仅位于 L1，单线圈的外端经 VRET 到最高物理层（L2 或 L4），在该层用 RETURN 铜线回到中央 VOUT，再经 VOUT 回 L1 接 PAD_B。该回流层**不是额外线圈**，其 `isActiveCoilLayer=false`。

## 焊盘、过孔与反焊盘

- PAD_A / PAD_B 仅位于 L1，`removable=true`，是唯一可删除的外接焊盘。
- 串联过孔：多线圈组合为 V12/V23/V34 与 VOUT；单线圈组合为 VRET 与 VOUT。过孔按层间转移角色区分：`OUTER_TRANSITION`（外端过渡）、`INNER_TRANSITION`（内端过渡）、`RETURN_OUTER`（回流外端）、`OUTPUT_RETURN`（输出回流）。
- 在 4 层输出中，每个过孔的非连接物理层 DXF 会写入 `ANTIPAD_Ln` 层圆与 `ANTIPAD_<viaName>` 文本；连接层保留过孔铜环。
- 手动坐标 `manualSeriesViaXY` 的行序必须与过孔顺序一致：2/1 与 4/1 为 `[VRET; VOUT]`；2/2 为 `[V12; VOUT]`；4/2 为 `[V14; VOUT]`；4/4 为 `[V12; V23; V34; VOUT]`。手动模式下行数不符会报 `CircularFPC:TerminalPlacementInvalid`。

### 端子布局元数据与 CSV/SVG 输出

- `padPairSpacing=2.0`（单位 mm）是 PAD_A/PAD_B 沿连接角切向并排的中心距，不随 `geometryScale` 缩放；PAD_A 与 PAD_B 位于中央平台靠近入口桥一侧。
- 入口桥采用双通道：进线通道（PAD_A → 线圈内端）与出线通道（VOUT → PAD_B）沿焊盘对切向并排布置，通道半距为 `(traceWidth + traceSpacing) / 2`。
- 每个端子在 `result` 中带有 `placementRegion` 与 `bridgeAngleDeg`：自动模式下 PAD_A/PAD_B 为 `CENTER_PLATFORM_NEAR_ENTRY_BRIDGE`（角度取 `connectionAngleDeg`，默认 135°）；`VOUT` 为 `ENTRY_BRIDGE`（135°）；`VRET`/`V12`/`V14`/`V34` 为 `OUTER_COIL_ENDPOINT`（V34 在回流桥侧，取 315°）；`V23` 为 `RETURN_BRIDGE`（315°）。手动模式全部为 `MANUAL`，`bridgeAngleDeg=NaN`。
- 五种层叠的过孔映射：2/1 与 4/1 为 `VRET`（回流外端）+ `VOUT`（输出回流）；2/2 为 `V12` + `VOUT`；4/2 为 `V14` + `VOUT`；4/4 为 `V12`、`V23`、`V34`、`VOUT`。
- `01_pad_via_coordinates.csv` 保留原有 11 列 `name,xMm,yMm,diameterMm,drillMm,antipadDiameterMm,layer,fromLayer,toLayer,removable,role`，末尾追加 `placementRegion`、`bridgeAngleDeg`（角度保留 6 位小数，`NaN` 输出字面量 `NaN`）。
- 预览中，每个焊盘/过孔圆后带有可见文本标签 `NAME [REGION] angle=...deg`，并写入 `data-name`、`data-placement-region`、`data-bridge-angle-deg` 属性（XML 特殊字符已转义）；`03_design_summary.txt` 同样记录 `connectionAngleDeg`、`padPairSpacing` 与逐端子区域/角度。每层单独预览（`03_preview_layer_L1_top.svg` 起）仅绘制该层铜与板框：L1 含焊盘，各层含与该层相连的过孔。

## 输出文件

每个设计在 `<outputRoot>/<designName>/` 下生成：

```text
dxf/
  00_board_outline.dxf                 板框（1 外边界 + 4 孔槽）
  L1/01_copper_L1.dxf ...             每物理层铜层 DXF
previews/
  01_preview_full.svg                  全板预览
  02_preview_connection_zone.svg       连接区预览
  03_preview_layer_L1_top.svg ...      每物理层单独预览（top/innerN/bottom）
reports/
  01_pad_via_coordinates.csv           焊盘/过孔坐标
  02_layer_map.csv                     层映射
  03_design_summary.txt                设计摘要
  04_turn_scan.csv                     匝数扫描
  05_validation_report.txt             验证报告
generation_status.txt                  生成状态
```

DXF 单位为毫米且 1:1。`result` 主要字段：`boardLayerCount`、`coilLayerCount`、`activeCoilLayers`、`effectiveDimensions`、`boardLoops`、`layerPaths`、`pads`、`vias`、`seriesSequence`、`seriesRoute`、`returnLayer`、`totalTraceLengthMm`、`estimatedDcResistanceOhm`、`validation`、`outputPath`。

## 错误与边界行为

- 不支持的板层/线圈层组合会报 `CircularFPC:UnsupportedLayerCombination`，不会静默压缩线距、减少匝数或移动中央平台。
- 几何不可行（如平台过大、缩放过小）会报 `CircularFPC:GeometryInfeasible`，且不留下正式输出目录。
- 正式输出目录已存在时报告 `CircularFPC:OutputExists`，不覆盖旧产物。

## 与论文几何的差异

本项目以用户提供的论文结构与官方补充材料为参考，但当前默认线宽/线距为 0.20 mm / 0.15 mm（另加 0.005 mm 节距余量），与论文中的 0.13 mm / 0.13 mm 不同；线圈内径 18.63 mm 也不等于论文中的 20 mm。本实现只复现结构思路，**不宣称复现论文的电气指标**。

- 论文正文：https://www.nature.com/articles/s41528-026-00577-x
- 官方补充材料：https://static-content.springer.com/esm/art%3A10.1038%2Fs41528-026-00577-x/MediaObjects/41528_2026_577_MOESM1_ESM.pdf

## 非目标与制造前复核

- 本项目不生成 KiCad、Gerber 或厂家叠层文件。
- 不声明电感、Q 值、4 MHz 工作频率、热性能或植入安全性能；`estimatedDcResistanceOhm` 仅为几何长度估算。
- 2 层/4 层输出目前只表达逻辑铜层与过孔连接；真实叠层（材料、盲埋孔能力、最终电气参数）需在制造前与厂商确认。
- 使用本生成结果进行制造或临床相关用途前，必须由具备资质的工程师复核几何、电气与安全要求。
