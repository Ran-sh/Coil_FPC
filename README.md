# Coil_FPC

用于生成多层柔性 PCB（FPC）串联平面线圈的 MATLAB 工具。程序生成圆角矩形螺旋、层间过孔、顶层输入/输出焊盘，并在全部几何与制造规则检查通过后输出 DXF、CSV、验证报告和预览图。

## 当前能力

- 支持 2、4、6、8 层，以及不超过 `maxLayerCount` 的其他偶数层。
- 暂不支持单数层；输入 3、5、7 层会明确报错 `FPC_Coil:InvalidLayerCount`。
- 相邻铜层通过 `V12`、`V23`、…、`V(N-1)N` 串联。
- 最后一层从右侧引出至 `VOUT`，经通孔返回 L1，再由独立的 L1 回路线连接 `PAD_B`。
- `PAD_A`、`PAD_B` 均位于 L1，便于从同一面焊接。
- `VOUT` 默认为通孔；在中间非连接铜层需要按 CSV 中的反焊盘直径设置禁铜。
- 同时输出宽度理论上限、完整几何验证上限和安全推荐值（完整上限减 1）。
- 自动检查角度、自交、线距、连接连续性、焊盘/过孔是否在板内、铜间距及 DXF 回读完整性。

## 环境

- MATLAB R2026a（已实际运行验证）
- 不依赖第三方 MATLAB 工具箱

## 快速开始

在 MATLAB 中切换到仓库目录：

```matlab
result = fpc_coil_main();
```

默认配置为 4 层，并启用自动推荐匝数：

```matlab
cfg = fpc_coil_default_config();
cfg.layerCount = 4;
cfg.useRecommendedTurns = true;
result = fpc_coil_generate(cfg);
```

自定义配置无需修改主程序：

```matlab
cfg = fpc_coil_default_config(struct( ...
    'layerCount', 6, ...
    'useRecommendedTurns', false, ...
    'turnsPerLayer', 6, ...
    'designName', 'my_6layer_coil'));

result = fpc_coil_generate(cfg);
```

也可直接向入口传覆盖参数：

```matlab
result = fpc_coil_main(struct('layerCount', 8));
```

## 层间拓扑

以 6 层为例：

```text
PAD_A (L1)
  -> L1 -> V12 -> L2 -> V23 -> L3 -> V34
  -> L4 -> V45 -> L5 -> V56 -> L6
  -> VOUT (L6 到 L1 通孔)
  -> L1 独立回路线
  -> PAD_B (L1)
```

L1 的线圈与输出回路线是两个独立 polyline。程序会分别写入同一个 L1 DXF，绝不会把两条路径拼接成一条造成虚假铜桥。

## 匝数上限

程序区分三个概念：

- `widthBasedMaximumTurns`：只按板宽、中心保留宽度、节距和多层相位计算。
- `fullyValidatedMaximumTurns`：从宽度上限向下试算，角度、线距、自交、焊盘、过孔和板框检查全部通过的最大值。
- `recommendedTurns`：`fullyValidatedMaximumTurns - 1`，保留一匝安全裕量。

默认几何与制造参数在 MATLAB R2026a 中复核得到：

| 层数 | 宽度理论上限 | 完整验证上限 | 安全推荐值 |
| ---: | ---: | ---: | ---: |
| 2 | 11 | 11 | 10 |
| 4 | 11 | 9 | 8 |
| 6 | 11 | 7 | 6 |
| 8 | 11 | 7 | 6 |

因此，两层并不是“大于 10 匝就一定不行”：默认参数下 11 匝能够通过完整验证，但推荐 10 匝以保留制造裕量。板宽、线宽、线距、中心保留宽度或逃逸几何变化后，上限会重新计算。

若要查看指定匝数的逐项结论：

```matlab
cfg = fpc_coil_default_config(struct('layerCount', 4));
scan = fpc_coil_scan_turns(cfg, 6:11);
disp(struct2table(scan));
```

每次正式生成还会写出 `04_turn_scan.csv`，失败候选包含具体原因。

## 关键参数

| 参数 | 默认值 | 说明 |
| --- | ---: | --- |
| `traceWidth` | 0.20 mm | 铜线宽度 |
| `traceSpacing` | 0.15 mm | 目标净线距 |
| `pitchMargin` | 0.005 mm | 附加节距余量 |
| `edgeClearance` | 0.50 mm | 铜线到主体板边余量 |
| `viaInnerBendRadius` | 0.50 mm | 内圈层间逃逸圆角半径 |
| `viaOuterLandingLeadLength` | 1.00 mm | 右侧层间过孔引出长度 |
| `viaToPadClearance` | 0.20 mm | 过孔焊盘到外接焊盘净距 |
| `outputViaType` | `through_via` | VOUT 类型 |
| `outputViaAntiPadDiameter` | 0.90 mm | VOUT 在非连接内层的反焊盘直径 |
| `outputViaTipInset` | 4.00 mm | VOUT 距右侧尾端的水平内缩 |
| `useRecommendedTurns` | `true` | 自动采用完整上限减 1 |

实际生成节距为：

```text
traceWidth + traceSpacing + pitchMargin = 0.355 mm
```

## 输出文件

成功运行后：

```text
fpc_coil_output/<designName>/
├─ dxf/
│  ├─ L1/ ... L<N>/             各铜层 DXF
│  └─ BOARD_OUTLINE/             板框 DXF
├─ reports/
│  ├─ 01_pad_via_coordinates.csv 焊盘/过孔/反焊盘数据
│  ├─ 02_design_summary.txt       长度、电阻、上限和拓扑摘要
│  ├─ 03_validation_report.txt    全部验证结论
│  └─ 04_turn_scan.csv            候选匝数与失败原因
├─ previews/
│  ├─ 01_preview_full.png
│  └─ 02_preview_right_tab.png
└─ generation_status.txt
```

输出目录属于可再生成文件，已由 `.gitignore` 排除。发布时可把经过验证的输出压缩包附加到 GitHub Release，而不把大量 DXF 长期放在源码分支。

## EDA 导入注意事项

- DXF 单位为毫米，比例 1:1。
- 铜线导入宽度设为 `traceWidth`（默认 0.20 mm）。
- 各层按统一观察方向输出，底层无需手动镜像。
- CSV 提供焊盘、钻孔、环宽、连接层和反焊盘数据；真实 padstack、覆盖膜开窗、盲埋孔或通孔工艺仍需在 EDA 中建立。
- `VOUT` 穿过所有层；除 L1 和最后一层外，中间层按 `outputViaAntiPadDiameter` 设置禁铜/反焊盘。
- 生产前必须与 FPC 制造商确认层叠、最小环宽、钻孔公差和通孔能力。

## 测试

```matlab
results = runtests('test_fpc_coil_regressions.m');
assertSuccess(results);
```

测试覆盖配置入口、偶数/单数层约束、6/8 层扩展、VOUT 通孔、PAD_B 顶层归属、L1 双独立路径、动态 DXF 层名、输出文件和失败原因。

## 文件说明

```text
fpc_coil_main.m              简洁入口
fpc_coil_default_config.m    默认配置与覆盖参数
fpc_coil_validate_config.m   公共配置验证
fpc_coil_scan_turns.m        参数组合/匝数扫描
fpc_coil_generate.m          几何、验证与导出核心
examples/                    2/4/6/8 层示例
test_fpc_coil_regressions.m  MATLAB 行为回归测试
```

## 当前限制与后续方向

- 单数层需要额外的专用回流层或独立跨层走线通道；当前明确拒绝，避免生成电气拓扑错误的结果。
- 相邻层过孔目前按相邻层连接建模；是否使用盲孔、埋孔或逐层微孔，应根据制造商能力决定。
- 核心文件仍可继续拆分为独立的 geometry、validation、export 模块；公共配置、验证和扫描入口已经先行分离。
- 圆角函数保留失败回退标记；若某组参数只能形成尖角，验证报告会显示 `FALLBACK_TO_SHARP_CORNER`。
