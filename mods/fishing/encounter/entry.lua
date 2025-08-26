local create_fishing_action = require("fishing_action")

local piranha_id = "BattleNetwork6.Piranha.Enemy"
local piranha_v1 = { id = piranha_id, rank = Rank.V1 }
local piranha_v2 = { id = piranha_id, rank = Rank.V2 }
local piranha_v3 = { id = piranha_id, rank = Rank.V3 }
local piranha_sp = { id = piranha_id, rank = Rank.SP }
local piranha_rare1 = { id = piranha_id, rank = Rank.Rare1 }
local piranha_rare2 = { id = piranha_id, rank = Rank.Rare2 }

local cragger_id = "BattleNetwork6.Cragger.Enemy"
local cragger_v1 = { id = cragger_id, rank = Rank.V1 }
local cragger_v2 = { id = cragger_id, rank = Rank.V2 }
local cragger_v3 = { id = cragger_id, rank = Rank.V3 }
local cragger_sp = { id = cragger_id, rank = Rank.SP }
local cragger_rare1 = { id = cragger_id, rank = Rank.Rare1 }
local cragger_rare2 = { id = cragger_id, rank = Rank.Rare2 }

local pool_weights = {
  -- bait level 1
  { 7, 1, 0, 0, 0 },
  -- bait level 2
  { 1, 2, 0, 0, 0 },
  -- bait level 3
  { 0, 1, 1, 0, 0 },
  -- bait level 4
  { 0, 1, 2, 2, 0 },
  -- bait level 5
  { 0, 1, 2, 6, 1 },
}

local enemy_pools = {
  -- unlocked at bait level 1
  {
    { piranha_v1 },
    { piranha_v1, piranha_v1 },
    { piranha_v1, piranha_v2 },
  },

  -- unlocked at bait level 2
  {
    { piranha_v1, piranha_v2 },
    { piranha_v2, piranha_v2 },
    { piranha_v2, cragger_v1 }
  },

  -- unlocked at bait level 3
  {
    { piranha_v2, piranha_v2, cragger_v1 },
    { piranha_v2, piranha_v3, cragger_v2 },
    { piranha_v3, piranha_v3, cragger_v3 }
  },

  -- unlocked at bait level 4
  {
    { piranha_v3, piranha_sp, cragger_sp },
    { piranha_v3, piranha_sp, cragger_v1 },
    { piranha_sp, piranha_sp, cragger_rare1 }
  },

  -- unlocked at bait level 5
  {
    { piranha_sp,    piranha_sp,    cragger_v2, },
    { piranha_sp,    piranha_rare1, cragger_rare1, },
    { piranha_v2,    piranha_rare1, cragger_v2, },
    { piranha_sp,    piranha_rare2, cragger_rare1, cragger_rare2 },
    { piranha_rare2, cragger_v3,    cragger_rare1 },
  },
}

local function resolve_pool_index(bait_level)
  local weights = pool_weights[bait_level]

  local max_weight = 0
  for _, value in ipairs(weights) do
    max_weight = max_weight + value
  end

  local target = math.random(max_weight)
  local last_non_zero = 1

  for i, value in ipairs(weights) do
    if value > 0 then
      last_non_zero = i

      target = target - value

      if target <= 0 then
        return i
      end
    end
  end

  return last_non_zero
end

---@param encounter Encounter
function encounter_init(encounter, data)
  encounter:set_turn_limit(1)
  encounter:enable_automatic_turn_end(true)
  TurnGauge.set_max_time(512 * 3 / 2)

  encounter:on_battle_end(function()
    -- pause everything at battle end
    local dummy = Artifact.new()
    local action = Action.new(dummy)
    action:set_lockout(ActionLockout.new_sequence())

    -- lock indefinitely
    action:create_step()

    local card_properties = CardProperties.new()
    card_properties.time_freeze = true
    card_properties.skip_time_freeze_intro = true
    action:set_card_properties(card_properties)

    dummy:queue_action(action)
    Field.spawn(dummy, 0, 0)
  end)

  -- resolve enemies
  local pool_index = resolve_pool_index(data.bait_level)

  local enemy_pool = enemy_pools[pool_index]
  local enemies = enemy_pool[math.random(#enemy_pool)]

  -- resolve battle field
  local blue_start = 4
  local blue_end = Field.width() - 2

  if pool_index >= 3 and #enemies <= 3 then
    -- increase enemy space to increase difficulty
    blue_start = blue_start - 1
  end

  local tile_pool = {}

  for y = 1, Field.height() - 2 do
    for x = blue_start, blue_end do
      local tile = Field.tile_at(x, y) --[[@as Tile]]

      if data.hole and y == 2 and x ~= blue_start and x ~= blue_end then
        tile:set_state(TileState.Void)
      else
        tile:set_team(Team.Blue, Direction.Left)
        tile:set_state(TileState.Sea)
        tile_pool[#tile_pool + 1] = tile
      end
    end
  end

  -- resolve spawn positions
  local column_spawn_counts = {}

  for _, enemy in ipairs(enemies) do
    while true do
      local tile = table.remove(tile_pool, math.random(#tile_pool))
      local x = tile:x()

      local column_spawn_count = column_spawn_counts[x] or 0

      if column_spawn_count < 2 then
        encounter:create_spawner(enemy.id, enemy.rank):spawn_at(x, tile:y())
        column_spawn_counts[x] = column_spawn_count + 1
        break
      end
    end
  end

  -- fishing logic
  local artifact = Artifact.new()
  artifact.on_update_func = function()
    artifact:delete()

    Field.find_players(function(player)
      local component = player:create_component(Lifetime.ActiveBattle)
      local time_since_action = 0

      component.on_update_func = function()
        if player:has_actions() then
          time_since_action = 0
          return
        end

        time_since_action = time_since_action + 1

        if time_since_action < 5 then
          -- avoid accidentally casting again
          return
        end

        if not player:input_has(Input.Pressed.Use) then
          return
        end

        if player:is_inactionable() or player:field_card(1) ~= nil then
          return
        end

        local action = create_fishing_action(player, function(fish_data)
          encounter:send_to_server({
            name = fish_data.name,
            rank = fish_data.rank
          })

          encounter:end_scene()
        end)

        player:queue_action(action)
      end

      return false
    end)
  end

  Field.spawn(artifact, 0, 0)
end
