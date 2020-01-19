--[[ Copyright (c) 2019 robot256 (MIT License)
 * Project: Robot256's Library
 * File: carriage_replacement.lua
 * Description: Functions replace one Carriage Entity with a new one of a different entity-name.
 *    Preserves as many properties of the original as possible.
 * Parameters: loco (locomotive entity to be replaced), newName (name of locomotive entity to replace it)
 * Returns: newLoco entity if successful, nil if unsuccessful
 -]]

function saveBurner(burner)
  if burner and burner.valid then
    local burning = nil
    if burner.currently_burning then
      burning = burner.currently_burning.name
    end
    return { heat = burner.heat, 
          remaining_burning_fuel = burner.remaining_burning_fuel,
          currently_burning = burning,
          inventory = saveInventoryStacks(burner.inventory),
          burnt_result_inventory = saveInventoryStacks(burner.burnt_result_inventory)
        }
  end
end

function restoreBurner(target,saved)
  if target and target.valid and saved then
    target.heat = saved.heat
    -- Only restore burner heat if the fuel prototype still exists.]
    if game.item_prototypes[saved.currently_burning] then
      target.currently_burning = game.item_prototypes[saved.currently_burning]
      target.remaining_burning_fuel = saved.remaining_burning_fuel
    end
    local r1 = restoreInventoryStacks(target.inventory, saved.inventory) or {}
    local r2 = restoreInventoryStacks(target.burnt_result_inventory, saved.burnt_result_inventory) or {}
    for _,s in pairs(r2) do
      table.insert(r1,s)
    end
    if #r1 > 0 then
      return r1
    end
  end
end


function saveGrid(grid)
  if grid and grid.valid then
    gridContents = {}
    for _,v in pairs(grid.equipment) do
      local item = {name=v.name,position=v.position}
      local burner = saveBurner(v.burner)
      table.insert(gridContents,{item=item,energy=v.energy,shield=v.shield,burner=burner})
    end
    return gridContents
  else
    return nil
  end
end

function restoreGrid(grid,savedItems,player_index)
  local r_items = {}
  for _,v in pairs(savedItems) do
    if game.equipment_prototypes[v.item.name] then
      local e = grid.put(v.item)
      if e then
        if v.energy then
          e.energy = v.energy
        end
        if v.shield and v.shield > 0 then
          e.shield = v.shield
        end
        if v.burner then
          local r1 = restoreBurner(e.burner,v.burner) or {}
          for _,s in pairs(r1) do
            r_items[s.name] = (r_items[s.name] or 0) + s.count
          end
        end
        if player_index then
          script.raise_event(defines.events.on_player_placed_equipment, {player_index = player_index, equipment = e, grid = grid})
        end
      else
        r_items[v.item.name] = (r_items[v.item.name] or 0) + 1
        if v.burner then
          if v.burner.inventory then
            for _,s in pairs(v.burner.inventory) do
              r_items[s.name] = (r_items[s.name] or 0) + s.count
            end
          end
          if v.burner.burnt_result_inventory then
            for _,s in pairs(v.burner.burnt_result_inventory) do
              r_items[s.name] = (r_items[s.name] or 0) + s.count
            end
          end
        end
      end
    end
  end
  if #r_items then
    local remainders = {}
    for n,c in pairs(r_items) do
      table.insert(remainders, {name=n, count=c})
    end
    return remainders
  end
end


---------------------------------------------------------------
-- Convert Grid Contents to SimpleItemStack array.
-- Arguments:  grid -> table result of saveGrid()
--             dest (optional) -> SimpleItemStack array to insert stacks into
-- Returns:    stacks -> List of SimpleItemStacks or reference to dest
---------------------------------------------------------------
function saveGridStacks(grid)
-- Count item numbers so we can add stacks of equipment and fuel properly
  local items = {}
  local fuel_items = {}
  for _,v in pairs(grid.equipment) do
    if v.burner then
      if v.burner.inventory and v.burner.inventory.valid and not v.burner.inventory.is_empty() then
        for fn,fc in pairs(v.burner.inventory.get_contents()) do
          fuel_items[fn] = (fuel[fn] or 0) + fc
        end
      end
      if v.burner.burnt_result_inventory and v.burner.burnt_result_inventory.valid and not v.burner.burnt_result_inventory.is_empty() then
        for fn,fc in pairs(v.burner.burnt_result_inventory.get_contents()) do
          fuel_items[fn] = (fuel[fn] or 0) + fc
        end
      end
    end
    items[v.name] = (items[v.name] or 0) + 1
  end
  -- Convert item count to stacks
  local equip = {}
  local fuel = {}
  for en,ec in pairs(items) do
    table.insert(equip, {name=en, count=ec})
  end
  for en,ec in pairs(fuel_items) do
    table.insert(fuel, {name=en, count=ec})
  end
  return equip, fuel
end



local exportable = {["blueprint"]=true,
                    ["blueprint-book"]=true,
                    ["upgrade-planner"]=true,
                    ["deconstruction-planner"]=true,
                    ["item-with-tags"]=true}

---------------------------------------------------------------
-- Insert Stack Structure into Inventory.
-- Arguments:  source -> LuaInventory to save contents of
-- Returns:    stacks -> Dictionary [slot#] -> SimpleItemStack with extra optional field "data" storing blueprint export string
---------------------------------------------------------------
function saveInventoryStacks(source)
  if source and source.valid and not source.is_empty() then
    local stacks = {}
    for slot = 1, #source do
      local stack = source[slot]
      if stack and stack.valid_for_read then
        if exportable[stack.name] then
          table.insert(stacks, {name=stack.name, count=1, data=stack.export_stack()})
        else
          local s = {name=stack.name, count = stack.count}
          if stack.prototype.magazine_size then
            s.ammo = stack.ammo
          end
          if stack.prototype.durability then
            s.durability = stack.durability
          end
          if stack.health < 1 then
            s.health = stack.health
          end
          table.insert(stacks, s)
          if stack.grid and stack.grid.valid then
            -- Can't restore equipment to an item's grid, have to unpack it to the inventory
            saveGridStacks(stacks, stack.grid)
          end
        end
      end
    end
    return stacks
  else
    return nil
  end
end

---------------------------------------------------------------
-- Insert Stack Structure into Inventory.
-- Arguments:  target -> LuaInventory to insert items into
--             stack -> SimpleItemStack with extra optional field "data" storing blueprint export string.
--             stack_limit (optional) -> integer maximum number of items to insert from the given stack.
-- Returns:    remainder -> SimpleItemStack with extra field "data", representing all the items that could not be inserted at this time.
---------------------------------------------------------------
function insertStack(target, stack, stack_limit)
  local proto = game.item_prototypes[stack.name]
  if proto then
    if target.can_insert(stack) then
      if stack.data then
        -- Insert bp item, find ItemStack, import data string
        for i = #target, 1 do
          if not target[i].valid_for_read then
            -- this stack is empty, set it to blueprint
            target[i].set_stack(stack)
            target[i].import_stack(stack.data)
            return nil  -- no remainders after insertion
          end
        end
      else
        -- Handle normal item, break into chunks if need be, correct for oversized stacks
        if not stack_limit or stack_limit > proto.stack_size then
          stack_limit = proto.stack_size
        end
        local d = 0
        if stack.count > stack_limit then
          -- This time we limit ourselves to part of the given stack.
          d = target.insert({name=stack.name, count=stack_limit})
        else
          -- Only the last part gets assigned ammo and durability ratings of the original stack
          d = target.insert(stack)
        end
        stack.count = stack.count - d
        if stack.count == 0 then
          return nil  -- All items inserted, no remainder
        else
          return stack  -- Not all items inserted, return remainder with original ammo/durability ratings
        end
      end
    else
      -- Can't insert this stack, entire thing is remainder.
      return stack
    end
  else
    -- Prototype for this item was removed from the game, don't give a remainder.
    return nil
  end
end

---------------------------------------------------------------
-- Spill Stack Structure onto ground.
-- Arguments:  target -> LuaInventory to insert items into
--             stack -> SimpleItemStack with extra optional field "data" storing blueprint export string.
--             stack_limit (optional) -> integer maximum number of items to insert from the given stack.
-- Returns:    remainder -> SimpleItemStack with extra field "data", representing all the items that could not be inserted at this time.
---------------------------------------------------------------
function spillStack(stack, surface, position)
  surface.spill_item_stack(position, stack)
  if stack.data then
    -- This is a bp item, find it on the surface and restore data
    for _,entity in pairs(surface.find_entities_filtered{name="ItemEntity",position=position,radius=1000}) do
      -- Check if these are the droids we are looking for
      if entity.stack.valid_for_read then
        if entity.stack.name == stack.name then
          -- TODO: Handle detection of empty deconstruction_planner, upgrade_planner, item_with_tags
          if not entity.stack.is_blueprint_setup() then
            -- New empty blueprint, let's import into it
            entity.stack.import_stack(stack.data)
          end
        end
      end
    end
  end
end


---------------------------------------------------------------
-- Restore Inventory Stack List to Inventory.
-- Arguments:  target -> LuaInventory to insert items into
--             stacks -> List of SimpleItemStack with extra optional field "data" storing blueprint export string.
-- Returns:    remainders -> List of SimpleItemStacks representing all the items that could not be inserted at this time.
---------------------------------------------------------------
function restoreInventoryStacks(target, stacks)
  local remainders = {}
  if target and target.valid and stacks then
    for _,stack in pairs(stacks) do
      local r = saveRestoreLib.insertStack(target, stack)
      if r then 
        table.insert(remainders, r)
      end
    end
  end
  if #remainders then
    return remainders
  else
    return nil
  end
end



function saveFilters(source)
  local filters = nil
  if source and source.valid then
    if source.is_filtered() then
      filters = {}
      for f = 1, #source do
        filters[f] = source.get_filter(f)
      end
    end
    if source.hasbar() and source.getbar() then
      filters = filters or {}
      filters.bar = source.getbar()
    end
  end
  return filters
end

function restoreFilters(target, filters)
  if target and target.valid then
    if target.supports_filters() and filters then
      for f = 1, #target do
        target.set_filter(f, filters[f])
      end
    end
    if target.hasbar() and filters.bar then
      target.setbar(filters.bar)
    end
  end
end


function saveItemRequestProxy(target)
  -- Search for item_request_proxy ghosts targeting this entity
  local proxies = target.surface.find_entities_filtered{
            name = "item-request-proxy",
            force = target.force,
            position = target.position
          }
  for _, proxy in pairs(proxies) do
    if proxy.proxy_target == target and proxy.valid then
      local items = {}
      for k,v in pairs(proxy.item_requests) do
        items[k] = v
      end
      return items
    else
      return nil
    end
  end
end

return {
    saveBurner = saveBurner,
    restoreBurner = restoreBurner,
    saveGrid = saveGrid,
    restoreGrid = restoreGrid,
    saveGridStacks = saveGridStacks,
    saveInventoryStacks = saveInventoryStacks,
    insertStack = insertStack,
    restoreInventoryStacks = restoreInventoryStacks,
    spillStack = spillStack,
    saveFilters = saveFilters,
    restoreFilters = restoreFilters,
    saveItemRequestProxy = saveItemRequestProxy,
  }
