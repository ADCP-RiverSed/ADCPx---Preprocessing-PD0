function RAW = readPD0_one_fread(filename, giorno)
% READPD0_ONE_FREAD  Binary PD0 reader.
% Supports WorkHorse, RioGrande, RiverPro / RioPro, RiverRay.
%
% Block IDs are confirmed against the USGS QRev source (clsPd0TRDI_HB.m).
% IDs are read as u16le (little-endian uint16), matching:
%   dec2hex(fread(fid,1,'uint16'),4)  from QRev.
%
% CORRECT block ID mapping (u16le value = hex2dec of QRev string):
%
%  Standard water profile (all instruments):
%   0x0000  = Fixed Leader
%   0x0080  = Variable Leader
%   0x0100  = Water Velocity        (bytes [0x00,0x01] in file)
%   0x0200  = Correlation Magnitude (bytes [0x00,0x02])
%   0x0300  = Echo Intensity        (bytes [0x00,0x03])
%   0x0400  = Percent Good          (bytes [0x00,0x04])
%   0x0500  = Status                (bytes [0x00,0x05])
%   0x0600  = Bottom Track          (bytes [0x00,0x06])
%
%  Surface layer (RiverRay / RiverPro):
%   0x0010  = Surface Leader
%   0x0110  = Surface Velocity
%   0x0210  = Surface Correlation
%   0x0310  = Surface Echo
%   0x0410  = Surface Percent Good
%   0x0510  = Surface Status
%
%  Other:
%   0x4401  = RiverRay AutoMode config
%   0x020C  = RiverPro AutoMode config
%   0x2022  = WinRiver2 NMEA GPS block
%   0x2100..0x2103  = Individual NMEA strings (RioGrande WinRiver)
%   0x0032 / 0x3200 = Transformation matrix
%
%  Vertical beam (RiverPro):
%   0x0041  = VB Range
%   0x010F  = VB Profile Leader
%   0x000A  = VB Velocity
%   0x000B  = VB Correlation
%   0x000C  = VB Echo
%   0x000D  = VB Percent Good
%   0x000E  = VB Good/Bad Echo

if nargin < 2, giorno = []; end

fid = fopen(filename,'r','ieee-le');
if fid < 0, error('Cannot open file: %s', filename); end
bytes = fread(fid,inf,'*uint8');
fclose(fid);
nBytes = numel(bytes);

% -------------------------------------------------------------------------
% Preallocate
% -------------------------------------------------------------------------
nens = 0;

% Fixed leader
WN=[]; WP=[]; LagWater=[]; DataPings=[]; WS=[]; WF=[];
CodedWlementsWAterProfile=[]; LowCorr=[]; WE=[]; EX=[]; EA=[]; EB=[];
EZ=[]; plslgh=[];

% Variable leader
TIM_m=[]; TS=[]; TIM_s=[]; ED=[]; EH=[]; EP=[]; ER=[]; WT=[];
XmitV=[]; XmitC=[];

% Water profile (standard, 0x0100/0x0200/0x0300/0x0400)
V1=[]; V2=[]; V3=[]; V4=[];
COR1=[]; COR2=[]; COR3=[]; COR4=[];
ECH1=[]; ECH2=[]; ECH3=[]; ECH4=[];
PG1=[];  PG2=[];  PG3=[];  PG4=[];
STA1=[]; STA2=[]; STA3=[]; STA4=[];

% Bottom track (0x0600)
BP=[]; BTdelay=[]; BE=[]; RNG1=[]; RNG2=[]; RNG3=[]; RNG4=[];
BTV1=[]; BTV2=[]; BTV3=[]; BTV4=[];
BX=[]; BTcorr=[]; BTamp=[];
BTcorr1=[]; BTcorr2=[]; BTcorr3=[]; BTcorr4=[];
BT_AMP1=[]; BT_AMP2=[]; BT_AMP3=[]; BT_AMP4=[];
BT_PG1=[]; BT_PG2=[]; BT_PG3=[]; BT_PG4=[];
BT_RSSI1=[]; BT_RSSI2=[]; BT_RSSI3=[]; BT_RSSI4=[];
BTgain=[];

% Vertical beam (RiverPro)
EVALamp=[]; RSSIAmp=[]; VRNG1=[]; VRNG2=[]; VFLAG=[]; VGAIN=[];
VWN=[]; VWP=[]; VWS=[]; VWFd=[]; VTL=[]; VLag=[]; VCodElements=[];
VV=[]; VCOR=[]; VECH=[]; BEDGOODECH=[]; VPG=[];

% Surface layer (0x0010/0x0110/0x0210/0x0310/0x0410)
SWN=[]; SWS=[]; SWDistance=[];
SV1=[]; SV2=[]; SV3=[]; SV4=[];
SCOR1=[]; SCOR2=[]; SCOR3=[]; SCOR4=[];
SECH1=[]; SECH2=[]; SECH3=[]; SECH4=[];
SPG1=[]; SPG2=[]; SPG3=[]; SPG4=[];

% GPS – WinRiver 0x2022
Latd=[]; Latd2=[]; Latd3=[];
Long=[]; Long2=[]; Long3=[];
Z_gga=[]; Z_gga2=[]; Z_gga3=[];
Tgps={}; Tgps2={}; Tgps3={};
T_gpsNUM=[]; T_gpsNUM2=[]; T_gpsNUM3=[];
VTGH1=[]; VTGV1=[]; VTGH2=[]; VTGV2=[]; VTGH3=[]; VTGV3=[];
Msg_type=[]; Msg_size=[];

% NMEA individual strings
NMEA_GGA={}; NMEA_VTG={}; NMEA_DBT={}; NMEA_GSA={}; NMEA_HDT={};
NMEA_GGA_dt=[]; NMEA_VTG_dt=[]; NMEA_DBT_dt=[]; NMEA_GSA_dt=[]; NMEA_HDT_dt=[];

% AutoMode / transform
AutoMode_data={};
AMB_SS=[];
M = {};

% State trackers
Ndt=[]; ndt=[]; FILE=[]; WN_last=0; VWN_last=0; SWN_last=0;
CoordModeFromEX = cell(0,1);

% -------------------------------------------------------------------------
% Main parse loop
% -------------------------------------------------------------------------
p = 1;
while p <= nBytes - 5

    if bytes(p)~=hex2dec('7F') || bytes(p+1)~=hex2dec('7F')
        p = p+1; continue
    end

    % bytes-per-ensemble in file excludes 2-byte checksum
    bpe = double(u16le(bytes,p+2)) + 2;
    if bpe < 8 || p+bpe-1 > nBytes
        p = p+1; continue
    end

    ensEnd = p + bpe - 1;
    nens   = nens + 1;
    FILE(nens) = 1;
    Ndt(nens)  = 0;
    ndt(nens)  = double(bytes(p+5));

    offs = zeros(ndt(nens),1);
    for it = 1:ndt(nens)
        offs(it) = double(u16le(bytes, p+6+2*(it-1)));
    end

    for it = 1:numel(offs)

        base = p + offs(it);
        if base+1 > ensEnd, continue; end

        % Compute this block's end byte for safe cell-count clamping
        if it < numel(offs)
            blockEnd = p + offs(it+1) - 1;
        else
            blockEnd = ensEnd - 2;
        end
        blockEnd = min(blockEnd, ensEnd-2);

        leaderID = double(u16le(bytes,base));

        switch leaderID

            % =============================================================
            % 0x0000  Fixed Leader
            % Byte layout after 2-byte ID (confirmed against QRev + USF-COT):
            %   +2  firmVer_int   +3  firmVer_dec
            %   +4  sysCfg_lsb   +5  sysCfg_msb
            %   +6  dataType      +7  lag_length (LagWater)
            %   +8  nBeams        +9  WN (num depth cells)  ← NOT +8
            %   +10..+11 WP       +12..+13 WS_cm
            %   +14..+15 WF_cm    +16 WM   +17 WC (LowCorr)
            %   +18 codeReps      +19 minPG  +20..+21 WE
            %   +22..+24 TP       +25 EX     +26..+27 EA
            %   +28..+29 EB       +30 EZ      +31 sensorAvail
            %   +32..+33 distBin1 +34..+35 xmitPulse (plslgh)
            % =============================================================
            case hex2dec('0000')
                Ndt(nens) = Ndt(nens)+1;
                WN(nens)        = double(bytes(base+9));   % num depth cells
                WN_last         = WN(nens);
                LagWater(nens)  = double(bytes(base+7));
                WP(nens)        = double(u16le(bytes,base+10));
                DataPings(nens) = WP(nens);
                WS(nens)        = double(u16le(bytes,base+12));
                WF(nens)        = double(u16le(bytes,base+14));
                LowCorr(nens)   = double(bytes(base+17));
                CodedWlementsWAterProfile(nens) = double(bytes(base+18));
                WE(nens)        = double(u16le(bytes,base+20));
                EX(nens,:)      = char(dec2bin(bytes(base+25),8));
                EA(nens)        = double(i16le(bytes,base+26))*0.01;
                EB(nens)        = double(i16le(bytes,base+28))*0.01;
                EZ(nens,:)      = char(dec2bin(bytes(base+30),8));
                plslgh(nens)    = double(u16le(bytes,base+34));
                CoordModeFromEX{nens,1} = EX(nens,1:2);

            % =============================================================
            % 0x0080  Variable Leader
            % After ID:  +2..+3 ensNum  +4 YY  +5 MM  +6 DD
            %            +7 HH  +8 mm  +9 SS  +10 1/100
            %            +11 rollover  +12..+13 BIT  +14..+15 SoS
            %            +16..+17 depth_dm  +18..+19 heading
            %            +20..+21 pitch  +22..+23 roll
            %            +24..+25 salinity  +26..+27 temperature
            %            ... +34 xmitCurrent  +35 xmitVoltage
            % =============================================================
            case hex2dec('0080')
                Ndt(nens) = Ndt(nens)+1;
                yr = 2000 + double(bytes(base+4));
                mo = double(bytes(base+5));
                da = double(bytes(base+6));
                hh = double(bytes(base+7));
                mm = double(bytes(base+8));
                ss = double(bytes(base+9));
                TIM_m(nens,1)  = datenum([yr mo da hh mm ss]);
                TS(nens,1)     = double(bytes(base+10));
                TIM_s{nens,1}  = datestr([yr mo da hh mm ss]);
                ED(nens,1)     = double(u16le(bytes,base+16));
                EH(nens,1)     = double(u16le(bytes,base+18))*0.01;
                EP(nens,1)     = double(i16le(bytes,base+20))*0.01;
                ER(nens,1)     = double(i16le(bytes,base+22))*0.01;
                WT(nens,1)     = double(i16le(bytes,base+26))*0.01;
                XmitC(nens,1)  = double(bytes(base+34));
                XmitV(nens,1)  = 10*double(bytes(base+35));

            % =============================================================
            % 0x0100  Water Velocity  (was wrong as 0x0001)
            % QRev: case '0100'   bytes [0x00,0x01] → u16le = 256 = 0x0100
            % =============================================================
            case hex2dec('0100')
                Ndt(nens) = Ndt(nens)+1;
                nc = min(WN_last, floor((blockEnd-(base+2)+1)/8));
                for ic = 1:nc
                    q = base+2+8*(ic-1);
                    if q+7 > blockEnd, break; end
                    V1(ic,nens) = double(i16le(bytes,q));
                    V2(ic,nens) = double(i16le(bytes,q+2));
                    V3(ic,nens) = double(i16le(bytes,q+4));
                    V4(ic,nens) = double(i16le(bytes,q+6));
                end

            % =============================================================
            % 0x0200  Correlation  (was wrong as 0x0002)
            % =============================================================
            case hex2dec('0200')
                Ndt(nens) = Ndt(nens)+1;
                nc  = min(WN_last, floor((blockEnd-(base+2)+1)/4));
                idx = base+2;
                for ic = 1:nc
                    if idx+3 > blockEnd, break; end
                    COR1(ic,nens)=double(bytes(idx)); idx=idx+1;
                    COR2(ic,nens)=double(bytes(idx)); idx=idx+1;
                    COR3(ic,nens)=double(bytes(idx)); idx=idx+1;
                    COR4(ic,nens)=double(bytes(idx)); idx=idx+1;
                end

            % =============================================================
            % 0x0300  Echo Intensity  (was wrong as 0x0003)
            % =============================================================
            case hex2dec('0300')
                Ndt(nens) = Ndt(nens)+1;
                nc  = min(WN_last, floor((blockEnd-(base+2)+1)/4));
                idx = base+2;
                for ic = 1:nc
                    if idx+3 > blockEnd, break; end
                    ECH1(ic,nens)=double(bytes(idx)); idx=idx+1;
                    ECH2(ic,nens)=double(bytes(idx)); idx=idx+1;
                    ECH3(ic,nens)=double(bytes(idx)); idx=idx+1;
                    ECH4(ic,nens)=double(bytes(idx)); idx=idx+1;
                end

            % =============================================================
            % 0x0400  Percent Good  (was wrong as 0x0004)
            % =============================================================
            case hex2dec('0400')
                Ndt(nens) = Ndt(nens)+1;
                nc  = min(WN_last, floor((blockEnd-(base+2)+1)/4));
                idx = base+2;
                for ic = 1:nc
                    if idx+3 > blockEnd, break; end
                    PG1(ic,nens)=double(bytes(idx)); idx=idx+1;
                    PG2(ic,nens)=double(bytes(idx)); idx=idx+1;
                    PG3(ic,nens)=double(bytes(idx)); idx=idx+1;
                    PG4(ic,nens)=double(bytes(idx)); idx=idx+1;
                end

            % =============================================================
            % 0x0500  Status  (was wrong as 0x0005)
            % =============================================================
            case hex2dec('0500')
                Ndt(nens) = Ndt(nens)+1;
                nc  = min(WN_last, floor((blockEnd-(base+2)+1)/4));
                idx = base+2;
                for ic = 1:nc
                    if idx+3 > blockEnd, break; end
                    STA1(ic,nens)=double(bytes(idx)); idx=idx+1;
                    STA2(ic,nens)=double(bytes(idx)); idx=idx+1;
                    STA3(ic,nens)=double(bytes(idx)); idx=idx+1;
                    STA4(ic,nens)=double(bytes(idx)); idx=idx+1;
                end

            % =============================================================
            % 0x0600  Bottom Track  (confirmed by QRev: case '0600')
            % Layout after ID (confirmed against QRev byte-by-byte):
            %   +2..+3   BP (pings)
            %   +4..+5   long1 (WinRiver GPS long LSB, stored as BTdelay)
            %   +6  bc (BTcorr min)   +7  ba (BTamp min)
            %   +8  bg (gain)         +9  bm (mode)
            %   +10..+11  BE (error vel max)
            %   +12..+15  GPS lat (int32)
            %   +16..+23  beam ranges (4x uint16) [cm]
            %   +24..+31  BT velocities (4x int16) [mm/s]
            %   +32..+35  BT correlations (4x uint8)
            %   +36..+39  BT eval amplitude (4x uint8)
            %   +40..+43  BT percent good (4x uint8)
            %   +44..+45  GPS alt   +46..+47 long2
            %   +48..+49  extDepth  +50..+57 GPS velocities
            %   +58..+69  GPS quality
            %   +70..+71  BX (max depth)
            %   +72..+75  BT RSSI   +76 wj (gain switch)
            %   +77..+80  range MSB bytes (32-bit range extension)
            % =============================================================
            case hex2dec('0600')
                Ndt(nens) = Ndt(nens)+1;
                BP(nens,1)      = double(u16le(bytes,base+2));
                BTdelay(nens,1) = double(u16le(bytes,base+4));  % long1 GPS
                BTcorr(nens,1)  = double(bytes(base+6));
                BTamp(nens,1)   = double(bytes(base+7));
                BE(nens,1)      = double(u16le(bytes,base+10));

                RNG1(nens,1)    = double(u16le(bytes,base+16));
                RNG2(nens,1)    = double(u16le(bytes,base+18));
                RNG3(nens,1)    = double(u16le(bytes,base+20));
                RNG4(nens,1)    = double(u16le(bytes,base+22));

                BTV1(nens,1)    = double(i16le(bytes,base+24));
                BTV2(nens,1)    = double(i16le(bytes,base+26));
                BTV3(nens,1)    = double(i16le(bytes,base+28));
                BTV4(nens,1)    = double(i16le(bytes,base+30));

                BTcorr1(nens,1) = double(bytes(base+32));
                BTcorr2(nens,1) = double(bytes(base+33));
                BTcorr3(nens,1) = double(bytes(base+34));
                BTcorr4(nens,1) = double(bytes(base+35));

                BT_AMP1(nens,1) = double(bytes(base+36));
                BT_AMP2(nens,1) = double(bytes(base+37));
                BT_AMP3(nens,1) = double(bytes(base+38));
                BT_AMP4(nens,1) = double(bytes(base+39));

                % BT percent good (base+40..+43) — from QRev confirmed
                if base+43 <= blockEnd
                    BT_PG1(nens,1) = double(bytes(base+40));
                    BT_PG2(nens,1) = double(bytes(base+41));
                    BT_PG3(nens,1) = double(bytes(base+42));
                    BT_PG4(nens,1) = double(bytes(base+43));
                end

                % BX, RSSI, gain
                if base+71 <= blockEnd
                    BX(nens,1)       = double(i16le(bytes,base+70));
                end
                if base+76 <= blockEnd
                    BT_RSSI1(nens,1) = double(bytes(base+72));
                    BT_RSSI2(nens,1) = double(bytes(base+73));
                    BT_RSSI3(nens,1) = double(bytes(base+74));
                    BT_RSSI4(nens,1) = double(bytes(base+75));
                    BTgain(nens,1)   = double(bytes(base+76));
                else
                    BT_RSSI1(nens,1)=NaN; BT_RSSI2(nens,1)=NaN;
                    BT_RSSI3(nens,1)=NaN; BT_RSSI4(nens,1)=NaN;
                    BTgain(nens,1)=NaN;
                end

                % 32-bit range extension (QRev: RR_Btdepthcorrection, base+77..+80)
                if base+80 <= blockEnd
                    RNG1(nens,1) = RNG1(nens,1) + 65536*double(bytes(base+77));
                    RNG2(nens,1) = RNG2(nens,1) + 65536*double(bytes(base+78));
                    RNG3(nens,1) = RNG3(nens,1) + 65536*double(bytes(base+79));
                    RNG4(nens,1) = RNG4(nens,1) + 65536*double(bytes(base+80));
                end

            % =============================================================
            % 0x0010  Surface Layer Leader  (was WRONG as 0x0100)
            % QRev: case '0010'
            % =============================================================
            case hex2dec('0010')
                Ndt(nens) = Ndt(nens)+1;
                SWN(nens,1)        = double(bytes(base+2));
                SWN_last           = SWN(nens,1);
                SWS(nens,1)        = double(u16le(bytes,base+3));
                SWDistance(nens,1) = double(u16le(bytes,base+5));

            % =============================================================
            % 0x0110  Surface Velocity  (QRev: case '0110')
            % =============================================================
            case hex2dec('0110')
                Ndt(nens) = Ndt(nens)+1;
                nc = min(SWN_last, floor((blockEnd-(base+2)+1)/8));
                if nc < 1, nc = 1; end
                for ic = 1:nc
                    q = base+2+8*(ic-1);
                    if q+7 > blockEnd, break; end
                    SV1(ic,nens)=double(i16le(bytes,q));
                    SV2(ic,nens)=double(i16le(bytes,q+2));
                    SV3(ic,nens)=double(i16le(bytes,q+4));
                    SV4(ic,nens)=double(i16le(bytes,q+6));
                end

            % =============================================================
            % 0x0210  Surface Correlation  (QRev: case '0210')
            % =============================================================
            case hex2dec('0210')
                Ndt(nens) = Ndt(nens)+1;
                nc  = min(SWN_last, floor((blockEnd-(base+2)+1)/4));
                if nc < 1, nc = 1; end
                idx = base+2;
                for ic = 1:nc
                    if idx+3 > blockEnd, break; end
                    SCOR1(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SCOR2(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SCOR3(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SCOR4(ic,nens)=double(bytes(idx)); idx=idx+1;
                end

            % =============================================================
            % 0x0310  Surface Echo  (QRev: case '0310')
            % =============================================================
            case hex2dec('0310')
                Ndt(nens) = Ndt(nens)+1;
                nc  = min(SWN_last, floor((blockEnd-(base+2)+1)/4));
                if nc < 1, nc = 1; end
                idx = base+2;
                for ic = 1:nc
                    if idx+3 > blockEnd, break; end
                    SECH1(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SECH2(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SECH3(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SECH4(ic,nens)=double(bytes(idx)); idx=idx+1;
                end

            % =============================================================
            % 0x0410  Surface Percent Good  (QRev: case '0410')
            % =============================================================
            case hex2dec('0410')
                Ndt(nens) = Ndt(nens)+1;
                nc  = min(SWN_last, floor((blockEnd-(base+2)+1)/4));
                if nc < 1, nc = 1; end
                idx = base+2;
                for ic = 1:nc
                    if idx+3 > blockEnd, break; end
                    SPG1(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SPG2(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SPG3(ic,nens)=double(bytes(idx)); idx=idx+1;
                    SPG4(ic,nens)=double(bytes(idx)); idx=idx+1;
                end

            % =============================================================
            % 0x0510  Surface Status  (QRev: case '0510' — skip)
            % =============================================================
            case hex2dec('0510')
                Ndt(nens) = Ndt(nens)+1;   % skip body

            % =============================================================
            % 0x0041  VB Range (WorkHorse/RioGrande byte order)
            % 0x4100  VB Range (RiverPro byte order — bytes [0x00,0x41])
            % =============================================================
            case {hex2dec('0041'), hex2dec('4100')}
                Ndt(nens) = Ndt(nens)+1;
                if base+8 <= blockEnd
                    EVALamp(nens,1) = double(bytes(base+2));
                    RSSIAmp(nens,1) = double(bytes(base+3));
                    VRNG1(nens,1)   = double(u16le(bytes,base+4))/1000;
                    VRNG2(nens,1)   = double(u16le(bytes,base+6))/1000;
                    VFLAG(nens,:)   = char(dec2bin(bytes(base+8),8));
                    VGAIN(nens,1)   = bitget(bytes(base+8),3);
                end

            % =============================================================
            % 0x010F  VB Profile Leader (WorkHorse/RioGrande byte order)
            % 0x0F01  VB Profile Leader (RiverPro byte order — bytes [0x01,0x0F])
            % =============================================================
            case {hex2dec('010F'), hex2dec('0F01')}
                Ndt(nens) = Ndt(nens)+1;
                if base+16 <= blockEnd
                    VWN(nens,1)          = double(u16le(bytes,base+2));
                    VWN_last             = VWN(nens,1);
                    VWP(nens,1)          = double(u16le(bytes,base+4));
                    VWS(nens,1)          = double(u16le(bytes,base+6));
                    VWFd(nens,1)         = double(u16le(bytes,base+8));
                    VTL(nens,1)          = double(u16le(bytes,base+12));
                    VLag(nens,1)         = double(u16le(bytes,base+14));
                    VCodElements(nens,1) = double(u16le(bytes,base+16));
                end

            % =============================================================
            % VB Velocity    0x000A (standard) | 0x0A00 (RiverPro)
            % VB Correlation 0x000B (standard) | 0x0B00 (RiverPro)
            % VB Echo        0x000C (standard) | 0x0C00 (RiverPro)
            % VB Percent Good 0x000D (standard)| 0x0D00 (RiverPro)
            % VB Good/Bad    0x000E (standard) | 0x0E00 (RiverPro)
            % =============================================================
            case {hex2dec('000A'), hex2dec('0A00')}
                Ndt(nens) = Ndt(nens)+1;
                nc = min(VWN_last, floor((blockEnd-(base+2)+1)/2));
                if nc<1, nc=1; end
                for ic = 1:nc
                    q = base+2+2*(ic-1);
                    if q+1 > blockEnd, break; end
                    VV(ic,nens) = double(i16le(bytes,q));
                end

            case {hex2dec('000B'), hex2dec('0B00')}
                Ndt(nens) = Ndt(nens)+1;
                nc = min(VWN_last, blockEnd-(base+2)+1);
                if nc<1, nc=1; end
                for ic = 1:nc
                    if base+2+(ic-1) > blockEnd, break; end
                    VCOR(ic,nens) = double(bytes(base+2+(ic-1)));
                end

            case {hex2dec('000C'), hex2dec('0C00')}
                Ndt(nens) = Ndt(nens)+1;
                nc = min(VWN_last, blockEnd-(base+2)+1);
                if nc<1, nc=1; end
                for ic = 1:nc
                    if base+2+(ic-1) > blockEnd, break; end
                    VECH(ic,nens) = double(bytes(base+2+(ic-1)));
                end

            case {hex2dec('000D'), hex2dec('0D00')}
                Ndt(nens) = Ndt(nens)+1;
                nc = min(VWN_last, blockEnd-(base+2)+1);
                if nc<1, nc=1; end
                for ic = 1:nc
                    if base+2+(ic-1) > blockEnd, break; end
                    VPG(ic,nens) = double(bytes(base+2+(ic-1)));
                end

            case {hex2dec('000E'), hex2dec('0E00')}
                Ndt(nens) = Ndt(nens)+1;
                nc = min(VWN_last, blockEnd-(base+2)+1);
                if nc<1, nc=1; end
                for ic = 1:nc
                    if base+2+(ic-1) > blockEnd, break; end
                    BEDGOODECH(ic,nens) = double(bytes(base+2+(ic-1)));
                end

            % =============================================================
            % 0x4401  RiverRay AutoMode  (QRev: case '4401')
            % 0x4400  RiverPro AutoMode  (byte-swapped variant seen in RiverPro files)
            % 0x020C  RiverPro AutoMode  (alternate ID)
            % =============================================================
            case {hex2dec('4401'), hex2dec('4400'), hex2dec('020C')}
                Ndt(nens) = Ndt(nens)+1;
                blen = min(blockEnd-(base+2)+1, 80);
                if blen > 0
                    AutoMode_data{nens} = double(bytes(base+2:base+2+blen-1))';
                end

            % =============================================================
            % 0x2022  WinRiver2 NMEA GPS block
            % =============================================================
            case hex2dec('2022')
                Ndt(nens) = Ndt(nens)+1;
                Msg_type(nens,1) = double(u16le(bytes,base+2));
                Msg_size(nens,1) = double(u16le(bytes,base+4));
                takeTo = min(blockEnd, base+max(70,min(400,Msg_size(nens)+20)));
                gps    = char(bytes(base:takeTo))';
                try
                    [Latd(nens),Long(nens),Z_gga(nens), ...
                     Latd2(nens),Long2(nens),Z_gga2(nens), ...
                     Tgps{nens},Tgps2{nens},Tgps3{nens}, ...
                     Latd3(nens),Long3(nens),Z_gga3(nens)] = ...
                     GGAfind1(giorno,gps,Msg_size(nens),Msg_type(nens));
                catch
                    Latd(nens)=0;  Long(nens)=0;  Z_gga(nens)=NaN;
                    Latd2(nens)=0; Long2(nens)=0; Z_gga2(nens)=NaN;
                    Latd3(nens)=0; Long3(nens)=0; Z_gga3(nens)=NaN;
                    Tgps{nens}=''; Tgps2{nens}=''; Tgps3{nens}='';
                end
                try
                    [VTGH1(nens),VTGV1(nens),VTGH2(nens),VTGV2(nens), ...
                     VTGH3(nens),VTGV3(nens)] = VTGfind1(gps,Msg_type(nens));
                catch
                    VTGH1(nens)=0; VTGV1(nens)=0;
                    VTGH2(nens)=0; VTGV2(nens)=0;
                    VTGH3(nens)=0; VTGV3(nens)=0;
                end
                try; T_gpsNUM(nens)  = datenum(Tgps{nens});  catch; T_gpsNUM(nens)=0;  end
                try; T_gpsNUM2(nens) = datenum(Tgps2{nens}); catch; T_gpsNUM2(nens)=0; end
                try; T_gpsNUM3(nens) = datenum(Tgps3{nens}); catch; T_gpsNUM3(nens)=0; end

            % =============================================================
            % 0x2100-0x2103  Individual NMEA strings (WinRiver / RioGrande)
            % =============================================================
            case hex2dec('2100')
                Ndt(nens) = Ndt(nens)+1;
                NMEA_DBT_dt(nens) = double(u16le(bytes,base+2));
                NMEA_DBT{nens}    = extractNMEA(bytes,base+4,blockEnd);

            case hex2dec('2101')
                Ndt(nens) = Ndt(nens)+1;
                NMEA_GGA_dt(nens) = double(u16le(bytes,base+2));
                NMEA_GGA{nens}    = extractNMEA(bytes,base+4,blockEnd);

            case hex2dec('2102')
                Ndt(nens) = Ndt(nens)+1;
                NMEA_VTG_dt(nens) = double(u16le(bytes,base+2));
                NMEA_VTG{nens}    = extractNMEA(bytes,base+4,blockEnd);

            case hex2dec('2103')
                Ndt(nens) = Ndt(nens)+1;
                NMEA_GSA_dt(nens) = double(u16le(bytes,base+2));
                NMEA_GSA{nens}    = extractNMEA(bytes,base+4,blockEnd);

            % =============================================================
            % 0x0032 / 0x3200  Transformation / beam-correction matrix
            % =============================================================
            case {hex2dec('0032'), hex2dec('3200')}
                Ndt(nens) = Ndt(nens)+1;
                if base+33 <= blockEnd
                    MM = zeros(16,1);
                    for q = 1:16
                        MM(q) = double(i16le(bytes,base+2+2*(q-1)));
                    end
                    M{nens} = reshape(MM,4,4)'/1e4;
                end

            % unknown — skip silently
        end % switch
    end % for it

    p = ensEnd + 1;
end % while

fprintf('readPD0: %s — %d ensembles\n', filename, nens);

% -------------------------------------------------------------------------
% Output struct
% -------------------------------------------------------------------------
RAW = struct();
RAW.nens = nens;
RAW.Ndt  = Ndt;  RAW.ndt = ndt;  RAW.FILE = FILE;

RAW.WN=WN; RAW.WP=WP; RAW.LagWater=LagWater; RAW.DataPings=DataPings;
RAW.WS=WS; RAW.WF=WF;
RAW.CodedWlementsWAterProfile=CodedWlementsWAterProfile;
RAW.LowCorr=LowCorr; RAW.WE=WE; RAW.EX=EX; RAW.EA=EA; RAW.EB=EB;
RAW.EZ=EZ; RAW.plslgh=plslgh;
RAW.TIM_m=TIM_m; RAW.TS=TS; RAW.TIM_s=TIM_s;
RAW.ED=ED; RAW.EH=EH; RAW.EP=EP; RAW.ER=ER; RAW.WT=WT;
RAW.XmitV=XmitV; RAW.XmitC=XmitC;

RAW.V1=V1; RAW.V2=V2; RAW.V3=V3; RAW.V4=V4;
RAW.COR1=COR1; RAW.COR2=COR2; RAW.COR3=COR3; RAW.COR4=COR4;
RAW.ECH1=ECH1; RAW.ECH2=ECH2; RAW.ECH3=ECH3; RAW.ECH4=ECH4;
RAW.PG1=PG1; RAW.PG2=PG2; RAW.PG3=PG3; RAW.PG4=PG4;
RAW.STA1=STA1; RAW.STA2=STA2; RAW.STA3=STA3; RAW.STA4=STA4;

RAW.BP=BP; RAW.BTdelay=BTdelay; RAW.BE=BE;
RAW.RNG1=RNG1; RAW.RNG2=RNG2; RAW.RNG3=RNG3; RAW.RNG4=RNG4;
RAW.BTV1=BTV1; RAW.BTV2=BTV2; RAW.BTV3=BTV3; RAW.BTV4=BTV4;
RAW.BX=BX; RAW.BTcorr=BTcorr; RAW.BTamp=BTamp;
RAW.BTcorr1=BTcorr1; RAW.BTcorr2=BTcorr2;
RAW.BTcorr3=BTcorr3; RAW.BTcorr4=BTcorr4;
RAW.BT_AMP1=BT_AMP1; RAW.BT_AMP2=BT_AMP2;
RAW.BT_AMP3=BT_AMP3; RAW.BT_AMP4=BT_AMP4;
RAW.BT_PG1=BT_PG1; RAW.BT_PG2=BT_PG2;
RAW.BT_PG3=BT_PG3; RAW.BT_PG4=BT_PG4;
RAW.BT_RSSI1=BT_RSSI1; RAW.BT_RSSI2=BT_RSSI2;
RAW.BT_RSSI3=BT_RSSI3; RAW.BT_RSSI4=BT_RSSI4;
RAW.BTgain=BTgain;

RAW.EVALamp=EVALamp; RAW.RSSIAmp=RSSIAmp;
RAW.VRNG1=VRNG1; RAW.VRNG2=VRNG2;
RAW.VFLAG=VFLAG; RAW.VGAIN=VGAIN;
RAW.VWN=VWN; RAW.VWP=VWP; RAW.VWS=VWS; RAW.VWFd=VWFd;
RAW.VTL=VTL; RAW.VLag=VLag; RAW.VCodElements=VCodElements;
RAW.VV=VV; RAW.VCOR=VCOR; RAW.VECH=VECH; RAW.VPG=VPG;
RAW.BEDGOODECH=BEDGOODECH; RAW.AMB_SS=AMB_SS;

RAW.SWN=SWN; RAW.SWS=SWS; RAW.SWDistance=SWDistance;
RAW.SV1=SV1; RAW.SV2=SV2; RAW.SV3=SV3; RAW.SV4=SV4;
RAW.SCOR1=SCOR1; RAW.SCOR2=SCOR2; RAW.SCOR3=SCOR3; RAW.SCOR4=SCOR4;
RAW.SECH1=SECH1; RAW.SECH2=SECH2; RAW.SECH3=SECH3; RAW.SECH4=SECH4;
RAW.SPG1=SPG1; RAW.SPG2=SPG2; RAW.SPG3=SPG3; RAW.SPG4=SPG4;

RAW.Latd=Latd; RAW.Long=Long; RAW.Z_gga=Z_gga;
RAW.Latd2=Latd2; RAW.Long2=Long2; RAW.Z_gga2=Z_gga2;
RAW.Latd3=Latd3; RAW.Long3=Long3; RAW.Z_gga3=Z_gga3;
RAW.Tgps=Tgps; RAW.Tgps2=Tgps2; RAW.Tgps3=Tgps3;
RAW.T_gpsNUM=T_gpsNUM; RAW.T_gpsNUM2=T_gpsNUM2; RAW.T_gpsNUM3=T_gpsNUM3;
RAW.VTGH1=VTGH1; RAW.VTGV1=VTGV1;
RAW.VTGH2=VTGH2; RAW.VTGV2=VTGV2;
RAW.VTGH3=VTGH3; RAW.VTGV3=VTGV3;
RAW.Msg_type=Msg_type; RAW.Msg_size=Msg_size;

RAW.NMEA_GGA=NMEA_GGA; RAW.NMEA_GGA_dt=NMEA_GGA_dt;
RAW.NMEA_VTG=NMEA_VTG; RAW.NMEA_VTG_dt=NMEA_VTG_dt;
RAW.NMEA_DBT=NMEA_DBT; RAW.NMEA_DBT_dt=NMEA_DBT_dt;
RAW.NMEA_GSA=NMEA_GSA; RAW.NMEA_GSA_dt=NMEA_GSA_dt;
RAW.NMEA_HDT=NMEA_HDT; RAW.NMEA_HDT_dt=NMEA_HDT_dt;

RAW.AutoMode_data=AutoMode_data;
RAW.M=M;
RAW.CoordModeFromEX=CoordModeFromEX;

end % function

% =========================================================================
function v = u16le(b,idx)
v = uint16(b(idx)) + bitshift(uint16(b(idx+1)),8);
end

function v = i16le(b,idx)
u = uint16(b(idx)) + bitshift(uint16(b(idx+1)),8);
v = typecast(u,'int16');
end

function s = extractNMEA(bytes,startIdx,blockEnd)
maxLen = min(blockEnd, startIdx+299);
if startIdx > maxLen, s=''; return; end
raw  = bytes(startIdx:maxLen);
stop = find(raw==0,1);
if ~isempty(stop), raw=raw(1:stop-1); end
s = strtrim(char(raw(:))');
end