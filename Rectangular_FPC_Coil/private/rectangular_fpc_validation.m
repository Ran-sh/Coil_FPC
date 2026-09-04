function varargout = rectangular_fpc_validation(operation, varargin)
%RECTANGULAR_FPC_VALIDATION Stable private validation dispatcher.

switch operation
    case 'config'
        [varargout{1:nargout}] = rectangular_fpc_config_validation( ...
            operation, varargin{:});
    case 'candidate'
        [varargout{1:nargout}] = rectangular_fpc_candidate_validation( ...
            operation, varargin{:});
    case 'design'
        [varargout{1:nargout}] = rectangular_fpc_design_checks( ...
            operation, varargin{:});
    case 'route_candidate'
        [varargout{1:nargout}] = rectangular_fpc_path_geometry( ...
            'candidate_compliant', varargin{:});
    otherwise
        error('RectangularFPC:UnknownValidationOperation', ...
            'Unknown validation operation: %s', operation);
end
end
