local ModDownloader = require("scripts/libs/mod_downloader")

local package_ids = {
  -- chips
  "BattleNetwork6.Class01.Standard.164", -- panel grab
  "BattleNetwork5.Class01.Standard.037", -- crakbom
  "BattleNetwork6.Class01.Standard.074", -- longblde
  -- encounters
  "BattleNetwork3.Virus.Boomer",
  "BattleNetwork4.Gaia",
  -- libraries
  "BattleNetwork.Assets",
  "BattleNetwork.FallingRock",
  "BattleNetwork6.Libraries.PanelGrab",
  "dev.konstinople.library.sword",
  "dev.konstinople.library.bomb",
  "dev.konstinople.library.iterator",
  "dev.konstinople.library.ai",
}

ModDownloader.maintain(package_ids)

-- preload
Net:on("player_connect", function(event)
  Net.provide_package_for_player(event.player_id, ModDownloader.resolve_asset_path("BattleNetwork.Assets"))
end)
