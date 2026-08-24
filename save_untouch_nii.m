function save_untouch_nii(nii, fileName)
% SAVE_UNTOUCH_NII SPM-backed compatibility wrapper for ROAST.
%
% This provides the small subset of the legacy NIfTI toolbox writer used by
% ROAST/NHPulse. It prefers SPM when available, but falls back to a simple
% NHPulse writer when SPM's compiled mat2file MEX is unavailable.

    if nargin < 1 || ~isstruct(nii) || ~isfield(nii, 'img')
        error('save_untouch_nii:InvalidInput', ...
            'Input must be a NIfTI-like struct with an img field.');
    end
    if nargin < 2 || isempty(fileName)
        if isfield(nii, 'fileprefix') && ~isempty(nii.fileprefix)
            fileName = [char(nii.fileprefix) '.nii'];
        else
            error('save_untouch_nii:MissingFilename', ...
                'A target filename is required when nii.fileprefix is empty.');
        end
    end
    fileName = char(fileName);
    img = nii.img;
    imgSize = size(img);
    if numel(imgSize) < 3
        imgSize(3) = 1;
    end
    if numel(imgSize) > 4
        error('save_untouch_nii:UnsupportedDimensionality', ...
            'Only 3D and simple 4D NIfTI images are supported.');
    end

    folderName = fileparts(fileName);
    if ~isempty(folderName) && exist(folderName, 'dir') ~= 7
        mkdir(folderName);
    end

    baseVol = makeVolumeStruct(nii, fileName, imgSize);
    if exist(fileName, 'file') == 2
        delete(fileName);
    end

    if exist('spm_write_vol', 'file') == 2
        try
            if numel(imgSize) <= 3 || imgSize(4) == 1
                spm_write_vol(baseVol, img(:, :, :, 1));
            else
                for iFrame = 1:imgSize(4)
                    frameVol = baseVol;
                    frameVol.n = [iFrame 1];
                    spm_write_vol(frameVol, img(:, :, :, iFrame));
                end
            end
            return;
        catch ME
            if exist(fileName, 'file') == 2
                delete(fileName);
            end
            warning('save_untouch_nii:SpmWriteFallback', ...
                ['SPM could not write "%s" (%s). Falling back to ', ...
                 'NHPulse simple NIfTI writer.'], fileName, ME.message);
        end
    end
    nhpulseWriteSimpleNifti(fileName, img, baseVol.mat, baseVol.dt(1), ...
        baseVol.descrip);
end

function V = makeVolumeStruct(nii, fileName, imgSize)
    V = struct();
    V.fname = fileName;
    V.dim = double(imgSize(1:3));
    V.dt = [spmDatatypeFromNii(nii) 0];
    V.mat = affineFromNii(nii);
    V.pinfo = pinfoFromNii(nii);
    V.descrip = descriptionFromNii(nii);
end

function mat = affineFromNii(nii)
    if isfield(nii, 'hdr') && isfield(nii.hdr, 'hist') && ...
            all(isfield(nii.hdr.hist, {'srow_x', 'srow_y', 'srow_z'}))
        mat = [double(nii.hdr.hist.srow_x(:))'; ...
               double(nii.hdr.hist.srow_y(:))'; ...
               double(nii.hdr.hist.srow_z(:))'; ...
               0 0 0 1];
        if all(isfinite(mat(:))) && rank(mat(1:3, 1:3)) == 3
            return;
        end
    end
    if isfield(nii, 'mat') && isnumeric(nii.mat) && isequal(size(nii.mat), [4 4])
        mat = double(nii.mat);
        return;
    end

    pixdim = [1 1 1];
    if isfield(nii, 'hdr') && isfield(nii.hdr, 'dime') && ...
            isfield(nii.hdr.dime, 'pixdim') && numel(nii.hdr.dime.pixdim) >= 4
        pixdim = double(nii.hdr.dime.pixdim(2:4));
        pixdim(~isfinite(pixdim) | pixdim == 0) = 1;
    end
    mat = diag([pixdim(:)' 1]);
end

function dtCode = spmDatatypeFromNii(nii)
    dtCode = [];
    if isfield(nii, 'hdr') && isfield(nii.hdr, 'dime') && ...
            isfield(nii.hdr.dime, 'datatype') && ~isempty(nii.hdr.dime.datatype)
        dtCode = double(nii.hdr.dime.datatype);
    end
    if isempty(dtCode) || ~isfinite(dtCode) || dtCode == 0
        dtCode = spmDatatypeFromClass(class(nii.img));
    end
end

function dtCode = spmDatatypeFromClass(className)
    switch char(className)
        case {'uint8', 'logical'}
            dtCode = 2;
        case 'int16'
            dtCode = 4;
        case 'int32'
            dtCode = 8;
        case 'single'
            dtCode = 16;
        case 'double'
            dtCode = 64;
        case 'uint16'
            dtCode = 512;
        case 'uint32'
            dtCode = 768;
        otherwise
            dtCode = 16;
    end
end

function pinfo = pinfoFromNii(nii)
    slope = 1;
    intercept = 0;
    if isfield(nii, 'hdr') && isfield(nii.hdr, 'dime')
        if isfield(nii.hdr.dime, 'scl_slope') && ~isempty(nii.hdr.dime.scl_slope)
            slope = double(nii.hdr.dime.scl_slope);
        end
        if isfield(nii.hdr.dime, 'scl_inter') && ~isempty(nii.hdr.dime.scl_inter)
            intercept = double(nii.hdr.dime.scl_inter);
        end
    end
    if ~isfinite(slope) || slope == 0
        slope = 1;
    end
    if ~isfinite(intercept)
        intercept = 0;
    end
    pinfo = [slope; intercept; 0];
end

function text = descriptionFromNii(nii)
    text = '';
    if isfield(nii, 'hdr') && isfield(nii.hdr, 'hist') && ...
            isfield(nii.hdr.hist, 'descrip') && ~isempty(nii.hdr.hist.descrip)
        text = char(nii.hdr.hist.descrip);
    end
end
