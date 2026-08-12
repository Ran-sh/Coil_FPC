# FPC 多层平面线圈 DXF 生成工具

本项目使用 MATLAB 生成用于无线充电、骨愈合刺激等场景的多层 FPC（柔性印刷电路）平面线圈，输出可直接导入嘉立创 EDA 的 DXF 文件、配套坐标/报告和矢量 SVG 预览。程序能够生成：

- 2、4、6、8 层串联 FPC 平面线圈（以及其他不超过 `maxLayerCount` 的偶数层）
- 圆角矩形螺旋铜线
- 层间连接过孔（V12、V23、…）与末层输出通孔（VOUT）
- L1 输入/输出焊盘（PAD_A / PAD_B）
- 板框 DXF 与每层铜线 DXF
- 焊盘与过孔坐标 CSV
- 设计摘要、验证报告、匝数扫描报告
- 两张整体矢量预览、独立焊盘/过孔图及每层一张线圈图；SVG 总数始终为 `layerCount + 3`（不嵌入位图）

所有几何在输出前都会经过角度、自交、线距、连接连续性、焊盘/过孔间距、DXF 回读等多项自动验证，验证不通过时不会产生正式输出。

## 项目文件结构

```text
fpc_coil_main.m              简洁公共入口：读取配置并执行完整生成
fpc_coil_default_config.m    唯一公共配置入口
private/
├─ fpc_coil_engine.m         生成流程、匝数扫描与缓存
├─ fpc_coil_geometry.m       螺旋、引线和坐标几何
├─ fpc_coil_validation.m     配置与几何验证
├─ fpc_coil_export.m         DXF、CSV、TXT 与 SVG 导出
└─ fpc_coil_plot.m           图像窗口内部实现：运行完成后自动弹出，可另存
examples/
└─ generate_fpc_coil.m       参数化生成示例
tests/
├─ test_fpc_coil_regressions.m
└─ run_all_verification.m    完整验证入口
fpc_coil_output/             输出目录（可再生成文件，已被 .gitignore 排除）
```

- 日常修改线圈尺寸、线宽、层数、匝数等，主要编辑 `fpc_coil_default_config.m`，其中每个参数都带有中文行尾注释，说明单位与含义。
- 普通用户只需调用两个根目录入口（`fpc_coil_main`、`fpc_coil_default_config`）；`private/` 中的内部实现（含图像窗口 `fpc_coil_plot.m`）不会成为公共 API。

## MATLAB 环境

- 已在 MATLAB R2026a 环境下实际运行验证。
- 不依赖第三方 MATLAB 工具箱（也不依赖 Simulink）。
- DXF 坐标和尺寸单位为毫米，比例为 1:1。

## 最简单的运行方法

在 MATLAB 中把当前目录切换到本仓库根目录，然后运行：

```matlab
result = fpc_coil_main();
```

默认配置目前为：

```text
层数：4 层
每层匝数：12 匝
自动推荐匝数：关闭
主体长度：80.0 mm
主体宽度：12.0 mm
铜线宽度：0.20 mm
铜线间距：0.15 mm
附加节距余量：0.005 mm
```

### 运行完成后自动弹出图像窗口

`fpc_coil_main` 运行完成后会自动在 MATLAB 中弹出图像窗口（`cfg.enableFigure = true`，默认开启），与 `previews/` 的 SVG 输出结构一致：1 个全部层叠放总览窗口 + 每层各 1 个独立窗口。总览窗口包含板框、全部层铜线路径、焊盘（PAD_A/PAD_B）与过孔（V12…VOUT）；每层窗口只显示该层铜线路径和与该层相连的过孔，焊盘仅出现在 L1（同 SVG 分层预览）。

弹出后可直接使用窗口菜单 **File > Save As**（或工具栏保存按钮），将图像另存为 PNG、JPG、SVG、EMF、PDF 等任意 MATLAB 支持的格式：

```matlab
result = fpc_coil_main();   % 运行完自动弹窗，自行另存即可
```

其他用法：

- 关闭窗口后想再次查看，无需重新生成，重新运行 `result = fpc_coil_main();` 即可再次弹出（图像窗口实现在 `private/fpc_coil_plot.m`，不属于公共 API）；
- 不希望运行时自动弹窗：`result = fpc_coil_main(struct('enableFigure', false));`
- 无头环境（如 CI 的 `-batch` 运行）会自动跳过弹窗，不影响自动化测试。

实际节距说明：

```text
实际节距 = 铜线宽度 + 铜线间距 + 附加节距余量
         = 0.20 + 0.15 + 0.005
         = 0.355 mm
```

默认配置显式生成 `fpc_coil_4layer`：4 层、每层 12 匝，并执行全部几何验证。匝数上限仍会随板宽、线宽、线距、中心保留宽度、层数、过孔位置、引线和验证规则变化；修改参数后请以 `04_turn_scan.csv` 的实际验证结果为准。

## 参数修改方法

修改参数有两种方式，推荐优先使用第二种（覆盖参数），便于保留默认配置原样。

### 方法一：修改默认配置

直接编辑 `fpc_coil_default_config.m`：

```matlab
cfg.traceWidth = 0.20;       % mm，铜线宽度
cfg.traceSpacing = 0.15;     % mm，铜线净间距
cfg.plateLength = 80.0;      % mm，主体长度
cfg.plateWidth = 12.0;       % mm，主体宽度
cfg.layerCount = 4;          % 层，铜层数量
cfg.turnsPerLayer = 12;      % 匝，每层匝数
```

### 方法二：使用覆盖参数，不修改源文件

```matlab
overrides = struct( ...
    'layerCount', 4, ...
    'turnsPerLayer', 12, ...
    'traceWidth', 0.20, ...
    'traceSpacing', 0.15, ...
    'plateLength', 80.0, ...
    'plateWidth', 12.0, ...
    'designName', 'my_fpc_coil');

result = fpc_coil_main(overrides);
```

覆盖参数的优先级高于默认配置；只覆盖 `layerCount` 时，`turnsPerLayer` 保持默认值，`designName` 自动变为 `fpc_coil_<层数>layer`。未知配置字段会被明确拒绝，避免拼写错误被静默忽略。

## 匝数：由几何决定，不与层数绑定

### 为什么层数不应直接决定每层匝数

在相同的接骨板尺寸、线宽、线距、圆角和中心空白要求下，线圈主体的理论匝数上限主要由几何尺寸决定，而不是由 2、4、6、8 层决定。旧版本按层数写死“2 层 9 匝、4 层 6 匝、6/8 层 5 匝”，并在螺旋相位中加入随层数变化的补偿项，使层数直接影响径向尺寸——这套逻辑已全部删除。

重构后：

- 每层螺旋完成**整数圈**（`turnsPerLayer`），起点与终点相位相同（由 `connectionPhase`/`connectionSide` 控制）；
- 奇数层从外圈向内圈绕，偶数层从内圈向外圈绕，相邻层的内圈/外圈锚点重合；
- 不再存在“8 圈 + 随层数变化的相位补偿”；`turnsPerLayer = 8` 就是每层实际完成 8 个完整绕行周期；
- 过孔位置通过独立逃逸引线连接，不再通过改变螺旋相位实现。

### 最大匝数联合约束

最大匝数由以下解析约束的最小值决定（全部写入 `result.turnLimits` 与报告）：

```text
pitch = traceWidth + traceSpacing + pitchMargin
outerCenterInset = edgeClearance + traceWidth/2
outerLength = plateLength - 2*outerCenterInset
outerWidth  = plateWidth  - 2*outerCenterInset

widthMaxTurns    = floor((outerWidth  - minInnerWidth) / (2*pitch))
lengthMaxTurns   = floor((outerLength - minInnerLength) / (2*pitch))
cornerMaxTurns   = floor((coilOuterRadius - minSpiralCornerRadius) / pitch)   % 严格同心模式
innerViaMaxTurns = min( floor((outerWidth  - requiredInnerWidthForVias)/(2*pitch)),
                        floor((outerLength - requiredInnerLengthForVias)/(2*pitch)) )
analyticalMaximum = min(widthMaxTurns, lengthMaxTurns, cornerMaxTurns, innerViaMaxTurns)
recommended       = max(1, fullyValidatedMaximumTurns - recommendedTurnMargin)
```

其中 `coilOuterRadius` 由 `coilOuterCornerRadiusMode` 决定：

- `follow_board`：`plateCornerRadius - outerCenterInset`（兼容旧行为）；
- `maximize`：`min(outerLength, outerWidth)/2`（推荐；80×12 板线圈接近长圆形，板框仍保持原圆角）；
- `manual`：使用 `coilOuterCornerRadius`（必须满足 `0 < r <= min(outerLength,outerWidth)/2`）。

`turnLimits` 字段：`width`、`length`、`cornerRadius`、`innerViaRegion`、`tabViaRegion`、`analyticalMaximum`、`fullyValidatedMaximum`、`recommended`、`limitingFactors`（限制因素，如 `WIDTH_LIMIT`/`CORNER_RADIUS_LIMIT`/`INNER_VIA_CAPACITY`/`TAB_VIA_CAPACITY`）。

### 板框圆角与线圈圆角

- `plateCornerRadius` 只控制接骨板主体外框圆角，与线圈圆角完全解耦；
- 线圈外圈圆角由 `coilOuterCornerRadiusMode` 独立控制；
- `cornerOffsetMode = 'strict_concentric'`：第 n 圈圆角半径严格等于 `coilOuterRadius - radialInset`，相邻匝半径差 = pitch；用户匝数超过圆角上限时报错；
- `cornerOffsetMode = 'legacy_clamped'`：保留旧版 `max(..., minSpiralCornerRadius)` 截断；摘要中给出“内圈圆角发生下限截断”警告，且不描述为“严格等距圆角”。

### 为什么 80×12 mm 通常由宽度控制

`widthMaxTurns = floor((12 - 2*0.6 - 1.0) / (2*0.355)) = 13`，而 `lengthMaxTurns` 约 109、`cornerMaxTurns`（maximize 模式）为 12，因此宽度或圆角最先成为瓶颈，长度通常不限制。

### 过孔放置模式

- `viaPlacementMode = 'hybrid_auto'`（推荐）：奇数编号层间过孔（V12、V34、V56、V78）从中心空白区最靠近右侧线圈锚点的安全边界起向左紧凑排列；偶数编号（V23、V45、V67）从主体与右侧尾板交界后的安全边界起向右紧凑排列；候选行优先取到对应线圈锚点总距离最短者；
- `viaPlacementMode = 'legacy_auto'`：旧版端点附近放置，仅用于兼容与对比；
- `viaPlacementMode = 'manual'`：人工坐标（见下）。

内圈过孔沿长度方向（X）横向排列，是因为 80×12 板的中心空白区长而窄：横向排布能容纳更多过孔，过孔到内圈铜线的净距可由几何统一保证。实际过孔中心距取 `max(innerViaPitch, viaPadDiameter + viaToViaClearance)`。自动 VOUT 同样优先放在主体/尾板交界后的最靠左安全位置，以缩短线圈到 VOUT 的引线；VOUT 到右侧 `PAD_B` 的独立回线不参与该最短目标。

### 主体左下角坐标系与人工过孔

用户坐标原点为**主体左下角**（`coordinateOrigin = 'body_lower_left'`）：

- 主体范围：`0 <= X <= plateLength`、`0 <= Y <= plateWidth`；
- 右侧尾板范围：`plateLength < X <= plateLength + tabLength`，Y 以 `tabWidth` 相对主体中线对称；
- 内部几何运算仍以主体中心为原点，`01_pad_via_coordinates.csv` 同时输出两套坐标（`x/y_body_lower_left_mm` 与 `x/y_internal_center_mm`）。

```matlab
cfg.layerCount = 4;
cfg.viaPlacementMode = 'manual';
cfg.manualSeriesViaXY = [25.0, 6.0; 82.0, 6.0; 55.0, 6.0];  % 每行依次对应 V12、V23、V34
cfg.outputViaPlacementMode = 'manual';
cfg.manualOutputViaXY = [88.0, 4.7];                          % VOUT，主体左下角原点
```

人工坐标非法时程序不会自动移动或静默修正，会报出具体过孔名、输入坐标与失败原因（例如“V34 手动坐标 (55.000, 6.000) mm 无效：过孔焊盘到 L3 铜线净距仅为 0.083 mm，要求至少为 0.150 mm”）。

### 过孔数量随层数增加的真实限制

主体尺寸上限不随层数变化；但层数增加会新增层间过孔及逃逸引线，占用中心空白与尾板空间，因此**完整验证上限**可能下降。报告会明确输出：

```text
线圈主体尺寸上限未变化；
完整验证上限下降是由于新增层间过孔及逃逸引线占用空间。
```

并给出具体限制因素（`INNER_VIA_CAPACITY`、`TAB_VIA_CAPACITY`、`ROUTING_NO_PATH`、`ROUTING_ARC_FAILURE` 等）。

### 输出报告字段

`02_design_summary.txt` 与 `03_validation_report.txt` 输出：用户坐标原点、过孔放置模式、线圈外圈圆角模式、实际线圈外圈圆角半径、圆角偏移模式、宽度/长度/圆角/内圈过孔区域匝数上限、尾板过孔容量检查、综合理论上限、完整验证上限、推荐匝数、最终限制因素、内圈/尾板过孔排列方式、是否发生圆角半径截断。

### 手动匝数与自动推荐匝数

```matlab
cfg.useRecommendedTurns = false;   % 手动：使用 cfg.turnsPerLayer
cfg.turnsPerLayer = 8;             % 每层整数圈数

cfg.useRecommendedTurns = true;    % 自动：推荐 = 完整验证上限 - recommendedTurnMargin
```

自动推荐模式下程序通过完整几何扫描确定 `fullyValidatedMaximumTurns`（从解析上限向下，逐候选执行角度、线距、自交、焊盘、过孔与板框全部验证，第一个全部通过的值），推荐值再保留 `recommendedTurnMargin` 匝裕量。扫描成功候选的几何会被缓存供正式生成复用，但最终仍会执行完整精确验证。每次正式生成都会写出 `04_turn_scan.csv`（含 `failure_code` 列）：

```matlab
result = fpc_coil_main(struct( ...
    'layerCount', 4, ...
    'useRecommendedTurns', true, ...
    'enablePreview', false));
scan = readtable(result.turnScanFile);
disp(scan);
```

## 常用参数表

### 新增参数（重构版）

| 参数 | 默认值 | 单位 | 说明 |
| --- | --- | --- | --- |
| `minInnerLength` | 1.00 | mm | 中心空白区域最小长度 |
| `connectionPhase` | 0.0 | — | 所有层内外连接锚点的归一化相位 |
| `connectionSide` | `'right_center'` | — | 连接锚点方位 |
| `coilOuterCornerRadiusMode` | `'maximize'` | — | `'follow_board'`/`'maximize'`/`'manual'` |
| `coilOuterCornerRadius` | `[]` | mm | manual 模式下的线圈最外圈圆角半径 |
| `cornerOffsetMode` | `'strict_concentric'` | — | `'strict_concentric'`/`'legacy_clamped'` |
| `coordinateOrigin` | `'body_lower_left'` | — | 用户输入及导出坐标原点 |
| `viaPlacementMode` | `'hybrid_auto'` | — | `'legacy_auto'`/`'hybrid_auto'`/`'manual'` |
| `manualSeriesViaXY` | `zeros(0,2)` | mm | 手动层间过孔坐标，每行对应 V12、V23…… |
| `outputViaPlacementMode` | `'auto'` | — | VOUT 使用 `'auto'` 或 `'manual'` |
| `manualOutputViaXY` | `zeros(0,2)` | mm | 手动 VOUT 坐标 |
| `outputViaTipInset` | 4.00 | mm | auto 模式下 VOUT 距尾板尖端的最小水平内缩限制；实际位置可更靠左 |
| `innerViaLayout` | `'horizontal'` | — | 内圈过孔排列方向 |
| `innerViaPitch` | 2.00 | mm | 内圈过孔期望中心间距 |
| `innerViaRowOffsetY` | 0.00 | mm | 内圈过孔排相对主体中线的偏移 |
| `outerViaLayout` | `'horizontal'` | — | 尾板过孔排列方向 |
| `outerViaPitch` | 1.50 | mm | 尾板过孔期望中心间距 |
| `outerViaRowOffsetY` | 0.00 | mm | 尾板过孔排相对主体中线的偏移 |
| `viaKeepoutMargin` | 0.10 | mm | 过孔规划附加安全余量 |
| `autoViaGridStep` | 0.25 | mm | 自动过孔候选位置搜索步长 |
| `recommendedTurnMargin` | 1 | 匝 | 推荐值相对完整验证上限保留的匝数裕量 |

### 基础参数

| 参数                    |   当前默认值 | 单位 | 说明                |
| --------------------- | ------: | -- | ----------------- |
| `layerCount`          |       4 | 层  | 铜层数量，只支持规定范围内的偶数层 |
| `useRecommendedTurns` | `false` | —  | 是否自动使用安全推荐匝数      |
| `turnsPerLayer`       |      12 | 匝  | 手动模式下的每层匝数        |
| `plateLength`         |    80.0 | mm | 主体线圈区域长度          |
| `plateWidth`          |    12.0 | mm | 主体线圈区域宽度          |
| `traceWidth`          |    0.20 | mm | 铜线宽度              |
| `traceSpacing`        |    0.15 | mm | 相邻铜线目标净间距         |
| `edgeClearance`       |    0.50 | mm | 铜线到主体板边的安全距离      |
| `minInnerWidth`       |    1.00 | mm | 线圈中心最小保留宽度        |

### 尾板、焊盘与引出线参数

| 参数                    |   当前默认值 | 单位 | 说明                |
| --------------------- | ------: | -- | ----------------- |
| `tabLength`           |    12.0 | mm | 右侧尾板长度            |
| `tabWidth`            |     5.0 | mm | 右侧尾板宽度            |
| `leadYOffset`         |    1.10 | mm | PAD_A/PAD_B/VOUT 相对板中线的 Y 偏移 |
| `leadBendRadius`      |    1.20 | mm | 焊盘与螺旋间 90° 圆弧半径   |
| `padTipInset`         |    1.50 | mm | 焊盘圆心到尾板右端的内缩距离    |
| `padDiameter`         |    1.50 | mm | PAD_A/PAD_B 焊盘直径    |
| `padToPadClearance`   |    0.15 | mm | 两个焊盘之间的目标净间距      |
| `padToCopperClearance`|    0.15 | mm | 焊盘边缘到非连接铜线的净距     |

### 过孔参数

| 参数                    |   当前默认值 | 单位 | 说明                |
| --------------------- | ------: | -- | ----------------- |
| `viaDrillDiameter`    |    0.30 | mm | 层间过孔钻孔直径          |
| `viaPadDiameter`      |    0.60 | mm | 层间过孔焊盘直径          |
| `minAnnularRing`      |    0.15 | mm | 过孔最小环宽（仅配置校验使用）   |
| `viaToCopperClearance`|    0.15 | mm | 过孔焊盘到非连接层铜线的净距    |
| `viaToBoardClearance` |    0.30 | mm | 过孔到板框的净距          |
| `viaToViaClearance`   |    0.20 | mm | 相邻过孔之间的目标净间距      |
| `viaToPadClearance`   |    0.20 | mm | 过孔焊盘到外接焊盘的净距      |

### 高级参数

| 参数                    |   当前默认值 | 单位 | 说明                |
| --------------------- | ------: | -- | ----------------- |
| `geometryTolerance`   |   1e-6 | mm | 全局几何容差（去重、零长度段等）  |
| `connectionTolerance` |   1e-5 | mm | 层间端点连接误差上限        |
| `clearanceTolerance`  |  0.002 | mm | 线距检查允许的负偏差        |
| `requireSmoothLeadTransitions` | `true` | — | 要求引线连接满足平滑过渡与严格角度阈值 |
| `pointsPerTurn`       |     900 | 点  | 每匝螺旋采样点数          |
| `minTurnPointCount`   |     500 | 点  | 单条螺旋路径最少采样点数      |
| `boardArcPointCount`  |      64 | 点  | 板框圆弧采样点数          |
| `maxVerticesPerDxfEntity` | 220 | 点 | 单条 DXF 多段线最大顶点数（超出拆分） |

> 高级参数影响几何离散精度、验证容差和 DXF 文件复杂度。没有明确原因时，不建议修改。

### 验证开关

| 参数 | 当前默认值 | 说明 |
| --- | --- | --- |
| `enableExactSelfIntersectionCheck` | `true` | 检查板框与铜线自交、同层路径相交 |
| `enableCopperClearanceCheck` | `true` | 检查铜线之间的实际最小线距 |
| `enableBoardAngleCheck` | `true` | 检查板框最小内角 |
| `enableCopperAngleCheck` | `true` | 检查铜线路径最小内角 |
| `enablePadClearanceCheck` | `true` | 检查焊盘在板内、焊盘互距及焊盘到铜线净距 |
| `enableViaClearanceCheck` | `true` | 检查过孔互距及过孔到板框/焊盘/铜线净距、反焊盘开窗 |
| `enableDxfReadbackCheck` | `true` | 回读 DXF 检查文件完整性与顶点数 |

关闭验证开关可能使不合格的几何进入输出文件，生产设计不建议关闭。

### 输出与显示开关

| 参数 | 当前默认值 | 说明 |
| --- | --- | --- |
| `enablePreview` | `true` | 是否生成 `previews/` 矢量 SVG 预览图 |
| `enableFigure` | `true` | 运行完成后是否在 MATLAB 桌面环境自动弹出图像窗口 |

引线按固定优先级选择：合规直线优先，其次是单个最小圆角加直线，仅在前两类均受板框、线距、自交或连接角限制时才使用双段绕行；同一级候选取总长度最短者。PAD_A、层间过孔与 VOUT 的长直段只允许水平或垂直，方向切换使用与入口切线相切的圆弧；更高优先级一旦找到合规路径，就不会继续计算更复杂绕行。这样可直连的位置不会再生成半圆或回头弧线。PAD_B 保持独立的水平回路，右侧 PAD_A/PAD_B 焊盘引线不参与过孔就近布局的最短长度目标。默认右侧焊盘组使用 `leadYOffset=1.10 mm`：PAD_A/PAD_B 铜边间距为 `0.70 mm`，上下板边余量各为 `0.65 mm`；VOUT 与 PAD_B 保持水平对齐。自动规划时 VOUT 按过孔直径和 `viaToViaClearance` 与层间过孔判距，不再按外部大焊盘直径无谓推远 V23。手动 VOUT 坐标会先从用户坐标系转换到内部坐标系，再执行板边、焊盘、过孔和铜线净距检查。

## 层间串联拓扑

以 4 层为例，电气路径为：

```text
PAD_A
  → L1线圈
  → V12
  → L2线圈
  → V23
  → L3线圈
  → V34
  → L4线圈
  → VOUT通孔
  → L1独立回路线
  → PAD_B
```

说明：

- `PAD_A` 和 `PAD_B` 均位于 L1，便于从同一面焊接。
- 相邻层由层间过孔 `V12`、`V23`、… 串联（奇数层从外圈进、偶数层从内圈出）。
- `VOUT` 将最后一层（L4）连接回 L1，是贯穿所有层的通孔；在中间非连接铜层，`VOUT` 需要按 `outputViaAntiPadDiameter` 设置反焊盘（禁铜开窗），否则会与中间层线圈短路。
- L1 线圈路径与 L1 输出回路线是两条独立路径，程序会分别写入同一个 L1 DXF 文件，不会拼接成一条造成虚假铜桥；在 EDA 中也不要将这两条独立路径错误合并。

## 输出目录说明

成功运行后，输出位于 `fpc_coil_output/<designName>/`：

```text
fpc_coil_output/<designName>/
├─ dxf/
│  ├─ L1/
│  │  └─ 01_copper_l1_top.dxf         L1（顶层）铜线
│  ├─ L2/
│  │  └─ 02_copper_l2_inner1.dxf      L2 铜线
│  ├─ L3/
│  │  └─ 03_copper_l3_inner2.dxf      L3 铜线
│  ├─ L4/
│  │  └─ 04_copper_l4_bottom.dxf      L4（底层）铜线
│  └─ 05_board_outline.dxf            板框（编号 = 层数 + 1，位于 dxf/ 根目录）
├─ reports/
│  ├─ 01_pad_via_coordinates.csv      焊盘/过孔坐标、钻孔、环宽、反焊盘与连接层
│  ├─ 02_design_summary.txt           设计摘要（尺寸、长度、估算电阻、匝数上限、拓扑）
│  ├─ 03_validation_report.txt        全部验证项逐项结论
│  └─ 04_turn_scan.csv                候选匝数扫描结果与失败原因
├─ previews/
│  ├─ 01_preview_full.svg             整体矢量预览图
│  ├─ 02_preview_right_tab.svg        右侧尾板区域矢量预览图
│  ├─ 03_preview_pads_vias.svg        独立焊盘/过孔、钻孔及 VOUT 反焊盘图
│  ├─ 04_preview_layer_L1_top.svg     L1 铜线、输出回线、焊盘及连接过孔
│  ├─ 05_preview_layer_L2_inner1.svg  L2 铜线及与 L2 连接的过孔
│  ├─ 06_preview_layer_L3_inner2.svg  L3 铜线及与 L3 连接的过孔
│  └─ 07_preview_layer_L4_bottom.svg  L4 铜线及与 L4 连接的过孔
└─ generation_status.txt              生成状态与关键参数快照
```

文件用途说明：

- `dxf/`：每层一个子目录，铜线 DXF 按层号命名；板框 DXF 位于 `dxf/` 根目录。
- `01_pad_via_coordinates.csv`：`PAD_A`、`PAD_B`、各层间过孔与 `VOUT` 的坐标、连接层、钻孔直径、焊盘直径、环宽和反焊盘直径，供在 EDA 中建立真实焊盘/过孔使用。
- `02_design_summary.txt`：主体/尾板尺寸、节距、每层长度与估算直流电阻、串联总长度与总电阻、三个匝数上限、拓扑与 DXF 文件名。
- `03_validation_report.txt`：参数检查、尺寸检查、板框/铜线角度与自交、线距、连接误差、焊盘/过孔间距等逐项结论。
- `04_turn_scan.csv`：每个候选匝数是否通过验证及失败原因。
- `previews/`：白色背景的纯矢量 SVG，不含嵌入式 `<image>`，也不生成 PNG。前两张保持整体/右侧尾板视图；`03_preview_pads_vias.svg` 按真实直径显示 PAD、过孔焊盘、钻孔及 VOUT 虚线反焊盘；从编号 04 开始每个铜层各一张，只显示该层铜路径、与该层连接的过孔，并仅在 L1 显示 PAD_A/PAD_B 与输出回线。文件总数为 `layerCount + 3`；仅作几何示意，不能代替 DRC。
- `generation_status.txt`：本次生成的参数快照与状态。

生成失败时，程序会抛出错误，并在 `fpc_coil_output/<designName>_temp/` 中保留 `03_validation_report.txt` 供查看失败原因；正式输出目录不会被不完整结果覆盖。

## 嘉立创 EDA 导入步骤

1. 运行 MATLAB 程序生成 DXF。
2. 在嘉立创 EDA 中新建对应层数的 FPC 工程。
3. 将每个铜层 DXF 导入对应铜层（如 `01_copper_l1_top.dxf` 导入顶层）。
4. 导入时使用毫米单位和 1:1 比例。
5. 检查导入后的总长、总宽是否与设计摘要（`02_design_summary.txt`）一致。
6. 根据 CSV（`01_pad_via_coordinates.csv`）建立焊盘和过孔。
7. 铜线图形导入后确认实际线宽为 `traceWidth`（默认 0.20 mm）。
8. 检查 VOUT 通孔在中间层的反焊盘或禁铜设置（`outputViaAntiPadDiameter`，默认 0.90 mm）。
9. 导入板框 DXF。
10. 运行嘉立创 EDA 的 DRC。
11. 下单前确认 FPC 厂家的最小线宽、最小线距、孔径、环宽和多层通孔能力。

需要特别提醒：

- DXF 只包含几何图形，不会自动建立完整的 padstack（焊盘、钻孔、覆盖膜开窗）。
- CSV 中的坐标需要用于创建真实焊盘和钻孔。
- 中间层反焊盘需要在 EDA 中正确设置，否则 VOUT 会与中间层铜线短路。
- 不要盲目依赖预览图代替 DRC。
- 底层是否需要镜像，以当前程序的统一观察方向和 EDA 导入规则为准：程序按统一观察方向输出，设计摘要中标注“底层 DXF 不需要手动镜像”，导入时如与目标工程方向不符，应以实测核对为准。

## 常见错误与处理方法

### 匝数超过严格同心圆角上限

报错形如：“宽度允许 13 匝，但严格同心圆角仅允许 8 匝”。解决：增大 `coilOuterCornerRadius`（或 `maximize` 模式）、减小匝数、或切换 `cornerOffsetMode = 'legacy_clamped'`（会触发截断警告）。

### 内圈/尾板过孔容量不足

报错给出所需长度与可用长度。解决：增大板尺寸或 `tabLength`、减小过孔数量（减少层数）、改变过孔布局、或使用 `viaPlacementMode = 'manual'` 人工坐标。

### 人工过孔坐标无效

报错给出具体过孔名、输入坐标与失败原因（板外/焊盘重叠/过孔互距不足/离铜线过近/行数错误）。程序不会自动移动或静默修正坐标。

### 过孔规划失败（ROUTING_NO_PATH / ROUTING_ARC_FAILURE）

逃逸引线无法用切向圆弧布通（转向角超过 90° 或没有可用通道）。解决：增大板/尾板空间、增大 `leadBendRadius`/`viaInnerBendRadius`、或改用 `manual` 过孔。

### 匝数过多

可能原因：

- 线圈中心空间不足
- 引出线无法形成平滑圆角（例如“逃逸引线无法生成平滑圆弧，将回退为90度尖角”）
- 铜线发生自交
- 线距不足
- 过孔与铜线距离不足

处理方法：

- 减少 `turnsPerLayer`
- 开启 `useRecommendedTurns`，使用程序扫描出的安全推荐匝数
- 增大 `plateWidth`
- 减小 `traceWidth`
- 减小 `traceSpacing`
- 调整中心保留宽度（`minInnerWidth`）或逃逸参数（`viaLandingLeadLength`、`viaOuterLandingLeadLength`、`viaInnerBendRadius` 等）

> 减小线宽和线距前必须确认制造工艺支持，程序验证通过不等于厂家一定能够生产。

### 层数错误

当前程序只接受 2 到 `maxLayerCount`（默认 8）范围内的偶数层，单数层会报：

```text
FPC_Coil:InvalidLayerCount
```

例如输入 3、5、7 层都会触发该错误。

### 过孔环宽不足

环宽关系：

```text
环宽 = (viaPadDiameter - viaDrillDiameter) / 2
```

需要满足 `minAnnularRing`（默认 0.15 mm），否则报 `FPC_Coil:InvalidViaGeometry`。增大 `viaPadDiameter` 或减小 `viaDrillDiameter` 均可提高环宽，但同样需要满足制造工艺。

### DXF 回读验证失败

`enableDxfReadbackCheck` 开启时，程序会回读 DXF 检查文件完整性与实体数量。该检查失败说明输出可能不完整、实体数量异常或文件写入有问题，不应把失败文件直接用于生产。可检查磁盘空间、路径权限后重试。

### 输出目录已有旧文件

不同参数生成的结果会先写入 `<designName>_temp`，全部验证和导出成功后再原子替换 `fpc_coil_output/<designName>/`；同一正式目录中的 DXF、报告和 SVG 因而来自同一次生成。若需要同时保留多个版本，请使用不同的 `designName`。

## 参数修改示例

生成 4 层、每层 12 匝、铜线宽 0.20 mm、线距 0.15 mm、主体长度 80 mm 的线圈：

```matlab
overrides = struct( ...
    'layerCount', 4, ...
    'useRecommendedTurns', false, ...
    'turnsPerLayer', 12, ...
    'plateLength', 80.0, ...
    'plateWidth', 12.0, ...
    'traceWidth', 0.20, ...
    'traceSpacing', 0.15, ...
    'designName', 'fpc_coil_4layer');

result = fpc_coil_main(overrides);
```

也可以直接编辑并运行唯一参数化示例 `examples/generate_fpc_coil.m`。

自动推荐匝数示例：

```matlab
overrides = struct( ...
    'layerCount', 4, ...
    'useRecommendedTurns', true, ...
    'plateLength', 80.0, ...
    'plateWidth', 12.0, ...
    'traceWidth', 0.20, ...
    'traceSpacing', 0.15, ...
    'designName', 'fpc_4layer_auto_turns');

result = fpc_coil_main(overrides);
```

## 测试方法

修改核心代码、层间拓扑或 DXF 输出逻辑后，应重新运行回归测试：

```matlab
addpath('tests');
results = run_all_verification();
```

回归测试覆盖配置入口、2/4/6/8 层、手动过孔与 VOUT、正交直线/单圆角/绕行候选、自动过孔就近布局、线距、角度、自交、DXF 回读、动态分层 SVG 矢量输出和 12 匝目标等行为；当前共 31 项。

## 性能基准（MATLAB R2026a）

以下数据均在同一台机器上先预热一次，再连续运行三次并取中位数。自动推荐场景关闭 SVG 预览，但不降低采样精度或关闭几何验证；完整回归按测试自身配置运行，其中 SVG 行为测试会真实生成并解析 4 层 7 张和 6 层 9 张预览：

- 4 层自动推荐场景：`17.495 s`（三次为 `24.650 / 17.495 / 16.587 s`，推荐 11 匝）。相对项目原基线 `10.06 s` 当前慢约 `73.9%`；该路径不执行预览导出，因此这里只如实记录本机本轮结果，不把波动解释成 SVG 改动，也不设置 CI 时间阈值。
- 完整回归套件：`161.746 s`（三次为 `283.770 / 149.705 / 161.746 s`），31 项全部通过。原基线为 20 项、`34.3 s`；当前中位耗时高约 `371.6%`。当前套件新增 4/6 层共 16 张 SVG 的真实生成、XML/矢量元素/分层内容检查，与旧基线负载不同，不能视为严格同负载比较。

正交候选按优先级短路后，不再在简单合规路径已经找到时继续执行后续候选的精确角度、间距和自交计算；该优化不降低采样密度，也不跳过最终验证。性能仍有继续优化空间，尤其是完整路径的重复精确几何检查。

耗时会随 CPU、MATLAB 缓存和后台负载波动，因此不作为脆弱的 CI 硬阈值。

## 当前限制

- 不支持单数层，单数层会明确报错拒绝，避免生成电气拓扑错误的结果。
- 输出 DXF 仍需在 EDA 中建立真实焊盘、钻孔和覆盖膜开窗，程序不生成完整 padstack。
- 多层 FPC 的具体层叠和过孔工艺（盲孔/埋孔/通孔）需与厂家确认。
- 自动验证通过不等于厂家一定能够生产。
- 线宽、线距、孔径和环宽必须满足制造商规则。
- SVG 预览用于几何核对，不替代 EDA 的制造规则检查与实际打样验证。
