local PlayerFishingData = require("scripts/fishing/player_data")
local StringUtil = require("scripts/fishing/string_util")

local BAIT_PER_UPGRADE = 3
local BAIT_PER_PURCHASE = 32 -- just buy as much as possible for now

local TEXTURE_PATH = "/server/assets/bots/heel_navi.png"
local ANIMATION_PATH = "/server/assets/bots/heel_navi.animation"
local MUG_TEXTURE = "/server/assets/bots/heel_navi_mug.png"
local MUG_ANIM_PATH = "/server/assets/bots/three_panel_mug.animation"

local GREETINGS = {
  "You can teach a cat to fish, but you can't drink water.",
  "You can bring a cat to fresh water, but you can't make her fish.",
  "You can bring a fish to a cat, but you can't water him.",
  "Fish.",
  "Welcome.",
}

local THANK_MESSAGE = "Thank you for your purchase."

local LEAVE_MESSAGE = "Thanks for stopping by!"

---@class FishingShop
local FishingShop = {}

local function bait_upgrade_id(item_id)
  return item_id .. ":upgrade"
end

FishingShop.FISHING_ROD_ID = "fishing_rod"
Net.register_item(FishingShop.FISHING_ROD_ID, {
  name = "FishingRod",
  description = "Used to fish at ripples."
})

local HELP_ID = "help"
local HELP_DATA = {
  name = "Help",
  description = "A free guide to fishing.",
  lines = {
    "With bait and a fishing rod, you can encounter fish at ripples.",
    "Fishing encounters are a special form of battle.",
    "You have one turn to catch a fish.",
    "With an empty hand, attempting to use a chip will throw a hook.",
    "With a fish on the line, press your chip button again to reel it in.",
    "Mashing will snap your line, if you're too slow the fish will get away!",
    "Try to clear your battlefield, anything between you and your fish can also snap the line."
  }
}

local BAIT_IDS = { "bait:1", "bait:2", "bait:3", "bait:4" }
FishingShop.BAIT_ITEM_MAP = {
  ["bait:1"] = {
    name = "url_slug",
    description = "Lvl 1 Fish Bait\n\nAffects rank",
    consumable = true,
    price = 0,
    upgrade_price = { 0, 10, 20, 30 }
  },
  ["bait:2"] = {
    name = "Worm.png",
    description = "Lvl 2 Fish Bait\n\nAffects rank",
    consumable = true,
    price = 1,
    -- unlocks after ~75 Piranha2s
    upgrade_price = { 150, 75, 100, 125 }
  },
  ["bait:3"] = {
    name = "HoneyPot",
    description = "Lvl 3 Fish Bait\n\nAffects rank",
    consumable = true,
    price = 2,
    -- unlocks after ~100 Piranha3s
    upgrade_price = { 400, 150, 200, 250 }
  },
  ["bait:4"] = {
    name = "Cob",
    description = "Lvl 4 Fish Bait\n\nAffects rank",
    consumable = true,
    price = 3,
    -- unlocks after ~125 PiranhaSPs
    upgrade_price = { 1200, 400, 600, 800 }
  },
  -- ["bait:5"] = {
  --   name = "BugCrumb",
  --   description = "Lvl 5 Fish Bait\n\nAffects rank",
  --   price = 5,
  --   upgrade_price = { 3000, 1000, 2000 }
  -- }
}

local MOD_ITEM_IDS = { "mod:fish_chip" }
local MOD_ITEMS = {
  ["mod:fish_chip"] = {
    name = "Fish",
    description = "Toss a\nfish onto\nthe field",
    price = 4500,
    package_id = "GrandSquare.Cards.Fish"
  },
}

local item_description_map = {}
item_description_map[HELP_ID] = HELP_DATA.description

for i = #BAIT_IDS, 1, -1 do
  local id = BAIT_IDS[i]
  local definition = FishingShop.BAIT_ITEM_MAP[id]

  Net.register_item(id, definition)
  item_description_map[id] = definition.description
  item_description_map[bait_upgrade_id(id)] = definition.name ..
      " Upgrade.\nIncreases " .. definition.name .. " Capacity by " .. BAIT_PER_UPGRADE .. "."
end

for id, definition in pairs(MOD_ITEMS) do
  item_description_map[id] = definition.description
end

---@param area_id string
---@param object Net.Object
function FishingShop.spawn_bot(area_id, object)
  return Net.create_bot({
    texture_path = TEXTURE_PATH,
    animation_path = ANIMATION_PATH,
    area_id = area_id,
    x = object.x,
    y = object.y,
    z = object.z,
    direction = object.custom_properties.Direction,
    solid = true,
  })
end

---@param player_id Net.ActorId
---@param data PlayerFishingData
local function first_interaction(player_id, data)
  Async.create_scope(function()
    Async.await(Async.message_player(
      player_id,
      "I'm running a fishing shop.",
      MUG_TEXTURE,
      MUG_ANIM_PATH
    ))

    local response = Async.await(Async.question_player(
      player_id,
      "Need a fishing rod?",
      MUG_TEXTURE,
      MUG_ANIM_PATH
    ))

    if response ~= 1 then
      return nil
    end


    Net.give_player_item(player_id, FishingShop.FISHING_ROD_ID)
    Net.give_player_item(player_id, "bait:1", BAIT_PER_UPGRADE)

    data.inventory[FishingShop.FISHING_ROD_ID] = 1
    data.inventory["bait:1"] = BAIT_PER_UPGRADE
    data.hidden_inventory[bait_upgrade_id("bait:1")] = 1
    data:save(player_id)

    Net.message_player(
      player_id,
      "You can have some bait to start as well.",
      MUG_TEXTURE,
      MUG_ANIM_PATH
    )

    response = Async.await(Async.question_player(
      player_id, "Want me to explain how fishing works?",
      MUG_TEXTURE,
      MUG_ANIM_PATH
    ))

    if response == 1 then
      for _, text in ipairs(HELP_DATA.lines) do
        Net.message_player(player_id, text, MUG_TEXTURE, MUG_ANIM_PATH)
      end
    end

    Net.message_player(
      player_id,
      "Remember to stop by when you're out of bait!",
      MUG_TEXTURE,
      MUG_ANIM_PATH
    )

    return nil
  end)
end

---@param data PlayerFishingData
local function resolve_bait_purchase_count(data, item_id)
  local item = FishingShop.BAIT_ITEM_MAP[item_id]

  local bait_count = data.inventory[item_id] or 0
  local upgrade_count = (data.hidden_inventory[bait_upgrade_id(item_id)] or 0)
  local max_capacity = upgrade_count * BAIT_PER_UPGRADE
  local affordable_count

  if item.price == 0 then
    affordable_count = BAIT_PER_PURCHASE
  else
    affordable_count = data.money // item.price
  end

  return math.max(math.min(max_capacity - bait_count, BAIT_PER_PURCHASE, affordable_count), 0)
end

---@param player_id Net.ActorId
---@param data PlayerFishingData
---@param price number
---@param success_callback fun() called before saving
local function try_purchase(player_id, data, price, success_callback)
  if data.money < price then
    return
  end

  data.money = data.money - price
  Net.set_player_money(player_id, data.money)
  success_callback()
  data:save(player_id)
end

---@param player_id Net.ActorId
local function respond_to_purchase(player_id)
  Net.message_player(player_id, THANK_MESSAGE, MUG_TEXTURE, MUG_ANIM_PATH)
end

---@param player_id Net.ActorId
function FishingShop.handle_interaction(player_id)
  Async.create_scope(function()
    local data = Async.await(PlayerFishingData.fetch(player_id))

    if not data.inventory[FishingShop.FISHING_ROD_ID] then
      first_interaction(player_id, data)
      return nil
    end

    ---@type Net.ShopItem[]
    local shop_items = {
      { id = HELP_ID, name = HELP_DATA.name, price = "0z" }
    }

    -- list bait and upgrades
    local prev_upgrade_count = 0

    for _, id in ipairs(BAIT_IDS) do
      local upgrade_key = bait_upgrade_id(id)
      local item = FishingShop.BAIT_ITEM_MAP[id]
      local upgrade_count = data.hidden_inventory[upgrade_key] or 0

      if upgrade_count > 0 then
        local count = resolve_bait_purchase_count(data, id)

        shop_items[#shop_items + 1] = {
          id = id,
          name = item.name .. " x" .. count,
          price = item.price * count .. "z"
        }
      end

      if (upgrade_count > 0 or prev_upgrade_count > 0) and upgrade_count < #item.upgrade_price then
        shop_items[#shop_items + 1] = {
          id = upgrade_key,
          name = item.name .. " Up",
          price = item.upgrade_price[upgrade_count + 1] .. "z"
        }
      end

      prev_upgrade_count = upgrade_count
    end

    -- list mod souvenirs
    for _, id in ipairs(MOD_ITEM_IDS) do
      local item = MOD_ITEMS[id]
      local price = item.price

      if data.hidden_inventory[id] then
        -- already purchased
        price = 0
      end

      shop_items[#shop_items + 1] = {
        id = id,
        name = item.name,
        price = price .. "z"
      }
    end

    -- send shop and handle events
    local events = Net.open_shop(player_id, shop_items, MUG_TEXTURE, MUG_ANIM_PATH)

    Net.set_shop_message(player_id, GREETINGS[math.random(#GREETINGS)])

    for event_name, event in Async.await(events:async_iter_all()) do
      local item_id = event.item_id

      if event_name == "shop_purchase" then
        if item_id == HELP_ID then
          -- requested help
          local question = "Want me to explain how fishing works?"
          local response = Async.await(Async.question_player(player_id, question, MUG_TEXTURE, MUG_ANIM_PATH))

          if response == 1 then
            for _, text in ipairs(HELP_DATA.lines) do
              Net.message_player(player_id, text)
            end
          end
        elseif StringUtil.ends_with(item_id, ":upgrade") then
          -- purchasing bait upgrade
          local bait_id = StringUtil.strip_suffix(item_id, ":upgrade")
          local bait_item = FishingShop.BAIT_ITEM_MAP[bait_id]

          if not bait_item then
            print("invalid purchase attempt: " .. item_id)
            goto continue
          end

          local count = (data.hidden_inventory[item_id] or 0)

          if count < #bait_item.upgrade_price then
            try_purchase(player_id, data, bait_item.upgrade_price[count + 1], function()
              respond_to_purchase(player_id)

              count = count + 1
              data.hidden_inventory[item_id] = count

              if count >= #bait_item.upgrade_price then
                Net.remove_shop_item(player_id, item_id)
              else
                Net.update_shop_item(player_id, {
                  id = item_id,
                  name = bait_item.name .. " Up",
                  price = bait_item.upgrade_price[count + 1] .. "z"
                })
              end

              if count == 1 then
                -- first purchase, need to add an option to buy the new bait
                local next_purchase_count = resolve_bait_purchase_count(data, bait_id)
                local bait_shop_item = {
                  id = bait_id,
                  name = bait_item.name .. " x" .. next_purchase_count,
                  price = bait_item.price * next_purchase_count .. "z"
                }

                Net.prepend_shop_items(player_id, { bait_shop_item }, item_id)

                -- todo: add the option for the next upgrade
              end
            end)
          end
        elseif StringUtil.starts_with(item_id, "bait:") then
          -- purchasing bait
          local bait_item = FishingShop.BAIT_ITEM_MAP[item_id]

          if not bait_item then
            print("invalid purchase attempt: " .. item_id)
            goto continue
          end

          -- avoid purchasing more bait than we have space for
          local count = resolve_bait_purchase_count(data, item_id)

          if count == 0 then
            -- not enough room for more
            local mug = Net.get_player_mugshot(player_id)

            Net.message_player(
              player_id,
              "We can't carry more " .. bait_item.name,
              mug.texture_path,
              mug.animation_path
            )

            goto continue
          end

          local price = bait_item.price * count

          try_purchase(player_id, data, price, function()
            respond_to_purchase(player_id)

            local bait_count = data.inventory[item_id] or 0
            bait_count = bait_count + count
            data.inventory[item_id] = bait_count
            Net.give_player_item(player_id, item_id, count)

            local next_purchase_count = resolve_bait_purchase_count(data, item_id)

            if next_purchase_count ~= count then
              Net.update_shop_item(player_id, {
                id = item_id,
                name = bait_item.name .. " x" .. next_purchase_count,
                price = bait_item.price * next_purchase_count .. "z"
              })
            end
          end)
        elseif StringUtil.starts_with(item_id, "mod:") then
          -- purchase souvenir
          local mod_item = MOD_ITEMS[item_id]

          if not mod_item then
            print("invalid purchase attempt: " .. item_id)
            goto continue
          end

          if data.hidden_inventory[item_id] then
            Net.refer_package(player_id, mod_item.package_id)
          else
            try_purchase(player_id, data, mod_item.price, function()
              Net.refer_package(player_id, mod_item.package_id)

              data.hidden_inventory[item_id] = 1
              Net.update_shop_item(player_id, {
                id = item_id,
                name = mod_item.name,
                price = "0z"
              })
            end)
          end
        else
          print("invalid purchase attempt: " .. item_id)
        end
      elseif event_name == "shop_description_request" then
        local description = item_description_map[item_id]

        if description then
          Net.message_player(player_id, description)
        end
      elseif event_name == "shop_leave" then
        Net.set_shop_message(player_id, LEAVE_MESSAGE)
      end

      ::continue::
    end

    return nil
  end)
end

return FishingShop
