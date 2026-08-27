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

The public synthetic smoke test uses NHPulse's bundled simple NIfTI reader and
writer for its generated toy files. Full real-subject workflows still use SPM
heavily. Errors involving `spm_vol`, `spm_preproc_run`, or SPM segmentation
usually mean SPM is not on the MATLAB path. Install SPM and configure:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
report = nhpulseCheckDependencies();
```

NHPulse includes `load_untouch_nii` and `save_untouch_nii` compatibility
wrappers that prefer SPM but can fall back to bundled simple NIfTI I/O for the
synthetic/demo files. A separate legacy NIfTI toolbox is normally not needed.

## SPM MEX Files Are Not Compiled On Apple Silicon

On Apple Silicon Macs, source-only or platform-mismatched SPM downloads may
show warnings such as:

```text
spm_existfile is not compiled for your platform
mat2file.c not compiled - see Makefile
spm_slice_vol.c was not compiled
```

This means MATLAB can see SPM functions, but at least one compiled SPM
NIfTI/resampling helper is unavailable for the current platform. NHPulse's
synthetic smoke-test path can fall back to `nhpulseReadSimpleNifti` and
`nhpulseWriteSimpleNifti` for the generated toy files. However, full SPM
segmentation and upstream ROAST/SPM paths still require a working,
platform-compatible SPM install.

First confirm that you downloaded the current SPM release from the main SPM
download page rather than an older source snapshot. If the right `.mexmaca64`
files are present but macOS blocks them, clear quarantine:

```matlab
nhpulseClearMacQuarantine('spm')
```

or pass the exact folder:

```matlab
nhpulseClearMacQuarantine('/Users/you/Documents/MATLAB/NHPulse/lib/spm12-main')
```

Restart MATLAB afterward.

To diagnose:

```matlab
setNHPulsePath;
report = nhpulseCheckDependencies();
report.spm
```

## macOS Blocks MEX Files

Symptoms include "Invalid MEX-file", "developer cannot be verified", "library
load disallowed by system policy", or `Permission denied` from `cgalmesh` or
GetDP.

After configuring dependency paths:

```matlab
nhpulseClearMacQuarantine({'spm', 'cvx', 'iso2mesh', 'getdp'})
```

Restart MATLAB. For CVX, rerun `cvx_setup`.

If `nhpulseClearMacQuarantine('getdp')` says the GetDP path is not found or
not configured, rerun local path setup after installing GetDP:

```matlab
P = nhpulseConfigureLocalPaths('profile', 'syntheticMwe', 'useGui', true);
```

or pass the folder/executable directly, for example:

```matlab
nhpulseClearMacQuarantine('/Users/you/Documents/MATLAB/NHPulse/lib/getdp-3.2.0')
```

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

## TAZ Pro Startup Wipe Or Bed-Leveling Problems

If a LulzBot TAZ Pro dual-extrusion print starts with the nozzle too high or
too low during wiping or bed leveling, first check physical setup: both nozzles
should be clean, both extruders should be primed, and the printer should be
auto-homed before the job.

For one tested TAZ Pro setup, NHPulse includes an optional Cura-style G-code
patcher that re-homes before the first `G12` wipe command and waits for the TPE
extruder before its first extrusion:

```bash
python printing/tazpro_dual/patch_tazpro_dual.py path/to/your_file.gcode
```

This writes `*_patched.gcode` next to the input file. Keep the original G-code
and inspect the patched file before printing. See
[3D Printing And Fabrication](fabrication.md) for the full slicing checklist.

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
