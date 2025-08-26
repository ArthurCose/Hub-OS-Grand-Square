local json = require("scripts/libs/json")

local BOARD_COLOR = { r = 104, g = 184, b = 111 }

---@class FishingLeaderboardRow
---@field name string
---@field points number

---@class FishingLeaderboardData
---@field players table<string, FishingLeaderboardRow> raw identity -> data
---@field month number

---@class FishingLeaderboard
---@field package data FishingLeaderboardData
local FishingLeaderboard = {
  data = { players = {}, month = 0 }
}

local FILE_PATH = "scripts/fishing/_data/leaderboard.json"

function FishingLeaderboard.reset()
  FishingLeaderboard.data.players = {}
  FishingLeaderboard.data.month = tonumber(os.date("*t").month) --[[@as number]]
end

function FishingLeaderboard.save()
  Async.write_file(FILE_PATH, json.encode(FishingLeaderboard.data))
end

---@param player_id Net.ActorId
---@param points number
function FishingLeaderboard.add_points(player_id, points)
  local identity = Net.get_player_secret(player_id)
  local data = FishingLeaderboard.data.players[identity]

  if not data then
    data = {
      name = "",
      points = 0
    }
    FishingLeaderboard.data.players[identity] = data
  end

  -- update name
  data.name = Net.get_player_name(player_id)
  -- update points
  data.points = data.points + points
end

---@param player_id Net.ActorId
function FishingLeaderboard.open(player_id)
  ---@type Net.BoardPost[]
  local posts = {}

  for _, row in pairs(FishingLeaderboard.data.players) do
    posts[#posts + 1] = {
      id = tostring(#posts),
      title = row.name,
      author = tostring(row.points) .. "z",
      points = row.points,
      read = true
    }
  end

  ---@param a any
  ---@param b any
  table.sort(posts, function(a, b)
    return b.points < a.points
  end)

  Net.open_board(player_id, "Monthly Fishing Leaderboard", BOARD_COLOR, posts)
end

FishingLeaderboard.reset()

Async.read_file(FILE_PATH).and_then(function(contents)
  if contents == "" then
    return
  end

  local loaded = json.decode(contents)

  if loaded.month == FishingLeaderboard.data.month then
    FishingLeaderboard.data = loaded
  end
end)

local function monthly_loop()
  local date = os.date("*t")
  local diff = os.time({ year = date.year, month = FishingLeaderboard.data.month + 1, day = 1 }) - os.time()

  Async.sleep(diff).and_then(function()
    FishingLeaderboard.reset()
    monthly_loop()
  end)
end

monthly_loop()

return FishingLeaderboard
