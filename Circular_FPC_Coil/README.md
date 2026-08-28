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
全部五种组合可运行 `examples/generate_all_variants.m`。

`terminalLeadSpacing` 和 `terminalLeadLength` 分别控制平行端子引线的中心距和直线长度；
`connectionAngleDeg` 控制整体连接方向。手动模式可使用 `manualPadAXY`、
`manualPadBXY` 和 `manualSeriesViaXY`。

## 输出

默认根目录为 `circular_fpc_output/`。`designName='auto'` 时使用：

```text
Circular_FPC_<板层>L_<线圈层>C_yyyyMMdd_HHmm/
```

输出包括板框、各层中心线/物理铜 DXF、SVG 预览、端子坐标、验证报告、设计摘要和清单。
当前不生成 Gerber，physical DXF 不能替代 Gerber。

## 测试

```matlab
addpath('tests');
run_all_verification();
```

DXF 是工程几何，不是完整生产文件；制造前请复核叠层、材料和电气参数。
