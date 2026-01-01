local bn_assets = require("BattleNetwork.Assets")
local BombLib = require("dev.konstinople.library.bomb")
local fish_behavior = require("fish_behavior")

local ROD_TEXTURE = Resources.load_texture("fishing_rod.png")
local ROD_ANIM_PATH = "fishing_rod.animation"

local PULL_SFX = bn_assets.load_audio("feather.ogg")
local SNAP_SFX = bn_assets.load_audio("hit.ogg")
local SUCCESS_SFX = bn_assets.load_audio("battle_counterhit.ogg")

local bomb = BombLib.new_bomb()
bomb:set_bomb_texture(Resources.load_texture("lure.png"))
bomb:set_bomb_animation_path(_folder_path .. "lure.animation")
bomb:set_bomb_shadow(bn_assets.load_texture("bomb_shadow.png"))
bomb:set_execute_sfx(bn_assets.load_audio("lob_bomb.ogg"))

local BOMB_FRAME_DATA = bomb:frame_data()
BOMB_FRAME_DATA[#BOMB_FRAME_DATA][2] = 99999

local REEL_FAIL_FRAME_DATA = { { 3, 4 }, { 4, 5 } }

local REEL_INPUTS = {
  Input.Pressed.Left,
  Input.Pressed.Use,
  Input.Pressed.Shoot
}

local function any(list, callback)
  for index, value in ipairs(list) do
    if callback(value, index) then
      return true
    end
  end
  return false
end

---@param fish Entity
local function resolve_fish_behavior(fish)
  local rank_table = fish_behavior[fish:name()]

  if not rank_table then
    return nil
  end

  return rank_table[fish:rank()]
end

local INITIAL_DISTANCE = 3

local function resolve_timing(timing_table, distance)
  local range = timing_table[INITIAL_DISTANCE - distance + 1] or timing_table[#timing_table]
  return math.random(range[1], range[2])
end

---@param user Entity
---@param fish Entity
---@param success_callback fun(fish_data: GrandSquare.Fishing.FishData)
local function create_reeling_action(user, fish, success_callback)
  local action = Action.new(user, "CHARACTER_SWING_HILT")
  action:override_animation_frames({ { 1, 1 } })
  action:set_lockout(ActionLockout.new_sequence())

  local rod = action:create_attachment("ENDPOINT")
  rod:sprite():set_texture(ROD_TEXTURE)
  rod:sprite():use_root_shader()
  local rod_animation = rod:animation()
  rod_animation:load(ROD_ANIM_PATH)
  rod_animation:set_state("DEFAULT", { { 1, 1 } })

  local animation = user:animation()
  local success = false
  local reeling = false
  local distance = INITIAL_DISTANCE
  local fish_tile
  local behavior = resolve_fish_behavior(fish) --[[@as GrandSquare.Fishing.FishData]]

  -- handles movement without modifying callbacks on the fish entity
  local artifact = Artifact.new()
  artifact:enable_sharing_tile(false)
  local last_artifact_tile = nil

  artifact.on_update_func = function()
    local current_tile = artifact:current_tile()

    if not last_artifact_tile then
      current_tile:reserve_for(artifact)
    elseif last_artifact_tile ~= current_tile then
      last_artifact_tile:remove_reservation_for(artifact)
      current_tile:reserve_for(artifact)
    end

    current_tile:add_entity(fish)
    last_artifact_tile = current_tile

    local artifact_offset = artifact:movement_offset()
    local fish_offset = fish:movement_offset()
    fish:set_movement_offset(fish_offset.x + artifact_offset.x, fish_offset.y + artifact_offset.y)
  end

  local reservation_exclusions = { fish:id() }

  artifact.can_move_to_func = function(tile)
    return (tile:is_walkable() and not tile:is_reserved(reservation_exclusions)) or
        (not user:deleted() and tile == user:current_tile())
  end

  action.on_execute_func = function()
    fish_tile = user:get_tile(user:facing(), distance)

    if not behavior or not fish_tile then
      action:end_action()
      return
    end

    Field.spawn(artifact, fish_tile)
  end

  local reeling_step = action:create_step()
  local fight_timer = 0
  local max_fight_time = 0
  reeling_step.on_update_func = function()
    if
        fish:deleted()
        or (not artifact:is_moving() and artifact:current_tile() ~= fish_tile)
        or fish:current_tile():y() ~= user:current_tile():y()
    then
      Resources.play_audio(SNAP_SFX)
      action:end_action()
      return
    end

    if not artifact:is_moving() and distance == 0 then
      success = true
      action:end_action()
    end

    -- refresh status
    fish:apply_status(Hit.HookFish, 9999)

    if reeling then
      fight_timer = 0

      if any(REEL_INPUTS, function(input) return user:input_has(input) end) then
        -- snap the line if the player is mashing
        Resources.play_audio(SNAP_SFX)

        reeling_step.on_update_func = nil

        rod_animation:set_state("DEFAULT", REEL_FAIL_FRAME_DATA)
        animation:set_state("CHARACTER_SWING_HILT", REEL_FAIL_FRAME_DATA)
        animation:on_complete(function()
          action:end_action()
        end)
      end

      return
    end

    if artifact:is_moving() then
      -- fish is moving, block new actions
      return
    end

    if distance < INITIAL_DISTANCE then
      -- fight the line!

      if fight_timer == 0 then
        max_fight_time = resolve_timing(behavior.fight_timing, distance + 1)
      end

      if fight_timer >= max_fight_time then
        local next_tile = user:get_tile(user:facing(), distance + 1)

        if next_tile and artifact:can_move_to(next_tile) then
          fight_timer = 0
          distance = distance + 1
          fish_tile = next_tile

          artifact:slide(fish_tile, resolve_timing(behavior.slide_timing, distance))
          return
        end
      end

      fight_timer = fight_timer + 1
    end

    if not any(REEL_INPUTS, function(input) return user:input_has(input) end) then
      return
    end

    -- reel the fish in!
    reeling = true
    local timing = resolve_timing(behavior.slide_timing, distance)

    local frame_data = { { 3, 4 }, { 4, timing }, { 3, 4 }, { 1, 0 } }

    rod_animation:set_state("DEFAULT", frame_data)
    animation:set_state("CHARACTER_SWING_HILT", frame_data)
    animation:on_frame(2, function()
      distance = distance - 1
      fish_tile = user:get_tile(user:facing(), distance)

      if not fish_tile or not fish_tile:is_walkable() then
        Resources.play_audio(SNAP_SFX)
        action:end_action()
      end

      Resources.play_audio(PULL_SFX)
      artifact:slide(fish_tile, timing)
    end)

    animation:on_frame(3, function()
      reeling = false
    end)

    if artifact:is_moving() then
      -- already moving
      return
    end
  end

  action.on_action_end_func = function()
    if not fish:deleted() then
      fish:remove_status(Hit.HookFish)
    end

    if not artifact:deleted() then
      artifact:delete()
    end

    if success and not fish:deleted() then
      Resources.play_audio(SUCCESS_SFX)
      success_callback(behavior)
      fish:erase()
      fish:hide()
    else
      -- resume
      TurnGauge.set_enabled(true)
    end
  end

  return action
end

---@param user Entity
---@param success_callback fun(fish_data: GrandSquare.Fishing.FishData)
local function create_casting_action(user, success_callback)
  local action

  ---@param tile Tile
  action = bomb:create_action(user, function(tile)
    if user:deleted() then
      return
    end

    user:cancel_actions()

    local aqua_enemies = tile:find_characters(function(c)
      return
          c:team() ~= user:team() and
          c:element() == Element.Aqua and
          c:hittable() and
          c:remaining_status_time(Hit.HookFish) == 0
    end)

    local fish = aqua_enemies[1]

    if fish then
      TurnGauge.set_enabled(false)
      fish:apply_status(Hit.HookFish, 9999)
      user:queue_action(create_reeling_action(user, fish, success_callback))
    end
  end)

  return action
end

return create_casting_action
