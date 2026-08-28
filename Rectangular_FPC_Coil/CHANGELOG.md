# Changelog

## Unreleased

### Added

- 新公共入口 `rectangular_fpc_main` 与 `rectangular_fpc_default_config`。
- `analysisOnly` 只读分析模式，不创建输出根目录、临时目录或预览文件。
- `jlc_fpc_1oz` 制造规则档案、`standard` / `extreme` 档位和数值规则覆盖。
- 结构化 `validation`、`manufacturing`、`layerPaths`、`turnScan` 及输出文件路径字段。
- 板框、钻孔参考、逐层中心线铜、物理铜和反焊盘 DXF。
- 层映射、制造检查、加工说明和带 SHA-256 的文件清单；发布前执行回读核验。
- 分钟级版本目录 `<designName>_yyyyMMdd_HHmm`，同分钟原子替换并在失败时恢复旧版本。
- 带进程所有者元数据的发布锁，可接管已终止进程遗留的锁并恢复同分钟备份。
- `requestedConfig` 原始请求配置；`config` 记录实际生效配置，推荐匝数与导出报告保持一致。
- 针对制造规则、只读副作用、6/8 层未验证状态、时间戳、回滚和清单的工程化测试。

### Changed

- 项目目录由 `FPC_Coil` 更名为 `Rectangular_FPC_Coil`，正式实现统一使用 `rectangular_fpc_*`。
- 默认输出根目录由 `fpc_coil_output` 改为 `rectangular_fpc_output`；旧输出目录不迁移、不删除。
- 2 / 4 层串联过孔改为带逐层反焊盘的贯穿通孔；内侧引线圆角上限调整为 0.60 mm，以满足非连接层净距。
- 6 / 8 层保留相邻层过孔模型，并在制造报告中标记为未验证工艺。
- 生成流程拆分为只读分析、几何/布线、结构化验证、制造检查和统一原子导出；约 310 行编排引擎不再承担文件系统、几何算法或验证算法职责。
- 报告固定为 01–08：坐标、层映射、设计摘要、匝数扫描、验证、制造、加工说明、清单。
- 新错误标识统一使用 `RectangularFPC:*`，包括无效类型、形状以及 NaN/Inf 配置输入。
- DXF 回读拒绝未知实体；CSV、状态文件、SVG 文件集合和清单按完整语义逐项核验。
- 修复旧 CHANGELOG 的乱码内容，保留可读的变更摘要。

### Compatibility

- `fpc_coil_main` 与 `fpc_coil_default_config` 保留为弃用转发入口，并发出 `RectangularFPC:DeprecatedAPI`。
- 保留 `outputFolder`、`totalLengthMm`、`totalResistanceOhm` 等主要旧结果字段作为别名。
- 保留核心矩形螺旋、电气串联拓扑、默认 4 层 × 12 匝以及 2 / 4 / 6 / 8 层能力。

## 1.2.0 — 2026-08-04

- 修复引线切向与圆弧连接方向。
- 完善尾板过孔布局、手动 VOUT 校验和 DXF 顶点回读。
- 引入完整候选匝数扫描、严格同心圆角和可配置过孔规划。
- 增加分层 SVG 预览、坐标双坐标系和详细验证报告。
