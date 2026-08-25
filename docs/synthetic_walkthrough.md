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

## What Each Step Is Trying To Accomplish

The walkthrough is not just a file-conversion demo. It is meant to show how a
researcher goes from a head model to a manufacturable cap while preserving the
geometry needed for electrical modeling.

### 01 - Synthetic Anatomy

Goal: create a tiny, non-sensitive stand-in for a macaque MRI and tissue-label
volume. The synthetic head lets reviewers exercise the software without real
animal MRI, phone-scan, or lead-field data.

Check: the QC figure should show a simple head-like object with nested tissue
labels. It is intentionally cartoon-like and should not be interpreted as a
scientific model.

### 02 - ROAST-Derived Scalp Surface

Goal: establish the scalp surface that will be used by the capMaker side of
the workflow. In real projects this surface is the common reference for cap
manufacturing, electrode placement, and alignment to additional measurements.

Check: the extracted surface should be a continuous outer head/scalp shell
rather than disconnected fragments.

### 03 - Crop To Printer-Bed Coordinates

Goal: define what part of the head should receive a cap. The crop plane becomes
the 3D-printer bed (`Z=0`) in capMaker coordinates. Rubber/TPE cap geometry is
built only over scalp points above this plane, and later steps keep cap rails
and holders away from the cropped edge by user-configurable margins.

What the user is deciding: where the cap should end. For an EEG/tES cap, the
crop should include the top-level scalp that the cap should cover, while
excluding ventral face/neck regions that are not intended to be part of the
cap.

Check: the cropped mesh should look like the intended cap footprint. It is fine
to be conservative; ears, face regions, implants, and other local keepouts are
handled in later steps.

### 04 - Ear And Painted Exclusions

Goal: mark areas where the cap should not be built even though they survived
the crop. Ears and facial regions can be sensitive, highly curved, or physically
incompatible with electrodes and rails.

What the user is deciding: place spherical exclusions around ears, and paint
specific mesh vertices on the face or other local regions that should not be
used as electrode sites or rail endpoints.

Check: valid scalp vertices should remain over the intended dorsal cap region,
and excluded vertices should cover ears/face without swallowing the whole cap.

### 05 - Headpost Placement And Keepout

Goal: represent cranial implants that affect cap manufacturing and, optionally,
electrical modeling. Neurophysiology animals often have titanium headposts or
other implants. The cap should not be built over the exposed post, and the
implant geometry may be relevant to current-flow models.

What the user is deciding: confirm or refine a simplified headpost placement.
The synthetic demo creates a toy circular implant trace; real projects may use
Polhemus traces, phone scans, CAD/STL models, or other measurements.

Check: the keepout should surround the exposed cylindrical/post portion. For
manufacturing, the keepout is deliberately tighter than the entire buried base
because scalp can often cover implant straps or bases.

### 06 - PLA Fit-Check STL

Goal: make a quick physical scaffold before committing to a long dual-material
print. The fit-check cap tests gross shape and exclusion geometry with a sparse
PLA rail network.

Check: the scaffold should cover the intended cap area, respect ear/implant
keepouts, and include small markers where electrodes would be placed when
requested.

### 07 - Fiducials

Goal: define anatomical landmarks that let measurements from different devices
share a reference frame. Fiducials are especially useful when registering MRI,
digitizer traces, phone scans, or physical measurements.

Check: selected points should correspond to the intended anatomical labels.
Exact labels can be project-specific, but repeated use should be consistent.

### 08 - Brain Target

Goal: choose the brain location the tES montage should try to stimulate. In a
real experiment this might come from an atlas, MRI anatomy, functional data, or
planned recording chamber trajectory.

Check: the target should lie in the modeled brain compartment, and the desired
field orientation should make sense for the scientific question.

### 09-10 - tES Candidate Layout And Growth

Goal: start with a small set of legal candidate electrodes, model or approximate
their lead fields, solve a sparse targeting problem, and then propose additional
candidate sites that may improve targeting.

What the algorithm is doing: the growth step balances predicted stimulation
quality with exploration of under-sampled scalp regions. The default synthetic
run uses dummy lead fields for speed; `syntheticRoast` exercises real ROAST/GetDP
solves.

Check: proposed candidates should stay on legal scalp and outside keepouts.
Sparse optimization should select a small active montage from the candidates.

### 11 - EEG Interleaving

Goal: add EEG electrodes to the remaining cap area without colliding with tES
contacts, ears, implants, or other exclusions. These EEG sites are chosen for
approximately even scalp coverage rather than stimulation targeting.

Check: EEG sites should be distributed over the remaining legal scalp, with no
obvious collisions or placements on excluded regions.

### 11.5 - tES Stimulation Parameters

Goal: display the final tES current recipe in a table that can be reviewed
later from a clean workspace. The same utility can be called with no arguments
for a file picker, or with a saved layout/manufacturing MAT file or tag.

Check: selected tES channels should have balanced anodal and cathodal current,
and the source electrode names should match the sparse optimization result.

### 12 - Dual-Material Manufacturing STL

Goal: convert the layout into printable geometry: TPE/rubber rails and
electrode holders, plus PLA support/underfill for printing. This is the stage
where a cap becomes a slicer-ready object.

Check: electrode holders should be clear through to the scalp, rails should be
connected, keepouts should be respected, and no holders should be clipped by the
printer bed or placed on the underside of the cap.

### 13 - Verification

Goal: give reviewers a lightweight file-level check that the walkthrough
produced the expected classes of outputs.

Check: all required products should pass. Missing optional real lead-field
results are expected if the walkthrough was run in dummy mode.

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
