# Coil_FPC

MATLAB 多层 FPC 线圈生成器，输出毫米制 1:1 DXF、SVG 预览和制造检查报告。

| 线圈 | 支持层数 | 主入口 |
| --- | --- | --- |
| [圆形](Circular_FPC_Coil/README.md) | 2 / 4 层板 | `circular_fpc_main` |
| [圆角矩形](Rectangular_FPC_Coil/README.md) | 2 / 4 / 6 / 8 层板 | `rectangular_fpc_main` |

## 快速上手

在 MATLAB 中进入仓库目录，然后运行：

```matlab
% 默认圆形 4 层线圈
cd('Circular_FPC_Coil');
result = circular_fpc_main();
```

常用自定义示例：

```matlab
result = circular_fpc_main(struct( ...
    'boardLayerCount', 4, ...
    'coilLayerCount', 4, ...
    'turnsPerCoilLayer', 8, ...
    'terminalLeadSpacing', 2.0, ...
    'terminalLeadLength', 1.5));
```

只分析、不写输出：

```matlab
result = circular_fpc_main(struct('analysisOnly', true));
```

生成矩形线圈：

```matlab
cd('../Rectangular_FPC_Coil');
result = rectangular_fpc_main();
```

## 验证

在对应子项目目录运行：

```matlab
addpath('tests');
run_all_verification();
```

DXF 是工程参考几何，不是 Gerber；投产前仍需复核叠层、材料与电气参数。
