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

输出包括板框、钻孔、逐层中心线/物理铜/反焊盘 DXF、逐层 COMSOL 闭合铜实体 DXF，CSV/TXT 报告及 SHA-256 文件清单；默认生成 SVG 预览，`enablePreview=false` 时省略。

## COMSOL 闭合铜实体

每层除制造用 DXF 外，另输出两份**只服务于仿真**的闭合轮廓，DXF 图层分别为
`COPPER_SOLID_L<n>` 与 `COPPER_SOLID_TERMINALS_L<n>`：

- `dxf/Ln/NN_copper_solid_Ln.dxf`：只含该层**主螺旋**。适合在线圈上直接加激励、
  自己画端子的模型。
- `dxf/Ln/NN_copper_solid_with_terminals_Ln.dxf`：该层**完整导体**（主螺旋 + 逃逸引线 +
  过孔引线 + 端子引线），每条连通体一个环，COMSOL 2D 里选中即是一个域。

矩形线圈层内导体本来就是一条连续折线（螺旋与引线共用端点），因此不需要圆形模块那样的
并集合并；**L1 有两个环**——从 PAD_A 出发的主链，以及 VOUT → PAD_B 的回程引线，
两者只在过孔处相连——其余层各一个环。文件内实体顺序与 `result.layerPaths{layer}` 一致：
L1 的第 1 条是主链、第 2 条是回程，据此可以给两层分别加激励方向。两份文件都**不含**
电极焊盘、过孔焊盘、钻孔和反焊盘：端点用垂直于走线的直短边封口（不是圆头端弧），
落在焊盘/过孔中心，如何终止交给求解器。

几何契约：中线按半个线宽（`traceWidth/2`）偏置，折角处是半径等于半个线宽的圆角
（与蚀刻铜箔的实际圆角一致，不是制造参考轮廓——制造参考仍是 `NN_copper_physical_Ln.dxf`）；
轮廓顶点经 5 µm 容差的 RDP 简化，可保持在缓冲几何的 5 µm 以内。每条中线必须缓冲出
**恰好一个单连通、无孔的环**，否则导出直接失败（`RectangularFPC:ExportWriteFailed`），
不会写出几何上不成立的轮廓。闭合环一律整条写出，**不按 `maxVerticesPerDxfEntity` 拆分**：
拆开的环不再是闭合边界。导出后逐顶点回读校验，实体类型只能是闭合且无 group-43 宽度的
LWPOLYLINE，出现 CIRCLE 即判失败。

层高（Z）不在这份导出里：本模块只给 XY 几何，6/8 层在所选嘉立创档案下始终是
`UNVERIFIED_LAYER_COUNT`，层叠位置须以厂家档案为准，不要由成品厚度反推。这些是工程几何，
不是 Gerber，也不代表已通过 COMSOL 实际导入或求解验证。

## 制造检查

默认使用 `jlc_fpc_1oz / standard`：所有层数的层间串联过孔都采用**贯穿通孔模型**（连接层焊盘 + 非连接层反焊盘），6 / 8 层的尾板过孔行会自动抬高到「反焊盘半径 + 半线宽 + 外侧逃逸弧半径」以上，为跨越反焊盘场的引线让出通道。2 / 4 层执行完整制造资格判定，失败时拒绝导出；6 / 8 层几何检查同样完整执行（`VIA_TECHNOLOGY` 为 PASS），但 JLCPCB 的 FPC 能力清单只覆盖 1 / 2 / 4 层，因此 6 / 8 层始终标记为 `UNVERIFIED_LAYER_COUNT`——可导出，仅供工程分析以及与具备 6/8 层能力的厂家做工艺确认。

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
