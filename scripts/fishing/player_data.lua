local json = require("scripts/libs/json")

---@class PlayerFishingData
---@field version number
---@field nickname string used for manual data recovery
---@field money number
---@field selected_bait string
---@field inventory table<string, number>
---@field hidden_inventory table<string, number>
---@field fish_caught table<string, table<string, number>>
local PlayerFishingData = {}
PlayerFishingData.__index = PlayerFishingData

local PLAYER_DATA_DIR = "scripts/fishing/_data/players/"

---@type table<string, PlayerFishingData>
local loaded_data = {}

---@return Net.Promise<PlayerFishingData>
function PlayerFishingData.fetch(player_id)
  return Async.create_promise(function(resolve)
    local identity = Net.get_player_secret(player_id)
    local nickname = Net.get_player_name(player_id)
    local data = loaded_data[identity]

    if data then
      -- already loaded
      resolve(data)
    end

    local path = PLAYER_DATA_DIR .. Net.encode_uri_component(identity)
    Async.read_file(path).and_then(function(contents)
      data = loaded_data[identity]

      if data then
        -- goofy data race patch
        -- ignoring a better solution since this might never get hit
        return resolve(data)
      end

      if contents == "" then
        -- generate default data
        data = {
          version = 1,
          nickname = nickname,
          money = 0,
          selected_bait = "bait:1",
          inventory = {},
          hidden_inventory = {},
          fish_caught = {}
        }
      else
        -- decode file
        data = json.decode(contents)
      end

      if data.nickname ~= nickname then
        -- keep nickname up to date, this may help with data recovery
        data.nickname = nickname
        data:save(player_id)
      end

      setmetatable(data, PlayerFishingData)
      loaded_data[identity] = data
      resolve(data)
    end)
  end)
end

---@param player_id Net.ActorId
function PlayerFishingData:save(player_id)
  local identity = Net.get_player_secret(player_id)
  local path = PLAYER_DATA_DIR .. Net.encode_uri_component(identity)
  Async.write_file(path, json.encode(self))
end

Async.ensure_dir(PLAYER_DATA_DIR)

Net:on("player_connect", function(event)
  PlayerFishingData.fetch(event.player_id)
      .and_then(function(data)
        if not data then return end

        Net.set_player_money(event.player_id, data.money)

        for id, count in pairs(data.inventory) do
          Net.give_player_item(event.player_id, id, count)
        end
      end)
end)

Net:on("player_disconnect", function(event)
  loaded_data[event.player_id] = nil
end)

return PlayerFishingData
