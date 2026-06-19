function dateStr = extractDateFromPath(folderPath)
%EXTRACTDATEFROMPATH Extracts a valid YYYYMMDD date from anywhere in a path.
%
% It does NOT assume a fixed folder position.
% If several valid dates are found, it uses the last one in the path.

    % Convert to char if input is string
    folderPath = char(folderPath);

    % Find all 8-digit groups anywhere in the path
    candidates = regexp(folderPath, '\d{8}', 'match');

    if isempty(candidates)
        error('No 8-digit date pattern YYYYMMDD found in path:\n%s', folderPath);
    end

    validDates = {};

    % Check which 8-digit groups are real dates
    for i = 1:numel(candidates)
        thisDate = candidates{i};

        try
            datetime(thisDate, 'InputFormat', 'yyyyMMdd');
            validDates{end+1} = thisDate; %#ok<AGROW>
        catch
            % Ignore invalid dates
        end
    end

    if isempty(validDates)
        error('No valid YYYYMMDD date found in path:\n%s', folderPath);
    end

    % Use the last valid date in the path
    dateStr = validDates{end};
end