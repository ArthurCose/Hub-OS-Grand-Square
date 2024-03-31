local TEXTURE = "/server/assets/bots/cafe_worker.png"
local ANIMATION = "/server/assets/bots/cafe_worker.animation"
local MUG_TEXTURE = "/server/assets/bots/cafe_worker_mug.png"
local MUG_ANIMATION = "/server/assets/bots/three_panel_mug.animation"

---@type table<string, boolean>
local bots = {}

---@type table<string, boolean>
local table_objects = {}

for _, area_id in ipairs(Net.list_areas()) do
  for _, object_id in ipairs(Net.list_objects(area_id)) do
    local object = Net.get_object_by_id(area_id, object_id)

    if object.name == "Cafe Table" then
      table_objects[object.id] = true
    elseif object.name == "Cafe Worker" then
      local bot_id = Net.create_bot({
        x = object.x,
        y = object.y,
        z = object.z,
        texture_path = TEXTURE,
        animation_path = ANIMATION,
        direction = object.custom_properties.Direction,
        solid = true
      })

      bots[bot_id] = true
    end
  end
end

local offer_message = table.concat({
  "...Welcome to the",
  "Kitty Cafe...",
  "",
  "...Would you like",
  "a warm cup of",
  "catnip tea?",
}, "\n")

local accept_message = "...Thanks!"

local reject_message = table.concat({
  "...Really?",
  "The tea is free...",
}, "\n")

local drink_description_message = table.concat({
  -- must be prefixed with the navi's name
  "The air fills",
  "with the earthy",
  "aroma of catnip.",
}, "\n")

local navi_response_message = table.concat({
  "...I feel",
  "relaxed...",
}, "\n")

local function shop_flow(player_id)
  Async.question_player(player_id, offer_message, MUG_TEXTURE, MUG_ANIMATION)
      .and_then(function(offer_response)
        if offer_response ~= 1 then
          Net.message_player(player_id, reject_message, MUG_TEXTURE, MUG_ANIMATION)
          return
        end

        Net.message_player(player_id, accept_message, MUG_TEXTURE, MUG_ANIMATION)
        Net.message_player(player_id, drink_description_message)

        local mug = Net.get_player_mugshot(player_id)
        Net.message_player(player_id, navi_response_message, mug.texture_path, mug.animation_path)
      end)
end

Net:on("actor_interaction", function(event)
  if event.button ~= 0 or not bots[event.actor_id] then
    return
  end

  shop_flow(event.player_id)
end)

Net:on("object_interaction", function(event)
  if event.button ~= 0 or not table_objects[event.object_id] then
    return
  end

  shop_flow(event.player_id)
end)
