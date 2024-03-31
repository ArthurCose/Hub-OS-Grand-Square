local function debug_print(...)
  -- local s = ""
  -- for _, value in ipairs({ ... }) do
  --   s = s .. tostring(value)
  -- end
  -- print(s)
end

---@class Arena
---@field area_id string
---@field x number
---@field y number
---@field z number
---@field center_x number
---@field center_y number
---@field fight_active boolean
---@field red_players string[]
---@field blue_players string[]
---@field countdown_bots string[]
---@field cancel_countdown_callback? function
local Arena = {}
Arena.__index = Arena

local bot_offsets = {
  { -1.5, -1 },
  { -1.5, 1 },
  { 1.5,  -1 },
  { 1.5,  1 },
}

---@return Arena
function Arena:new(area_id, tile_x, tile_y, tile_z)
  local center_x = tile_x + 0.5
  local center_y = tile_y + 1

  local countdown_bots = {}

  for _, offset in ipairs(bot_offsets) do
    countdown_bots[#countdown_bots + 1] = Net.create_bot({
      area_id = area_id,
      warp_in = false,
      texture_path = "/server/assets/bots/pvp_countdown.png",
      animation_path = "/server/assets/bots/pvp_countdown.animation",
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
    countdown_bots = countdown_bots,
  }
  setmetatable(arena, self)

  return arena
end

function Arena:try_reset()
  -- resolve if we should reset the arena for new players
  local should_reset =
      (not self.fight_active and (#self.red_players == 0 or #self.blue_players == 0)) or
      (self.fight_active and (#self.red_players + #self.blue_players == 0))

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

---@param self Arena
local function start_encounter(self)
  local player_ids = {}

  for _, player_id in ipairs(self.red_players) do
    player_ids[#player_ids + 1] = player_id
  end

  for _, player_id in ipairs(self.blue_players) do
    player_ids[#player_ids + 1] = player_id
  end

  Net.initiate_netplay(player_ids, "/server/assets/encounters/pvp_arena.zip", {
    player_count = #player_ids,
    red_player_count = #self.red_players,
  })
end

function Arena:try_start()
  -- resolve if we should reset the arena for new players
  local can_start =
      not self.fight_active and #self.red_players > 0 and #self.blue_players > 0 and not self.cancel_countdown_callback

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
  Async.sleep(3).and_then(function()
    if cancelled then
      return
    end

    Net.synchronize(function()
      -- fight! instead of the timer
      for _, bot_id in ipairs(self.countdown_bots) do
        Net.animate_bot(bot_id, "FIGHT")
      end

      -- make players face opponents
      for _, player_id in ipairs(self.red_players) do
        Net.lock_player_input(player_id)
        Net.animate_player_properties(player_id, {
          {
            properties = { { property = "Direction", value = "DOWN RIGHT" } },
            duration = 1
          }
        })
      end

      for _, player_id in ipairs(self.blue_players) do
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

---@param tracked_player TrackedPlayer
function Arena:launch_player(tracked_player)
  local target_x
  local facing_direction

  if tracked_player.x < self.center_x then
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
        { property = "X", value = target_x,         ease = "Linear" },
        { property = "Y", value = tracked_player.y, ease = "Linear" },
        { property = "Z", value = self.z,           ease = "In" }
      },
      duration = duration
    }
  })
end

---@param x number
---@param y number
---@param z number
function Arena:overlaps(x, y, z)
  return
      (z == self.z) and
      (x > self.x and x < self.x + 3) and
      (y > self.y and y < self.y + 2)
end

return Arena
