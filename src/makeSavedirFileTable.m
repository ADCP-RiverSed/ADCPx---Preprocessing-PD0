function Tfiles = makeSavedirFileTable(savedir)
%MAKESAVEDIRFILETABLE Make overview table of .mat files in savedir.
%
% Creates:
%   1) MATLAB table shown in Command Window
%   2) CSV file
%   3) XLSX file
%   4) tab-separated text copied to clipboard for direct Excel paste
%
% Usage:
%   Tfiles = makeSavedirFileTable(savedir);

    if nargin < 1 || isempty(savedir)
        savedir = uigetdir(pwd, 'Select savedir with processed ADCP .mat files');
        if isequal(savedir, 0)
            disp('Cancelled.');
            Tfiles = table();
            return
        end
    end

    if ~exist(savedir, 'dir')
        error('Folder does not exist:\n%s', savedir);
    end

    files = dir(fullfile(savedir, '*.mat'));

    if isempty(files)
        warning('No .mat files found in:\n%s', savedir);
        Tfiles = table();
        return
    end

    fileNames = {files.name}';

    % Natural sort if sort_nat exists
    if exist('sort_nat', 'file') == 2
        [~, idx] = sort_nat(fileNames, 'ascend');
    else
        [~, idx] = sort(lower(fileNames));
    end

    files = files(idx);
    fileNames = {files.name}';

    n = numel(files);

    Index        = (1:n)';
    FileName     = fileNames;
    Prefix       = cell(n,1);
    IsMerged     = false(n,1);
    Size_MB      = zeros(n,1);
    DateModified = strings(n,1);
    FullPath     = cell(n,1);

    for i = 1:n

        thisName = files(i).name;

        % Prefix before first underscore
        token = regexp(thisName, '^[^_]+_', 'match', 'once');

        if isempty(token)
            [~, baseName, ~] = fileparts(thisName);
            token = baseName;
        else
            token = erase(token, '_');
        end

        Prefix{i} = token;

        IsMerged(i) = contains(lower(thisName), 'merged');

        Size_MB(i) = files(i).bytes / 1024^2;

        DateModified(i) = string(files(i).date);

        FullPath{i} = fullfile(savedir, thisName);
    end

    Tfiles = table(Index, Prefix, FileName, IsMerged, Size_MB, DateModified, FullPath);

    % Display table
    disp(Tfiles);

    % Output names
    outCsv  = fullfile(savedir, 'ADCP_file_overview.csv');
    outXlsx = fullfile(savedir, 'ADCP_file_overview.xlsx');

    % Save CSV
    writetable(Tfiles, outCsv);

    % Save Excel
    try
        writetable(Tfiles, outXlsx);
    catch
        warning('Could not write XLSX file. CSV was still created.');
    end

    % Copy tab-separated version to clipboard for Excel
    try
        txt = tableToTabText(Tfiles);
        clipboard('copy', txt);
        fprintf('\nTable copied to clipboard. You can paste directly into Excel.\n');
    catch
        warning('Could not copy table to clipboard.');
    end

    fprintf('\nSaved file overview:\n%s\n', outCsv);

    if exist(outXlsx, 'file')
        fprintf('%s\n', outXlsx);
    end
end


function txt = tableToTabText(T)
%TABLETOTABTEXT Convert MATLAB table to tab-separated text for Excel paste.

    varNames = T.Properties.VariableNames;

    lines = strings(height(T) + 1, 1);

    % Header
    lines(1) = strjoin(string(varNames), sprintf('\t'));

    % Rows
    for i = 1:height(T)

        rowValues = strings(1, width(T));

        for j = 1:width(T)

            value = T{i,j};

            if iscell(value)
                value = value{1};
            end

            if isstring(value)
                rowValues(j) = value;

            elseif ischar(value)
                rowValues(j) = string(value);

            elseif isnumeric(value) || islogical(value)
                rowValues(j) = string(value);

            elseif isdatetime(value)
                rowValues(j) = string(value);

            else
                rowValues(j) = string(value);
            end
        end

        lines(i+1) = strjoin(rowValues, sprintf('\t'));
    end

    txt = strjoin(lines, newline);
end