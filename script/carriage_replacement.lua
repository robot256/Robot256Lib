--[[ Copyright (c) 2020 robot256 (MIT License)
 * Project: Robot256's Library
 * File: replace_carriage.lua
 * Description: Replaces one Carriage Entity with a new one of the
 *    same type and different entity-name.  Preserves as many properties
 *    of the original as possible.
 * Parameters: carriage: locomotive or wagon entity to be replaced)
 *             newName: name of entity to replace it)
 *             raiseBuilt (optional): whether or not to issue script_raised_built when done creating the new carriage
 *             raiseDestroy (optional): whether or not to issue script_raised_destroy when destroying the old carriage
 *             flip (optional): whether to rotate the replacement carriage 180 degrees relative to the original
 * Returns: newCarriage entity if successful, nil if unsuccessful
 * Dependencies: saveGrid,
 *               restoreGrid,
 *               saveBurner,
 *               restoreBurner,
 *               saveItemRequestProxy,
 *               saveInventoryStacks,
 *               insertInventoryStacks,
 *               saveFilters,
 *               restoreFilters,
 *               spillStacks
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
  local minable = carriage.minable_flag
  local destructible = carriage.destructible
  local operable = carriage.operable
  local rotatable = carriage.rotatable
  local enable_logistics_while_moving = carriage.enable_logistics_while_moving
  local quality = carriage.quality
  local copy_color_from_train_stop = carriage.copy_color_from_train_stop
  
  -- Save deconstruction request by any force
  local deconstruction_request = nil
  for _,f in pairs(game.forces) do
    if carriage.to_be_deconstructed(f) then
      deconstruction_request = f
      break
    end
  end
  
  -- Save GUI opened by any player
  local opened_by_players = {}
  for _,p in pairs(game.players) do
    if p.opened == carriage then
      table.insert(opened_by_players, p)
    end
  end
  
  -- Flip orientation if needed
  if flip then
    local foo
    foo,orientation = math.modf(orientation + 0.5)
  end

  -- Save equipment grid contents
  -- TODO: UPDATE FOR QUALITY
  local grid_equipment = saveRestoreLib.saveGrid(carriage.grid)

  -- Save item requests left over from a blueprint
  local insert_plan, removal_plan = saveRestoreLib.saveItemRequestProxy(carriage)
  
  -- Save the burner progress, including heat and fuel item quality
  local saved_burner
  if carriage.type == "locomotive" and carriage.burner then
    local burner = carriage.burner
    saved_burner = {}
    saved_burner.currently_burning = burner.currently_burning  -- returns array[{name, count, quality}]
    saved_burner.remaining_burning_fuel = burner.remaining_burning_fuel
    saved_burner.heat = burner.heat
    if burner.inventory and not burner.inventory.is_empty() then
      saved_burner.inventory = game.create_inventory(#burner.inventory)
      for k=1,#burner.inventory do
        saved_burner.inventory[k].transfer_stack(burner.inventory[k])
      end
    end
    if burner.burnt_result_inventory and not burner.burnt_result_inventory.is_empty() then
      saved_burner.burnt_result_inventory = game.create_inventory(#burner.burnt_result_inventory)
      for k=1,#burner.burnt_result_inventory do
        saved_burner.burnt_result_inventory[k].transfer_stack(burner.burnt_result_inventory[k])
      end
    end
  end
  
  
  -- Save the kills stat for artillery wagons
  local kills, damage_dealt, artillery_auto_targeting
  if carriage.type == "artillery-wagon" then
    kills = carriage.kills
    damage_dealt = carriage.damage_dealt
    artillery_auto_targeting = carriage.artillery_auto_targeting
  end

  -- Save the artillery wagon ammunition inventory (respects quality, ignores spoilage)
  local ammo_inventory = nil
  local ammo_filters = nil
  if carriage.type == "artillery-wagon" then
    local ammo_inventory_object = carriage.get_inventory(defines.inventory.artillery_wagon_ammo)
    if( ammo_inventory_object and ammo_inventory_object.valid ) then
      ammo_inventory = saveRestoreLib.saveInventoryStacks(ammo_inventory_object)
      ammo_filters = saveRestoreLib.saveFilters(ammo_inventory_object)
    end
  end

  -- Save the cargo wagon inventory (respects quality and spoilage)
  local cargo_inventory = nil
  local cargo_filters = nil
  if carriage.type == "cargo-wagon" then
    local cargo_inventory_object = carriage.get_inventory(defines.inventory.cargo_wagon)
    if( cargo_inventory_object and cargo_inventory_object.valid ) then
      -- Move cargo items into Script Inventory object to preserve quality and spoilage
      if not cargo_inventory_object.is_empty() then
        cargo_inventory = game.create_inventory(#cargo_inventory_object)
        for k = 1,#cargo_inventory_object do
          cargo_inventory[k].transfer_stack(cargo_inventory_object[k])
        end
      end
      cargo_filters = saveRestoreLib.saveFilters(cargo_inventory_object)
    end
  end
  
  -- Save the fluid wagon contents
  local fluid_contents = carriage.get_fluid_contents()

  -- Save the train schedule and group.  If we are replacing a lone MU with a regular carriage, the train schedule and group will be lost when we delete it.
  local train_schedule = carriage.train.schedule
  local destination = carriage.train.schedule.current
  local train_group = carriage.train.group
  local manual_mode = carriage.train.manual_mode

  -- Save its coupling state.  By default, created carriages couple to everything nearby, which we might have to undo
  --   if we're replacing after intentional uncoupling.
  local back_was_connected = carriage.get_connected_rolling_stock(defines.rail_direction.back)
  local front_was_connected = carriage.get_connected_rolling_stock(defines.rail_direction.front)

  -- Destroy the old Locomotive so we have space to make the new one
  if raiseDestroy == nil then raiseDestroy = true end
  carriage.destroy{raise_destroy=raiseDestroy}

  ------------------------------
  -- Create the new locomotive in the same spot and orientation
  local newCarriage = surface.create_entity{
    name = newName,
    quality = quality,
    position = position,
    orientation = orientation,
    force = force,
    create_build_effect_smoke = false,
    raise_built = false,
    snap_to_train_stop = false}
  -- make sure it was actually created
  if newCarriage then
  
    -- Restore coupling state (if we flipped the wagon, uncouple opposite sides)
    if flip then
      if not front_was_connected and newCarriage.get_connected_rolling_stock(defines.rail_direction.front) then
        newCarriage.disconnect_rolling_stock(defines.rail_direction.back)
      end
      if not back_was_connected and newCarriage.get_connected_rolling_stock(defines.rail_direction.back) then
        newCarriage.disconnect_rolling_stock(defines.rail_direction.front)
      end
    else
      if not front_was_connected and newCarriage.get_connected_rolling_stock(defines.rail_direction.front) then
        newCarriage.disconnect_rolling_stock(defines.rail_direction.front)
      end
      if not back_was_connected and newCarriage.get_connected_rolling_stock(defines.rail_direction.back) then
        newCarriage.disconnect_rolling_stock(defines.rail_direction.back)
      end
    end


    -- Restore parameters
    newCarriage.health = health
    if color then newCarriage.color = color end
    if backer_name then newCarriage.backer_name = backer_name end
    if last_user then newCarriage.last_user = last_user end
    if kills then newCarriage.kills = kills end
    if damage_dealt then newCarriage.damage_dealt = damage_dealt end
    if artillery_auto_targeting then newCarriage.artillery_auto_targeting = artillery_auto_targeting end
    newCarriage.minable_flag = minable
    newCarriage.destructible = destructible
    newCarriage.operable = operable
    newCarriage.rotatable = rotatable
    newCarriage.enable_logistics_while_moving = enable_logistics_while_moving
    newCarriage.copy_color_from_train_stop = copy_color_from_train_stop
    
    
    -- Restore the partially-used burner fuel
    if saved_burner and newCarriage.burner then
      local burner = newCarriage.burner
      burner.currently_burning = saved_burner.currently_burning
      burner.remaining_burning_fuel = saved_burner.remaining_burning_fuel
      burner.heat = saved_burner.heat
      if burner.inventory and saved_burner.inventory then
        for k=1,math.min(#burner.inventory, #saved_burner.inventory) do
          burner.inventory[k].transfer_stack(saved_burner.inventory[k])
        end
      end
      if burner.burnt_result_inventory and saved_burner.burnt_result_inventory then
        for k=1,math.min(#burner.burnt_result_inventory, #saved_burner.burnt_result_inventory) do
          burner.burnt_result_inventory[k].transfer_stack(saved_burner.burnt_result_inventory[k])
        end
      end
    end

    -- Restore the ammo inventory
    if ammo_inventory or ammo_filters then
      local newAmmoInventory = newCarriage.get_inventory(defines.inventory.artillery_wagon_ammo)
      if newAmmoInventory and newAmmoInventory.valid then
        saveRestoreLib.restoreFilters(newAmmoInventory, ammo_filters)
        local remainders = saveRestoreLib.insertInventoryStacks(newAmmoInventory, ammo_inventory)
        saveRestoreLib.spillStacks(remainders, surface, position)
      end
    end

    -- Restore the cargo inventory
    if cargo_inventory or cargo_filters then
      local newCargoInventory = newCarriage.get_inventory(defines.inventory.cargo_wagon)
      if newCargoInventory and newCargoInventory.valid then
        saveRestoreLib.restoreFilters(newCargoInventory, cargo_filters)
        -- Copy LuaItemStacks back out of the Script Inventory
        for k=1, #cargo_inventory do
          newCargoInventory[k].transfer_stack(cargo_inventory[k])
        end
        cargo_inventory.destroy()
      end
    end

    -- Restore the fluid wagon contents
    for fluid,amount in pairs(fluid_contents) do
      newCarriage.insert_fluid(fluid,amount)
    end

    -- Restore the equipment grid
    if grid_equipment and newCarriage.grid and newCarriage.grid.valid then
      local remainders = saveRestoreLib.restoreGrid(newCarriage.grid, grid_equipment)
      saveRestoreLib.spillStacks(remainders, surface, position)
    end

    -- Restore the player driving
    if player_driving then
      newCarriage.set_driver(player_driving)
    end
    
    -- Restore pending deconstruction order
    if deconstruction_request then
      newCarriage.order_deconstruction(deconstruction_request)
    end

    -- Restore item_request_proxy by creating new ones
    if #insert_plan>0 or #removal_plan>0 then
      local newProxy = surface.create_entity{name="item-request-proxy", position=position, force=force, target=newCarriage,
        modules=insert_plan, removal_plan=removal_plan}
    end

    -- After all that, fire an event so other scripts can reconnect to it
    if raiseBuilt == nil or raiseBuilt == true then
      script.raise_event(defines.events.script_raised_built, {entity = newCarriage})
    end

    -- Restore the train schedule and mode
    if train_schedule and train_schedule.records then
      -- If the schedule is not empty, assign it and restore manual/automatic mode
      if table_size(train_schedule.records) > 0 and table_size(newCarriage.train.schedule.records) == 0 then
        newCarriage.train.schedule = train_schedule
      end
    end
    if train_group and newCarriage.train.group ~= train_group then
      newCarriage.train.group = train_group
    end
    newCarriage.train.manual_mode = manual_mode
    if manual_mode == false then
      -- Send train to correct station in schedule
      if destination <= table_size(newCarriage.train.schedule) and newCarriage.train.schedule.current ~= destination then
        newCarriage.train.go_to_station(destination)
      end
    end
    
    -- Restore the GUI opened by players
    for _,p in pairs(opened_by_players) do
      p.opened = newCarriage
    end
    
    --game.print("Finished replacing. Used direction "..newDirection..", new orientation: " .. newCarriage.orientation)
    return newCarriage

  else
    -- Could not Create New Wagon
    -- Spill Wagon and Contents on Ground!
    
    -- Spill carriage item
    saveRestoreLib.spillStack({name=newName, count=1}, surface, position)
    
    -- Spill burner contents
    local r = saveRestoreLib.restoreBurner(nil, saved_burner)
    saveRestoreLib.spillStacks(r, surface, position)
    
    -- Spill equipment grid
    local r = saveRestoreLib.restoreGrid(nil, grid_equipment)
    saveRestoreLib.spillStacks(r, surface, position)
    
    -- Spill ammo inventory
    saveRestoreLib.spillStacks(ammo_inventory, surface, position)
    
    -- Spill cargo inventory from the Script Inventory
    for _,stack in pairs(cargo_inventory) do
      surface.spill_item_stack{position=position, stack=stack, force=force, allow_belts=false}
    end
    
    return nil
  end
end

return {replaceCarriage = replaceCarriage}
