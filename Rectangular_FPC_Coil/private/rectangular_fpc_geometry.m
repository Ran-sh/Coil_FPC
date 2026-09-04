function varargout = rectangular_fpc_geometry(operation, varargin)
%RECTANGULAR_FPC_GEOMETRY Stable private geometry dispatcher.
%   Public private-surface operations are preserved while implementation
%   responsibilities live in focused geometry modules.

switch operation
    case {'turn_limits', 'spiral', 'derived_parameters', 'build_layers'}
        [varargout{1:nargout}] = rectangular_fpc_coil_geometry( ...
            operation, varargin{:});
    case {'plan_vias', 'auto_output_via'}
        [varargout{1:nargout}] = rectangular_fpc_via_planner( ...
            operation, varargin{:});
    case 'smooth_lead'
        [varargout{1:nargout}] = rectangular_fpc_lead_router( ...
            operation, varargin{:});
    case 'board_outline'
        [varargout{1:nargout}] = rectangular_fpc_board_geometry( ...
            operation, varargin{:});
    case {'normalize_layers', 'user_to_internal', 'internal_to_user', ...
            'remove_duplicates', 'remove_zero_length', ...
            'has_zero_length', 'path_length'}
        [varargout{1:nargout}] = rectangular_fpc_path_geometry( ...
            operation, varargin{:});
    otherwise
        error('RectangularFPC:UnknownGeometryOperation', ...
            'Unknown geometry operation: %s', operation);
end
end
