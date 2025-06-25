local Arena = require("scripts/pvp_arena/arena")

local area_id = "default"

local function debug_print(...)
  -- local s = ""
  -- for _, value in ipairs({ ... }) do
  --   s = s .. tostring(value)
  -- end
  -- print(s)
end

---@type Arena[]
local arenas = {}

---@class TrackedPlayer
---@field id Net.ActorId
---@field x number
---@field y number
---@field tile_x number
---@field tile_y number
---@field tile_z number
---@field arena? Arena
---@field team "red" | "blue" | nil

---@type TrackedPlayer[]
local tracked_players = {}

local coop_bots = {
  -- heel
  -- {
  --   encounter = "/server/mods/heel",
  --   bot_texture = "/server/assets/bots/heel_navi.png",
  --   bot_animation = "/server/assets/bots/heel_navi.animation",
  --   on_interact = function(event)
  --     Net.message_player(
  --       event.player_id,
  --       "...",
  --       "/server/assets/bots/heel_navi_mug.png",
  --       "/server/assets/bots/three_panel_mug.animation"
  --     )
  --   end
  -- },
  -- final destination
  {
    encounter = "/server/assets/downloaded_mods/dev.konstinople.encounter.final_destination_multiman.zip",
    bot_texture = "/server/assets/bots/powie.png",
    bot_animation = "/server/assets/bots/powie.animation",
    on_interact = function(event) end
  }
}

local coop_arena
local coop_bot_id
local current_coop_bot = math.random(#coop_bots)
local COOP_CYCLE_MINS = 60

local function encounter_cycle_loop()
  if coop_arena then
    current_coop_bot = current_coop_bot % #coop_bots + 1

    local current_data = coop_bots[current_coop_bot]
    coop_arena:set_encounter_package(current_data.encounter)
    Net.set_bot_avatar(coop_bot_id, current_data.bot_texture, current_data.bot_animation)
  end

  local date = os.date("*t")
  local secs_to_next_hour = os.time({
    year = date.year,
    month = date.month,
    day = date.day,
    hour = date.hour,
    min = date.min // COOP_CYCLE_MINS * COOP_CYCLE_MINS + COOP_CYCLE_MINS
  }) - os.time()

  Async.sleep(secs_to_next_hour).and_then(encounter_cycle_loop)
end

if #coop_bots > 1 then
  encounter_cycle_loop()
end

-- init arenas
local function track_arenas()
  local area_width = Net.get_layer_width(area_id)
  local area_height = Net.get_layer_height(area_id)
  local area_layer_count = Net.get_layer_count(area_id)

  local arena_tileset = Net.get_tileset(area_id, "/server/assets/tiles/battle_arena.tsx")
  local top_tile_gid = arena_tileset.first_gid + 1

  for z = 0, area_layer_count - 1 do
    for y = 0, area_height - 1 do
      for x = 0, area_width - 1 do
        local tile = Net.get_tile(area_id, x, y, z)

        if tile.gid == top_tile_gid then
          local arena = Arena:new(area_id, x, y, z)
          arena:set_encounter_package("/server/mods/pvp_arena")
          arenas[#arenas + 1] = arena
        end
      end
    end
  end

  -- server specific
  -- todo: convert this script into a lib, in a similar style to the co-op server's plugins

  local coop_bot = coop_bots[current_coop_bot]

  coop_arena = arenas[#arenas]
  coop_arena:set_encounter_package(coop_bot.encounter)
  coop_arena:set_ignore_teams(true)

  coop_bot_id = Net.create_bot({
    x = coop_arena.x + 2.5,
    y = coop_arena.y + 1,
    z = coop_arena.z,
    texture_path = coop_bot.bot_texture,
    animation_path = coop_bot.bot_animation,
    direction = "Up Left"
  })

  Net:on("actor_interaction", function(event)
    if event.actor_id == coop_bot_id then
      local coop_bot = coop_bots[current_coop_bot]
      coop_bot.on_interact(event)
    end
  end)
end

track_arenas()

---@param tracked_player TrackedPlayer
---@param arena? Arena
local function join_arena(tracked_player, arena)
  tracked_player.arena = arena

  if not arena then
    return
  end

  if arena.fight_active then
    arena:launch_player(tracked_player)
  end

  debug_print(tracked_player.id, " joined arena")
end

---@param tracked_player TrackedPlayer
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

---@param tracked_player TrackedPlayer
local function leave_arena(tracked_player)
  local arena = tracked_player.arena

  if not arena then
    return
  end

  leave_team(tracked_player)

  debug_print(tracked_player.id, " left arena")

  arena:try_reset()
end

---@param tracked_player TrackedPlayer
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

Net:on("player_move", function(event)
  local position = Net.get_player_position(event.player_id)
  local tile_x = math.floor(position.x)
  local tile_y = math.floor(position.y)
  local tile_z = math.floor(position.z)

  local tracked_player = tracked_players[event.player_id]

  if not tracked_player then
    tracked_players[event.player_id] = {
      id = event.player_id,
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

    for _, arena in ipairs(arenas) do
      if arena:overlaps(position.x, position.y, position.z) then
        overlapped_arena = arena
        break
      end
    end

    if tracked_player.arena ~= overlapped_arena then
      leave_arena(tracked_player)
      join_arena(tracked_player, overlapped_arena)
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
