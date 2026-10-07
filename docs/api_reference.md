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

## Projects And Provenance

- `nhpulseArtifactTypes`: inspect or extend the artifact hierarchy.
- `nhpulseOpenProject`: load all run manifests and inventory recognizable
  unregistered outputs without modifying them.
- `nhpulseProjectStatus`: report current, stale, missing, incompatible, and
  unregistered artifacts in one table.
- `nhpulseDiscoverLegacyArtifacts`: perform the read-only legacy output scan.
- `nhpulseImportLegacyArtifacts`: preview or explicitly register selected
  legacy files in place; dry-run mode is the default.
- `nhpulseCreateManifest`, `nhpulseRegisterArtifact`, and
  `nhpulseSaveManifest`: record a new run and its dependency edges.
- `nhpulseCheckManifest`: validate files, fingerprints, dependency freshness,
  cycles, and known artifact-type relationships.

## Stable Pipeline Services

- `nhpulseCreateProjectContext`: identify one project root and run manifest.
- `nhpulseResolveArtifact`: resolve and validate an artifact key or handle.
- `nhpulseServiceBuildScalp`, `nhpulseServiceCropScalp`, and
  `nhpulseServiceDefineExclusions`: prepare printable subject geometry.
- `nhpulseServicePlaceHeadpost`: place/register a headpost and its keepout.
- `nhpulseServiceBuildFitCheck`: export/register a sparse PLA fit-check cap.
- `nhpulseServiceDefineFiducials` and `nhpulseServiceSelectTarget`: register
  spatial landmarks and the brain target consumed by later stages.
- `nhpulseServiceBuildCandidateLayout`, `nhpulseServiceGenerateLeadField`, and
  `nhpulseServiceOptimizeMontage`: perform registered targeting stages.
- `nhpulseServiceGrowCandidateLayout`: propose/register an expanded candidate
  layout from the current sparse solution.
- `nhpulseServiceBuildCombinedLayout`, `nhpulseServicePlanRetention`, and
  `nhpulseServiceBuildManufacturing`: produce the final layout and STLs.

See [Stable Pipeline Services](services.md) for the service contract and call
sequence.

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
- `acsBuildTesToEegTransferMatrix`: perform and cache the independent direct
  solves that map fixed-layout tES currents to referenced EEG voltages.
- `acsOptimizeOrthogonalTesEegTopography`: find a current-balanced active
  control whose predicted EEG artifact is orthogonal to the target-optimized
  stimulus under matched current limits.
- `acsPrepareTesEegContrastProtocol`: resolve a finalized cap by tag from a
  clean workspace and export target-optimized and EEG-orthogonal signed
  current vectors in a stable MAT/CSV protocol.
- `acsShowTesStimulationParameters`: reload a saved sparse/layout/manufacturing
  product and display the final tES current recipe, with optional replay of
  saved electric-field and EEG topography figures.

## Manufacturing And QC

- `acsBuildCapMakerFitCheckStl`: create a sparse PLA fit-check scaffold.
- `acsPlanVelcroAnchors`: propose and refine six Velcro-loop attachment
  anchors around the cap edge.
- `acsBuildCapMakerManufacturingStl`: export dual-material cap STL products.
- `acsInspectCapMakerManufacturingGeometry`: inspect scalp/cap/electrode
  geometry and orientation diagnostics.
- `acsPreviewChinStrapGeometry`: interactively preview chin strap parameters.
