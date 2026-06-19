function pd0_diagnose(filename)
% PD0_DIAGNOSE  Quick scan of a PD0 binary file.
% Prints ensemble count, block IDs, and checksums.
% Block IDs confirmed against USGS QRev (clsPd0TRDI_HB.m).
%
% Usage:  pd0_diagnose('myfile.PD0')

fid = fopen(filename,'r','ieee-le');
if fid < 0, error('Cannot open: %s', filename); end
bytes = fread(fid,inf,'*uint8');
fclose(fid);
nBytes = numel(bytes);
fprintf('File: %s  (%d bytes)\n\n', filename, nBytes);

nens = 0;
idCounts = containers.Map('KeyType','uint32','ValueType','uint32');

p = 1;
while p <= nBytes-5
    if bytes(p)~=hex2dec('7F') || bytes(p+1)~=hex2dec('7F')
        p=p+1; continue
    end
    bpe_raw = double(bytes(p+2)) + 256*double(bytes(p+3));
    bpe     = bpe_raw + 2;
    if bpe<8 || p+bpe-1>nBytes, p=p+1; continue; end

    ensEnd = p+bpe-1;
    ndt    = double(bytes(p+5));
    cs_calc   = mod(sum(double(bytes(p:ensEnd-2))),65536);
    cs_stored = double(bytes(ensEnd-1))+256*double(bytes(ensEnd));
    cs_ok = (cs_calc==cs_stored);
    nens = nens+1;

    if nens<=3
        fprintf('=== Ensemble %d (p=%d bpe=%d ndt=%d cs=%s) ===\n',...
            nens,p,bpe_raw,ndt,tf(cs_ok));
    end

    for it=1:ndt
        lo = double(bytes(p+6+2*(it-1)));
        hi = double(bytes(p+7+2*(it-1)));
        off = lo + 256*hi;
        base = p+off;
        if base+1>ensEnd, continue; end
        lid = double(bytes(base))+256*double(bytes(base+1));
        if nens<=3
            fprintf('  Block %d: offset=%d  ID=0x%04X (%s)\n',it,off,lid,id2name(lid));
        end
        k = uint32(lid);
        if isKey(idCounts,k); idCounts(k)=idCounts(k)+1;
        else; idCounts(k)=uint32(1); end
    end
    p=ensEnd+1;
end

fprintf('\n--- Summary ---\n');
fprintf('Total ensembles: %d\n\n',nens);
fprintf('Block ID    Count    Name\n');
fprintf('----------  -------  ----\n');
ks=keys(idCounts);
for k=1:numel(ks)
    lid=uint32(ks{k});
    fprintf('0x%04X      %-7d  %s\n',lid,idCounts(lid),id2name(lid));
end
end

function s=tf(b); if b, s='OK'; else, s='BAD'; end; end

function name=id2name(lid)
% IDs as u16le values = dec2hex(fread(fid,1,'uint16'),4) from QRev
ids={
    % Standard (all instruments)
    hex2dec('0000'), 'Fixed Leader';
    hex2dec('0080'), 'Variable Leader';
    hex2dec('0100'), 'Water Velocity';
    hex2dec('0200'), 'Correlation';
    hex2dec('0300'), 'Echo Intensity';
    hex2dec('0400'), 'Percent Good';
    hex2dec('0500'), 'Status';
    hex2dec('0600'), 'Bottom Track';
    % Surface layer
    hex2dec('0010'), 'Surface Leader';
    hex2dec('0110'), 'Surface Velocity';
    hex2dec('0210'), 'Surface Correlation';
    hex2dec('0310'), 'Surface Echo';
    hex2dec('0410'), 'Surface Percent Good';
    hex2dec('0510'), 'Surface Status';
    % Vertical beam — standard byte order
    hex2dec('0041'), 'VB Range';
    hex2dec('010F'), 'VB Profile Leader';
    hex2dec('000A'), 'VB Velocity';
    hex2dec('000B'), 'VB Correlation';
    hex2dec('000C'), 'VB Echo';
    hex2dec('000D'), 'VB Percent Good';
    hex2dec('000E'), 'VB Good/Bad Echo';
    % Vertical beam — RiverPro byte-swapped order
    hex2dec('4100'), 'VB Range (RiverPro)';
    hex2dec('0F01'), 'VB Profile Leader (RiverPro)';
    hex2dec('0A00'), 'VB Velocity (RiverPro)';
    hex2dec('0B00'), 'VB Correlation (RiverPro)';
    hex2dec('0C00'), 'VB Echo (RiverPro)';
    hex2dec('0D00'), 'VB Percent Good (RiverPro)';
    hex2dec('0E00'), 'VB Good/Bad Echo (RiverPro)';
    % AutoMode
    hex2dec('4401'), 'AutoMode (RiverRay)';
    hex2dec('4400'), 'AutoMode (RiverPro)';
    hex2dec('020C'), 'AutoMode (RiverPro alt)';
    % GPS / Transform
    hex2dec('2022'), 'WinRiver NMEA GPS';
    hex2dec('2100'), 'NMEA DBT';
    hex2dec('2101'), 'NMEA GGA';
    hex2dec('2102'), 'NMEA VTG';
    hex2dec('2103'), 'NMEA GSA';
    hex2dec('0032'), 'Transform Matrix (WH)';
    hex2dec('3200'), 'Transform Matrix (RiverPro)';
};
for k=1:size(ids,1)
    if lid==ids{k,1}, name=ids{k,2}; return; end
end
name='??? unknown';
end