%% Process data
% Acquire data from run
data = ProcessCsvFile(datafile); % Select dataset

% Zero out the timestamps. This makes it easy to integrate with the
% resulting data of the simulator, which starts at 0.
timestampsFromZero = data.timestamp - data.timestamp(1);

% Check for both autonomous mode from HEARTBEAT @ 10Hz
valid_autodata_data = ~isnan(data.HEARTBEAT.base_mode);
auto_mode = bitand(data.HEARTBEAT.base_mode(valid_autodata_data), 4) ~= 0;
mode_time = timestampsFromZero(valid_autodata_data);
[mode_time, i] = unique(mode_time);
auto_mode = auto_mode(i);
clear valid_autodata_data;

% And manual override from NODE_STATUS @ 1Hz for the primary node.
valid_reset_data = ~isnan(data.NODE_STATUS.primary_errors);
manual_override = double(bitand(data.NODE_STATUS.primary_errors(valid_reset_data), hex2dec('10')) ~= 0);
override_time = timestampsFromZero(valid_reset_data);
clear valid_reset_data;

% Now resample the manual override signals, as that's the slower one
manual_override_int = interp1(override_time, manual_override, mode_time, 'nearest');
manual_override_int(isnan(manual_override_int)) = 0;
clear override_time manual_override;

% And now find all the times we're in autonomous mode and it's not being
% overridden.
automode = double(auto_mode & ~manual_override_int);
clear manual_override_int;

% Grab position and velocity data to interpolate all other data onto
valid_lpos_data = ~isnan(data.LOCAL_POSITION_NED.x);
x = data.LOCAL_POSITION_NED.x(valid_lpos_data);
y = data.LOCAL_POSITION_NED.y(valid_lpos_data);
vel_x = data.LOCAL_POSITION_NED.vx(valid_lpos_data);
vel_y = data.LOCAL_POSITION_NED.vy(valid_lpos_data);
pos_time = timestampsFromZero(valid_lpos_data);
clear valid_lpos_data;

% Interpolate the autonomous mode into the position timeslots
% 'nearest' mode is used to make sure these values stay logical.
mode_with_pos = interp1(mode_time, automode, pos_time, 'nearest');
mode_with_pos(isnan(mode_with_pos)) = 0;
mode_with_pos = logical(mode_with_pos);
clear automode mode_time;

% Split this data into groups based on the mode of autonomousity.
start_indices = find(diff(mode_with_pos) > 0);
end_indices = find(diff(mode_with_pos) < 0);
assert(length(start_indices) == length(end_indices));
clear mode_with_pos;

% Grab the valid range of any dataset interpolated onto the position data
% timesteps
valid_range = start_indices(auto_run):end_indices(auto_run);
clear start_indices end_indices;

% Now grab a starting-from-0 range of the current range of time
pos_time = pos_time(valid_range);
pos_time = pos_time - pos_time(1);

% Then grab waypoint and desired path data
valid_waypoint_data = ~isnan(data.WAYPOINT_STATUS.last_wp_north);
from_wp_n = data.WAYPOINT_STATUS.last_wp_north(valid_waypoint_data);
from_wp_e = data.WAYPOINT_STATUS.last_wp_east(valid_waypoint_data);
to_wp_n = data.WAYPOINT_STATUS.next_wp_north(valid_waypoint_data);
to_wp_e = data.WAYPOINT_STATUS.next_wp_east(valid_waypoint_data);
waypoint_time = timestampsFromZero(valid_waypoint_data);
fwaypoint_n_with_pos = interp1(waypoint_time, from_wp_n, pos_time, 'nearest'); % Nearest-neighbor matching is done becuase waypoints are actually discrete values, just represented as real numbers.
fwaypoint_e_with_pos = interp1(waypoint_time, from_wp_e, pos_time, 'nearest');
twaypoint_n_with_pos = interp1(waypoint_time, to_wp_n, pos_time, 'nearest');
twaypoint_e_with_pos = interp1(waypoint_time, to_wp_e, pos_time, 'nearest');
clear valid_waypoint_data;

% Get the commanded rudder angle from the simulation
commanded_rudder_angle = 180/pi*interp1(command_r.time, command_r.signals.values, pos_time);

% Also grab actual and commanded rudder angle and L2+ vector data
valid_basic_state_data = ~isnan(data.BASIC_STATE.rudder_angle);
basic_state_time = timestampsFromZero(valid_basic_state_data);
[basic_state_time, valid_basic_state_data2] = unique(basic_state_time);
clear tmp;
if isfield(data.BASIC_STATE, 'commanded_auto_rudder_angle')
    act_rudder_angle = data.BASIC_STATE.commanded_auto_rudder_angle(valid_basic_state_data);
else
    act_rudder_angle = data.BASIC_STATE.commanded_rudder_angle(valid_basic_state_data);
end
act_rudder_angle = 180/pi*interp1(basic_state_time, act_rudder_angle(valid_basic_state_data2), pos_time);
l2_north = data.BASIC_STATE.L2_north(valid_basic_state_data);
l2_north = interp1(basic_state_time, l2_north(valid_basic_state_data2), pos_time);
l2_east = data.BASIC_STATE.L2_east(valid_basic_state_data);
l2_east = interp1(basic_state_time, l2_east(valid_basic_state_data2), pos_time);
clear valid_basic_state_data;

% And finally course-over-ground data
valid_gps_data = ~isnan(data.GPS_RAW_INT.lat) & data.GPS_RAW_INT.fix_type >= 2 & data.GPS_RAW_INT.lat ~= 0 & data.GPS_RAW_INT.lon ~= 0;
gps_time = timestampsFromZero(valid_gps_data);
[gps_time, i] = unique(gps_time);
cog = unwrap(data.GPS_RAW_INT.cog(valid_gps_data) / 100 * pi / 180);
cog = cog(i);
cog = interp1(gps_time, cog, pos_time, 'nearest'); % Convert from centidegrees to radians
%cog = wrap(cog); % Wrap it back into the range [0..2*pi]
clear valid_gps_data gps_time;

% And water velocity (m/s) from DST800 @ 2Hz for the primary node.
valid_water_speed_data = ~isnan(data.DST800.speed);
water_speed_time = timestampsFromZero(valid_water_speed_data);
water_speed = data.DST800.speed(valid_water_speed_data);
water_speed = interp1(water_speed_time, water_speed, pos_time);
water_vel_x = water_speed .* cos(cog);
water_vel_y = water_speed .* sin(cog);
clear valid_water_speed_data water_speed_time;

% Also calculate the crosstrack error.
% This is done via simple vector projection using the vector from the start
% waypoint to the boat position and the vector from the start waypoint to
% the next waypoint.
all_wp_to_boat = [y - fwaypoint_e_with_pos x - fwaypoint_n_with_pos];
all_wp_to_wp = [twaypoint_e_with_pos twaypoint_n_with_pos] - [fwaypoint_e_with_pos fwaypoint_n_with_pos];
all_wp_to_wp_norm = sqrt(sum(all_wp_to_wp.^2,2));
all_wp_to_wp_unit = [all_wp_to_wp(:,1) ./ all_wp_to_wp_norm all_wp_to_wp(:,2) ./ all_wp_to_wp_norm];
scaling_factor = dot(all_wp_to_boat, all_wp_to_wp,2) ./ all_wp_to_wp_norm;
all_alongtrack = [all_wp_to_wp_unit(:,1) .* scaling_factor all_wp_to_wp_unit(:,2) .* scaling_factor];
crosstrack_vector = all_wp_to_boat - all_alongtrack;
crosstrack_error = sqrt(sum(crosstrack_vector.^2,2));
clear all_wp_to_boat all_wp_to_wp all_wp_to_wp_norm all_wp_to_wp_unit scaling_factor all_alongtrack;

% Calculate the heading error.
all_wp_to_wp = [twaypoint_e_with_pos twaypoint_n_with_pos] - [fwaypoint_e_with_pos fwaypoint_n_with_pos];
desired_heading = atan2_to_norm_angle(atan2(all_wp_to_wp(:,2), all_wp_to_wp(:,1)));
heading_error = 180/pi*(desired_heading - cog);

%% Animate (use static_plots to determine run to use)

% Get the coordinates for icons for the boat and rudder
icon_coords;

% Finally plot everything for the first timepoint
f = figure;
positionAxis = subplot(3,2,[1 3 5]);
axis(positionAxis, 'equal');
hold(positionAxis, 'on');
rudderAxis = subplot(3,2,2);
hold(rudderAxis, 'on');
title(rudderAxis, 'Rudder');
crosstrackErrorAxis = subplot(3,2,4);
hold(crosstrackErrorAxis, 'on');
set(crosstrackErrorAxis, 'xticklabel', []);
title(crosstrackErrorAxis, 'Crosstrack Error (m)');
headingErrorAxis = subplot(3,2,6);
hold(headingErrorAxis, 'on');
set(headingErrorAxis, 'xticklabel', []);
title(headingErrorAxis, 'Heading error');

% Keep the positionAxis current, necessary for patch()
axes(positionAxis);

% Plot the boat position as a dot trail
boat_pos = plot(positionAxis, y(valid_range(1)), x(valid_range(1)), '.', 'MarkerSize', 15);

% First calculate the position of the boat at all points during this range
boat_rotmat = rotmat2(-cog(valid_range(1)));
boat_coords_rot = boat_coords;
for i = 1:length(boat_coords_rot)
    boat_coords_rot(i,:) = boat_rotmat*boat_coords_rot(i,:)';
end
boat_rotmat = rotmat2(-cog(valid_range(1)));

% And plot the rudder with the commanded rudder angle from the sim.
rudder_rotmat = rotmat2(-pi/180*commanded_rudder_angle(valid_range(1)));
rudder_coords_rot = rudder_coords;
for i = 1:length(rudder_coords_rot)
    rudder_coords_rot(i,:) = boat_rotmat*rudder_rotmat*rudder_coords_rot(i,:)';
end
rudder_sim = patch(y(valid_range(1)) + boat_coords_rot(8,1) + rudder_coords_rot(:,1), x(valid_range(1)) + boat_coords_rot(8,2) + rudder_coords_rot(:,2), 'r');

% And plot the rudder with the actual rudder angle from the launch.
rudder_rotmat = rotmat2(-pi/180*act_rudder_angle(valid_range(1)));
rudder_coords_rot = rudder_coords;
for i = 1:length(rudder_coords_rot)
    rudder_coords_rot(i,:) = boat_rotmat*rudder_rotmat*rudder_coords_rot(i,:)';
end
rudder_true = patch(y(valid_range(1)) + boat_coords_rot(8,1) + rudder_coords_rot(:,1), x(valid_range(1)) + boat_coords_rot(8,2) + rudder_coords_rot(:,2), 'y');

% And the boat itself (done after the rudder to get ordering right)
boat = patch(y(valid_range(1)) + boat_coords_rot(:,1), x(valid_range(1)) + boat_coords_rot(:,2), 'y');

% And its current ground velocity
velocity = quiver(positionAxis, y(valid_range(1)), x(valid_range(1)), vel_y(valid_range(1)), vel_x(valid_range(1)));

% And its water velocity
water_velocity = quiver(positionAxis, y(valid_range(1)), x(valid_range(1)), water_vel_y(valid_range(1)), water_vel_y(valid_range(1)));

% And the current L2+ vector
l2_vector = quiver(positionAxis, y(valid_range(1)), x(valid_range(1)), l2_north(valid_range(1)), l2_east(valid_range(1)));

% And then plot the current waypoint pairing
a = fwaypoint_n_with_pos(valid_range);
c = fwaypoint_e_with_pos(valid_range);
e = twaypoint_n_with_pos(valid_range);
g = twaypoint_e_with_pos(valid_range);
path = plot(positionAxis, [c(1) g(1)], [a(1) e(1)], '.--k');

% On the rudder plot, plot the commanded and real rudder angle
a_r_angle = plot(rudderAxis, pos_time(1), pi/180*act_rudder_angle(valid_range(1)), 'k-');
c_r_angle = plot(rudderAxis, pos_time(1), commanded_rudder_angle(valid_range(1)), '--b');
set(rudderAxis, 'YLim', [-45 45]);
set(rudderAxis, 'YTick', -45:15:45);
set(rudderAxis, 'YGrid', 'on');

% On the crosstrack error plot, plot the crosstrack error
ce = plot(crosstrackErrorAxis, pos_time(1), crosstrack_error(valid_range(1)), 'k-');
ce2 = quiver(positionAxis, y(valid_range(1)), x(valid_range(1)), -crosstrack_vector(valid_range(1),1), -crosstrack_vector(valid_range(1),2));
set(crosstrackErrorAxis, 'YLim', [0 25]);

% On the heading error plot, plot the heading error
he = plot(headingErrorAxis, pos_time(1), heading_error(valid_range(1)), 'k-');
set(headingErrorAxis, 'YLim', [-90 90]);
set(headingErrorAxis, 'YTick', -90:30:90);
set(headingErrorAxis, 'YGrid', 'on');

% And now animate this plot by updating the data for every plot element.
for i=2:length(valid_range)
    % If the user closes the window quit animating.
    if ~ishandle(f)
        return;
    end

    % Update the boat position
    set(boat_pos, 'XData', y(valid_range(1:i)), 'YData', x(valid_range(1:i)));

    % Update the boat drawing
    boat_rotmat = rotmat2(-cog(valid_range(i)));
    boat_coords_rot = boat_coords;
    for j = 1:length(boat_coords_rot)
        boat_coords_rot(j,:) = boat_rotmat*boat_coords_rot(j,:)';
    end
    set(boat, 'XData', y(valid_range(i)) + boat_coords_rot(:,1), 'YData', x(valid_range(i)) + boat_coords_rot(:,2));

    % Update the rudder drawing for the actual commanded rudder angle.
    rudder_rotmat = rotmat2(-pi/180*act_rudder_angle(valid_range(i)));
    rudder_coords_rot = rudder_coords;
    for j = 1:length(rudder_coords_rot)
        rudder_coords_rot(j,:) = boat_rotmat*rudder_rotmat*rudder_coords_rot(j,:)';
    end
    set(rudder_true, 'XData', y(valid_range(i)) + boat_coords_rot(8,1) + rudder_coords_rot(:,1), 'YData', x(valid_range(i)) + boat_coords_rot(8,2) + rudder_coords_rot(:,2));
    
    % Update the rudder drawing for the simulated commanded rudder angle.
    rudder_rotmat = rotmat2(-pi/180*commanded_rudder_angle(valid_range(i)));
    rudder_coords_rot = rudder_coords;
    for j = 1:length(rudder_coords_rot)
        rudder_coords_rot(j,:) = boat_rotmat*rudder_rotmat*rudder_coords_rot(j,:)';
    end
    set(rudder_sim, 'XData', y(valid_range(i)) + boat_coords_rot(8,1) + rudder_coords_rot(:,1), 'YData', x(valid_range(i)) + boat_coords_rot(8,2) + rudder_coords_rot(:,2));
    
    % Update the viewport, keep it centered around the vessel with 60m
    % total viewing space.
    set(positionAxis, 'XLim', [y(valid_range(i)) - 30; y(valid_range(i)) + 30], 'YLim', [x(valid_range(i)) - 30; x(valid_range(i)) + 30]);

    % Update the boat's velocity vector
    set(velocity, 'XData', y(valid_range(i)), 'YData', x(valid_range(i)), 'UData', vel_y(valid_range(i)) * 2, 'VData', vel_x(valid_range(i)) * 2);

    % Update the boat's water velocity vector
    set(water_velocity, 'XData', y(valid_range(i)), 'YData', x(valid_range(i)), 'UData', water_vel_y(valid_range(i)) * 2, 'VData', water_vel_x(valid_range(i)) * 2);

    % Update the L2+ vector
    set(l2_vector, 'XData', y(valid_range(i)), 'YData', x(valid_range(i)), 'UData', l2_east(valid_range(i)), 'VData', l2_north(valid_range(i)));

    set(ce2, 'XData', y(valid_range(i)), 'YData', x(valid_range(i)), 'UData', -crosstrack_vector(valid_range(i),1), 'VData', -crosstrack_vector(valid_range(i),2));

    % Update the waypoint track as needed
    set(path, 'XData', [c(i) g(i)], 'YData', [a(i) e(i)]);

    % Update the plot title
    title(positionAxis, sprintf('Autonomous run %d, %.0f seconds', auto_run, pos_time(valid_range(i)) - pos_time(valid_range(1))));

    % Update the rudder data
    set(a_r_angle, 'XData', pos_time(valid_range(1:i)), 'YData', commanded_rudder_angle(valid_range(1:i)));
    set(c_r_angle, 'XData', pos_time(valid_range(1:i)), 'YData', act_rudder_angle(valid_range(1:i)));

    % Update the crosstrack error
    set(ce, 'XData', pos_time(valid_range(1:i)), 'YData', crosstrack_error(valid_range(1:i)));

    % Update the heading error
    set(he, 'XData', pos_time(valid_range(1:i)), 'YData', heading_error(valid_range(1:i)));

    % And limit the data views to the last 10s of data
    set(rudderAxis, 'XLim', [pos_time(valid_range(i)) - 10; pos_time(valid_range(i))]);
    set(crosstrackErrorAxis, 'XLim', [pos_time(valid_range(i)) - 10; pos_time(valid_range(i))]);
    set(headingErrorAxis, 'XLim', [pos_time(valid_range(i)) - 10; pos_time(valid_range(i))]);

    % Pause until the next frame
    if i < length(valid_range)
        pause(.05);
    end
end