# Circular_FPC_Coil

MATLAB 圆形多层 FPC 螺旋线圈生成器，支持 `2/1`、`2/2`、`4/1`、`4/2`、`4/4` 五种“板层数/活动线圈层数”组合。

## 使用

```matlab
cd('Circular_FPC_Coil');

result = circular_fpc_main();

result = circular_fpc_main(struct( ...
    'boardLayerCount', 4, ...
    'coilLayerCount', 4, ...
    'turnsPerCoilLayer', 8, ...
    'terminalLeadSpacing', 2.0, ...
    'terminalLeadLength', 1.5, ...
    'connectionAngleDeg', 135));
```

公共入口：`circular_fpc_default_config(overrides)`、`circular_fpc_main(overrides)`。
几何分析、端子重布线、DRC、制造规则和导出实现均位于 `private/`，不作为外部接口。
全部五种组合可运行 `examples/generate_all_variants.m`。

`terminalLeadSpacing` 控制 PAD_A/PAD_B 两条平行引出线的中心距 d；
`terminalLeadLength` 控制直线引出长度 L。自动模式采用 L1 → PAD_A 单圆弧、
最后活动层 → VOUT 单圆弧、VOUT → PAD_B 纯直线结构，并随
`connectionAngleDeg` 整体旋转。旧 `padPairSpacing` 仅保留配置兼容，不主导几何。

中央平台保持正向 13×14 mm 矩形。默认 `coilInnerDiameter=20.21` mm，确保平台
半对角线、`platformSlotMargin` 和铜到槽净距均位于圆环内径约束内；更小内径会
明确报 `CircularFPC:GeometryInfeasible`，不会生成额外角桥或八槽板框。

手动端子模式使用 `terminalPlacementMode='manual'`，并读取 `manualPadAXY`、
`manualPadBXY`、`manualSeriesViaXY`；d/L 不覆盖手动坐标。`geometryScale` 仅缩放
宏观板框/平台/内径，制造线宽、线距、焊盘和过孔规则保持实际毫米值。

## 输出

默认根目录为 `circular_fpc_output/`。`designName='auto'` 时使用：

```text
Circular_FPC_<板层>L_<线圈层>C_yyyyMMdd_HHmm/
```

显式指定名称时不追加时间戳，且不覆盖已有目录。输出包括板框、各层铜线 DXF、
physical DXF、SVG 预览、PAD_A/PAD_B/VOUT 坐标、验证报告、设计摘要和清单；
`reports/07_fabrication_notes.txt` 会明确记录当前未生成 Gerber，physical DXF 不能替代 Gerber。

## 测试

```matlab
addpath('tests');
run_all_verification();
```

DXF 是工程几何，不是完整生产文件；制造前请复核叠层、材料和电气参数。
