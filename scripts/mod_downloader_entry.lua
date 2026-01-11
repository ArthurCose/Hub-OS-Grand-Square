local ModDownloader = require("scripts/libs/mod_downloader")

local package_ids = {
  -- fishing
  "BattleNetwork1.SharkMan",
  "BattleNetwork4.Bass",
  "BattleNetwork6.Cragger",
  "BattleNetwork6.Piranha",
  "BattleNetwork5.TileStates.Sea",
  -- libraries
  "BattleNetwork6.Libraries.HitDamageJudge",
  "dev.konstinople.library.timers",
  "BattleNetwork.Assets",
  "BattleNetwork4.TournamentIntro",
  "BattleNetwork6.Libraries.PanelGrab",
  "dev.konstinople.library.sword",
  "dev.konstinople.library.iterator",
  "dev.konstinople.library.ai",
  "dev.konstinople.library.spectator_fun",
}

ModDownloader.maintain(package_ids)

-- preload
Net:on("player_connect", function(event)
  Net.provide_package_for_player(event.player_id, ModDownloader.resolve_asset_path("BattleNetwork.Assets"))
  Net.provide_package_for_player(event.player_id, ModDownloader.resolve_asset_path("dev.konstinople.library.ssb"))
end)
