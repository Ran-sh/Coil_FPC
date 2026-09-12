# Rectangular_FPC_Coil

MATLAB 圆角矩形多层 FPC 串联线圈生成器。默认 4 层 × 12 匝，可生成 2 / 4 / 6 / 8 个铜层。

## 使用

```matlab
cd('Rectangular_FPC_Coil');

result = rectangular_fpc_main();

result = rectangular_fpc_main(struct( ...
    'layerCount', 4, ...
    'turnsPerLayer', 12, ...
    'designName', 'bone_healing_coil'));

analysis = rectangular_fpc_main(struct('analysisOnly', true));
```

模块根目录只保留两个公开入口：`rectangular_fpc_default_config(overrides)` 与
`rectangular_fpc_main(overrides)`。其余实现都在 `+RectangularFpc/` 包内，包成员按
「下划线分词 + 每词首字母大写」命名（如 `+Publish/Publish_Lock.m`）。

矩形产物必须通过 `RectangularFpc.Publish.Read_Committed(outputPath, reader)` 读取。
已弃用的 `fpc_coil_default_config` / `fpc_coil_main` 移到 `+RectangularFpc/+Compat/`
（`Fpc_Coil_Default_Config` / `Fpc_Coil_Main`），仍发出 `RectangularFPC:DeprecatedAPI`；
旧的顶层写法 `fpc_coil_main(...)` 不再解析。

## 输出版本

正式目录固定为：

```text
rectangular_fpc_output/<designName>_yyyyMMdd_HHmm/
```

- 同一分钟仅原子替换已通过提交契约的同名旧版本，失败时恢复；占位、残缺或被篡改的目录会原样保留并拒绝覆盖。
- 目录存在不代表发布完成；读取必须通过 `RectangularFpc.Publish.Read_Committed` 校验提交证据并持有访问锁，并发占用时稍后重试。
- 跨分钟保留历史版本。
- `analysisOnly=true` 不创建文件或目录。
- 旧输出根 `fpc_coil_output/` 已清空移除；`.gitignore` 的规则保留，避免误提交再生的同名目录。

安全读取示例：

```matlab
summary = RectangularFpc.Publish.Read_Committed(result.outputPath, ...
    @(p) fileread(fullfile(p, 'reports', '03_design_summary.txt')));
```

输出包括板框、钻孔、逐层中心线/物理铜/反焊盘 DXF，CSV/TXT 报告及 SHA-256 文件清单；默认生成 SVG 预览，`enablePreview=false` 时省略。

## 制造检查

默认使用 `jlc_fpc_1oz / standard`：2 / 4 层采用带逐层反焊盘的贯穿通孔并执行完整制造资格判定，失败时拒绝导出；6 / 8 层仅供工程分析与工艺确认，可导出但始终标记为 `UNVERIFIED_LAYER_COUNT`。

正式资格会对最终几何实测，包括过孔焊盘边缘到真实板框至少 0.50 mm，并检查 4 层串联过孔已错位、未排成直线。

`manufacturingRuleOverrides` 只有在规则同等或更严格时才保留官方档案资格；任何放宽都会降级为 `CUSTOM_RULES / UNVERIFIED`。生成成功、允许导出和 `manufacturing.verified=true` 是三个不同结论。

规则于 2026-09-05 核对，来源为 [JLCPCB FPC 能力表](https://jlcpcb.com/capabilities/flex-pcb-capabilities/)、[FPC 间距指南](https://jlcpcb.com/help/article/fpc-design-clearance)及 [via/pad 孔径公差说明](https://jlcpcb.com/help/article/difference-and-tolerance-explanation-between-via-and-pad-holes)。最终规则、覆盖项与来源写入制造报告。

## 测试

MATLAB R2026a：

```matlab
addpath('tests');
run_all_verification();
```

完整套件覆盖回归、制造资格、拓扑连续性、导出契约、提交证据及原子回滚；测试数量以 `run_all_verification` 输出为准。

DXF 是工程几何，不是完整生产文件；制造前请复核叠层、材料和电气参数。
