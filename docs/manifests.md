# Run Manifests And Artifact Provenance

NHPulse run manifests inventory products that belong together without moving,
renaming, or changing the cache behavior of existing pipeline files. The first
manifest schema is deliberately generic so new artifact types can be recorded
before a type-specific validator is added.

## Minimal Example

```matlab
manifest = nhpulseCreateManifest(outputDir, 'Subject M2107 cap build', ...
    'metadata', struct('subjectId', 'M2107'));

[manifest, anatomy] = nhpulseRegisterArtifact(manifest, ...
    'nhpulse.anatomy', t1File, 'label', 'T1 anatomy');

[manifest, segmentation] = nhpulseRegisterArtifact(manifest, ...
    'nhpulse.segmentation', segmentationFile, ...
    'parents', nhpulseArtifactRef(anatomy, 'sourceAnatomy'));

manifestFiles = nhpulseSaveManifest(manifest);
report = nhpulseCheckManifest(manifestFiles.mat);
```

`nhpulseSaveManifest` writes both a MATLAB MAT file and readable JSON. By
default they are stored under:

```text
<projectRoot>/manifests/<runId>/nhpulse-manifest.mat
<projectRoot>/manifests/<runId>/nhpulse-manifest.json
```

Files within `projectRoot` are recorded with relative paths. Their content
fingerprints therefore remain meaningful if the entire output tree is moved to
another machine. When the old root is unavailable, `nhpulseLoadManifest`
searches upward from the manifest file for the relocated artifact tree. The
default `fingerprintMode='auto'` uses SHA-256 for files through 256 MB and a
fast, clearly labeled size-and-modification-time fingerprint for larger files.
Users can explicitly request either mode when registering an artifact.

## Artifact Hierarchy

`nhpulseArtifactTypes` defines the built-in dependency vocabulary. Its stages
follow the stable-to-changeable structure of an NHPulse project:

1. anatomy and segmentation;
2. registration, scalp models, crop planes, implants, and exclusions;
3. targets, candidate layouts, lead fields, and optimized montages;
4. combined tES/EEG layouts and predictions;
5. manufacturing geometry, printable STLs, and experimental protocols.

Each definition records a stage, display order, parent policy, accepted parent
types, normal file extensions, and conservative filename patterns for legacy
discovery. The registry is extensible:

```matlab
custom = struct( ...
    'type', 'myLab.behavioralProtocol', ...
    'label', 'Behavioral protocol', ...
    'stage', 'experiment', ...
    'stageOrder', 96, ...
    'parentPolicy', 'listed', ...
    'allowedParentTypes', {{'nhpulse.stimulationProtocol'}});

registry = nhpulseArtifactTypes('additionalTypes', custom);
report = nhpulseCheckManifest(manifest, 'artifactTypes', custom);
```

Omitted definition fields receive permissive defaults. Unknown artifact types
continue to receive generic checks, so adding a new product never requires a
schema migration before it can be recorded.

## Project Inspection

Open an existing output tree and summarize all known runs with:

```matlab
project = nhpulseOpenProject(outputRoot);
status = nhpulseProjectStatus(project);
```

`nhpulseOpenProject` loads each `nhpulse-manifest.mat`, checks its dependency
graph and fingerprints, and read-only scans the `outputs/` subtree for
recognizable files not represented by a manifest. `nhpulseProjectStatus`
reports five states:

- `current`: the file, fingerprint, parents, and known type relationships agree;
- `stale`: the file or an upstream parent has changed;
- `missing`: the recorded file cannot be found;
- `incompatible`: a known type has an invalid extension or parent type;
- `unregistered`: a legacy file was recognized but has no manifest record.

Legacy discovery deliberately does not infer dependency edges. Review a
dry-run import before creating an inventory manifest:

```matlab
preview = nhpulseImportLegacyArtifacts(project);  % dry run by default
imported = nhpulseImportLegacyArtifacts(project, ...
    'selection', {'nhpulse.manufacturingStl'}, 'dryRun', false);
```

Importing fingerprints and registers the selected files in place. It does not
move or rename outputs, and it labels the resulting manifest as a legacy
inventory whose parent relationships remain unspecified.

## Generic Checks

`nhpulseCheckManifest` currently checks:

- artifact files exist,
- current fingerprints match recorded fingerprints,
- artifact IDs are unique,
- parent IDs resolve,
- recorded parent revisions still match,
- the dependency graph contains no cycles, and
- stale or missing state propagates to downstream artifacts.

Artifact types are namespaced strings such as `nhpulse.scalpModel` or
`nhpulse.optimizedMontage`. Known types additionally receive extension and
parent-policy checks. Unknown types receive the generic checks and remain
valid.

## Current Scope

This recorder is additive. Existing output discovery, filenames, and cache
checks remain authoritative for the current pipeline. The synthetic walkthrough
creates a manifest after its normal verification step so the dependency model
can be exercised before it is used to reorganize real subject outputs.

Run `nhpulseTestManifestRecorder` and `nhpulseTestProjectInspection` for fast
self-tests that use only temporary files. Together they verify MAT/JSON round
trips, changed-parent detection, stale-child propagation, extensible artifact
types, project opening, legacy discovery, dry-run import, and incompatible
parent detection.
