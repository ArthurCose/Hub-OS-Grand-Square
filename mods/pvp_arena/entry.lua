local HitDamageJudge = require("BattleNetwork6.Libraries.HitDamageJudge")
local SpectatorFun = require("dev.konstinople.library.spectator_fun")
local Timers = require("dev.konstinople.library.timers")

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

function encounter_init(encounter, data)
  encounter:set_turn_limit(15)
  encounter:set_time_freeze_chain_limit(TimeFreezeChainLimit.Unlimited)
  HitDamageJudge.init(encounter)
  SpectatorFun.init(encounter)

  Timers.AfkTimer.init(encounter)
  Timers.CardSelectTimer.init(encounter)
  Timers.TurnTimer.init(encounter)

  encounter:set_spectate_on_delete(true)

  local active_player_count = data.red_player_count + data.blue_player_count

  for i = 0, encounter:player_count() - 1 do
    if i < active_player_count then
      local spawn_index = i
      local is_blue = i >= data.red_player_count

      if is_blue then
        spawn_index = spawn_index - data.red_player_count
      end

      spawn_index = spawn_index % #spawn_pattern + 1

      local position = spawn_pattern[spawn_index]

      if is_blue then
        -- blue (mirror)
        encounter:spawn_player(i, 7 - position[1], position[2])
      else
        -- red
        encounter:spawn_player(i, position[1], position[2])
      end
    else
      encounter:mark_spectator(i)
    end
  end
end
