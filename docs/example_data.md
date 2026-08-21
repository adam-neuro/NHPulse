# Example Data

The public repository uses generated synthetic data instead of committing real
MRI, phone/LiDAR scan, lead-field, or manufacturing products.

## Why Synthetic Data

Real subject MRI and lead-field outputs are large. Phone/LiDAR scans and
photographs can also contain sensitive animal imagery. Generated synthetic data
let reviewers exercise the software path without downloading private data or
large binary products.

## Current Public Fixture

The synthetic generator writes a cartoon NHP-like head:

- `*_T1.nii`: T1-like image volume.
- `*_T1_T1orT2_SPM_masks.nii`: ROAST-compatible hard-label mask.
- model and phone fiducials.
- phone-scan-like mesh/point products.
- optional toy headpost traces.

Create the inputs through the smoke test or walkthrough:

```matlab
smokeOut = nhpulseRunSyntheticSmokeTest('force', true);
```

or:

```matlab
syntheticOut = nhpulseCreateSyntheticRoastReadyData( ...
    fullfile(pwd, 'outputs', 'syntheticMwe', 'nhpulseSyntheticDemo'), ...
    'subjectId', 'nhpulseSyntheticDemo', ...
    'force', true);
```

## Real Data Guidance

Keep real subject inputs outside git. Configure private roots with
`nhpulseConfigureLocalPaths`, and add subject-specific path entries to
`local.paths.json` only on the machine where those data live.
