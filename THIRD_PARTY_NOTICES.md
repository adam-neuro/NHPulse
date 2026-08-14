# Third-Party Notices

NHPulse includes code derived from or designed to work with several external
research-software projects. 

Known dependencies and inherited components:

- ROAST: GPL-licensed transcranial electric stimulation modeling pipeline.
  NHPulse currently vendors a modified ROAST copy for reviewer/user
  reproducibility. The original README is preserved in `docs/ROAST_README.md`;
  modified files should retain upstream notices and should be documented in the
  release notes.
- `inpolyhedron.m`: MATLAB File Exchange utility by Sven Holcombe, distributed
  under a BSD-style license. The license text is preserved in
  `licenses/inpolyhedron-BSD.txt`.
- SPM, iso2mesh/TetGen, GetDP, Gmsh, CVX, and NIfTI utilities may be required
  by parts of the pipeline but should generally be installed as external
  dependencies rather than vendored in this release repository.

