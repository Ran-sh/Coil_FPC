function varargout = BoardAndCoil(operation, varargin)
%RECTANGULAR_FPC_GEOMETRY Stable private geometry dispatcher.
%   Public private-surface operations are preserved while implementation
%   responsibilities live in focused geometry modules.

switch operation
    case {'turn_limits', 'spiral', 'derived_parameters', 'build_layers'}
        [varargout{1:nargout}] = RectangularFpc.Geometry.CoilSpiral( ...
            operation, varargin{:});
    case {'plan_vias', 'auto_output_via'}
        [varargout{1:nargout}] = RectangularFpc.Geometry.ViaPlanner( ...
            operation, varargin{:});
    case 'smooth_lead'
        [varargout{1:nargout}] = RectangularFpc.Geometry.LeadRouter( ...
            operation, varargin{:});
    case 'board_outline'
        [varargout{1:nargout}] = RectangularFpc.Geometry.BoardOutline( ...
            operation, varargin{:});
    case {'normalize_layers', 'user_to_internal', 'internal_to_user', ...
            'remove_duplicates', 'remove_zero_length', ...
            'has_zero_length', 'path_length'}
        [varargout{1:nargout}] = RectangularFpc.Geometry.PathGeometry( ...
            operation, varargin{:});
    otherwise
        error('RectangularFPC:UnknownGeometryOperation', ...
            'Unknown geometry operation: %s', operation);
end
end
