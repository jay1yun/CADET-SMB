
classdef SMB < handle
% =============================================================================
% This is the class of the functions of simulated moving bed.
%
% =============================================================================


    methods (Static = true, Access = 'public')


        function [outletProfile, lastState] = secColumn(inletProfile, params, lastState, ParSwarm)
% -----------------------------------------------------------------------------
% Simulation of the single column
%
% Parameters:
%       - inletProfile. Inlet time and corresponding concentration
%       - params. Get parameters for simulation
%       - lastState. The recorded last STATE from previous simulation
%       of next simulation
% 
% Returns:
%       - outletProfile. outlet time and corresponding concentration
%       - lastState. Record the last STATE which used as the initial state
% -----------------------------------------------------------------------------


            if nargin < 4
                ParSwarm = [];
                if nargin < 3
                    lastState = [];
                end
            end

            if isempty(params.initMobilCon) && isempty(params.initSolidCon) && isempty(lastState)
                warning('There are no Initial Conditions / Boundary Conditions for the Simulator');
            end

%           Get parameters
            [opt, ~, ~] = getParameters(ParSwarm);

            model = ModelGRM();
            model.nComponents = opt.nComponents;

%           if you want to change the equilibrium isotherm            
            if strcmp(opt.BindingModel, 'LinearBinding')

                model.kineticBindingModel = false;
                model.bindingModel = LinearBinding(); 

%               Adsorption parameters
                model.bindingParameters.LIN_KA   = opt.KA;
                model.bindingParameters.LIN_KD   = opt.KD;

            elseif strcmp(opt.BindingModel, 'MultiComponentLangmuirBinding')

                model.kineticBindingModel = true;
                model.bindingModel = MultiComponentLangmuirBinding();

                model.bindingParameters.MCL_KA   = opt.KA;
                model.bindingParameters.MCL_KD   = opt.KD;
                model.bindingParameters.MCL_QMAX = opt.QMAX;

            elseif strcmp(opt.BindingModel, 'MultiComponentBiLangmuirBinding')

                model.kineticBindingModel = true;
                model.bindingModel = MultiComponentBiLangmuirBinding();

                model.bindingParameters.MCL_KA1   = opt.KA(1);
                model.bindingParameters.MCL_KD1   = opt.KD(1);
                model.bindingParameters.MCL_QMAX1 = opt.QMAX(1);
                model.bindingParameters.MCL_KA2   = opt.KA(2);
                model.bindingParameters.MCL_KD2   = opt.KD(2);
                model.bindingParameters.MCL_QMAX2 = opt.QMAX(2);

            elseif strcmp(opt.BindingModel, 'StericMassAction')

                error('%s: it is not available yet.', opt.BindingModel);

            end

            if nargin >= 3 && ~isempty(lastState)
                model.initialState = lastState;
            else      
                model.initialMobileConcentration = params.initMobilCon;
                model.initialSolidConcentration  = params.initSolidCon;
            end

%           Transport
            model.dispersionColumn          = opt.dispersionColumn;
            model.filmDiffusion             = opt.filmDiffusion;
            model.diffusionParticle         = opt.diffusionParticle;
            model.diffusionParticleSurface  = opt.diffusionParticleSurface;
            model.interstitialVelocity      = params.interstitialVelocity;

%           Geometry
            model.columnLength        = opt.columnLength;
            model.particleRadius      = opt.particleRadius;
            model.porosityColumn      = opt.porosityColumn;
            model.porosityParticle    = opt.porosityParticle;

%           Apply the inlet profile to the CADET model
            Time = repmat({inletProfile.time}, 1, opt.nComponents);
            if opt.nComponents == 2
                Profile = [{inletProfile.concentration(:,1)}, {inletProfile.concentration(:,2)}];
            elseif opt.nComponents == 3
                Profile = [{inletProfile.concentration(:,1)}, {inletProfile.concentration(:,2)},...
                           {inletProfile.concentration(:,3)}];
            elseif opt.nComponents == 4
                Profile = [{inletProfile.concentration(:,1)}, {inletProfile.concentration(:,2)},...
                           {inletProfile.concentration(:,3)}, {inletProfile.concentration(:,4)}];
            end

            model.setInletsFromData(Time, Profile);

%           Turn off the warnings of the interpolation
            warning('off', 'MATLAB:interp1:ppGriddedInterpolant');
            warning('off', 'MATLAB:interp1:UsePCHIP');

%           Discretization
            disc = DiscretizationGRM();
            disc.nCellsColumn   = opt.nCellsColumn;
            disc.nCellsParticle = opt.nCellsParticle;

%           Solving options
            sim = Simulator(model, disc);
            sim.nThreads = opt.nThreads;
            sim.solutionTimes = inletProfile.time;
            sim.solverOptions.time_integrator.ABSTOL         = opt.ABSTOL;
            sim.solverOptions.time_integrator.INIT_STEP_SIZE = opt.INIT_STEP_SIZE;
            sim.solverOptions.time_integrator.MAX_STEPS      = opt.MAX_STEPS;
            sim.solverOptions.WRITE_SOLUTION_ALL    = false;
            sim.solverOptions.WRITE_SOLUTION_LAST   = true;
            sim.solverOptions.WRITE_SENS_LAST       = false;
            sim.solverOptions.WRITE_SOLUTION_COLUMN_OUTLET = true;
            sim.solverOptions.WRITE_SOLUTION_COLUMN_INLET  = true;


%           Run the simulation
            try
                result = sim.simulate();
            catch e
                % Something went wrong
                error('CADET:simulationFailed', 'Check your settings and try again.\n%s',e.message);
            end

%           Extract the outlet profile
            outletProfile.time = result.solution.time;
            outletProfile.concentration = result.solution.outlet(:,:);
            lastState =  result.solution.lastState;


        end % secColumn

        function column = massConservation(currentData, interstVelocity, Feed, opt, sequence, index)
% -----------------------------------------------------------------------------
% This is the function to calculate the concentration changes on each node.
%
%                                       FOUR-ZONE
%              4-column SMB                                       8-column SMB
% Extract                          Feed       |    Extract                           Feed
%       \                          /          |         \                            /
%        --------Zone II(b)--------           |          --------Zone II(c/d)--------
%        |                        |           |          |                          | 
% Zone I(a)                  Zone III(c)      |     Zone I(a/b)               Zone III(e/f)
%        |                        |           |          |                          | 
%        --------Zone IV(d)--------           |          --------Zone IV(h/g)--------
%       /                          \          |         /                            \
% Desorbent                       Raffinate   |   Desorbent                         Raffinate
%
%             12-column SMB                                       16-column SMB
% Extract                            Feed       |    Extract                         Feed
%       \                            /          |         \                          /
%        -- ----Zone II(d/e/f)-------           |          -----Zone II(e/f/g/h)-----
%        |                          |           |          |                        | 
% Zone I(c/b/a)                Zone III(g/h/i)  |  Zone I(a/b/c/d)           Zone III(i/j/k/l)
%        |                          |           |          |                        | 
%        -------Zone IV(l/k/j)-------           |          -----Zone IV(p/o/n/m)-----
%       /                            \          |         /                          \
% Desorbent                         Raffinate   |   Desorbent                       Raffinate
%
%                                       FIVE-ZONE
%              5-column SMB                                       10-column SMB
%    Ext2                          Feed       |      Ext2                            Feed
%       \                          /          |         \                            /
%        --------Zone II(c)--------           |          --------Zone III(e/f)--------
%        |                        |           |          |                           | 
% Zone II(b)                      |           |     Zone II(d/c)                     |
%        |                        |           |          |                           |
% Ext1 --                    Zone IV(d)       |   Ext1 --                        Zone IV(g/h)
%        |                        |           |          |                           |
% Zone I(a)                       |           |     Zone I(b/a)                      |
%        |                        |           |          |                           | 
%        --------Zone V(e)---------           |          ---------Zone V(j/i)---------
%       /                          \          |         /                            \
% Desorbent                       Raffinate   |   Desorbent                         Raffinate
%
%             15-column SMB                                       20-column SMB
%    Ext2                            Feed       |      Ext2                              Feed
%       \                            /          |         \                              /
%        -------Zone II(g/h/i)-------           |          -------Zone III(i/g/k/l)-------
%        |                          |           |          |                             | 
% Zone II(f/e/d)                    |           | Zone II(h/g/f/e)                       |
%        |                          |           |          |                             |
% Ext1 --                    Zone IV(j/k/l)     |   Ext1 --                        Zone IV(m/n/o/p)
%        |                          |           |          |                             |
% Zone I(c/b/a)                     |           | Zone I(d/c/b/a)                        |
%        |                          |           |          |                             | 
%        -------Zone V(o/n/m)--------           |          -------Zone V(t/s/r/q)---------
%       /                            \          |         /                              \
% Desorbent                         Raffinate   |   Desorbent                           Raffinate
%
% Fluid goes from Zone I to Zone II to Zone III, while the switch direction
% is from Zone I to Zone IV to Zone III;
%
% Parameters:
%       - currentData. Which includes each column's outlet concentration
%       (time-dependent), and the last state (which records every component's concentration 
%        in bulk phase and stationary phase, and used as the initial state for the next simulation).
%       - interstVelocity. The interstitial velocity of each column
%       - Feed. The initialied injection 
%       - opt. Options
%       - sequence. During switching, the structure used for storing the
%       sequence of columns
%       - index. It is a character. It tell this subroutine to calculate the specified column 
% 
% Returns: column
%   Preparation for next column simulation
%       - column.inlet. The new inlet concentration of each column, which is
%       obtained from mass conservation on each node.
%       - column.lastState. 
%       - column.params. Set the initial Mobile and Solid concentration to the
%       Simulator (if there is no lastState given), and also store the
%       interstitial velocity.
% -----------------------------------------------------------------------------


%           Time points
            column.inlet.time = linspace(0, opt.switch, opt.timePoints);

%           Get the interstitial velocity of each columns and initial condition
            params = SMB.getParams(sequence, interstVelocity, opt);

            if opt.nZone == 4

                if opt.nColumn == 4

                    switch index

%                       The calculation of the column in the Zone I
%                       node DESORBENT (index a)
                        case 'a' 

                            column.params = params{sequence.a};

                            %   C_a^in = Q_d * C_d^out / Q_a
                            concentration = zeros(length(Feed.time), opt.nComponents);

                            column.inlet.concentration = concentration .* params{sequence.d}.interstitialVelocity...
                                ./ params{sequence.a}.interstitialVelocity; 


%                       The calculation of the column in the Zone II
%                       node EXTRACT (index b)
                        case 'b'

                            column.params = params{sequence.b};

                            %   C_b^in = C_a^out
                            column.inlet.concentration = currentData{sequence.a}.outlet.concentration;


%                       The calculation of the column in the Zone III
%                       node FEED (index c)
                        case 'c' 
                            column.params = params{sequence.c};

                            %   C_c^in = (Q_b * C_b^out + Q_F * C_F) / Q_c
                            column.inlet.concentration = (currentData{sequence.b}.outlet.concentration .* ...
                                params{sequence.b}.interstitialVelocity + Feed.concentration .* interstVelocity.feed) ...
                                ./ params{sequence.c}.interstitialVelocity; 


%                       The calculation of the column in the Zone IV
%                       node RAFFINATE (index d)
                        case 'd' 

                            column.params = params{sequence.d};

                            %   C_d^in = C_c^out
                            column.inlet.concentration = currentData{sequence.c}.outlet.concentration;
                    end


%     ------------------------------------------------------------------------------------    
                elseif opt.nColumn == 8

                    switch index

%                       The calculation of the column in the Zone I
%                       node DESORBENT (index a)
                        case 'a'  

                            column.params = params{sequence.a};

                            %   C_a^in = Q_h * C_h^out / Q_a
                            concentration = zeros(length(Feed.time), opt.nComponents);

                            column.inlet.concentration = concentration .* params{sequence.h}.interstitialVelocity...
                                ./ params{sequence.a}.interstitialVelocity;


%                       node DESORBENT (index b)
                        case 'b'  

                            column.params = params{sequence.b};

                            %   C_b^in = C_a^out
                            column.inlet.concentration = currentData{sequence.a}.outlet.concentration;


%                       The calculation of the column in the Zone II  
%                       node EXTRACT (index c)
                        case 'c'  

                            column.params = params{sequence.c};

                            %   C_c^in = C_b^out
                            column.inlet.concentration = currentData{sequence.b}.outlet.concentration;


%                       node EXTRACT (index d)
                        case 'd'  

                            column.params = params{sequence.d};

                            %   C_d^in = C_c^out
                            column.inlet.concentration = currentData{sequence.c}.outlet.concentration;


%                       The calculation of the column in the Zone III
%                       node FEED (index e)
                        case 'e' 

                            column.params = params{sequence.e};

                            %   C_e^in = (Q_d * C_d^out + Q_F * C_F) / Q_e
                            column.inlet.concentration = (currentData{sequence.d}.outlet.concentration .* ...
                            params{sequence.d}.interstitialVelocity + Feed.concentration .* interstVelocity.feed) ...
                            ./ params{sequence.e}.interstitialVelocity;


%                       node FEED (index f)
                        case 'f' 

                            column.params = params{sequence.f};

                            %   C_f^in = C_e^out
                            column.inlet.concentration = currentData{sequence.e}.outlet.concentration;


%                       The calculation of the column in the Zone IV 
%                       node RAFFINATE (index g)
                        case 'g'  

                            column.params = params{sequence.g};

                            %   C_g^in = C_f^out
                            column.inlet.concentration = currentData{sequence.f}.outlet.concentration;


%                       node RAFFINATE (index h)
                        case 'h' 

                            column.params = params{sequence.h};

                            %   C_h^in = C_g^out
                            column.inlet.concentration = currentData{sequence.g}.outlet.concentration;

                    end

%     ------------------------------------------------------------------------------------    
                elseif opt.nColumn == 12

                    switch index

%                       The calculation of the column in the Zone I
%                       node DESORBENT (index a)
                        case 'a'  

                            column.params = params{sequence.a};

                            %   C_a^in = Q_l * C_l^out / Q_a
                            concentration = zeros(length(Feed.time), opt.nComponents);

                            column.inlet.concentration = concentration .* params{sequence.l}.interstitialVelocity...
                                ./ params{sequence.a}.interstitialVelocity;


%                       node DESORBENT (index b)
                        case 'b'  

                            column.params = params{sequence.b};

                            %   C_b^in = C_a^out
                            column.inlet.concentration = currentData{sequence.a}.outlet.concentration;


%                       node DESORBENT (index c)
                        case 'c'  

                            column.params = params{sequence.c};

                            %   C_c^in = C_b^out
                            column.inlet.concentration = currentData{sequence.b}.outlet.concentration;


%                      The calculation of the column in the Zone II  
%                      node EXTRACT (index d)
                        case 'd'  

                            column.params = params{sequence.d};

                            %   C_d^in = C_c^out
                            column.inlet.concentration = currentData{sequence.c}.outlet.concentration;


%                       node EXTRACT (index e)
                        case 'e'  

                            column.params = params{sequence.e};

                            %   C_e^in = C_d^out
                            column.inlet.concentration = currentData{sequence.d}.outlet.concentration;


%                       node EXTRACT (index f)
                        case 'f'  

                            column.params = params{sequence.f};

                            %   C_f^in = C_e^out
                            column.inlet.concentration = currentData{sequence.e}.outlet.concentration;


%                       The calculation of the column in the Zone III
%                       node FEED (index g)
                        case 'g' 

                            column.params = params{sequence.g};

                            %   C_g^in = (Q_f * C_f^out + Q_F * C_F) / Q_g
                            column.inlet.concentration = (currentData{sequence.f}.outlet.concentration .* ...
                            params{sequence.f}.interstitialVelocity + Feed.concentration .* interstVelocity.feed) ...
                            ./ params{sequence.g}.interstitialVelocity;


%                       node FEED (index h)
                        case 'h' 

                            column.params = params{sequence.h};

                            %   C_h^in = C_g^out
                            column.inlet.concentration = currentData{sequence.g}.outlet.concentration;


%                       node FEED (index i)
                        case 'i' 

                            column.params = params{sequence.i};

                            %   C_i^in = C_h^out
                            column.inlet.concentration = currentData{sequence.h}.outlet.concentration;


%                       The calculation of the column in the Zone IV 
%                       node RAFFINATE (index j)
                        case 'j'  

                            column.params = params{sequence.j};

                            %   C_j^in = C_i^out
                            column.inlet.concentration = currentData{sequence.i}.outlet.concentration;


%                       node RAFFINATE (index k)
                        case 'k' 

                            column.params = params{sequence.k};

                            %   C_k^in = C_j^out
                            column.inlet.concentration = currentData{sequence.j}.outlet.concentration;


%                       node RAFFINATE (index l)
                        case 'l' 

                            column.params = params{sequence.l};

                            %   C_l^in = C_k^out
                            column.inlet.concentration = currentData{sequence.k}.outlet.concentration;

                    end

%     ------------------------------------------------------------------------------------    
                elseif opt.nColumn == 16

                    switch index

%                       The calculation of the column in the Zone I
%                       node DESORBENT (index a)
                        case 'a'  

                            column.params = params{sequence.a};

                            %   C_a^in = Q_p * C_p^out / Q_a
                            concentration = zeros(length(Feed.time), opt.nComponents);

                            column.inlet.concentration = concentration .* params{sequence.p}.interstitialVelocity...
                                ./ params{sequence.a}.interstitialVelocity;


%                       node DESORBENT (index b)
                        case 'b'  

                            column.params = params{sequence.b};

                            %   C_b^in = C_a^out
                            column.inlet.concentration = currentData{sequence.a}.outlet.concentration;


%                       node DESORBENT (index c)
                        case 'c'  

                            column.params = params{sequence.c};

                            %   C_c^in = C_b^out
                            column.inlet.concentration = currentData{sequence.b}.outlet.concentration;


%                       node DESORBENT (index d)
                        case 'd'  

                            column.params = params{sequence.d};

                            %   C_d^in = C_c^out
                            column.inlet.concentration = currentData{sequence.c}.outlet.concentration;


%                       The calculation of the column in the Zone II  
%                       node EXTRACT (index e)
                        case 'e'  

                            column.params = params{sequence.e};

                            %   C_e^in = C_d^out
                            column.inlet.concentration = currentData{sequence.d}.outlet.concentration;


%                       node EXTRACT (index f)
                        case 'f'  

                            column.params = params{sequence.f};

                            %   C_f^in = C_e^out
                            column.inlet.concentration = currentData{sequence.e}.outlet.concentration;


%                       node EXTRACT (index g)
                        case 'g'  

                            column.params = params{sequence.g};

                            %   C_g^in = C_f^out
                            column.inlet.concentration = currentData{sequence.f}.outlet.concentration;


%                       node EXTRACT (index h)
                        case 'h'  

                            column.params = params{sequence.h};

                            %   C_h^in = C_g^out
                            column.inlet.concentration = currentData{sequence.g}.outlet.concentration;


%                       The calculation of the column in the Zone III
%                       node FEED (index i)
                        case 'i' 

                            column.params = params{sequence.i};

                            %   C_i^in = (Q_h * C_h^out + Q_F * C_F) / Q_i
                            column.inlet.concentration = (currentData{sequence.h}.outlet.concentration .* ...
                            params{sequence.h}.interstitialVelocity + Feed.concentration .* interstVelocity.feed) ...
                            ./ params{sequence.i}.interstitialVelocity;


%                       node FEED (index j)
                        case 'j' 

                            column.params = params{sequence.j};

                            %   C_j^in = C_i^out
                            column.inlet.concentration = currentData{sequence.i}.outlet.concentration;


%                       node FEED (index k)
                        case 'k' 

                            column.params = params{sequence.k};

                            %   C_k^in = C_j^out
                            column.inlet.concentration = currentData{sequence.j}.outlet.concentration;


%                       node FEED (index l)
                        case 'l' 

                            column.params = params{sequence.l};

                            %   C_l^in = C_k^out
                            column.inlet.concentration = currentData{sequence.k}.outlet.concentration;


%                       The calculation of the column in the Zone IV 
%                       node RAFFINATE (index m)
                        case 'm'  

                            column.params = params{sequence.m};

                            %   C_m^in = C_l^out
                            column.inlet.concentration = currentData{sequence.l}.outlet.concentration;


%                       node RAFFINATE (index n)
                        case 'n' 

                            column.params = params{sequence.n};

                            %   C_n^in = C_m^out
                            column.inlet.concentration = currentData{sequence.m}.outlet.concentration;


%                       node RAFFINATE (index o)
                        case 'o' 

                            column.params = params{sequence.o};

                            %   C_o^in = C_n^out
                            column.inlet.concentration = currentData{sequence.n}.outlet.concentration;


%                       node RAFFINATE (index p)
                        case 'p' 

                            column.params = params{sequence.p};

                            %   C_p^in = C_o^out
                            column.inlet.concentration = currentData{sequence.o}.outlet.concentration;

                    end

                end


%     ***********************************************************************************
            elseif opt.nZone == 5

                if opt.nColumn == 5

                    switch index

%                       The calculation of the column in the Zone I
%                       node DESORBENT (index a)
                        case 'a' 

                            column.params = params{sequence.a};

                            %   C_a^in = Q_e * C_e^out / Q_a
                            concentration = zeros(length(Feed.time), opt.nComponents);

                            column.inlet.concentration = concentration .* params{sequence.e}.interstitialVelocity...
                                ./ params{sequence.a}.interstitialVelocity; 


%                       The calculation of the column in the Zone II
%                       node EXTRACT1 (index b)
                        case 'b'

                            column.params = params{sequence.b};

                            %   C_b^in = C_a^out
                            column.inlet.concentration = currentData{sequence.a}.outlet.concentration;


                            
%                       The calculation of the column in the Zone III
%                       node EXTRACT2 (index c)
                        case 'c'

                            column.params = params{sequence.c};

                            %   C_c^in = C_b^out
                            column.inlet.concentration = currentData{sequence.b}.outlet.concentration;
                            
                            
%                       The calculation of the column in the Zone IV
%                       node FEED (index d)
                        case 'd' 
                            column.params = params{sequence.d};

                            %   C_d^in = (Q_c * C_c^out + Q_F * C_F) / Q_d
                            column.inlet.concentration = (currentData{sequence.c}.outlet.concentration .* ...
                                params{sequence.c}.interstitialVelocity + Feed.concentration .* interstVelocity.feed) ...
                                ./ params{sequence.d}.interstitialVelocity; 


%                       The calculation of the column in the Zone V
%                       node RAFFINATE (index e)
                        case 'e' 

                            column.params = params{sequence.e};

                            %   C_e^in = C_d^out
                            column.inlet.concentration = currentData{sequence.d}.outlet.concentration;
                    end

%     ------------------------------------------------------------------------------------
                elseif opt.nColumn == 10

                    switch index

%                       The calculation of the column in the Zone I
%                       node DESORBENT (index a)
                        case 'a'  

                            column.params = params{sequence.a};

                            %   C_a^in = Q_j * C_j^out / Q_a
                            concentration = zeros(length(Feed.time), opt.nComponents);

                            column.inlet.concentration = concentration .* params{sequence.j}.interstitialVelocity...
                                ./ params{sequence.a}.interstitialVelocity;


%                       node DESORBENT (index b)
                        case 'b'  

                            column.params = params{sequence.b};

                            %   C_b^in = C_a^out
                            column.inlet.concentration = currentData{sequence.a}.outlet.concentration;

                            
%                       The calculation of the column in the Zone II
%                       node EXTRACT_1 (index c)
                        case 'c'  

                            column.params = params{sequence.c};

                            %   C_c^in = C_b^out
                            column.inlet.concentration = currentData{sequence.b}.outlet.concentration;


%                       node EXTRACT_1 (index d)
                        case 'd'  

                            column.params = params{sequence.d};

                            %   C_d^in = C_c^out
                            column.inlet.concentration = currentData{sequence.c}.outlet.concentration;
                            
                            
%                       The calculation of the column in the Zone III  
%                       node EXTRACT_2 (index e)
                        case 'e'  

                            column.params = params{sequence.e};

                            %   C_e^in = C_d^out
                            column.inlet.concentration = currentData{sequence.d}.outlet.concentration;


%                       node EXTRACT_2 (index f)
                        case 'f'  

                            column.params = params{sequence.f};

                            %   C_f^in = C_e^out
                            column.inlet.concentration = currentData{sequence.e}.outlet.concentration;


%                       The calculation of the column in the Zone III
%                       node FEED (index g)
                        case 'g' 

                            column.params = params{sequence.g};

                            %   C_g^in = (Q_f * C_f^out + Q_F * C_F) / Q_g
                            column.inlet.concentration = (currentData{sequence.f}.outlet.concentration .* ...
                            params{sequence.f}.interstitialVelocity + Feed.concentration .* interstVelocity.feed) ...
                            ./ params{sequence.g}.interstitialVelocity;


%                       node FEED (index h)
                        case 'h' 

                            column.params = params{sequence.h};

                            %   C_h^in = C_g^out
                            column.inlet.concentration = currentData{sequence.g}.outlet.concentration;


%                       The calculation of the column in the Zone V 
%                       node RAFFINATE (index i)
                        case 'i'  

                            column.params = params{sequence.i};

                            %   C_i^in = C_h^out
                            column.inlet.concentration = currentData{sequence.h}.outlet.concentration;


%                       node RAFFINATE (index j)
                        case 'j' 

                            column.params = params{sequence.j};

                            %   C_j^in = C_i^out
                            column.inlet.concentration = currentData{sequence.i}.outlet.concentration;

                    end


%     ------------------------------------------------------------------------------------
                elseif opt.nColumn == 15

                    switch index

%                       The calculation of the column in the Zone I
%                       node DESORBENT (index a)
                        case 'a'  

                            column.params = params{sequence.a};

                            %   C_a^in = Q_o * C_o^out / Q_a
                            concentration = zeros(length(Feed.time), opt.nComponents);

                            column.inlet.concentration = concentration .* params{sequence.o}.interstitialVelocity...
                                ./ params{sequence.a}.interstitialVelocity;


%                       node DESORBENT (index b)
                        case 'b'  

                            column.params = params{sequence.b};

                            %   C_b^in = C_a^out
                            column.inlet.concentration = currentData{sequence.a}.outlet.concentration;

 
%                       node DESORBENT (index c)
                        case 'c'  

                            column.params = params{sequence.c};

                            %   C_c^in = C_b^out
                            column.inlet.concentration = currentData{sequence.b}.outlet.concentration;


%                       The calculation of the column in the Zone II
%                       node EXTRACT_1 (index d)
                        case 'd'

                            column.params = params{sequence.d};

                            %   C_d^in = C_c^out
                            column.inlet.concentration = currentData{sequence.c}.outlet.concentration;


%                       node EXTRACT_1 (index e)
                        case 'e'  

                            column.params = params{sequence.e};

                            %   C_e^in = C_d^out
                            column.inlet.concentration = currentData{sequence.d}.outlet.concentration;


%                       node EXTRACT_1 (index f)
                        case 'f'  

                            column.params = params{sequence.f};

                            %   C_f^in = C_e^out
                            column.inlet.concentration = currentData{sequence.e}.outlet.concentration;


%                       The calculation of the column in the Zone III  
%                       node EXTRACT_2 (index g)
                        case 'g'  

                            column.params = params{sequence.g};

                            %   C_g^in = C_f^out
                            column.inlet.concentration = currentData{sequence.f}.outlet.concentration;


%                       node EXTRACT_2 (index h)
                        case 'h'  

                            column.params = params{sequence.h};

                            %   C_h^in = C_g^out
                            column.inlet.concentration = currentData{sequence.g}.outlet.concentration;


%                       node EXTRACT_2 (index i)
                        case 'i'  

                            column.params = params{sequence.i};

                            %   C_i^in = C_h^out
                            column.inlet.concentration = currentData{sequence.h}.outlet.concentration;


%                       The calculation of the column in the Zone III
%                       node FEED (index j)
                        case 'j' 

                            column.params = params{sequence.j};

                            %   C_j^in = (Q_i * C_i^out + Q_F * C_F) / Q_j
                            column.inlet.concentration = (currentData{sequence.i}.outlet.concentration .* ...
                            params{sequence.i}.interstitialVelocity + Feed.concentration .* interstVelocity.feed) ...
                            ./ params{sequence.j}.interstitialVelocity;


%                       node FEED (index k)
                        case 'k' 

                            column.params = params{sequence.k};

                            %   C_k^in = C_j^out
                            column.inlet.concentration = currentData{sequence.j}.outlet.concentration;


%                       node FEED (index l)
                        case 'l' 

                            column.params = params{sequence.l};

                            %   C_l^in = C_k^out
                            column.inlet.concentration = currentData{sequence.k}.outlet.concentration;


%                       The calculation of the column in the Zone V 
%                       node RAFFINATE (index m)
                        case 'm'  

                            column.params = params{sequence.m};

                            %   C_m^in = C_l^out
                            column.inlet.concentration = currentData{sequence.l}.outlet.concentration;


%                       node RAFFINATE (index n)
                        case 'n' 

                            column.params = params{sequence.n};

                            %   C_n^in = C_m^out
                            column.inlet.concentration = currentData{sequence.m}.outlet.concentration;


%                       node RAFFINATE (index o)
                        case 'o' 

                            column.params = params{sequence.o};

                            %   C_o^in = C_n^out
                            column.inlet.concentration = currentData{sequence.n}.outlet.concentration;

                    end


%     ------------------------------------------------------------------------------------
                elseif opt.nColumn == 20

                    switch index

%                       The calculation of the column in the Zone I
%                       node DESORBENT (index a)
                        case 'a'  

                            column.params = params{sequence.a};

                            %   C_a^in = Q_t * C_t^out / Q_a
                            concentration = zeros(length(Feed.time), opt.nComponents);

                            column.inlet.concentration = concentration .* params{sequence.t}.interstitialVelocity...
                                ./ params{sequence.a}.interstitialVelocity;


%                       node DESORBENT (index b)
                        case 'b'  

                            column.params = params{sequence.b};

                            %   C_b^in = C_a^out
                            column.inlet.concentration = currentData{sequence.a}.outlet.concentration;


%                       node DESORBENT (index c)
                        case 'c'  

                            column.params = params{sequence.c};

                            %   C_c^in = C_b^out
                            column.inlet.concentration = currentData{sequence.b}.outlet.concentration;
                            
                            
%                       node DESORBENT (index d)
                        case 'd'  

                            column.params = params{sequence.d};

                            %   C_d^in = C_c^out
                            column.inlet.concentration = currentData{sequence.c}.outlet.concentration;


%                       The calculation of the column in the Zone II
%                       node EXTRACT_1 (index e)
                        case 'e'  

                            column.params = params{sequence.e};

                            %   C_e^in = C_d^out
                            column.inlet.concentration = currentData{sequence.d}.outlet.concentration;


%                       node EXTRACT_1 (index f)
                        case 'f'  

                            column.params = params{sequence.f};

                            %   C_f^in = C_e^out
                            column.inlet.concentration = currentData{sequence.e}.outlet.concentration;


%                       node EXTRACT_1 (index g)
                        case 'g'  

                            column.params = params{sequence.g};

                            %   C_g^in = C_f^out
                            column.inlet.concentration = currentData{sequence.f}.outlet.concentration;


%                       node EXTRACT_1 (index h)
                        case 'h'  

                            column.params = params{sequence.h};

                            %   C_h^in = C_g^out
                            column.inlet.concentration = currentData{sequence.g}.outlet.concentration;


%                       The calculation of the column in the Zone III  
%                       node EXTRACT_2 (index i)
                        case 'i'  

                            column.params = params{sequence.i};

                            %   C_i^in = C_h^out
                            column.inlet.concentration = currentData{sequence.h}.outlet.concentration;


%                       node EXTRACT_2 (index j)
                        case 'j'  

                            column.params = params{sequence.j};

                            %   C_j^in = C_i^out
                            column.inlet.concentration = currentData{sequence.i}.outlet.concentration;


%                       node EXTRACT_2 (index k)
                        case 'k'  

                            column.params = params{sequence.k};

                            %   C_k^in = C_j^out
                            column.inlet.concentration = currentData{sequence.j}.outlet.concentration;

%                       node EXTRACT_2 (index l)
                        case 'l'  

                            column.params = params{sequence.l};

                            %   C_l^in = C_k^out
                            column.inlet.concentration = currentData{sequence.k}.outlet.concentration;


%                       The calculation of the column in the Zone III
%                       node FEED (index m)
                        case 'm' 

                            column.params = params{sequence.m};

                            %   C_m^in = (Q_l * C_l^out + Q_F * C_F) / Q_m
                            column.inlet.concentration = (currentData{sequence.l}.outlet.concentration .* ...
                            params{sequence.l}.interstitialVelocity + Feed.concentration .* interstVelocity.feed) ...
                            ./ params{sequence.m}.interstitialVelocity;


%                       node FEED (index n)
                        case 'n' 

                            column.params = params{sequence.n};

                            %   C_n^in = C_m^out
                            column.inlet.concentration = currentData{sequence.m}.outlet.concentration;


%                       node FEED (index o)
                        case 'o' 

                            column.params = params{sequence.o};

                            %   C_o^in = C_n^out
                            column.inlet.concentration = currentData{sequence.n}.outlet.concentration;


%                       node FEED (index p)
                        case 'p' 

                            column.params = params{sequence.p};

                            %   C_p^in = C_o^out
                            column.inlet.concentration = currentData{sequence.o}.outlet.concentration;


%                       The calculation of the column in the Zone V 
%                       node RAFFINATE (index q)
                        case 'q'  

                            column.params = params{sequence.q};

                            %   C_q^in = C_p^out
                            column.inlet.concentration = currentData{sequence.p}.outlet.concentration;


%                       node RAFFINATE (index r)
                        case 'r' 

                            column.params = params{sequence.r};

                            %   C_r^in = C_q^out
                            column.inlet.concentration = currentData{sequence.q}.outlet.concentration;


%                       node RAFFINATE (index s)
                        case 's' 

                            column.params = params{sequence.s};

                            %   C_s^in = C_r^out
                            column.inlet.concentration = currentData{sequence.r}.outlet.concentration;


%                       node RAFFINATE (index t)
                        case 't' 

                            column.params = params{sequence.t};

                            %   C_t^in = C_s^out
                            column.inlet.concentration = currentData{sequence.s}.outlet.concentration;

                    end

                end



            end

        end % massConservation

        function params = getParams(sequence, interstVelocity, opt)
%-----------------------------------------------------------------------------------------
% After each swtiching, the value of velocities and initial conditions are
% changed 
%-----------------------------------------------------------------------------------------


            global string;

            params = cell(1, opt.nColumn);
            for k = 1:opt.nColumn
                params{k} = struct('initMobilCon', [], 'initSolidCon', [], 'interstitialVelocity', []);
            end

            for j = 1:opt.nColumn
%               set the initial conditions to the solver, but when lastState is used, this setup will be ignored 
                params{eval(['sequence' '.' string(j)])}.initMobilCon = zeros(1,opt.nComponents);
                params{eval(['sequence' '.' string(j)])}.initSolidCon = zeros(1,opt.nComponents);
            end

            if opt.nZone == 4

                if opt.nColumn == 4

                    for i = 1: opt.nColumn
%                       Interstitial velocity of each ZONE
                        if strcmp('a', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle;
                        elseif strcmp('b', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract;
                        elseif strcmp('c', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract + interstVelocity.feed;
                        elseif strcmp('d', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent;
                        end
                    end

                elseif opt.nColumn == 8

                    for i = 1: opt.nColumn
%                       Interstitial velocity of each ZONE
                        if strcmp('a', string(i)) || strcmp('b', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle;
                        elseif strcmp('c', string(i)) || strcmp('d', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract;
                        elseif strcmp('e', string(i)) || strcmp('f', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract + interstVelocity.feed;
                        elseif strcmp('g', string(i)) || strcmp('h', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent;
                        end
                    end

                elseif opt.nColumn == 12

                    for i = 1: opt.nColumn
%                       Interstitial velocity of each ZONE
                        if strcmp('a', string(i)) || strcmp('b', string(i)) || strcmp('c', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle;
                        elseif strcmp('d', string(i)) || strcmp('e', string(i)) || strcmp('f', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract;
                        elseif strcmp('g', string(i)) || strcmp('h', string(i)) || strcmp('i', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract + interstVelocity.feed;
                        elseif strcmp('j', string(i)) || strcmp('k', string(i)) || strcmp('l', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent;
                        end
                    end

                elseif opt.nColumn == 16

                    for i = 1: opt.nColumn
%                       Interstitial velocity of each ZONE
                        if strcmp('a', string(i)) || strcmp('b', string(i)) || strcmp('c', string(i)) || strcmp('d', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle;
                        elseif strcmp('e', string(i)) || strcmp('f', string(i)) || strcmp('g', string(i)) || strcmp('h', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract;
                        elseif strcmp('i', string(i)) || strcmp('j', string(i)) || strcmp('k', string(i)) || strcmp('l', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract + interstVelocity.feed;
                        elseif strcmp('m', string(i)) || strcmp('n', string(i)) || strcmp('o', string(i)) || strcmp('p', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent;
                        end
                    end

                end

%  ----------------------------------------------------------------------------
            elseif opt.nZone == 5

                if opt.nColumn == 5

                    for i = 1: opt.nColumn
%                       Interstitial velocity of each ZONE
                        if strcmp('a', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle;
                        elseif strcmp('b', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract1;
                        elseif strcmp('c', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract1 - interstVelocity.extract2;
                        elseif strcmp('d', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent + interstVelocity.raffinate;
                        elseif strcmp('e', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent;
                        end
                    end

                elseif opt.nColumn == 10

                    for i = 1: opt.nColumn
%                       Interstitial velocity of each ZONE
                        if strcmp('a', string(i)) || strcmp('b', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle;
                        elseif strcmp('c', string(i)) || strcmp('d', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract1;
                        elseif strcmp('e', string(i)) || strcmp('f', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract1 - interstVelocity.extract2;
                        elseif strcmp('g', string(i)) || strcmp('h', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent + interstVelocity.raffinate;
                        elseif strcmp('i', string(i)) || strcmp('j', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent;
                        end
                    end

                elseif opt.nColumn == 15

                    for i = 1: opt.nColumn
%                       Interstitial velocity of each ZONE
                        if strcmp('a', string(i)) || strcmp('b', string(i)) || strcmp('c', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle;
                        elseif strcmp('d', string(i)) || strcmp('e', string(i)) || strcmp('f', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract1;
                        elseif strcmp('g', string(i)) || strcmp('h', string(i)) || strcmp('i', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract1 - interstVelocity.extract2;
                        elseif strcmp('j', string(i)) || strcmp('k', string(i)) || strcmp('l', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent + interstVelocity.raffinate;
                        elseif strcmp('m', string(i)) || strcmp('n', string(i)) || strcmp('p', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent;
                        end
                    end

                elseif opt.nColumn == 20

                    for i = 1: opt.nColumn
%                       Interstitial velocity of each ZONE
                        if strcmp('a', string(i)) || strcmp('b', string(i)) || strcmp('c', string(i)) || strcmp('d', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle;
                        elseif strcmp('e', string(i)) || strcmp('f', string(i)) || strcmp('g', string(i)) || strcmp('h', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract1;
                        elseif strcmp('i', string(i)) || strcmp('j', string(i)) || strcmp('k', string(i)) || strcmp('l', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.extract1 - interstVelocity.extract2;
                        elseif strcmp('m', string(i)) || strcmp('n', string(i)) || strcmp('o', string(i)) || strcmp('p', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent + interstVelocity.raffinate;
                        elseif strcmp('q', string(i)) || strcmp('r', string(i)) || strcmp('s', string(i)) || strcmp('t', string(i))
                            params{eval(['sequence' '.' string(i)])}.interstitialVelocity = interstVelocity.recycle - interstVelocity.desorbent;
                        end
                    end

                end

            end

        end % getParams

        function Results = Purity_Productivity(plotData, opt)
%-----------------------------------------------------------------------------------------
% Calculation of the performance index of SMB, such Purity and Productivity
%
%
%-----------------------------------------------------------------------------------------


            Nominator = pi * (opt.columnDiameter/2)^2 * opt.columnLength * (1-opt.porosityColumn);

            if opt.nZone == 4
%           using column in the Zone III to calculate the integral of purity
                if opt.nColumn == 4
                    position_ext = 1; position_raf = 3;
                elseif opt.nColumn == 8
                    position_ext = 2; position_raf = 6;
                elseif opt.nColumn == 12
                    position_ext = 3; position_raf = 9;
                elseif opt.nColumn == 16
                    position_ext = 4; position_raf = 12;
                end

                
%               Please be quite careful, which component is used for statistics (change them with comp_ext_ID or comp_raf_ID)
                if opt.nComponents == 2
%                   Extract ports
                    Purity_extract = trapz(plotData{position_ext}.outlet.time, plotData{position_ext}.outlet.concentration(:,opt.comp_ext_ID)) /...
                        ( trapz(plotData{position_ext}.outlet.time, plotData{position_ext}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_ext}.outlet.time, plotData{position_ext}.outlet.concentration(:,1)) );

%                   Raffinate ports
                    Purity_raffinate = trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,opt.comp_raf_ID)) / ...
                        ( trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,1)) );	

                elseif opt.nComponents == 3
%                   Extract ports
                    Purity_extract = trapz(plotData{position_ext}.outlet.time, plotData{position_ext}.outlet.concentration(:,opt.comp_ext_ID)) /...
                        ( trapz(plotData{position_ext}.outlet.time, plotData{position_ext}.outlet.concentration(:,3)) +...
                        trapz(plotData{position_ext}.outlet.time, plotData{position_ext}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_ext}.outlet.time, plotData{position_ext}.outlet.concentration(:,1)) );

%                   Raffinate ports
                    Purity_raffinate = trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,opt.comp_raf_ID)) / ...
                        ( trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,3)) +...
                        trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,1)) );	

                end

%               per switching time, in the tank of extract port, such (unit: g/m^3) amount of target component was collected.
                Productivity_extract = trapz(plotData{position_ext}.outlet.time, plotData{position_ext}.outlet.concentration(:,opt.comp_ext_ID))...
                    * opt.molMass(opt.comp_ext_ID) * opt.flowRate_extract / Nominator;

                Productivity_raffinate = trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,opt.comp_raf_ID))...
                    * opt.molMass(opt.comp_raf_ID) * opt.flowRate_raffinate / Nominator;


                if opt.enableDebug
                    fprintf('Purity (Extract): %g %% \n', Purity_extract * 100);
                    fprintf('Purity (Raffinate): %g %% \n', Purity_raffinate * 100)
                    fprintf('Productivity (Extract) in each switching time: %g g/m^3 \n', Productivity_extract);
                    fprintf('Productivity (Raffinate) in each switching time: %g g/m^3 \n', Productivity_raffinate);
                end

                Results = struct('Purity_extract', Purity_extract, 'Purity_raffinate', Purity_raffinate, ...
                    'Productivity_extract', Productivity_extract, 'Productivity_raffinate', Productivity_raffinate);
                Results.Data = plotData;


            elseif opt.nZone == 5

                if opt.nColumn == 5
                    position_ext1 = 1; position_ext2 = 2; position_raf = 4;
                elseif opt.nColumn == 10
                    position_ext1 = 2; position_ext2 = 4; position_raf = 8;
                elseif opt.nColumn == 15
                    position_ext1 = 3; position_ext2 = 6; position_raf = 12;
                elseif opt.nColumn == 20
                    position_ext1 = 4; position_ext2 = 8; position_raf = 16;
                end

%               Please be quite careful, which component is used for statistics (change them with comp_ext_ID or comp_raf_ID)
                if opt.nComponents == 3
%                   Extract ports
                    Purity_extract1 = trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,opt.comp_ext1_ID)) /...
                        ( trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,3)) +...
                        trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,1)) );

                    Purity_extract2 = trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,opt.comp_ext2_ID)) /...
                        ( trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,3)) +...
                        trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,1)) );

%                   Raffinate ports
                    Purity_raffinate = trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,opt.comp_raf_ID)) / ...
                        ( trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,3)) +...
                        trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,1)) );	

                elseif opt.nComponents == 4
%                   Extract ports
                    Purity_extract1 = trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,opt.comp_ext1_ID)) /...
                        ( trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,4)) +...
                        trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,3)) +...
                        trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,1)) );

                    Purity_extract2 = trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,opt.comp_ext2_ID)) /...
                        ( trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,4)) +...
                        trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,3)) +...
                        trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,1)) );

%                   Raffinate ports
                    Purity_raffinate = trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,opt.comp_raf_ID)) / ...
                        ( trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,4)) +...
                        trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,3)) +...
                        trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,2)) +...
                        trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,1)) );	

                end

%               per switching time, in the tank of extract port, such (unit: g/m^3) amount of target component was collected.
                Productivity_extract1 = trapz(plotData{position_ext1}.outlet.time, plotData{position_ext1}.outlet.concentration(:,opt.comp_ext1_ID))...
                    * opt.molMass(opt.comp_ext1_ID) * opt.flowRate_extract1 / Nominator;

                Productivity_extract2 = trapz(plotData{position_ext2}.outlet.time, plotData{position_ext2}.outlet.concentration(:,opt.comp_ext2_ID))...
                    * opt.molMass(opt.comp_ext2_ID) * opt.flowRate_extract2 / Nominator;

                Productivity_raffinate = trapz(plotData{position_raf}.outlet.time, plotData{position_raf}.outlet.concentration(:,opt.comp_raf_ID))...
                    * opt.molMass(opt.comp_raf_ID) * opt.flowRate_raffinate / Nominator;


                if opt.enableDebug
                    fprintf('Purity (Extract_1): %g %% \n', Purity_extract1 * 100);
                    fprintf('Purity (Extract_2): %g %% \n', Purity_extract2 * 100);
                    fprintf('Purity (Raffinate): %g %% \n', Purity_raffinate * 100)
                    fprintf('Productivity (Extract_1) in each switching time: %g g/m^3 \n', Productivity_extract1);
                    fprintf('Productivity (Extract_2) in each switching time: %g g/m^3 \n', Productivity_extract2);
                    fprintf('Productivity (Raffinate) in each switching time: %g g/m^3 \n', Productivity_raffinate);
                end

                Results = struct('Purity_extract1', Purity_extract1, 'Purity_extract2', Purity_extract2,...
                    'Purity_raffinate', Purity_raffinate, 'Productivity_extract1', Productivity_extract1,...
                    'Productivity_extract2', Productivity_extract2, 'Productivity_raffinate', Productivity_raffinate);
                Results.Data = plotData;

            end

        end % Purity_Productivity

        function objective = objectiveFunction(Results, opt)
%-----------------------------------------------------------------------------------------
% The objective function for the optimizers
% You can also define your own objective function here. The default function is: 
%
% Max Productivity_extract + Productivity_raffinate
% s.t. Purity_extract   >= 99% for more retained component
%      Purity_raffinate >= 99% for less retained component
%      other implicit constraints, such as upbound on Desorbent consumption
%-----------------------------------------------------------------------------------------


            if opt.nZone == 4
%               Construct the Penalty Function for the objective function
                penalty = abs( min(Results.Purity_extract - opt.Purity_extract_limit, 0) ) * opt.Penalty_factor ...
                    + abs( min(Results.Purity_raffinate - opt.Purity_raffinate_limit, 0) ) * opt.Penalty_factor;

%               (-)Since in the optimizer, the defined programme is of optimization of minimum.    
                objective = -(Results.Productivity_extract + Results.Productivity_raffinate) + penalty;

            elseif opt.nZone == 5
%               Construct the Penalty Function for the objective function
                penalty = abs( min(Results.Purity_extract1 - opt.Purity_extract1_limit, 0) ) * opt.Penalty_factor ...
                    + abs( min(Results.Purity_extract2 - opt.Purity_extract2_limit, 0) ) * opt.Penalty_factor ...
                    + abs( min(Results.Purity_raffinate - opt.Purity_raffinate_limit, 0) ) * opt.Penalty_factor;

%               (-)Since in the optimizer, the defined programme is of optimization of minimum.    
                objective = -(Results.Productivity_extract1 + Results.Productivity_extract2 + Results.Productivity_raffinate) + penalty;
            end


            if opt.enableDebug
                fprintf('**** The objective value:  %g \n', objective);
            end

        end % objectiveFunction

        function plotFigures(opt, plotData)
%-----------------------------------------------------------------------------------------
%  This is the plot function 
%  The numbers in the figure() represent the number of the columns
%-----------------------------------------------------------------------------------------


            if nargin < 2
                disp('Error: there are no enough input data for the function, plotFigures');
            else
                if isempty(opt)
                    disp('Error in plotFigures: the options of the parameters are missing');
                elseif isempty(plotData)
                    disp('Error in plotFigures: the data for figures plotting are missing');
                end
            end

            if opt.enableDebug                        

                if opt.nZone == 4

                    if opt.nColumn == 4

                        figure(01);clf

                        y = [plotData{4}.outlet.concentration; plotData{3}.outlet.concentration;...
                            plotData{2}.outlet.concentration; plotData{1}.outlet.concentration];

                        FigSet = plot(y); axis([0,opt.nColumn*opt.timePoints, 0,opt.yLim])
                        ylabel('Concentration [Mol]', 'FontSize', 10);
                        if opt.nComponents == 2
                            legend('comp 1', 'comp 2');
                        elseif opt.nComponents == 3
                            legend('comp 1', 'comp 2', 'comp 3');
                        end

                        set(FigSet, 'LineWidth', 2);
                        set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
                        set(gca, 'XTick', (1/2:1:(opt.nColumn-0.5)).*opt.timePoints);
                        set(gca, 'XTickLabel', {'Zone IV','Zone III','Zone II','Zone I'});
                        set(gca, 'ygrid', 'on');

                        for i = 1: (opt.nColumn-1)
                            line([i*opt.timePoints,i*opt.timePoints], [0, opt.yLim], 'color', 'k', 'LineStyle', '-.');
                        end

                    elseif opt.nColumn == 8

                        figure(01);clf

                        y = [plotData{8}.outlet.concentration; plotData{7}.outlet.concentration;...
                        plotData{6}.outlet.concentration; plotData{5}.outlet.concentration;...
                        plotData{4}.outlet.concentration; plotData{3}.outlet.concentration;...
                        plotData{2}.outlet.concentration; plotData{1}.outlet.concentration];

                        FigSet = plot(y); axis([0,opt.nColumn*opt.timePoints, 0,opt.yLim])
                        ylabel('Concentration [Mol]', 'FontSize', 10);
                        if opt.nComponents == 2
                            legend('comp 1', 'comp 2');
                        elseif opt.nComponents == 3
                            legend('comp 1', 'comp 2', 'comp 3');
                        end

                        set(FigSet, 'LineWidth', 2);
                        set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
                        set(gca, 'XTick', (1:2:(opt.nColumn-1)).*opt.timePoints);
                        set(gca, 'XTickLabel', {'Zone IV','Zone III','Zone II','Zone I'});
                        set(gca, 'ygrid', 'on');

                        for i = 1: (opt.nColumn-1)
                            line([i*opt.timePoints,i*opt.timePoints], [0, opt.yLim], 'color', 'k', 'LineStyle', '-.');
                        end

                    elseif opt.nColumn == 12

                        figure(01);clf

                        y = [plotData{12}.outlet.concentration; plotData{11}.outlet.concentration;...
                        plotData{10}.outlet.concentration; plotData{9}.outlet.concentration;...
                        plotData{8}.outlet.concentration; plotData{7}.outlet.concentration;...
                        plotData{6}.outlet.concentration; plotData{5}.outlet.concentration;...
                        plotData{4}.outlet.concentration; plotData{3}.outlet.concentration;...
                        plotData{2}.outlet.concentration; plotData{1}.outlet.concentration];

                        FigSet = plot(y); axis([0,opt.nColumn*opt.timePoints, 0,opt.yLim])
                        ylabel('Concentration [Mol]', 'FontSize', 10);
                        if opt.nComponents == 2
                            legend('comp 1', 'comp 2');
                        elseif opt.nComponents == 3
                            legend('comp 1', 'comp 2', 'comp 3');
                        end

                        set(FigSet, 'LineWidth', 2);
                        set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
                        set(gca, 'XTick', (opt.nColumn/8:3:(opt.nColumn-1)).*opt.timePoints);
                        set(gca, 'XTickLabel', {'Zone IV','Zone III','Zone II','Zone I'});
                        set(gca, 'ygrid', 'on');

                        for i = 1: (opt.nColumn-1)
                            line([i*opt.timePoints,i*opt.timePoints], [0, opt.yLim], 'color', 'k', 'LineStyle', '-.');
                        end

                    elseif opt.nColumn == 16

                        figure(01);clf

                        y = [plotData{16}.outlet.concentration; plotData{15}.outlet.concentration;...
                        plotData{14}.outlet.concentration; plotData{13}.outlet.concentration;...
                        plotData{12}.outlet.concentration; plotData{11}.outlet.concentration;...
                        plotData{10}.outlet.concentration; plotData{9}.outlet.concentration;...
                        plotData{8}.outlet.concentration; plotData{7}.outlet.concentration;...
                        plotData{6}.outlet.concentration; plotData{5}.outlet.concentration;...
                        plotData{4}.outlet.concentration; plotData{3}.outlet.concentration;...
                        plotData{2}.outlet.concentration; plotData{1}.outlet.concentration];

                        FigSet = plot(y); axis([0,opt.nColumn*opt.timePoints, 0,opt.yLim])
                        ylabel('Concentration [Mol]', 'FontSize', 10);
                        if opt.nComponents == 2
                            legend('comp 1', 'comp 2');
                        elseif opt.nComponents == 3
                            legend('comp 1', 'comp 2', 'comp 3');
                        end

                        set(FigSet, 'LineWidth', 2);
                        set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
                        set(gca, 'XTick', (opt.nColumn/8:4:(opt.nColumn-1)).*opt.timePoints);
                        set(gca, 'XTickLabel', {'Zone IV','Zone III','Zone II','Zone I'});
                        set(gca, 'ygrid', 'on');

                        for i = 1: (opt.nColumn-1)
                            line([i*opt.timePoints,i*opt.timePoints], [0, opt.yLim], 'color', 'k', 'LineStyle', '-.');
                        end

                    end

% -----------------------------------------------------------------------------
                elseif opt.nZone == 5

                    if opt.nColumn == 5

                        figure(01);clf

                        y = [plotData{5}.outlet.concentration; plotData{4}.outlet.concentration;...
                            plotData{3}.outlet.concentration; plotData{2}.outlet.concentration;...
                            plotData{1}.outlet.concentration];

                        FigSet = plot(y); axis([0,opt.nColumn*opt.timePoints, 0,opt.yLim])
                        ylabel('Concentration [Mol]', 'FontSize', 10);
                        if opt.nComponents == 3
                            legend('comp 1', 'comp 2', 'comp 3');
                        elseif opt.nComponents == 4
                            legend('comp 1', 'comp 2', 'comp 3', 'comp 4');
                        end

                        set(FigSet, 'LineWidth', 2);
                        set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
                        set(gca, 'XTick', (1/2:1:(opt.nColumn-0.5)).*opt.timePoints);
                        set(gca, 'XTickLabel', {'Zone V','Zone IV','Zone III','Zone II','Zone I'});
                        set(gca, 'ygrid', 'on');

                        for i = 1: (opt.nColumn-1)
                            line([i*opt.timePoints,i*opt.timePoints], [0, opt.yLim], 'color', 'k', 'LineStyle', '-.');
                        end

                    elseif opt.nColumn == 10

                        figure(01);clf

                        y = [plotData{10}.outlet.concentration; plotData{9}.outlet.concentration;...
                        plotData{8}.outlet.concentration; plotData{7}.outlet.concentration;...
                        plotData{6}.outlet.concentration; plotData{5}.outlet.concentration;...
                        plotData{4}.outlet.concentration; plotData{3}.outlet.concentration;...
                        plotData{2}.outlet.concentration; plotData{1}.outlet.concentration];

                        FigSet = plot(y); axis([0,opt.nColumn*opt.timePoints, 0,opt.yLim])
                        ylabel('Concentration [Mol]', 'FontSize', 10);
                        if opt.nComponents == 3
                            legend('comp 1', 'comp 2', 'comp 3');
                        elseif opt.nComponents == 4
                            legend('comp 1', 'comp 2', 'comp 3', 'comp 4');
                        end

                        set(FigSet, 'LineWidth', 2);
                        set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
                        set(gca, 'XTick', (1:2:(opt.nColumn-1)).*opt.timePoints);
                        set(gca, 'XTickLabel', {'Zone V','Zone IV','Zone III','Zone II','Zone I'});
                        set(gca, 'ygrid', 'on');

                        for i = 1: (opt.nColumn-1)
                            line([i*opt.timePoints,i*opt.timePoints], [0, opt.yLim], 'color', 'k', 'LineStyle', '-.');
                        end

                    elseif opt.nColumn == 15

                        figure(01);clf

                        y = [plotData{15}.outlet.concentration; plotData{14}.outlet.concentration;...
                        plotData{13}.outlet.concentration; plotData{12}.outlet.concentration;...
                        plotData{11}.outlet.concentration; plotData{10}.outlet.concentration;...
                        plotData{9}.outlet.concentration; plotData{8}.outlet.concentration;...
                        plotData{7}.outlet.concentration; plotData{6}.outlet.concentration;...
                        plotData{5}.outlet.concentration; plotData{4}.outlet.concentration;...
                        plotData{3}.outlet.concentration; plotData{2}.outlet.concentration;...
                        plotData{1}.outlet.concentration];

                        FigSet = plot(y); axis([0,opt.nColumn*opt.timePoints, 0,opt.yLim])
                        ylabel('Concentration [Mol]', 'FontSize', 10);
                        if opt.nComponents == 3
                            legend('comp 1', 'comp 2', 'comp 3');
                        elseif opt.nComponents == 4
                            legend('comp 1', 'comp 2', 'comp 3', 'comp 4');
                        end

                        set(FigSet, 'LineWidth', 2);
                        set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
                        set(gca, 'XTick', (opt.nColumn/10:3:(opt.nColumn-1)).*opt.timePoints);
                        set(gca, 'XTickLabel', {'Zone V','Zone IV','Zone III','Zone II','Zone I'});
                        set(gca, 'ygrid', 'on');

                        for i = 1: (opt.nColumn-1)
                            line([i*opt.timePoints,i*opt.timePoints], [0, opt.yLim], 'color', 'k', 'LineStyle', '-.');
                        end

                    elseif opt.nColumn == 20

                        figure(01);clf

                        y = [plotData{20}.outlet.concentration; plotData{19}.outlet.concentration;...
                        plotData{18}.outlet.concentration; plotData{17}.outlet.concentration;...
                        plotData{16}.outlet.concentration; plotData{15}.outlet.concentration;...
                        plotData{14}.outlet.concentration; plotData{13}.outlet.concentration;...
                        plotData{12}.outlet.concentration; plotData{11}.outlet.concentration;...
                        plotData{10}.outlet.concentration; plotData{9}.outlet.concentration;...
                        plotData{8}.outlet.concentration; plotData{7}.outlet.concentration;...
                        plotData{6}.outlet.concentration; plotData{5}.outlet.concentration;...
                        plotData{4}.outlet.concentration; plotData{3}.outlet.concentration;...
                        plotData{2}.outlet.concentration; plotData{1}.outlet.concentration];

                        FigSet = plot(y); axis([0,opt.nColumn*opt.timePoints, 0,opt.yLim])
                        ylabel('Concentration [Mol]', 'FontSize', 10);
                        if opt.nComponents == 3
                            legend('comp 1', 'comp 2', 'comp 3');
                        elseif opt.nComponents == 4
                            legend('comp 1', 'comp 2', 'comp 3', 'comp 4');
                        end

                        set(FigSet, 'LineWidth', 2);
                        set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
                        set(gca, 'XTick', (opt.nColumn/10:4:(opt.nColumn-1)).*opt.timePoints);
                        set(gca, 'XTickLabel', {'Zone IV','Zone III','Zone II','Zone I'});
                        set(gca, 'ygrid', 'on');

                        for i = 1: (opt.nColumn-1)
                            line([i*opt.timePoints,i*opt.timePoints], [0, opt.yLim], 'color', 'k', 'LineStyle', '-.');
                        end

                    end
                    
                end % if opt.nZone == 4 / opt.nZone == 5


            end % if opt.enableDebug

        end % function plotFigures


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