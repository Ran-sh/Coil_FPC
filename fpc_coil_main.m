function result = fpc_coil_main(overrides)
%FPC_COIL_MAIN Generate an FPC coil from the public configuration API.
%   RESULT = FPC_COIL_MAIN() uses the documented defaults.
%   RESULT = FPC_COIL_MAIN(OVERRIDES) applies fields from a scalar struct.

if nargin < 1
    overrides = struct();
end

cfg = fpc_coil_default_config(overrides);
cfg = fpc_coil_validate_config(cfg);
result = fpc_coil_generate(cfg);

end
