# Coil_FPC — FPC 线圈生成工具集（MATLAB）

本仓库用 **MATLAB 基础功能**（无第三方工具箱、不依赖 Simulink）生成 FPC（柔性印刷电路）线圈的几何数据与制造文件，包含两套相互独立的生成器：

| 子项目 | 线圈形态 | 适用板层 | 默认几何 | 默认匝数 |
| --- | --- | --- | --- | --- |
| [Circular_FPC_Coil](Circular_FPC_Coil/README.md) | 圆环阿基米德螺旋 | 2 / 4 层，5 种活动层组合（2/1、2/2、4/1、4/2、4/4） | 板外径 φ25 mm | 8 匝/层 |
| [FPC_Coil](FPC_Coil/README.md) | 圆角矩形多层平面线圈 | 2~8 层（偶数） | 主体 80 × 12 mm | 12 匝/层（可自动推荐） |

两套工具共享相同的输出与验证哲学：

- 输出可直接导入 EDA 的 **DXF**（毫米、1:1）、焊盘/过孔坐标 **CSV**、设计摘要与验证报告 **TXT**、纯矢量 **SVG** 预览（`enableFigure=true` 时还会在 MATLAB 桌面弹出图像窗口）；
- 所有几何在输出前经过**自动验证**（坐标有限性、自交、线距/净距、连接连续性、焊盘/过孔间距、DXF 回读等），验证不通过时不产生正式输出；
- 输出目录已存在时不覆盖（原子导出）。

> 仓库 GitHub 地址：<https://github.com/Ran-sh/Coil_FPC>

## 目录结构

```text
Coil/
├── Circular_FPC_Coil/        圆环柔性线圈生成器
│   ├── circular_fpc_main.m            公共入口
│   ├── circular_fpc_default_config.m  公共配置入口（每参数带中文注释）
│   ├── private/                       几何/验证/导出/绘图内部实现
│   ├── examples/                      一键生成全部五种层叠
│   └── tests/                         回归测试（13 项）
├── FPC_Coil/                 矩形多层平面线圈生成器
│   ├── fpc_coil_main.m                公共入口
│   ├── fpc_coil_default_config.m      公共配置入口（每参数带中文注释）
│   ├── private/                       几何/验证/导出/绘图内部实现
│   ├── examples/                      参数化生成示例
│   └── tests/                         回归测试（31 项）
├── .github/workflows/         GitHub Actions：MATLAB 自动跑两个项目的测试
└── README.md                  本文件
```

## 环境要求

- MATLAB R2026a（已在 R2026a 下实际运行验证）；
- 无第三方工具箱依赖（也不依赖 Simulink）；
- 所有 DXF 坐标与尺寸单位为毫米、比例 1:1。

## 快速开始

### 圆环线圈（Circular_FPC_Coil）

```matlab
cd('D:/A_Bone_healing/bone_healing_simulink/Coil/Circular_FPC_Coil');
result = circular_fpc_main();                    % 默认：2 层板 1 线圈，输出到 circular_fpc_output/Circular_FPC_2L_1C/
```

生成 4 层板 2 层线圈：

```matlab
result = circular_fpc_main(struct('boardLayerCount', 4, 'coilLayerCount', 2, ...
    'designName', 'Circular_FPC_4L_2C'));
```

### 矩形多层线圈（FPC_Coil）

```matlab
cd('D:/A_Bone_healing/bone_healing_simulink/Coil/FPC_Coil');
result = fpc_coil_main();                        % 默认：4 层、每层 12 匝，输出到 fpc_coil_output/fpc_coil_4layer/
```

自定义参数：

```matlab
result = fpc_coil_main(struct('layerCount', 4, 'turnsPerLayer', 12, ...
    'plateLength', 80.0, 'plateWidth', 12.0, 'designName', 'my_fpc_coil'));
```

### 两个子项目的详细文档

- 参数表、层间拓扑、过孔/反焊盘、嘉立创 EDA 导入步骤等，见各子项目自己的 `README.md`；
- 日常改尺寸/线宽/匝数，只需编辑对应的 `*_default_config.m`（每个参数都带中文行尾注释），或用 overrides 结构体覆盖，无需改动源码。

## 输出文件（两套工具一致）

每个设计在 `<输出根目录>/<designName>/` 下生成：

```text
dxf/
  00_board_outline.dxf / 05_board_outline.dxf   板框（外边界 + 孔槽/尾板）
  L1/01_copper_*.dxf ... Ln/nn_copper_*.dxf     每物理层铜层（含过孔/反焊盘）
previews/
  01_preview_full.svg ...                        全板/连接区/每层 SVG 预览
reports/
  01_pad_via_coordinates.csv                    焊盘/过孔坐标
  02_layer_map.csv 或 02_design_summary.txt     层映射 / 设计摘要
  ..._validation_report.txt                     验证报告（逐项 PASS/FAIL）
  ..._turn_scan.csv                             匝数可行性扫描
generation_status.txt                            生成状态
```

## 测试

修改核心代码后，在两个子项目根目录分别运行：

```matlab
addpath('tests');
results = run_all_verification();
```

- Circular_FPC_Coil：13 项回归测试；
- FPC_Coil：31 项回归测试。

推送后 GitHub Actions 会在 MATLAB 环境自动运行两套测试（`.github/workflows/matlab-tests.yml`）。

## 非目标与制造前复核

- 本项目只生成几何数据（DXF/CSV/SVG/TXT），**不生成** KiCad、Gerber 或厂家叠层文件；
- 不声明电感、Q 值、工作频率、热性能或植入安全等电气/临床指标（`estimatedDcResistanceOhm` 仅为几何长度估算）；
- 真实叠层（材料、盲埋孔能力、最终电气参数）需与 FPC 厂家确认；自动验证通过不等于厂家一定能够生产；
- 使用本生成结果进行制造或临床相关用途前，必须由具备资质的工程师复核几何、电气与安全要求。
