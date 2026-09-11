function varargout = ResultValidation(operation, varargin)
%RECTANGULAR_FPC_VALIDATION Stable private validation dispatcher.

switch operation
    case 'config'
        [varargout{1:nargout}] = RectangularFpc.Pipeline.ValidateConfig( ...
            operation, varargin{:});
    case 'candidate'
        [varargout{1:nargout}] = RectangularFpc.Pipeline.ValidateCandidate( ...
            operation, varargin{:});
    case 'design'
        [varargout{1:nargout}] = RectangularFpc.Quality.DesignChecks( ...
            operation, varargin{:});
    case 'route_candidate'
        [varargout{1:nargout}] = RectangularFpc.Geometry.PathGeometry( ...
            'candidate_compliant', varargin{:});
    otherwise
        error('RectangularFPC:UnknownValidationOperation', ...
            'Unknown validation operation: %s', operation);
end
end
