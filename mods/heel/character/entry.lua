---@type BattleNetwork.Assets
local bn_assets = require("BattleNetwork.Assets")
---@type KonstAiLib
local AiLib = require("dev.konstinople.library.ai")
local IteratorLib = AiLib.IteratorLib

local DEFAULT_SWORD_COOLDOWN = 150
local IDLE_DURATION = 30

local POOF_PREFIX = "BIG"
local LONG_BLADE_PROPS = CardProperties.from_package("BattleNetwork6.Class01.Standard.074")
local CRAKBOM_PROPS = CardProperties.from_package("BattleNetwork5.Class01.Standard.037")

local VIRUS_POOL = {
  { package_id = "BattleNetwork3.enemy.Gloomer", rank = Rank.V1 },
  { package_id = "BattleNetwork4.Gaia+.Enemy",   rank = Rank.V1 }
}

local function default_random_tile(entity)
  local tiles = entity:field():find_tiles(function(tile)
    if not entity:can_move_to(tile) or tile == entity:current_tile() then
      return false
    end

    if tile:facing() == Direction.Right then
      return tile:x() == 1
    else
      return tile:x() == 6
    end
  end)

  if #tiles == 0 then
    -- try anything we can move to
    tiles = entity:field():find_tiles(function(tile)
      return entity:can_move_to(tile) and tile ~= entity:current_tile()
    end)
  end

  if #tiles == 0 then
    return nil
  end

  return tiles[math.random(#tiles)]
end

---@param entity Entity
local function create_move_factory(entity)
  local function target_tile_callback()
    return default_random_tile(entity)
  end

  return function()
    return bn_assets.MobMoveAction.new(entity, POOF_PREFIX, target_tile_callback)
  end
end

---@class Heel: Entity
---@field _sword_cooldown number
---@field _spawned_allies Entity[]

local function copy_sprite_tree(dest_entity, source_entity)
  local queue = { { dest_entity:sprite(), source_entity:sprite() } }

  while #queue > 0 do
    local item = queue[1]

    -- swap remove to avoid shifting
    queue[1] = queue[#queue]
    queue[#queue] = nil

    -- process
    local dest_sprite = item[1]
    local source_sprite = item[2]

    dest_sprite:copy_from(source_sprite)

    for _, user_child_sprite in ipairs(source_sprite:children()) do
      queue[#queue + 1] = { user_child_sprite, dest_sprite:create_node() }
    end
  end
end

---@param character Heel
local function create_spawn_action_factory(character)
  return function()
    for i = #character._spawned_allies, 1, -1 do
      local ally = character._spawned_allies[i]

      if ally:deleted() then
        table.remove(character._spawned_allies, i)
      end
    end

    if #character._spawned_allies >= 2 then
      return Action.new(character, "CHEER")
    end

    local field = character:field()
    local tiles = field:find_tiles(function(tile)
      if not tile:is_walkable() or tile:team() ~= character:team() or tile:is_reserved() then
        return false
      end

      local x = tile:x()

      if character:facing() == Direction.Right then
        return x >= 2 and x <= 4
      else
        return x >= 3 and x <= 5
      end
    end)

    if #tiles == 0 then
      return Action.new(character, "CHEER")
    end

    local tile = tiles[math.random(#tiles)]

    local action = Action.new(character, "SPECIAL")
    local spell, spawned_spell

    action.on_execute_func = function()
      if tile:is_reserved() then
        action:end_action()
        return
      end

      spell = Spell.new()
      spell.on_delete_func = function()
        spell:erase()
      end

      tile:reserve_for(spell)
    end

    action:add_anim_action(7, function()
      local virus = VIRUS_POOL[math.random(#VIRUS_POOL)]
      local team = character:team()

      local ally = Character.from_package(virus.package_id, team, virus.rank)
      ally:set_facing(character:facing())
      character._spawned_allies[#character._spawned_allies + 1] = ally

      spell:set_facing(character:facing())
      copy_sprite_tree(spell, ally)

      local i = 0
      local MAX = 30

      spell.on_update_func = function()
        local c = 255 - i / MAX * 255
        spell:set_color(Color.new(c, c, c, 255))

        i = i + 1

        if i == MAX - 1 then
          field:spawn(ally, tile)
        elseif i == MAX then
          spell:erase()
        end
      end

      field:spawn(spell, tile)
      spawned_spell = true
    end)

    action.on_action_end_func = function()
      if spell and not spawned_spell then
        spell:erase()
      end
    end

    return action
  end
end

---@param entity Heel
local function think_callback(entity)
  if entity._sword_cooldown > 0 then
    entity._sword_cooldown = entity._sword_cooldown - 1
    return false
  end

  local tiles = AiLib.find_setup_tiles(entity, function(other, suggest)
    suggest(other:get_tile(entity:facing_away(), 2))
  end)

  if #tiles == 0 then
    return false
  end

  local tile = tiles[math.random(#tiles)]

  entity._sword_cooldown = DEFAULT_SWORD_COOLDOWN

  entity:queue_action(bn_assets.MobMoveAction.new(entity, POOF_PREFIX, function()
    -- make sure we can still move to this tile
    if entity:can_move_to(tile) then
      local action = AiLib.create_card_action_factory(entity, LONG_BLADE_PROPS)()

      if action then
        entity:queue_action(action)
      end

      return tile
    end
  end))

  return true
end

local TEXTURE = Resources.load_texture("battle.png")

---@param character Heel
function character_init(character)
  character:set_name("HeelNavi")
  character:set_health(2000)
  character:set_height(39.0)
  character:set_texture(TEXTURE)

  character._sword_cooldown = DEFAULT_SWORD_COOLDOWN
  character._spawned_allies = {}

  local animation = character:animation()
  animation:load("battle.animation")
  animation:set_state("PLAYER_IDLE")

  character.on_idle_func = function()
    animation:set_state("PLAYER_IDLE")
  end

  character:register_status_callback(Hit.Flinch, function()
    character:cancel_actions()
    character:cancel_movement()

    local action = Action.new(character, "PLAYER_HIT")
    action:override_animation_frames({ { 1, 15 }, { 2, 7 } })
    character:queue_action(action)
  end)

  local ai = AiLib.new_ai(character)

  local move_factory = create_move_factory(character)
  local idle_factory = AiLib.create_idle_action_factory(character, IDLE_DURATION, IDLE_DURATION, think_callback)
  local bomb_factory = AiLib.create_card_action_factory(character, CRAKBOM_PROPS)
  local spawn_virus_factory = create_spawn_action_factory(character)

  local bomb_plan = ai:create_plan()
  bomb_plan:set_weight(7)
  bomb_plan:set_action_iter_factory(function()
    return IteratorLib.chain(
    -- 4 - 6 random movements + idling
      IteratorLib.flatten(
        IteratorLib.take(math.random(4, 6), function()
          return IteratorLib.chain(
            IteratorLib.take(1, move_factory),
            IteratorLib.take(1, idle_factory)
          )
        end)
      ),
      -- find a good tile for crakbom
      IteratorLib.take(1, function()
        return bn_assets.MobMoveAction.new(character, POOF_PREFIX, function()
          local tiles = AiLib.find_setup_tiles(
            character,
            function(other, suggest)
              local middle = other:get_tile(character:facing_away(), 3)

              if middle then
                suggest(middle:get_tile(Direction.Up, 1))
                suggest(middle:get_tile(Direction.Down, 1))
              end
            end,
            function(tile)
              return character:can_move_to(tile) and tile:get_tile(character:facing(), 3):is_walkable()
            end
          )

          if #tiles > 0 then
            return tiles[math.random(#tiles)]
          else
            -- try any random tile as a default
            return default_random_tile(character)
          end
        end)
      end),
      -- toss the bomb
      IteratorLib.take(1, bomb_factory)
    )
  end)

  local spawn_virus_plan = ai:create_plan()
  spawn_virus_plan:set_weight(3)
  spawn_virus_plan:set_action_iter_factory(function()
    return IteratorLib.chain(
    -- 4 - 6 random movements + idling
      IteratorLib.flatten(
        IteratorLib.take(math.random(4, 6), function()
          return IteratorLib.chain(
            IteratorLib.take(1, move_factory),
            IteratorLib.take(1, idle_factory)
          )
        end)
      ),
      -- use the default movement logic to find the setup tile
      IteratorLib.take(1, move_factory),
      IteratorLib.take(1, spawn_virus_factory)
    )
  end)

  character.on_delete_func = function()
    character:default_player_delete()

    for _, ally in ipairs(character._spawned_allies) do
      ally:delete()
    end
  end
end
