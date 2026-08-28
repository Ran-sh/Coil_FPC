# Rectangular_FPC_Coil

MATLAB 圆角矩形多层 FPC 串联线圈生成器。默认 4 层 × 12 匝，支持 2 / 4 / 6 / 8 个偶数铜层。

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

公共入口：`rectangular_fpc_default_config(overrides)`、`rectangular_fpc_main(overrides)`。
旧入口 `fpc_coil_default_config`、`fpc_coil_main` 仍可用，但会发出 `RectangularFPC:DeprecatedAPI`。

## 输出版本

正式目录固定为：

```text
rectangular_fpc_output/<designName>_yyyyMMdd_HHmm/
```

- 同一分钟同名设计原子替换，失败时恢复旧版本。
- 读取前确认同名 `*_publish.lock` 不存在；若存在，等待其消失后再读。
- 跨分钟保留历史版本。
- `analysisOnly=true` 不创建文件或目录。
- 历史 `fpc_coil_output/` 不迁移、不删除。

输出包括板框、钻孔、逐层中心线/物理铜/反焊盘 DXF，SVG 预览，CSV/TXT 报告及 SHA-256 文件清单。

## 制造检查

默认使用 `jlc_fpc_1oz / standard`：2 / 4 层采用带逐层反焊盘的贯穿通孔并执行完整制造资格判定，失败时拒绝导出；6 / 8 层保留相邻层过孔模型，可导出但标记为 `UNVERIFIED_LAYER_COUNT`。

规则来源：[JLCPCB FPC 能力表](https://jlcpcb.com/capabilities/flex-pcb-capabilities/) 与 [FPC 间距指南](https://jlcpcb.com/help/article/fpc-design-clearance)。

## 测试

MATLAB R2026a：

```matlab
addpath('tests');
run_all_verification();
```

当前套件共 52 项测试，覆盖回归、制造、导出与原子回滚。

DXF 是工程几何，不是完整生产文件；制造前请复核叠层、材料和电气参数。
