function cfg = config_preprocessing_local()
%CONFIG_PREPROCESSING_LOCAL Local configuration for PD0 preprocessing.
%
% This file contains machine-specific paths and should NOT be committed to
% GitHub. Keep it beside run_PD0_preprocessing.m or on the MATLAB path.
%
% The public repository should contain config_preprocessing_example.m instead.

%% Local paths
cfg.mainDir = 'C:\Users\slavenc';

% Folder containing the raw RDI *.PD0 files.
cfg.MainDIR = fullfile(cfg.mainDir, ...
    'OneDrive - NTNU', 'Slaven_PhD', 'RiverPro_BedLoadAlbania', ...
    'DataForprocessing2026', '20170322_Tomorrice_Albania', ...
    'ADCPdata_RiverPro1200', '20170322TomorricaFixed_0');

% Leave empty to create:
%   <MainDIR>\<YYYYMMDD>_processedADCPdata
cfg.savedir = '';

%% PD0 reader and instrument settings
cfg.filePattern = '*.PD0';
cfg.day = '1';               % Survey-day string used by the GGA parser
cfg.MGVAR = 0;               % Magnetic variation [degrees]
cfg.Ed = 0.05;               % Draft/immersion offset [m], retained for compatibility
cfg.trasholdVB = 3;          % Legacy vertical-beam threshold, if used by local helpers

% Third scalar argument passed to processADCP_RDI in the established workflow:
%   processADCP_RDI(RAW, MGVAR, processADCPScalar, savedir, name, opts)
% Its exact meaning depends on the local processADCP_RDI implementation.
cfg.processADCPScalar = 5;

%% processADCP_RDI filtering options
cfg.opts = struct();
cfg.opts.apply_sidelobe    = false;
cfg.opts.apply_depth_limit = true;
cfg.opts.max_depth_m       = 14.0;
cfg.opts.apply_corr        = false;
cfg.opts.apply_pg          = false;
cfg.opts.apply_errvel      = false;
cfg.opts.beamAngle_deg     = 20;
cfg.opts.epsg_code         = 32632;

%% Diagnostics and post-processing
cfg.runSingleFileDiagnostic = false;
cfg.diagnosticFileIndex = 1;
cfg.expandRAWToWorkspace = true;

cfg.displayFilterFractions = true;
cfg.mergeAfterProcessing = true;
cfg.makeOverviewTable = true;
cfg.writeOverviewXlsx = true;

% Empty means the default name:
%   <YYYYMMDD>_processed_file_overview.xlsx
cfg.overviewFileName = '';

%% Runtime behavior
cfg.stopOnFileError = false;
cfg.verbose = true;
end
