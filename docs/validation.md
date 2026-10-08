# Validation

NHPulse currently combines lightweight automated checks with documented manual
reviewer tests. The manual pieces are intentional because several workflow
steps involve MATLAB figure GUIs and STL inspection.

## Dependency Report

```matlab
setNHPulsePath;
report = nhpulseCheckDependencies();
```

This reports obvious missing MATLAB products, functions, and external solver
paths.

## Smoke Test

```matlab
smokeOut = nhpulseRunSyntheticSmokeTest('force', true, 'showFigures', true);
```

The smoke test creates synthetic anatomy, builds a scalp cache, and places a
small custom cap layout. It intentionally stops before long ROAST/GetDP solves.

## Full Synthetic Walkthrough Verification

After running `exampleWalkthrough.m`:

```matlab
verification = nhpulseVerifySyntheticWalkthrough();
```

The verifier checks expected product classes:

- synthetic T1 and hard-label mask,
- scalp and printer-bed mesh caches,
- ear/painted exclusions,
- headpost placement and keepout,
- target voxel selection,
- fit-check STL,
- tES candidate and tES+EEG layout reports,
- Velcro anchor plan,
- final TPE/PLA manufacturing STLs,
- optional real ROAST lead-field result.

## Provenance Self-Tests

```matlab
nhpulseTestManifestRecorder;
nhpulseTestProjectInspection;
nhpulseTestServiceLayer;
nhpulseTestApplicationShell;
```

These fast tests use temporary files only. They verify manifest round trips,
fingerprints, stale dependency propagation, artifact hierarchy checks, project
opening, read-only legacy discovery, and dry-run import behavior.
The service-layer test additionally checks explicit context resolution,
workspace independence, stale-input rejection, and dependency refresh.
The application-shell test opens a hidden project window and verifies project,
subject, run, workflow, and artifact-table population. It also verifies legacy
artifact display and explicit import into a subject-labeled inventory run.

## Manual Checks

For a reviewer-oriented run, inspect:

- crop-plane QC figure,
- ear/painted exclusion GUI or saved exclusion report,
- headpost placement/keepout QC,
- tES growth and EEG layout QC figures,
- Velcro anchor placement QC,
- final manufacturing QC figure,
- exported STL files in slicer or mesh-viewer software.

## Future Test Targets

Planned public-development milestones include small unit tests for config
helpers, file-format generators, mesh-cache fingerprints, exclusion reuse, and
deeper geometry assertions for manufacturing products.
