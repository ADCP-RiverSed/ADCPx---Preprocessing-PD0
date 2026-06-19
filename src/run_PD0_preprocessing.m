%% RDI PD0 preprocessing
% Slaven Conevski
%
% Batch reads raw RDI PD0 files using readPD0_one_fread, applies the local
% processADCP_RDI workflow, saves one MAT file per source file, optionally
% merges compatible files, and creates an overview table for the later
% input-table and bedload-processing workflow.
%
% Supported by the current reader: StreamPro, RioGrande and RiverPro.
% WorkHorse has not been verified. Non-standard firmware/binary blocks may
% require updates to the PD0 parser.

clearvars;
clc;

%% Repository paths and local configuration
scriptDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(scriptDir, 'src')));

if exist('config_preprocessing_local', 'file') ~= 2
    error(['config_preprocessing_local.m was not found. Copy ', ...
        'config_preprocessing_example.m to config_preprocessing_local.m ', ...
        'and edit the local paths.']);
end

cfg = config_preprocessing_local();

requiredFunctions = { ...
    'readPD0_one_fread', ...
    'processADCP_RDI', ...
    'extractDateFromPath', ...
    'mergePostprocessedRDI_advanced', ...
    'makeSavedirFileTable'};

for iRequired = 1:numel(requiredFunctions)
    if exist(requiredFunctions{iRequired}, 'file') ~= 2
        error('Required function not found on the MATLAB path: %s.m', ...
            requiredFunctions{iRequired});
    end
end

if ~isfolder(cfg.MainDIR)
    error('Raw PD0 folder does not exist:\n%s', cfg.MainDIR);
end

%% Input and output folders
dateStr = extractDateFromPath(cfg.MainDIR);

if isempty(dateStr)
    error(['No date in YYYYMMDD format was found in cfg.MainDIR. ', ...
        'Rename a source folder or set cfg.savedir explicitly.']);
end

if isempty(cfg.savedir)
    savedir = fullfile(cfg.MainDIR, [dateStr '_processedADCPdata']);
else
    savedir = cfg.savedir;
end

if ~isfolder(savedir)
    mkdir(savedir);
end

DIR = dir(fullfile(cfg.MainDIR, cfg.filePattern));
DIR = DIR(~[DIR.isdir]);

if isempty(DIR)
    error('No files matching %s were found in:\n%s', ...
        cfg.filePattern, cfg.MainDIR);
end

% Deterministic filename order.
[~, sortIndex] = sort(lower(string({DIR.name})));
DIR = DIR(sortIndex);

if cfg.verbose
    fprintf('\n=== RDI PD0 preprocessing ===\n');
    fprintf('Raw folder:      %s\n', cfg.MainDIR);
    fprintf('Output folder:   %s\n', savedir);
    fprintf('Date prefix:     %s\n', dateStr);
    fprintf('PD0 files found: %d\n', numel(DIR));
end

%% Optional inspection of one raw file
if cfg.runSingleFileDiagnostic
    if exist('pd0_diagnose', 'file') ~= 2
        warning('pd0_diagnose.m was not found; diagnostic step skipped.');
    else
        diagnosticIndex = max(1, min(round(cfg.diagnosticFileIndex), numel(DIR)));
        pd0_diagnose(fullfile(cfg.MainDIR, DIR(diagnosticIndex).name));
    end
end

%% Process every PD0 file
ProcessingFile = strings(numel(DIR),1);
ProcessingStatus = strings(numel(DIR),1);
ProcessingMessage = strings(numel(DIR),1);
Nensembles = nan(numel(DIR),1);

for Di = 1:numel(DIR)
    name = DIR(Di).name;
    ProcessingFile(Di) = string(name);

    if cfg.verbose
        fprintf('\nReading file %d/%d: %s\n', Di, numel(DIR), name);
    end

    try
        %% Raw PD0 reading layer
        RAW = readPD0_one_fread(fullfile(cfg.MainDIR, name), cfg.day);

        if ~isfield(RAW, 'nens')
            error('RAW.nens is missing after reading %s.', name);
        end
        Nensembles(Di) = RAW.nens;

        % Optional compatibility behavior: expose RAW fields in this script
        % workspace using their original names.
        if cfg.expandRAWToWorkspace
            rawFields = fieldnames(RAW);
            for k = 1:numel(rawFields)
                assignin('caller', rawFields{k}, RAW.(rawFields{k}));
            end
        end

        %% Coordinate-system warning
        if isfield(RAW, 'EX') && ~isempty(RAW.EX)
            coordBits = string(RAW.EX(:,1:min(2,size(RAW.EX,2))));
            if any(coordBits(:) == "11")
                warning(['Some ensembles report EX = 11xxx (Earth coordinates). ', ...
                    'Check processADCP_RDI carefully to avoid transforming ', ...
                    'Earth-coordinate data a second time.']);
            end
        end

        %% Post-processing
        [BT, v, CORR, ECHO, SL, VB, GPSdata, Data] = processADCP_RDI( ...
            RAW, ...
            cfg.MGVAR, ...
            cfg.processADCPScalar, ...
            savedir, ...
            name, ...
            cfg.opts); %#ok<ASGLU>

        %% Filter diagnostics
        if cfg.displayFilterFractions && isstruct(Data) && ...
                isfield(Data, 'filter_info')
            displayMaskFraction(Data.filter_info, 'sidelobe_mask', 'sidelobe');
            displayMaskFraction(Data.filter_info, 'corr_mask', 'correlation');
            displayMaskFraction(Data.filter_info, 'pg_mask', 'percent-good');
            displayMaskFraction(Data.filter_info, 'errvel_mask', 'error velocity');
        end

        ProcessingStatus(Di) = "OK";
        ProcessingMessage(Di) = "";

    catch ME
        ProcessingStatus(Di) = "ERROR";
        ProcessingMessage(Di) = string(ME.message);

        warning('PD0 preprocessing failed for %s:\n%s', name, ME.message);

        if cfg.stopOnFileError
            rethrow(ME);
        end
    end
end

ProcessingSummary = table( ...
    (1:numel(DIR))', ...
    ProcessingFile, ...
    Nensembles, ...
    ProcessingStatus, ...
    ProcessingMessage, ...
    'VariableNames', { ...
    'FileNumber', 'PD0filename', 'Nensembles', 'Status', 'Message'});

disp(ProcessingSummary);

%% Merge files measured at the same position/time period
if cfg.mergeAfterProcessing
    mergePostprocessedRDI_advanced(savedir);
end

%% Create overview table used to prepare/check the input table
Tfiles = table();
if cfg.makeOverviewTable
    Tfiles = makeSavedirFileTable(savedir);

    if cfg.writeOverviewXlsx
        if isempty(cfg.overviewFileName)
            overviewFileName = [dateStr '_processed_file_overview.xlsx'];
        else
            overviewFileName = cfg.overviewFileName;
        end

        overviewFile = fullfile(savedir, overviewFileName);
        writetable(Tfiles, overviewFile);

        if cfg.verbose
            fprintf('Overview table written to:\n%s\n', overviewFile);
        end
    end
end

%% Final summary
fprintf('\n=== Preprocessing complete ===\n');
fprintf('Successful files: %d/%d\n', sum(ProcessingStatus == "OK"), numel(DIR));
fprintf('Processed MAT folder: %s\n', savedir);
fprintf(['Use this folder as Folder1200 in the main bedload-processing ', ...
    'configuration.\n']);

%% Local helper
function displayMaskFraction(filterInfo, fieldName, label)
if isfield(filterInfo, fieldName)
    mask = filterInfo.(fieldName);
    if ~isempty(mask)
        fprintf('%s mask: %.3f %% of cells\n', ...
            label, 100 .* mean(logical(mask(:)), 'omitnan'));
    end
end
end
