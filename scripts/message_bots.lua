math.randomseed()

local Direction = require("scripts/libs/direction")
local Ampstr = require("scripts/libs/ampstr")

---@class MessageBot
---@field default_direction string
---@field conversation_count number
---@field message string

---@type table<string, MessageBot>
local bots = {}

for _, area_id in ipairs(Net.list_areas()) do
  for _, object_id in ipairs(Net.list_objects(area_id)) do
    local object = Net.get_object_by_id(area_id, object_id)

    if object.name ~= "Message Bot" then
      goto continue
    end

    ---@type MessageBot
    local bot_data = {
      default_direction = object.custom_properties.Direction,
      conversation_count = 0,
      message = object.custom_properties.Message,
    }

    local bot_id = Net.create_bot({
      name = "Ampstr",
      x = object.x,
      y = object.y,
      z = object.z,
      texture_path = Ampstr.TEXTURE,
      animation_path = Ampstr.ANIMATION,
      direction = bot_data.default_direction,
      solid = true
    })

    bots[bot_id] = bot_data

    ::continue::
  end
end


local function conversation_start(bot_id)
  local bot_data = bots[bot_id]
  bot_data.conversation_count = bot_data.conversation_count + 1
end

local function conversation_end(bot_id)
  local bot_data = bots[bot_id]
  bot_data.conversation_count = bot_data.conversation_count - 1

  if bot_data.conversation_count == 0 then
    bot_data.conversation_count = 0
    Net.set_bot_direction(bot_id, bot_data.default_direction)
  end
end


Net:on("actor_interaction", function(event)
  local bot_data = bots[event.actor_id]

  if event.button ~= 0 or not bot_data then
    return
  end

  -- face the player
  local player_position = Net.get_player_position(event.player_id)
  local bot_position = Net.get_bot_position(event.actor_id)
  Net.set_bot_direction(event.actor_id, Direction.diagonal_from_points(bot_position, player_position))


  if Ampstr.serious(event.player_id) then
    return
  end

  -- track conversation
  conversation_start(event.actor_id)

  -- start conversation
  Ampstr.message_player_async(event.player_id, bot_data.message)
      .and_then(function()
        -- track conversation end
        conversation_end(event.actor_id)
      end)
end)
