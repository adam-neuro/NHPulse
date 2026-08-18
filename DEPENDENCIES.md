# Dependencies And Third-Party Notices

NHPulse is MATLAB research software built around ROAST/capMaker workflows.
This document lists the dependencies a reviewer or user is most likely to
need, and separates the lightweight synthetic smoke test from the full
lead-field/manufacturing workflow.

## MATLAB And JOSS Context

NHPulse currently requires MATLAB. The codebase is not expected to run in GNU
Octave or as a standalone executable at this stage.

JOSS accepts submissions that depend on proprietary languages or development
environments when the submission otherwise satisfies JOSS requirements, but
JOSS states a strong preference for non-proprietary environments. If NHPulse is
submitted to JOSS, the authors should be prepared to help identify reviewers
who already have access to MATLAB.

## Quick Dependency Check

From the repository root:

```matlab
setNHPulsePath;
report = nhpulseCheckDependencies();
```

The checker is intentionally lightweight. It reports obvious missing products
or functions, but the synthetic walkthrough remains the practical installation
test.

## Core Synthetic MWE

The public synthetic walkthrough in `exampleWalkthrough.m` is the lowest-friction
reviewer entry point. It generates a tiny synthetic ROAST-ready T1/mask pair,
builds a scalp cache, and places a toy custom electrode layout.

Known requirements for this path:

- MATLAB.
- SPM on the MATLAB path for NIfTI read/write functions such as `spm_vol`,
  `spm_read_vols`, `spm_write_vol`, and `spm_type`.
- MATLAB Image Processing Toolbox for morphology, connected components, and
  volume smoothing (`bwconncomp`, `imdilate`, `imerode`, `imreconstruct`,
  `imgaussfilt3`, `imfill`).
- MATLAB Statistics and Machine Learning Toolbox for distance and nearest
  neighbor helpers used by layout code (`pdist2`, `knnsearch`).
- MATLAB graphics functions used by mesh and QC plots (`triangulation`,
  `isosurface`, `reducepatch`, `polyshape`).

If the smoke test reports a missing dependency, run:

```matlab
setNHPulsePath;
report = nhpulseCheckDependencies();
```

The printed report includes install links and the relevant `local.paths.json`
field for configurable external dependencies.

## Full ROAST/tES Workflow

The full workflow adds heavier dependencies and can take hours for real
subjects:

- ROAST, including its expected SPM-based segmentation and field-solver
  workflow. NHPulse currently vendors a modified ROAST copy for reviewer/user
  reproducibility.
- iso2mesh/TetGen for volumetric meshing.
- GetDP for finite-element solves and lead-field generation.
- Gmsh for ROAST/GetDP mesh and visualization workflows.
- CVX for sparse tES montage optimization (`cvx_begin` and related commands).
- A configured local path file such as `local.paths.json` for
  machine-specific external executable and data locations. Create one with
  `nhpulseConfigureLocalPaths`, or edit the generated file by hand if needed.

## Install Links

- SPM: <https://www.fil.ion.ucl.ac.uk/spm/docs/installation/>
- CVX: <https://cvxr.com/cvx/download/>
- iso2mesh/TetGen: <https://github.com/fangq/iso2mesh/releases>
- GetDP: <https://getdp.info/>
- Gmsh: <https://gmsh.info/#Download>
- MathWorks Image Processing Toolbox:
  <https://www.mathworks.com/products/image-processing.html>
- MathWorks Statistics and Machine Learning Toolbox:
  <https://www.mathworks.com/products/statistics.html>

The public repository currently does not vendor SPM, CVX, iso2mesh/TetGen,
GetDP, or Gmsh. This keeps the first release smaller and avoids blending
several third-party release/update cycles into the NHPulse source tree. Some
of these packages are redistributable under GPL-family or related licenses,
but each project has its own terms and bundled binaries; revisit vendoring only
with explicit license notices and version pinning.

## Optional Components

These are useful for some workflows but are not required for the synthetic MWE:

- External digitizer or 3D-scan tools. NHPulse can work with saved point sets,
  traces, and phone/LiDAR meshes, but the public release does not include a
  live hardware acquisition interface.
- Phone/LiDAR scan inputs from tools such as EM3D. The synthetic MWE creates a
  small phone-scan-like mesh for software testing. Real animal scans should be
  kept outside git.
- 3D printing/slicer software such as Cura for manufacturing exported STL
  files.
- SolidWorks or other CAD tools if users want to inspect or replace implant
  geometry.

## Static Scan Notes

A static scan of the public staging repository found repeated use of these
dependency-sensitive functions:

- SPM functions: `spm_vol`, `spm_read_vols`, `spm_write_vol`,
  `spm_preproc_run`, `spm_jobman`, and related sampling/TPM utilities.
- Image Processing Toolbox functions: `bwconncomp`, `imreconstruct`,
  `imdilate`, `imerode`, `imclose`, `imfill`, `imgaussfilt3`, `bwdist`.
- Statistics and Machine Learning Toolbox functions: `pdist2`, `knnsearch`.
- CVX commands: `cvx_begin`.
- MATLAB geometry/graphics functions: `triangulation`,
  `delaunayTriangulation`, `polyshape`, `convhulln`, `isosurface`,
  `reducepatch`.

This scan should be treated as an aid to documentation, not a formal product
dependency proof. A future cleanup step should run
`matlab.codetools.requiredFilesAndProducts` on the public MWE in a clean MATLAB
environment and compare the result against this document.

## Third-Party Notices

NHPulse includes code derived from or designed to work with several external
research-software projects.

- ROAST: GPL-licensed transcranial electric stimulation modeling pipeline.
  The original README is preserved in `docs/ROAST_README.md`; modified files
  should retain upstream notices and should be documented in release notes.
- `inpolyhedron.m`: MATLAB File Exchange utility by Sven Holcombe, distributed
  under a BSD-style license. The license text is preserved in
  `licenses/inpolyhedron-BSD.txt`.
- SPM, iso2mesh/TetGen, GetDP, Gmsh, CVX, and NIfTI utilities may be required
  by parts of the pipeline but should generally be installed as external
  dependencies rather than vendored in this release repository, unless a
  future release intentionally vendors a compatible copy with appropriate
  license notices.
