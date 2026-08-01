FPC多层线圈程序说明
====================

文件结构
--------
- fpc_coil_main.m：统一入口，用户只修改本文件开头的cfg参数。
- fpc_coil_generate.m：共享生成核心，只读取cfg。
- README_fpc_coil.txt：本说明。

三个MATLAB文件必须放在同一个文件夹中。

运行
----
  fpc_coil_main

切换层数
--------
在fpc_coil_main.m开头修改：

  cfg.layerCount = 2;   % 两层
  cfg.layerCount = 4;   % 四层

参数说明
--------
- useRecommendedTurns=true时自动使用2层10匝、4层6匝。
- useRecommendedTurns=false时使用cfg.turnsPerLayer。
- cfg.pitchMargin是几何生成附加节距，线距验证仍按
  traceWidth+traceSpacing判断。
- 四层会额外增加一整圈相位，使V23落在右侧中部，再经
  viaOuterLandingLeadLength向右侧尾部引出，避免V23压到连接层
  相邻匝；验证目标线距仍为traceWidth+traceSpacing。
- viaInnerBendRadius控制V12/V34内圈逃逸圆角，viaOuterBendRadius
  控制V23外圈逃逸圆角；程序会修剪原路径后生成两侧相切圆弧。
- viaToPadClearance独立控制过孔焊盘到外接焊盘的净距，不再借用
  viaToViaClearance。
- 程序同时输出“宽度理论最大匝数”和“全部几何检查最大匝数”。
  后者从宽度上限向下试算角度、线距、自交、过孔及焊盘检查，实际
  可用匝数不得超过该值。
- 所有用户参数集中在fpc_coil_main.m开头，共享核心不包含
  需要用户手动修改的设计值。

输出目录
--------
fpc_coil_output/
|-- fpc_coil_2layer/
|   |-- dxf/
|   |   |-- L1/
|   |   |-- L2/
|   |-- reports/
|   `-- previews/
`-- fpc_coil_4layer/
    |-- dxf/
    |   |-- L1/
    |   |-- L2/
    |   |-- L3/
    |   |-- L4/
    |-- reports/
    `-- previews/

程序先写入designName_temp临时目录，全部验证和回读通过后才
替换正式目录。运行失败时不修改上一次成功的正式输出目录；
本次失败报告保存在designName_temp/reports中。正式目录中的DXF
属于上一次成功版本，不代表本次参数。

成功生成后，正式目录会写入generation_status.txt，记录生成时间、
参数摘要和SUCCESS状态，用于区分本次成功版本与旧版本。

DXF文件（两层）
--------------
- dxf/L1/01_copper_l1_top.dxf，图层COPPER_L1_TOP
- dxf/L2/02_copper_l2_bottom.dxf，图层COPPER_L2_BOTTOM
- dxf/03_board_outline.dxf，图层BOARD_OUTLINE

DXF文件（四层）
--------------
- dxf/L1/01_copper_l1_top.dxf，图层COPPER_L1_TOP
- dxf/L2/02_copper_l2_inner1.dxf，图层COPPER_L2_INNER1
- dxf/L3/03_copper_l3_inner2.dxf，图层COPPER_L3_INNER2
- dxf/L4/04_copper_l4_bottom.dxf，图层COPPER_L4_BOTTOM
- dxf/05_board_outline.dxf，图层BOARD_OUTLINE

报告和预览
----------
- reports/01_pad_via_coordinates.csv：焊盘和过孔建议坐标。
- reports/02_design_summary.txt：尺寸、匝数、线长、Rdc、坐标摘要。
- reports/03_validation_report.txt：角度、自交、线距、焊盘、
  过孔、DXF回读等检查结果。
- previews/01_preview_full.png：完整预览图。
- previews/02_preview_right_tab.png：右侧局部放大图。

嘉立创EDA导入
-------------
- 单位：跟随DXF（$INSUNITS=4，毫米）。
- 缩放：1。
- 参考点：DXF原点。
- 铜线导入线宽统一设置为 0.20 mm。
- 底层DXF不需要手动镜像，程序已按同一观察方向生成。
- 板框导入板框层，铜线DXF导入对应铜层。

说明
----
- CSV只提供焊盘和过孔建议坐标，程序不直接生成真实焊盘、
  钻孔、覆盖膜和反焊盘。
- 四层过孔工艺必须在EDA和厂家处确认。
- 当过孔与非连接铜层间距不足时，验证报告输出WARN；当前默认V23
  右侧引出方案通常能够通过该项检查。
- 内-内层间过孔会按viaLandingLeadLength生成逃逸引线，避免过孔
  焊盘压到连接层相邻匝。
