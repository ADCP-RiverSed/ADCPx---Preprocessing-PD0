% =========================================================================
% padarray_row.m
% Pads (or trims) a row vector to a target length.
%   x        - input vector (any shape, will be forced to row)
%   n_target - desired output length
%   padval   - value to pad with (e.g. 0, NaN)
%
% If length(x) < n_target  → append (n_target-length(x)) padval elements
% If length(x) > n_target  → keep only first n_target elements
% If length(x) == n_target → unchanged
% =========================================================================
function x = padarray_row(x, n_target, padval)
    if isempty(x)
        x = repmat(padval, 1, n_target);
        return
    end
    x = x(:)';                          % force to row vector
    n = numel(x);
    if n < n_target
        x = [x, repmat(padval, 1, n_target - n)];
    elseif n > n_target
        x = x(1:n_target);
    end
end