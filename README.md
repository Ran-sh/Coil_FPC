# Coil_FPC

MATLAB FPC 线圈生成工具集，可导出毫米制 1:1 DXF、CSV、TXT 和 SVG。

| 项目 | 形态 | 层数 | 入口 |
| --- | --- | --- | --- |
| [Circular_FPC_Coil](Circular_FPC_Coil/README.md) | 圆形螺旋 | 2 / 4 | `circular_fpc_main` |
| [Rectangular_FPC_Coil](Rectangular_FPC_Coil/README.md) | 圆角矩形螺旋 | 2 / 4 / 6 / 8 | `rectangular_fpc_main` |

## 快速开始

```matlab
cd('Circular_FPC_Coil');
circular = circular_fpc_main();

cd('../Rectangular_FPC_Coil');
rectangular = rectangular_fpc_main();
```

矩形项目支持 `analysisOnly=true`。其输出目录为
`rectangular_fpc_output/<designName>_yyyyMMdd_HHmm/`：同一分钟同名设计原子替换，跨分钟保留历史版本。

## 测试

在对应子项目中运行：

```matlab
addpath('tests');
run_all_verification();
```

DXF 是工程几何，不是完整生产文件；制造前请复核叠层、材料和电气参数。
