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
		saved = {	heat = burner.heat, 
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
	target.heat = saved.heat
	target.currently_burning = saved.currently_burning
	target.remaining_burning_fuel = saved.remaining_burning_fuel
	for k,v in pairs(saved.inventory) do
		target.inventory.insert({name=k, count=v})
	end
	if ( saved.burnt_result_inventory ) then
		for k,v in pairs(saved.burnt_result_inventory) do
			target.burnt_result_inventory.insert({name=k, count=v})
		end
	end
end


function saveGrid(grid)
	if grid and grid.valid then
		gridContents = {}
		for _,v in pairs(grid.equipment) do
			local item = {name=v.name,position={x=v.position.x,y=v.position.y}}
			local burner = saveBurner(v.burner)
			table.insert(gridContents,{item=item,energy=v.energy,shield=v.shield,burner=burner})
		end
		return gridContents
	else
		return nil
	end
end

function restoreGrid(grid,savedItems)
	for _,v in pairs(savedItems) do
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
		saveItemRequestProxy = saveItemRequestProxy,
	}
