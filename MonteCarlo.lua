local PASS		= 0
local BLOCK		= 1
local START		= 2
local FINISH	= 3

local SPEED_MAX				= 4
local SPEED_STATES		= (SPEED_MAX + 1) * (SPEED_MAX + 1)
local SPEED_DIFF			= 1
local SPEED_SIZE			= 2 * SPEED_DIFF + 1
-- e.g.
-- (-1, -1) (0, -1) (+1, +1)
-- (-1, 0)  (0, 0)  (+1, 0)
-- (-1, +1) (0, +1) (+1, +1)
local ACTIONS				= SPEED_SIZE * SPEED_SIZE

local ZERO_SPEED_CHANCE	= 0.1

local s_Track1 =
{
	"*******************",
	"****             F*",
	"***              F*",
	"***              F*",
	"**               F*",
	"*                F*",
	"*                F*",
	"*          ********",
	"*         *********",
	"*         *********",
	"*         *********",
	"*         *********",
	"*         *********",
	"*         *********",
	"*         *********",
	"**        *********",
	"**        *********",
	"**        *********",
	"**        *********",
	"**        *********",
	"**        *********",
	"**        *********",
	"**        *********",
	"***       *********",
	"***       *********",
	"***       *********",
	"***       *********",
	"***       *********",
	"***       *********",
	"***       *********",
	"****      *********",
	"****      *********",
	"****SSSSSS*********",
	"*******************",
}

local s_Track2 =
{
	"**********************************",
	"*****************               F*",
	"**************                  F*",
	"*************                   F*",
	"************                    F*",
	"************                    F*",
	"************                    F*",
	"************                    F*",
	"*************                   F*",
	"**************                  F*",
	"***************                ***",
	"***************             ******",
	"***************            *******",
	"***************          *********",
	"***************         **********",
	"**************          **********",
	"*************           **********",
	"************            **********",
	"***********             **********",
	"**********              **********",
	"*********               **********",
	"********                **********",
	"*******                 **********",
	"******                  **********",
	"*****                   **********",
	"****                    **********",
	"***                     **********",
	"**                      **********",
	"*                       **********",
	"*                       **********",
	"*SSSSSSSSSSSSSSSSSSSSSSS**********",
	"**********************************",
}

local s_Track3 =
{
	"******",
	"*   F*",
	"*   F*",
	"*   **",
	"*SS***",
	"******",
}

local s_Track4 =
{
	"****",
	"*FF*",
	"*  *",
	"*SS*",
	"****",
}

local CHAR_TO_VALUE =
{
	["*"] = BLOCK,
	["F"] = FINISH,
	["S"] = START,
	[" "] = PASS,
}

local VALUE_TO_CHAR =
{
	[BLOCK] = "*",
	[FINISH] = "F",
	[START] = "S",
	[PASS] = " ",
}



local function GetMinSteps(a, b)
    local delta = b - a
    
    local steps
    if delta == 0 then
      steps = 0
    elseif delta <= 1 then
      steps = 1
    elseif delta <= 3 then
      steps = 2
    elseif delta <= 6 then
      steps = 3
    else
      steps = 3 + (delta - 7) // 4 + 1
    end
  
    return steps
end

local function TrackToGrid(track)
	local grid = {size_y = #track, size_x = #track[1]}
  grid.size = grid.size_x * grid.size_y
	for i = 1, #track do
		grid[i] = {}
		local s = track[i]
		assert(#s == grid.size_x)
		for k = 1, #s do
			local ch = string.sub(s, k, k)
			local tile = CHAR_TO_VALUE[ch]
			grid[i][k] = tile
		end
	end
	
	return grid
end

local function ActionToSpeed(action)
	local speed_x = (action - 1) % SPEED_SIZE
	local speed_y = (action - 1) // SPEED_SIZE
	
	return speed_x - SPEED_DIFF, speed_y - SPEED_DIFF
end

local function SpeedToAction(speed_x, speed_y)
	return (speed_y + SPEED_DIFF) * SPEED_SIZE + (speed_x + SPEED_DIFF) + 1
end

local function SpeedToComponents(speed)
	local speed_x = speed % (SPEED_MAX + 1)
	local speed_y = speed // (SPEED_MAX + 1)
	
	return speed_x, speed_y
end

local function ComponentsToSpeed(speed_x, speed_y)
	return speed_y * (SPEED_MAX + 1) + speed_x
end

local function CoordSpeedToState(policy, row, col, speed)
	return speed * policy.size + (row - 1) * policy.size_x + (col - 1) + 1
end

local function StateToCoordSpeed(policy, state)
	state = state - 1
	local speed = state // policy.size
	state = state - speed * policy.size
	return state // policy.size_x + 1, state % policy.size_x + 1, speed
end

local function IsSpeedActionValid(speed, action, speed_x, speed_y)
    if not speed_x or not speed_y then
      assert(speed)
      speed_x, speed_y = SpeedToComponents(speed)
    end
    
    local action_x, action_y = ActionToSpeed(action)    
    speed_x = speed_x + action_x
    speed_y = speed_y + action_y
    
    if (speed_x < 0) or (speed_x > SPEED_MAX) or (speed_y < 0) or (speed_y > SPEED_MAX) then
      return false
    end
    
    return speed_x + speed_y > 0
end

local function GetAvailableActions(speed)
  local speed_x, speed_y = SpeedToComponents(speed)
  
  local actions = {}
  for action = 1, ACTIONS do
      if IsSpeedActionValid(nil, action, speed_x, speed_y) then
        table.insert(actions, action)
      end
  end

  return actions
end

local function GenerateRandomPolicy(track, epsilon_soft)
	local policy =
	{
		size = track.size,
		size_x = track.size_x,
		size_y = track.size_y,
		epsilon_soft = epsilon_soft,
    state_actions = {}
	}
	policy.states = policy.size * SPEED_STATES
	policy.start_states, policy.finish_states = {}, {}
  
  local marked = {}
	for s = 1, policy.states do
		local row, col, speed = StateToCoordSpeed(policy, s)
		local tile = track[row][col]
		if tile == PASS or tile == START then
      local actions = GetAvailableActions(speed)
      policy.state_actions[s] = actions
			policy[s] = actions[math.random(1, #actions)]
			if tile == START and speed == 0 then
				table.insert(policy.start_states, s)
			end
		end
    if tile == FINISH then
        table.insert(policy.finish_states, s)
        local goal = CoordSpeedToState(policy, row, col, ComponentsToSpeed(0, 0))
        if not marked[goal] then
          marked[goal] = true
          table.insert(marked, goal)
        end
    end
	end
  
  for _, start in ipairs(policy.start_states) do
    local start_row, start_col = StateToCoordSpeed(policy, start)
    for _, goal in ipairs(marked) do
      local goal_row, goal_col = StateToCoordSpeed(policy, goal)
      local row_steps = GetMinSteps(goal_row, start_row)
      local col_steps = GetMinSteps(start_col, goal_col)
      local steps = row_steps > col_steps and row_steps or col_steps
      policy.best_steps = ((not policy.best_steps) or (policy.best_steps > steps)) and steps or policy.best_steps
    end
  end
	
	return policy
end

local function GetPolicyRandomStartState(policy)
	return policy.start_states[math.random(1, #policy.start_states)]
end

local function SpeedToStr(speed_x, speed_y)
	return string.format("(%s%d,%s%d)",
		(speed_x == 0) and " " or (speed_x > 0 and "+" or ""), speed_x,
		(speed_y == 0) and " " or (speed_y > 0 and "+" or ""), speed_y)
end

local function PrintPolicy(policy, track, max_speed)
  local col_width = 9
  local speed_width = policy.size_x * col_width
  
	for speed_y = 0, (max_speed or SPEED_MAX) do
    local str = ""
    for speed_x = 0, (max_speed or SPEED_MAX) do
      local speed = ComponentsToSpeed(speed_x, speed_y)
      local speed_str = string.format("Speed layer %02d(%d,%d)", speed, speed_x, speed_y)
      str = str .. speed_str .. string.rep(" ", speed_width - #speed_str, "")
    end
    print(str)
    for row = 1, policy.size_y do
      str = ""
      for speed_x = 0, (max_speed or SPEED_MAX) do
        local speed = ComponentsToSpeed(speed_x, speed_y)
        for col = 1, policy.size_x do
          local s = CoordSpeedToState(policy, row, col, speed)
          local action = policy[s]
          if action then
            local speed_x, speed_y = ActionToSpeed(action)
            str = str .. " " .. SpeedToStr(speed_x, speed_y) .. " "
          else
            str = str .. " " .. string.rep(VALUE_TO_CHAR[track[row][col]], 7, "") .. " "    -- 7 is '(+x,-y)' length
          end
        end
      end
      print(str)
    end
	end
end

local function PrintStateActionValueFunction(policy, track, Q, max_speed)
  local col_width = 11
  local speed_width = policy.size_x * col_width
  
	for speed_y = 0, (max_speed or SPEED_MAX) do
    local str = ""
    for speed_x = 0, (max_speed or SPEED_MAX) do
      local speed = ComponentsToSpeed(speed_x, speed_y)
      local speed_str = string.format("Speed layer %02d(%d,%d)", speed, speed_x, speed_y)
      str = str .. speed_str .. string.rep(" ", speed_width - #speed_str, "")
    end
    print(str)
    for row = 1, policy.size_y do
      str = ""
      for speed_x = 0, (max_speed or SPEED_MAX) do
        local speed = ComponentsToSpeed(speed_x, speed_y)
        for col = 1, policy.size_x do
          local s = CoordSpeedToState(policy, row, col, speed)
          local action = policy[s]
          if action then
            str = str .. string.format(" %+08.2f ", Q[s][action])
          else
            str = str .. " " .. string.rep(VALUE_TO_CHAR[track[row][col]], 8, "") .. " "
          end
        end
      end
      print(str)
    end
	end
end

local function PrintEpisode(policy, episode)
  print("Episode ", step, ", Len: ", #episode)
  for i = 1, #episode do
      local s, a = episode[i].s, episode[i].a
      local row, col, speed = StateToCoordSpeed(policy, s)
      local speed_x, speed_y = SpeedToComponents(speed)
      local action_x, action_y = ActionToSpeed(a or 5)
      print(string.format("#%d: %d=[%d,%d]@(%d,%d) + (%d, %d)", i, s, row, col, speed_x, speed_y, action_x, action_y))
  end
end

local function FindFirstCrossTile(col, row, speed_x, speed_y, track)
  if speed_x == 0 and speed_y == 0 then
      return track[row][col], row, col
  end

	-- Bresenham's algorithm for the 1st octant only
	if speed_x > speed_y then
		local err, y = 0, 0
		for x = 0, speed_x do
			local tile = track[row - y][col + x]
			if tile ~= PASS and tile ~= START then
				return tile, row - y, col + x
			end
			if 2 * (err + speed_y) < speed_x then
				err = err + speed_y
			else
				err = err + speed_y - speed_x
				y = (x < speed_x) and (y + 1) or y   -- stay on the last pixel for the assert below not to trigger
			end
		end
    if y ~= speed_y then
      assert(y == speed_y)
    end
	else
		local err, x = 0, 0
		for y = 0, speed_y do
			local tile = track[row - y][col + x]
			if tile ~= PASS and tile ~= START then
				return tile, row - y, col + x
			end
			if 2 * (err + speed_x) < speed_y then
				err = err + speed_x
			else
				err = err + speed_x - speed_y
				x = (y < speed_y) and (x + 1) or x    -- stay on the last pixel for the assert below not to trigger
			end
		end
    if x ~= speed_x then
      assert(x == speed_x)
    end
	end
  
  return track[row - speed_y][col + speed_x], row - speed_y, col + speed_x
end

local function RacePolicy(s, policy, track, zero_speed_chance, max_time)
	local episode = {}
	while (not max_time) or (#episode < max_time) do
		local action
		if policy.epsilon_soft then
			if math.random() < 1.0 - policy.epsilon_soft then
				action = policy[s]
			else
        local actions = policy.state_actions[s]
				action = actions[math.random(1, #actions)]
			end
		else
			action = policy[s]
			if type(action) == "table" then
				action = action[math.random(1, #action)]
			end
		end
		table.insert(episode, { s = s, a = action })
		local action_x, action_y = ActionToSpeed(action)
		if math.random() < zero_speed_chance then
			action_x, action_y = 0, 0
		end
		local row, col, speed = StateToCoordSpeed(policy, s)
		local speed_x, speed_y = SpeedToComponents(speed)
    --print(string.format("#%d->%d,%d(%d,%d): [%d,%d]@(%d,%d)", #episode, s, action, action_x, action_y, row, col, speed_x, speed_y))
		speed_x = speed_x + action_x
		speed_y = speed_y + action_y
		local tile, new_row, new_col = FindFirstCrossTile(col, row, speed_x, speed_y, track)
		if tile == FINISH then
			-- finish the race
			table.insert(episode, { s = CoordSpeedToState(policy, new_row, new_col, ComponentsToSpeed(0, 0)) })
			break
		elseif tile == BLOCK then
			-- restart at random start tile
      --print("restart")
			s = GetPolicyRandomStartState(policy)
    else
      speed = ComponentsToSpeed(speed_x, speed_y)
      s = CoordSpeedToState(policy, new_row, new_col, speed)
		end
    --row,col,speed = StateToCoordSpeed(policy, s) speed_x,speed_y = SpeedToComponents(speed) print(string.format("   --> %d[%d,%d]@(%d,%d)", s, row, col, speed_x, speed_y))
	end
	
	return episode
end

local function GenerateEpisode(s, policy, track, max_time)
	return RacePolicy(s, policy, track, ZERO_SPEED_CHANCE, max_time)
end

local function TestPolicy(policy, track, tests, max_time)
	local shortest_episode
  local total_score = 0.0
	for i = 1, tests do
		local s = GetPolicyRandomStartState(policy)
		local episode = GenerateEpisode(s, policy, track, max_time)
    local ep_len = #episode - 1
    if not shortest_episode or ep_len < #shortest_episode then
        shortest_episode = episode
    end
    local G = -ep_len
		total_score = total_score + G
	end
	
	return total_score / tests, shortest_episode
end

local function GetMaxQAction(policy, s, Q)
    local actions = policy.state_actions[s]
    local max_action, max_Q
    for _, action in ipairs(actions) do
        if (not max_action) or (max_Q < Q[action]) then
            max_action = action
            max_Q = Q[action]
        end
    end
    
    return max_action
end

local function MonteCarloOffPolicy(track, eps_soft, threshold, max_steps, max_no_improv_steps)
	local policy = GenerateRandomPolicy(track)
  local Q, C = {}, {}
	for s = 1, track.size * SPEED_STATES do
		Q[s], C[s] = {}, {}
    if policy.state_actions[s] then
      for _, a in ipairs(policy.state_actions[s]) do
        Q[s][a] = -100.0
        C[s][a] = 0.0
      end
    end
	end
	
	local ep_min, ep_max, ep_total_len
  local ep_min_last, ep_max_last, ep_total_len_last
  local shortest_episode
  local step, no_improv_steps = 0, 0
	while step < max_steps and no_improv_steps < max_no_improv_steps do
		step = step + 1
		-- random behavior policy
		local behavior = GenerateRandomPolicy(track, eps_soft)
		
		local s = GetPolicyRandomStartState(behavior)
		local episode = GenerateEpisode(s, behavior, track, 5000000)
    local ep_len = #episode
    if not shortest_episode or ep_len < #shortest_episode then
        shortest_episode = episode
    end
    if not ep_min then
      ep_min, ep_max, ep_total_len = ep_len, ep_len, ep_len * 1.0
    end
    ep_min = (ep_len < ep_min) and ep_len or ep_min
    ep_max = (ep_len > ep_max) and ep_len or ep_max
    ep_total_len = ep_total_len + #episode
    if not ep_min_last then
      ep_min_last, ep_max_last, ep_total_len_last = ep_len, ep_len, ep_len * 1.0
    end
    ep_min_last = (ep_len < ep_min_last) and ep_len or ep_min_last
    ep_max_last = (ep_len > ep_max_last) and ep_len or ep_max_last
    ep_total_len_last = ep_total_len_last + #episode
    --PrintEpisode(policy, episode)
		local G = 0.0
		local W = 1.0
		local changed = false
		for i = ep_len - 1, 1, -1 do
			G = G - 1.0		-- no discounting, each step reward is -1, otherwise G = gamma * G + Rt
			local s, a = episode[i].s, episode[i].a
			C[s][a] = C[s][a] + W
			Q[s][a] = Q[s][a] + W * (G - Q[s][a]) / C[s][a]
			local old_a = policy[s]
			policy[s] = GetMaxQAction(policy, s, Q[s])
			changed = changed or (policy[s] ~= old_a)
			if policy[s] ~= a then break end
   		local prob = behavior.epsilon_soft / (#policy.state_actions[s])
			local b = (behavior[s] == a) and (1.0 - behavior.epsilon_soft + prob) or prob
			W = W / b
		end
		if changed then
			no_improv_steps = 0
		else
			no_improv_steps = no_improv_steps + 1
		end
    local delta
    for _, s in ipairs(policy.start_states) do
      local diff = math.abs(Q[s][policy[s]] + policy.best_steps)
      delta = ((not delta) or (diff > delta)) and diff or delta
    end
    local stats = 100
		if step % stats == 0 then
      local performance = TestPolicy(policy, track, 20, 1000)
			print(string.format("#%d, No improvement steps: %d, Episode min/max/avg[last]: %d/%d/%.2f[%d/%d/%.2f], Best Steps: %d, Delta: %.2f, Performace: %.2f", step, no_improv_steps, ep_min, ep_max, ep_total_len / step, ep_min_last, ep_max_last, ep_total_len_last / stats, policy.best_steps, delta, performance))
      ep_min_last, ep_max_last, ep_total_len_last = nil, nil, nil
			--PrintPolicy(policy, track, 2)
			--PrintStateActionValueFunction(policy, track, Q, 2)
		end
    if delta < threshold then break end
	end
	
	return policy, step, Q, shortest_episode
end

function RunRaceTrack()
	local track1 = TrackToGrid(s_Track1)
	local track2 = TrackToGrid(s_Track2)
	local track3 = TrackToGrid(s_Track3)
	local track4 = TrackToGrid(s_Track4)
  
 	local track = track4

  local policy, steps, Q, shortest_MC = MonteCarloOffPolicy(track, 0.1, 0.001, 100000, 20000)
  print(string.format("Finished in %d steps", steps))
  PrintPolicy(policy, track, 0)
  PrintStateActionValueFunction(policy, track, Q, 0)
	
  local rand_policy = GenerateRandomPolicy(track)
  local rand_result = TestPolicy(rand_policy, track, 10000, 1000)
  print(string.format("Random policy result: %.2f", rand_result))
  
  local eps_soft_policy = GenerateRandomPolicy(track, 0.1)
  local eps_soft_policy_result, shortest_policy = TestPolicy(eps_soft_policy, track, 10000, 1000)
  print(string.format("Epsilon soft policy result: %.2f", eps_soft_policy_result))
  
  local result = TestPolicy(policy, track, 10000, 1000)
  print(string.format("Policy policy result: %.2f", result))
  
  print("Shortest episode by Policy")
  PrintEpisode(policy, shortest_policy)
  print("Shortest episode by Monte Carlo Control")
  PrintEpisode(policy, shortest_MC)
end

RunRaceTrack()