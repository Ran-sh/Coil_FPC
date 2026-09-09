---
name: coil-fpc-verification
description: Verify Coil_FPC MATLAB geometry, terminal routing, manufacturing clearances, and DXF/SVG exports with numerical checks and actual rendered layers. Use for coil geometry changes or candidate artifact reviews; skip for routine prose or Git status queries.
---

# Coil_FPC verification

Use this skill when a result must be tied to final geometry or exported files. Work from
the repository root and read the affected module's README and public config first.

## Evidence by task

- For dimensions, call the public main function with `analysisOnly=true` and read final
  values from the result. Circular final sizing is in `result.effectiveDimensions`; do not
  confuse it with pre-sizing values in `result.config`.
- For code or geometry changes, run focused regressions and the affected module's full
  `run_all_verification` in a fresh MATLAB process.
- For exports, use a fresh temporary output root. Verify the returned output path, status,
  manifest, required DXF/SVG/report files, and manufacturing result together.
- For rectangular committed outputs, use `rectangular_fpc_read_committed`; directory
  existence is not publication evidence.
- For the current circular 4-layer process, read `reports/09_comsol_stackup.csv` for the
  nominal `FPC0420TT-121A` layer order and Z positions. Treat its computed 0.203 mm sum
  as rounded stackup data against the 0.20 mm order option.
- For candidate reviews, bind every artifact and image to the exact commit and CI run.

## Visual gate

Open the MATLAB-generated Layer 1, last active coil layer, and overview. For export or
candidate reviews, render and open the SVGs from the artifact itself. Inspect the terminal
and slot/platform junctions at useful zoom; the last active layer comes from the result,
not an assumption that it is Layer 4.

For the current circular design, preserve these requirements unless the user changes them:

- The default center platform is an axis-aligned 13 x 14 mm rectangle. Four bridges use
  one shared width and remain constrained by the inner ring, line spacing, pads, and
  terminal envelope. A wider bridge may consume a slot.
- Slot boundary corners receive small geometric fillets. There is no separate
  `platformCornerRadius` control.
- The entry and final-layer terminal transitions each contain one tangent arc with sweep
  strictly greater than 90.1 degrees. Reject S bends, consecutive arcs, micro-jogs,
  sharp turns, or an invalid PAD_A/PAD_B/VOUT arrangement. VOUT to PAD_B is straight,
  and rerouting does not rewrite the original spiral samples.
- Through-vias use 0.55/0.31 mm pad/drill sizes and appear on every physical layer. Check
  via-to-board-edge and via-to-non-connected-copper clearances, including the outline
  stroke width. Do not add visible yellow antipad circles or dashed construction geometry.
- Circular previews use yellow board material, a purple outline, translucent cyan slots
  with black boundaries, red/orange/green/blue layer colors, red pads with black outlines,
  and dark-gray vias with black outlines. Keep rectangular antipad rules module-specific.

## Handoff

Record the configuration, final dimensions, tests and counts, artifact/image paths, visual
observations, and rule warnings. A positive nominal clearance does not prove manufacturing
tolerance, and missing images leave visual verification incomplete.
