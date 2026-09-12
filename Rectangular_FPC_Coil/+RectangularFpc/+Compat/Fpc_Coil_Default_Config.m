function cfg = Fpc_Coil_Default_Config(overrides)
%FPC_COIL_DEFAULT_CONFIG Deprecated compatibility wrapper.
warning('RectangularFPC:DeprecatedAPI', ...
    ['RectangularFpc.Compat.Fpc_Coil_Default_Config is deprecated. Use ', ...
     'rectangular_fpc_default_config instead.']);
if nargin < 1
    overrides = struct();
end
cfg = rectangular_fpc_default_config(overrides);
end
