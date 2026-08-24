function nhpulseWriteSimpleNifti(fileName, data, affine, datatype, description)
% NHPULSEWRITESIMPLENIFTI Write a simple uncompressed NIfTI-1 .nii file.
%
% This lightweight writer is intended for NHPulse synthetic/demo products and
% ROAST compatibility masks. It avoids SPM's compiled mat2file MEX writer,
% which is not always available on fresh Apple Silicon installations.

    if nargin < 3 || isempty(affine)
        affine = eye(4);
    end
    if nargin < 4 || isempty(datatype)
        datatype = class(data);
    end
    if nargin < 5
        description = '';
    end

    fileName = char(fileName);
    [datatypeCode, bitpix, matlabClass] = niftiDatatype(datatype, class(data));
    data = cast(data, matlabClass);
    dims = size(data);
    if numel(dims) < 3
        dims(3) = 1;
    end
    if numel(dims) > 4
        error('nhpulseWriteSimpleNifti:UnsupportedDimensionality', ...
            'Only 3D and 4D NIfTI images are supported.');
    end

    folderName = fileparts(fileName);
    if ~isempty(folderName) && exist(folderName, 'dir') ~= 7
        mkdir(folderName);
    end
    if exist(fileName, 'file') == 2
        delete(fileName);
    end

    fid = fopen(fileName, 'w', 'ieee-le');
    if fid < 0
        error('nhpulseWriteSimpleNifti:OpenFailed', ...
            'Could not open "%s" for writing.', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));

    header = zeros(348, 1, 'uint8');
    fwrite(fid, header, 'uint8');

    fseek(fid, 0, 'bof');
    fwrite(fid, int32(348), 'int32');

    dim = ones(1, 8);
    dim(1) = max(3, numel(dims));
    dim(2:(1 + numel(dims))) = dims;
    fseek(fid, 40, 'bof');
    fwrite(fid, int16(dim), 'int16');

    fseek(fid, 70, 'bof');
    fwrite(fid, int16(datatypeCode), 'int16');
    fwrite(fid, int16(bitpix), 'int16');

    pixdim = zeros(1, 8);
    pixdim(1) = 1;
    pixdim(2:4) = voxelSizeFromAffine(affine);
    if numel(dims) >= 4
        pixdim(5) = 1;
    end
    fseek(fid, 76, 'bof');
    fwrite(fid, single(pixdim), 'float32');

    fseek(fid, 108, 'bof');
    fwrite(fid, single(352), 'float32');
    fwrite(fid, single(1), 'float32');
    fwrite(fid, single(0), 'float32');

    fseek(fid, 123, 'bof');
    fwrite(fid, uint8(10), 'uint8'); % mm + seconds

    descBytes = zeros(1, 80, 'uint8');
    description = uint8(char(description));
    nDesc = min(numel(description), 79);
    if nDesc > 0
        descBytes(1:nDesc) = description(1:nDesc);
    end
    fseek(fid, 148, 'bof');
    fwrite(fid, descBytes, 'uint8');

    fseek(fid, 252, 'bof');
    fwrite(fid, int16(0), 'int16');
    fwrite(fid, int16(1), 'int16');

    fseek(fid, 280, 'bof');
    fwrite(fid, single(affine(1, :)), 'float32');
    fwrite(fid, single(affine(2, :)), 'float32');
    fwrite(fid, single(affine(3, :)), 'float32');

    fseek(fid, 344, 'bof');
    fwrite(fid, uint8([double('n+1') 0]), 'uint8');

    fseek(fid, 348, 'bof');
    fwrite(fid, zeros(4, 1, 'uint8'), 'uint8');
    fwrite(fid, data(:), matlabClass);

    clear cleaner
end

function vox = voxelSizeFromAffine(affine)
    vox = sqrt(sum(double(affine(1:3, 1:3)) .^ 2, 1));
    vox(~isfinite(vox) | vox == 0) = 1;
end

function [datatypeCode, bitpix, matlabClass] = niftiDatatype(datatype, fallbackClass)
    if isnumeric(datatype)
        datatypeCode = double(datatype(1));
        [bitpix, matlabClass] = niftiClassFromCode(datatypeCode);
        return;
    end

    key = lower(char(datatype));
    switch key
        case {'uint8', 'logical', 'uchar', '2'}
            datatypeCode = 2;
            bitpix = 8;
            matlabClass = 'uint8';
        case {'int16', 'short', '4'}
            datatypeCode = 4;
            bitpix = 16;
            matlabClass = 'int16';
        case {'int32', 'int', '8'}
            datatypeCode = 8;
            bitpix = 32;
            matlabClass = 'int32';
        case {'single', 'float32', 'float', '16'}
            datatypeCode = 16;
            bitpix = 32;
            matlabClass = 'single';
        case {'double', 'float64', '64'}
            datatypeCode = 64;
            bitpix = 64;
            matlabClass = 'double';
        case {'uint16', 'ushort', '512'}
            datatypeCode = 512;
            bitpix = 16;
            matlabClass = 'uint16';
        case {'uint32', 'uint', '768'}
            datatypeCode = 768;
            bitpix = 32;
            matlabClass = 'uint32';
        otherwise
            [datatypeCode, bitpix, matlabClass] = niftiDatatype(fallbackClass, 'single');
    end
end

function [bitpix, matlabClass] = niftiClassFromCode(datatypeCode)
    switch datatypeCode
        case 2
            bitpix = 8;
            matlabClass = 'uint8';
        case 4
            bitpix = 16;
            matlabClass = 'int16';
        case 8
            bitpix = 32;
            matlabClass = 'int32';
        case 16
            bitpix = 32;
            matlabClass = 'single';
        case 64
            bitpix = 64;
            matlabClass = 'double';
        case 512
            bitpix = 16;
            matlabClass = 'uint16';
        case 768
            bitpix = 32;
            matlabClass = 'uint32';
        otherwise
            error('nhpulseWriteSimpleNifti:UnsupportedDatatype', ...
                'Unsupported NIfTI datatype code: %g.', datatypeCode);
    end
end
