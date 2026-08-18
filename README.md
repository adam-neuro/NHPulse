# NHPulse

NHPulse is a research workflow for designing individualized non-human-primate
EEG/tES caps. It extends the ROAST electric-field modeling toolbox with
utilities for subject-specific anatomy import, scalp/implant registration,
capMaker-style electrode layout, tES targeting, EEG placement, and STL
generation for cap manufacturing.

The current code is a working research pipeline rather than a polished GUI
application. The short-term goal is to make the workflow reproducible and
inspectable from documented MATLAB walkthroughs; a comprehensive GUI can sit
on top of the same functions later.

## What This Adds

- DICOM/NIfTI preprocessing helpers for monkey MRI workflows.
- ROAST-compatible tissue-label and lead-field generation wrappers.
- Phone-scan and saved digitizer-trace registration utilities for updating
  scalp shape and localizing implants.
- Subject-specific headpost, chamber, ear, face, and manufacturing exclusion
  tools.
- Iterative candidate growth for tES electrode layouts, including surrogate
  lead-field expansion and UCB-style candidate selection.
- Sparse tES optimization and channel-count sweep utilities.
- EEG site placement for approximately uniform scalp coverage while respecting
  tES/manufacturing exclusions.
- capMaker manufacturing utilities for electrode holders, rails, chin straps,
  PLA/TPE STL export, and QC/inspection figures.

## Relationship to ROAST

This repository includes and modifies ROAST:

> Huang, Y., Datta, A., Bikson, M., Parra, L.C. Realistic vOlumetric-Approach
> to Simulate Transcranial Electric Stimulation -- ROAST -- a fully automated
> open-source pipeline. Journal of Neural Engineering 16(5), 2019.
> <https://doi.org/10.1088/1741-2552/ab208d>

Please see [CITATION.md](CITATION.md) for the citations to use when NHPulse or
the underlying ROAST functionality contributes to a project. The
upstream ROAST README is preserved at [docs/ROAST_README.md](docs/ROAST_README.md).

## Quick Start

1. Open MATLAB from the repository root.
2. Add NHPulse folders to the MATLAB path:

   ```matlab
   setNHPulsePath;
   ```

3. Optional but recommended: create a local machine-path config. This writes
   `local.paths.json`, which is ignored by git. For the synthetic walkthrough,
   the defaults are enough:

   ```matlab
   P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe');
   ```

   To choose folders with dialogs instead of accepting defaults:

   ```matlab
   P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
   ```

   The config file records where generated outputs, private source data, ROAST
   scratch products, and optional external MATLAB dependencies live on a given
   computer. Generated data should stay outside git under `outputs/`, `data/`,
   or a configured external data root.

   If a dependency is missing, run:

   ```matlab
   report = nhpulseCheckDependencies();
   ```

   The report includes install links and the relevant `local.paths.json` field
   for dependencies such as SPM, CVX, iso2mesh/TetGen, GetDP, and Gmsh.

4. Run the synthetic smoke test to verify that the installation can generate
   tiny ROAST-ready demo data and place a toy cap layout:

   ```matlab
   if ~exist('P', 'var'), P = acsPaths(); end
   smokeOut = nhpulseRunSyntheticSmokeTest( ...
       fullfile(P.outputRoot, 'syntheticMwe', 'nhpulseSyntheticSmoke'), ...
       'force', true, ...
       'showFigures', true);
   ```

   The current smoke test uses SPM for NIfTI read/write. SPM is not bundled in
   the public repo; if it is missing, the error and dependency report point to
   the official SPM install page and the local config field to update.

5. Work through [exampleWalkthrough.m](exampleWalkthrough.m) one cell at a time.

The walkthrough is intentionally cell-based because several steps are
interactive, slow, or both. ROAST/GetDP lead-field solves can take hours; the
walkthrough includes switches for replaying cached products and for using dummy
lead fields during software development.

## Example Data

Subject MRI, phone/LiDAR scans, animal photographs, and derived lead-field
files are too large for normal git hosting and may also be sensitive. The
repository therefore includes a synthetic data generator instead of generated
NIfTI outputs or real scan exports. See
[syntheticMwe/README.md](syntheticMwe/README.md) for the current smoke-test
entry point and [docs/example_data.md](docs/example_data.md) for the broader
example-data strategy.

In brief, a public release should include:

- Synthetic data generators and small dummy lead-field products for software
  tests.
- Small geometry-only examples for UI/manufacturing demonstrations.
- Download instructions for any full MRI/lead-field example hosted externally.

## Important Caveats

- This is research software. It is not a medical device and is not validated
  for clinical decision-making.
- Many routines assume MATLAB plus ROAST's usual external dependencies
  including SPM, iso2mesh/TetGen/GetDP paths used by ROAST, and Image Processing
  Toolbox functions.
- The public-facing workflow is still under active cleanup. Start with
  `exampleWalkthrough.m`; additional synthetic examples and automated tests
  are planned public-development milestones.

## Repository Layout

- `acsUtilities/` - project-specific workflow functions and QC utilities.
- `capMaker/` - cap geometry, voxel/mesh, and STL helpers.
- `syntheticMwe/` - synthetic data generators and smoke-test utilities.
- `exampleWalkthrough.m` - documented end-to-end example script.
- `setNHPulsePath.m` and `nhpulseConfigureLocalPaths.m` - reviewer-friendly
  setup helpers for MATLAB paths and machine-local folders.
- `docs/ROAST_README.md` - original ROAST README retained for upstream docs.

## License

ROAST is distributed under GPL version 3 or later, with notes in
[LICENSE.md](LICENSE.md) and [docs/ROAST_README.md](docs/ROAST_README.md).
Unless otherwise stated, added workflow code in this repository should be
treated as part of the same GPL-licensed research codebase.
