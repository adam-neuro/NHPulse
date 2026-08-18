function text = nhpulseCommandWindowLink(url, label)
% NHPULSECOMMANDWINDOWLINK Format a clickable MATLAB Command Window link.

    url = char(url);
    if nargin < 2 || isempty(label)
        label = url;
    end
    label = char(label);

    if isempty(url)
        text = label;
    else
        text = sprintf('<a href="%s">%s</a>', url, label);
    end
end
