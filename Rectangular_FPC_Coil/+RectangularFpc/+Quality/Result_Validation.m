function varargout = Result_Validation(operation, varargin)
%RESULT_VALIDATION Stable private validation dispatcher.

switch operation
    case 'config'
        [varargout{1:nargout}] = RectangularFpc.Pipeline.Validate_Config( ...
            operation, varargin{:});
    case 'candidate'
        [varargout{1:nargout}] = RectangularFpc.Pipeline.Validate_Candidate( ...
            operation, varargin{:});
    case 'design'
        [varargout{1:nargout}] = RectangularFpc.Quality.Design_Checks( ...
            operation, varargin{:});
    case 'route_candidate'
        [varargout{1:nargout}] = RectangularFpc.Geometry.Path_Geometry( ...
            'candidate_compliant', varargin{:});
    otherwise
        error('RectangularFPC:UnknownValidationOperation', ...
            'Unknown validation operation: %s', operation);
end
end
