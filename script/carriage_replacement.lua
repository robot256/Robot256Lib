--[[ Copyright (c) 2019 robot256 (MIT License)
 * Project: Robot256's Library
 * File: replace_carriage.lua
 * Description: Replaces one Carriage Entity with a new one of the
 *    same type and different entity-name.  Preserves as many properties
 *    of the original as possible.
 * Parameters: carriage: locomotive or wagon entity to be replaced)
 *             newName: name of entity to replace it)
 *             raiseBuilt (optional): whether or not to issue script_raised_built when done creating the new locomotive
 *             raiseDestroy (optional): whether or not to issue script_raised_destroy when destroying the old locomotive
 * Returns: newCarriage entity if successful, nil if unsuccessful
 * Dependencies: saveGrid,
 *               restoreGrid,
 *               saveBurner,
 *               restoreBurner,
 *               saveItemRequestProxy
--]]

local saveRestoreLib = require("__Robot256Lib__/script/save_restore")


local function replaceCarriage(carriage, newName, raiseBuilt, raiseDestroy, flip)

  -- Save basic parameters
  local position = carriage.position
  local force = carriage.force
  local surface = carriage.surface
  local orientation = carriage.orientation
  local backer_name = carriage.backer_name
  local color = carriage.color
  local health = carriage.health
  local player_driving = carriage.get_driver()
  local last_user = carriage.last_user
  
  -- Save deconstruction request by any force
  local deconstruction_request = nil
  for _,f in pairs(game.forces) do
    if carriage.to_be_deconstructed(f) then
      deconstruction_request = f
      break
    end
  end
  
  -- Flip orientation if needed
  if flip then
    _,orientation = math.modf(orientation + 0.5)
  end

  -- Save equipment grid contents
  local grid_equipment = saveRestoreLib.saveGrid(carriage.grid)

  -- Save item requests left over from a blueprint
  local item_requests = saveRestoreLib.saveItemRequestProxy(carriage)

  -- Save the burner progress
  local saved_burner = saveRestoreLib.saveBurner(carriage.burner)

  -- Save the kills stat for artillery wagons
  local kills = nil
  if carriage.type == "artillery-wagon" then
    kills = carriage.kills
  end

  -- Save the artillery wagon ammunition inventory
  local ammo_inventory = nil
  local ammo_filters = nil
  local ammo_inventory_object = carriage.get_inventory(defines.inventory.artillery_wagon_ammo)
  if( ammo_inventory_object and ammo_inventory_object.valid ) then
    ammo_inventory = saveRestoreLib.saveInventoryStacks(ammo_inventory_object)
    ammo_filters = saveRestoreLib.saveFilters(ammo_inventory_object)
  end

  -- Save the cargo wagon inventory
  local cargo_inventory = nil
  local cargo_filters = nil
  local cargo_inventory_object = carriage.get_inventory(defines.inventory.cargo_wagon)
  if( cargo_inventory_object and cargo_inventory_object.valid ) then
    cargo_inventory = saveRestoreLib.saveInventoryStacks(cargo_inventory_object)
    cargo_filters = saveRestoreLib.saveFilters(cargo_inventory_object)
  end

  -- Save the fluid wagon contents
  local fluid_contents = carriage.get_fluid_contents()

  -- Save the train schedule.  If we are replacing a lone MU with a regular carriage, the train schedule will be lost when we delete it.
  local train_schedule = carriage.train.schedule
  local manual_mode = carriage.train.manual_mode

  -- Save its coupling state.  By default, created carriages couple to everything nearby, which we might have to undo
  --   if we're replacing after intentional uncoupling.
  local back_was_connected = carriage.disconnect_rolling_stock(defines.rail_direction.back)
  local front_was_connected = carriage.disconnect_rolling_stock(defines.rail_direction.front)

  -- Destroy the old Locomotive so we have space to make the new one
  if raiseDestroy == nil then raiseDestroy = true end
  carriage.destroy{raise_destroy=raiseDestroy}

  ------------------------------
  -- Create the new locomotive in the same spot and orientation
  local newCarriage = surface.create_entity{
    name = newName,
    position = position,
    orientation = orientation,
    force = force,
    create_build_effect_smoke = false,
    raise_built = false,
    snap_to_train_stop = false}
  -- make sure it was actually created
  if not newCarriage then
    return nil
  end

  -- Restore coupling state (if we flipped the wagon, uncouple opposite sides)
  if flip then
    if not front_was_connected then
      newCarriage.disconnect_rolling_stock(defines.rail_direction.back)
    end
    if not back_was_connected then
      newCarriage.disconnect_rolling_stock(defines.rail_direction.front)
    end
  else
    if not front_was_connected then
      newCarriage.disconnect_rolling_stock(defines.rail_direction.front)
    end
    if not back_was_connected then
      newCarriage.disconnect_rolling_stock(defines.rail_direction.back)
    end
  end


  -- Restore parameters
  newCarriage.health = health
  if backer_name then newCarriage.backer_name = backer_name end
  if last_user then newCarriage.last_user = last_user end
  if color then newCarriage.color = color end
  if kills then newCarriage.kills = kills end
  
  -- Restore the partially-used burner fuel
  if saved_burner then
    local remainders = saveRestoreLib.restoreBurner(newCarriage.burner, saved_burner)
    saveRestoreLib.spillStacks(remainders)
  end

  -- Restore the ammo inventory
  newAmmoInventory = newCarriage.get_inventory(defines.inventory.artillery_wagon_ammo)
  if newAmmoInventory and newAmmoInventory.valid then
    saveRestoreLib.restoreFilters(newAmmoInventory, ammo_filters)
    local remainders = saveRestoreLib.restoreInventoryStacks(newAmmoInventory, ammo_inventory)
    saveRestoreLib.spillStacks(remainders)
  end

  -- Restore the cargo inventory
  newCargoInventory = newCarriage.get_inventory(defines.inventory.cargo_wagon)
  if newCargoInventory and newCargoInventory.valid then
    saveRestoreLib.restoreFilters(newCargoInventory, cargo_filters)
    local remainders = saveRestoreLib.restoreInventoryStacks(newCargoInventory, cargo_inventory)
    saveRestoreLib.spillStacks(remainders)
  end

  -- Restore the fluid wagon contents
  for fluid,amount in pairs(fluid_contents) do
    newCarriage.insert_fluid(fluid,amount)
  end

  -- Restore the equipment grid
  if grid_equipment and newCarriage.grid and newCarriage.grid.valid then
    local remainders = saveRestoreLib.restoreGrid(newCarriage.grid, grid_equipment)
    saveRestoreLib.spillStacks(remainders)
  end

  -- Restore the player driving
  if player_driving then
    newCarriage.set_driver(player_driving)
  end
  
  -- Restore pending deconstruction order
  if deconstruction_request then
    newCarriage.order_deconstruction(deconstruction_request)
  end

  -- Restore item_request_proxy by creating a new one
  if item_requests then
    newProxy = surface.create_entity{name="item-request-proxy", position=position, force=force, target=newCarriage, modules=item_requests}
  end

  -- After all that, fire an event so other scripts can reconnect to it
  if raiseBuilt == nil or raiseBuilt == true then
    script.raise_event(defines.events.script_raised_built, {entity = newCarriage})
  end

  -- Restore the train schedule and mode
  if train_schedule and train_schedule.records ~= nil then
    local num_stops = 0
    for k,v in pairs(train_schedule.records) do
      num_stops = num_stops + 1
    end
    -- If the schedule is not empty, assign it and restore manual/automatic mode
    if num_stops > 0 then
      newCarriage.train.schedule = train_schedule
    end
    -- If the saved schedule has no stops, do not write to train.schedule.  In 0.17.59, this will cause a script error.
  end
  newCarriage.train.manual_mode = manual_mode


  --game.print("Finished replacing. Used direction "..newDirection..", new orientation: " .. newCarriage.orientation)
  return newCarriage
end

return {replaceCarriage = replaceCarriage}
