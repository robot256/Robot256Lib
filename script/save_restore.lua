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
    saved = { heat = burner.heat, 
          remaining_burning_fuel = burner.remaining_burning_fuel,
          currently_burning = burner.currently_burning,
          inventory = burner.inventory.get_contents(),
          burnt_result_inventory = burner.burnt_result_inventory.valid and burner.burnt_result_inventory.get_contents() or nil
        }
    return saved
  else
    return nil
  end
end

function restoreBurner(target,saved)
  if target and target.valid and saved then
    target.heat = saved.heat
    target.currently_burning = saved.currently_burning
    target.remaining_burning_fuel = saved.remaining_burning_fuel
    if saved.inventory then
      for k,v in pairs(saved.inventory) do
        target.inventory.insert({name=k, count=v})
      end
    end
    if ( saved.burnt_result_inventory ) then
      for k,v in pairs(saved.burnt_result_inventory) do
        target.burnt_result_inventory.insert({name=k, count=v})
      end
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
  for _,v in pairs(savedItems) do
    if game.equipment_prototypes[v.item.name] then
      local e = grid.put(v.item)
      if v.energy then
        e.energy = v.energy
      end
      if v.shield and v.shield > 0 then
        e.shield = v.shield
      end
      if v.burner then
        restoreBurner(e.burner,v.burner)
      end
      if player_index then
        script.raise_event(defines.events.on_player_placed_equipment, {player_index = player_index, equipment = e, grid = grid})
      end
    end
  end
end


function saveInventory(source)
  if source and source.valid then
    local items = {}
    for name, count in pairs(source.get_contents()) do
      items[name] = items[name] or 0
      items[name] = items[name] + count
      local stack = source.find_item_stack(name)
      local magazine = stack.prototype.magazine_size
      local durability = stack.prototype.durability
      while stack and magazine do
        items[name] = items[name] + (stack.ammo - magazine)/magazine
        source.remove(stack)
        stack = source.find_item_stack(name)
      end
      while stack and durability do
        items[name] = items[name] + (stack.durability - durability)/durability
        source.remove(stack)
        stack = source.find_item_stack(name)
      end
    end
    return items
  else
    return nil
  end
end

function restoreInventory(target, items)
  if target and target.valid and items then
    for name, count in pairs(items) do
      local proto = game.item_prototypes[name]
      if proto then
        local stack = {name=name, count=math.ceil(count)}
        _,f = math.modf(count)  -- find fractional value of last item
        if f > 0 then
          local magazine = proto.magazine_size  -- nil if not ammo
          local durability = proto.durability  -- nil if not durable
          if magazine then
            stack.ammo = math.floor(f*magazine+0.5)  -- set ammo to fractional value
          elseif durability then
            stack.durability = math.floor(f*durability+0.5)  -- set durability to fractional value
          end
        end
        target.insert(stack)
      end
    end
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
  local proxies = target.surface.find_entities_filtered({
            name = "item-request-proxy",
            force = target.force,
            position = target.position
          })
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

return {saveBurner = saveBurner,
    restoreBurner = restoreBurner,
    saveGrid = saveGrid,
    restoreGrid = restoreGrid,
    saveInventory = saveInventory,
    restoreInventory = restoreInventory,
    saveFilters = saveFilters,
    restoreFilters = restoreFilters,
    saveItemRequestProxy = saveItemRequestProxy,
  }
