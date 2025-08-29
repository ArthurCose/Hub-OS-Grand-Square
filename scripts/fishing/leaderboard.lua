local json = require("scripts/libs/json")

local BOARD_COLOR = { r = 104, g = 184, b = 111 }

---@class FishingLeaderboardRow
---@field name string
---@field points number

---@class FishingLeaderboardData
---@field year number
---@field month number
---@field players table<string, FishingLeaderboardRow> raw identity -> data

---@class FishingLeaderboard
---@field package data FishingLeaderboardData
local FishingLeaderboard = {
  data = { year = 0, month = 0, players = {} }
}

local ARCHIVE_PATH = "scripts/fishing/_data/leaderboard_archive/"
local FILE_PATH = "scripts/fishing/_data/leaderboard.json"

function FishingLeaderboard.reset()
  local date = os.date("*t")

  FishingLeaderboard.data.year = tonumber(date.year) --[[@as number]]
  FishingLeaderboard.data.month = tonumber(date.month) --[[@as number]]
  FishingLeaderboard.data.players = {}
end

function FishingLeaderboard.save()
  Async.write_file(FILE_PATH, json.encode(FishingLeaderboard.data))
end

function FishingLeaderboard.archive()
  local data = FishingLeaderboard.data
  local date_string = string.format("%d-%02d", data.year, data.month)

  Async.ensure_dir(ARCHIVE_PATH).and_then(function()
    Async.write_file(ARCHIVE_PATH .. date_string .. ".json", json.encode(FishingLeaderboard.data))
  end)
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
  local date_param = {
    year = date.year,
    month = FishingLeaderboard.data.month + 1,
    day = 1,
    hour = 0,
    min = 0,
    sec = 0
  }
  local diff = os.time(date_param) - os.time()

  Async.sleep(diff).and_then(function()
    FishingLeaderboard.archive()
    FishingLeaderboard.reset()
    FishingLeaderboard.save()
    monthly_loop()
  end)
end

monthly_loop()

return FishingLeaderboard
