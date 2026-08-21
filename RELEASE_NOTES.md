# Release Notes

## v0.1.0-alpha

First public alpha release of NHPulse.

Highlights:

- Bundled a modified ROAST/capMaker research workflow for NHP EEG/tES cap
  design.
- Added synthetic ROAST-ready data generation for public testing.
- Added a documented end-to-end `exampleWalkthrough.m` that reaches fit-check
  and dual-material STL export.
- Added setup helpers for MATLAB path configuration and machine-local paths.
- Added dependency reporting and macOS quarantine helper utilities.
- Added support for optional real ROAST/GetDP lead-field solves on the
  synthetic walkthrough.

Known limitations:

- The public workflow is still script/cell based rather than a comprehensive
  GUI.
- Full real-subject workflows remain active research code and require careful
  QC at each step.
- Automated tests are limited; the synthetic walkthrough plus verification
  helper are the current reviewer-facing validation path.
