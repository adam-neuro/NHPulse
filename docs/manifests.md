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
`nhpulse.montage`. Unknown types receive these generic checks and remain valid.
Future type definitions can add specialized schemas and validators without
changing the manifest envelope or dependency traversal.

## Current Scope

This recorder is additive. Existing output discovery, filenames, and cache
checks remain authoritative for the current pipeline. The synthetic walkthrough
creates a manifest after its normal verification step so the dependency model
can be exercised before it is used to reorganize real subject outputs.

Run `nhpulseTestManifestRecorder` for a fast self-test that uses only temporary
files and verifies MAT/JSON round trips, changed-parent detection, stale-child
propagation, and acceptance of an unregistered extension artifact type.
