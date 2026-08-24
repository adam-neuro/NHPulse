# Configuration

NHPulse uses two configuration layers:

- `local.paths.json` for machine-specific folders and external executables.
- `nhpulseExampleConfig` for tutorial/workflow settings.

## Machine-Local Paths

Create or refresh the local path file:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe');
```

Use GUI pickers:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
```

The generated `local.paths.json` is ignored by git. It is allowed to contain
private paths, but it should not contain scientific source data itself.

You may also edit `local.paths.json` directly. The common fields are:

- `outputRoot`: generated demo files, QC figures, lead fields, STL files, and
  verification products.
- `dataRoot`: optional private source-data root for real MRI or scan products.
- `roastWorkRoot`: scratch/work space for long ROAST jobs.
- `spmPath`: SPM folder containing functions such as `spm_vol.m`.
- `iso2meshPath`: iso2mesh folder containing functions such as `vol2mesh.m`.
- `cvxPath`: CVX folder for sparse optimization.
- `niftiPath`: optional legacy NIfTI helper folder. This can usually remain
  blank because NHPulse includes SPM-backed ROAST compatibility wrappers.
- `getdpExecutable`: full path to `getdp`, `getdp.exe`, or `getdpMac`.
- `gmshExecutable`: full path to `gmsh`, `gmsh.exe`, or on macOS
  `Gmsh.app/Contents/MacOS/gmsh`.
- `extraMatlabPaths`: cell array of additional MATLAB folders to add.

If you unpack dependencies into the repository-local `lib/` folder, exact
folder names are not required for common MATLAB libraries. `setNHPulsePath`
searches under `lib/` for diagnostic files, so `lib/spm12-main` is accepted as
an SPM install as long as it contains `spm_vol.m`.

## Example Presets

Use:

```matlab
cfg = nhpulseExampleConfig('syntheticReviewer');
```

Available presets:

- `syntheticReviewer`: interactive GUI steps, dummy lead fields, full tutorial.
- `syntheticFast`: noninteractive dummy-leadfield run for repeated testing.
- `syntheticRoast`: noninteractive real ROAST/GetDP lead-field run.

Inspect available fields:

```matlab
cfg = nhpulseExampleConfig();
disp(cfg)
```

Override fields by name:

```matlab
cfg = nhpulseExampleConfig('syntheticFast', ...
    'nGrowthSteps', 1, ...
    'nNewCandidatesPerStep', 1, ...
    'showFigures', false);
```

Unknown field names produce an error so misspellings are caught early.

## Common Fields

- `force`: overwrite existing products. Set false after a successful first run
  to reuse saved GUI selections.
- `interactiveSelections`: open picker/refinement GUIs.
- `leadFieldMode`: `dummy` or `roast`.
- `initialTesCandidates`, `nGrowthSteps`, `nNewCandidatesPerStep`: candidate
  layout growth.
- `activeTesChannels`, `nEegChannels`: final montage sizes.
- `fitCheckGridSurfaceMaxFaces`, `finalManufacturingSurfaceMaxFaces`,
  `finalRailSurfaceMaxFaces`: synthetic manufacturing mesh density.
