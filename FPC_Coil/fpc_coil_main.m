function result = fpc_coil_main(overrides)
%FPC_COIL_MAIN Generate an FPC coil from the public configuration API.
%   RESULT = FPC_COIL_MAIN() uses the documented defaults.
%   RESULT = FPC_COIL_MAIN(OVERRIDES) applies fields from a scalar struct.

if nargin < 1
    overrides = struct();
end

cfg = fpc_coil_default_config(overrides);
result = fpc_coil_engine(cfg);

% When cfg.enableFigure is true (default) and a MATLAB desktop is available,
% pop up the interactive figure viewer; headless runs (e.g. CI -batch) skip
% the popup automatically. The viewer is implemented in private/fpc_coil_plot.m
% and figures can be saved from the window menu.
if cfg.enableFigure && usejava('desktop')
    fpc_coil_plot(result);
end

end
