local HitDamageJudge = require("BattleNetwork6.Libraries.HitDamageJudge")
local SpectatorFun = require("dev.konstinople.library.spectator_fun")
local Timers = require("dev.konstinople.library.timers")

local function create_player_spawn_resolver()
  local spawn_pattern = {
    { 2, 2 }, -- center
    { 1, 3 }, -- bottom left
    { 1, 1 }, -- top left
    { 3, 3 }, -- bottom right
    { 3, 1 }, -- top right
    { 1, 2 }, -- back
    { 3, 2 }, -- front
    { 2, 1 }, -- top
    { 2, 3 }, -- bottom
  }

  local red_attempts = 0
  local blue_attempts = 0

  ---@param team Team
  return function(team)
    while true do
      local spawn_index

      if team == Team.Blue then
        spawn_index = blue_attempts
        blue_attempts = blue_attempts + 1
      else
        spawn_index = red_attempts
        red_attempts = red_attempts + 1
      end

      spawn_index = spawn_index % #spawn_pattern + 1

      local position = spawn_pattern[spawn_index]
      local x, y = position[1], position[2]

      if team == Team.Blue then
        -- mirror
        x = 7 - x
      end

      local tile = Field.tile_at(x, y)

      if not tile then
        goto continue
      end

      if tile:is_walkable() and not tile:is_reserved() then
        return x, y
      end

      if team == Team.Blue then
        tile = tile:get_tile(Direction.Right, 1)
      else
        tile = tile:get_tile(Direction.Left, 1)
      end

      if tile and tile:is_walkable() and not tile:is_reserved() then
        return tile:x(), tile:y()
      end

      ::continue::
    end
  end
end

---@param encounter Encounter
---@param teams { team: string, player_count: number }[]
---@param callback fun(index: number, team_name: string?)
local function for_players_in_teams(encounter, teams, callback)
  local team = teams[1]
  local remaining = (team and team.player_count) or 0
  local next_team_i = 2

  for i = 0, encounter:player_count() - 1 do
    while team and remaining == 0 do
      team = teams[next_team_i]
      next_team_i = next_team_i + 1

      if team then
        remaining = team.player_count
      end
    end

    callback(i, team and team.team)
    remaining = remaining - 1
  end
end


---@param encounter Encounter
function encounter_init(encounter, data)
  encounter:set_turn_limit(15)
  encounter:set_time_freeze_chain_limit(TimeFreezeChainLimit.Unlimited)
  HitDamageJudge.init(encounter)
  SpectatorFun.init(encounter)

  Timers.AfkTimer.init(encounter)
  Timers.CardSelectTimer.init(encounter)
  Timers.TurnTimer.init(encounter)

  encounter:set_spectate_on_delete(true)

  local active_player_count = 0

  local resolve_spawn = create_player_spawn_resolver()

  for_players_in_teams(encounter, data.teams, function(i, team_name)
    if team_name == "red" or team_name == "blue" then
      active_player_count = active_player_count + 1

      local team

      if team_name == "blue" then
        team = Team.Blue
      else
        team = Team.Red
      end

      local x, y = resolve_spawn(team)
      encounter:spawn_player(i, x, y)
    else
      encounter:mark_spectator(i)
    end
  end)

  if active_player_count > 2 then
    -- prevent enemy teams from owning certain columns in a multibattle
    -- set to Team.Other instead

    local artifact = Artifact.new()
    local component = artifact:create_component(Lifetime.Scene)
    component.on_update_func = function()
      local function neutralize_column(x)
        for y = 0, Field.height() - 1 do
          local tile = Field.tile_at(x, y)

          if tile and tile:team() ~= tile:original_team() and tile:team() ~= Team.Other then
            tile:set_team(Team.Other, tile:facing())
          end
        end
      end

      neutralize_column(2)
      neutralize_column(Field.width() - 3)
    end
  end

  -- by LDR's request
  encounter:set_entities_share_ownership(false)
end
