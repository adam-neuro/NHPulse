function message = nhpulseMissingDependencyMessage(name, context, missingItems)
% NHPULSEMISSINGDEPENDENCYMESSAGE Format actionable dependency help text.

    if nargin < 2 || isempty(context)
        context = 'This NHPulse step requires an unavailable dependency.';
    end
    if nargin < 3
        missingItems = {};
    end
    if ischar(missingItems) || isstring(missingItems)
        missingItems = cellstr(missingItems);
    end

    info = nhpulseDependencyInfo(name);
    lines = {char(context)};

    if ~isempty(missingItems)
        lines{end + 1} = sprintf('Missing function/file(s): %s.', ...
            strjoin(missingItems(:)', ', ')); %#ok<AGROW>
    end

    if ~isempty(info.installUrl)
        lines{end + 1} = sprintf('Install/download: %s', ...
            nhpulseCommandWindowLink(info.installUrl, info.installUrl)); %#ok<AGROW>
    end

    if ~isempty(info.configField)
        lines{end + 1} = sprintf( ...
            ['After installing, run setNHPulsePath and/or ', ...
             'nhpulseConfigureLocalPaths(''useGui'', true), then set %s.'], ...
            info.configField); %#ok<AGROW>
    elseif ~isempty(info.setupHint)
        lines{end + 1} = info.setupHint; %#ok<AGROW>
    end

    message = strjoin(lines, newline);
end
