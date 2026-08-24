# NHPulse

NHPulse is a MATLAB research workflow for individualized non-human-primate
EEG/tES cap design. It extends the ROAST electric-field modeling toolbox with
utilities for synthetic/reviewer examples, subject-specific scalp and implant
registration, capMaker-style layout design, sparse tES targeting, EEG
interleaving, and PLA/TPE STL generation.

The current release is a working research-software alpha rather than a polished
GUI application. The reviewer path is intentionally script-based so every file,
setting, and intermediate product is inspectable.

## Reviewer Quick Start

Open MATLAB from the repository root and run:

```matlab
setNHPulsePath;
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe');
report = nhpulseCheckDependencies();
```

If the report lists missing dependencies, install those packages before running
the smoke test. A convenient local drop zone is `lib/` inside this repository;
for example, an SPM download may be left as `lib/spm`, `lib/spm12`, or
`lib/spm12-main`. `setNHPulsePath` searches `lib/` for diagnostic dependency
functions rather than requiring exact folder names. You can also point NHPulse
to dependencies installed elsewhere with:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
```

or by editing the generated `local.paths.json` file directly. Important fields
include `spmPath`, `iso2meshPath`, `cvxPath`, `getdpExecutable`, and
`gmshExecutable`; see [Configuration](docs/configuration.md) and
[Dependencies And Third-Party Notices](DEPENDENCIES.md) for details.

After the dependency report says the synthetic smoke test is likely runnable,
run:

```matlab
setNHPulsePath;
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe');
report = nhpulseCheckDependencies();
smokeOut = nhpulseRunSyntheticSmokeTest('force', true, 'showFigures', true);
```

Then open [exampleWalkthrough.m](exampleWalkthrough.m) and run the cells in
order. The default preset uses interactive GUI steps and dummy lead fields so a
reviewer can exercise the full cap-manufacturing path without waiting for long
finite-element solves. To run the same walkthrough without interaction:

```matlab
cfg = nhpulseExampleConfig('syntheticFast');
```

To exercise real ROAST/GetDP lead-field generation on the synthetic head, use:

```matlab
cfg = nhpulseExampleConfig('syntheticRoast');
```

At the end of the walkthrough, or after a previously completed run:

```matlab
verification = nhpulseVerifySyntheticWalkthrough();
```

## Documentation

- [Installation](docs/installation.md): MATLAB path setup, local paths, and
  third-party dependencies.
- [Synthetic Walkthrough](docs/synthetic_walkthrough.md): the supported public
  example from synthetic anatomy to STL files.
- [Troubleshooting](docs/troubleshooting.md): common setup, macOS quarantine,
  ROAST, GetDP, and output-path failures.
- [User Manual](docs/user_manual.md): conceptual workflow and where the major
  functions fit.
- [Configuration](docs/configuration.md): `local.paths.json` and
  `nhpulseExampleConfig` presets.
- [Validation](docs/validation.md): smoke tests, verification, and manual test
  expectations.
- [Example Data](docs/example_data.md): why generated synthetic data are used
  instead of committing real MRI/scan products.
- [Dependencies And Third-Party Notices](DEPENDENCIES.md): MATLAB toolboxes,
  ROAST, SPM, iso2mesh, CVX, GetDP, Gmsh, and macaque tissue priors.
- [Citation](CITATION.md): citations for NHPulse, ROAST, optimization methods,
  and macaque tissue priors.

## What NHPulse Adds

- Synthetic ROAST-ready NHP-like anatomy for reproducible public examples.
- ROAST-compatible wrappers for custom capMaker electrode layouts and optional
  subject-specific tissue/implant handling.
- Scalp, phone-scan, digitizer-trace, fiducial, headpost, chamber, ear, and
  painted exclusion utilities.
- Iterative tES candidate growth with surrogate prediction and UCB-style
  exploration.
- Sparse tES optimization and channel-count sweep utilities.
- EEG layout interleaving that respects tES contacts and manufacturing
  exclusions.
- capMaker manufacturing helpers for electrode holders, rails, chin straps,
  fit-check scaffolds, STL export, and QC/inspection figures.

## Relationship To ROAST

This repository includes and modifies ROAST:

> Huang, Y., Datta, A., Bikson, M., Parra, L.C. Realistic vOlumetric-Approach
> to Simulate Transcranial Electric Stimulation -- ROAST -- a fully automated
> open-source pipeline. Journal of Neural Engineering 16(5), 2019.
> <https://doi.org/10.1088/1741-2552/ab208d>

The upstream ROAST README is preserved at
[docs/ROAST_README.md](docs/ROAST_README.md). Please see
[CITATION.md](CITATION.md) for citation details.

## Caveats

- NHPulse is research software. It is not a medical device and is not validated
  for clinical decision-making.
- Real MRI, phone/LiDAR scans, animal photographs, lead fields, and STL/G-code
  products should remain outside git.
- Full ROAST/GetDP solves can still be slow, even when the synthetic example is
  small. The default walkthrough uses dummy lead fields for reviewer speed.

## License

ROAST is distributed under GPL version 3 or later, with notes in
[LICENSE.md](LICENSE.md) and [docs/ROAST_README.md](docs/ROAST_README.md).
Unless otherwise stated, added NHPulse workflow code in this repository should
be treated as part of the same GPL-licensed research codebase.
