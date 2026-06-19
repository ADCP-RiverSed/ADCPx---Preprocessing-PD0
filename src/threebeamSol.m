function [BTV1, BTV2, BTV3, BTV4, flag] = threebeamSol(BTV1, BTV2, BTV3, BTV4)
% THREEBEAMSOL  Three-beam bottom-track solution for RDI Janus ADCPs.
%
% When exactly one beam is invalid (NaN or zero), the missing beam velocity
% is reconstructed by assuming the error velocity = 0.
%
% For a standard RDI 4-beam Janus ADCP the error velocity constraint is:
%   Verr = (BTV1 - BTV2 + BTV3 - BTV4) / 4   [beam coordinates]
% Setting Verr = 0 gives the reconstruction equations:
%   If beam 1 missing:  BTV1 =  BTV2 - BTV3 + BTV4
%   If beam 2 missing:  BTV2 =  BTV1 + BTV4 - BTV3   (= BTV1 - BTV3 + BTV4)
%   If beam 3 missing:  BTV3 =  BTV1 - BTV2 + BTV4   ... wait, need pairs
%
% RDI beam pairing (opposing beams cancel horizontal motion):
%   Pair A: beams 1 & 2  (measure in fore-aft)
%   Pair B: beams 3 & 4  (measure in port-starboard)
%   Error velocity:  Verr ∝ (B1 + B2) - (B3 + B4)
%
% Setting Verr = 0:  B1 + B2 = B3 + B4
%   Missing B1 → B1 = B3 + B4 - B2
%   Missing B2 → B2 = B3 + B4 - B1
%   Missing B3 → B3 = B1 + B2 - B4
%   Missing B4 → B4 = B1 + B2 - B3
%
% Inputs / Outputs:
%   BTV1..BTV4  - BT beam velocities [m/s], 1×nens row vectors.
%                 NaN = invalid beam (caller must replace -32768 with NaN
%                 before calling; 0 is treated as a valid zero velocity).
%                 On output, reconstructed where one beam was NaN.
%   flag        - 1×nens cell array: '4-beam', '3-beam', 'bad'
%
% Reference: RDI Workhorse Commands and Output Data Format, Ch.6;
%            Mueller (2020) QRev technical manual.

nens = numel(BTV1);
flag = repmat({'4-beam'}, 1, nens);

% Do NOT convert 0→NaN here.  Zero is a valid velocity (stationary boat).
% The caller is responsible for replacing the -32768 bad sentinel with NaN
% before calling this function.

for i = 1:nens

    b = [BTV1(i), BTV2(i), BTV3(i), BTV4(i)];
    bad = isnan(b);
    nBad = sum(bad);

    if nBad == 0
        % All four beams valid — nothing to do
        flag{i} = '4-beam';

    elseif nBad == 1
        % Exactly one beam missing — reconstruct using Verr = 0
        % Constraint: B1 + B2 = B3 + B4

        switch find(bad)
            case 1   % beam 1 missing
                b(1) = b(3) + b(4) - b(2);
            case 2   % beam 2 missing
                b(2) = b(3) + b(4) - b(1);
            case 3   % beam 3 missing
                b(3) = b(1) + b(2) - b(4);
            case 4   % beam 4 missing
                b(4) = b(1) + b(2) - b(3);
        end

        BTV1(i) = b(1);  BTV2(i) = b(2);
        BTV3(i) = b(3);  BTV4(i) = b(4);
        flag{i} = '3-beam';

    else
        % Two or more beams missing — no valid BT solution
        BTV1(i) = NaN;  BTV2(i) = NaN;
        BTV3(i) = NaN;  BTV4(i) = NaN;
        flag{i} = 'bad';
    end

end
end