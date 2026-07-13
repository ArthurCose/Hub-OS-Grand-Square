local function debug_print(...)
  -- local s = ""
  -- for _, value in ipairs({ ... }) do
  --   s = s .. tostring(value)
  -- end
  -- print(s)
end

---@class BattleArena._TrackedPlayer
---@field id Net.ActorId
---@field area string
---@field x number
---@field y number
---@field z number
---@field arena? BattleArena
---@field team_range BattleArena.TeamRange?

---@type BattleArena._TrackedPlayer[]
local tracked_players = {}

---@class BattleArena.Range
---@field x number
---@field y number
---@field z number
---@field w number
---@field h number

---@param x number
---@param y number
---@param z number
---@param range BattleArena.Range
local function overlaps_range(x, y, z, range)
  return
      x >= range.x and
      x <= range.x + range.w and
      y >= range.y and
      y <= range.y + range.h and
      z >= range.z and
      z < range.z + 1
end

---@param x number
---@param y number
---@param range BattleArena.Range
local function overlaps_range_column(x, y, range)
  return
      x >= range.x and
      x <= range.x + range.w and
      y >= range.y and
      y <= range.y + range.h
end

---@class BattleArena.TeamRange: BattleArena.Range
---@field team string the name of this team, encounters see { teams = { team, player_count }[] } in the encounter data field
---@field face_direction Direction the direction for player overworld sprites to face when battle starts

---@class BattleArena.Options: BattleArena.Range
---@field area_id string
---@field encounter_path string
---@field pve? boolean when enabled, battle can start if there's at least one player in any required team, otherwise each team requires at least one player
---@field min_players? number default is 1, only checks required teams
---@field team_ranges? BattleArena.TeamRange[] creates a "red" team on the left and "blue" team on the right by default
---@field required_teams? string[] all teams are required by default

---@class BattleArena
---@field area_id string
---@field events Net.EventEmitter "battle_start" - called just before initiating netplay, "eject_player" { player_id, x, y, z, team_range }, "battle_results" [battle_results](https://docs.hubos.dev/server/lua-api/events#battle_results).
---@field detection_range BattleArena.Range
---@field team_ranges BattleArena.TeamRange[]
---@field teams table<string, Net.ActorId[]>
---@field package required_teams string[]
---@field package pve? boolean
---@field package min_players number
---@field package encounter_path string
---@field package fight_active boolean
---@field package locked_players table<Net.ActorId, boolean>
---@field package countdown_bots Net.ActorId[]
---@field package cancel_countdown_callback? function
local BattleArena = {}
BattleArena.__index = BattleArena

local Lib = {
  COUNTDOWN_TEXTURE_PATH = "/server/assets/bots/pvp_countdown.png",
  COUNTDOWN_ANIMATION_PATH = "/server/assets/bots/pvp_countdown.animation"
}

---@type table<string, BattleArena[]>
local arenas_by_area = {}

---@param options BattleArena.Options
---@return BattleArena
---Creates and tracks an arena
function Lib.create_arena(area_id, options)
  local countdown_bots = {}

  local function create_countdown_bot(x, y)
    countdown_bots[#countdown_bots + 1] = Net.create_bot({
      area_id = area_id,
      warp_in = false,
      texture_path = Lib.COUNTDOWN_TEXTURE_PATH,
      animation_path = Lib.COUNTDOWN_ANIMATION_PATH,
      solid = false,
      x = x,
      y = y,
      z = options.z
    })
  end

  local x, y, z = options.x, options.y, options.z
  local w, h = options.w, options.h

  create_countdown_bot(x, y)
  create_countdown_bot(x + w, y)
  create_countdown_bot(x, y + h)
  create_countdown_bot(x + w, y + h)

  ---@type BattleArena.TeamRange[]
  local team_ranges = options.team_ranges or {
    {
      team = "red",
      face_direction = "DOWN RIGHT",
      x = x,
      y = y,
      z = z,
      w = w / 2,
      h = h
    },
    {
      team = "blue",
      face_direction = "UP LEFT",
      x = x + w / 2,
      y = y,
      z = z,
      w = w / 2,
      h = h
    }
  }

  -- resolve required teams
  local required_teams = options.required_teams

  if not required_teams then
    --- require all teams
    required_teams = {}

    for _, team_range in ipairs(team_ranges) do
      required_teams[#required_teams + 1] = team_range.team
    end
  end

  -- resolve detection range
  local first_range = team_ranges[1]
  local min_x, min_y = first_range.x, first_range.y
  local max_x, max_y = first_range.x + first_range.w, first_range.y + first_range.h

  for i = 2, #team_ranges do
    local team_range = team_ranges[i]
    min_x = math.min(min_x, team_range.x)
    min_y = math.min(min_y, team_range.y)
    max_x = math.max(max_x, team_range.x + team_range.w)
    max_y = math.max(max_y, team_range.y + team_range.h)
  end

  ---@type BattleArena.Range
  local detection_range = {
    x = min_x,
    y = min_y,
    z = first_range.z,
    w = max_x - min_x,
    h = max_y - min_y,
  }

  ---@type BattleArena
  local arena = {
    area_id = area_id,
    encounter_path = options.encounter_path,
    required_teams = required_teams,
    team_ranges = team_ranges,
    teams = {},
    fight_active = false,
    locked_players = {},
    pve = options.pve,
    min_players = options.min_players or 1,
    detection_range = detection_range,
    events = Net.EventEmitter.new(),
    countdown_bots = countdown_bots,
  }
  setmetatable(arena, BattleArena)

  local arenas = arenas_by_area[area_id]

  if not arenas then
    arenas = {}
    arenas_by_area[area_id] = arenas
  end

  arenas[#arenas + 1] = arena

  return arena
end

function Lib.destroy_arenas_in_area(area_id)
  local arenas = arenas_by_area[area_id]

  if not arenas then
    return
  end

  arenas_by_area[area_id] = nil
  for _, arena in ipairs(arenas) do
    for player_id, _ in pairs(arena.locked_players) do
      if Net.is_player(player_id) then
        Net.unlock_player_input(player_id)
      end

      local tracked_player = tracked_players[player_id]
      tracked_player.arena = nil
      tracked_player.team_range = nil
    end
  end
end

function BattleArena:set_encounter_package(path)
  self.encounter_path = path
end

---@package
function BattleArena:try_reset()
  -- resolve if we should reset the arena for new players
  local should_reset

  if self.fight_active or self.pve then
    -- reset if we can't start a battle
    local min_players = self.min_players

    if self.fight_active then
      -- reset if there are no players in the arena
      min_players = 1
    end

    should_reset = true

    for _, team_id in ipairs(self.required_teams) do
      local team_players = self.teams[team_id]
      if team_players and #team_players >= min_players then
        should_reset = false
        break
      end
    end
  else
    -- reset if we can't start a battle
    should_reset = false
    local total_players = 0

    for _, team_id in ipairs(self.required_teams) do
      local team_players = self.teams[team_id]
      if not team_players or #team_players == 0 then
        should_reset = true
        break
      end

      total_players = total_players + #team_players
    end

    if total_players < self.min_players then
      should_reset = true
    end
  end

  if not should_reset then
    return
  end

  -- cancel timer
  if self.cancel_countdown_callback then
    self.cancel_countdown_callback()
    self.cancel_countdown_callback = nil
  end

  -- reset timer animations
  Net.synchronize(function()
    for _, bot_id in ipairs(self.countdown_bots) do
      Net.animate_actor(bot_id, "DEFAULT")
    end
  end)

  self.fight_active = false

  debug_print("reset arena")
end

---@param self BattleArena
local function start_encounter(self)
  local player_ids = {}

  self.events:emit("battle_start")

  local team_data = {}

  for team_id, team_players in pairs(self.teams) do
    for _, player_id in ipairs(team_players) do
      player_ids[#player_ids + 1] = player_id
    end

    team_data[#team_data + 1] = {
      team = team_id,
      player_count = #team_players
    }
  end

  Net.initiate_netplay(player_ids, self.encounter_path, {
    teams = team_data
  })
end

---@package
function BattleArena:try_start()
  -- resolve if we should reset the arena for new players
  local can_start = not self.fight_active and not self.cancel_countdown_callback

  if not can_start then
    return
  end

  local total_players = 0

  for _, team_id in ipairs(self.required_teams) do
    local team_players = self.teams[team_id]

    if team_players then
      total_players = total_players + #team_players
    end
  end

  if total_players < self.min_players then
    return
  end

  if self.pve then
    -- we can start if any team has a player
    can_start = false

    for _, team_id in ipairs(self.required_teams) do
      local team_players = self.teams[team_id]
      if team_players and #team_players > 0 then
        can_start = true
        break
      end
    end
  else
    -- we can start if there are no teams without a player
    for _, team_id in ipairs(self.required_teams) do
      local team_players = self.teams[team_id]
      if not team_players or #team_players == 0 then
        can_start = false
        break
      end
    end
  end

  if not can_start then
    return
  end

  -- animate bots to display timer
  Net.synchronize(function()
    for _, bot_id in ipairs(self.countdown_bots) do
      Net.animate_actor(bot_id, "COUNTDOWN")
    end
  end)

  -- allow us to cancel the timer
  local cancelled = false

  self.cancel_countdown_callback = function()
    cancelled = true
  end

  debug_print("starting pvp timer")

  -- start timing
  Async.sleep(5).and_then(function()
    if cancelled then
      return
    end

    -- lock in players
    Net.synchronize(function()
      -- fight! instead of the timer
      for _, bot_id in ipairs(self.countdown_bots) do
        Net.animate_actor(bot_id, "FIGHT")
      end

      -- make players face opponents
      for _, player_ids in pairs(self.teams) do
        for _, player_id in ipairs(player_ids) do
          local tracked_player = tracked_players[player_id]

          if not tracked_player or not tracked_player.team_range then
            goto continue
          end

          local direction = tracked_player.team_range.face_direction

          if not self.locked_players[player_id] then
            self.locked_players[player_id] = true
            Net.lock_player_input(player_id)
          end

          Net.animate_actor_properties(player_id, {
            {
              properties = { { property = "Direction", value = direction, ease = "Ceil" } },
              duration = 1
            }
          })

          ::continue::
        end
      end
    end)

    -- mark fight as active
    self.fight_active = true

    debug_print("timer complete, encounter will start soon")

    -- start the encounter after some delay to give time for players to see "FIGHT!"
    Async.sleep(1).and_then(function()
      debug_print("encounter started")
      start_encounter(self)
    end)
  end)
end

---@param arena BattleArena
---@param x number
---@param y number
---@param z number
---@returns BattleArena.TeamRange?
local function resolve_team_range(arena, x, y, z)
  for _, range in ipairs(arena.team_ranges) do
    if overlaps_range(x, y, z, range) then
      return range
    end
  end
end

---@param arena BattleArena
---@param player_id Net.ActorId
---@param x number?
---@param y number?
---@param z number?
local function eject_player(arena, player_id, x, y, z)
  if not x or not y or not z then
    x, y, z = Net.get_actor_position_multi(player_id)
  end

  local team_range = resolve_team_range(arena, x, y, z)

  if team_range then
    arena.events:emit("eject_player", {
      player_id = player_id,
      team_range = team_range,
      x = x,
      y = y,
      z = z
    })
  end
end

-- tracking

---@param tracked_player BattleArena._TrackedPlayer
---@param arena? BattleArena
---@param x number?
---@param y number?
---@param z number?
local function join_arena(tracked_player, arena, x, y, z)
  tracked_player.arena = arena

  if not arena then
    return
  end

  if arena.fight_active then
    eject_player(arena, tracked_player.id, x, y, z)
  end

  debug_print(tracked_player.id, " joined arena")
end

---@param tracked_player BattleArena._TrackedPlayer
local function leave_team(tracked_player)
  local arena = tracked_player.arena

  if not arena then
    return
  end

  debug_print(tracked_player.id, " left team ", tracked_player.team_range.team)

  -- remove the player from their team
  local team_players = arena.teams[tracked_player.team_range.team]

  if team_players then
    for i, player_id in ipairs(team_players) do
      if tracked_player.id == player_id then
        table.remove(team_players, i)
        break
      end
    end
  end

  tracked_player.team_range = nil
end

---@param tracked_player BattleArena._TrackedPlayer
local function leave_arena(tracked_player)
  local arena = tracked_player.arena

  if not arena then
    return
  end

  if arena.locked_players[tracked_player.id] then
    Net.unlock_player_input(tracked_player.id)
    arena.locked_players[tracked_player.id] = nil
  end

  leave_team(tracked_player)

  debug_print(tracked_player.id, " left arena")

  arena:try_reset()
end

---@param tracked_player BattleArena._TrackedPlayer
---@param team_range BattleArena.TeamRange?
local function update_team(tracked_player, team_range)
  local arena = tracked_player.arena

  if not arena then
    return
  end

  if team_range and tracked_player.team_range then
    if tracked_player.team_range == team_range then
      -- no change
      return
    end

    if tracked_player.team_range.team == team_range.team then
      -- switched box, make sure we adopt correct details
      tracked_player.team_range = team_range
      return
    end
  end

  -- try leaving existing team
  if tracked_player.team_range then
    leave_team(tracked_player)
  end

  if not team_range then
    arena:try_reset()
    return
  end

  -- join team
  tracked_player.team_range = team_range
  local team_players = arena.teams[team_range.team]

  if not team_players then
    team_players = {}
    arena.teams[team_range.team] = team_players
  end

  team_players[#team_players + 1] = tracked_player.id

  debug_print(tracked_player.id, " joined team ", team_range.team)

  -- try reset and try starting
  arena:try_reset()
  arena:try_start()

  if arena.fight_active then
    eject_player(arena, tracked_player.id, tracked_player.x, tracked_player.y, tracked_player.z)
  end
end

Net:on("player_disconnect", function(event)
  local tracked_player = tracked_players[event.player_id]

  if tracked_player then
    leave_arena(tracked_player)
    tracked_players[event.player_id] = nil
  end
end)

Net:on("player_area_transfer", function(event)
  local tracked_player = tracked_players[event.player_id]

  if tracked_player then
    tracked_player.area = Net.get_actor_area(event.player_id)
    leave_arena(tracked_player)
  end
end)

Net:on("player_move", function(event)
  local x, y, z = event.x, event.y, event.z

  local tracked_player = tracked_players[event.player_id]

  if not tracked_player then
    tracked_players[event.player_id] = {
      id = event.player_id,
      area = Net.get_actor_area(event.player_id),
      x = x,
      y = y,
      z = z,
    }
    return
  end

  local overlapped_arena
  local overlapped_team_range

  local arenas = arenas_by_area[tracked_player.area]

  if arenas then
    for _, arena in ipairs(arenas) do
      if not overlaps_range_column(x, y, arena.detection_range) then
        goto continue
      end

      local team_range = resolve_team_range(arena, x, y, z)

      if team_range then
        overlapped_arena = arena
        overlapped_team_range = team_range
      end

      ::continue::
    end
  end

  if tracked_player.arena ~= overlapped_arena then
    leave_arena(tracked_player)
    join_arena(tracked_player, overlapped_arena, x, y, z)
  end

  tracked_player.x = x
  tracked_player.y = y
  tracked_player.z = z

  update_team(tracked_player, overlapped_team_range)
end)

Net:on("battle_results", function(event)
  local tracked_player = tracked_players[event.player_id]
  print("battle completed for " .. event.player_id .. " " .. tostring(tracked_player ~= nil))

  if not tracked_player then
    return
  end

  local arena = tracked_player.arena

  if not arena then
    return
  end

  Async.sleep(0.5).and_then(function()
    eject_player(arena, event.player_id, tracked_player.x, tracked_player.y, tracked_player.z)

    if arena.locked_players[event.player_id] then
      Net.unlock_player_input(event.player_id)
      arena.locked_players[tracked_player.id] = nil
    end
  end)

  arena.events:emit("battle_results", event)
end)


return Lib
