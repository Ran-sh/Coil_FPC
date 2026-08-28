function result = fpc_coil_main(overrides)
%FPC_COIL_MAIN Deprecated compatibility wrapper.
warning('RectangularFPC:DeprecatedAPI', ...
    'fpc_coil_main is deprecated. Use rectangular_fpc_main instead.');
if nargin < 1
    overrides = struct();
end
result = rectangular_fpc_main(overrides);
end
