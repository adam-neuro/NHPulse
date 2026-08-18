# Synthetic MWE Data Tools

This folder holds developer utilities for creating small synthetic inputs for
NHPulse minimal working examples. These are intentionally separate from the
main project functions so the public tutorial fixtures can be refined without
muddying the scientific pipeline.

## Current Entry Point

For a quick end-to-end format/plumbing check that stops before expensive
ROAST solves:

```matlab
setNHPulsePath;
smokeOut = nhpulseRunSyntheticSmokeTest( ...
    fullfile(pwd, 'outputs', 'syntheticMwe', 'nhpulseSyntheticSmoke'), ...
    'force', true, ...
    'showFigures', true);
```

To create only the synthetic input files:

```matlab
setNHPulsePath;
syntheticOut = nhpulseCreateSyntheticRoastReadyData( ...
    fullfile(pwd, 'outputs', 'syntheticMwe', 'nhpulseSynthetic01'), ...
    'force', true, ...
    'showFigure', true);
```

The generator writes a small cartoon macaque-head dataset:

- `*_T1.nii`: T1-like image volume.
- `*_T1_T1orT2_SPM_masks.nii`: ROAST-compatible hard-label mask.
- `*_syntheticReport.mat/json`: a report with a `roastReady` struct.
- optional paired synthetic model/phone-scan fiducial files.
- optional synthetic phone-scan-like PLY/MAT surface.

The ROAST label convention is:

1. white
2. gray
3. CSF
4. bone
5. skin
6. air

## Intended MWE Boundary

The first public MWE should probably start from `syntheticOut.roastReady`
rather than from DICOM import or SPM segmentation. That keeps the example
small and deterministic while still exercising the NHPulse/capMaker layout
and manufacturing path.

These data are for software checks only. They are not anatomically realistic
and should never be used for scientific simulation claims.
