function conductivities = roastValidateExtraTissueConductivities(conductivities, tissueCfg)
% ROASTVALIDATEEXTRATISSUECONDUCTIVITIES Fill/validate optional passive tissues.

    if nargin < 2 || isempty(tissueCfg) || ~isfield(tissueCfg, 'extraTissues') || ...
            isempty(tissueCfg.extraTissues)
        return;
    end

    for i = 1:numel(tissueCfg.extraTissues)
        fieldName = tissueCfg.extraTissues(i).conductivityField;
        if ~isfield(conductivities, fieldName)
            conductivities.(fieldName) = defaultExtraConductivity(fieldName);
        end
        value = conductivities.(fieldName);
        if ~isnumeric(value) || any(value(:) <= 0) || numel(value) ~= 1
            error('roastValidateExtraTissueConductivities:BadConductivity', ...
                'Please enter a positive scalar conductivity for extra tissue "%s".', ...
                fieldName);
        end
    end
end

function value = defaultExtraConductivity(fieldName)
    switch lower(fieldName)
        case 'titanium'
            resistivityOhmM = mean([168 170]) * 1e-8;
            value = 1 / resistivityOhmM;
        otherwise
            error('roastValidateExtraTissueConductivities:MissingConductivity', ...
                ['No default conductivity is defined for extra tissue "%s". ', ...
                 'Add conductivities.%s explicitly.'], fieldName, fieldName);
    end
end
