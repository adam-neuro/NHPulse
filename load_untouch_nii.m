function nii = load_untouch_nii(fileName, varargin)
% LOAD_UNTOUCH_NII SPM-backed compatibility wrapper for ROAST.
%
% NHPulse vendors ROAST code that expects the legacy NIfTI toolbox function
% load_untouch_nii. The public walkthrough otherwise standardizes on SPM for
% NIfTI I/O, so this small wrapper provides the subset of the legacy struct
% interface used by ROAST/NHPulse.

    if nargin < 1 || isempty(fileName)
        error('load_untouch_nii:MissingInput', ...
            'A NIfTI filename is required.');
    end
    if ~isempty(varargin)
        warning('load_untouch_nii:IgnoredOptions', ...
            'SPM-backed load_untouch_nii ignores optional arguments.');
    end
    requireSpm();

    fileName = char(fileName);
    V = spm_vol(fileName);
    if isempty(V)
        error('load_untouch_nii:ReadFailed', ...
            'SPM could not read a NIfTI header from %s.', fileName);
    end

    img = spm_read_vols(V);
    mat = V(1).mat;
    imgSize = size(img);
    if numel(imgSize) < 3
        imgSize(3) = 1;
    end

    hdr = makeHeader(V, img, imgSize, mat);
    nii = struct();
    nii.hdr = hdr;
    nii.filetype = 2;
    nii.fileprefix = stripNiftiExtension(fileName);
    nii.machine = 'spm';
    nii.img = img;
    nii.originalSpmVol = V;
    nii.mat = mat;
    nii.untouch = 1;
end

function requireSpm()
    missing = {};
    if exist('spm_vol', 'file') ~= 2
        missing{end + 1} = 'spm_vol'; %#ok<AGROW>
    end
    if exist('spm_read_vols', 'file') ~= 2
        missing{end + 1} = 'spm_read_vols'; %#ok<AGROW>
    end
    if isempty(missing)
        return;
    end
    if exist('nhpulseMissingDependencyMessage', 'file') == 2
        message = nhpulseMissingDependencyMessage('SPM', ...
            ['NHPulse is using its SPM-backed load_untouch_nii ', ...
             'compatibility wrapper, but SPM is not available.'], missing);
    else
        message = sprintf('SPM is required. Missing: %s.', ...
            strjoin(missing, ', '));
    end
    error('load_untouch_nii:MissingSPM', '%s', message);
end

function hdr = makeHeader(V, img, imgSize, mat)
    dim = ones(1, 8);
    dim(1) = max(3, numel(imgSize));
    dim(2:(1 + numel(imgSize))) = imgSize;

    pixdim = zeros(1, 8);
    pixdim(1) = 1;
    pixdim(2:4) = voxelSizeFromMat(mat);
    if numel(imgSize) >= 4
        pixdim(5) = 1;
    end

    dtCode = double(V(1).dt(1));
    dime = struct();
    dime.dim = dim;
    dime.pixdim = pixdim;
    dime.datatype = dtCode;
    dime.bitpix = bitpixFromDatatype(dtCode);
    dime.scl_slope = 1;
    dime.scl_inter = 0;
    dime.cal_max = 0;
    dime.cal_min = 0;
    dime.glmax = finiteExtrema(img, @max);
    dime.glmin = finiteExtrema(img, @min);

    hist = struct();
    hist.qform_code = 0;
    hist.sform_code = 1;
    hist.quatern_b = 0;
    hist.quatern_c = 0;
    hist.quatern_d = 0;
    hist.qoffset_x = mat(1, 4);
    hist.qoffset_y = mat(2, 4);
    hist.qoffset_z = mat(3, 4);
    hist.srow_x = mat(1, :);
    hist.srow_y = mat(2, :);
    hist.srow_z = mat(3, :);
    hist.descrip = safeDescription(V(1));

    hdr = struct();
    hdr.hk = struct();
    hdr.dime = dime;
    hdr.hist = hist;
end

function vox = voxelSizeFromMat(mat)
    vox = sqrt(sum(mat(1:3, 1:3).^2, 1));
    vox(~isfinite(vox) | vox == 0) = 1;
end

function value = finiteExtrema(img, fun)
    value = 0;
    vals = double(img(isfinite(img)));
    if ~isempty(vals)
        value = fun(vals(:));
    end
end

function text = safeDescription(V)
    text = '';
    if isfield(V, 'descrip') && ~isempty(V.descrip)
        text = char(V.descrip);
    end
end

function bitpix = bitpixFromDatatype(dtCode)
    switch double(dtCode)
        case {2, 256}
            bitpix = 8;
        case {4, 512}
            bitpix = 16;
        case {8, 16, 768}
            bitpix = 32;
        case {64, 1024, 1280}
            bitpix = 64;
        otherwise
            bitpix = 32;
    end
end

function filePrefix = stripNiftiExtension(fileName)
    filePrefix = char(fileName);
    lowerName = lower(filePrefix);
    if endsWith(lowerName, '.nii.gz')
        filePrefix = filePrefix(1:end - 7);
    else
        [folderName, baseName, ext] = fileparts(filePrefix);
        if strcmpi(ext, '.nii') || strcmpi(ext, '.img')
            filePrefix = fullfile(folderName, baseName);
        end
    end
end
