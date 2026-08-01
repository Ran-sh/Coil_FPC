function cfg = fpc_coil_default_config(overrides)
%FPC_COIL_DEFAULT_CONFIG Return a complete, caller-overridable configuration.
%   CFG = FPC_COIL_DEFAULT_CONFIG() returns the production defaults.
%   CFG = FPC_COIL_DEFAULT_CONFIG(OVERRIDES) replaces matching fields (and
%   preserves forward-compatible additional fields) from a scalar struct.

if nargin < 1
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('FPC_Coil:InvalidOverrides', ...
        'overrides must be a scalar struct.');
end

cfg = struct();

% Winding and supported stack-up.
cfg.layerCount = 4;
cfg.maxLayerCount = 8;
cfg.useRecommendedTurns = true;
cfg.turnsPerLayer = 6;

% Board body and right-hand terminal tab (mm).
cfg.plateLength = 80.0;
cfg.plateWidth = 12.0;
cfg.plateCornerRadius = 3.0;
cfg.tabLength = 12.0;
cfg.tabWidth = 5.0;
cfg.tabOuterCornerRadius = 1.5;
cfg.tabTransitionRadius = 1.5;
cfg.tabEdgeMargin = 0.30;

% Copper geometry (mm).
cfg.traceWidth = 0.20;
cfg.traceSpacing = 0.15;
cfg.pitchMargin = 0.005;
cfg.edgeClearance = 0.50;
cfg.minInnerWidth = 2.00;
cfg.minSpiralCornerRadius = 0.80;

% Leads and external pads (mm).
cfg.leadYOffset = 1.30;
cfg.leadBendRadius = 1.20;
cfg.leadArcPointCount = 64;
cfg.padTipInset = 1.50;
cfg.padDiameter = 1.50;
cfg.padTipMargin = 0.20;
cfg.leadTabClearance = 0.50;
cfg.padToPadClearance = 0.15;
cfg.padToCopperClearance = 0.15;

% Inter-layer vias (mm).
cfg.viaDrillDiameter = 0.30;
cfg.viaPadDiameter = 0.60;
cfg.viaToCopperClearance = 0.15;
cfg.viaToBoardClearance = 0.30;
cfg.viaToViaClearance = 0.20;
cfg.viaToPadClearance = 0.20;
cfg.viaLandingLeadLength = 0.80;
cfg.viaLandingClearance = 0.15;
cfg.viaInnerBendRadius = 0.50;
cfg.viaOuterLandingLeadLength = 1.00;
cfg.viaOuterLandingClearance = 0.15;
cfg.viaOuterBendRadius = 0.30;
cfg.viaClearanceSeverity = 'warning';

% Last-layer output via and independent L1 return (mm). VOUT reuses the
% common drill/pad diameters and is a through via with inner-layer antipads.
cfg.outputViaType = 'through_via';
cfg.outputViaTipInset = 4.00;
cfg.outputViaAntiPadDiameter = 0.90;
cfg.outputViaToCopperClearance = 0.15;
cfg.outputViaToBoardClearance = 0.30;
cfg.outputReturnBendRadius = 0.30;

% Material and manufacturing assumptions.
cfg.copperThickness = 0.035;
cfg.copperResistivity = 1.724e-8;
cfg.minAnnularRing = 0.15;
cfg.manufacturingTolerance = 0.05;

% Geometry tolerances and discretization.
cfg.minCopperInteriorAngleDeg = 90.0;
cfg.minBoardInteriorAngleDeg = 90.0;
cfg.angleToleranceDeg = 0.1;
cfg.geometryTolerance = 1e-6;
cfg.connectionTolerance = 1e-5;
cfg.clearanceTolerance = 0.002;
cfg.crossProductTolerance = 1e-12;
cfg.parameterTolerance = 1e-9;
cfg.pointsPerTurn = 900;
cfg.minTurnPointCount = 500;
cfg.boardArcPointCount = 64;
cfg.maxVerticesPerDxfEntity = 220;
cfg.previewDpi = 220;
cfg.enablePreview = true;

% Validation switches.
cfg.enableExactSelfIntersectionCheck = true;
cfg.enableCopperClearanceCheck = true;
cfg.enableBoardAngleCheck = true;
cfg.enableCopperAngleCheck = true;
cfg.enablePadClearanceCheck = true;
cfg.enableViaClearanceCheck = true;
cfg.enableDxfReadbackCheck = true;

% Output.
cfg.outputRoot = fullfile(pwd, 'fpc_coil_output');
cfg.designName = 'fpc_coil_4layer';

names = fieldnames(overrides);
for k = 1:numel(names)
    cfg.(names{k}) = overrides.(names{k});
end

% Derive only values the caller did not explicitly supply.
if ~isfield(overrides, 'turnsPerLayer') && isfield(overrides, 'layerCount')
    cfg.turnsPerLayer = recommendedTurns(cfg.layerCount);
end
if ~isfield(overrides, 'designName') && isfield(overrides, 'layerCount')
    cfg.designName = sprintf('fpc_coil_%dlayer', cfg.layerCount);
end

end

function turns = recommendedTurns(layerCount)

if layerCount == 2
    turns = 10;
else
    % Six and more layers must ultimately be selected by a geometry scan;
    % six is a conservative starting value shared with the four-layer case.
    turns = 6;
end

end
