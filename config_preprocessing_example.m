function cfg = config_preprocessing_example()
%CONFIG_PREPROCESSING_EXAMPLE Public template for PD0 preprocessing.
%
% Copy this file to config_preprocessing_local.m and edit the local paths.
% Do not commit config_preprocessing_local.m to GitHub.

%% Local paths
cfg.mainDir = 'C:\Users\YOUR_USERNAME';

cfg.MainDIR = fullfile(cfg.mainDir, ...
    'path', 'to', 'folder', 'containing', 'raw_PD0_files');

% Leave empty to derive <YYYYMMDD>_processedADCPdata from MainDIR.
cfg.savedir = '';

%% PD0 reader and instrument settings
cfg.filePattern = '*.PD0';
cfg.day = '1';
cfg.MGVAR = 0;               % degrees
cfg.Ed = 0.05;               % m; retained for compatibility
cfg.trasholdVB = 3;          % legacy setting, if used by local helpers
cfg.processADCPScalar = 5;   % verify against processADCP_RDI.m

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
cfg.overviewFileName = '';

%% Runtime behavior
cfg.stopOnFileError = false;
cfg.verbose = true;
end
