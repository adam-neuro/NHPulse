# 3D Printing And Fabrication

NHPulse manufacturing steps export STL files for the cap geometry, but the STL
files still need to be sliced and printed with settings appropriate for the
printer, filament, nozzles, and laboratory workflow. This page records the
configuration that has been tested during NHPulse development and gives users a
starting point for their own validation.

## Printed Parts

The final dual-material cap export produces two coordinated STL files:

- a flexible thermoplastic elastomer (TPE) cap containing the scalp rails,
  electrode holders, and chin straps,
- a rigid polylactic acid (PLA) support structure that stabilizes the flexible
  cap during printing and is removed after printing.

Import the two STL files into the slicer together and preserve their relative
coordinates. They should not be auto-centered independently. Assign the PLA STL
to the rigid/support-material extruder and the TPE STL to the flexible-material
extruder.

NHPulse can also export sparse PLA-only fit-check caps. These are faster,
single-material scaffolds intended to test the overall cap shape before
committing to a full dual-material print.

Instead of printing integrated chin straps, users can also add reinforced
Velcro attachment loops around the cap edge. `acsPlanVelcroAnchors` proposes
six bilateral loop locations, lets the user refine them on the scalp mesh, and
saves an anchor plan. Pass that plan to the final STL build with
`velcroAnchorMode='file'`, `velcroAnchorFile=velcroPlan.outputFile`, and
`strapMode='none'` if the printed chin straps should be omitted.

## Tested Hardware

The current fabrication workflow has been tested with:

- printer: LulzBot TAZ Pro with dual-extruder tool head,
- extruder 1: 2.85 mm PLA filament with a 0.4 mm nozzle,
- extruder 2: 1.75 mm NinjaTek Chinchilla TPE filament with a 0.5 mm nozzle.

This is an example configuration, not a requirement. Other printers and
materials may work, but users should expect to validate slicer settings, bed
adhesion, support removal, holder dimensions, and cap fit locally.

## Cura Slicing Workflow

The exact Cura menu labels can vary by version, but the tested workflow is:

1. Open Cura or LulzBot Cura and select the dual-extruder TAZ Pro printer
   profile.
2. Import both STL files from the same NHPulse manufacturing run.
3. Assign the PLA/support model to extruder 1.
4. Assign the TPE/cap model to extruder 2.
5. Select both imported models and merge them so they share one coordinate
   system.
6. Center the merged model on the printer bed.
7. Load the tested NHPulse Cura settings profile, if available.
8. Slice the merged model.
9. Inspect the sliced preview layer by layer, with special attention to
   electrode-holder holes, chin straps, implant keepouts, and low features near
   the printer bed.
10. Save the G-code to disk.
11. If using the tested TAZ Pro setup and the startup wipe/home issue applies,
    run the optional G-code patcher.
12. Keep the slicer project/profile and the final G-code with the experiment
    records.

Merge the models before centering them. Centering the PLA and TPE models
independently can destroy the alignment between the flexible cap and its
support structure.

Generated subject-specific STL and G-code files should usually remain outside
git. If you want to share printer settings with other users, prefer a small
Cura profile or project-template file and avoid committing animal-specific
geometry.

TODO: Add the tested Cura profile and Cura version after the profile has been
exported from the development workstation.

## Optional TAZ Pro G-code Patcher

The folder `printing/tazpro_dual` contains an optional Python patcher for one
TAZ Pro dual-extrusion startup problem observed during development. In that
setup, the nozzle sometimes failed to descend fully to the bed during the
startup wipe routine. The patcher writes a new `*_patched.gcode` file that:

- inserts a conservative top-of-file initialization block,
- re-homes immediately before the first `G12` wipe command,
- waits for the TPE extruder to reach print temperature before its first
  positive extrusion move.

Run it from the repository root or from any folder:

```bash
python printing/tazpro_dual/patch_tazpro_dual.py path/to/your_file.gcode
```

Keep the original G-code file and inspect the patched output in the slicer or a
G-code viewer before printing. The patcher assumes Cura-style G-code containing
a `G12` wipe command and is not a general-purpose printer repair tool.

## Print And Post-Print Checklist

Before printing:

- confirm that both extruders are assigned to the intended material,
- confirm nozzle diameters and filament diameters in the slicer,
- verify that the TPE cap is not clipped by the bed or by support geometry,
- check that all electrode-holder bores remain open,
- check that chin straps are connected and have the expected corrugation, or
  that Velcro loops are connected and have open slots,
- clean both nozzles so auto bed leveling can contact the bed correctly,
- apply the bed preparation used by your local protocol, such as a glue-stick
  layer for the tested TAZ Pro setup,
- prime both extruders by feeding a small amount of material,
- auto-home the printer before starting the job,
- keep the unpatched and patched G-code files with the print records.

After printing:

- inspect the cap before removing support material,
- remove PLA support using a locally validated process,
- follow institutional chemical-safety procedures if using alkaline PLA
  dissolution,
- test holder fit with the intended electrodes,
- perform an animal-safe fit check before experimental use.

NHPulse is research software. Printed parts are not validated medical devices,
and all animal, electrical, material, and chemical-safety procedures remain the
responsibility of the user and their institution.
