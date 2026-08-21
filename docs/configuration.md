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
