---@class GrandSquare.Fishing.FishData
---@field name string
---@field rank string
---@field slide_timing [number, number][] at most 2 should be defined
---@field fight_timing [number, number][] at most 2 should be defined, fish can't fight at the furthest distance

---@type table<string, table<Rank, GrandSquare.Fishing.FishData>>
local fish_data = {}

fish_data.Piranha = {
  [Rank.V1] = {
    name = "Piranha",
    rank = "V1",
    slide_timing = { { 12, 12 } },
    fight_timing = { { 15, 20 } },
  },
  [Rank.V2] = {
    name = "Piranha",
    rank = "V2",
    slide_timing = { { 8, 12 } },
    fight_timing = { { 12, 16 }, { 6, 10 } },
  },
  [Rank.V3] = {
    name = "Piranha",
    rank = "V3",
    slide_timing = { { 6, 12 } },
    fight_timing = { { 8, 12 }, { 5, 7 } },
  },
  [Rank.SP] = {
    name = "Piranha",
    rank = "SP",
    slide_timing = { { 8, 10 }, { 6, 8 } },
    fight_timing = { { 6, 9 }, { 3, 5 }, },
  },
  [Rank.Rare1] = {
    name = "Piranha",
    rank = "Rare1",
    slide_timing = { { 8, 10 }, { 4, 6 } },
    fight_timing = { { 4, 6 }, { 2, 3 } },
  },
  [Rank.Rare2] = {
    name = "Piranha",
    rank = "Rare2",
    slide_timing = { { 6, 8 }, { 4, 8 } },
    fight_timing = { { 2, 5 }, { 1, 3 } },
  }
}

fish_data.RarePira1 = fish_data.Piranha
fish_data.RarePira2 = fish_data.Piranha

return fish_data
