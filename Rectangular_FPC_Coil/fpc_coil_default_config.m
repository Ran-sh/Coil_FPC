function cfg = fpc_coil_default_config(overrides)
%FPC_COIL_DEFAULT_CONFIG Deprecated compatibility wrapper.
warning('RectangularFPC:DeprecatedAPI', ...
    ['fpc_coil_default_config is deprecated. Use ', ...
     'rectangular_fpc_default_config instead.']);
if nargin < 1
    overrides = struct();
end
cfg = rectangular_fpc_default_config(overrides);
end
