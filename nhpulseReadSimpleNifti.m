function [data, meta] = nhpulseReadSimpleNifti(fileName)
% NHPULSEREADSIMPLENIFTI Read a simple uncompressed NIfTI-1 .nii file.
%
% This reader supports the small single-file NIfTI products written by
% nhpulseWriteSimpleNifti. It is intended as a reviewer/synthetic fallback
% when SPM's compiled MEX readers are not available.

    fileName = char(fileName);
    fid = fopen(fileName, 'r', 'ieee-le');
    if fid < 0
        error('nhpulseReadSimpleNifti:OpenFailed', ...
            'Could not open "%s" for reading.', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));

    sizeofHdr = fread(fid, 1, 'int32=>double');
    if isempty(sizeofHdr) || sizeofHdr ~= 348
        error('nhpulseReadSimpleNifti:BadHeader', ...
            'File does not look like a little-endian NIfTI-1 file: %s', fileName);
    end

    fseek(fid, 40, 'bof');
    dim = fread(fid, 8, 'int16=>double')';
    nDim = max(1, min(7, round(dim(1))));
    dims = max(1, round(dim(2:(1 + nDim))));
    if numel(dims) < 3
        dims(3) = 1;
    end

    fseek(fid, 70, 'bof');
    datatypeCode = fread(fid, 1, 'int16=>double');
    bitpix = fread(fid, 1, 'int16=>double');
    matlabClass = matlabClassFromDatatype(datatypeCode);

    fseek(fid, 76, 'bof');
    pixdim = fread(fid, 8, 'float32=>double')';

    fseek(fid, 108, 'bof');
    voxOffset = fread(fid, 1, 'float32=>double');
    if isempty(voxOffset) || ~isfinite(voxOffset) || voxOffset < 348
        voxOffset = 352;
    end

    fseek(fid, 252, 'bof');
    qformCode = fread(fid, 1, 'int16=>double');
    sformCode = fread(fid, 1, 'int16=>double');

    fseek(fid, 280, 'bof');
    srowX = fread(fid, 4, 'float32=>double')';
    srowY = fread(fid, 4, 'float32=>double')';
    srowZ = fread(fid, 4, 'float32=>double')';
    if sformCode > 0
        affine = [srowX; srowY; srowZ; 0 0 0 1];
    else
        vox = pixdim(2:4);
        vox(~isfinite(vox) | vox == 0) = 1;
        affine = diag([vox(:)' 1]);
    end

    fseek(fid, round(voxOffset), 'bof');
    nVox = prod(dims);
    raw = fread(fid, nVox, ['*' matlabClass]);
    if numel(raw) ~= nVox
        error('nhpulseReadSimpleNifti:TruncatedData', ...
            'Expected %d voxels but read %d from %s.', nVox, numel(raw), fileName);
    end
    data = reshape(raw, dims);

    meta = struct();
    meta.fname = fileName;
    meta.dim = double(dims(1:3));
    meta.dt = [datatypeCode 0];
    meta.bitpix = bitpix;
    meta.mat = affine;
    meta.pixdim = pixdim;
    meta.qformCode = qformCode;
    meta.sformCode = sformCode;

    clear cleaner
end

function matlabClass = matlabClassFromDatatype(datatypeCode)
    switch double(datatypeCode)
        case 2
            matlabClass = 'uint8';
        case 4
            matlabClass = 'int16';
        case 8
            matlabClass = 'int32';
        case 16
            matlabClass = 'single';
        case 64
            matlabClass = 'double';
        case 512
            matlabClass = 'uint16';
        case 768
            matlabClass = 'uint32';
        otherwise
            error('nhpulseReadSimpleNifti:UnsupportedDatatype', ...
                'Unsupported NIfTI datatype code: %g.', datatypeCode);
    end
end
