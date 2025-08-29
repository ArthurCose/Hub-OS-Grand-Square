local json = require("scripts/libs/json")

local BOARD_COLOR = { r = 104, g = 184, b = 111 }
local BOARD_PREV_COLOR = { r = 216, g = 144, b = 31 }

---@class FishingLeaderboardRow
---@field name string
---@field points number

---@class FishingLeaderboardData
---@field year number
---@field month number
---@field players table<string, FishingLeaderboardRow> raw identity -> data

---@class FishingLeaderboard
---@field package current FishingLeaderboardData
local FishingLeaderboard = {
  current = { year = 0, month = 0, players = {} },
  prev = { year = 0, month = 0, players = {} }
}

local ARCHIVE_PATH = "scripts/fishing/_data/leaderboard_archive/"
local FILE_PATH = "scripts/fishing/_data/leaderboard.json"

---@param year number
---@param month number
local function archive_file_path(year, month)
  local date_string = string.format("%d-%02d", year, month)
  return ARCHIVE_PATH .. date_string .. ".json"
end

function FishingLeaderboard.reset()
  local date = os.date("*t")

  FishingLeaderboard.current.year = tonumber(date.year) --[[@as number]]
  FishingLeaderboard.current.month = tonumber(date.month) --[[@as number]]
  FishingLeaderboard.current.players = {}
end

function FishingLeaderboard.save()
  Async.write_file(FILE_PATH, json.encode(FishingLeaderboard.current))
end

function FishingLeaderboard.archive()
  local data = FishingLeaderboard.current
  FishingLeaderboard.current = FishingLeaderboard.prev
  FishingLeaderboard.prev = data
  FishingLeaderboard.reset()

  Async.ensure_dir(ARCHIVE_PATH).and_then(function()
    local path = archive_file_path(data.year, data.month)
    Async.write_file(path, json.encode(data))
  end)

  FishingLeaderboard.save()
end

---@param player_id Net.ActorId
---@param points number
function FishingLeaderboard.add_points(player_id, points)
  local identity = Net.get_player_secret(player_id)
  local data = FishingLeaderboard.current.players[identity]

  if not data then
    data = {
      name = "",
      points = 0
    }
    FishingLeaderboard.current.players[identity] = data
  end

  -- update name
  data.name = Net.get_player_name(player_id)
  -- update points
  data.points = data.points + points
end

---@param player_id Net.ActorId
---@param name string
---@param color Net.Color
---@param data FishingLeaderboardData
local function open_leaderboard(player_id, name, color, data)
  ---@type Net.BoardPost[]
  local posts = {}

  for _, row in pairs(data.players) do
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

  Net.open_board(player_id, name, color, posts)
end

---@param player_id Net.ActorId
function FishingLeaderboard.open(player_id)
  open_leaderboard(
    player_id,
    "Monthly Fishing Leaderboard",
    BOARD_COLOR,
    FishingLeaderboard.current
  )
end

---@param player_id Net.ActorId
function FishingLeaderboard.open_prev(player_id)
  open_leaderboard(
    player_id,
    "Last Month's Leaderboard",
    BOARD_PREV_COLOR,
    FishingLeaderboard.prev
  )
end

local function monthly_loop()
  local date = os.date("*t")
  local date_param = {
    year = date.year,
    month = FishingLeaderboard.current.month + 1,
    day = 1,
    hour = 0,
    min = 0,
    sec = 0
  }
  local diff = os.time(date_param) - os.time()

  Async.sleep(diff).and_then(function()
    FishingLeaderboard.archive()
    monthly_loop()
  end)
end

FishingLeaderboard.reset()

Async.read_file(FILE_PATH).and_then(function(contents)
  if contents == "" then
    monthly_loop()
    return
  end

  local loaded = json.decode(contents)

  FishingLeaderboard.current = loaded

  -- load last month's data
  local prev_time = os.time({ year = loaded.year, month = loaded.month - 1, day = 1 })
  local prev_date = os.date("*t", prev_time)

  local path = archive_file_path(prev_date.year --[[@as number]], prev_date.month --[[@as number]])

  Async.read_file(path).and_then(function(contents)
    if contents ~= "" then
      FishingLeaderboard.prev = json.decode(contents)
    end

    monthly_loop()
  end)
end)

return FishingLeaderboard
