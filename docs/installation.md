# Installation

This page is the reviewer-oriented setup path for NHPulse. It assumes MATLAB is
available and that the user has cloned the repository.

## Minimal Setup

Start MATLAB from the repository root:

```matlab
setNHPulsePath;
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe');
report = nhpulseCheckDependencies();
```

`setNHPulsePath` adds the repository folders, capMaker helpers, synthetic MWE
tools, and common bundled utility folders. `nhpulseConfigureLocalPaths` writes a
machine-local `local.paths.json` file, which is ignored by git. The dependency
report prints install links and config-field names for missing packages.

If you want folder and executable pickers:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
```

## Expected Local Folders

Generated products should live outside version control, normally under
`outputs/`. Real MRI data, phone/LiDAR scans, animal photos, and printer outputs
should stay in private folders or in a configured external data root.

The generated `local.paths.json` may contain:

- `outputRoot`: generated synthetic examples, QC figures, lead fields, and STL
  products.
- `dataRoot`: private source data for real subjects.
- `roastWorkRoot`: scratch space for ROAST products.
- `spmPath`, `iso2meshPath`, `cvxPath`: optional external MATLAB libraries.
- `getdpExecutable`, `gmshExecutable`: solver/mesh executables for real ROAST
  lead-field runs.

## Dependencies

The synthetic smoke test requires MATLAB, SPM for NIfTI read/write, Image
Processing Toolbox, and Statistics and Machine Learning Toolbox. Real ROAST
lead-field generation additionally requires iso2mesh/TetGen, GetDP, and often
Gmsh. Sparse optimization with CVX is optional for the public synthetic
walkthrough because the tutorial can use a development heuristic.

See [../DEPENDENCIES.md](../DEPENDENCIES.md) for install links and third-party
notices.

## macOS Quarantine

Downloaded MATLAB dependencies on macOS may contain quarantined MEX files or
non-executable helper binaries. After configuring paths, run:

```matlab
nhpulseClearMacQuarantine({'spm', 'cvx', 'iso2mesh'})
```

You can also pass a folder path directly. Restart MATLAB afterward.
