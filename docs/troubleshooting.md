# Troubleshooting

This page records failures seen during fresh-clone testing and the shortest
known path to diagnose them.

## Read-Only Output Folder

If MATLAB reports a read-only file system while creating synthetic outputs,
choose a writable `outputRoot`:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
```

Pick a folder under your home directory.

## Missing SPM Or NIfTI Functions

Errors involving `spm_vol`, `spm_write_vol`, or `load_untouch_nii` usually mean
SPM is not on the MATLAB path. Install SPM and configure:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
report = nhpulseCheckDependencies();
```

NHPulse includes SPM-backed `load_untouch_nii` and `save_untouch_nii`
compatibility wrappers, so a separate legacy NIfTI toolbox is normally not
needed.

## macOS Blocks MEX Files

Symptoms include "Invalid MEX-file", "developer cannot be verified", "library
load disallowed by system policy", or `Permission denied` from `cgalmesh`.

After configuring dependency paths:

```matlab
nhpulseClearMacQuarantine({'spm', 'cvx', 'iso2mesh'})
```

Restart MATLAB. For CVX, rerun `cvx_setup`.

## Gmsh App Bundle On macOS

If you downloaded `Gmsh.app`, the command-line executable is inside the bundle:

```text
Gmsh.app/Contents/MacOS/gmsh
```

`nhpulseConfigureLocalPaths` and `nhpulseCheckDependencies` try to resolve this
automatically if you select the `.app` folder.

## GetDP Not Found

The full ROAST lead-field path needs a GetDP executable. Configure it with the
GUI or edit `local.paths.json`:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
report = nhpulseCheckDependencies();
```

## ROAST Custom Segmentation Or capInfo Errors

The synthetic walkthrough supplies a custom hard-label mask so ROAST can skip
SPM segmentation. It also uses custom electrode locations, so upstream
`capInfo.xlsx` should not be required for the public synthetic path. If ROAST
tries to segment or asks for `capInfo.xlsx`, make sure you are running the
current repository version and restart MATLAB with:

```matlab
clear functions;
setNHPulsePath;
```

## Gel Labels Missing In The Synthetic ROAST Path

The synthetic ROAST path uses a stacked disc electrode/gel model that is sized
for the toy mesh. Use:

```matlab
cfg = nhpulseExampleConfig('syntheticRoast');
```

If you override electrode geometry, inspect domains with:

```matlab
nhpulseInspectRoastLeadFieldDomains(syntheticOut.t1File, simulationTag)
```

## Verification Fails

Run:

```matlab
verification = nhpulseVerifySyntheticWalkthrough();
```

The printed table names the missing product class. If only the real lead-field
check is missing, confirm whether you used the default dummy mode. Dummy mode is
expected to skip real ROAST result files.
