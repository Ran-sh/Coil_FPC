# Coil_FPC

MATLAB 多层 FPC 螺旋线圈生成器：一键生成毫米制 1:1 DXF、SVG 预览和制造检查报告。

| 模块 | 可生成层数 | 内置 JLC 规则检查覆盖 | 主入口 |
| --- | --- | --- | --- |
| [圆形 Circular_FPC_Coil](Circular_FPC_Coil/README.md) | 2 / 4 层板 | 2 / 4 层；不等同于板厂 DFM/正式制造资格 | `circular_fpc_main` |
| [圆角矩形 Rectangular_FPC_Coil](Rectangular_FPC_Coil/README.md) | 2 / 4 / 6 / 8 层板 | 2 / 4 层；6 / 8 层标记为 `UNVERIFIED_LAYER_COUNT`；不等同于板厂 DFM/正式制造资格 | `rectangular_fpc_main` |

## 快速上手

环境要求：MATLAB R2026a（与 CI 一致）。

```matlab
% 圆形线圈：默认 4 层板 / 4 线圈层
cd('Circular_FPC_Coil');
result = circular_fpc_main();

% 圆角矩形线圈：默认 4 层板 × 12 匝
cd('../Rectangular_FPC_Coil');
result = rectangular_fpc_main();
```

自定义参数（两个模块同一种写法，传入覆盖结构体）：

```matlab
result = circular_fpc_main(struct( ...
    'boardLayerCount', 4, ...          % 板层数
    'coilLayerCount', 4, ...           % 活动线圈层数
    'turnsPerCoilLayer', 7, ...        % 每层物理匝数（完整 360° 圈数）
    'terminalLeadSpacing', 2.0, ...    % 端子引线中心距 (mm)
    'terminalLeadLength', 1.5));       % 端子引线长度 (mm)

analysis = rectangular_fpc_main(struct('analysisOnly', true));  % 只分析、不写文件
```

## 输出

- 圆形：`Circular_FPC_Coil/circular_fpc_output/Circular_FPC_<板层>L_<线圈层>C_时间戳/`
- 矩形：`Rectangular_FPC_Coil/rectangular_fpc_output/<designName>_yyyyMMdd_HHmm/`

均包含板框与逐层 DXF、端子坐标、验证报告和文件清单；`enablePreview=true`
时额外生成 SVG 预览。

## 验证

在对应子项目目录运行：

```matlab
addpath('tests');
run_all_verification();
```

推送 / PR 时 GitHub Actions 会自动跑两套测试。

> DXF 是工程参考几何，不是 Gerber；投产前请复核叠层、材料与电气参数。
