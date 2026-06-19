# ADCPx---Preprocessing-PD0
# RDI PD0 Preprocessing

MATLAB preprocessing workflow for converting raw Teledyne RDI `*.PD0` files into the standardized MAT files used by the downstream ADCP bedload-processing toolbox.

The workflow was originally developed by **Slaven Conevski** and has been modernized to use `fread` and little-endian binary helpers while preserving the established variable names and output structures.

## Instrument coverage

The current reader has been used with:

- RiverPro;
- RioGrande;
- StreamPro.

It has **not been fully verified for WorkHorse instruments**. Proprietary firmware changes, owner-specific binary blocks, or non-standard PD0 configurations may require updates to the parser.

## Repository location

Place this folder inside the main repository, for example:

```text
adcp-bedload-processing/
├─ README.md
├─ run_RDI1200_processing.m
├─ config_local.m
├─ src/
└─ preprocessing/
   ├─ README.md
   ├─ run_PD0_preprocessing.m
   ├─ config_preprocessing_example.m
   ├─ config_preprocessing_local.m   # local only; do not commit
   └─ src/
      ├─ readPD0_one_fread.m
      ├─ processADCP_RDI.m
      ├─ pd0_diagnose.m
      ├─ extractDateFromPath.m
      ├─ mergePostprocessedRDI_advanced.m
      ├─ makeSavedirFileTable.m
      └─ parser/helper functions
```

The preprocessing functions may alternatively be placed in the repository-level `src/` folder. The runner adds `preprocessing/src/` recursively by default.

## Main purpose

For every raw PD0 file, the workflow:

1. reads the binary ensembles with `readPD0_one_fread`;
2. preserves the original parsed variable names;
3. runs `processADCP_RDI` with explicit filter options;
4. saves the processed ADCP structures as MAT files;
5. reports the proportions affected by available filters;
6. optionally merges files measured at the same position/time period;
7. creates an overview table that must match the later field-data input table.

The main saved structures produced by `processADCP_RDI` are expected to include:

```matlab
BT
v
CORR
ECHO
SL
VB
GPSdata
Data
```

These processed files are then used by the main workflow through:

```matlab
cfg.folder1200 = '<date>_processedADCPdata';
```

## Installation

1. Put all PD0 reader and preprocessing functions in `preprocessing/src/` or another repository source folder on the MATLAB path.
2. Copy:

```text
config_preprocessing_example.m
```

to:

```text
config_preprocessing_local.m
```

3. Edit `config_preprocessing_local.m` with the local raw-data path and processing options.
4. Run:

```matlab
run_PD0_preprocessing
```

## Local configuration

`config_preprocessing_local.m` contains personal paths and must not be committed to GitHub.

Add these entries to the repository `.gitignore`:

```gitignore
preprocessing/config_preprocessing_local.m
*.PD0
*.pd0
*_processedADCPdata/
*.mat
*.xlsx
```

Upload `config_preprocessing_example.m`, not the local configuration.

## Output-folder naming

The date is extracted from the raw source path using `extractDateFromPath`.

For a source folder such as:

```text
...\20170322_Tomorrice_Albania\ADCPdata_RiverPro1200\20170322TomorricaFixed_0
```

the default output folder is:

```text
20170322_processedADCPdata
```

This avoids manually assigning an output folder from a different survey date.

## Configuration parameters

### Reader and instrument parameters

```matlab
cfg.day = '1';
cfg.MGVAR = 0;
cfg.Ed = 0.05;
cfg.trasholdVB = 3;
cfg.processADCPScalar = 5;
```

`day` is retained for the GGA parser. `MGVAR` is the magnetic variation in degrees.

`Ed` and `trasholdVB` are retained because they existed in the legacy workflow, but the exact shown call to `processADCP_RDI` does not use them directly. Confirm whether your local helper functions require them.

The meaning of `processADCPScalar` depends on the local signature of `processADCP_RDI.m`. The established workflow passes the value `5` as the third scalar argument. Verify this before generalizing the code to another instrument or survey.

### Filter options

```matlab
cfg.opts.apply_sidelobe    = false;
cfg.opts.apply_depth_limit = true;
cfg.opts.max_depth_m       = 14.0;
cfg.opts.apply_corr        = false;
cfg.opts.apply_pg          = false;
cfg.opts.apply_errvel      = false;
cfg.opts.beamAngle_deg     = 20;
cfg.opts.epsg_code         = 32632;
```

These options are passed directly to `processADCP_RDI`. They should be selected for the instrument, deployment geometry, coordinate system, and study objectives.

Disabling a filter does not mean the diagnostic mask is unavailable. Where supported by `processADCP_RDI`, `Data.filter_info` records what the filter would remove.

## Coordinate-system warning

The PD0 extended-system configuration field `EX` can indicate that data are already in Earth coordinates. The runner checks for the `11xxx` coordinate bits and warns when Earth-coordinate ensembles are detected.

This is important because applying another beam-to-Earth transformation to data that are already transformed will corrupt the velocity components.

## Single-file diagnostics

Enable:

```matlab
cfg.runSingleFileDiagnostic = true;
cfg.diagnosticFileIndex = 1;
```

The runner then calls:

```matlab
pd0_diagnose(...)
```

before batch processing. This is recommended when reading data from a new instrument, firmware version, or binary configuration.

## Merging processed files

When:

```matlab
cfg.mergeAfterProcessing = true;
```

the runner calls:

```matlab
mergePostprocessedRDI_advanced(savedir)
```

Use this only for files that represent the same measurement position and a continuous or intentionally combined time period. Review the merged filename and ensemble order before preparing the input table.

## Overview table and input-table matching

When enabled, the runner calls:

```matlab
Tfiles = makeSavedirFileTable(savedir);
```

and can write:

```text
<YYYYMMDD>_processed_file_overview.xlsx
```

The filenames and row order in the later field-data input table must correspond to the final processed/merged MAT files. This matching is critical because downstream functions align:

- `ADCPfilename`;
- `StartADCP` and `EndADCP` trim counts;
- cross-section position;
- grain-size samples;
- measured transport rates;
- processed ADCP time series.

## Relationship to the main processing toolbox

After successful preprocessing, use the generated folder as `folder1200` in the main local configuration:

```matlab
cfg.folder1200 = fullfile(..., '20170322_processedADCPdata');
```

The main workflow then runs:

1. depth/range processing;
2. water-profile processing;
3. apparent bedload-velocity filtering;
4. shear-stress calculations;
5. kinematic transport calculations;
6. acoustic-parameter calculations;
7. backscatter processing;
8. structure packaging and validation.

## Important corrections relative to the legacy script

The GitHub runner intentionally corrects several unsafe patterns from the one-off script:

- it does not hard-code a second survey's `savedir` after processing;
- it does not assume that a second PD0 file exists for diagnostics;
- it checks that required functions and folders exist;
- it sorts source filenames deterministically;
- it records per-file success/error information;
- it can continue to the next file after one failure;
- it derives the output date from the active source folder;
- it keeps private paths in `config_preprocessing_local.m`.

## Data and GitHub policy

Do not upload:

- raw PD0 files;
- processed MAT files;
- merged field datasets;
- private input tables;
- personal OneDrive paths;
- confidential project data.

Upload:

- MATLAB source functions you are allowed to redistribute;
- `run_PD0_preprocessing.m`;
- `config_preprocessing_example.m`;
- this README;
- optionally, a very small anonymized test PD0 file when redistribution is permitted.

## Reproducibility checklist

Before a public release:

- document the tested MATLAB version;
- list required MATLAB toolboxes;
- record tested RDI instrument and firmware configurations;
- document the meaning of the third scalar input to `processADCP_RDI`;
- include one small non-confidential test case;
- record expected ensemble counts and output structures;
- add a software license only after checking ownership of all parser/helper code.

## Troubleshooting

### No PD0 files found

Check:

```matlab
cfg.MainDIR
cfg.filePattern
```

and verify whether the extension is `.PD0` or `.pd0`.

### No date found in the path

At least one source-folder component should contain an eight-digit date such as `20170322`. Alternatively, set `cfg.savedir` explicitly.

### Parser fails on one file

Run:

```matlab
cfg.runSingleFileDiagnostic = true;
```

and inspect the raw block layout with `pd0_diagnose`.

### Coordinate warning

Inspect `RAW.EX` and the transformation steps in `processADCP_RDI`. Do not apply a second coordinate transformation to Earth-coordinate data.

### Input table does not match processed files

Regenerate the overview with `makeSavedirFileTable`, verify merged filenames, and update the input table before running the main bedload workflow.
