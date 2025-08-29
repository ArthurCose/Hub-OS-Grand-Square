---@param status Status
function status_init(status)
  local fish = status:owner()
  local original_tile = fish:current_tile()
  original_tile:reserve_for(fish)

  local component = fish:create_component(Lifetime.ActiveBattle)

  component.on_update_func = function()
    local movement_offset = fish:movement_offset()

    fish:set_movement_offset(
      movement_offset.x + math.random(-1, 1),
      movement_offset.y + math.random(-1, 1)
    )
  end

  status.on_delete_func = function()
    original_tile:add_entity(fish)
    original_tile:remove_reservation_for(fish)
    component:eject()
  end
end
