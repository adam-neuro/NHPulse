# NHPulse Application Shell

`nhpulseApp` is a thin, manifest-backed front end for reopening an NHPulse
project. It does not reimplement the scientific or manufacturing tools. It
selects explicit artifacts from one run and launches the existing specialized
GUIs through the stable service layer.

Start it after configuring the MATLAB path:

```matlab
setNHPulsePath;
P = acsPaths();
app = nhpulseApp(P.outputRoot);
```

With no argument, `nhpulseApp` uses the configured `P.outputRoot` when it is
available. Ordinary app refreshes validate manifest structure, file existence,
and dependency revisions without rehashing every large artifact. Run
`nhpulseCheckManifest(manifestFile, 'verifyContent', true)` when a full content
integrity check is required, or launch the app with
`nhpulseApp('verifyContent', true)`.

The project field should point to the folder that contains the `manifests/`
directory and the artifacts referenced by those manifests. Use **Browse** or
type another root and select **Open**.

## Interface

- **Subject** filters runs using `manifest.metadata.subjectId`.
- **Run** selects the exact manifest used by every launch action.
- **Stage** shows the workflow in dependency order and reports whether each
  stage is current, partial, stale, missing, or not started.
- **Artifacts** lists registered products for the selected run. Green rows are
  current; amber or red rows require attention.
- **Unregistered outputs** appears as a temporary run when recognizable files
  predate the manifest system. Select one inferred subject and choose
  **Import existing outputs** to create an inventory manifest. Importing does
  not move files or guess unknown parent relationships.
- **Inspect selected** opens an existing specialized inspector when one is
  registered for that artifact type.
- **Open file folder** reveals the selected artifact without changing it.

Interactive launch buttons currently cover printer-bed cropping, anatomical
exclusions, model fiducials, target selection, headpost placement, Velcro
anchor planning, and manufacturing inspection. Accepted outputs are recorded
immediately. If an upstream decision changes, manifest checks mark dependent
products stale rather than silently treating them as compatible.

The shell intentionally leaves long or highly configurable operations, such as
lead-field generation and montage optimization, in the documented service and
walkthrough APIs for now. Those stages still appear in workflow navigation and
artifact status reporting.

Current smoke tests and walkthroughs write manifests automatically. The import
path is primarily for products created by older NHPulse versions. The default
`discoverLegacy='auto'` scans for these files only when the selected project has
no manifests. To inspect a mixed project containing both registered and older
outputs, launch `nhpulseApp(P.outputRoot, 'discoverLegacy', 'always')`.
