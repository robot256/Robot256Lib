
-- Reimplements LuaPlayer::mine_entity() with force=true with the ability to set undo_index
-- Uses entity.destroy() instead of player.mine_entity so that we can use the undo stack properly
local save_restore = require("__Robot256Lib__/script/save_restore")

local function player_mine_entity_undo(player, entity, undo_index, raise_destroy)
	
  raise_destroy = (raise_destroy == true) or false
  
  local temp_inventory = game.create_inventory(1)
  for k=1,entity.get_max_inventory_index() do
    local inv = entity.get_inventory(k)
    if inv and not inv.is_empty() then
      temp_inventory.resize(1 + #inv)
      temp_inventory.transfer_from_inventory(inv)
    end
	end

	-- Add the item result of mining the entity itself, if any
	local mineprop = entity.prototype.mineable_properties
	local mine_item = mineprop and mineprop.products and mineprop.products[1] and mineprop.products[1].type == "item" and mineprop.products[1].name
  local mine_amount = mineprop and mineprop.products and mineprop.products[1] and mineprop.products[1].type == "item" and mineprop.products[1].amount
	if mine_item then
	  temp_inventory.insert({name=mine_item, count=mine_amount, quality=entity.quality, health=entity.health/entity.max_health})
	  -- Add the grid to the item
	  if entity.grid and entity.grid.count() > 0 then
		temp_inventory.resize(#temp_inventory + entity.grid.count())
		-- Find the last item that we just inserted
		local item_slot = nil
		for i=#temp_inventory,1,-1 do
		  local slot = temp_inventory[i]
		  if slot.valid_for_read and slot.name == mine_item and slot.count == mine_amount and slot.quality == entity.quality and slot.health == entity.health/entity.max_health then
			item_slot = slot
			break
		  end
		end
		local item_grid = item_slot and item_slot.create_grid() or nil
		--game.print("Created item grid "..tostring(item_grid))
		local grid_remainder = save_restore.restoreGrid(item_grid, save_restore.saveGrid(entity.grid))
		save_restore.insertInventoryStacks(temp_inventory, grid_remainder)
	  end
	elseif entity.grid then
	  -- Stock has grid but can't be mined, give player all the equipment
	  temp_inventory.resize(#temp_inventory + entity.grid.count())
	  local grid_remainder = save_restore.restoreGrid(nil, save_restore.saveGrid(entity.grid))
	  save_restore.insertInventoryStacks(temp_inventory, grid_remainder)
	end
	player.get_main_inventory().transfer_from_inventory(temp_inventory)
	if not temp_inventory.is_empty() then
	  entity.surface.spill_inventory{position=entity.position, inventory=temp_inventory}
	end

	return entity.destroy{player=player, undo_index=undo_index, raise_destroy=raise_destroy}
				
end

return player_mine_entity_undo
