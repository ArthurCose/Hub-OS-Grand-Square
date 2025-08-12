local BattleArenas = require("scripts/pvp_arena/battle_arenas")

local area_id = "default"

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

---@param arena BattleArena
local function add_spectator_detection(arena)
  local center_x_floored = math.floor(arena.center_x)
  local center_y_floored = math.floor(arena.center_y)

  arena.event_emitter:on("battle_start", function()
    local seen = {}

    for _, value in ipairs(arena.red_players) do
      seen[value] = true
    end

    for _, value in ipairs(arena.blue_players) do
      seen[value] = true
    end

    for _, player_id in ipairs(Net.list_players(arena.area_id)) do
      if seen[player_id] then
        -- already taking part in battle
        goto continue
      end

      local x, y, z = Net.get_player_position_multi(player_id)

      local x_floored = math.floor(x)

      if x_floored < center_x_floored - 1 or x_floored > center_x_floored + 1 or arena.z ~= math.floor(z) then
        goto continue
      end

      local y_floored = math.floor(y)

      if y_floored ~= center_y_floored - 2 and y_floored ~= center_y_floored + 1 then
        goto continue
      end

      arena.gray_players[#arena.gray_players + 1] = player_id

      ::continue::
    end
  end)
end

-- init arenas
local function track_arenas()
  local area_width = Net.get_layer_width(area_id)
  local area_height = Net.get_layer_height(area_id)
  local area_layer_count = Net.get_layer_count(area_id)

  local arena_tileset = Net.get_tileset(area_id, "/server/assets/tiles/battle_arena.tsx")
  local top_tile_gid = arena_tileset.first_gid + 1

  local last_arena

  for z = 0, area_layer_count - 1 do
    for y = 0, area_height - 1 do
      for x = 0, area_width - 1 do
        local tile = Net.get_tile(area_id, x, y, z)

        if tile.gid == top_tile_gid then
          local arena = BattleArenas.create_arena(area_id, x, y, z)
          arena:set_encounter_package("/server/mods/pvp_arena")
          add_spectator_detection(arena)
          last_arena = arena
        end
      end
    end
  end

  -- server specific
  -- todo: convert this script into a lib, in a similar style to the co-op server's plugins

  local coop_bot = coop_bots[current_coop_bot]

  coop_arena = last_arena
  coop_arena:set_encounter_package(coop_bot.encounter)
  coop_arena:set_ignore_teams(true)

  coop_bot_id = Net.create_bot({
    x = coop_arena.center_x + 1,
    y = coop_arena.center_y,
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
