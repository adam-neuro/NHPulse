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
builds a scalp cache, exercises ear/painted/implant exclusion bookkeeping,
exports a quick PLA fit-check STL, grows a tES candidate layout with dummy
lead fields, interleaves EEG sites, and writes small dual-material cap STLs.

Known requirements for this path:

- MATLAB.
- SPM on the MATLAB path for NIfTI read/write functions such as `spm_vol`,
  `spm_read_vols`, `spm_write_vol`, and `spm_type`.
  NHPulse includes SPM-backed compatibility wrappers for ROAST's legacy
  `load_untouch_nii` and `save_untouch_nii` calls, so reviewers do not need
  a separate NIfTI toolbox for the walkthrough.
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
  The synthetic walkthrough uses the development heuristic search mode so that
  reviewers can exercise the optimization path before installing CVX.
- A configured local path file such as `local.paths.json` for
  machine-specific external executable and data locations. Create one with
  `nhpulseConfigureLocalPaths`, or edit the generated file by hand if needed.

By default, `exampleWalkthrough.m` uses dummy lead fields to keep reviewer
runs fast. Set `cfg.leadFieldMode = 'roast'` in cell 00 to benchmark actual
ROAST/GetDP lead-field solves on the synthetic head; the walkthrough prints
timing feedback for each solve.

## Real Macaque Tissue Priors

Real-subject SPM segmentation can use a six-channel macaque tissue probability
map (TPM). The development workflow used a derived ROAST/SPM-style TPM named
`defaultMonkeyTpm.nii`, with a legacy local filename fallback of `myTpm.nii`.
This file is generated outside git and should not be committed.

The default `templateMaker('mode','atlasPriors')` inputs are named
`gm_priors_ohsu+uw.nii`, `wm_priors_ohsu+uw.nii`, and
`csf_priors_ohsu+uw.nii`. Those names correspond to the 112RM-SL rhesus
macaque atlas priors described by McLaren et al. (2009), which were built from
OHSU and University of Wisconsin animals. Cite the atlas paper when these
priors or a TPM derived from them are used:

McLaren, D.G., Kosmatka, K.J., Oakes, T.R., Kroenke, C.D., Kohama, S.G.,
Matochik, J.A., Ingram, D.K., & Johnson, S.C. A population-average MRI-based
atlas collection of the rhesus macaque. *NeuroImage*, 45(1), 52-59, 2009.
<https://doi.org/10.1016/j.neuroimage.2008.10.058>

Useful source pages include the SPM Extensions listing for the 112RM-SL
template and priors (<https://www.fil.ion.ucl.ac.uk/spm/ext/>) and the
NeuroDebian package page for the McLaren rhesus macaque atlas
(<https://neuro.debian.net/pkgs/mclaren-rhesus-macaque-atlas.html>). The
historical project URL was `http://brainmap.wisc.edu/monkey.html`, but registry
pages currently mark that URL as old or unavailable, so users may need to use
one of the mirrored/package routes or contact the data maintainers.

## Install Links

- SPM: <https://www.fil.ion.ucl.ac.uk/spm/docs/installation/>
- CVX: <https://cvxr.com/cvx/download/>
- iso2mesh/TetGen: <https://sourceforge.net/projects/iso2mesh/files/iso2mesh/>
- GetDP: <https://getdp.info/>
- Gmsh: <https://gmsh.info/#Download>
- MathWorks Image Processing Toolbox:
  <https://www.mathworks.com/products/image-processing.html>
- MathWorks Statistics and Machine Learning Toolbox:
  <https://www.mathworks.com/products/statistics.html>

`niftiPath` can remain blank for normal NHPulse/ROAST use because the
repository includes SPM-backed `load_untouch_nii` and `save_untouch_nii`
compatibility wrappers. It is only needed when you want NHPulse to add a
separate legacy NIfTI utility folder automatically.

The public repository currently does not vendor SPM, CVX, iso2mesh/TetGen,
GetDP, or Gmsh. This keeps the first release smaller and avoids blending
several third-party release/update cycles into the NHPulse source tree. Some
of these packages are redistributable under GPL-family or related licenses,
but each project has its own terms and bundled binaries; revisit vendoring only
with explicit license notices and version pinning.

If users manually install MATLAB dependencies inside a clone, `setNHPulsePath`
checks common local folders including `lib/spm`, `lib/spm12`, `lib/cvx`,
`lib/iso2mesh`, and `lib/NIFTI_20110921`.

## macOS Quarantine / MEX Troubleshooting

If MATLAB fails on macOS with an "Invalid MEX-file", "developer cannot be
verified", "library load disallowed by system policy", or "Permission denied"
message, the downloaded dependency folder may have a Gatekeeper quarantine
attribute or a missing executable bit. This can affect CVX, SPM, iso2mesh, or
other dependencies that contain MEX binaries and helper executables.

After setting `spmPath` and/or `cvxPath` with `nhpulseConfigureLocalPaths`, run
one of:

```matlab
nhpulseClearMacQuarantine('spm')
nhpulseClearMacQuarantine('cvx')
nhpulseClearMacQuarantine('iso2mesh')
nhpulseClearMacQuarantine({'spm', 'cvx', 'iso2mesh'})
```

The helper runs the equivalent of `xattr -rc` on the configured folder and also
marks common MEX/solver helper files executable. You can also pass a direct
folder path:

```matlab
nhpulseClearMacQuarantine('/Users/adam/Documents/MATLAB/NHPulse/lib/spm')
```

The same operation can be run from Terminal:

```bash
xattr -rc /path/to/spm
xattr -rc /path/to/cvx
xattr -rc /path/to/iso2mesh
find /path/to/iso2mesh -type f \( -name '*.mex*' -o -name 'cgalmesh*' -o -name 'tetgen*' \) -exec chmod u+x {} +
```

Then restart MATLAB. For CVX, rerun `cvx_setup`. If `savepath` fails during CVX
setup, that usually only means MATLAB could not write its global `pathdef.m`;
configure CVX through `nhpulseConfigureLocalPaths` or add it from your own
`startup.m`.

For Apple Silicon MATLAB, iso2mesh must include a platform-matched mesher such
as `lib/iso2mesh/bin/cgalmesh.mexmaca64`. If `nhpulseCheckDependencies` reports
that this binary is missing, download the matching MEX files from the iso2mesh
release/bin folder and then run `nhpulseClearMacQuarantine('iso2mesh')`.

## Optional Components

These are useful for some workflows but are not required for the synthetic MWE:

- External digitizer or 3D-scan tools. NHPulse can work with saved point sets,
  traces, and phone/LiDAR meshes, but the public release does not include a
  live hardware acquisition interface.
- Upstream ROAST `capInfo.xlsx` if users want predefined 10-20/10-10/10-05,
  BioSemi, or EGI electrode names. NHPulse's synthetic and capMaker workflows
  use subject-specific `custom...` locations and do not require this
  spreadsheet.
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
