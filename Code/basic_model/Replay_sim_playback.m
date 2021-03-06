% Show an animation of the vehicle using data generated by Replay_sim.mdl
saveVideo = false; % Change this to trigger saving an AVI of the animation

% Make sure the tout variable exists, which is used for interpolating data
assert(exist('tout', 'var') == 1);

% Make sure the waypoint data exists from the simulation run
assert(exist('wp0', 'var') == 1 & exist('wp1', 'var') == 1);
fwaypoint_n_with_pos = interp1(wp0.Time, wp0.Data(:,1), tout, 'nearest'); % Nearest-neighbor matching is done becuase waypoints are actually discrete values, just represented as real numbers.
fwaypoint_e_with_pos = interp1(wp0.Time, wp0.Data(:,2), tout, 'nearest');
twaypoint_n_with_pos = interp1(wp0.Time, wp1.Data(:,1), tout, 'nearest');
twaypoint_e_with_pos = interp1(wp0.Time, wp1.Data(:,2), tout, 'nearest');

% Also grab the rudder data (actual and commanded)
assert(exist('rudder', 'var') == 1);
rudder_angle = interp1(rudder.Time, rudder.Data, tout);
assert(exist('command_r', 'var') == 1);
commanded_rudder_angle = command_r(:);

% Get position and velocity data
assert(exist('sensedPosition', 'var') == 1);
x = sensedPosition(:,1,:); % North
y = sensedPosition(:,2,:); % East
assert(exist('sensedVelocity', 'var') == 1);
vel_x = sensedVelocity(:,1,:); % North
vel_y = sensedVelocity(:,2,:); % East

% And also extract the uncorrected position
x_uncorrected = squeeze(localPosUncorrected(1,1,:));
y_uncorrected = squeeze(localPosUncorrected(1,2,:));

% L2+ vector data
%l2_north = data.BASIC_STATE.L2_north(valid_basic_state_data);
%l2_north = interp1(basic_state_time, l2_north(valid_basic_state_data2), pos_time);
%l2_east = data.BASIC_STATE.L2_east(valid_basic_state_data);
%l2_east = interp1(basic_state_time, l2_east(valid_basic_state_data2), pos_time);

% Course-over-ground data
assert(exist('cog', 'var') == 1);

% Yaw and yaw rate
assert(exist('sensedYaw', 'var') == 1);
heading = sensedYaw;
assert(exist('sensedYawRate', 'var') == 1);

% And extract water velocity
assert(exist('water_speed', 'var') == 1);
water_speed_sim = interp1(water_speed.Time, water_speed.Data, tout);
water_vel_x = water_speed_sim .* cos(sensedYaw);
water_vel_y = water_speed_sim .* sin(sensedYaw);

% Finally specify the indices that we will iterate over. Basically, just
% plot 1/10th of the total data.
anim_range = 1:10:length(tout);

%% Animate (use static_plots to determine run to use)

% Prepare for saving video
if saveVideo
    videoFileName = sprintf('replaysim-run-%f.avi', now);
    aviWriter = VideoWriter(videoFileName);
    aviWriter.FrameRate = 30;
    open(aviWriter);
end

% Get the coordinates for icons for the boat and rudder (doubling their
% size)
scale_factor = 1;
[boat_coords, rudder_coords] = icon_coords(scale_factor);

% Set whether the animation is playing or not. Setting this to true
% pauses the rendering loop.
isPaused = false;

% If a video is requested, fullscreen the video. Resizing the video
% mid-playback during recording doesn't work, so this is the only way
% to get big videos out. This must be done in the first figure() call
% and not in a separate get() call.
if saveVideo
    f = figure('WindowKeyPressFcn', @playpause, 'units', 'normalized', 'outerposition', [0 0 1 1]);
else
    f = figure('WindowKeyPressFcn', @playpause);
end

% Finally plot everything for the first timepoint
positionAxis = gca;
axis(positionAxis, 'equal');
hold(positionAxis, 'on');
viewport_size = 300;
set(positionAxis, 'XLim', [y(1) - viewport_size/2; y(1) + viewport_size/2], 'YLim', [x(1) - viewport_size/2; x(1) + viewport_size/2]);

% Keep the positionAxis current, necessary for patch()
axes(positionAxis);

% First calculate the position of the boat at all points during this range
boat_rotmat = rotmat2(-heading((1)));
boat_coords_rot = boat_coords;
for i = 1:length(boat_coords_rot)
    boat_coords_rot(i,:) = boat_rotmat*boat_coords_rot(i,:)';
end
boat_rotmat = rotmat2(-heading((1)));

% And plot the rudder angle
rudder_rotmat = rotmat2(-rudder_angle((1)));
rudder_coords_rot = rudder_coords;
for i = 1:length(rudder_coords_rot)
    rudder_coords_rot(i,:) = boat_rotmat*rudder_rotmat*rudder_coords_rot(i,:)';
end
rudder_patch = patch(y(1) + boat_coords_rot(8,1) + rudder_coords_rot(:,1), x(1) + boat_coords_rot(8,2) + rudder_coords_rot(:,2), 'y');

% And the boat itself (done after the rudder to get ordering right)
boat_patch = patch(y(1) + boat_coords_rot(:,1), x((1)) + boat_coords_rot(:,2), 'y');

% Plot the boat position as a dot trail
boat_pos_plot = plot(positionAxis, y(1), x(1), '.', 'MarkerSize', 15);

% And its current ground velocity
velocity = quiver(positionAxis, y(1), x(1), vel_y(1), vel_x(1), 'r');

% And its water velocity
water_velocity_quiver = quiver(positionAxis, y(1), x((1)), water_vel_y((1)), water_vel_y(1), 'g');

% And the current L2+ vector
%l2_vector = quiver(positionAxis, y(1), x(1), l2_north(1), l2_east(1), 'c');

% And the induced circular velocity from the GPS offset, if correcting this
% has been enabled. Also plot the GPS sensed position as a reference
if GpsOffsetCorrectionEnable.Value ~= 0
    gps_offset_quiver = quiver(positionAxis, y(1) + scale_factor*gpsPosOffset(1,2), x(1) + scale_factor*gpsPosOffset(1,1), gpsVelOffset(1,2,1), gpsVelOffset(1,1,1), 'r');
    boat_pos_uncor_plot = plot(positionAxis, y_uncorrected(1), x_uncorrected(1), 'r.', 'MarkerSize', 15);
end

% And then plot the current waypoint pairing
a = fwaypoint_n_with_pos(anim_range);
c = fwaypoint_e_with_pos(anim_range);
e = twaypoint_n_with_pos(anim_range);
g = twaypoint_e_with_pos(anim_range);
path = plot(positionAxis, [c(1) g(1)], [a(1) e(1)], '.--k');

% On the rudder plot, plot the commanded and real rudder angle
%r_angle = plot(rudderAxis, pos_time(1), pi/180*rudder_angle(anim_range(1)), 'k-');
%c_r_angle = plot(rudderAxis, pos_time(1), commanded_rudder_angle(anim_range(1)), '--b');
%set(rudderAxis, 'YLim', [-45 45]);
%set(rudderAxis, 'YTick', -45:15:45);
%set(rudderAxis, 'YGrid', 'on');

% Save this frame to our video.
if saveVideo
    currentFrame = getframe(f);
    writeVideo(aviWriter, currentFrame);
end

% And now animate this plot by updating the data for every plot element.
for i=2:length(anim_range)
    % If the user closes the window quit animating.
    if ~ishandle(f)
        return;
    end

    % Wait if the animation is paused
    while isPaused
        if ~ishandle(f)
            return;
        end
        pause(0.1)
    end

    % Update the boat position
    set(boat_pos_plot, 'XData', y(anim_range(1:i)), 'YData', x(anim_range(1:i)));

    % Update the boat drawing
    boat_rotmat = rotmat2(-heading(anim_range(i)));
    boat_coords_rot = boat_coords;
    for j = 1:length(boat_coords_rot)
        boat_coords_rot(j,:) = boat_rotmat*boat_coords_rot(j,:)';
    end
    set(boat_patch, 'XData', y(anim_range(i)) + boat_coords_rot(:,1), 'YData', x(anim_range(i)) + boat_coords_rot(:,2));

    % Update the rudder drawing
    rudder_rotmat = rotmat2(-rudder_angle(anim_range(i)));
    rudder_coords_rot = rudder_coords;
    for j = 1:length(rudder_coords_rot)
        rudder_coords_rot(j,:) = boat_rotmat*rudder_rotmat*rudder_coords_rot(j,:)';
    end
    set(rudder_patch, 'XData', y(anim_range(i)) + boat_coords_rot(8,1) + rudder_coords_rot(:,1), 'YData', x(anim_range(i)) + boat_coords_rot(8,2) + rudder_coords_rot(:,2));
    
    % Update the viewport, keep it centered around the vessel with 60m
    % total viewing space.
    set(positionAxis, 'XLim', [y(anim_range(i)) - viewport_size/2; y(anim_range(i)) + viewport_size/2], 'YLim', [x(anim_range(i)) - viewport_size/2; x(anim_range(i)) + viewport_size/2]);

    % Update the boat's velocity vector
    set(velocity, 'XData', y(anim_range(i)), 'YData', x(anim_range(i)), 'UData', vel_y(anim_range(i)) * 2, 'VData', vel_x(anim_range(i)) * 2);

    % Update the boat's water velocity vector
    set(water_velocity_quiver, 'XData', y(anim_range(i)), 'YData', x(anim_range(i)), 'UData', water_vel_y(anim_range(i)) * 2, 'VData', water_vel_x(anim_range(i)) * 2);

    % Update the L2+ vector
    %set(l2_vector, 'XData', y(anim_range(i)), 'YData', x(anim_range(i)), 'UData', l2_east(anim_range(i)), 'VData', l2_north(anim_range(i)));

    % Update the waypoint track as needed
    set(path, 'XData', [c(i) g(i)], 'YData', [a(i) e(i)]);

    % Update the induced sensor velocity and sensor position
    if GpsOffsetCorrectionEnable.Value ~= 0
        set(gps_offset_quiver, 'XData', y(anim_range(i)) + scale_factor*gpsPosOffset(anim_range(i),2), 'YData', x(anim_range(i)) + scale_factor*gpsPosOffset(anim_range(i),1), 'UData', gpsVelOffset(1,2,anim_range(i)), 'VData', gpsVelOffset(1,1,anim_range(i)));
        
        set(boat_pos_uncor_plot, 'XData', y_uncorrected(anim_range(1:i)), 'YData', x_uncorrected(anim_range(1:i)));
    end

    % Update the crosstrack error plot
    %set(ce2, 'XData', y(anim_range(i)), 'YData', x(anim_range(i)), 'UData', -crosstrack_vector(i,1), 'VData', -crosstrack_vector(i,2));

    % Update the waypoint track as needed
    %set(path, 'XData', [c(anim_range(i)) g(anim_range(i))], 'YData', [a(anim_range(i)) e(anim_range(i))]);

    % Update the plot title
    title(positionAxis, sprintf('Autonomous run %d, %.0f seconds\ngreen=v_{water},red=v_{ground},blue=err_{ct},cyan=L1\\_vector', auto_run, tout(anim_range(i))));

    % Update the rudder data
    %set(r_angle, 'XData', tout(anim_range(1:i)), 'YData', rudder_angle(anim_range(1:i)));
    %set(c_r_angle, 'XData', tout(anim_range(1:i)), 'YData', commanded_rudder_angle(anim_range(1:i)));

    % Update the crosstrack error
    %set(ce, 'XData', pos_time(anim_range(1:i)), 'YData', crosstrack_error(anim_range(1:i)));

    % Update the heading error
    %set(he, 'XData', pos_time(anim_range(1:i)), 'YData', heading_error(anim_range(1:i)));

    % And limit the data views to the last 10s of data
    %set(rudderAxis, 'XLim', [pos_time(anim_range(i)) - 10; pos_time(anim_range(i))]);
    %set(crosstrackErrorAxis, 'XLim', [pos_time(anim_range(i)) - 10; pos_time(anim_range(i))]);
    %set(headingErrorAxis, 'XLim', [pos_time(anim_range(i)) - 10; pos_time(anim_range(i))]);

    % Save this frame to our video.
    if saveVideo
        currentFrame = getframe(f);
        writeVideo(aviWriter, currentFrame);

    % Pause until the next frame
    else
        if i < length(anim_range)
            pause(T_step * 10);
        end
    end
end