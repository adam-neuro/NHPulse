# User Manual

NHPulse is organized as a transparent MATLAB workflow rather than a single GUI.
Most users should start with the synthetic walkthrough and then adapt the same
sequence to real subject data.

## Core Idea

The package keeps one capMaker-compatible scalp surface as the manufacturing
geometry, uses ROAST-compatible tissue and lead-field products for electrical
modeling, and records the transformations/exclusions needed to keep implants,
ears, face regions, and printer-bed constraints consistent.

## Public Tutorial Workflow

The supported public tutorial is:

```matlab
setNHPulsePath;
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe');
cfg = nhpulseExampleConfig('syntheticReviewer');
```

Then run [../exampleWalkthrough.m](../exampleWalkthrough.m) cell by cell.

## Real Subject Workflow

A real subject workflow typically replaces the synthetic inputs with:

- subject MRI or ROAST-ready NIfTI/mask products,
- model fiducials selected on the scalp/head surface,
- phone/LiDAR scan or digitizer traces for scalp/headpost localization,
- optional chamber planning and implant keepouts,
- subject-specific electrode count, target voxel, and manufacturing settings.

The high-level sequence remains:

1. Prepare anatomy and tissue labels.
2. Build or update the scalp surface.
3. Crop into printer-bed coordinates.
4. Define ear, painted, face, strap, and implant exclusions.
5. Create initial tES candidates.
6. Generate or approximate lead fields.
7. Optimize sparse tES montage.
8. Grow candidates iteratively if needed.
9. Add EEG electrodes over the remaining valid scalp.
10. Inspect manufacturing geometry.
11. Export fit-check or final cap STLs.

## Interactive Steps

Several functions open MATLAB figures for user selection or refinement:

- fiducial selection,
- crop-plane selection,
- ear/painted exclusion selection,
- target voxel selection,
- headpost or chamber placement.

Most of these write MAT files so a later run can reuse saved decisions. When
debugging a replay, prefer `force=false` after the first successful pass.

## Fit-Check Before Final Manufacturing

For new subjects or newly warped scalp surfaces, a sparse PLA fit-check cap is
often faster and safer than jumping directly to a full dual-material print. The
fit-check scaffold exercises the same crop/exclusion geometry while avoiding
the longer PLA/TPE manufacturing path.

## Lead-Field Modes

The public walkthrough supports two lead-field modes:

- `dummy`: fast software check; not physically meaningful.
- `roast`: real ROAST/GetDP finite-element solve on the synthetic head.

Real experiments should use real ROAST/GetDP lead fields for final modeling and
should treat dummy lead fields only as development plumbing.

## Data Hygiene

Do not commit real MRI data, phone/LiDAR scans, animal photographs, lead-field
results, STL/G-code products, or local path files. The `.gitignore` is set up
to keep these products out of the public repository.
