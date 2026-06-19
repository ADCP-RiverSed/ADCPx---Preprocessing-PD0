function GPSdata = mergeGPSdata(GPSdata, GPSdataNew)
%MERGEGPSDATA Robust handling of GPSdata when it can be struct, char, string, or empty.

    if isempty(GPSdata)
        GPSdata = GPSdataNew;
        return
    end

    if isempty(GPSdataNew)
        return
    end

    if isstruct(GPSdata) && isstruct(GPSdataNew)
        GPSdata = CatStructFields(GPSdata, GPSdataNew);
        return
    end

    % If one of them is char/string, e.g. 'no GPS',
    % keep the latest available information.
    GPSdata = GPSdataNew;
end

function A = CatStructFields(v1, v2)
%CATSTRUCTFIELDS Robustly concatenate matching fields from two structures.
%
% Designed for merging postprocessed ADCP structures such as:
%   BT, Data, v, ECHO, CORR, GPSdata
%
% Improvements compared with the simple version:
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

    % Union of field names, preserving order as much as possible
    fields = unique([fields1; fields2], 'stable');

    A = struct();

    for k = 1:numel(fields)

        f = fields{k};

        has1 = isfield(v1, f);
        has2 = isfield(v2, f);

        % Field only exists in v1
        if has1 && ~has2
            A.(f) = v1.(f);
            warning('Field "%s" exists only in first structure. Keeping first value.', f);
            continue
        end

        % Field only exists in v2
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
        if istable(x1) && istable(x2)
            try
                A.(f) = [x1; x2];
            catch
                warning('Could not vertically concatenate table field "%s". Keeping first table.', f);
                A.(f) = x1;
            end
            continue
        end

        % Timetables
        if istimetable(x1) && istimetable(x2)
            try
                A.(f) = [x1; x2];
            catch
                warning('Could not vertically concatenate timetable field "%s". Keeping first timetable.', f);
                A.(f) = x1;
            end
            continue
        end

        % Datetime / duration
        if (isdatetime(x1) && isdatetime(x2)) || ...
           (isduration(x1) && isduration(x2))

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
                % Keep both metadata values without destroying information
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

    % Try direct smart concatenation first
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

    % Decide concatenation direction after padding
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

    % Vectors
    if isrow(x1) && isrow(x2)
        dim = 2;
        return
    end

    if iscolumn(x1) && iscolumn(x2)
        dim = 1;
        return
    end

    % Matrices
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

    % If number of cells/depth bins differs, but number of ensembles differs too,
    % ADCP matrices are usually [depth/cell x ensemble], so merge along columns.
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
        padValue = NaN;
    elseif islogical(x)
        padValue = false;
    else
        padValue = 0;
    end

    xp = repmat(cast(padValue, 'like', x), nrow, ncol);
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