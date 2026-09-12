---
name: coil-fpc-release
description: Audit Coil_FPC release readiness for Circular_FPC_Coil or Rectangular_FPC_Coil. Use for final validation, candidate go/no-go review, tagging, or publishing; skip for routine edits and partial implementations.
---

# Coil_FPC release readiness

Return a reviewable release decision tied to the exact candidate. Identify the candidate
ref, module scope, supported layer counts, and requested external action before checking.

## Checks

1. Inspect Git status, candidate history, and the diff from the intended base. Stop if
   tracked changes are unexplained.
2. Run each affected module's full suite from its root in a fresh MATLAB process:

   ```matlab
   addpath('tests');
   results = run_all_verification();
   assert(~isempty(results));
   ```

3. Generate a canonical artifact with previews enabled and figures disabled. Require the
   validation and manufacturing checks to pass for supported layer counts.
4. Verify the status file, required reports, DXF/SVG outputs, and SHA-256 manifest from
   the returned path. Read rectangular outputs through
   `RectangularFpc.Publish.Read_Committed`.
5. Use `coil-fpc-verification` for the actual Layer 1, last active-layer, and overview
   visual gate. Check that documentation matches public entrypoints, timestamps, supported
   layer counts, and the engineering-DXF boundary.

Return `READY`, `NOT READY`, or `READY WITH DISCLOSED LIMITATIONS`, followed by exact
evidence, blockers, limitations, and the remaining requested action.
