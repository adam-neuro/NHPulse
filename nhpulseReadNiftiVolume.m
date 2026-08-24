function [data, V] = nhpulseReadNiftiVolume(fileName, varargin)
% NHPULSEREADNIFTIVOLUME Read a NIfTI volume with SPM or simple fallback.
%
% [data, V] = nhpulseReadNiftiVolume(fileName) returns image data and an
% SPM-like metadata struct with fname, dim, dt, and mat fields. It tries SPM
% first when available, then falls back to nhpulseReadSimpleNifti for the
% simple uncompressed .nii files used by the public synthetic workflow.

    p = inputParser;
    p.FunctionName = 'nhpulseReadNiftiVolume';
    addParameter(p, 'preferSpm', true, ...
        @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    parse(p, varargin{:});
    preferSpm = logical(p.Results.preferSpm);

    fileName = char(fileName);
    persistent spmReadFailedThisSession
    if isempty(spmReadFailedThisSession)
        spmReadFailedThisSession = false;
    end

    if preferSpm && ~spmReadFailedThisSession && ...
            exist('spm_vol', 'file') == 2 && ...
            exist('spm_read_vols', 'file') == 2
        try
            V = spm_vol(fileName);
            if numel(V) > 1
                V = V(1);
            end
            data = spm_read_vols(V);
            return;
        catch ME
            spmReadFailedThisSession = true;
            warning('nhpulseReadNiftiVolume:SpmFallback', ...
                ['SPM could not read "%s" (%s). Falling back to ', ...
                 'NHPulse simple NIfTI reader for this and later reads in ', ...
                 'this MATLAB session.'], fileName, ME.message);
        end
    end

    if exist('nhpulseReadSimpleNifti', 'file') ~= 2
        error('nhpulseReadNiftiVolume:NoReader', ...
            ['Could not read "%s": SPM reading failed/unavailable and ', ...
             'nhpulseReadSimpleNifti is not on the MATLAB path.'], fileName);
    end
    [data, V] = nhpulseReadSimpleNifti(fileName);
end
