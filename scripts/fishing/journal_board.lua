local PlayerFishingData = require("scripts/fishing/player_data")

-- local BOARD_COLOR = { r = 144, g = 184, b = 191 }
local BOARD_COLOR = { r = 111, g = 159, b = 167 }

local order = {
  { "Piranha1",  "Piranha",  "V1" },
  { "Piranha2",  "Piranha",  "V2" },
  { "Piranha3",  "Piranha",  "V3" },
  { "PiranhaSP", "Piranha",  "SP" },
  { "RarePira1", "Piranha",  "Rare1" },
  { "RarePira2", "Piranha",  "Rare2" },
  { "SharkMan",  "SharkMan", "V1" },
  { "Bass",      "Bass",     "V1" },
}

local JournalBoard = {}

---@param player_id Net.ActorId
function JournalBoard.open(player_id)
  PlayerFishingData.fetch(player_id).and_then(function(data)
    ---@type Net.BoardPost[]
    local posts = {}

    for _, row in ipairs(order) do
      local display_name, fish_name, rank = row[1], row[2], row[3]

      local rank_map = data.fish_caught[fish_name]

      if not rank_map then
        goto continue
      end

      local caught_count = rank_map[rank]

      if not caught_count then
        goto continue
      end

      posts[#posts + 1] = {
        id = tostring(#posts),
        title = display_name,
        author = tostring(caught_count),
        read = true
      }

      ::continue::
    end

    Net.open_board(player_id, "Fishing Journal", BOARD_COLOR, posts)
  end)
end

return JournalBoard
