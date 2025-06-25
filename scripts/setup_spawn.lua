local areas = Net.list_areas()

for _, area_id in ipairs(areas) do
  local spawn = Net.get_object_by_name(area_id, "Spawn")

  if spawn == nil then
    goto continue
  end

  Net.set_spawn_position(area_id, spawn.x, spawn.y, spawn.z)

  local direction = spawn.custom_properties.Direction

  if direction then
    Net.set_spawn_direction(area_id, direction)
  end

  ::continue::
end
