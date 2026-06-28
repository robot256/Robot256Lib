
-- Reimplements LuaPlayer::mine_entity() with force=true with the ability to set undo_index
-- Uses entity.destroy() instead of player.mine_entity so that we can use the undo stack properly
local save_restore = require("__Robot256Lib__/script/save_restore")

local function player_mine_entity_undo(player, entity, undo_index, raise_destroy)
	
  raise_destroy = (raise_destroy == true) or false
  
  -- Transfer all the items out of the entity and leave item ghosts in place
  -- This way the undo entry will have item ghosts stored in it
  local temp_inventory = game.create_inventory(1)
  local insert_plan = {}
  for k=1,entity.get_max_inventory_index() do
    local inv = entity.get_inventory(k)
    if inv and not inv.is_empty() then
      -- Add to or create proxy
      local proxy = entity.item_request_proxy
      if proxy then
        insert_plan = proxy.insert_plan
      end
      -- Convert item contents to ghost item requests before transferring
      local transfer_stack_count = 0
      for i=1,#inv do
        local stack = inv[i]
        if stack.valid_for_read then
          table.insert(insert_plan, {id={name=stack.name, quality=stack.quality.name}, items={in_inventory={{inventory=k, stack=i-1, count=stack.count}}}})
          transfer_stack_count = transfer_stack_count + 1
        end
      end
      -- Transfer items
      temp_inventory.resize(1 + transfer_stack_count)
      temp_inventory.transfer_from_inventory(inv)
      -- Create or update proxy
      log(serpent.block(insert_plan))
      if proxy then
        proxy.insert_plan = insert_plan
      else
        entity.surface.create_entity{name="item-request-proxy", position=entity.position, target=entity, force=player.force, modules = insert_plan}
      end
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
