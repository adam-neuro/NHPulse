# User Manual

NHPulse is organized as a transparent MATLAB workflow rather than a single GUI.
Most users should start with the synthetic walkthrough and then adapt the same
sequence to real subject data.

## Core Idea

The package keeps one capMaker-compatible scalp surface as the manufacturing
geometry, uses ROAST-compatible tissue and lead-field products for electrical
modeling, and records the transformations/exclusions needed to keep implants,
ears, face regions, and printer-bed constraints consistent.

## Physical Design Mental Model

The practical object being designed is a flexible cap that sits on the dorsal
scalp. The cap is manufactured in printer-bed coordinates: the crop plane is
treated as the printer bed (`Z=0`), and cap rails/electrode holders are built
over scalp vertices above that plane. The software then keeps cap geometry away
from the cropped edge by configurable margins and applies additional local
exclusions for ears, face, implants, straps, or other regions.

A useful way to think about the early workflow is:

1. decide which part of the head can plausibly be covered by a cap,
2. remove local regions that should not receive cap material,
3. place or localize implants so the cap avoids them,
4. choose legal electrode locations on the remaining scalp,
5. model the electrical consequences of candidate locations,
6. export geometry that can actually be printed and inspected.

Future documentation should include annotated screenshots and photographs near
the beginning of the manual so users can see the intended final object before
they encounter the crop and exclusion GUIs.

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

### Crop-Plane Selection

The crop-plane GUI asks where the printable cap footprint should end. The goal
is not to preserve the entire head mesh. For an EEG/tES cap, include the
top-level scalp that should receive cap mesh and exclude lower face/neck
regions. Later exclusions handle ears, face patches, implants, and other local
keepouts.

### Ear And Painted Exclusions

Ear exclusions keep cap rails and electrode holders away from ears. Painted
vertices mark additional local areas, such as face or eyelid regions, that
survived the crop but should not be used as electrode sites or rail endpoints.

### Implant Placement

Neurophysiology animals often have titanium headposts, chambers, or other
cranial implants. Implant placement utilities help the user represent those
objects on the head model. The resulting geometry can be used to avoid building
cap material over exposed implants and, for some workflows, to include implant
conductivity in electrical models.

### Target Selection

The target-voxel picker selects the brain location that tES optimization should
attempt to stimulate. For real studies this target may come from MRI anatomy,
atlas coordinates, functional data, or planned recording trajectories.

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
