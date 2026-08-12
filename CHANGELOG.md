# Changelog

## Unreleased

- `fpc_coil_plot` 移入 `private/` 作为内部实现（不再属于公共 API），由 `fpc_coil_main` 在桌面环境自动调用；根目录公共入口收敛为 `fpc_coil_main.m` 与 `fpc_coil_default_config.m` 两个。
- `fpc_coil_plot` 由单窗口 subplot 布局改为与 `previews/` SVG 输出一致的独立窗口：1 个全部层叠放总览窗口 + 每层各 1 个窗口；每层窗口只显示该层铜线路径和相连过孔，焊盘仅 L1，窗口名称带 top/innerN/bottom 角色后缀。
- Added `fpc_coil_plot.m` private figure viewer: `fpc_coil_main` now pops up an interactive MATLAB figure (stacked overview plus one view per layer, showing board outline, copper paths, pads, and vias) after generation when `cfg.enableFigure` (default `true`) is enabled and a desktop is available; headless `-batch` runs skip the popup automatically, and each window can be saved to any MATLAB-supported format from the window menu.
- Kept only `fpc_coil_main.m` and `fpc_coil_default_config.m` as root-level public MATLAB entry points; consolidated implementation into five `private/` modules (including the figure viewer `fpc_coil_plot.m`) and verification into `tests/`.
- Consolidated the duplicated layer-specific examples into `examples/generate_fpc_coil.m`.
- Replaced lead routing with deterministic straight, single-fillet, then dogleg candidate priority; same-priority candidates use the shortest compliant path.
- Restricted PAD_A, series-via, and VOUT lead runs to horizontal/vertical segments with tangent circular transitions, while keeping PAD_B as an independent horizontal return; lower-priority routes stop evaluating as soon as the shortest compliant route in the current class is found.
- Packed hybrid-auto series vias toward their corresponding coil anchors and moved automatic VOUT to the nearest safe body/tab location, shortening coil-side via leads while leaving the right-side PAD_B return free to be longer.
- Corrected tab-via planning so automatic VOUT is treated as a via, not an external pad, when checking V23 clearance; this prevents unnecessary displacement and keeps the via-side leads short.
- Balanced the default right-side pad group at `leadYOffset=1.10 mm`, giving 0.70 mm PAD_A-to-PAD_B copper clearance and 0.65 mm clearance to each horizontal tab edge while keeping VOUT aligned with PAD_B.
- Fixed manual VOUT placement so `manualOutputViaXY` is coordinate-converted and checked against board, pad, via, and copper clearances.
- Changed previews from PNG to `layerCount + 3` white-background vector SVG files: the two compatible overview images, one pad/via placement image, and one image per copper layer; added checks that reject embedded raster images.
- Removed unused configuration fields `outputReturnBendRadius`, `manufacturingTolerance`, and `previewDpi`; renamed `requireSmoothEscapeArcs` to `requireSmoothLeadTransitions` and reject unknown overrides.
- Optimized exact validation with bounding-box/spatial pruning, vectorized spiral sampling, batched DXF parsing, and successful turn-scan geometry caching without reducing sampling density or skipping final validation.
- Expanded behavior-level MATLAB regression coverage to 31 tests for lead selection, raw spiral invariance, nearest automatic via placement, VOUT/series-via classification, balanced right-pad placement, manual VOUT, SVG output, supported layer counts, clearances, angles, self-intersection, DXF readback, and the 12-turn target.

## [Unreleased] - 閲嶆瀯鐗堬紙鍖濇暟涓庤繃瀛?鍦嗚绯荤粺閲嶈璁★級

### Added
- `fpc_coil_calculate_turn_limits.m`锛氬绾︽潫鍖濇暟涓婇檺锛堝搴?闀垮害/鍦嗚/鍐呭湀杩囧瓟鍖哄煙/灏炬澘瀹归噺锛夛紝杩斿洖 `turnLimits` 缁撴瀯銆?- `fpc_coil_plan_vias.m`锛氳繃瀛斾笁妯″紡 `legacy_auto`/`hybrid_auto`/`manual`锛屽唴鍦堜笌灏炬澘杩囧瓟鑷姩妯悜鎺掑垪 + Y 鏂瑰悜姝ヨ繘鎼滅储銆?- `fpc_coil_generate_spiral.m`锛氭暣鏁板湀铻烘棆鐢熸垚锛岀粺涓€杩炴帴鐩镐綅锛坄connectionPhase`/`connectionSide`锛夛紝涓ユ牸鍚屽績涓庢棫鐗堟埅鏂渾瑙掋€?- `fpc_coil_route_smooth_lead.m`锛氶€氱敤骞虫粦甯冪嚎锛堝垏鍚戝渾寮?+ 鐩寸嚎锛夛紝杞悜瑙掕秴杩?90掳 杩斿洖鏄庣‘澶辫触鍘熷洜銆?- `userToInternalXY.m` / `internalToUserXY.m`锛氱敤鎴峰潗鏍囷紙涓讳綋宸︿笅瑙掞級涓庡唴閮ㄥ潗鏍囷紙涓績锛夊弻鍚戣浆鎹€?- 鏂板 20 涓厤缃弬鏁帮紙`minInnerLength`銆乣coilOuterCornerRadiusMode`銆乣cornerOffsetMode`銆乣viaPlacementMode`銆乣manualSeriesViaXY`銆乣recommendedTurnMargin` 绛夛級銆?- 棰勮鍥惧鍔犺繃瀛?鐒婄洏鏂囧瓧鏍囩涓庝富浣撳乏涓嬭鍘熺偣鏍囪锛汣SV 澧炲姞鍙屽潗鏍囩郴鍒椾笌 `placement_region`/`placement_mode`锛涘対鏁版壂鎻?CSV 澧炲姞 `failure_code` 鍒椼€?- 鏂板绀轰緥锛歚examples/generate_4layer_hybrid_auto.m`銆乣examples/generate_4layer_manual_vias.m`銆乣examples/compare_corner_modes.m`銆?
### Removed
- 鍒犻櫎 `recommendedTurns(layerCount)` 灞傛暟纭紪鐮佸嚱鏁颁笌 `turnsPerLayer` 鐨勫眰鏁版淳鐢熼€昏緫锛堝眰鏁板彧褰卞搷杈撳嚭鐩綍鍚嶏級銆?- 鍒犻櫎闅忓眰鏁板彉鍖栫殑鐩镐綅琛ュ伩锛坄phaseStep`/`routingDelta`/`effectiveTurnsPerLayer`锛夛紱`turnsPerLayer` 鐜板湪琛ㄧず姣忓眰瀹為檯鏁存暟鍦堟暟銆?- 鍒犻櫎姝讳唬鐮?`validateConfiguration`锛堝凡琚?`fpc_coil_validate_config.m` 瀹屽叏鏇夸唬锛夊強鏃ц灪鏃?鍒囩嚎寮曠嚎/閫冮€稿紩绾垮疄鐜般€?
### Changed
- 鏈€澶у対鏁帮細`widthBasedMaximumTurns` 鈫?`turnLimits` 澶氬瓧娈碉紱閿欒淇℃伅鏄庣‘鍖哄垎瀹藉害/闀垮害/鍦嗚/鍐呭湀杩囧瓟/灏炬澘瀹归噺銆?- 鏉挎鍦嗚锛坄plateCornerRadius`锛変笌绾垮湀鍦嗚锛坄coilOuterCornerRadiusMode`锛夊交搴曡В鑰︼紱`cornerOffsetMode` 鍖哄垎涓ユ牸鍚屽績涓庢棫鐗堟埅鏂€?- 鎺ㄨ崘鍖濇暟 = 瀹屾暣楠岃瘉涓婇檺 - `recommendedTurnMargin`锛堥粯璁?1锛夈€?- 杩囧瓟鍒伴摐绾块獙璇佷娇鐢ㄧ湡瀹炲紩绾块暱搴︼紙`vias(k).fromLeadPath/toLeadPath`锛夛紝涓嶅啀浣跨敤鍥哄畾 `viaLandingLeadLength` 浼扮畻銆?

## [1.2.0] - 2026-08-04 (修复验证闭环)

### 修复（几何与验证）
- **引线布线方向语义**：`route_smooth_lead` 的圆弧候选按末端共线评分；90° 型几何中
  alpha 恒为负导致实际首段方向 = -t，据此统一各引线 startTangent 符号
  （PAD_A 沿 +spiralTangentStart；层间过孔两侧独立布线：append 侧 -tangentEnd、
  prepend 侧 +tangentEnd 后 flipud；VOUT 沿 -tangentEnd）。
- **短段半圆方案**：目标点距离 ≤ 2×弯曲半径时直接用半圆弧连接（圆心=中点），
  覆盖“水平进入 + 竖直短段”退化几何；衔接角允许 ≤25.8°（角度检查 >90° 兜底）。
- **圆角矩形段布局**：段 1 覆盖右侧直边全长（2a），消除 frac 在 0↔1 跳变处的
  0.71° 折返；四边由线距/边距确定、四角 90° 圆弧连接（用户设计指引）。
- **尾板过孔布局**：可用区域扣除 pad 半径 + 板框净距 + 右端圆角区
  （xMax = 圆角圆心 - (tabRadius + padR + clearance)），修复“过孔到板框间距不足”。
- **DXF 回读统计**：'10'/'20' 计数排除 '90' 声明值行（块顶点数恰为 10 时误计）。
- **手动过孔无效**：NoValidTurnCount 抛出前识别“手动坐标”失败原因，
  直接抛 FPC_Coil:ViaPlanningFailed（含具体过孔名与原因）。

### 新增
- 诊断钩子：引线失败（LEAD FAIL）、角度不足（ANGLE FAIL）、过孔到板框
  （VIA BOARD FAIL）、DXF 声明顶点（DXF DECL）写入 `_diag_stack.log`（排障用）。
