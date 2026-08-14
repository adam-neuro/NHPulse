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
- Phone-scan and Polhemus registration utilities for updating scalp shape and
  localizing implants.
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
2. Add the repository and helper folders to the path:

   ```matlab
   repoRoot = pwd;
   addpath(repoRoot);
   addpath(fullfile(repoRoot, 'acsUtilities'));
   addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
   addpath(fullfile(repoRoot, 'capMaker', 'core'));
   ```

3. Configure local machine paths using `acsUtilities/local.paths.json`.
   Generated data should live outside git under `outputs/`, `data/`, or a
   configured external data root.
4. Work through [exampleWalkthrough.m](exampleWalkthrough.m) one cell at a time.

The walkthrough is intentionally cell-based because several steps are
interactive, slow, or both. ROAST/GetDP lead-field solves can take hours; the
walkthrough includes switches for replaying cached products and for using dummy
lead fields during software development.

## Example Data

Subject MRI and derived lead-field files are too large for normal git hosting
and may also be sensitive. See [docs/example_data.md](docs/example_data.md) for
the intended example-data strategy.

In brief, a public release should include:

- Small synthetic or dummy lead-field products for software tests.
- Small geometry-only examples for UI/manufacturing demonstrations.
- Download instructions for any full MRI/lead-field example hosted externally.

## Public Release Checklist

See [docs/public_release_checklist.md](docs/public_release_checklist.md) for
the cleanup tasks that should be checked before switching the GitHub repository
from private to public.

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
- `exampleWalkthrough.m` - documented end-to-end example script.
- `docs/ROAST_README.md` - original ROAST README retained for upstream docs.

## License

ROAST is distributed under GPL version 3 or later, with notes in
[LICENSE.md](LICENSE.md) and [docs/ROAST_README.md](docs/ROAST_README.md).
Unless otherwise stated, added workflow code in this repository should be
treated as part of the same GPL-licensed research codebase.
