# Coil_FPC repository guidance

MATLAB R2026a generators for circular and rounded rectangular FPC coils.
Preserve the public geometry, electrical, manufacturing-check, and export contracts.

## Repository map

- `Circular_FPC_Coil/`: public entrypoints `circular_fpc_default_config` and
  `circular_fpc_main`; helpers belong in `private/`.
- `Rectangular_FPC_Coil/`: public entrypoints `rectangular_fpc_default_config`,
  `rectangular_fpc_main`, and `rectangular_fpc_read_committed`; helpers belong in
  `private/`.
- Each module has `tests/run_all_verification.m`. The root workflow is
  `.github/workflows/matlab-tests.yml`.
- Load `.agents/skills/coil-fpc-verification/SKILL.md` for geometry or export evidence,
  and `.agents/skills/coil-fpc-release/SKILL.md` for release readiness.

## Stable contracts

- Change only the affected module unless a shared contract requires both.
- Generated DXF, SVG, reports, manifests, and output directories are build products.
- `analysisOnly=true` has no filesystem side effects.
- Preserve rectangular atomic publication, manifest verification, and committed-reader
  protections.
- The current circular manufacturing baseline is JLC `FPC0420TT-121A`: nominal 0.20 mm
  finished thickness and 1/3 oz (0.012 mm) copper. Use the generated stackup report for
  Z positions; do not infer layer spacing from finished thickness alone.
- DXF is engineering geometry, not Gerber or factory approval. Rectangular 6/8-layer
  output remains `UNVERIFIED_LAYER_COUNT` until a verified manufacturing profile exists.
- Treat changes to defaults, result fields, warning/error identifiers, filenames, output
  layout, timestamps, or compatibility wrappers as public-contract changes.

## Execution

Inspect the smallest relevant surface, infer routine choices from code and tests, and
carry authorized work through implementation and proportionate verification. Preserve
unrelated changes. Use a `codex/` branch and separate worktrees for concurrent tasks.
User instructions take precedence over this file and repository skills.
The invoking harness selects the model and reasoning effort; repository guidance only
defines task scope, evidence, and constraints.

## Verification

- Documentation or instruction edits: validate links, commands, metadata, contradictions,
  and the diff.
- Local behavior: run focused tests; public API, geometry, topology, manufacturing, export,
  or cross-cutting changes require the affected module's full runner.
- Run each module in a fresh MATLAB process from its own directory:
  `addpath('tests'); results = run_all_verification();`
- For geometry or export changes, open the generated Layer 1, last active-layer, and
  overview images. Numerical tests alone do not establish a visual pass.
- Report commands, outcomes, and material limitations. Do not push, merge, tag, or publish
  without explicit user direction.

The DSH Crew policy is managed outside this file. Follow its live capability and operator
decision rules when Crew is selected; do not duplicate or weaken that policy.
