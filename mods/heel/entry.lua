local spawn_pattern = {
  { 2, 2 }, -- center
  { 1, 3 }, -- bottom left
  { 3, 1 }, -- top right
  { 1, 1 }, -- top left
  { 3, 3 }, -- bottom right
  { 1, 2 }, -- back
  { 1, 3 }, -- front
  { 2, 1 }, -- top
  { 2, 3 }, -- bottom
}

function encounter_init(encounter, data)
  if not data then
    data = { player_count = 1 }
  end

  encounter:set_spectate_on_delete(true)

  local active_player_count = data.red_player_count + data.blue_player_count

  for i = 0, encounter:player_count() - 1 do
    if i < active_player_count then
      local spawn_index = i

      spawn_index = spawn_index % #spawn_pattern + 1

      local position = spawn_pattern[spawn_index]

      encounter:spawn_player(i, position[1], position[2])
    else
      encounter:mark_spectator(i)
    end
  end

  encounter:create_spawner("dev.konstinople.enemy.HeelNavi", Rank.V1)
      :spawn_at(5, 2)
end
