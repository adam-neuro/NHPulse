# API Reference

This is a high-level map of the public-facing functions most useful to new
users. MATLAB help text in each function remains the authoritative interface
description.

## Setup And Configuration

- `setNHPulsePath`: add repository folders and known local dependency folders.
- `nhpulseConfigureLocalPaths`: create or update `local.paths.json`.
- `nhpulseCheckDependencies`: print dependency availability and install links.
- `nhpulseClearMacQuarantine`: clear macOS quarantine attributes on configured
  dependencies.
- `nhpulseExampleConfig`: return named synthetic walkthrough presets.

## Synthetic MWE

- `nhpulseCreateSyntheticRoastReadyData`: generate synthetic T1, hard-label
  mask, fiducials, and scan-like geometry.
- `nhpulseCreateSyntheticHeadpostTrace`: create a toy headpost trace.
- `nhpulseRunSyntheticSmokeTest`: quick synthetic installation smoke test.
- `nhpulseVerifySyntheticWalkthrough`: verify products from the full synthetic
  walkthrough.

## Scalp And Registration

- `acsBuildRoastScalpSkinCache`: build a capMaker-compatible scalp cache from
  ROAST labels.
- `acsCropWarpedSkinCacheToPrinterBed`: crop a full-head scalp into printer-bed
  coordinates.
- `acsRegisterPhoneScanToCapMakerFrame`: register phone/PLY scans to the MRI
  or capMaker frame.
- `acsWarpScalpSurfaceToPhoneScan`: warp a scalp surface to phone-scan data.
- `acsSelectModelFiducials`, `acsSelectPhoneScanFiducials`: fiducial pickers.

## Exclusions And Implants

- `acsSelectEarExclusionSpheres`: define ears and painted vertex exclusions.
- `acsPlanHeadpostPlacement`: place and refine a simplified headpost mesh.
- `acsMakeHeadpostExclusionFromPlacement`: derive a tight cap keepout from a
  placed headpost.
- `acsPlanChamberPlacement`: plan cylindrical recording chamber placement.

## Layout And Modeling

- `acsMakeRoastCapMakerLayout`: place initial capMaker/ROAST custom locations.
- `acsGenerateRoastLeadField`: run ROAST lead-field generation for a layout.
- `acsGenerateDummyRoastLeadField`: create development-only dummy lead fields.
- `acsOptimizeSparseRoastLeadField`: select a sparse active tES montage.
- `acsProposeRoastCandidateGrowth`: propose new candidate sites with surrogate
  prediction and UCB-style acquisition.
- `acsAssembleTesEegCapMakerLayout`: interleave EEG electrodes around selected
  tES sites.
- `acsShowTesStimulationParameters`: reload a saved sparse/layout/manufacturing
  product and display the final tES current recipe, with optional replay of
  saved electric-field and EEG topography figures.

## Manufacturing And QC

- `acsBuildCapMakerFitCheckStl`: create a sparse PLA fit-check scaffold.
- `acsBuildCapMakerManufacturingStl`: export dual-material cap STL products.
- `acsInspectCapMakerManufacturingGeometry`: inspect scalp/cap/electrode
  geometry and orientation diagnostics.
- `acsPreviewChinStrapGeometry`: interactively preview chin strap parameters.
