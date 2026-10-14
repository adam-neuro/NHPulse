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
- **Settings** opens the shared stage-settings editor when the selected stage
  has configurable presets. The button shows the active preset after settings
  have been applied.

Interactive launch buttons currently cover printer-bed cropping, anatomical
exclusions, model fiducials, target selection, headpost placement, Velcro
anchor planning, and manufacturing inspection. Accepted outputs are recorded
immediately. If an upstream decision changes, manifest checks mark dependent
products stale rather than silently treating them as compatible.

Closing or canceling an interactive selection tool leaves the manifest and its
accepted artifact unchanged. A canceled tool is reported in the status bar,
not as a failed pipeline stage.

Stages that create or replace artifacts require current parents. For example,
Velcro anchors cannot safely be regenerated from a combined layout whose
target or scalp dependency is stale. Read-only inspection is different:
existing manufacturing geometry can still be opened from the workflow or the
Artifacts table. The app warns when that geometry is historical, because it
should not be used as a current input until the upstream chain is rebuilt.

The shell intentionally leaves long or highly configurable operations, such as
lead-field generation and montage optimization, in the documented service and
walkthrough APIs for now. Those stages still appear in workflow navigation and
artifact status reporting.

## Stage settings

The application exposes common decisions first and keeps uncommon engine
arguments in an **Advanced options** JSON object. Settings are resolved in this
order:

1. stage defaults;
2. the selected preset;
3. values edited in the dialog;
4. advanced engine overrides.

Settings currently apply to the next launch in the open application session.
They do not rewrite accepted artifacts merely by being edited. When the stage
runs, the resolved configuration is returned with the service result and the
new artifacts are registered normally.

The same system can be used without the application:

```matlab
definition = nhpulseStageSettings('crop');
cfg = nhpulseResolveStageSettings('crop', ...
    'preset', 'detailed', ...
    'overrides', struct('showFigures', true));

[cfg, selection] = nhpulseEditStageSettings('retention', struct(), ...
    'preset', 'guided');
```

Schemas are explicit rather than inferred from low-level `inputParser`
definitions. Each schema supplies user-facing labels, help, choices, units,
defaults, presets, and the name of the advanced-options structure. Adding a
new stage to the shared editor therefore requires one schema entry without
writing another settings GUI.

Current smoke tests and walkthroughs write manifests automatically. The import
path is primarily for products created by older NHPulse versions. The default
`discoverLegacy='auto'` scans for these files only when the selected project has
no manifests. To inspect a mixed project containing both registered and older
outputs, launch `nhpulseApp(P.outputRoot, 'discoverLegacy', 'always')`.
