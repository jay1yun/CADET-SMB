function objective = simulatedMovingBed(varargin)

% =============================================================================
% This is the main function which is charge of switching to reach the
% cyclic steady state. The layout of the columns and the configuration is
% listed as follow:
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
% Fluid phase goes from Zone I to Zone II to Zone III, while the ports switch direction
% is from Zone I to Zone IV to Zone III;
% =============================================================================


    global string stringSet dummyProfile startingPointIndex Feed2;

    tTotal = tic;

%   Construct the string in order to tell simulator the calculation sequence
    stringSet = {'a' 'b' 'c' 'd' 'e' 'f' 'g' 'h' 'i' 'j' 'k' 'l' 'm'...
                 'n' 'o' 'p' 'q' 'r' 's' 't' 'u' 'v' 'w' 'x' 'y' 'z'...
                 'a1' 'b1' 'c1' 'd1' 'e1' 'f1' 'g1' 'h1' 'i1' 'j1' 'k1' 'l1' 'm1'...
                 'n1' 'o1' 'p1' 'q1' 'r1' 's1' 't1' 'u1' 'v1' 'w1' 'x1' 'y1' 'z1'...
                 'a2' 'b2' 'c2' 'd2' 'e2' 'f2' 'g2' 'h2' 'i2' 'j2' 'k2' 'l2' 'm2'...
                 'n2' 'o2' 'p2' 'q2' 'r2' 's2' 't2' 'u2' 'v2' 'w2' 'x2' 'y2' 'z2'...
                 'a3' 'b3' 'c3' 'd3' 'e3' 'f3' 'g3' 'h3' 'i3' 'j3' 'k3' 'l3' 'm3'...
                 'n3' 'o3' 'p3' 'q3' 'r3' 's3' 't3' 'u3' 'v3' 'w3' 'x3' 'y3' 'z3'...
                 'aa' 'bb' 'cc' 'dd' 'ee' 'ff' 'gg' 'hh' 'ii' 'jj' 'kk' 'll' 'mm'...
                 'nn' 'oo' 'pp' 'qq' 'rr' 'ss' 'tt' 'uu' 'vv' 'ww' 'xx' 'yy' 'zz'};

    [opt, interstVelocity, Feed] = getParameters(varargin{:});

%   Check the interstitial velocity, if anyone was negative, stop the simulation
%       and assign a very big objective function value to this column configuration.
    flag = SMB.interstVelocityCheck(interstVelocity, opt);
    if flag == 1
        objective = 1e5;
        return;
    end

    if opt.enable_CSTR && opt.enable_DPFR
        error('It is not allowed have both the CSTR and DPFR in the simulation \n');
    end

    if opt.nColumn > length(stringSet)
        error('The simulation of %3g-column case in %3g-zone is not finished so far \n', opt.nColumn, opt.nZone);
    end


%   Preallocation
%----------------------------------------------------------------------------------------
%   Construct the string for simulation sequence
    string = char(stringSet(1:opt.nColumn));

%   If num = 2 (4-column case), the starting point is Feed, sequence is c, d, a, b
%       num = 0, the starting point is Desorbent (default), sequence is a, b, c, d
%	In the 8-zone scenario, it should be careful in choosing the starting node
%       as it is impossible to start from Feed2 node at the outset.
    string = circshift(string, 0);
    startingPointIndex = SMB.stringIndexing(opt, string(1));

%   Initialize the starting points, currentData
    currentData    = cell(1, opt.nColumn);
    for k = 1:opt.nColumn
%       currentData stores the outlets of each interval of columns
        currentData{k}.outlet.time = linspace(0, opt.switch, opt.timePoints);
        currentData{k}.outlet.concentration = zeros(length(Feed.time), opt.nComponents);
        currentData{k}.lastState = [];

        if opt.enable_DPFR
            currentData{k}.lastState_DPFR = cell(1,2);
            currentData{k}.lastState_DPFR{1} = zeros(opt.nComponents, opt.DPFR_nCells); % DPFR before
            currentData{k}.lastState_DPFR{2} = zeros(opt.nComponents, opt.DPFR_nCells); % DPFR after
        end
    end

%   Number the columns for the sake of plotting
    columnNumber = cell(1, opt.nColumn);
    for k = 1:opt.nColumn
        if k == 1
            columnNumber{1} = opt.nColumn;
        else
            columnNumber{k} = k-1;
        end
    end

    sequence = cell2struct( columnNumber, stringSet(1:opt.nColumn), 2 );

%   Specify the column for the convergence checking
%   Usually, the column after the Feed node is adopted
    if opt.nZone == 4
        convergIndx = sum(opt.structID(1:2));
    elseif opt.nZone == 5
        convergIndx = sum(opt.structID(1:3));
    elseif opt.nZone == 8
        convergIndx = sum(opt.structID(1:3));
    else
        error('Please choose the correct zone configuration \n');
    end

%   convergPrevious is used for stopping criterion
    convergPrevious = currentData{convergIndx}.outlet.concentration;

%   After switching, dummyProfile is used to transfer concentration profile of last column
%       to the inlet port of the first column
    dummyProfile 	= currentData{sequence.(string(end))}.outlet;

%   The dimension of plotData (columnNumber x switches)
%          t_s   2*t_s  3*t_s  4*t_s
%          {1}    {1}    {1}    {1}
%          {2}    {2}    {2}    {2}
%          {3}    {3}    {3}    {3}
%          {4}    {4}    {4}    {4}
    plotData = cell(opt.nColumn,opt.nColumn);

%   The data for plotting dynamic trajectory.
%   The row represents the number of withdrawn ports
    if opt.nZone == 4
        dyncData = cell(2, opt.nMaxIter);
    elseif opt.nZone == 5
        dyncData = cell(3, opt.nMaxIter);
    elseif opt.nZone == 8
        dyncData = cell(3, opt.nMaxIter);
    end
%----------------------------------------------------------------------------------------

%   Simulations
%----------------------------------------------------------------------------------------
%   Interactive plotting
    if opt.enableDebug
        fprintf(' ============================================= \n');
        fprintf(' ---- Switch ---- Cycle ---- CSS_relError ---- \n');
    end

%   Main loop
    for i = 1:opt.nMaxIter

%       Switching the ports, in the countercurrent manner of fluid
        sequence = cell2struct( circshift( struct2cell(sequence),-1 ), stringSet(1:opt.nColumn) );

%       The simulation of columns within a SMB unit by the sequence
%           say, 'a', 'b', 'c', 'd' in four-column cases (desorbent node)
        for k = string'

            % The node balance: transmission of concentration, column state, velocity and so on
            column = SMB.massConservation(currentData, interstVelocity, Feed, opt, sequence, k);

            if opt.enable_CSTR

                % The CSTR before the current column
                column.inlet = SMB.CSTR(column.inlet, column, opt);

                [outletProfile, lastState] = SMB.secColumn(column.inlet, column.params, column.initialState, varargin{:});

                % The CSTR after the current column
                outletProfile = SMB.CSTR(outletProfile, column, opt);

            elseif opt.enable_DPFR

                % The DPFR before the current column
                [column.inlet, lastState_DPFR_pre] = SMB.DPFR(column.inlet, column.initialState_DPFR{1}, opt);

                [outletProfile, lastState] = SMB.secColumn(column.inlet, column.params, column.initialState, varargin{:});

                % The DPFR after the current column
                [outletProfile, lastState_DPFR_pos] = SMB.DPFR(outletProfile, column.initialState_DPFR{2}, opt);

                currentData{sequence.(k)}.lastState_DPFR = [{lastState_DPFR_pre}, {lastState_DPFR_pos}];

            else

                % The simulation of a single column with the CADET solver
                [outletProfile, lastState] = SMB.secColumn(column.inlet, column.params, column.initialState, varargin{:});

            end


            % Store the concentration profile, in which it is used as the profile of Feed_2 inlet
            if opt.nZone == 8
                if strcmp('raffinate', opt.intermediate_feed) && strcmp(k, stringSet(sum(opt.structID(1:3))))
                    Feed2 = outletProfile;
                elseif strcmp('extract', opt.intermediate_feed) && strcmp(k, stringSet(opt.structID(1)))
                    Feed2 = outletProfile;
                end
            end

            % The concentration profile of column string(end) is also stored as the dummyProfile
            % because of a technical problem
            if strcmp(k, string(end))
                dummyProfile = outletProfile;
            end

            currentData{sequence.(k)}.outlet     = outletProfile;
            currentData{sequence.(k)}.lastState  = lastState;

        end


        % The collection of the dyncData for the trajectory plotting
        if opt.nZone == 4
            dyncData{1, i} = currentData{sequence.(char(stringSet(sum(opt.structID(1:3)))))}.outlet.concentration;
            dyncData{2, i} = currentData{sequence.(char(stringSet(opt.structID(1))))}.outlet.concentration;
        elseif opt.nZone == 5
            dyncData{1, i} = currentData{sequence.(char(stringSet(sum(opt.structID(1:4)))))}.outlet.concentration;
            dyncData{2, i} = currentData{sequence.(char(stringSet(sum(opt.structID(1:2)))))}.outlet.concentration;
            dyncData{3, i} = currentData{sequence.(char(stringSet(opt.structID(1))))}.outlet.concentration;
        elseif opt.nZone == 8
            dyncData{1, i} = currentData{sequence.(char(stringSet(sum(opt.structID(1:7)))))}.outlet.concentration;
            dyncData{2, i} = currentData{sequence.(char(stringSet(sum(opt.structID(1:5)))))}.outlet.concentration;
            dyncData{3, i} = currentData{sequence.(char(stringSet(opt.structID(1))))}.outlet.concentration;
        end

%       Plot the dynamic trajectory
        SMB.plotDynamic(opt, dyncData(:,1:i), i);

%       Store the data of one round (opt.nColumn switches), into plotData
        index = mod(i, opt.nColumn);
        if index == 0
            plotData(:,opt.nColumn) = currentData';
        else
            plotData(:,index) = currentData';
        end


%       Convergence criterion was adopted in each nColumn iteration
%           ||( C(z, t) - C(z, t + nColumn * t_s) ) / C(z, t)|| < tol, for a specific column
        if fix(i/opt.nColumn) == i/(opt.nColumn)

            diffNorm = 0; stateNorm = 0;

            for k = 1:opt.nComponents
                diffNorm = diffNorm + norm( convergPrevious(:,k) - currentData{convergIndx}.outlet.concentration(:,k) );
                stateNorm = stateNorm + norm( currentData{convergIndx}.outlet.concentration(:,k) );
            end

            relativeDelta = diffNorm / stateNorm;

            if opt.enableDebug
                fprintf(' %8d %10d %18g \n', i, i/opt.nColumn, relativeDelta);
            end

%           Plot the outlet profile of each column in one round
            SMB.plotFigures(opt, plotData);

            if relativeDelta <= opt.tolIter
                break
            else
                convergPrevious = currentData{convergIndx}.outlet.concentration;
            end

        end
    end
%----------------------------------------------------------------------------------------

%   Post-process
%----------------------------------------------------------------------------------------
%   Compute the performance index, such Purity and Productivity
    Results = SMB.Purity_Productivity(plotData, opt);

%   Construct your own Objective Function and calculate the value
    objective = SMB.objectiveFunction(Results, opt);

    tTotal = toc(tTotal);
%   Store the final data into DATA.mat file in the mode of forward simulation
    if opt.enableDebug
        fprintf('The time elapsed for reaching the Cyclic Steady State: %g sec \n', tTotal);
        SMB.concDataConvertToASCII(plotData, opt);
        SMB.trajDataConvertToASCII(dyncData, opt);
        save(sprintf('Performance_%03d.mat',fix(rand*100)),'Results');
        fprintf('The results about concentration profiles and the trajectories have been stored \n');
    end

end
% =============================================================================
%  SMB - The Simulated Moving Bed Chromatography for separation of
%  target compounds, either binary or ternary.
%
%      Copyright © 2008-2016: Eric von Lieres, Qiaole He
%
%      Forschungszentrum Juelich GmbH, IBG-1, Juelich, Germany.
%
%  All rights reserved. This program and the accompanying materials
%  are made available under the terms of the GNU Public License v3.0 (or, at
%  your option, any later version) which accompanies this distribution, and
%  is available at http://www.gnu.org/licenses/gpl.html
% =============================================================================
