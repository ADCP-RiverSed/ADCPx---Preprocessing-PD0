function mergePostprocessedRDI_advanced(Folder)
%MERGEPOSTPROCESSEDRDI_ADVANCED Advanced interactive merge of postprocessed RDI .mat files.
%
% This function:
%   - looks for .mat files in Folder
%   - ignores files already containing "merged"
%   - groups files by prefix before first "_"
%   - allows several merge batches inside the same prefix group
%   - does NOT delete original files
%
% Example:
%   If files are:
%       1   100_fileA.mat
%       2   100_fileB.mat
%       3   100_fileC.mat
%       4   100_fileD.mat
%       5   100_fileE.mat
%
%   Enter:
%       1:3; 4:5
%
%   Output:
%       100_merged_01.mat
%       100_merged_02.mat
%
% Main script call:
%   mergePostprocessedRDI_advanced(savedir)

    if nargin < 1 || isempty(Folder)
        Folder = uigetdir(pwd, 'Select folder with postprocessed ADCP .mat files');

        if isequal(Folder, 0)
            disp('Merge cancelled.');
            return
        end
    end

    if ~exist(Folder, 'dir')
        error('Folder does not exist:\n%s', Folder);
    end

    files = dir(fullfile(Folder, '*.mat'));

    if isempty(files)
        warning('No .mat files found in folder:\n%s', Folder);
        return
    end

    filesRS = {files.name}';

    % Ignore already merged files
    isMerged = contains(lower(filesRS), 'merged');
    filesRS  = filesRS(~isMerged);

    if isempty(filesRS)
        warning('No non-merged .mat files found in folder:\n%s', Folder);
        return
    end

    % Natural sort if sort_nat exists, otherwise normal sort
    if exist('sort_nat', 'file') == 2
        [~, idx] = sort_nat(filesRS, 'ascend');
        filesRS = filesRS(idx);
    else
        filesRS = sort(filesRS);
    end

    % Build prefix before first underscore
    % Example:
    %   100_test1.mat  -> 100_
    %   100_test2.mat  -> 100_
    prefixAll = cell(size(filesRS));

    for i = 1:numel(filesRS)
        token = regexp(filesRS{i}, '^[^_]+_', 'match', 'once');

        if isempty(token)
            % If no underscore exists, use filename without extension
            [~, baseName, ~] = fileparts(filesRS{i});
            token = [baseName '_'];
        end

        prefixAll{i} = token;
    end

    % Stable unique prefixes, robust also for older MATLAB versions
    [uniquePrefix, ic] = uniqueStableCell(prefixAll);

    % Keep only groups with at least 2 files
    groupLabels = {};
    groupIDs    = [];

    for g = 1:numel(uniquePrefix)
        idxGroup = find(ic == g);

        if numel(idxGroup) >= 2
            groupIDs(end+1) = g; %#ok<AGROW>
            groupLabels{end+1} = sprintf('%s   (%d files)', ...
                uniquePrefix{g}, numel(idxGroup)); %#ok<AGROW>
        end
    end

    if isempty(groupIDs)
        disp('No groups with 2 or more files found. Nothing to merge.');
        return
    end

    % Select prefix groups
    [selGroups, ok] = listdlg( ...
        'PromptString', 'Select prefix groups to work with:', ...
        'SelectionMode', 'multiple', ...
        'ListString', groupLabels, ...
        'ListSize', [600 350]);

    if ~ok || isempty(selGroups)
        disp('No groups selected. Merge cancelled.');
        return
    end

    selectedGroupIDs = groupIDs(selGroups);

    for gg = 1:numel(selectedGroupIDs)

        g = selectedGroupIDs(gg);
        thisPrefix = uniquePrefix{g};

        idxGroup = find(ic == g);
        groupFiles = filesRS(idxGroup);

        fprintf('\n====================================================\n');
        fprintf('Prefix group: %s\n', thisPrefix);
        fprintf('Files available for merging:\n\n');

        for i = 1:numel(groupFiles)
            fprintf('%3d   %s\n', i, groupFiles{i});
        end

        fprintf('\nExamples of valid merge commands:\n');
        fprintf('  1:3\n');
        fprintf('  1:3; 4:5\n');
        fprintf('  1,2,3; 4,5\n');
        fprintf('  1:3; 4:5; 6:8\n\n');

        defaultBatch = sprintf('1:%d', numel(groupFiles));

        prompt = {sprintf(['Enter merge batches for prefix "%s".\n\n', ...
            'Use semicolon or new line between output files.\n\n', ...
            'Examples:\n', ...
            '1:3; 4:5\n', ...
            '1,2,3; 4,5\n\n', ...
            'Available file index range: 1:%d'], ...
            thisPrefix, numel(groupFiles))};

        dlgtitle = 'Define merge batches';
        dims = [9 85];
        definput = {defaultBatch};

        answer = inputdlg(prompt, dlgtitle, dims, definput);

        if isempty(answer)
            fprintf('Skipped prefix "%s".\n', thisPrefix);
            continue
        end

        mergeText = strtrim(answer{1});

        if isempty(mergeText)
            fprintf('Skipped prefix "%s" because no merge batches were entered.\n', thisPrefix);
            continue
        end

        try
            mergeBatches = parseMergeBatches(mergeText, numel(groupFiles));
        catch ME
            warning('Could not parse merge batches for prefix "%s":\n%s', ...
                thisPrefix, ME.message);
            continue
        end

        if isempty(mergeBatches)
            fprintf('No valid merge batches for prefix "%s".\n', thisPrefix);
            continue
        end

        % Output base name
        defaultBase = [thisPrefix 'merged'];

        answerName = inputdlg( ...
            {sprintf(['Output base name for prefix "%s".\n\n', ...
            'The function will add _01, _02, etc.\n\n', ...
            'Example output:\n%s_01.mat'], ...
            thisPrefix, defaultBase)}, ...
            'Output name', ...
            [4 85], ...
            {defaultBase});

        if isempty(answerName)
            fprintf('Skipped prefix "%s".\n', thisPrefix);
            continue
        end

        outBaseName = strtrim(answerName{1});

        if isempty(outBaseName)
            outBaseName = defaultBase;
        end

        % Print planned merge batches
        fprintf('\nPlanned merge batches for prefix "%s":\n', thisPrefix);

        for b = 1:numel(mergeBatches)
            thisIdx = mergeBatches{b};
            outName = sprintf('%s_%02d.mat', outBaseName, b);

            fprintf('\nOutput %d: %s\n', b, outName);

            for ii = 1:numel(thisIdx)
                fprintf('   %3d   %s\n', thisIdx(ii), groupFiles{thisIdx(ii)});
            end
        end

        choice = questdlg( ...
            sprintf('Proceed with merging prefix "%s"?', thisPrefix), ...
            'Confirm merge', ...
            'Yes', 'No', 'No');

        if ~strcmp(choice, 'Yes')
            fprintf('Skipped prefix "%s".\n', thisPrefix);
            continue
        end

        % Perform each merge batch
        for b = 1:numel(mergeBatches)

            thisIdx = mergeBatches{b};
            selectedFiles = groupFiles(thisIdx);

            outName = sprintf('%s_%02d.mat', outBaseName, b);
            outPath = fullfile(Folder, outName);

            if exist(outPath, 'file')
                answerOverwrite = questdlg( ...
                    sprintf('File already exists:\n%s\n\nOverwrite?', outName), ...
                    'File exists', ...
                    'Yes', 'No', 'No');

                if ~strcmp(answerOverwrite, 'Yes')
                    fprintf('Skipped existing output file: %s\n', outName);
                    continue
                end
            end

            fprintf('\nMerging batch %d/%d for prefix "%s"\n', ...
                b, numel(mergeBatches), thisPrefix);

            for i = 1:numel(selectedFiles)
                fprintf('   %s\n', selectedFiles{i});
            end

            try
                [BT, v, Data, GPSdata, CORR, ECHO] = mergeOneBatch(Folder, selectedFiles);
            catch ME
                warning('Merge failed for batch %d of prefix "%s":\n%s', ...
                    b, thisPrefix, ME.message);
                continue
            end

            save(outPath, 'BT', 'v', 'Data', 'GPSdata', 'CORR', 'ECHO');

            fprintf('Saved merged file:\n%s\n', outPath);
            fprintf('Original files were NOT deleted.\n');
        end
    end

    disp('Advanced interactive merge finished.');
end


function [uniqueList, ic] = uniqueStableCell(inputCell)
%UNIQUESTABLECELL Stable unique for cell array of strings/chars.
%
% Avoids potential older MATLAB issues with:
%   [C,~,ic] = unique(...,'stable')

    uniqueList = {};
    ic = zeros(numel(inputCell), 1);

    for i = 1:numel(inputCell)

        thisValue = inputCell{i};
        foundID = [];

        for j = 1:numel(uniqueList)
            if strcmp(thisValue, uniqueList{j})
                foundID = j;
                break
            end
        end

        if isempty(foundID)
            uniqueList{end+1,1} = thisValue; %#ok<AGROW>
            foundID = numel(uniqueList);
        end

        ic(i) = foundID;
    end
end


function mergeBatches = parseMergeBatches(mergeText, nFiles)
%PARSEMERGEBATCHES Convert text like '1:3; 4:5' into index batches.

    % Accept semicolon or new line as batch separator
    mergeText = strrep(mergeText, newline, ';');
    mergeText = strrep(mergeText, char(10), ';');
    mergeText = strrep(mergeText, char(13), ';');

    rawBatches = regexp(mergeText, ';', 'split');

    mergeBatches = {};

    for b = 1:numel(rawBatches)

        txt = strtrim(rawBatches{b});

        if isempty(txt)
            continue
        end

        idx = [];

        % Split within one batch by comma or spaces
        parts = regexp(txt, '[,\s]+', 'split');

        for p = 1:numel(parts)

            part = strtrim(parts{p});

            if isempty(part)
                continue
            end

            % Range, e.g. 1:3
            if contains(part, ':')

                rangeParts = regexp(part, ':', 'split');

                if numel(rangeParts) ~= 2
                    error('Invalid range: "%s"', part);
                end

                a = str2double(rangeParts{1});
                c = str2double(rangeParts{2});

                if isnan(a) || isnan(c)
                    error('Invalid number in range: "%s"', part);
                end

                if a > c
                    error('Invalid descending range: "%s"', part);
                end

                idx = [idx, a:c]; %#ok<AGROW>

            else
                val = str2double(part);

                if isnan(val)
                    error('Invalid file index: "%s"', part);
                end

                idx = [idx, val]; %#ok<AGROW>
            end
        end

        idx = unique(idx, 'stable');

        if any(idx < 1) || any(idx > nFiles)
            error('One or more indices are outside the valid range 1:%d.', nFiles);
        end

        if numel(idx) < 2
            warning('Batch "%s" has fewer than 2 files and will be skipped.', txt);
            continue
        end

        mergeBatches{end+1} = idx; %#ok<AGROW>
    end
end


function [BT, v, Data, GPSdata, CORR, ECHO] = mergeOneBatch(Folder, selectedFiles)
%MERGEONEBATCH Merge one selected batch of RDI postprocessed .mat files.

    S1 = load(fullfile(Folder, selectedFiles{1}));

    requiredVars = {'BT', 'Data', 'v', 'ECHO', 'CORR'};

    for r = 1:numel(requiredVars)
        if ~isfield(S1, requiredVars{r})
            error('File "%s" does not contain variable "%s".', ...
                selectedFiles{1}, requiredVars{r});
        end
    end

    BT   = S1.BT;
    Data = S1.Data;
    v    = S1.v;
    ECHO = S1.ECHO;
    CORR = S1.CORR;

    if isfield(S1, 'GPSdata')
        GPSdata = S1.GPSdata;
    else
        GPSdata = [];
    end

    for k = 2:numel(selectedFiles)

        fname = fullfile(Folder, selectedFiles{k});
        S2 = load(fname);

        for r = 1:numel(requiredVars)
            if ~isfield(S2, requiredVars{r})
                error('File "%s" does not contain variable "%s".', ...
                    selectedFiles{k}, requiredVars{r});
            end
        end

        BT   = CatStructFields(BT,   S2.BT);
        Data = CatStructFields(Data, S2.Data);
        v    = CatStructFields(v,    S2.v);
        ECHO = CatStructFields(ECHO, S2.ECHO);
        CORR = CatStructFields(CORR, S2.CORR);

        % Direct GPSdata handling, no separate GPS helper function
        if isfield(S2, 'GPSdata')

            if isempty(GPSdata)
                GPSdata = S2.GPSdata;

            elseif isempty(S2.GPSdata)
                % Keep existing GPSdata

            elseif isstruct(GPSdata) && isstruct(S2.GPSdata)
                GPSdata = CatStructFields(GPSdata, S2.GPSdata);

            else
                % If one is char/string, for example 'no GPS',
                % keep the latest available value.
                GPSdata = S2.GPSdata;
            end
        end
    end
end


function A = CatStructFields(v1, v2)
%CATSTRUCTFIELDS Robustly concatenate matching fields from two structures.
%
% Designed for merging postprocessed ADCP structures:
%   BT, Data, v, ECHO, CORR, GPSdata
%
% Main behaviour:
%   - uses union of fields from both structures
%   - handles missing fields
%   - handles empty fields
%   - handles nested structures recursively
%   - pads 2D numeric arrays safely
%   - uses NaN padding for floating-point numeric arrays
%   - avoids replacing numeric fields with text such as 'different dimension'

    if isempty(v1)
        A = v2;
        return
    end

    if isempty(v2)
        A = v1;
        return
    end

    if ~isstruct(v1) || ~isstruct(v2)
        error('CatStructFields expects both inputs to be structures.');
    end

    fields1 = fieldnames(v1);
    fields2 = fieldnames(v2);

    % Stable union of fields
    fields = fields1;

    for i = 1:numel(fields2)
        if ~any(strcmp(fields2{i}, fields))
            fields{end+1,1} = fields2{i}; %#ok<AGROW>
        end
    end

    A = struct();

    for k = 1:numel(fields)

        f = fields{k};

        has1 = isfield(v1, f);
        has2 = isfield(v2, f);

        if has1 && ~has2
            A.(f) = v1.(f);
            warning('Field "%s" exists only in first structure. Keeping first value.', f);
            continue
        end

        if ~has1 && has2
            A.(f) = v2.(f);
            warning('Field "%s" exists only in second structure. Keeping second value.', f);
            continue
        end

        x1 = v1.(f);
        x2 = v2.(f);

        % Empty handling
        if isempty(x1)
            A.(f) = x2;
            continue
        elseif isempty(x2)
            A.(f) = x1;
            continue
        end

        % Nested structures
        if isstruct(x1) && isstruct(x2)
            A.(f) = CatStructFields(x1, x2);
            continue
        end

        % Numeric or logical arrays
        if (isnumeric(x1) || islogical(x1)) && ...
           (isnumeric(x2) || islogical(x2))

            A.(f) = catNumericRobust(x1, x2, f);
            continue
        end

        % Cell arrays
        if iscell(x1) && iscell(x2)
            A.(f) = catCellRobust(x1, x2);
            continue
        end

        % Tables
        if exist('istable', 'file') == 2 || exist('istable', 'builtin') == 5
            if istable(x1) && istable(x2)
                try
                    A.(f) = [x1; x2];
                catch
                    warning('Could not vertically concatenate table field "%s". Keeping first table.', f);
                    A.(f) = x1;
                end
                continue
            end
        end

        % Timetables
        if exist('istimetable', 'file') == 2 || exist('istimetable', 'builtin') == 5
            if istimetable(x1) && istimetable(x2)
                try
                    A.(f) = [x1; x2];
                catch
                    warning('Could not vertically concatenate timetable field "%s". Keeping first timetable.', f);
                    A.(f) = x1;
                end
                continue
            end
        end

        % Datetime / duration
        if isTimeLikePair(x1, x2)
            try
                A.(f) = catSmartSameType(x1, x2);
            catch
                warning('Could not concatenate time field "%s". Keeping first value.', f);
                A.(f) = x1;
            end
            continue
        end

        % Character / string metadata
        if (ischar(x1) || isstring(x1)) && ...
           (ischar(x2) || isstring(x2))

            s1 = string(x1);
            s2 = string(x2);

            if isequal(s1, s2)
                A.(f) = x1;
            else
                % Keep both metadata values
                A.(f) = unique([s1(:); s2(:)], 'stable');
            end
            continue
        end

        % Same class fallback
        if strcmp(class(x1), class(x2))
            try
                A.(f) = catSmartSameType(x1, x2);
            catch
                warning('Could not concatenate field "%s" of class "%s". Keeping first value.', ...
                    f, class(x1));
                A.(f) = x1;
            end
        else
            warning(['Field "%s" has different classes: "%s" and "%s". ', ...
                     'Keeping first value.'], f, class(x1), class(x2));
            A.(f) = x1;
        end
    end
end


function out = catNumericRobust(x1, x2, fieldName)
%CATNUMERICROBUST Concatenate numeric/logical arrays with safe padding.

    sx = size(x1);
    sy = size(x2);

    % First try direct smart concatenation
    try
        dim = chooseCatDim(x1, x2);
        out = cat(dim, x1, x2);
        return
    catch
        % Continue to padded handling
    end

    % Only pad 2D arrays robustly
    if ~ismatrix(x1) || ~ismatrix(x2)
        warning('Field "%s" is not 2D and could not be concatenated. Keeping first value.', fieldName);
        out = x1;
        return
    end

    nrow = max(sx(1), sy(1));
    ncol = max(sx(2), sy(2));

    dim = chooseCatDimAfterPadding(x1, x2);

    if dim == 2
        % Concatenate columns, so rows must match
        x1p = padArray2D(x1, nrow, sx(2));
        x2p = padArray2D(x2, nrow, sy(2));
        out = [x1p, x2p];
    else
        % Concatenate rows, so columns must match
        x1p = padArray2D(x1, sx(1), ncol);
        x2p = padArray2D(x2, sy(1), ncol);
        out = [x1p; x2p];
    end
end


function dim = chooseCatDim(x1, x2)
%CHOOSECATDIM Decide best concatenation dimension.
%
% For ADCP data:
%   - row vectors usually grow along columns
%   - column vectors usually grow along rows
%   - matrices with same number of rows usually grow along columns
%   - matrices with same number of columns usually grow along rows

    sx = size(x1);
    sy = size(x2);

    if isrow(x1) && isrow(x2)
        dim = 2;
        return
    end

    if iscolumn(x1) && iscolumn(x2)
        dim = 1;
        return
    end

    if ndims(x1) == 2 && ndims(x2) == 2

        if sx(1) == sy(1)
            dim = 2;
            return
        end

        if sx(2) == sy(2)
            dim = 1;
            return
        end
    end

    % Fallback close to your original logic
    if ndims(x1) == 2 && size(x1,2) < size(x1,1)
        dim = 1;
    else
        dim = 2;
    end
end


function dim = chooseCatDimAfterPadding(x1, x2)
%CHOOSECATDIMAFTERPADDING Decide direction when dimensions differ.

    sx = size(x1);
    sy = size(x2);

    % ADCP matrices are often [depth/bin/cell x ensemble/time].
    % If both dimensions differ, usually merge along ensemble/time direction.
    if sx(1) ~= sy(1) && sx(2) ~= sy(2)
        dim = 2;
        return
    end

    dim = chooseCatDim(x1, x2);
end


function xp = padArray2D(x, nrow, ncol)
%PADARRAY2D Pad a 2D array to requested size.
%
% Floating numeric arrays are padded with NaN.
% Integer/logical arrays are padded with zero/false because they cannot hold NaN.

    sx = size(x);

    if sx(1) > nrow || sx(2) > ncol
        error('Requested padded size is smaller than input size.');
    end

    if isfloat(x)
        xp = NaN(nrow, ncol);

        if isa(x, 'single')
            xp = single(xp);
        end

    elseif islogical(x)
        xp = false(nrow, ncol);

    else
        % Integer or other numeric classes cannot contain NaN
        xp = zeros(nrow, ncol, class(x));
    end

    xp(1:sx(1), 1:sx(2)) = x;
end


function out = catCellRobust(x1, x2)
%CATCELLROBUST Concatenate cell arrays safely.

    try
        dim = chooseCatDim(x1, x2);
        out = cat(dim, x1, x2);
    catch
        out = [x1(:); x2(:)];
    end
end


function out = catSmartSameType(x1, x2)
%CATSMARTSAMETYPE Generic concatenation for same-type non-numeric arrays.

    dim = chooseCatDim(x1, x2);
    out = cat(dim, x1, x2);
end


function tf = isTimeLikePair(x1, x2)
%ISTIMELIKEPAIR Safe datetime/duration check.

    tf = false;

    hasIsDatetime = exist('isdatetime', 'file') == 2 || exist('isdatetime', 'builtin') == 5;
    hasIsDuration = exist('isduration', 'file') == 2 || exist('isduration', 'builtin') == 5;

    if hasIsDatetime
        if isdatetime(x1) && isdatetime(x2)
            tf = true;
            return
        end
    end

    if hasIsDuration
        if isduration(x1) && isduration(x2)
            tf = true;
            return
        end
    end
end