# Synthetic Walkthrough

The public walkthrough is [../exampleWalkthrough.m](../exampleWalkthrough.m).
It starts from generated synthetic anatomy so reviewers do not need private MRI,
phone scan, or lead-field data.

## Before Running

From the repository root:

```matlab
setNHPulsePath;
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe');
report = nhpulseCheckDependencies();
```

Then open `exampleWalkthrough.m` and run cells in order.

## Presets

The walkthrough uses `nhpulseExampleConfig` so reviewers do not have to type a
long list of option names.

```matlab
cfg = nhpulseExampleConfig('syntheticReviewer');
```

Supported presets:

- `syntheticReviewer`: default public path; opens GUI steps and uses dummy lead
  fields.
- `syntheticFast`: noninteractive dummy-leadfield run for repeat testing.
- `syntheticRoast`: noninteractive run that uses real ROAST/GetDP lead-field
  solves on the toy head.

Any preset field can be overridden:

```matlab
cfg = nhpulseExampleConfig('syntheticFast', ...
    'showFigures', false, ...
    'nGrowthSteps', 1);
```

## Walkthrough Stages

1. Create synthetic ROAST-ready T1 and hard-label mask files.
2. Build a ROAST-derived scalp surface cache.
3. Crop the scalp into the capMaker printer-bed frame.
4. Define ear and painted manufacturing exclusions.
5. Place a toy headpost and derive a cap keepout.
6. Export a sparse PLA fit-check STL.
7. Mark or reuse model fiducials.
8. Select a target voxel.
9. Build the initial tES candidate layout.
10. Grow tES candidates with dummy or ROAST lead fields.
11. Interleave EEG electrodes around the optimized tES montage.
12. Export final dual-material PLA/TPE cap STLs.
13. Verify generated outputs with `nhpulseVerifySyntheticWalkthrough`.

## Outputs

By default, products are written under:

```text
outputs/syntheticMwe/nhpulseSyntheticDemo
```

The important reviewer outputs are synthetic anatomy, scalp caches, exclusions,
headpost placement/keepout files, a target voxel selection, a fit-check STL,
tES/EEG layout reports, final PLA/TPE STL files, and QC figures.

## Verifying A Completed Run

```matlab
verification = nhpulseVerifySyntheticWalkthrough();
```

If you ran a custom output directory:

```matlab
verification = nhpulseVerifySyntheticWalkthrough(cfg.outputDir, ...
    'subjectId', cfg.subjectId);
```
