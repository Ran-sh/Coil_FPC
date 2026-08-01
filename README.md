# Coil_FPC

用于生成两层或四层柔性 PCB（FPC）平面线圈的 MATLAB 工具。程序根据集中配置生成圆角矩形螺旋、焊盘与层间过孔坐标，并在验证通过后输出可导入 EDA 的 DXF、CSV、报告和预览图。

## 主要功能

- 支持 2 层和 4 层串联线圈。
- 线宽、线距、板框、尾部、焊盘及过孔参数集中配置。
- 自动生成圆角矩形螺旋和与路径相切的逃逸圆弧。
- 四层设计中，V23 位于右侧中部并向尾部引出；V12、V34 向中心空白区引出。
- 分别计算宽度理论最大匝数和全部几何检查最大匝数。
- 检查铜线角度、自相交、线距、层间连接、焊盘、过孔、板框及 DXF 完整性。
- 验证全部通过后才替换正式输出目录，失败时保留上一次成功结果。

## 环境

- MATLAB
- 已在 MATLAB R2026a 上完成实际运行和回归测试
- 不依赖第三方 MATLAB 工具箱

## 快速开始

将 MATLAB 当前目录切换到仓库根目录，然后运行：

```matlab
result = fpc_coil_main();
```

默认配置为四层、每层 6 匝。生成成功后，`result.passed` 为 `true`，文件写入：

```text
fpc_coil_output/fpc_coil_4layer/
```

## 切换两层或四层

编辑 `fpc_coil_main.m`：

```matlab
cfg.layerCount = 2;  % 两层
cfg.layerCount = 4;  % 四层
```

当 `cfg.useRecommendedTurns = true` 时，程序使用以下默认值：

| 层数 | 默认匝数 |
| ---: | ---: |
| 2 | 10 匝/层 |
| 4 | 6 匝/层 |

如需手动指定匝数：

```matlab
cfg.useRecommendedTurns = false;
cfg.turnsPerLayer = 8;
```

## 关键参数

所有用户参数均位于 `fpc_coil_main.m`。

| 参数 | 默认值 | 说明 |
| --- | ---: | --- |
| `traceWidth` | 0.20 mm | 铜线宽度 |
| `traceSpacing` | 0.15 mm | 目标净线距 |
| `pitchMargin` | 0.005 mm | 几何附加节距 |
| `edgeClearance` | 0.50 mm | 铜线到主体板边距离 |
| `viaLandingLeadLength` | 0.80 mm | V12/V34 内圈逃逸长度 |
| `viaInnerBendRadius` | 0.50 mm | V12/V34 逃逸圆弧半径 |
| `viaOuterLandingLeadLength` | 1.00 mm | V23 向右引出长度 |
| `viaOuterBendRadius` | 0.30 mm | V23 逃逸圆弧半径 |
| `viaToPadClearance` | 0.20 mm | 过孔焊盘到外接焊盘净距 |
| `viaClearanceSeverity` | `warning` | 非连接铜层间距不足时的处理方式 |

实际生成节距为：

```text
traceWidth + traceSpacing + pitchMargin
```

默认值对应 `0.355 mm`。

## 默认几何结果

默认四层 6 匝配置经 MATLAB 实际运行验证：

```text
V12 ≈ (-36.295037, -1.136177) mm
V23 =  ( 40.400000,  0.000000) mm
V34 ≈ (-36.295037,  1.139741) mm
```

当前默认配置的验证结果：

| 项目 | 两层默认配置 | 四层默认配置 |
| --- | ---: | ---: |
| 当前匝数 | 10 | 6 |
| 宽度理论最大匝数 | 11 | 11 |
| 全部几何检查最大匝数 | 11 | 9 |
| 最小铜线角 | 约 166.813° | 约 166.816° |
| 最小铜线净距 | 约 0.151 mm | 约 0.151 mm |
| 层间连接误差 | 0 mm | 0 mm |
| 逃逸圆弧 | PASS | PASS |

四层设计建议使用 6–9 匝/层。虽然宽度公式允许 11 匝，但 10–11 匝无法通过当前全部几何检查。

## 输出结构

运行后自动生成：

```text
fpc_coil_output/
├─ fpc_coil_2layer/ 或 fpc_coil_4layer/
│  ├─ dxf/                         # 各铜层及板框 DXF
│  ├─ reports/
│  │  ├─ 01_pad_via_coordinates.csv
│  │  ├─ 02_design_summary.txt
│  │  └─ 03_validation_report.txt
│  ├─ previews/
│  │  ├─ 01_preview_full.png
│  │  └─ 02_preview_right_tab.png
│  └─ generation_status.txt
```

输出目录属于可再生成文件，因此不纳入 Git 版本控制。

## 验证逻辑

程序在写出正式结果前检查：

1. 配置字段、数值范围和板框尺寸。
2. NaN、Inf、重复点及零长度线段。
3. 板框和铜线最小角度。
4. 板框及各铜层自相交。
5. 同层非相邻铜线的实际最小线距。
6. 修改后最终路径的层间连接误差。
7. 焊盘和过孔是否位于板框内部，以及相关净距。
8. 过孔连接层与非连接层铜线间距。
9. DXF 写出后的实体、顶点和闭合标志回读。

当过孔与非连接铜层间距不足时，`viaClearanceSeverity = 'warning'` 会输出警告并继续；设为 `'error'` 时停止生成。当前默认 V23 右侧引出方案通常能够通过该项检查。

## 运行测试

```matlab
results = runtests('test_fpc_coil_regressions.m');
assertSuccess(results);
```

当前回归测试覆盖独立过孔间距参数、内圈圆角参数、最终路径连接检查、板内判断、匝数上限报告和修剪圆角实现。

## EDA 导入

- 单位：毫米，DXF 中 `$INSUNITS = 4`。
- 缩放比例：1:1。
- 铜线导入线宽应设置为 `0.20 mm`，或与配置中的 `traceWidth` 保持一致。
- 底层 DXF 已按统一观察方向生成，无需手动镜像。
- CSV 仅提供焊盘和过孔坐标；真实焊盘、钻孔、覆盖膜及反焊盘需要在 EDA 中建立。
- 四层过孔结构和生产工艺必须与 PCB 制造商确认。

## 文件说明

```text
fpc_coil_main.m             用户入口与集中配置
fpc_coil_generate.m         几何生成、验证和文件输出核心
test_fpc_coil_regressions.m MATLAB 回归测试
README.md                   项目说明
```
