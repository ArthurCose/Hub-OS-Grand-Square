local BattleArenas = require("scripts/libs/battle_arenas")

local area_id = "default"

-- init arenas
local function track_arenas()
  for _, object_id in ipairs(Net.list_objects(area_id)) do
    local object = Net.get_object_by_id(area_id, object_id)

    if object.name ~= "Arena" then
      goto continue
    end

    local x = object.x
    local y = object.y
    local w = object.width
    local h = object.height
    local z = object.z

    local bottom = object.y + object.height

    local team_ranges = {
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
      },
      {
        team = "spectators",
        face_direction = "DOWN LEFT",
        x = x,
        y = y - 1,
        z = z,
        w = w,
        h = 1
      },
      {
        team = "spectators",
        face_direction = "UP RIGHT",
        x = x,
        y = bottom,
        z = z,
        w = w,
        h = 1
      },
    }

    local arena = BattleArenas.create_arena(area_id, {
      area_id = area_id,
      encounter_path = object.custom_properties.Encounter,
      x = object.x,
      y = object.y,
      w = object.width,
      h = object.height,
      z = object.z,
      team_ranges = team_ranges,
      required_teams = { "red", "blue" }
    })

    arena.events:on("eject_player", function(event)
      ---@type BattleArena.TeamRange
      local team_range = event.team_range

      if team_range.team == "spectators" then
        return
      end

      ---@type Net.ActorId
      local player_id = event.player_id
      ---@type number, number
      local y, z = event.y, team_range.z

      local facing_direction = team_range.face_direction
      local target_x

      if facing_direction == "DOWN RIGHT" then
        target_x = team_range.x + team_range.w - 3
      else
        target_x = team_range.x + 3
      end

      target_x = target_x + math.random() * 0.4

      local duration = 0.3

      Net.animate_actor_properties(player_id, {
        {
          properties = {
            { property = "Direction", value = Net.get_actor_direction(player_id) }
          }
        },
        {
          properties = {
            { property = "Z", value = z + 1, ease = "In" }
          },
          duration = duration * 0.75
        },
        {
          properties = {
            { property = "X", value = target_x, ease = "Linear" },
            { property = "Y", value = y,        ease = "Linear" },
            { property = "Z", value = z,        ease = "In" }
          },
          duration = duration
        }
      })
    end)

    ::continue::
  end
end

track_arenas()
