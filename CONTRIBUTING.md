# Contributing

NHPulse is an active research-software release candidate. Issues, bug reports,
documentation fixes, synthetic test cases, and focused pull requests are
welcome.

## Before Opening A Pull Request

1. Keep generated subject data, lead fields, ROAST work directories, STL/G-code
   products, raw scans, animal images, and local path files out of git.
2. Prefer small, focused changes with a clear use case.
3. Update documentation when changing workflow behavior or settings.
4. Use synthetic or dummy data for tests and examples unless a public data
   source is explicitly documented.
5. Run the synthetic smoke test when the change touches setup, file formats,
   or capMaker geometry:

   ```matlab
   setNHPulsePath;
   smokeOut = nhpulseRunSyntheticSmokeTest('force', true, 'showFigures', false);
   ```

6. If the change touches the full tutorial, run the relevant cells in
   `exampleWalkthrough.m` and then:

   ```matlab
   verification = nhpulseVerifySyntheticWalkthrough();
   ```

## Coding Style

MATLAB style currently follows the surrounding code. Prefer explicit
name-value parameters, short helper functions, and QC output that helps users
understand coordinate frames and generated geometry.

## Sensitive Data

Do not commit real MRI files, phone/LiDAR scans, photos, lead-field products,
STL/G-code outputs, or machine-local path files. Public issues should use
synthetic examples or redacted metadata whenever possible.

## AI Assistance

This project has used AI assistance for substantial implementation,
documentation, debugging, and refactoring work. Human contributors remain
responsible for reviewing, testing, and validating submitted changes.
