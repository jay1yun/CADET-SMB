function [opt, interstVelocity, Feed] = getParameters(varargin)
%   Case 2, a eight-column demonstration case

% =============================================================================
% This is the function to input all the necessary data for simulation
%
% Returns: 
%       1. opt stands for options, which involves the parameter settings
%       for the algorithm, the binding isotherm, and the model equations
%
%       2. interstVelocity is calculated from flowrate of each column and inlet. 
%       interstitial_velocity = flow_rate / (across_area * porosity_Column)
%
%       3. Feed initializes the injection concentration
% =============================================================================


%   The parameter setting for simulator
    opt.tolIter         = 1e-4;
    opt.nMaxIter        = 1000;
    opt.nThreads        = 8;
    opt.nCellsColumn    = 40;
    opt.nCellsParticle  = 1;
    opt.ABSTOL          = 1e-10;
    opt.INIT_STEP_SIZE  = 1e-14;
    opt.MAX_STEPS       = 5e6;

%   The parameter settting for the SMB 
    opt.switch          = 1552;
    opt.timePoints      = 1000;
    opt.Purity_extract_limit    = 0.99;
    opt.Purity_raffinate_limit  = 0.99;
    opt.Penalty_factor          = 10;

    opt.enableDebug = true;
    opt.nZone   = 4;    % 4-zone for binary separation, 5-zone for ternary separation
    opt.nColumn = 8;    % 4,8,12,16- column cases are available
%     opt.nColumn = 12;
%     opt.nColumn = 16;

%   Binding: Linear Binding isotherm
    opt.nComponents = 2;
    opt.KA = [0.28 0.54]; % [comp_A, comp_B], A for raffinate, B for extract
    opt.KD = [1, 1];
    opt.comp_raf_ID = 1;  % the target component withdrawn from the raffinate ports
    opt.comp_ext_ID = 2;  % the target component withdrawn from the extract ports

%   Transport
    opt.dispersionColumn          = 3.8148e-6;      % 
    opt.filmDiffusion             = [5e-5 5e-5];      % unknown 
    opt.diffusionParticle         = [1.6e4 1.6e4];  % unknown
    opt.diffusionParticleSurface  = [0.0 0.0];

%   Geometry
    opt.columnLength        = 53.6e-2;        % m
    opt.columnDiameter      = 2.60e-2;        % m
    opt.particleRadius      = 0.325e-2 /2;    % m
    opt.porosityColumn      = 0.38;
    opt.porosityParticle    = 0.00001;        % unknown

%   Parameter units transformation
%   The flow rate of Zone I was defined as the recycle flow rate
    crossArea = pi * (opt.columnDiameter/2)^2;        % m^2
    flowRate.recycle    = 0.1395e-6;      % m^3/s 
    flowRate.feed       = 0.02e-6  ;      % m^3/s
    flowRate.raffinate  = 0.0266e-6;      % m^3/s
    flowRate.desorbent  = 0.0414e-6;      % m^3/s
    flowRate.extract    = 0.0348e-6;      % m^3/s
    opt.flowRate_extract   = flowRate.extract;
    opt.flowRate_raffinate = flowRate.raffinate;

%   Interstitial velocity = flow_rate / (across_area * opt.porosityColumn)
    interstVelocity.recycle   = flowRate.recycle / (crossArea*opt.porosityColumn);      % m/s 
    interstVelocity.feed      = flowRate.feed / (crossArea*opt.porosityColumn);         % m/s
    interstVelocity.raffinate = flowRate.raffinate / (crossArea*opt.porosityColumn);    % m/s
    interstVelocity.desorbent = flowRate.desorbent / (crossArea*opt.porosityColumn);    % m/s
    interstVelocity.extract   = flowRate.extract / (crossArea*opt.porosityColumn);      % m/s

    concentrationFeed 	= [0.5, 0.5];   % g/m^3 [concentration_compA, concentration_compB]
    opt.molMass         = [180.16, 180.16];
    opt.yLim            = max(concentrationFeed ./ opt.molMass);

%   Feed concentration setup
    Feed.time = linspace(0, opt.switch, opt.timePoints);
    Feed.concentration = zeros(length(Feed.time), opt.nComponents);

    for i = 1:opt.nComponents
        Feed.concentration(1:end,i) = (concentrationFeed(i) / opt.molMass(i));
    end

end
% =============================================================================
%  SMB - The Simulated Moving Bed Chromatography for separation of
%  target compounds, either binary or ternary.
%  
%  Author: QiaoLe He   E-mail: q.he@fz-juelich.de
%                                      
%  Institute: Forschungszentrum Juelich GmbH, IBG-1, Juelich, Germany.
%  
%  All rights reserved. Please see the license of CADET.
% =============================================================================