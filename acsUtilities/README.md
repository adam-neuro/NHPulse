# ACS Utilities

Small project utilities for keeping machine-specific paths and generated
data products out of the source tree.

## Local Paths

Path resolution is centralized in `acsPaths.m` and `acsSubjectPath.m`.
For a fresh clone, run this from the repository root:

```matlab
setNHPulsePath;
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe');
```

This creates `local.paths.json` with demo-friendly defaults. To choose local
folders with dialogs, run:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
```

`acsPaths` checks, in order:

1. Function name-value overrides.
2. Environment variables such as `ACS_BOX_ROOT`, `ACS_DATA_ROOT`, and
   `ACS_OUTPUT_ROOT`.
3. A local `local.paths.json` file in the repository root or `acsUtilities/`.
4. Common Box locations on Windows and macOS.

`local.paths.json` is ignored by git. You can edit it directly after it is
generated, or use `acsUtilities/local.paths.example.json` as a reference.
The main fields are:

- `outputRoot`: generated files, QC figures, lead fields, and STL products.
- `dataRoot`: optional private source data such as real MRI or scan exports.
- `roastWorkRoot`: scratch/work products from long ROAST jobs.
- `spmPath`, `iso2meshPath`, `cvxPath`, `niftiPath`: optional external
  MATLAB dependency folders.
- `getdpExecutable`, `gmshExecutable`: optional solver/viewer executable paths.
- `inpolyhedronPath`: mesh voxelization helper; the public repo includes this
  under `acsUtilities/inpolyhedron.m`.

Subject aliases live in the per-subject `aliases` array in
`local.paths.json`. Use a canonical subject key that is a valid MATLAB
field name, such as `M2107`, then list scanner IDs and lab nicknames as
aliases:

```json
"subjects": {
  "M2107": {
    "aliases": ["2107", "21-07", "M21-07", "reeses"],
    "mprageInitial": "..."
  }
}
```

## Generated Products

Generated images, meshes, ROAST results, template products, and cap caches
should be written under `acsPaths().outputRoot` or another explicitly
configured external folder. The repository root `.gitignore` excludes the
default `outputs/` folder and common large neuroimaging/modeling products.

## DICOM Anatomy Import

Use `acsImportDicomAnatomy` as the first individual-subject preprocessing
step. It converts a DICOM series into a canonical NIfTI plus an import
report, without attempting segmentation or registration.

Example:

```matlab
out = acsImportDicomAnatomy('M2107', ...
    'verbose', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

## Raw Volume Orientation Labeling

Use `acsLabelVolumeOrientation` when scanner/header orientation may be
wrong and you need to label the raw voxel-array dimensions directly. The
viewer does not use NIfTI affine/header orientation to reorient the data.
It displays three linked raw slice views through one voxel. Use the sliders
to move through dimensions 1-3, or click a slice to update the other two
dimensions, then enter a three-character code such as `ras`.

The same viewer can also be used as a target voxel picker. `out.currentVoxel`
always contains the final crosshair position. For multiple targets, pass
`'voxelSelectionMode','multiple'`, click through the volume, and press `A` or
the Add voxel button for each target. The selected target list is returned in
`out.selectedVoxels`; if no explicit target was added, `selectedVoxels` falls
back to `currentVoxel`.

Example:

```matlab
out = acsLabelVolumeOrientation( ...
    'C:/path/to/M2107_T1.nii', ...
    'orientationCode', 'ask', ...
    'saveFigures', true);
```

To inspect without entering a code:

```matlab
out = acsLabelVolumeOrientation( ...
    'C:/path/to/M2107_T1.nii', ...
    'orientationCode', '');
```

For later scripted calls, pass a known code directly:

```matlab
out = acsLabelVolumeOrientation( ...
    'C:/path/to/M2107_T1.nii', ...
    'orientationCode', 'ras', ...
    'showFigures', false);
```

## Macaque TPM Segmentation

Use `acsSegmentAnatomyWithTpm` after DICOM import to run SPM unified
segmentation with a six-channel macaque TPM. By default it looks for
`defaultMonkeyTpm.nii` under `acsPaths().dataRoot/MRIs/atlasfiles`, with a
temporary fallback to the historical `myTpm.nii` name.

For real rhesus macaque workflows, the default `templateMaker` atlas-prior
filenames (`gm_priors_ohsu+uw.nii`, `wm_priors_ohsu+uw.nii`, and
`csf_priors_ohsu+uw.nii`) correspond to the 112RM-SL rhesus macaque atlas
priors described by McLaren et al. (2009). The generated six-channel
ROAST/SPM-style TPM is a local derived product and should stay outside git.
See [../CITATION.md](../CITATION.md) and [../DEPENDENCIES.md](../DEPENDENCIES.md)
for citation and download notes.

The TPM channel order is assumed to match ROAST/SPM:

1. gray matter
2. white matter
3. CSF
4. bone
5. skin/scalp
6. air/background

Example:

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'verbose', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

SPM's affine regularization is exposed as `affineRegularization`. The
default is `mni`, matching SPM/ROAST defaults. For comparison runs, use
`segmentationTag` so each run is written to a separate ignored output
subfolder:

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'segmentationTag', 'affreg_subj', ...
    'affineRegularization', 'subj', ...
    'forceCopyInput', true, ...
    'forceSegmentation', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

Useful `affineRegularization` values are `mni`, `subj`, `none`, and `''`.
Here `none` still performs affine registration but disables affine
regularization; `''` skips the initial affine registration.

The segmentation wrapper does not trust header orientation. It uses raw
voxel orientation codes, writes RAS-oriented working copies of the T1 and
TPM into the ignored segmentation folder, and passes those derived files to
SPM. The current defaults are `t1Orientation='sar'` for M2107 and
`tpmOrientation='ras'` for `defaultMonkeyTpm.nii`:

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'segmentationTag', 'ras_inputs', ...
    't1Orientation', 'sar', ...
    'tpmOrientation', 'ras', ...
    'forceCopyInput', true, ...
    'forceSegmentation', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

Use `ask` for either source to launch `acsLabelVolumeOrientation` from the
segmentation workflow:

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    't1Orientation', 'ask', ...
    'tpmOrientation', 'ask', ...
    'tpmOrientationVolume', 1, ...
    'showFigures', true);
```

By default the wrapper also creates subject-derived head/interior masks from
the RAS T1 and passes the head mask to SPM as an explicit mask. These masks
are written under the ignored segmentation output folder:

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'segmentationTag', 'head_masked', ...
    'spmMaskMode', 'head', ...
    'forceSegmentation', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

Useful `spmMaskMode` values are `none`, `head`, `innerHead`, and
`brainSearch`. `head` is the conservative default and mainly suppresses
outside-head speckles. `innerHead` and `brainSearch` are tighter masks for
debugging or later brain-focused registration experiments. You can provide a
custom mask directly with `subjectMaskFile`.

Standalone mask QC is also available:

```matlab
out = acsMakeSubjectMasks( ...
    'C:/path/to/M2107_T1_RAS_fromSAR.nii', ...
    'showFigures', true, ...
    'saveFigures', true);
```

SPM's explicit mask constrains the segmentation sampling/classification
stage, but it does not solve the harder problem of registering a
brain-only TPM to a whole-head T1 by itself. For that we will likely add a
separate brain-focused registration/masking step.

When figures are enabled, the wrapper saves two soft-probability contour
figures plus a maximum-probability tissue figure. The latter displays the
winner-take-all tissue identity at each displayed voxel, which is useful for
distinguishing true tissue-label errors from overlapping probability
contours:

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'segmentationTag', 'map_qc', ...
    'forceSegmentation', true, ...
    'showFigures', true, ...
    'saveFigures', true, ...
    'qcMaxTissueMinProbability', 0.35);
```

Because T1 anatomy does not reliably distinguish skull from other low-signal
structures, the wrapper applies a subject-specific cranium-shell correction
to the bone probability map by default. It builds a fuzzy shell from the
merged brain probabilities, boosts bone inside that shell, suppresses bone
outside it, and renormalizes all six tissue maps. The original SPM `c1..c6`
files are left intact; corrected files are written with a `shellPrior` suffix
and used for QC/reporting.

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'segmentationTag', 'shell_bone', ...
    'forceSegmentation', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

Useful bone options:

```matlab
'boneMode', 'shellPrior'          % default; strong but not deterministic
'boneMode', 'spm'                 % use raw SPM c4
'boneMode', 'shellOnly'           % deterministic shell-style replacement
'boneShellDilateMm', 5
'boneShellFloor', 0.05
'boneShellBoost', 8
'boneShellAdd', 0.20
```

The wrapper also writes a ROAST-ready hard tissue label volume by default,
using the active probability maps after any bone correction. Labels follow
ROAST order: `0 background`, `1 white`, `2 gray`, `3 CSF`, `4 bone`,
`5 skin`, `6 air`. Low-confidence voxels inside the configured head mask are
assigned to air; voxels outside the head mask remain background. The label
volume is written directly to ROAST's expected mask filename for the active T1,
avoiding an extra adapter copy:
`<activeT1>_T1orT2_SPM_masks.nii`. A small `<activeT1>_T1orT2_seg8.mat`
metadata alias is also created so ROAST can skip its own SPM segmentation.

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'segmentationTag', 'roast_labels', ...
    'boneMode', 'shellOnly', ...
    'forceRoastLabels', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

Useful label options:

```matlab
'makeRoastLabels', true
'roastLabelMinProbability', 0.35
'roastLabelConstraintMask', 'head'
```

The wrapper reports these files under `out.roastReady`. For an initial ROAST
smoke test, pass `out.roastReady.t1File` to `roast` and keep resampling off so
the filenames continue to match:

```matlab
recipe = {'Fp1', 1, 'P4', -1};
roast(out.roastReady.t1File, recipe, 'resampling', 'off');
```

### capMaker Custom Layouts

Use `acsMakeRoastCapMakerLayout` to generate a ROAST custom electrode layout
from capMaker's simple automatic target placement. By default the utility
uses capMaker's outer scalp mesh for target selection, transforms those
targets into the ROAST voxel frame, snaps them to the ROAST outer-head
surface, and writes `<activeT1>_customLocations` next to the ROAST-ready T1.
The written coordinates are in the voxel coordinate frame ROAST expects when
resampling is off. By default the capMaker surface is now built from the same
ROAST-ready RAS T1 that is passed to ROAST, not from the original DICOM folder.
That keeps the coordinate transform deterministic: the exporter inverts the
capMaker print translation and crop-plane alignment rotation, then lands
directly back in the ROAST RAS voxel lattice.

The capMaker plots are in its print frame, where `Z = 0` is the 3D printer
bed; the ROAST QC panel is in ROAST's scaled image/mesh frame, so the numeric
origins are not expected to match. If you explicitly pass `dicomDir`, the
legacy DICOM route is used and `capMakerVoxelOrientation` can still be
overridden for debugging. Large snap distances trigger a warning because they
usually indicate a transform mismatch.

To choose the capMaker crop plane interactively, use
`'cropPlaneMode', 'select'`. Drag in the 3D view to rotate the camera, scroll
to move the plane, Ctrl-click or Command-click to redirect the crop axis, and
Alt-click or Option-click to move the plane through a picked scalp point.
Press `x`, `y`, or `z` to reset the camera to a canonical view along that
world axis. The GUI renders a decimated display mesh by default while retaining
the full-resolution surface for plane placement and picking.
The accepted plane is saved as a small MAT file and a human-readable JSON
file under the subject's ignored `capMaker` work folder. It is separate from
the cached scalp mesh so it can be inspected and reused reproducibly.

```matlab
layout = acsMakeRoastCapMakerLayout(out, ...
    'surfaceSource', 'capMaker', ...
    'cropPlaneMode', 'select', ...
    'forceLayout', true, ...
    'showFigures', true, ...
    'saveFigures', true, ...
    'verbose', true);

% For a later non-interactive run that requires the saved plane:
layout = acsMakeRoastCapMakerLayout(out, ...
    'surfaceSource', 'capMaker', ...
    'cropPlaneMode', 'reuse', ...
    'forceLayout', true, ...
    'showFigures', true);
```

The default `cropPlaneMode='auto'` reuses a saved crop plane when one exists
and otherwise uses capMaker defaults. Use `'default'` to ignore any saved
selection. If a saved plane changes, the wrapper recomputes the scalp mesh
instead of silently loading a stale cache.
Use `cropPlaneMode='autoSelect'` when you want the wrapper to reuse a saved
crop plane if one exists, but open the crop-plane selector and save a new plane
when none has been defined yet. `forceLayout` controls whether the generated
`customLocations` file is overwritten; the older name `force` is still accepted
as an alias.

If camera movement is still sluggish on a particular machine, lower the
display-only triangle budget without affecting the saved plane geometry:

```matlab
skinOpts = struct('cropGuiOptions', struct('displayMaxFaces', 5000));
layout = acsMakeRoastCapMakerLayout(out, ...
    'cropPlaneMode', 'select', ...
    'skinMeshOptions', skinOpts);
```

```matlab
layout = acsMakeRoastCapMakerLayout(out, ...
    'nElectrodes', 8, ...
    'surfaceSource', 'capMaker', ...
    'forceLayout', true, ...
    'showFigures', true, ...
    'saveFigures', true);

recipe = {layout.names{1}, 1, layout.names{2}, -1};
roast(out.roastReady.t1File, recipe, ...
    'resampling', 'off', ...
    'simulationTag', 'capMakerSmoke');
```

The established electrode-placement behavior remains available as
`placementMode='footprintCvt'` and is still the default. It fits a 2-D
footprint, distributes electrodes in that footprint, and projects them down
onto the cap. To test mesh-native placement, pass
`placementMode='surfaceGeodesic'` through `targetOptions`:

```matlab
targetOpts = struct( ...
    'placementMode', 'surfaceGeodesic', ...
    'edgeMarginMM', 10, ...
    'vizSurfaceGeodesic', true);

layout = acsMakeRoastCapMakerLayout(out, ...
    'surfaceSource', 'capMaker', ...
    'targetOptions', targetOpts, ...
    'force', true, ...
    'showFigures', true, ...
    'saveFigures', true, ...
    'verbose', true);
```

The surface-geodesic mode detects the fabricated printer-bed patch, excludes
its vertices, excludes an additional geodesic margin from its crop rim, and
computes electrode spacing only across the remaining scalp graph. Steep scalp
surfaces remain eligible by default. Bilateral pairs also treat the midline as
a special edge: paired targets must remain at least `midlineMarginMM` lateral
X distance from `symmetryPlaneX`. This defaults to `edgeMarginMM`; odd layouts may still
include one dedicated midline target. Set `visibleFromAbove=true` as an
optional extra safeguard if a particular cap should retain the legacy
top-visible constraint. Mesh-specific ear exclusion spheres and the headpost
disk are applied before sampling. Additional implanted-material avoidance
regions can be specified in capMaker print coordinates:

```matlab
targetOpts.exclusionCenters = [12 -8 34; -12 -8 34];
targetOpts.exclusionRadiusMM = 8;
```

For subject-specific ear avoidance, `acsMakeRoastCapMakerLayout` now uses the
current capMaker scalp mesh to load reusable left/right exclusion spheres, or
opens the selector when no saved file exists. The first proposal places the
spheres at extreme left/right points near the caudal lower third of the mesh,
with an initial diameter equal to one quarter of the left-right scalp range.
In the GUI, Shift-click the scalp to move the active sphere center near the
clicked point, use arrow keys plus `u`/`d` to nudge the center in X/Y/Z, and
use `i`/`o` or the mouse wheel to shrink/grow the radius:

```matlab
layout = acsMakeRoastCapMakerLayout(out, ...
    'surfaceSource', 'capMaker', ...
    'earExclusionMode', 'auto', ...
    'showFigures', true, ...
    'saveFigures', true);
```

`earExclusionMode='auto'` opens the editor only when the mesh-specific
ear-exclusion file does not exist, then reuses that file quietly on later runs.
Use `earExclusionMode='always'` to revise saved spheres, or
`earExclusionMode='never'` to avoid opening the editor and use the saved file
or automatic proposal quietly. The low-level selector
`acsSelectEarExclusionSpheres` remains available when you want to inspect or
edit the saved file directly.

`surfaceGeodesic` requires the triangulated capMaker scalp surface. The
point-cloud-only debugging route `surfaceSource='roastLabels'` continues to
support `footprintCvt`.

For EEG coverage layouts, use `placementMode='surfaceVoronoi'`. This mode
builds compact geodesic Voronoi cells over the anatomical scalp coverage
surface above the printer bed, while applying edge, ear, headpost, tES, and
other exclusion rules only when snapping each cell center to a legal electrode
placement vertex:

```matlab
eegTargetOpts = targetOpts;
eegTargetOpts.placementMode = 'surfaceVoronoi';
eegTargetOpts.preferSymmetry = false;
eegTargetOpts.midlineMarginMM = 0;
eegTargetOpts.voronoiIterations = 10;
eegTargetOpts.voronoiSnapMode = 'spacingAware';
eegTargetOpts.voronoiSpacingWeight = 4;
eegTargetOpts.voronoiMinSpacingFraction = 0.75;
eegTargetOpts.vizSurfaceVoronoi = true;
```

The Voronoi QC figure shows colored coverage cells, legal placement vertices,
final electrodes, per-cell area balance, and nearest-neighbor geodesic spacing.
Set `voronoiSnapMode='centroid'` to recover the older centroid-only snapping
behavior. Switch back to
`placementMode='surfaceGeodesic'` to recover the earlier greedy farthest-point
sampler.

For debugging, set `'surfaceSource', 'roastLabels'` to place electrodes from
the filled ROAST label surface instead of the capMaker scalp mesh.

### capMaker Lead Fields

After validating a capMaker layout with a small forward simulation, generate
a reusable ROAST lead field over the custom candidate positions. The ACS
wrapper defaults to capMaker candidates. Its final candidate is used as the
mathematical reference unless another candidate is selected explicitly:

```matlab
lf = acsGenerateRoastLeadField(layout, ...
    'simulationTag', 'M2107_capMakerGeo_lf8', ...
    'resampling', 'off');
```

This calls ROAST's existing lead-field solver path. It places and meshes all
candidate electrodes once, then solves one unit-current basis field for each
non-reference candidate against the reference. All custom candidate contacts
remain in the modeled domain during each solve; passive contacts receive zero
current. The resulting `A_all` matrix can be linearly combined to evaluate
new montages without another FEM solve.

The wrapper also preserves the tiny custom-location text file under the
lead-field tag. ROAST still receives its expected mutable
`<T1 stem>_customLocations` file, while older and newer candidate layouts can
be traced back to the coordinates that generated each lead field.

For a strict superposition check, ask the validator to run one direct GetDP
solve on the existing lead-field mesh. The inactive candidates deliberately
receive zero current so that the direct and reconstructed fields represent
the same physical model. The temporary direct field file is removed after QC
by default:

```matlab
check = acsValidateRoastLeadField(layout.t1File, ...
    lf.simulationTag, ...
    lf.validationRecipe, ...
    'showFigures', true, ...
    'saveFigures', true);
```

For local development when the real ROAST/GetDP lead-field solve is too slow,
use `acsGenerateDummyRoastLeadField`. It writes the `A_all`,
`*_roastOptions.mat`, mesh MAT, custom-location snapshot, and request report
that the ACS optimizer expects, but marks every report and options struct with
`dummy=true` and uses a `DUMMY_...` simulation tag. These fields are smooth
synthetic patterns for exercising downstream code only.

```matlab
lf = acsGenerateDummyRoastLeadField(layout, ...
    'simulationTag', 'DUMMY_M2107_capMakerGeo_lf16', ...
    'force', true);
```

Skip `acsValidateRoastLeadField` for dummy outputs; that validation checks
superposition against a direct GetDP solve and requires real ROAST mesh products.

The original ROAST 10-10 lead-field behavior remains available explicitly:

```matlab
lfLegacy = acsGenerateRoastLeadField(layout.t1File, ...
    'candidateMode', 'legacy1010', ...
    'simulationTag', 'legacy1010LeadField');
```

### Sparse capMaker Targeting

Choose a sparse montage from the capMaker candidates without any additional
FEM solves. Provide the target in the voxel coordinates of the modeled RAS T1
and provide an explicit desired field direction. Using explicit subject-space
inputs avoids the human-template assumptions in ROAST's MNI and radial
defaults:

```matlab
% Use the linked-slice viewer to choose a target in the modeled RAS T1.
% Click the desired location(s), press A/Add voxel for each one, then press
% Enter at the orientation prompt.
pick = acsLabelVolumeOrientation(layout.t1File, ...
    'orientationCode', 'ask', ...
    'voxelSelectionMode', 'multiple', ...
    'allowSkip', true);
targetVoxel = pick.selectedVoxels;

sparse = acsOptimizeSparseRoastLeadField(layout.t1File, ...
    lf.simulationTag, ...
    targetVoxel, ...
    'orientation', [0 0 1], ...
    'targetRadiusMm', 2, ...
    'activeElectrodeCount', 4, ...
    'targetingTag', 'smokeTarget01', ...
    'showFigures', true, ...
    'saveFigures', true);
```

The utility defaults to a ROAST-style weighted least-squares focal objective
(`optType='wls-l1per'`). It asks for a desired field at the target, penalizes
field elsewhere in the brain, then refines the relaxed solution down to the
requested number of active contacts. The default total injected current is
2 mA and the corresponding four-electrode bound is 1 mA per electrode.

Two tuning knobs matter most:

```matlab
'desiredIntensityVm', 1   % lower this if every selected contact rails
'focalityK', 0.02         % lower = more off-target penalty; higher = more target intensity
```

The earlier maximum-directional behavior remains available as
`optType='max-l1per'`. It is useful as a ceiling check, but it is expected to
drive contacts to their current limits because it does not penalize off-target
field.

To cross-check the scalable solution during development, explicitly request
exhaustive enumeration. With eight candidates, this searches only
`nchoosek(8,4) = 70` subsets:

```matlab
sparseExactCheck = acsOptimizeSparseRoastLeadField(layout.t1File, ...
    lf.simulationTag, ...
    targetVoxel, ...
    'orientation', [0 0 1], ...
    'optType', 'max-l1per', ...
    'activeElectrodeCount', 4, ...
    'searchMode', 'exhaustiveCvx', ...
    'targetingTag', 'smokeTarget01_exhaustive');
```

The exhaustive mode has a safety limit because it is intended for small
development sets, not the eventual 128-channel search.

Visualize the reconstructed field immediately from the lead-field sum,
without another mesh or GetDP solve:

```matlab
fieldQc = acsVisualizeSparseRoastLeadField(sparse, ...
    'showFigures', true, ...
    'saveFigures', true);
```

The viewer colors the gray-matter surface by electric-field magnitude, marks
the selected electrodes and target, and shows target-centered sagittal,
coronal, and axial mesh cuts.

### Incremental 16-candidate Test

Before replacing the current eight-contact layout, snapshot its location
file using the updated wrapper without rerunning ROAST:

```matlab
lf8Archive = acsGenerateRoastLeadField(layout, ...
    'simulationTag', 'M2107_capMakerGeo_lf8', ...
    'resampling', 'off', ...
    'execute', false);
```

Then create and inspect a denser capMaker layout. Reuse the saved crop plane
and scalp mesh:

```matlab
targetOpts16 = struct( ...
    'placementMode', 'surfaceGeodesic', ...
    'edgeMarginMM', 10, ...
    'midlineMarginMM', 10, ...
    'vizSurfaceGeodesic', true);

layout16 = acsMakeRoastCapMakerLayout(out, ...
    'nElectrodes', 16, ...
    'surfaceSource', 'capMaker', ...
    'targetOptions', targetOpts16, ...
    'force', true, ...
    'showFigures', true, ...
    'saveFigures', true, ...
    'verbose', true);
```

After the candidate placement QC looks reasonable, generate the denser lead
field. This is the expensive step: 16 candidates require 15 basis solves.

```matlab
lf16 = acsGenerateRoastLeadField(layout16, ...
    'simulationTag', 'M2107_capMakerGeo_lf16', ...
    'resampling', 'off');
```

Select eight contacts with the scalable global solve and visualize the
reconstructed field:

```matlab
sparse16 = acsOptimizeSparseRoastLeadField(layout16.t1File, ...
    lf16.simulationTag, ...
    targetVoxel, ...
    'orientation', [0 0 1], ...
    'activeElectrodeCount', 8, ...
    'optType', 'wls-l1per', ...
    'desiredIntensityVm', 0.5, ...
    'focalityK', 0.02, ...
    'targetingTag', 'smokeTarget16choose8', ...
    'showFigures', true, ...
    'saveFigures', true);

fieldQc16 = acsVisualizeSparseRoastLeadField(sparse16, ...
    'showFigures', true, ...
    'saveFigures', true);
```

If the selected currents all sit at `+/- maxCurrentPerElectrodeMa`, the
desired field is probably too high for the requested focality. Try lowering
`desiredIntensityVm`. If the target is hit but the map is too broad, try a
smaller `focalityK`; if the solution is too weak at the target, try a larger
`focalityK`.

### Surrogate-Guided Candidate Growth

Use `acsProposeRoastCandidateGrowth` to grow a candidate set before spending
time on another ROAST lead-field run. The utility samples legal virtual
locations on the capMaker scalp mesh, uses Gaussian RBF regression to predict
reduced lead-field features from the existing real leadfield, and greedily
selects points expected to reduce the current WLS residual. The current
default acquisition mode is upper-confidence-bound (`acquisitionMode='ucb'`),
which balances predicted utility with distance/uncertainty relative to the
already sampled electrode locations.

The virtual pool is drawn from the eligible vertices on the existing capMaker
scalp mesh. If fewer vertices are available than `poolSize`, the utility warns
and scores all available vertices. By default it also enforces a 12 mm
center-to-center spacing: 10 mm for the BioSemi-style plastic housing
footprint plus 2 mm clearance. For denser candidate searches, recompute the
capMaker scalp mesh with less decimation, then regenerate the base layout and
leadfield from that mesh.

First inspect a proposal without overwriting the active ROAST
`customLocations` file:

```matlab
grow = acsProposeRoastCandidateGrowth(layout16, sparse16, ...
    'nNew', 8, ...
    'poolSize', 128, ...
    'kernelSigmaMm', 'auto', ...
    'proposalTag', 'grow16to24_target01', ...
    'showFigures', true, ...
    'saveFigures', true);
```

If the QC looks sensible, write an expanded capMaker/ROAST layout using the
exact proposed print-frame coordinates:

```matlab
grow = acsProposeRoastCandidateGrowth(layout16, sparse16, ...
    'nNew', 8, ...
    'poolSize', 128, ...
    'proposalTag', 'grow16to24_target01', ...
    'makeLayout', true, ...
    'forceLayout', true, ...
    'showFigures', true, ...
    'saveFigures', true);

preflight24 = acsVisualizeRoastElectrodeLayout(grow.expandedLayout, ...
    'electrodeModel', 'biosemiPin', ...
    'showFigures', true, ...
    'saveFigures', true);

lf24 = acsGenerateRoastLeadField(grow.expandedLayout, ...
    'simulationTag', 'M2107_capMakerGeo_lf24_surrogate01', ...
    'electrodeModel', 'biosemiPin', ...
    'resampling', 'off');
```

For faster iterative growth, write a surrogate-expanded leadfield product
instead of running ROAST on every intermediate candidate set:

```matlab
lf24Approx = acsGenerateApproximateExpandedRoastLeadField( ...
    layout16, lf16, grow.expandedLayout, ...
    'simulationTag', 'M2107_capMakerGeo_lf24_approxGrow01', ...
    'referenceElectrode', lf16.referenceElectrode);
```

This copies existing `A_all` columns and appends Gaussian RBF-predicted
columns for newly proposed contacts while keeping the same reference electrode.
Downstream sparse optimization can read the resulting ROAST-style files, but
the product is marked approximate in `*_roastOptions.mat` and is intentionally
ignored by exact lead-field cache matching. Because adding contacts changes
the ROAST electrode domain and mesh, do not treat surrogate-expanded columns
as final physics; run a fresh exact leadfield on the final candidate set.

`electrodeModel='biosemiPin'` approximates the conductive Ag/AgCl pin as a
ROAST disc with radius 1 mm and height 5 mm, places its lower end 0.5 mm above
the scalp, and surrounds it with a 2.5 mm radius by 2.5 mm high gel pool.
ROAST does not model the surrounding plastic housing as conductive material;
the housing footprint is handled by the candidate-spacing constraints above. Use
`electrodeModel='roastDefault'` to recover ROAST's default 6 mm radius disc.
`acsVisualizeRoastElectrodeLayout` is a preflight visualization/check that
reports ROAST-domain collision risk, including gel-pool overlap, and
housing-risk nearest-neighbor pairs before ROAST voxelizes the electrodes.

After sparse tES targeting, use `acsAssembleTesEegCapMakerLayout` to build a
combined cap layout for manufacturing:

```matlab
eegTargetOpts = targetOpts;
eegTargetOpts.placementMode = 'surfaceVoronoi';
eegTargetOpts.preferSymmetry = false;
eegTargetOpts.midlineMarginMM = 0;

combinedLayout = acsAssembleTesEegCapMakerLayout(grow.expandedLayout, sparse, ...
    'nTes', 8, ...
    'nEeg', 8, ...
    'eegPreferSymmetry', false, ...
    'eegMidlineMarginMM', 0, ...
    'eegExclusionRadiusMm', 12, ...
    'eegTargetOptions', eegTargetOpts, ...
    'forceLayout', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

The EEG sites are placed with the same capMaker surface rules while treating
the selected tES sites as exclusion centers. EEG symmetry is off by default in
this assembly step to improve coverage around fixed tES sites. By default,
asymmetric EEG placement also removes the midline buffer while preserving the
base cap edge margin and ear/headpost exclusions. Pass `'eegPreferSymmetry',
true` to restore bilateral pairing. The combined layout records `siteRoles`,
`tesCurrentsMa`, `eegTargetOptions`, and the source tES electrode names.
`forceLayout` controls whether the generated EEG-only and combined layout files
are overwritten; the older name `force` is still accepted as an alias.

To predict what the passive EEG contacts would measure during a selected tES
montage, run a direct ROAST solve from the combined layout. The utility maps
recipe names from the sparse candidate layout onto the combined tES names,
adds all EEG contacts as zero-current passive electrodes, and samples nodal
voltage over each EEG electrode domain:

```matlab
tesRecipe = sparse.recipe;

eegPrediction = acsPredictEegVoltagesFromTes(combinedLayout, tesRecipe, ...
    'simulationTag', 'M2107_tes8_eeg8_voltageCheck', ...
    'electrodeModel', 'biosemiPin', ...
    'resampling', 'off', ...
    'sampleDomain', 'electrode', ...
    'referenceMode', 'meanEeg', ...
    'showFigures', true, ...
    'saveFigures', true);

eegPrediction.eegTable
```

The default reference is the mean of the sampled EEG channels. Use
`referenceMode='none'` for raw arbitrary-reference GetDP potentials, or pass an
EEG channel name to reference all channels to that contact.

Visualize the sampled EEG voltage topography on the capMaker scalp mesh:

```matlab
eegTopo = acsVisualizeEegVoltageTopography(eegPrediction, combinedLayout, ...
    'valueMode', 'referencedMicroV', ...
    'interpolation', 'rbf', ...
    'showTes', true, ...
    'showFigures', true, ...
    'saveFigures', true);
```

The topography uses a smooth Gaussian interpolation between sparse EEG
channels, so it is a visualization aid rather than a new forward model. Use
`interpolation='nearest'` to inspect channel domains without smoothing, or set
`rbfSigmaMM` to tune the smoothing width.

## Saved Digitizer Traces

The public release does not include a live hardware acquisition GUI. Users can
collect 3D points with their preferred digitizer workflow, then bring saved
fiducial points, scalp traces, implant traces, or electrode-QC points into
NHPulse for registration and visualization.

Several historical utility names still include `Polhemus`; in the public
release, those functions operate on saved point-set files or structs and do
not require Polhemus hardware or MATLAB Instrument Control Toolbox. Point-set
files should provide labels plus coordinates in millimeters, and optional
trace/object groupings for scalp or implant loops.

Use `acsMonkeyLandmarkBullpen` to get the shared macaque landmark list for
model-fiducial selection and external digitizer prompts:

```matlab
landmarkLabels = acsMonkeyLandmarkBullpen('labels');
```

Use `acsRegisterPolhemusFiducials` to align saved digitizer points to MRI,
ROAST, or capMaker coordinates once the corresponding model-space fiducials
have been identified:

```matlab
modelFiducials = acsSelectModelFiducials(combinedLayout, ...
    'fiducialLabels', {'Nas', 'Lpa', 'Rpa'}, ...
    'meshStage', 'fullHead', ...
    'editMode', 'auto', ...
    'showFigures', true, ...
    'saveFigures', true);

registration = acsRegisterPolhemusFiducials( ...
    'C:/path/to/digitizer_session.mat', ...
    modelFiducials, ...
    'modelUnits', 'mm', ...
    'transformType', 'rigid');
```

`acsSelectModelFiducials` defaults to the uncropped full-head fiducial mesh
because `Nas`, `Lpa`, and `Rpa` are usually cropped out of the manufacturing
cap mesh. The selected points are still saved in capMaker print-frame
millimeters, using the same print transform as the cropped cap mesh.
Shift-click the head mesh to place the active fiducial; drag rotates the view.
The registration output transforms every saved digitizer point, not just
`Nas`/`Lpa`/`Rpa`:

For an all-landmark assessment, use the same bullpen labels when selecting
model fiducials and when registering/visualizing the digitizer session:

```matlab
landmarkLabels = acsMonkeyLandmarkBullpen('labels');

modelLandmarks = acsSelectModelFiducials(combinedLayout, ...
    'fiducialLabels', landmarkLabels, ...
    'meshStage', 'fullHead', ...
    'editMode', 'always', ...
    'showFigures', true);

traceQc = acsVisualizePolhemusTraceOnHead( ...
    'C:/path/to/landmarkAssessmentSession.mat', ...
    modelLandmarks, ...
    'fiducialLabels', landmarkLabels, ...
    'showFigures', true);
```

Use `meshStage='cap'` only for non-anatomical points that are known to be on
the cropped cap surface. If a full-head fiducial mesh is missing from an older
cache, rerun the capMaker layout step so the cache is rebuilt with
`TRfiducialHead`.

```matlab
registration.transformedSourcePointsMm   % capMaker print-frame points
registration.registeredObjects           % transformed implant traces
```

For a quick QC overlay of saved scalp or implant traces on the full-head
capMaker mesh, use:

```matlab
traceQc = acsVisualizePolhemusTraceOnHead( ...
    'C:/path/to/headpostTraceSession.mat', ...
    modelFiducials, ...
    'fiducialLabels', {'Nas', 'Lpa', 'Rpa'}, ...
    'showFigures', true, ...
    'saveFigures', true);
```

If the digitizer report contains named `objects`, those are drawn separately.
Otherwise all non-fiducial points are treated as one ordered trace. The output
reports nearest-head-mesh distances for a first-pass registration sanity
check.

The transform is row-vector based:

```matlab
pointsModelMm = pointsDigitizerMm * registration.rotation + ...
    registration.translationMm;
```

For the ROAST/capMaker integration path, convert those registered capMaker
print-frame points back into the input MRI frame with the saved skin-mesh
metadata:

```matlab
polhemusMri = acsCapMakerPrintToMriFrame(registration, modelFiducials);

polhemusMri.mriWorldCoordinatesMm
polhemusMri.mriVoxel1
polhemusMri.objects                 % traced implants converted to MRI frame
```

For NIfTI-driven capMaker runs, `mriWorldCoordinatesMm` is the zero-based MRI
millimeter lattice used by the capMaker skin-mesh preprocessing, and
`mriVoxel1` gives MATLAB/SPM-style one-based voxel coordinates.

For cross-session cap QC alignment, pass the repeatable headpost/chair labels
as the registration fiducials:

```matlab
sessionToSession = acsRegisterPolhemusFiducials( ...
    'C:/path/to/session_today.mat', ...
    'C:/path/to/session_reference.mat', ...
    'fiducialLabels', {'headpost1', 'headpost2', ...
        'rightChairPoint', 'leftChairPoint', 'topChairPoint'});
```

Once the combined layout has been accepted, build capMaker manufacturing STLs
directly from those final print-frame electrode coordinates:

```matlab
manufacturingPreflight = acsBuildCapMakerManufacturingStl(combinedLayout, ...
    'manufacturingTag', 'M2107_tes8_eeg8_cap_v01', ...
    'earExclusionMode', 'auto', ...
    'railEarExclusionMode', 'projectedSpheres', ...
    'strapMode', 'earRostral', ...
    'strapCorrStyle', 'rectilinear', ...
    'strapCorrFitIntegerCycles', true, ...
    'holderSupportMode', 'nearestRail', ...
    'holderSupportCount', 2, ...
    'holderSupportMinAngleDeg', 90, ...
    'holderBridgeMode', 'auto', ...
    'manufacturingSurfaceMaxFaces', 5000, ...
    'railSurfaceMaxFaces', 5000, ...
    'preflightOnly', true, ...
    'showFigures', true, ...
    'saveFigures', true, ...
    'force', true);

manufacturing = acsBuildCapMakerManufacturingStl(combinedLayout, ...
    'manufacturingTag', 'M2107_tes8_eeg8_cap_v01', ...
    'earExclusionMode', 'auto', ...
    'railEarExclusionMode', 'projectedSpheres', ...
    'strapMode', 'earRostral', ...
    'strapCorrStyle', 'rectilinear', ...
    'strapCorrFitIntegerCycles', true, ...
    'holderSupportMode', 'nearestRail', ...
    'holderSupportCount', 2, ...
    'holderSupportMinAngleDeg', 90, ...
    'holderBridgeMode', 'auto', ...
    'manufacturingSurfaceMaxFaces', 5000, ...
    'railSurfaceMaxFaces', 5000, ...
    'voxelSizeMm', 0.75, ...
    'showFigures', true, ...
    'saveFigures', true, ...
    'force', true);
```

The manufacturing utility reuses the capMaker scalp mesh cache reported by the
layout, places all selected tES and EEG holders, builds edge rails, subtracts
tetrahedral gel/electrode keepouts from the holder centers, creates PLA
underfill, and writes TPE/PLA STL files under the ignored capMaker output
folder. `strapMode='earRostral'` estimates lateral strap anchors from the
rostral edge of the saved ear exclusion spheres; use `strapMode='bboxLateral'`
for the older bounding-box heuristic or `strapMode='none'` while debugging the
rail/holder geometry. `holderSupportMode='nearestRail'` adds short support
struts from each electrode holder to nearby cap rails so the manufacturing mesh
does not depend on the decimated scalp mesh preserving a convenient edge under
every holder. The supports are selected to spread around each holder by at
least `holderSupportMinAngleDeg` when possible; `holderBridgeMode='auto'` adds
holder-to-holder stabilizer struts for holders whose rail-only supports still
approach from a narrow angle.
Chin straps use `strapCorrStyle='rectilinear'` by default, which voxelizes the
strap as an explicit square-wave sequence of vertical and horizontal bars.
Set `strapCorrStyle='swept'` only to recover the older swept-prism strap body.
`strapCorrFitIntegerCycles=true` adjusts each strap section to contain whole
cycles so partial corrugations are not left at the cap or ring end.
Use `acsPreviewChinStrapGeometry` for a strap-only tuning loop before running
the full manufacturing build. The interactive tuner shows both the triangulated
surface and the underlying voxel raster, and its Done button saves a MAT file
containing `manufacturingNameValuePairs` plus the explicit `strapOptions` and
`strapFrameOptions`.

```matlab
strapPreview = acsPreviewChinStrapGeometry( ...
    'outputDir', fullfile(pwd, 'outputs', 'debug', 'chinStrapPreview'), ...
    'previewTag', 'M2107_chinStrapTune', ...
    'parameterFile', fullfile(pwd, 'outputs', 'debug', ...
        'chinStrapPreview', 'M2107_chinStrapTune_params.mat'), ...
    'voxelSizeMm', 0.75, ...
    'interactive', true);
```

The full STL build uses `inpolyhedron` during voxel fusion/carving. The public
repo includes `acsUtilities/inpolyhedron.m`, and `setNHPulsePath` adds it with
the rest of the utilities. If you use a different copy, set
`inpolyhedronPath`, `ACS_INPOLYHEDRON_PATH`, or an entry in
`local.paths.json`. A typical local config entry is:

```json
"inpolyhedronPath": "/path/to/inpolyhedron.m"
```

During manufacturing, `preserveFusedTpeOccupancy=true` keeps the fused TPE
raster authoritative through electrode-hole carving. This avoids a
fuse-to-mesh-to-raster round trip that can corrupt voxel-native corrugations
such as chin straps. `carveCloseVox=0` is recommended for corrugated straps;
use `acsDiagnoseChinStrapManufacturing` to compare intended strap voxels
against fused, carved, cropped, and PLA raster stages.

Pass a custom TPM explicitly when needed:

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'tpmFile', 'C:/path/to/customMonkeyTpm.nii');
```

For debugging genuinely incorrect headers, `planeVoxelDims` can manually set
the displayed sagittal, coronal, and axial slice dimensions:

```matlab
out = acsSegmentAnatomyWithTpm('M2107', ...
    'planeVoxelDims', [3 2 1], ...
    'showFigures', true);
```

## TPM QC

Use `acsViewTpm` to inspect the macaque TPM itself before using it for
subject segmentation. It samples slices through the TPM with SPM, so it does
not need to load a multi-gigabyte TPM fully into memory.

```matlab
out = acsViewTpm('showFigures', true, 'saveFigures', true);
```

Or pass a specific TPM:

```matlab
out = acsViewTpm('C:/path/to/defaultMonkeyTpm.nii', ...
    'showFigures', true, ...
    'saveFigures', true);
```

## SPM TPM Alignment QC

Use `acsViewSpmTpmAlignment` after a segmentation run to inspect the TPM
as SPM has aligned it into the subject T1 grid. This helps distinguish a
bad TPM from a bad subject-to-TPM transform or a later tissue-class output
problem.

```matlab
out = acsViewSpmTpmAlignment('M2107', ...
    'segmentationTag', 'affreg_mni', ...
    'planeMode', 'spm', ...
    'showFigures', true, ...
    'saveFigures', true);
```

By default it creates separate affine-only and final-warp figures in raw
SPM subject voxel dimensions. Each figure shows the T1, the aligned TPM
sampled in the same subject grid, and T1 plus TPM contours for the same
slices. After the raw SPM-space check looks sensible, use
`'planeMode','anatomical'` with `anatomicalAxes` or `planeVoxelDims` for a
presentation view with anatomical labels.
