function [BT, v, CORR, ECHO, SL, VB, GPSdata, Data] = ...
    processADCP_RDI(RAW, MGVAR, trasholdVB, savedir, name, opts)
% PROCESSADCP_RDI
% Post-processes the RAW struct from readPD0_one_fread.
%
% Usage:
%   [BT,v,CORR,ECHO,SL,VB,GPSdata,Data] = processADCP_RDI(RAW, MGVAR, trasholdVB, savedir, name)
%   [BT,v,CORR,ECHO,SL,VB,GPSdata,Data] = processADCP_RDI(RAW, MGVAR, trasholdVB, savedir, name, opts)
%
% Inputs:
%   RAW         - struct from readPD0_one_fread
%   MGVAR       - magnetic variation [degrees], positive East
%   trasholdVB  - velocity threshold for outlier removal [m/s], e.g. 5
%   savedir     - directory to save .mat file ([] to skip saving)
%   name        - file identifier string (used as .mat filename)
%   opts        - (optional) struct with filter settings:
%
%     opts.apply_depth_limit  [false]  Simple depth ceiling on processed vel.
%     opts.max_depth_m        [Inf]    Depth limit in metres
%     opts.apply_sidelobe     [true]   Acoustic sidelobe cutoff on processed vel.
%     opts.beamAngle_deg      [20]     Beam angle: 20° RioGrande/RiverPro, 15° StreamPro
%     opts.apply_corr         [false]  Correlation threshold on raw V1-V4
%     opts.corr_threshold     [auto]   Override correlation threshold (0-255)
%     opts.apply_pg           [false]  Percent-good threshold on raw V1-V4
%     opts.pg_threshold       [25]     Percent-good minimum [%]
%     opts.apply_errvel       [false]  Error velocity threshold on processed vel.
%     opts.errVel_threshold   [auto]   Override error velocity threshold [m/s]
%     opts.epsg_code          [32634]  UTM zone EPSG code for GPS projection
%
% Example — sidelobe on, depth limit at 5 m, correlation filter off:
%   opts.apply_sidelobe    = true;
%   opts.apply_depth_limit = true;
%   opts.max_depth_m       = 5.0;
%   opts.apply_corr        = false;
%   [BT,v,...] = processADCP_RDI(RAW, 0, 5, [], 'run01', opts);
%
% Outputs:
%   BT, v, CORR, ECHO, SL, VB, GPSdata, Data  - result structs

% ---- Parse opts with defaults ----
if nargin < 6 || isempty(opts), opts = struct(); end
apply_depth_limit = getopt(opts,'apply_depth_limit', false);
max_depth_m       = getopt(opts,'max_depth_m',       Inf);
apply_sidelobe    = getopt(opts,'apply_sidelobe',    true);
beamAngle_deg     = getopt(opts,'beamAngle_deg',     20);
apply_corr        = getopt(opts,'apply_corr',        false);
apply_pg          = getopt(opts,'apply_pg',          false);
pg_threshold      = getopt(opts,'pg_threshold',      25);
apply_errvel      = getopt(opts,'apply_errvel',      false);
epsg_code         = getopt(opts,'epsg_code',         32634);

% =========================================================================
% 1. Unpack RAW fields into local workspace
%    All names kept identical to original post-processing script.
% =========================================================================
nens   = RAW.nens;

% Fixed leader
WN     = RAW.WN;      WP    = RAW.WP;    WS    = RAW.WS;    WF    = RAW.WF;
LagWater = RAW.LagWater;  DataPings = RAW.DataPings;
plslgh = RAW.plslgh;  LowCorr = RAW.LowCorr;  WE = RAW.WE;
EA     = RAW.EA;      EB    = RAW.EB;    EX    = RAW.EX;    EZ    = RAW.EZ;
WT     = RAW.WT;      XmitC = RAW.XmitC;  XmitV = RAW.XmitV;
CodedWlementsWAterProfile = RAW.CodedWlementsWAterProfile;

% Variable leader
TIM_m  = RAW.TIM_m;   TS    = RAW.TS;
ED     = RAW.ED;       % transducer depth [dm]
EH     = RAW.EH(:)';   % heading [deg] — row vector
EP     = RAW.EP(:)';   % pitch   [deg]
ER     = RAW.ER(:)';   % roll    [deg]
M      = RAW.M;        % transformation matrices

% Transducer depth in metres (ED stored as decimetres in reader)
Ed     = double(ED(:)') ./ 10;    % dm → m, row vector

% Water profile
V1 = RAW.V1;  V2 = RAW.V2;  V3 = RAW.V3;  V4 = RAW.V4;
COR1 = RAW.COR1;  COR2 = RAW.COR2;  COR3 = RAW.COR3;  COR4 = RAW.COR4;
ECH1 = RAW.ECH1;  ECH2 = RAW.ECH2;  ECH3 = RAW.ECH3;  ECH4 = RAW.ECH4;
PG1  = RAW.PG1;   PG2  = RAW.PG2;   PG3  = RAW.PG3;   PG4  = RAW.PG4;

% Bottom track
BTV1 = RAW.BTV1(:)';  BTV2 = RAW.BTV2(:)';
BTV3 = RAW.BTV3(:)';  BTV4 = RAW.BTV4(:)';
RNG1 = RAW.RNG1(:)';  RNG2 = RAW.RNG2(:)';
RNG3 = RAW.RNG3(:)';  RNG4 = RAW.RNG4(:)';
BTcorr  = RAW.BTcorr(:)';   BTamp  = RAW.BTamp(:)';
BTcorr1 = RAW.BTcorr1(:)';  BTcorr2 = RAW.BTcorr2(:)';
BTcorr3 = RAW.BTcorr3(:)';  BTcorr4 = RAW.BTcorr4(:)';
BT_AMP1 = RAW.BT_AMP1(:)';  BT_AMP2 = RAW.BT_AMP2(:)';
BT_AMP3 = RAW.BT_AMP3(:)';  BT_AMP4 = RAW.BT_AMP4(:)';
BT_RSSI1 = RAW.BT_RSSI1(:)'; BT_RSSI2 = RAW.BT_RSSI2(:)';
BT_RSSI3 = RAW.BT_RSSI3(:)'; BT_RSSI4 = RAW.BT_RSSI4(:)';
BTgain  = RAW.BTgain(:)';
BT_PG1  = RAW.BT_PG1(:)';   BT_PG2  = RAW.BT_PG2(:)';
BT_PG3  = RAW.BT_PG3(:)';   BT_PG4  = RAW.BT_PG4(:)';
BP      = RAW.BP(:)';        BTdelay = RAW.BTdelay(:)';
BX      = RAW.BX(:)';        BE      = RAW.BE(:)';

% Vertical beam
EVALamp = RAW.EVALamp;  RSSIAmp = RAW.RSSIAmp;
VRNG1   = RAW.VRNG1;    VRNG2   = RAW.VRNG2;
VFLAG   = RAW.VFLAG;    VGAIN   = RAW.VGAIN;
VWN     = RAW.VWN;      VWP     = RAW.VWP;
VWS     = RAW.VWS;      VWFd    = RAW.VWFd;
VTL     = RAW.VTL;      VLag    = RAW.VLag;
VCodElements = RAW.VCodElements;
VV   = RAW.VV;   VCOR = RAW.VCOR;
VECH = RAW.VECH; BEDGOODECH = RAW.BEDGOODECH;

% Surface layer
SWN  = RAW.SWN;    SWS = RAW.SWS;   SWDistance = RAW.SWDistance;
SV1  = RAW.SV1;    SV2 = RAW.SV2;   SV3 = RAW.SV3;    SV4 = RAW.SV4;
SCOR1 = RAW.SCOR1; SCOR2 = RAW.SCOR2; SCOR3 = RAW.SCOR3; SCOR4 = RAW.SCOR4;
SECH1 = RAW.SECH1; SECH2 = RAW.SECH2; SECH3 = RAW.SECH3; SECH4 = RAW.SECH4;
SPG1  = RAW.SPG1;  SPG2  = RAW.SPG2;  SPG3  = RAW.SPG3;  SPG4  = RAW.SPG4;

% GPS
Latd  = RAW.Latd(:)';   Long  = RAW.Long(:)';   Z_gga  = RAW.Z_gga(:)';
Latd2 = RAW.Latd2(:)';  Long2 = RAW.Long2(:)';  Z_gga2 = RAW.Z_gga2(:)';
Latd3 = RAW.Latd3(:)';  Long3 = RAW.Long3(:)';  Z_gga3 = RAW.Z_gga3(:)';
T_gpsNUM  = RAW.T_gpsNUM(:)';
T_gpsNUM2 = RAW.T_gpsNUM2(:)';
T_gpsNUM3 = RAW.T_gpsNUM3(:)';
VTGH1 = RAW.VTGH1(:)';  VTGV1 = RAW.VTGV1(:)';
VTGH2 = RAW.VTGH2(:)';  VTGV2 = RAW.VTGV2(:)';
VTGH3 = RAW.VTGH3(:)';  VTGV3 = RAW.VTGV3(:)';
Z_gga  = RAW.Z_gga(:)'; Z_gga2 = RAW.Z_gga2(:)'; Z_gga3 = RAW.Z_gga3(:)';
Tgps  = RAW.Tgps;   Tgps2 = RAW.Tgps2;  Tgps3 = RAW.Tgps3;
Msg_type = RAW.Msg_type(:)';  Msg_size = RAW.Msg_size(:)';

% =========================================================================
% 2. Align GPS and attitude arrays to BT length
%    BTV1 is the reference length (= nens).  GPS may be shorter if some
%    ensembles had no NMEA fix recorded.
% =========================================================================
nbt = numel(BTV1);    % reference: one value per ensemble

Latd      = padarray_row(Latd,      nbt, 0);
Latd2     = padarray_row(Latd2,     nbt, 0);
Latd3     = padarray_row(Latd3,     nbt, 0);
Long      = padarray_row(Long,      nbt, 0);
Long2     = padarray_row(Long2,     nbt, 0);
Long3     = padarray_row(Long3,     nbt, 0);
T_gpsNUM  = padarray_row(T_gpsNUM,  nbt, 0);
T_gpsNUM2 = padarray_row(T_gpsNUM2, nbt, 0);
T_gpsNUM3 = padarray_row(T_gpsNUM3, nbt, 0);
VTGH1     = padarray_row(VTGH1,     nbt, 0);
VTGH2     = padarray_row(VTGH2,     nbt, 0);
VTGH3     = padarray_row(VTGH3,     nbt, 0);
VTGV1     = padarray_row(VTGV1,     nbt, 0);
VTGV2     = padarray_row(VTGV2,     nbt, 0);
VTGV3     = padarray_row(VTGV3,     nbt, 0);
Z_gga     = padarray_row(Z_gga,     nbt, NaN);
Z_gga2    = padarray_row(Z_gga2,    nbt, NaN);
Z_gga3    = padarray_row(Z_gga3,    nbt, NaN);
Msg_type  = padarray_row(Msg_type,  nbt, 0);
Msg_size  = padarray_row(Msg_size,  nbt, 0);

% Attitude arrays — also align to nbt
EH  = padarray_row(EH,  nbt, 0);
EP  = padarray_row(EP,  nbt, 0);
ER  = padarray_row(ER,  nbt, 0);
Ed  = padarray_row(Ed,  nbt, NaN);
TIM_m = padarray_row(TIM_m(:)', nbt, NaN);
TS    = padarray_row(TS(:)',    nbt, 0);

% BT scalar arrays — align to nbt (should already be nbt, safety only)
RNG1 = padarray_row(RNG1, nbt, NaN);
RNG2 = padarray_row(RNG2, nbt, NaN);
RNG3 = padarray_row(RNG3, nbt, NaN);
RNG4 = padarray_row(RNG4, nbt, NaN);
BTcorr  = padarray_row(BTcorr,  nbt, NaN);
BTamp   = padarray_row(BTamp,   nbt, NaN);
BTgain  = padarray_row(BTgain,  nbt, NaN);
BTdelay = padarray_row(BTdelay, nbt, NaN);
BP      = padarray_row(BP,      nbt, NaN);
BX      = padarray_row(BX,      nbt, NaN);

% WN must have a value for every ensemble — use most common value if missing
if isempty(WN) || numel(WN) < nbt
    if ~isempty(WN)
        WN = padarray_row(WN(:)', nbt, mode(WN));
    else
        WN = zeros(1, nbt);
    end
end

% =========================================================================
% 3. Post-process velocities
% =========================================================================

% --- 3a. Bad-data sentinel and unit conversion ---
% RDI uses -32768 (0x8000) as invalid-data flag.  Replace with NaN.
% Velocities stored in mm/s → convert to m/s.
V1(V1==-32768)=NaN;  V2(V2==-32768)=NaN;
V3(V3==-32768)=NaN;  V4(V4==-32768)=NaN;
V1=V1/1000; V2=V2/1000; V3=V3/1000; V4=V4/1000;

BTV1(BTV1==-32768)=NaN; BTV2(BTV2==-32768)=NaN;
BTV3(BTV3==-32768)=NaN; BTV4(BTV4==-32768)=NaN;
BTV1=BTV1/1000; BTV2=BTV2/1000; BTV3=BTV3/1000; BTV4=BTV4/1000;

% BT ranges: cm → m
RNG1=RNG1/100; RNG2=RNG2/100; RNG3=RNG3/100; RNG4=RNG4/100;

% Forward-fill zero ranges (instrument reports 0 when BT lock is lost)
for rr = 2:nbt
    if RNG1(rr)==0, RNG1(rr)=RNG1(rr-1); end
    if RNG2(rr)==0, RNG2(rr)=RNG2(rr-1); end
    if RNG3(rr)==0, RNG3(rr)=RNG3(rr-1); end
    if RNG4(rr)==0, RNG4(rr)=RNG4(rr-1); end
end

% Surface layer velocities: sentinel + unit conversion
if ~isempty(SV1)
    SV1(SV1==-32768)=NaN; SV2(SV2==-32768)=NaN;
    SV3(SV3==-32768)=NaN; SV4(SV4==-32768)=NaN;
    SV1=SV1/1000; SV2=SV2/1000; SV3=SV3/1000; SV4=SV4/1000;
end

% Mean echo and correlation (all-beam average, used for QC reporting)
ECH = (ECH1+ECH2+ECH3+ECH4)./4;
COR = (COR1+COR2+COR3+COR4)./4;

% Beam-averaged range, spread, minimum
RNG    = median([RNG1; RNG2; RNG3; RNG4], 1, 'omitnan');
diffRG = max([RNG1; RNG2; RNG3; RNG4], [], 1) - ...
         min([RNG1; RNG2; RNG3; RNG4], [], 1);
minRG  = min([RNG1; RNG2; RNG3; RNG4], [], 1);

% Instrument geometry from fixed leader (median over ensembles, ignore zeros)
Wf = median(WF(WF>0), 'omitnan') / 100;      % blank after transmit [m]
Ws = median(WS(WS>0), 'omitnan') / 100;      % cell (bin) size [m]
Pl = median(plslgh(plslgh>0),'omitnan') / 100; % transmit pulse length [m]
Lg = median(LagWater(LagWater>0),'omitnan') / 100; % lag length [m]

% Beam angle: decode from fixed leader system config byte
% QRev: Inst.beamAng from bitms(7:8). Common values: 15°, 20°, 30°.
% We default to 20° (RioGrande / RiverPro / most river ADCPs).
beamAngle_deg = 20;    % ← change to 15 for StreamPro, 30 for some WH

% Time vector
TIME      = cellstr(datestr(TIM_m));
DateVector = datevec(TIM_m);
time      = [DateVector(:,4:6), TS(:)];
timeSS    = time(:,1)*3600 + time(:,2)*60 + time(:,3) + time(:,4)./100;
DeltaT    = [0; diff(timeSS)];

% Outlier range correction: when beam spread > cell + 6% depth, use min range
% (consistent with original script and QRev's computeCellData)
EL = diffRG > Ws + 0.06*RNG & diffRG < RNG/2;
RNG(EL) = minRG(EL);

% Water surface to bottom [m]
SEZ = Ed + RNG;

nCells = max(WN);
if isempty(nCells) || nCells == 0, nCells = size(V1,1); end

% Cell-centre depths [m] — nCells×nbt matrix
PRO = repmat(Ed, nCells, 1) + Pl/2 + Wf + 3/4*Ws + ...
      repmat((0:nCells-1)' * Ws, 1, nbt);

% =========================================================================
% 3b.  QUALITY FILTER MASKS  (all disabled by default — set flag to enable)
%
%  These masks are computed but NOT applied unless you set the corresponding
%  enable flag to true.  Inspect filter_info after processing to decide
%  which filters are appropriate for your data before enabling them.
%
%  Independent flags:
%   apply_depth_limit  — simple depth cutoff: remove all cells whose centre
%                        is deeper than max_depth_m (user-defined, metres).
%                        Useful when you know the river bottom depth.
%
%   apply_sidelobe     — acoustic sidelobe cutoff: removes cells close to
%                        the bed where sidelobe reflections contaminate data.
%                        Cutoff = RNG * cos(beamAngle) - lag_effect (per ens).
%                        This varies ensemble by ensemble with river depth.
%
%   apply_corr / apply_pg / apply_errvel — signal quality filters.
%
%  Both depth_limit and sidelobe act on PROCESSED outputs (VE, VN, V_B etc.)
%  but leave raw V1/V2/V3/V4 untouched.
% =========================================================================

% --- Geometry parameters (needed for PRO/SEZ regardless of filtering) ---
Wf = median(WF(WF>0), 'omitnan') / 100;       % blank after transmit [m]
Ws = median(WS(WS>0), 'omitnan') / 100;       % cell size [m]
Pl = median(plslgh(plslgh>0),'omitnan') / 100;% transmit pulse length [m]
Lg = median(LagWater(LagWater>0),'omitnan') / 100; % lag length [m]

% corr/errVel thresholds: use opts override if supplied, else auto from file
corr_threshold   = getopt(opts,'corr_threshold', ...
                    max(double(median(LowCorr(LowCorr>0),'omitnan')), 64));
errVel_threshold = getopt(opts,'errVel_threshold', ...
                    median(WE(WE>0),'omitnan') / 1000);
if isnan(errVel_threshold) || errVel_threshold <= 0
    errVel_threshold = 0.10;
end

% --- Sidelobe mask (computed but not applied unless apply_sidelobe=true) ---
cellOffset    = (0:nCells-1)' * Ws;
cellDist      = Wf + Pl/2 + 3/4*Ws + cellOffset;    % nCells×1, from transducer
cellDist_mat  = repmat(cellDist, 1, nbt);
lag_effect    = (Lg + Pl + Ws) ./ 2;
sidelobe_cutoff = RNG .* cosd(beamAngle_deg) - lag_effect;
sidelobe_mask   = bsxfun(@ge, cellDist_mat, sidelobe_cutoff);

% --- Simple depth limit mask (nCells × nbt) ---
% PRO = cell-centre depth below surface [m], computed above.
% Mask is true wherever a cell is deeper than max_depth_m.
depth_limit_mask = PRO > max_depth_m;   % always computed, applied only if flag set
if ~isempty(COR1) && size(COR1,1) >= nCells
    corr_mask = COR1(1:nCells,:) < corr_threshold | ...
                COR2(1:nCells,:) < corr_threshold | ...
                COR3(1:nCells,:) < corr_threshold | ...
                COR4(1:nCells,:) < corr_threshold;
else
    corr_mask = false(nCells, nbt);
end

% --- Percent-good mask ---
if ~isempty(PG4) && size(PG4,1) >= 1
    pg4_trim = PG4(1:min(nCells,size(PG4,1)), 1:min(nbt,size(PG4,2)));
    pg4_full = nan(nCells, nbt);
    pg4_full(1:size(pg4_trim,1), 1:size(pg4_trim,2)) = pg4_trim;
    pg_mask  = pg4_full < pg_threshold;
else
    pg_mask = false(nCells, nbt);
end

% --- Apply masks only if enabled (raw V1-V4 never touched here) ---
if apply_sidelobe || apply_corr || apply_pg
    combined_mask = (apply_sidelobe & sidelobe_mask) | ...
                    (apply_corr     & corr_mask)     | ...
                    (apply_pg       & pg_mask);
    if size(combined_mask,1) > size(V1,1)
        combined_mask = combined_mask(1:size(V1,1),:);
    elseif size(combined_mask,1) < size(V1,1)
        combined_mask(end+1:size(V1,1),:) = false;
    end
    combined_mask = combined_mask(:, 1:size(V1,2));
    V1(combined_mask)=NaN; V2(combined_mask)=NaN;
    V3(combined_mask)=NaN; V4(combined_mask)=NaN;
    fprintf('  Filters applied to raw V — Sidelobe:%d Corr:%d PG:%d\n', ...
        apply_sidelobe, apply_corr, apply_pg);
else
    combined_mask = false(size(V1));
    fprintf('  All raw-V filters disabled\n');
end

% Store filter diagnostics
filter_info.sidelobe_mask    = sidelobe_mask;
filter_info.depth_limit_mask = depth_limit_mask;
filter_info.corr_mask        = corr_mask;
filter_info.pg_mask          = pg_mask;
filter_info.combined_mask    = combined_mask;
filter_info.corr_threshold   = corr_threshold;
filter_info.errVel_threshold = errVel_threshold;
filter_info.pg_threshold     = pg_threshold;
filter_info.sidelobe_cutoff  = sidelobe_cutoff;
filter_info.beamAngle_deg    = beamAngle_deg;
filter_info.apply_depth_limit = apply_depth_limit;
filter_info.max_depth_m       = max_depth_m;
filter_info.apply_sidelobe   = apply_sidelobe;
filter_info.apply_corr       = apply_corr;
filter_info.apply_pg         = apply_pg;
filter_info.apply_errvel     = apply_errvel;

% =========================================================================
% 4. Beam → instrument/Earth coordinates
%
% The ADCP may output V1-V4 in different coordinate systems depending on
% the EX command setting (stored in fixed leader byte +25):
%   EX bits 4:3 (dec2bin positions 4:5) = '00' → BEAM coordinates
%   EX bits 4:3                          = '01' → INSTRUMENT coordinates
%   EX bits 4:3                          = '10' → SHIP coordinates
%   EX bits 4:3                          = '11' → EARTH (ENU) coordinates
%
% For most river ADCP deployments (WinRiver II default, RiverPro auto-mode):
%   EX = Earth → V1=East, V2=North, V3=Up, V4=Error  → NO transform needed
%
% Only if EX = BEAM should we apply M.
% =========================================================================

% Decode coordinate mode from first valid EX record
coordMode = 'EARTH';   % safe default for river deployments
if ~isempty(EX)
    for qq = 1:size(EX,1)
        row = EX(qq,:);
        if numel(row) >= 5
            cm = base2dec(row(4:5), 2);
            switch cm
                case 0, coordMode='BEAM';
                case 1, coordMode='INST';
                case 2, coordMode='SHIP';
                case 3, coordMode='EARTH';
            end
            break
        end
    end
end
fprintf('  Coordinate mode from EX: %s\n', coordMode);

VX1 = V1;  VX2 = V2;  VX3 = V3;  VX4 = V4;   % default: pass through

if strcmp(coordMode,'BEAM') && ~isempty(M) && ~isempty(M{1})
    % Data is in beam coordinates → apply transformation matrix M
    nan_mask_V = isnan(V1) | isnan(V2) | isnan(V3) | isnan(V4);
    V1tmp = V1;  V2tmp = V2;  V3tmp = V3;  V4tmp = V4;
    V1tmp(isnan(V1tmp))=0; V2tmp(isnan(V2tmp))=0;
    V3tmp(isnan(V3tmp))=0; V4tmp(isnan(V4tmp))=0;

    for jj = 1:nens
        if jj > numel(M) || isempty(M{jj}), continue; end
        for j = 1:size(V1,1)
            vx = M{jj} * [V1tmp(j,jj); V2tmp(j,jj); V3tmp(j,jj); V4tmp(j,jj)];
            VX1(j,jj)=vx(1); VX2(j,jj)=vx(2); VX3(j,jj)=vx(3); VX4(j,jj)=vx(4);
        end
    end
    VX1(nan_mask_V)=NaN; VX2(nan_mask_V)=NaN;
    VX3(nan_mask_V)=NaN; VX4(nan_mask_V)=NaN;
    fprintf('  Water velocity: beam→instrument transform applied\n');
else
    fprintf('  Water velocity: already in %s coords, no transform applied\n', coordMode);
end

% BT beam → instrument
% Same logic: only transform if BEAM coordinates
nan_mask_BT = isnan(BTV1) & isnan(BTV2) & isnan(BTV3) & isnan(BTV4);

[BTV1, BTV2, BTV3, BTV4, ThreeBeamsNoNZeros] = ...
    threebeamSol(BTV1, BTV2, BTV3, BTV4);

BX1 = BTV1;  BX2 = BTV2;  BX3 = BTV3;  BX4 = BTV4;   % default: pass through

if strcmp(coordMode,'BEAM') && ~isempty(M) && ~isempty(M{1})
    BX1=nan(1,nbt); BX2=nan(1,nbt); BX3=nan(1,nbt); BX4=nan(1,nbt);
    for ll = 1:nbt
        if nan_mask_BT(ll), continue; end
        if ll > numel(M) || isempty(M{ll}), continue; end
        b1=BTV1(ll); b2=BTV2(ll); b3=BTV3(ll); b4=BTV4(ll);
        if any(isnan([b1 b2 b3 b4])), continue; end
        bx = M{ll} * [b1; b2; b3; b4];
        BX1(ll)=bx(1); BX2(ll)=bx(2); BX3(ll)=bx(3); BX4(ll)=bx(4);
    end
    fprintf('  BT velocity: beam→instrument transform applied\n');
else
    % Already in Earth/Instrument coords: BX1=E, BX2=N, BX3=U, BX4=Err
    BX1(nan_mask_BT)=NaN; BX2(nan_mask_BT)=NaN;
    BX3(nan_mask_BT)=NaN; BX4(nan_mask_BT)=NaN;
    fprintf('  BT velocity: already in %s coords, no transform applied\n', coordMode);
end

% --- Error velocity filter (disabled by default, see apply_errvel flag) ---
if apply_errvel && ~isempty(VX4)
    errVel_mask = abs(VX4) > errVel_threshold;
    VX1(errVel_mask)=NaN; VX2(errVel_mask)=NaN;
    VX3(errVel_mask)=NaN; VX4(errVel_mask)=NaN;
    filter_info.errVel_mask = errVel_mask;
    fprintf('  Error velocity filter: %.0f%% cells removed (threshold=%.3f m/s)\n', ...
        100*mean(errVel_mask(:),'omitnan'), errVel_threshold);
else
    filter_info.errVel_mask = false(size(VX4));
end

% Remove boat velocity (bottom-track referenced)
V1_B = VX1 - repmat(BX1, size(VX1,1), 1); V1_B(abs(V1_B)>trasholdVB)=NaN;
V2_B = VX2 - repmat(BX2, size(VX1,1), 1); V2_B(abs(V2_B)>trasholdVB)=NaN;
V3_B = VX3 - repmat(BX3, size(VX1,1), 1); V3_B(abs(V3_B)>trasholdVB)=NaN;
V4_B = VX4 - repmat(BX4, size(VX1,1), 1); V4_B(abs(V4_B)>trasholdVB)=NaN;

% =========================================================================
% 5. Heading-only rotation (ENU without pitch/roll)
% =========================================================================
EH_rad = deg2rad(EH);
EP_rad = deg2rad(EP);
ER_rad = deg2rad(ER);

R_EH = angle2dcm(zeros(1,nbt), zeros(1,nbt), EH_rad);

BT_UEN = nan(3,1,nbt);
for eh = 1:nbt
    BT_UEN(:,:,eh) = R_EH(:,:,eh) * [BX3(eh); BX1(eh); BX2(eh)];
end

V_U  = nan(size(VX1));  V_E1 = nan(size(VX1));  V_N1 = nan(size(VX1));
for jj = 1:nens
    for j = 1:size(VX3,1)
        v_UEN = R_EH(:,:,jj) * [VX3(j,jj)./2; VX1(j,jj); VX2(j,jj)];
        V_U(j,jj)=v_UEN(1); V_E1(j,jj)=v_UEN(2); V_N1(j,jj)=v_UEN(3);
    end
end

VE_B = V_E1 - repmat(reshape(BT_UEN(2,:,:),[],1,1)', size(V_E1,1), 1);
VN_B = V_N1 - repmat(reshape(BT_UEN(3,:,:),[],1,1)', size(V_N1,1), 1);

% =========================================================================
% 6. Full pitch-roll rotation
% =========================================================================
R = angle2dcm(EP_rad, ER_rad, EH_rad);

BT_UEN_PitchRoll = nan(3,1,nbt);
for eh = 1:nbt
    BT_UEN_PitchRoll(:,:,eh) = R(:,:,eh) * [BX3(eh); BX1(eh); BX2(eh)];
end
btE_pitchRoll = reshape(BT_UEN_PitchRoll(2,:,:),[],1,1)';
btN_pitchRoll = reshape(BT_UEN_PitchRoll(3,:,:),[],1,1)';
btNE_pitchRoll_MOD = hypot(btE_pitchRoll, btN_pitchRoll);

V_UPR  = nan(size(VX1)); V_E1PR = nan(size(VX1)); V_N1PR = nan(size(VX1));
for jj = 1:nens
    for j = 1:size(VX3,1)
        v_UEN = R(:,:,jj) * [VX3(j,jj)./2; VX1(j,jj); VX2(j,jj)];
        V_UPR(j,jj)=v_UEN(1); V_E1PR(j,jj)=v_UEN(2); V_N1PR(j,jj)=v_UEN(3);
    end
end

VE_B_PitchRoll = V_E1PR - repmat(reshape(BT_UEN_PitchRoll(2,:,:),[],1,1)', size(V_E1PR,1), 1);
VN_B_PitchRoll = V_N1PR - repmat(reshape(BT_UEN_PitchRoll(3,:,:),[],1,1)', size(V_N1PR,1), 1);
VNEmod_B_PitchRoll = hypot(VE_B_PitchRoll, VN_B_PitchRoll);

% =========================================================================
% Apply depth_limit and sidelobe cutoff independently to PROCESSED outputs.
% Raw V1/V2/V3/V4 are always left untouched.
%
%  apply_depth_limit — user depth ceiling (max_depth_m, constant per file)
%  apply_sidelobe    — geometric BT-based cutoff (varies per ensemble)
%
% Both can be toggled independently.
% =========================================================================

% Helper: resize mask rows to match processed velocity arrays
    function m = fit_mask(m, ref)
        nr = size(ref,1); nc = size(ref,2);
        if size(m,1) < nr, m(end+1:nr,:) = true; end
        m = m(1:nr, 1:min(nc,size(m,2)));
        if size(m,2) < nc, m(:,end+1:nc) = false; end
    end

% --- 1. Simple depth cutoff ---
if apply_depth_limit
    dl = fit_mask(depth_limit_mask, V_E1);
    V1_B(dl)=NaN;            V2_B(dl)=NaN;
    V3_B(dl)=NaN;            V4_B(dl)=NaN;
    V_U(dl)=NaN;             V_E1(dl)=NaN;             V_N1(dl)=NaN;
    VE_B(dl)=NaN;            VN_B(dl)=NaN;
    V_UPR(dl)=NaN;           V_E1PR(dl)=NaN;           V_N1PR(dl)=NaN;
    VE_B_PitchRoll(dl)=NaN;  VN_B_PitchRoll(dl)=NaN;
    VNEmod_B_PitchRoll(dl)=NaN;
    fprintf('  Depth limit (>%.1f m): %.0f%% cells removed\n', ...
        max_depth_m, 100*mean(dl(:),'omitnan'));
end

% --- 2. Acoustic sidelobe cutoff ---
if apply_sidelobe
    sl = fit_mask(sidelobe_mask, V_E1);
    V1_B(sl)=NaN;            V2_B(sl)=NaN;
    V3_B(sl)=NaN;            V4_B(sl)=NaN;
    V_U(sl)=NaN;             V_E1(sl)=NaN;             V_N1(sl)=NaN;
    VE_B(sl)=NaN;            VN_B(sl)=NaN;
    V_UPR(sl)=NaN;           V_E1PR(sl)=NaN;           V_N1PR(sl)=NaN;
    VE_B_PitchRoll(sl)=NaN;  VN_B_PitchRoll(sl)=NaN;
    VNEmod_B_PitchRoll(sl)=NaN;
    fprintf('  Sidelobe cutoff: %.0f%% cells removed\n', ...
        100*mean(sl(:),'omitnan'));
else
    fprintf('  Sidelobe cutoff: disabled\n');
end

filter_info.sidelobe_applied_to_processed   = apply_sidelobe;
filter_info.depth_limit_applied_to_processed = apply_depth_limit;

% =========================================================================
% 7. Earth-coordinate BT speed and direction
% =========================================================================
DB   = 180*((BX1>0 & BX2<0) | (BX1<0 & BX2<0));
DEGB = wrapTo360(EH + DB + MGVAR + atand(BX1./BX2));
BTmod = hypot(BX1, BX2);
btvE  = BTmod.*sind(DEGB);
btvN  = BTmod.*cosd(DEGB);
BTmodNE = hypot(btvE, btvN);

% Water velocity direction and speed (BT-referenced, heading-only)
MAGB = hypot(V1_B, V2_B);
DV   = 180*((V1_B>0 & V2_B<0) | (V1_B<0 & V2_B<0));
DEGV = wrapTo360(EH + DV + MGVAR + atand(V1_B./V2_B));
V_E = MAGB.*sind(DEGV);
V_N = MAGB.*cosd(DEGV);
V_NEmod = hypot(V_N, V_E);

% =========================================================================
% 8. Surface layer (RiverRay / RiverPro)
% =========================================================================
hasSurface = ~isempty(SWN) && ~isempty(SV1);

if hasSurface
    SV1tmp=SV1; SV2tmp=SV2; SV3tmp=SV3; SV4tmp=SV4;

    nSens = size(SV1,2);
    SVX1=SV1; SVX2=SV2; SVX3=SV3; SVX4=SV4;   % default: pass through

    if strcmp(coordMode,'BEAM') && ~isempty(M) && ~isempty(M{1})
        nan_mask_SV = isnan(SV1)|isnan(SV2)|isnan(SV3)|isnan(SV4);
        SV1tmp(isnan(SV1tmp))=0; SV2tmp(isnan(SV2tmp))=0;
        SV3tmp(isnan(SV3tmp))=0; SV4tmp(isnan(SV4tmp))=0;
        SVX1=nan(size(SV1)); SVX2=nan(size(SV1));
        SVX3=nan(size(SV1)); SVX4=nan(size(SV1));
        MM = M(1:min(nSens,numel(M)));
        for jj = 1:nSens
            if jj>numel(MM)||isempty(MM{jj}), continue; end
            for j = 1:size(SV1,1)
                svx = MM{jj} * [SV1tmp(j,jj); SV2tmp(j,jj); SV3tmp(j,jj); SV4tmp(j,jj)];
                SVX1(j,jj)=svx(1); SVX2(j,jj)=svx(2); SVX3(j,jj)=svx(3); SVX4(j,jj)=svx(4);
            end
        end
        SVX1(nan_mask_SV)=NaN; SVX2(nan_mask_SV)=NaN;
        SVX3(nan_mask_SV)=NaN; SVX4(nan_mask_SV)=NaN;
    end

    maxSWN = max(SWN(~isnan(SWN)));
    if isempty(maxSWN), maxSWN=1; end
    SV1_B = SVX1 - repmat(BX1(1:nSens), maxSWN, 1); SV1_B(abs(SV1_B)>trasholdVB)=NaN;
    SV2_B = SVX2 - repmat(BX2(1:nSens), maxSWN, 1); SV2_B(abs(SV2_B)>trasholdVB)=NaN;
    SV3_B = SVX3 - repmat(BX3(1:nSens), maxSWN, 1); SV3_B(abs(SV3_B)>trasholdVB)=NaN;
    SV4_B = SVX4 - repmat(BX4(1:nSens), maxSWN, 1); SV4_B(abs(SV4_B)>trasholdVB)=NaN;

    SMAGB = hypot(SV1_B, SV2_B);
    SDV   = 180*((SV1_B>0 & SV2_B<0) | (SV1_B<0 & SV2_B<0));
    SDEGV = wrapTo360(EH(1:nSens) + SDV + MGVAR + atand(SV1_B./SV2_B));
    SV_E  = SMAGB.*sind(SDEGV);
    SV_N  = SMAGB.*cosd(SDEGV);
    SV_NEmod = hypot(SV_N, SV_E);
end

% =========================================================================
% 9. GPS boat velocity (GGA-derived)
% =========================================================================
% Project lat/lon → UTM [m] using projfwd (replaces deprecated mfwdtran).
% PROJ defines the projection; adjust the UTM zone string to match your site.
proj = projcrs(epsg_code);   % UTM zone from opts.epsg_code (default 32634 = WGS84 UTM 34N)
                         % Zone letter T (your original '34T') = Northern hemisphere
                         % EPSG 32634 = UTM zone 34N, 32734 = zone 34S

Latd2(Latd2==0) = NaN;  Long2(Long2==0) = NaN;
T_gpsNUM2(T_gpsNUM2==0) = NaN;

LatdNoN = fillmissing(Latd2, 'linear');
LongNoN = fillmissing(Long2, 'linear');

% projfwd expects (proj, lat, lon) and returns (easting, northing)
[XxNoN, YyNoN] = projfwd(proj, LatdNoN, LongNoN);

GPVXfinal = [0, diff(XxNoN)] ./ DeltaT(:)';
GPVYfinal = [0, diff(YyNoN)] ./ DeltaT(:)';
GPVfinal  = hypot(GPVXfinal, GPVYfinal);

% NaN-guard for zero DeltaT
GPVXfinal(~isfinite(GPVXfinal)) = NaN;
GPVYfinal(~isfinite(GPVYfinal)) = NaN;

VE_GGA  = V_E1   + repmat(GPVXfinal, size(V_E1,1), 1);
VN_GGA  = V_N1   + repmat(GPVYfinal, size(V_N1,1), 1);
V_NEmodGGA = hypot(VN_GGA, VE_GGA);

VE_GGA_PR = V_E1PR + repmat(GPVXfinal, size(V_E1,1), 1);
VN_GGA_PR = V_N1PR + repmat(GPVYfinal, size(V_N1,1), 1);
V_NEmodGGA_PR = hypot(VN_GGA_PR, VE_GGA_PR);

Latd_FILLED  = fillmissing(Latd,  'linear');
Long_FILLED  = fillmissing(Long,  'linear');

btE_GGA  = btvE + GPVXfinal;
btN_GGA  = btvN + GPVYfinal;
btNEmodGGA = hypot(btE_GGA, btN_GGA);

btE_GGA_PitchnRoll = btE_pitchRoll + GPVXfinal;
btN_GGA_PitchnRoll = btN_pitchRoll + GPVYfinal;
btNEmodGGA_PitchnRoll = hypot(btE_GGA_PitchnRoll, btN_GGA_PitchnRoll);

% =========================================================================
% 10. VTG boat velocity
% =========================================================================
VTGH1(VTGH1==0)=NaN;  VTGH1 = fillmissing(VTGH1, 'linear');
VTGV1(VTGV1==0)=NaN;  VTGV1 = fillmissing(VTGV1, 'linear');

VTG1E = VTGV1.*sind(VTGH1);
VTG1N = VTGV1.*cosd(VTGH1);

VE_VTG = V_E1 + repmat(VTG1E, size(V_E1,1), 1);
VN_VTG = V_N1 + repmat(VTG1N, size(V_N1,1), 1);
V_NEmodVTG = hypot(VN_VTG, VE_VTG);

btE_VTG = btvE + VTG1E;
btN_VTG = btvN + VTG1N;
btNEmodVTG = hypot(btE_VTG, btN_VTG);

btE_VTG_PitchnRoll = btE_pitchRoll + VTG1E;
btN_VTG_PitchnRoll = btN_pitchRoll + VTG1N;
btNEmodVTG_PitchnRoll = hypot(btE_VTG_PitchnRoll, btN_VTG_PitchnRoll);

% =========================================================================
% 11. Pack output structs
% =========================================================================

% --- Bottom track ---
BT.BTV1 = BTV1;  BT.BTV2 = BTV2;  BT.BTV3 = BTV3;  BT.BTV4 = BTV4;
BT.BX1  = BX1;   BT.BX2  = BX2;   BT.BX3  = BX3;   BT.BX4  = BX4;
BT.DEGB = DEGB;
BT.BTgain  = BTgain;
BT.BX      = BX;
BT.BTcorr  = BTcorr;   BT.BTamp = BTamp;
BT.RNG1 = RNG1; BT.RNG2 = RNG2; BT.RNG3 = RNG3; BT.RNG4 = RNG4;
BT.RNG  = RNG;
BT.ThreeBeamsNoNZeros = ThreeBeamsNoNZeros;
BT.BT_AMP1 = BT_AMP1; BT.BT_AMP2 = BT_AMP2;
BT.BT_AMP3 = BT_AMP3; BT.BT_AMP4 = BT_AMP4;
BT.BT_corr1 = BTcorr1; BT.BT_corr2 = BTcorr2;
BT.BT_corr3 = BTcorr3; BT.BT_corr4 = BTcorr4;
BT.BT_PG1   = BT_PG1;  BT.BT_PG2   = BT_PG2;   % added: BT percent good
BT.BT_PG3   = BT_PG3;  BT.BT_PG4   = BT_PG4;
BT.BT_RSSI1 = BT_RSSI1; BT.BT_RSSI2 = BT_RSSI2;
BT.BT_RSSI3 = BT_RSSI3; BT.BT_RSSI4 = BT_RSSI4;
BT.BP  = BP;   BT.BTmod = BTmod;  BT.BTdelay = BTdelay;
BT.btvE = btvE;  BT.btvN = btvN;  BT.btvError = BX4;
BT.btE_pitchRoll = btE_pitchRoll;
BT.btN_pitchRoll = btN_pitchRoll;
BT.btNE_pitchRoll_MOD = btNE_pitchRoll_MOD;
BT.btE_GGA = btE_GGA;  BT.btN_GGA = btN_GGA;  BT.btNEmodGGA = btNEmodGGA;
BT.btE_GGA_PitchnRoll = btE_GGA_PitchnRoll;
BT.btN_GGA_PitchnRoll = btN_GGA_PitchnRoll;
BT.btNEmodGGA_PitchnRoll = btNEmodGGA_PitchnRoll;
BT.btE_VTG = btE_VTG;  BT.btN_VTG = btN_VTG;  BT.btNEmodVTG = btNEmodVTG;
BT.btE_VTG_PitchnRoll = btE_VTG_PitchnRoll;
BT.btN_VTG_PitchnRoll = btN_VTG_PitchnRoll;
BT.CoordModeFromEX = RAW.CoordModeFromEX;

% --- Water velocities ---
v.v1 = V1;   v.v2 = V2;   v.v3 = V3;   v.v4 = V4;
v.VX1 = VX1; v.VX2 = VX2; v.VX3 = VX3; v.VX4 = VX4;
v.V1_B = V1_B; v.V2_B = V2_B; v.V3_B = V3_B; v.V4_B = V4_B;
v.MAGB = MAGB;
v.V_E  = V_E;   v.V_N  = V_N;
v.DEGV = DEGV;
v.V_NEmod = V_NEmod;
v.VE_B_PitchRoll = VE_B_PitchRoll;
v.VN_B_PitchRoll = VN_B_PitchRoll;
v.VNEmod_B_PitchRoll = VNEmod_B_PitchRoll;
v.V_E1nonref = V_E1;   v.V_N1nonref = V_N1;   v.V_Unonref = V_U;
v.VE_GGA  = VE_GGA;   v.VN_GGA  = VN_GGA;   v.V_NEmodGGA = V_NEmodGGA;
v.VE_GGA_PR = VE_GGA_PR; v.VN_GGA_PR = VN_GGA_PR;
v.V_NEmodGGA_PR = V_NEmodGGA_PR;
v.VE_VTG = VE_VTG; v.VN_VTG = VN_VTG; v.V_NEmodVTG = V_NEmodVTG;

% --- Acoustics ---
ECHO.ECH1 = ECH1; ECHO.ECH2 = ECH2; ECHO.ECH3 = ECH3; ECHO.ECH4 = ECH4;
ECHO.ECH  = ECH;
CORR.COR1 = COR1; CORR.COR2 = COR2; CORR.COR3 = COR3; CORR.COR4 = COR4;
CORR.COR  = COR;
CORR.PG1  = PG1;  CORR.PG2  = PG2;  CORR.PG3  = PG3;  CORR.PG4  = PG4;

% --- Vertical beam ---
VB.EVALamp = EVALamp; VB.RSSIAmp = RSSIAmp;
VB.VRNG1 = VRNG1; VB.VRNG2 = VRNG2;
VB.VGAIN = VGAIN; VB.VFLAG = VFLAG;
if ~isempty(VWN)
    VB.VWN = VWN; VB.VWP = VWP; VB.VWS = VWS; VB.VWFd = VWFd;
    VB.VTL = VTL; VB.VLag = VLag; VB.VCodElements = VCodElements;
    VB.VV = VV; VB.VCOR = VCOR; VB.VECH = VECH; VB.BEDGOODECH = BEDGOODECH;
end

% --- Surface layer ---
if hasSurface
    SL.SWN = SWN; SL.SWS = SWS; SL.SWDistance = SWDistance;
    SL.SV1 = SV1; SL.SV2 = SV2; SL.SV3 = SV3; SL.SV4 = SV4;
    SL.SCOR1 = SCOR1; SL.SCOR2 = SCOR2; SL.SCOR3 = SCOR3; SL.SCOR4 = SCOR4;
    SL.SECH1 = SECH1; SL.SECH2 = SECH2; SL.SECH3 = SECH3; SL.SECH4 = SECH4;
    SL.SPG1  = SPG1;  SL.SPG2  = SPG2;  SL.SPG3  = SPG3;  SL.SPG4  = SPG4;
    SL.SVX1  = SVX1;  SL.SVX2  = SVX2;  SL.SVX3  = SVX3;  SL.SVX4  = SVX4;
    SL.SV1_B = SV1_B; SL.SV2_B = SV2_B; SL.SV3_B = SV3_B; SL.SV4_B = SV4_B;
    SL.SV_N  = SV_N;  SL.SV_E  = SV_E;  SL.SV_NEmod = SV_NEmod;
    SL.SDEGV = SDEGV;
else
    SL = NaN;
end

% --- Metadata / geometry ---
Data.PRO    = PRO;    Data.WF     = WF;     Data.WS   = WS;   Data.Pl   = Pl;
Data.DeltaT = DeltaT; Data.TIME   = TIME;   Data.TIM_m = TIM_m;
Data.Pitch  = EP;     Data.Roll   = ER;
Data.EA     = EA;     Data.EB     = EB;     Data.EZ   = EZ;
Data.WN     = WN;     Data.EH     = EH;     Data.WE   = WE;
Data.WP     = WP;     Data.TS     = TS;     Data.EX   = EX;
Data.R_EH   = R_EH;   Data.R      = R;      Data.M    = M;
Data.LagWater = LagWater;   Data.DataPings = DataPings;
Data.CodedWlementsWAterProfile = CodedWlementsWAterProfile;
Data.WT     = WT;     Data.SEZ    = SEZ;
Data.LowCorr = LowCorr; Data.XmitC = XmitC; Data.XmitV = XmitV;
Data.CoordModeFromEX = RAW.CoordModeFromEX;
Data.Ed     = Ed;     % transducer depth [m]
Data.filter_info = filter_info;   % all QC masks and thresholds

% --- GPS ---
GPSdata.Latd  = Latd;    GPSdata.Long  = Long;
GPSdata.Latd2 = Latd2;   GPSdata.Long2 = Long2;
GPSdata.Latd3 = Latd3;   GPSdata.Long3 = Long3;
GPSdata.Z_gga  = Z_gga;  GPSdata.Z_gga2 = Z_gga2; GPSdata.Z_gga3 = Z_gga3;
GPSdata.Tgps  = Tgps;    GPSdata.Tgps2  = Tgps2;  GPSdata.Tgps3  = Tgps3;
GPSdata.Latd_FILLED = Latd_FILLED;
GPSdata.Long_FILLED = Long_FILLED;
GPSdata.VTGH1 = VTGH1;   GPSdata.VTGV1 = VTGV1;
GPSdata.VTGH2 = VTGH2;   GPSdata.VTGV2 = VTGV2;
GPSdata.VTGH3 = VTGH3;   GPSdata.VTGV3 = VTGV3;
GPSdata.GPVfinal  = GPVfinal;
GPSdata.GPVXfinal = GPVXfinal;
GPSdata.GPVYfinal = GPVYfinal;
GPSdata.T_gpsNUM  = T_gpsNUM;
GPSdata.T_gpsNUM2 = T_gpsNUM2;
GPSdata.T_gpsNUM3 = T_gpsNUM3;
GPSdata.Msg_type  = Msg_type;
GPSdata.Msg_size  = Msg_size;

% =========================================================================
% 12. Save
% =========================================================================
if nargin >= 4 && ~isempty(savedir)
    [~,exp_num] = fileparts(name);
    fname = fullfile(savedir, [exp_num '.mat']);
    save(fname, 'Data','BT','v','CORR','ECHO','SL','VB','GPSdata','-mat');
    fprintf('Saved: %s\n', fname);
end

end % function processADCP_RDI


% =========================================================================
% Local helper: get field from opts struct with default fallback
% =========================================================================
function v = getopt(s, field, default)
    if isfield(s, field)
        v = s.(field);
    else
        v = default;
    end
end