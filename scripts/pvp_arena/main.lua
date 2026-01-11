local BattleArenas = require("scripts/pvp_arena/battle_arenas")

local area_id = "default"

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

  for z = 0, area_layer_count - 1 do
    for y = 0, area_height - 1 do
      for x = 0, area_width - 1 do
        local tile = Net.get_tile(area_id, x, y, z)

        if tile.gid == top_tile_gid then
          local arena = BattleArenas.create_arena(area_id, x, y, z)
          arena:set_encounter_package("/server/mods/pvp_arena")
          add_spectator_detection(arena)
        end
      end
    end
  end
end

track_arenas()
