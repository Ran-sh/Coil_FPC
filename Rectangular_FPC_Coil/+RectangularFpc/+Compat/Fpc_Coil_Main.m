function result = Fpc_Coil_Main(overrides)
%FPC_COIL_MAIN Deprecated compatibility wrapper.
warning('RectangularFPC:DeprecatedAPI', ...
    'RectangularFpc.Compat.Fpc_Coil_Main is deprecated. Use rectangular_fpc_main instead.');
if nargin < 1
    overrides = struct();
end
result = rectangular_fpc_main(overrides);
end
