local Direction = require("scripts/libs/direction")
local Ampstr = require("scripts/libs/ampstr")

local SERVER_NAME = Net.get_area_name("default")

---@class BookmarkBot
---@field default_direction string
---@field conversation_count number

local bookmark_bots = {}

for _, area_id in ipairs(Net.list_areas()) do
  for _, object_id in ipairs(Net.list_objects(area_id)) do
    local object = Net.get_object_by_id(area_id, object_id)

    if object.name ~= "Bookmark Bot" then
      goto continue
    end

    ---@type BookmarkBot
    local bot_data = {
      default_direction = object.custom_properties.Direction,
      conversation_count = 0,
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

    bookmark_bots[bot_id] = bot_data

    ::continue::
  end
end


local function conversation_start(bot_id)
  local bot_data = bookmark_bots[bot_id]
  bot_data.conversation_count = bot_data.conversation_count + 1
end

local function conversation_end(bot_id)
  local bot_data = bookmark_bots[bot_id]
  bot_data.conversation_count = bot_data.conversation_count - 1

  if bot_data.conversation_count == 0 then
    bot_data.conversation_count = 0
    Net.set_bot_direction(bot_id, bot_data.default_direction)
  end
end


Net:on("actor_interaction", function(event)
  if event.button ~= 0 or not bookmark_bots[event.actor_id] then
    return
  end

  -- face the player
  local player_position = Net.get_player_position(event.player_id)
  local bot_position = Net.get_bot_position(event.actor_id)
  Net.set_bot_direction(event.actor_id, Direction.diagonal_from_points(bot_position, player_position))

  -- track conversation
  conversation_start(event.actor_id)

  -- start conversation
  Async.create_scope(function()
    local response = Async.await(Ampstr.question_player_async(event.player_id, "Would you like to bookmark us?"))

    if response ~= 1 then
      conversation_end(event.actor_id)
      return nil
    end

    Net.refer_server(event.player_id, SERVER_NAME, "hubos.konstinople.dev:8018")

    Async.await(Ampstr.message_player_async(event.player_id, "Yippee!"))

    conversation_end(event.actor_id)
    return nil
  end)
end)
