local function debug_print(...)
  -- local s = ""
  -- for _, value in ipairs({ ... }) do
  --   s = s .. tostring(value)
  -- end
  -- print(s)
end

---@type table<string, BattleArena[]>
local arenas_by_area = {}

---@class BattleArena
---@field area_id string
---@field x number
---@field y number
---@field z number
---@field center_x number
---@field center_y number
---@field event_emitter Net.EventEmitter "battle_start"
---@field red_players Net.ActorId[]
---@field blue_players Net.ActorId[]
---@field gray_players Net.ActorId[]
---@field package encounter_path string
---@field package ignore_teams? boolean
---@field package fight_active boolean
---@field package countdown_bots Net.ActorId[]
---@field package cancel_countdown_callback? function
local BattleArena = {}
BattleArena.__index = BattleArena

local bot_offsets = {
  { -1.5, -1 },
  { -1.5, 1 },
  { 1.5,  -1 },
  { 1.5,  1 },
}

local Lib = {
  COUNTDOWN_TEXTURE_PATH = "/server/assets/bots/pvp_countdown.png",
  COUNTDOWN_ANIMATION_PATH = "/server/assets/bots/pvp_countdown.animation"
}

---@return BattleArena
---Creates and tracks an arena
function Lib.create_arena(area_id, tile_x, tile_y, tile_z)
  local center_x = tile_x + 0.5
  local center_y = tile_y + 1

  local countdown_bots = {}

  for _, offset in ipairs(bot_offsets) do
    countdown_bots[#countdown_bots + 1] = Net.create_bot({
      area_id = area_id,
      warp_in = false,
      texture_path = Lib.COUNTDOWN_TEXTURE_PATH,
      animation_path = Lib.COUNTDOWN_ANIMATION_PATH,
      solid = false,
      x = center_x + offset[1],
      y = center_y + offset[2],
      z = tile_z
    })
  end

  local arena = {
    area_id = area_id,
    center_x = center_x,
    center_y = center_y,
    x = tile_x - 1,
    y = tile_y,
    z = tile_z,
    fight_active = false,
    red_players = {},
    blue_players = {},
    gray_players = {},
    event_emitter = Net.EventEmitter.new(),
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

function BattleArena:set_encounter_package(path)
  self.encounter_path = path
end

function BattleArena:set_ignore_teams(ignore_teams)
  self.ignore_teams = ignore_teams
end

---@package
function BattleArena:try_reset()
  -- resolve if we should reset the arena for new players
  local should_reset

  if self.ignore_teams then
    should_reset = #self.red_players + #self.blue_players == 0
  else
    should_reset = (not self.fight_active and (#self.red_players == 0 or #self.blue_players == 0)) or
        (self.fight_active and (#self.red_players + #self.blue_players == 0))
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
      Net.animate_bot(bot_id, "DEFAULT")
    end
  end)

  self.fight_active = false

  debug_print("reset arena")
end

---@param self BattleArena
local function start_encounter(self)
  local player_ids = {}

  self.event_emitter:emit("battle_start")

  for _, player_id in ipairs(self.red_players) do
    player_ids[#player_ids + 1] = player_id
  end

  for _, player_id in ipairs(self.blue_players) do
    player_ids[#player_ids + 1] = player_id
  end

  for _, player_id in ipairs(self.gray_players) do
    player_ids[#player_ids + 1] = player_id
  end

  self.gray_players = {}

  Net.initiate_netplay(player_ids, self.encounter_path, {
    red_player_count = #self.red_players,
    blue_player_count = #self.blue_players,
  })
end

---@package
function BattleArena:try_start()
  -- resolve if we should reset the arena for new players
  local can_start = not self.fight_active and not self.cancel_countdown_callback

  if self.ignore_teams then
    can_start = can_start and #self.red_players + #self.blue_players > 0
  else
    can_start = can_start and #self.red_players > 0 and #self.blue_players > 0
  end

  if not can_start then
    return
  end

  -- animate bots to display timer
  Net.synchronize(function()
    for _, bot_id in ipairs(self.countdown_bots) do
      Net.animate_bot(bot_id, "COUNTDOWN")
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
    local red_players = self.red_players
    local blue_players = self.blue_players

    Net.synchronize(function()
      -- fight! instead of the timer
      for _, bot_id in ipairs(self.countdown_bots) do
        Net.animate_bot(bot_id, "FIGHT")
      end

      -- make players face opponents
      for _, player_id in ipairs(red_players) do
        Net.lock_player_input(player_id)
        Net.animate_player_properties(player_id, {
          {
            properties = { { property = "Direction", value = "DOWN RIGHT" } },
            duration = 1
          }
        })
      end

      for _, player_id in ipairs(blue_players) do
        Net.lock_player_input(player_id)
        Net.animate_player_properties(player_id, {
          {
            properties = { { property = "Direction", value = "UP LEFT" } },
            duration = 1
          }
        })
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

---@package
---@param tracked_player BattleArena._TrackedPlayer
---@param x number?
---@param y number?
function BattleArena:launch_player(tracked_player, x, y)
  local target_x
  local facing_direction

  x = x or tracked_player.x
  y = y or tracked_player.y

  if x < self.center_x then
    target_x = self.center_x - 3
    facing_direction = "DOWN RIGHT"
  else
    target_x = self.center_x + 3
    facing_direction = "UP LEFT"
  end

  target_x = target_x + math.random() * 0.4

  local duration = 0.3

  Net.animate_player_properties(tracked_player.id, {
    {
      properties = {
        { property = "Direction", value = facing_direction }
      }
    },
    {
      properties = {
        { property = "Z", value = self.z + 1, ease = "In" }
      },
      duration = duration * 0.75
    },
    {
      properties = {
        { property = "X", value = target_x, ease = "Linear" },
        { property = "Y", value = y,        ease = "Linear" },
        { property = "Z", value = self.z,   ease = "In" }
      },
      duration = duration
    }
  })
end

---@param x number
---@param y number
---@param z number
function BattleArena:overlaps(x, y, z)
  return
      (z == self.z) and
      (x > self.x and x < self.x + 3) and
      (y > self.y and y < self.y + 2)
end

-- tracking

---@class BattleArena._TrackedPlayer
---@field id Net.ActorId
---@field area string
---@field x number
---@field y number
---@field tile_x number
---@field tile_y number
---@field tile_z number
---@field arena? BattleArena
---@field team "red" | "blue" | nil

---@type BattleArena._TrackedPlayer[]
local tracked_players = {}

---@param tracked_player BattleArena._TrackedPlayer
---@param arena? BattleArena
---@param x number?
---@param y number?
local function join_arena(tracked_player, arena, x, y)
  tracked_player.arena = arena

  if not arena then
    return
  end

  if arena.fight_active then
    arena:launch_player(tracked_player, x, y)
  end

  debug_print(tracked_player.id, " joined arena")
end

---@param tracked_player BattleArena._TrackedPlayer
local function leave_team(tracked_player)
  local arena = tracked_player.arena

  if not arena then
    return
  end

  debug_print(tracked_player.id, " left team ", tracked_player.team)

  -- remove the player from their team
  local team_players = arena.red_players

  if tracked_player.team == "blue" then
    team_players = arena.blue_players
  end

  for i, player_id in ipairs(team_players) do
    if tracked_player.id == player_id then
      table.remove(team_players, i)
      break
    end
  end

  tracked_player.team = nil
end

---@param tracked_player BattleArena._TrackedPlayer
local function leave_arena(tracked_player)
  local arena = tracked_player.arena

  if not arena then
    return
  end

  leave_team(tracked_player)

  debug_print(tracked_player.id, " left arena")

  arena:try_reset()
end

---@param tracked_player BattleArena._TrackedPlayer
local function update_team(tracked_player)
  local arena = tracked_player.arena

  if not arena then
    return
  end

  -- resolve team
  local team = "red"

  if tracked_player.x > arena.center_x then
    team = "blue"
  end

  if tracked_player.team == team then
    return
  end

  -- try leaving existing team
  if tracked_player.team then
    leave_team(tracked_player)
  end

  -- join team
  tracked_player.team = team

  if team == "red" then
    arena.red_players[#arena.red_players + 1] = tracked_player.id
  else
    arena.blue_players[#arena.blue_players + 1] = tracked_player.id
  end

  debug_print(tracked_player.id, " joined team ", team)

  -- try reset and try starting
  arena:try_reset()
  arena:try_start()
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
    tracked_player.area = Net.get_player_area(event.player_id)
    leave_arena(tracked_player)
    leave_arena(tracked_player)
  end
end)

Net:on("player_move", function(event)
  local position = Net.get_player_position(event.player_id)
  local tile_x = math.floor(position.x)
  local tile_y = math.floor(position.y)
  local tile_z = math.floor(position.z)

  local tracked_player = tracked_players[event.player_id]

  if not tracked_player then
    tracked_players[event.player_id] = {
      id = event.player_id,
      area = Net.get_player_area(event.player_id),
      x = position.x,
      y = position.x,
      tile_x = tile_x,
      tile_y = tile_y,
      tile_z = tile_z,
    }
    return
  end

  if tracked_player.tile_x ~= tile_x or tracked_player.tile_y ~= tile_y or tracked_player.tile_z ~= tile_z then
    local overlapped_arena

    local arenas = arenas_by_area[tracked_player.area]

    if arenas then
      for _, arena in ipairs(arenas) do
        if arena:overlaps(position.x, position.y, position.z) then
          overlapped_arena = arena
          break
        end
      end
    end

    if tracked_player.arena ~= overlapped_arena then
      leave_arena(tracked_player)
      join_arena(tracked_player, overlapped_arena, position.x, position.y)
    end
  end

  tracked_player.tile_x = tile_x
  tracked_player.tile_y = tile_y
  tracked_player.tile_z = tile_z
  tracked_player.x = position.x
  tracked_player.y = position.y

  update_team(tracked_player)
end)

Net:on("battle_results", function(event)
  local tracked_player = tracked_players[event.player_id]

  if not tracked_player or not tracked_player.arena then
    return
  end

  Async.sleep(0.5).and_then(function()
    tracked_player.arena:launch_player(tracked_player)
    Net.unlock_player_input(event.player_id)
  end)
end)


return Lib
