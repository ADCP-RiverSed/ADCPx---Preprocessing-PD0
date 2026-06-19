%% Slaven Conevski 02/11/2017
% Modernised PD0 batch reader using fread + little-endian helpers
% reads Stream Pro RGrande, and RiverPro, not tested on WorkhHorse 
% any changes in the bianry (e.g., special request by the owner to RDI) can
% cause feil,but it is easy to de-bug
% Keeps the original variable names, post-processing pattern, save
% structures, and MAT-file output.
clear all; clc

% maindir = 'C:\Users\slc';
maindir = 'C:\Users\slavenc';
% maindir = 'D:';

% Function directories, in this case  \PD0processing
addpath(genpath([maindir '\OneDrive - NTNU\ADCPdataColin\functiosforprocesingNIWA\PD0processing']));

% MainDIR = [maindir '\OneDrive - NTNU\Po_river_2023\ADCP2024'];
% MainDIR = [maindir '\OneDrive - NTNU\Rheine2\allADCP_RDIboat\20210622_fixedboat']

MainDIR = [maindir '\OneDrive - NTNU\Slaven_PhD\RiverPro_BedLoadAlbania\DataForprocessing2026\20170322_Tomorrice_Albania\ADCPdata_RiverPro1200\20170322TomorricaFixed_0']; 
% cd(MainDIR)
MGVAR      = 0;      % Playback magnetic variation [deg]
Ed         = 0.05;   % Draft / immersion offset [m]
day     = '1';    % Survey day string used by GGA parser.. not really needed
trasholdVB = 3;

dateStr = extractDateFromPath(MainDIR);

% Create folder like: 20161202_processedADCPdata
savedir = fullfile(MainDIR, [dateStr '_processedADCPdata']);

if ~exist(savedir, 'dir')
    mkdir(savedir);
end

DIR = dir(fullfile(MainDIR,'*.PD0'));
    name = DIR(2).name;

% check one file if interested of teh content if the readPD0_one_fread is
% able to read
   % pd0_diagnose(fullfile(MainDIR,name))


for Di = 1:numel(DIR)
% Di = 2
    clearvars -except Di DIR savedir MainDIR maindir MGVAR Ed giorno trasholdVB day

    name = DIR(Di).name;
    file = Di;

    fprintf('\nReading file %d/%d: %s\n',Di,numel(DIR),name);

    % ---------------------------------------------------------------------
    % RAW PD0 READING LAYER
    % ---------------------------------------------------------------------
    RAW = readPD0_one_fread(fullfile(MainDIR,name),day);

    % Push parsed variables into the workspace using the same names your
    % original script expects downstream.
    fn = fieldnames(RAW);
    for k = 1:numel(fn)
        eval([fn{k} ' = RAW.(fn{k});']);
    end

    nens = RAW.nens;

    % Optional coordinate-system warning.
    if exist('EX','var') && ~isempty(EX)
        coordBits = EX(:,1:2);
        if any(strcmp(string(coordBits),'11'))
            warning(['Some ensembles report EX = 11xxx (Earth coordinates). ', ...
                     'Your downstream beam->ENU conversion code is preserved as requested, ', ...
                     'so check carefully that you are not double-transforming those data.']);
        end
    end

    % ---------------------------------------------------------------------
    % POST-PROCESSING 1 (Depends on the application, might contain errors,
    % Please check. and choose the proper options. Open the processADCP_RDI
    % and onvestigate
    % ---------------------------------------------------------------------
opts.apply_sidelobe    = false;
opts.apply_depth_limit = true;
opts.max_depth_m       = 14.0;
opts.apply_corr        = false;
opts.apply_pg          = false;
opts.apply_errvel      = false;
opts.beamAngle_deg     = 20;
opts.epsg_code         = 32632;
[BT,v,CORR,ECHO,SL,VB,GPSdata,Data] = processADCP_RDI(RAW, MGVAR, 5, savedir,name,opts); 
% Example ...  See what sidelobe filter would remove
% figure; imagesc(Data.filter_info.sidelobe_mask); title('Sidelobe mask — 1=would be removed');

% See fraction each filter would remove
disp(100*mean(Data.filter_info.sidelobe_mask(:)))  % % cells in sidelobe zone
disp(100*mean(Data.filter_info.corr_mask(:)))       % % low-correlation cells
disp(100*mean(Data.filter_info.pg_mask(:)))   
end

savedir = 'C:\Users\slavenc\OneDrive - NTNU\Slaven_PhD\RiverPro_BedLoadAlbania\DataForprocessing2026\20161202_Tomorrice_Albania\20161202Dec2\processedADCPdata' 

% Merge the files that needs to be merged (same positon, same time frame)
mergePostprocessedRDI_advanced(savedir);

%ADD renaming BEFORE RUNING the input table 


% Make overview table for Excel...IMPORTANT this must macth the data in the
% table also critical fo rfurte rproicessing 
Tfiles = makeSavedirFileTable(savedir);

