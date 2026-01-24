local PlayerFishingData = require("scripts/fishing/player_data")
local Leaderboard = require("scripts/fishing/leaderboard")
local JournalBoard = require("scripts/fishing/journal_board")
local SellPrices = require("scripts/fishing/sell_prices")
local FishingShop = require("scripts/fishing/shop")
local StringUtil = require("scripts/fishing/string_util")

local area_id = "default"
local objects = Net.list_objects(area_id)

local relevant_tile_id = Net.get_tileset(area_id, "/server/assets/tiles/ripples.tsx").first_gid

---@class FishingPool
---@field available number[]
---@field ripple_encounters table<number, number>
---@field min_ripple_encounters number min encounters a single ripple provides
---@field max_ripple_encounters number max encounters a single ripple provides
---@field total_ripples number
---@field max_ripples number

local function create_pool(max_spawns)
  ---@type FishingPool
  return {
    available = {},
    ripple_encounters = {},
    min_ripple_encounters = 1,
    max_ripple_encounters = 1,
    total_ripples = 0,
    max_ripples = max_spawns
  }
end

local pond_pool = create_pool(2)
pond_pool.min_ripple_encounters = 2
pond_pool.max_ripple_encounters = 2

local generic_pool = create_pool(4)
generic_pool.min_ripple_encounters = 2
generic_pool.max_ripple_encounters = 5

local pools = { pond_pool, generic_pool }

---@type table<Net.ActorId, fun(player_id: Net.ActorId)>
local actor_handlers = {}
---@type table<number, fun(player_id: Net.ActorId)>
local object_handlers = {}

local function tile_hash(x, y, z)
  return (x << 32) | (y << 16) | z
end

local function position_from_hash(hash)
  return hash >> 32, (hash >> 16) & 65535, hash & 65535
end

-- read map data
for _, id in ipairs(objects) do
  local object = Net.get_object_by_id(area_id, id)

  if object.name == "Fishing Spot" then
    Net.remove_object(area_id, id)

    local pool

    if object.custom_properties.Category == "Pond" then
      pool = pond_pool
    else
      pool = generic_pool
    end

    local x_start = math.floor(object.x)
    local y_start = math.floor(object.y)

    for y = y_start, y_start + math.floor(object.height) do
      for x = x_start, x_start + math.floor(object.width) do
        pool.available[#pool.available + 1] = tile_hash(x, y, object.z)
      end
    end
  elseif object.name == "Fishing Shop" then
    local bot_id = FishingShop.spawn_bot(area_id, object)
    actor_handlers[bot_id] = FishingShop.handle_interaction
  elseif object.name == "Fishing Leaderboard" then
    object_handlers[object.id] = Leaderboard.open
  elseif object.name == "Fishing Prev Leaderboard" then
    object_handlers[object.id] = Leaderboard.open_prev
  elseif object.name == "Fishing Journal" then
    object_handlers[object.id] = JournalBoard.open
  end
end

local function resolve_pool_from_hash(hash)
  for _, pool in ipairs(pools) do
    if pool.ripple_encounters[hash] then
      return pool
    end
  end

  return nil
end

Net:on("actor_interaction", function(event)
  if Net.is_player_busy(event.player_id) then
    return
  end

  local listener = actor_handlers[event.actor_id]
  if listener and event.button == 0 then
    listener(event.player_id)
  end
end)

Net:on("object_interaction", function(event)
  if Net.is_player_busy(event.player_id) then
    return
  end

  local listener = object_handlers[event.object_id]
  if listener and event.button == 0 then
    listener(event.player_id)
  end
end)

---expects to run in an async scope
---@param player_id Net.ActorId
---@parma player_data PlayerFishingData
local function resolve_bait(player_id, player_data)
  local bait_id = player_data.selected_bait
  local bait_count = player_data.inventory[bait_id] or 0
  local bait_item = FishingShop.BAIT_ITEM_MAP[bait_id]

  local initial_bait_item = bait_item

  if not bait_item then
    -- invalid bait?
    warn("invalid bait: " .. bait_id)
    return nil
  end

  if bait_count > 0 then
    -- resolve bait
    return bait_id, bait_item, bait_count
  end

  -- fallback

  local initial_id = bait_id

  -- try the next best bait
  while bait_id do
    bait_id = FishingShop.next_bait(bait_id)
    bait_count = player_data.inventory[bait_id] or 0

    if bait_count > 0 then
      bait_item = FishingShop.BAIT_ITEM_MAP[bait_id]
      break
    end
  end

  -- try worse bait
  if not bait_id then
    bait_id = initial_id

    while bait_id do
      bait_id = FishingShop.prev_bait(bait_id)
      bait_count = player_data.inventory[bait_id] or 0

      if bait_count > 0 then
        bait_item = FishingShop.BAIT_ITEM_MAP[bait_id]
        break
      end
    end
  end

  local mug = Net.get_player_mugshot(player_id)

  if not bait_id or bait_count <= 0 then
    Net.message_player(
      player_id,
      "We're out of bait.",
      mug.texture_path,
      mug.animation_path
    )

    return nil
  end

  Net.message_player(
    player_id,
    "We're out of " .. initial_bait_item.name .. " bait.",
    mug.texture_path,
    mug.animation_path
  )

  local response = Async.await(Async.question_player(
    player_id,
    "Switch to " .. bait_item.name .. "?",
    mug.texture_path,
    mug.animation_path
  ))

  if response ~= 1 then
    return nil
  end

  player_data.selected_bait = bait_id

  return bait_id, bait_item, bait_count
end

Net:on("tile_interaction", function(event)
  local player_id = event.player_id

  if Net.get_player_area(player_id) ~= area_id or Net.is_player_busy(player_id) then
    return
  end

  local x, y, z = math.floor(event.x), math.floor(event.y), math.floor(event.z)
  local hash = tile_hash(x, y, z)
  local pool = resolve_pool_from_hash(hash)

  if not pool then
    return
  end

  Async.create_scope(function()
    ---@type PlayerFishingData
    local player_data = Async.await(PlayerFishingData.fetch(player_id))

    if not player_data.inventory[FishingShop.FISHING_ROD_ID] then
      local mug = Net.get_player_mugshot(player_id)

      Net.message_player(
        player_id,
        "I can see fish below the surface.",
        mug.texture_path,
        mug.animation_path
      )

      return nil
    end

    local bait_id, bait_item, bait_count = resolve_bait(player_id, player_data)

    if not bait_id or not bait_item or not bait_count then
      return nil
    end

    -- take bait
    player_data.inventory[bait_id] = bait_count - 1
    Net.give_player_item(player_id, bait_id, -1)
    player_data:save(player_id)

    -- build encounter
    local data = {
      bait_level = tonumber(StringUtil.strip_prefix(bait_id, "bait:")) or 1
    }

    if pool == pond_pool then
      data.hole = true
      data.bait_level = data.bait_level + 1
    end

    local remaining_encounters = (pool.ripple_encounters[hash] or 1) - 1
    pool.ripple_encounters[hash] = remaining_encounters

    if remaining_encounters <= 0 then
      pool.ripple_encounters[hash] = nil
      pool.available[#pool.available + 1] = hash
      pool.total_ripples = pool.total_ripples - 1
      Net.set_tile(area_id, x, y, z, 0)
    end

    local event_emitter = Net.initiate_encounter(player_id, "/server/mods/fishing/encounter", data)

    if not event_emitter then
      return nil
    end

    -- handle results
    ---@type { name: string, rank: string }[]
    local fishies = {}

    event_emitter:on("battle_message", function(event)
      fishies[#fishies + 1] = event.data
    end)

    event_emitter:on("battle_results", function()
      if #fishies == 0 then return end

      -- resolve money earned
      local earned = 0

      for i = #fishies, 1, -1 do
        local fish = fishies[i]
        local fish_name = fish.name
        local rank = fish.rank

        local rank_sell_prices = SellPrices[fish_name]

        if not rank_sell_prices then
          warn("caught invalid fish: ", fish)
          table.remove(fishies, i)
          goto continue
        end

        local sell_price = rank_sell_prices[rank]

        if not sell_price then
          warn("caught invalid fish: ", fish)
          table.remove(fishies, i)
          goto continue
        end

        earned = earned + sell_price
        ::continue::
      end

      -- update stats
      for _, fish in ipairs(fishies) do
        local fish_name = fish.name
        local rank = fish.rank

        local rank_counts = player_data.fish_caught[fish_name]

        if not rank_counts then
          rank_counts = {}
          player_data.fish_caught[fish_name] = rank_counts
        end

        rank_counts[rank] = (rank_counts[rank] or 0) + 1
      end

      player_data.money = player_data.money + earned
      player_data:save(player_id)
      Net.set_player_money(player_id, player_data.money)

      Leaderboard.add_points(player_id, earned)
      Leaderboard.save()

      Async.create_scope(function()
        -- display visuals to the player
        ---@type Net.SpriteId | nil
        local fish_sprite

        for i, fish in ipairs(fishies) do
          local fish_name = fish.name
          local rank = fish.rank

          Net.synchronize(function()
            if fish_sprite then
              Net.remove_sprite(fish_sprite)
            end

            fish_sprite = Net.create_sprite({
              parent_id = player_id,
              texture_path = "/server/assets/ui/fish.png",
              animation_path = "/server/assets/ui/fish.animation",
              animation = fish_name .. "_" .. rank
            })
          end)

          if i == #fishies then
            -- linger longer on the last fish
            Async.await(Async.sleep(2))
          end
        end

        local text_sprite

        Net.synchronize(function()
          if fish_sprite then
            Net.remove_sprite(fish_sprite)
          end

          text_sprite = Net.create_text_sprite({
            parent_id = player_id,
            parent_point = "EMOTE",
            y = -4,
            text = tostring(earned),
            text_style = {
              font = "MENU_TITLE",
              shadow_color = { r = 50, g = 50, b = 50 },
              monospace = true
            },
            h_align = "center",
            v_align = "bottom",
          })
        end)

        Async.await(Async.sleep(2))

        Net.remove_sprite(text_sprite)

        return nil
      end)
    end)

    return nil
  end)
end)

Net:on("item_use", function(event)
  local bait_item = FishingShop.BAIT_ITEM_MAP[event.item_id]

  if not bait_item then
    warn("invalid item selection: ", event.item_id)
    return
  end

  PlayerFishingData.fetch(event.player_id)
      .and_then(function(data)
        local item_count = data.inventory[event.item_id] or 0

        if item_count <= 0 then
          return
        end

        data.selected_bait = event.item_id
        local mug = Net.get_player_mugshot(event.player_id)
        local message = "Set " .. bait_item.name .. " as bait."
        Net.message_player(event.player_id, message, mug.texture_path, mug.animation_path)
      end)
end)

local player_count = 0

local function updated_player_count()
  pond_pool.max_ripple_encounters = math.max(2, 2 * player_count)

  local date = os.date("*t")
  local hour = string.format("%02d", date.hour)
  local min = string.format("%02d", date.min)

  print("[" .. hour .. ":" .. min .. "] player count: " .. player_count)
end

Net:on("player_request", function()
  player_count = player_count + 1
  updated_player_count()
end)

Net:on("player_disconnect", function()
  player_count = player_count - 1
  updated_player_count()
end)

local function spawn_ripples()
  for _, pool in ipairs(pools) do
    if pool.total_ripples < pool.max_ripples then
      local hash = table.remove(pool.available, math.random(#pool.available))
      pool.ripple_encounters[hash] = math.random(pool.min_ripple_encounters, pool.max_ripple_encounters)
      pool.total_ripples = pool.total_ripples + 1

      local x, y, z = position_from_hash(hash)
      Net.set_tile(area_id, x, y, z, relevant_tile_id)
    end
  end

  Async.sleep(80).and_then(spawn_ripples)
end

spawn_ripples()
