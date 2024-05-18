Net:on("player_connect", function(event)
  Net.provide_package_for_player(event.player_id, "/server/mods/mods/libraries/battle_network_assets")
end)
