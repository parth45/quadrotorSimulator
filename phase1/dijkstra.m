function [path, num_expanded] = dijkstra(map, start, goal, astar)
% DIJKSTRA Find the shortest path from start to goal.
%   PATH = DIJKSTRA(map, start, goal) returns an M-by-3 matrix, where each row
%   consists of the (x, y, z) coordinates of a point on the path.  The first
%   row is start and the last row is goal.  If no path is found, PATH is a
%   0-by-3 matrix.  Consecutive points in PATH should not be farther apart than
%   neighboring cells in the map (e.g.., if 5 consecutive points in PATH are
%   co-linear, don't simplify PATH by removing the 3 intermediate points).
% 
%   PATH = DIJKSTRA(map, start, goal, astar) finds the path using euclidean
%   distance to goal as a heuristic if astar is true.
%
%   [PATH, NUM_EXPANDED] = DIJKSTRA(...) returns the path as well as
%   the number of points that were visited while performing the search.
if nargin < 4
    astar = false;
end
six_connected = 1;
show_plot = 0;

if show_plot
    figure(5);
    plot3(start(1), start(2), start(3), 'go');
    grid on;
    hold on;
    plot3(goal(1), goal(2), goal(3),'ro');
    xlim(map.boundary_dim([1 4]));
    ylim(map.boundary_dim([2 5]));
    zlim(map.boundary_dim([3 6]));
    plot_obstacles(map);
end

% Pull out necessary information
xy_res = map.xy_res;
z_res = map.z_res;

% Calculate 'goal box'
goal_min = goal - [xy_res xy_res z_res];
goal_max = goal + [xy_res xy_res z_res];

% All possible expansion directions
dpi = [eye(3,'int16'); -eye(3, 'int16')];
dp = bsxfun(@times, double(dpi), [xy_res xy_res z_res]);
dps = abs(sum(dp, 2));
% for xi = -1:1
%     for yi = -1:1
%         for zi = -1:1
%             if all([xi yi zi] == 0) || sum([xi yi zi]) == 0
%                 continue;
%             end
%             dp = [dp; xi*xy_res yi*xy_res zi*z_res];
%             dps = [dps; norm(dp(end,:))];
%             dpi = [dpi; xi yi zi];
%         end
%     end
% end
avoid_dir_p = zeros(1,3,'int16'); % used to avoid cutting corners
avoid_dir_n = zeros(1,3,'int16');

% Initial
current = start;
parent = NaN(1,3);
cur_cost = 0;

% Keep track of neighbors and visited node
if astar
    neighbors = zeros(0,8,'single');
else    
    neighbors = zeros(0,7,'single');
end
nis = zeros(0, 3, 'int16');

% Build visitor and cost map
[visited offsets res min_m max_i] = create_visited_map(map, start);
isNeighbor = -1*single(ones(size(visited)));

% Get starting index
ci = int16(real_to_idx(start, offsets, res, min_m, max_i, 0));
goali = int16(real_to_idx(goal, offsets, res, min_m, max_i, 0));

% Make sparse collision map
col_map = create_collision_map(map, size(visited), offsets, res, min_m, max_i);
% Flags and info
no_path = 0;
num_expanded = 0;

while true

%    % Determine nodes 'in consideration'
   incons = bsxfun(@plus, current, dp);
   inconsi = bsxfun(@plus, ci, dpi);
   % Check if they collide
   for j = 1:size(inconsi,1)
       point = incons(j,:);
       pidx  = inconsi(j,:);
       dpix = dpi(j,:);
       % Check if out of bounds
       if any(pidx < 1)
           continue;
       elseif any(pidx > max_i)
           continue;
       % Check if already neighbor
%        elseif isNeighbor(pidx(1), pidx(2), pidx(3)) == -1
%            continue;
       % Check if already visited 
       elseif ~isnan(visited(pidx(1), pidx(2), pidx(3), 1))
           continue;
       % Check if collision
       elseif col_map{pidx(3)}(pidx(1), pidx(2))
           % Check if it's one of the 6 orthogonal motions
           if j < 7
               avoid_dir_p(dpix > 0) = avoid_dir_p(dpix > 0) + dpix(dpix > 0);
               avoid_dir_n(dpix < 0) = avoid_dir_n(dpix < 0) + dpix(dpix < 0);
           end
           continue;
       % If we're looking at a corner that will cut through a block
       elseif j > 6 && (any(dpix(dpix > 0) == avoid_dir_p(dpix > 0)) || any(dpix(dpix < 0) == avoid_dir_n(dpix < 0)))
           continue;
       end
       % Calculate tentative cost
       tent_cost = cur_cost + dps(j);
       isN = isNeighbor(pidx(1), pidx(2), pidx(3));
       % If just dijkstra
       if ~astar
           if isN >= 0 && isN <= tent_cost
                continue;
           end
           % Figure out where to put it in the neighbor list
           idx = find(tent_cost <= neighbors(:,7), 1, 'first');           
           if isempty(idx)
               neighbors = [neighbors; point, current, tent_cost];
               nis = [nis; pidx];
           elseif idx == 1
               neighbors = [point, current, tent_cost; neighbors];
               nis = [pidx; nis];
           else          
                neighbors = [neighbors(1:idx-1,:); [point, current, tent_cost]; neighbors(idx:end,:)];
                nis = [nis(1:idx-1,:); pidx; nis(idx:end,:)];
           end
           % Add cost to cost_map
           isNeighbor(pidx(1), pidx(2), pidx(3)) = tent_cost;
       else
           % If we're only doing 6-connected, each neighbor is expanded
           % optimally
           if six_connected && isN >= 0
               continue;
           end
           hueristic = tent_cost + est_dist(pidx, goali, res);
           % Check if already exists
           if isN >= 0 && isN <= hueristic
                continue;
           end
           % Figure out where to put it in the neighbor list
           idx = find(hueristic <= neighbors(:,8), 1, 'first');
           if isempty(idx)
               neighbors = [neighbors; point, current, tent_cost, hueristic];
               nis = [nis; pidx];
           elseif idx == 1
               neighbors = [point, current, tent_cost, hueristic; neighbors];
               nis = [pidx; nis];
           else          
                neighbors = [neighbors(1:idx-1,:); [point, current, tent_cost, hueristic]; neighbors(idx:end,:)];
                nis = [nis(1:idx-1,:); pidx; nis(idx:end,:)];
           end
           % Add cost to cost_map
           isNeighbor(pidx(1), pidx(2), pidx(3)) = hueristic;
       end

       % Incrememnt num_expanded
       num_expanded = num_expanded + 1;
       % Plot, if desired
       if show_plot
           plot3(point(1), point(2), point(3), 'b.');
           drawnow;
       end
   end
      
   % Check if there are no more neighbors -> no path
   if isempty(neighbors)
       no_path = 1;
       break;
   end
   
   % Fill parent in the corresponding entry for visited
   vidx = ci;
   visited(vidx(1), vidx(2), vidx(3), :) = parent;
   
   % Choose new current and parent
   current = neighbors(1,1:3);
   ci = nis(1,1:3);
   parent = neighbors(1,4:6);   
   cur_cost = neighbors(1,7);
   % Remove from neighbors
   neighbors = neighbors(2:end,:);
   nis = nis(2:end,:);
   isNeighbor(vidx(1), vidx(2), vidx(3)) = 0;
   % Reset avoid_dir
   avoid_dir_p(1:3) = 0;
   avoid_dir_n(1:3) = 0; 
   
   
   % Plot, if desired
   if show_plot
       plot3(current(1), current(2), current(3), 'yo');
       drawnow;
   end
      
   % See if we're close enough to the goal to stop
   if all(current >= goal_min) && all(current <= goal_max)
       break;
   end  

end

% Don't do anything if there as no path
path = zeros(0,3);
if no_path
    pause(5);
    return;
end

% Trace steps
path = current;
current = parent;
while ~all(almostEqual(start, current))
    path = [current; path];    
    cidx = real_to_idx(current, offsets, res, min_m, max_i, 0); 
    current = squeeze(visited(cidx(1), cidx(2), cidx(3), :))';
end  

% Add start and end
path = [start; path; goal];
    
end

function col_map = create_collision_map(map, dims, offsets, res, min_m, max_i)
    col_mat = zeros(dims(1:3));
    res4 = repmat(res, length(map.block_dim(:,1)), 1);
    % Get indices of box coordinates
    horiz_offset = .15; %m
    vert_offset = .1; %m
    quad_body = repmat([horiz_offset, horiz_offset, vert_offset], size(map.block_dim, 1), 1);
    lower_bound = real_to_idx(map.block_dim(:,1:3)-quad_body-map.margin, offsets, res4, min_m, max_i, 1);
    upper_bound = real_to_idx(map.block_dim(:,4:6)+map.margin+quad_body, offsets, res4, min_m, max_i, -1);
    for i = 1:length(map.block_dim(:,1))
        col_mat(lower_bound(i,1):upper_bound(i,1),...
                lower_bound(i,2):upper_bound(i,2),...
                lower_bound(i,3):upper_bound(i,3)) = 1;
    end
    % Make sparse?
    col_map = cell(dims(3),1);
    for i = 1:dims(3)
        col_map{i} = sparse(squeeze(col_mat(:,:,i)));
    end
%     col_map = col_mat;        
end

function [visited offsets res min_m dim] = create_visited_map(map, start)
    % Pull out data
    min_m = map.boundary_dim(1:3);
    max_m = map.boundary_dim(4:6);
    res = single([map.xy_res map.xy_res map.z_res]);
    % Find offsets
    offsets = mod(start - min_m, res);
    % Find dimensions of map
    dim = floor_approx((max_m - min_m - offsets)./res)+1;
    % Create map
    visited = NaN(dim(1), dim(2), dim(3), 3, 'single');
end

function v = floor_approx(v)
for i=1:length(v)
    if abs(round(v(i)) - v(i)) < 0.001
        v(i) = round(v(i));
    else
        v(i) = floor(v(i));
    end
end
end

function idx = real_to_idx(v, offsets, res, min_m, max_i, snap_dir)
    % res should match dimension of v
    if snap_dir == 0
        idx = round((bsxfun(@minus,v, min_m+offsets))./ res)+1;
    elseif snap_dir == -1
        idx = floor((bsxfun(@minus,v, min_m+offsets))./ res)+1;
    else
        idx = ceil((bsxfun(@minus,v, min_m+offsets))./ res)+1;
    end
    % Make sure it's in the map
    idx = bsxfun(@max, idx, [1 1 1]);
    idx = bsxfun(@min, idx, max_i);
end

function estimate = est_dist(point, goal, res)
    six_connected = 1;
    
    if six_connected
        estimate = sum(single(abs(point-goal)).*res);
    else
        % Get index square distance
        d1 = abs(goal - point);    
        dm1 = min(d1);
        % Get rid of largest component
        d2 = d1 - dm1;
        [dm2, im2] = min(d2(d2>0));
        % Get rid of next largest component, unless it's zero
        if isempty(dm2)
            dm2 = 0;
            dm3 = 0;
            im3 = 0;
        else
            % Get third component
            d3 = d2 - dm2;        
            im3 = find(d3 > 0);        
            if isempty(im3)
                dm3 = 0;
                im3 = 0;
            else
                dm3 = d3(im3);
            end
        end        
        % Convert to real distances
        dm1_val = single(dm1)*norm(res);
        dm2_val = single(dm2)*sqrt(2*res(1)^2 + (im2 == 3) * (res(3)^2 - res(2)^2));
        dm3_val = single(dm3) * (res(1)  + (im3 == 3) * (res(3) - res(1)));
        estimate = dm1_val + dm2_val + dm3_val;
    end
end

% function d = square_dist(v1, v2)
% d = sum(abs(v1-v2));
% end
% 
% function d = euclid_dist(v1, v2)
% d = norm(v1-v2);
% end

function v = almostEqual(a,b)
v = (abs(a-b) < 1e-4);

end

function plot_obstacles(map)
% PLOT_PATH Visualize a path through an environment
%   PLOT_PATH(map, path) creates a figure showing a path through the
%   environment.  path is an N-by-3 matrix where each row corresponds to the
%   (x, y, z) coordinates of one point along the path.
% figure(2)
% hold on
for i = 1:length(map.block_dim(:,1))
% i = 1;  

b = map.block_dim(i,:);
    x = [b(1) b(4)];
    y = [b(2) b(5)];
    z = [b(3) b(6)];
    col = b(7:9);
    verts = [];
    for xi = 1:2
        for yi = 1:2
            for zi = 1:2
                verts(end+1, 1:3) = [x(xi) y(yi) z(zi)];
            end
        end
    end
    faces = [1 3 4 2; 5 6 8 7;
             1 2 6 5; 3 4 8 7;
             1 3 7 5; 2 4 8 6];
   patch('Faces',faces,'Vertices',verts,'FaceColor',col./255);  
%    hold on;
end
end