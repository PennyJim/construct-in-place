
---@class DirectionInformation
---@field orientation RealOrientation
---@field width int
---@field height int
---@class CIPGlobal
--- The silos and their direction information
---@field entities table<uint, DirectionInformation>
--- The silos that can still change their recipe
---@field unlocked_silos table<uint, LuaEntity>
--- The silos we care about
---@field registered table<uint, LuaEntity>
global = {
	entities={},
	unlocked_silos={},
	registered={},
}

---@type table<string,fun(EventData.on_script_trigger_effect)>
local script_trigger_handlers = {}
script.on_event(defines.events.on_script_trigger_effect, function (EventData)
	local handler = script_trigger_handlers[EventData.effect_id]
	if handler then handler(EventData) end
end)

-- Hold a reference locally so on_tick is slightly faster
local unlocked_silos = global.unlocked_silos
script.on_load(function ()
	unlocked_silos = global.unlocked_silos
end)

--MARK: Placement

---@param EventData EventData.on_script_trigger_effect
script_trigger_handlers["cip-site-placed"] = function (EventData)
	local source_entity = EventData.source_entity
	if not source_entity then return end

	local surface = game.get_surface(EventData.surface_index) --[[@as LuaSurface]]

	local size = source_entity.name:sub(10)
	local width_len = size:find("x")
	local width,height = tonumber(size:sub(1,width_len-1)),tonumber(size:sub(width_len+1))
	if not width or not height then error("cip-site-placed was ran on an invalid entity") end

	local orientation = source_entity.orientation
	local direction = source_entity.direction
	local last_user = source_entity.last_user
	local position = source_entity.position
	local dir_info = {
		orientation = orientation,
		width = width,
		height = height
	}--[[@as DirectionInformation]]

	if direction == defines.direction.east
	or direction == defines.direction.west then
		width,height = height,width
	end

	source_entity.destroy{raise_destroy = false}

	local silo = surface.create_entity{
		name = "cip-site-"..width.."x"..height,
		position = position,
		player = last_user,
		force = last_user and last_user.force_index or "player",
		raise_built = false, -- I can be convinced to enable this
		create_build_effect_smoke = false,
	}
	if not silo then error("Could not place actual silo") end
	local unit_number = silo.unit_number
	if not unit_number then error("The silo has no unit number!?") end
	global.entities[unit_number] = dir_info
	global.unlocked_silos[unit_number--[[@as uint]]] = silo
	global.registered[unit_number--[[@as uint]]] = silo
	script.register_on_entity_destroyed(silo)
end

--MARK: Recipe Locking

---@param unit uint
---@param entity LuaEntity
local function check_entities(unit, entity)
	-- Remove entry if it's invalid
	if not entity.valid then
		log("The unit '"..unit.."' was invalidated without being removed from unlocked_silos")
		unlocked_silos[unit] = nil
		return
	end

	-- Lock and remove entity if it's progressed
	if entity.rocket_parts > 0 then
		entity.recipe_locked = true
		unlocked_silos[unit] = nil
		log("The unit '"..unit.."' has been locked")
		return
	end
end

script.on_event(defines.events.on_tick, function (EventData)
	for unit, entity in pairs(unlocked_silos) do
		check_entities(unit, entity)
	end
end)

--MARK: Mining

---@param EventData EventData.on_robot_mined_entity|EventData.on_player_mined_entity
local function mined_handler(EventData)
	local entity = EventData.entity
	local unit_number = entity.unit_number
	-- Do not handle this entity if it's not one we've registered
	if not unit_number or not global.registered[unit_number] then return	end
	global.registered[unit_number] = nil

	local count = entity.rocket_parts
	if count == 0 then return end

	local recipe = entity.get_recipe().name
	local surface = entity.surface
	local inventory = game.create_inventory(1000)

	local create_params = {
		name = "cip-"..recipe.."-fragment",
		position = entity.position,
		raise_built = false,
	}--[[@as LuaSurface.create_entity_param]]
	local mine_params = {
		force = true,
		inventory = inventory,
		raise_destroyed = false,
	}--[[@as LuaEntity.mine_param]]

	---@type LuaEntity
	local pack
	for i = 1, count, 1 do
		pack = surface.create_entity(create_params)--[[@as LuaEntity]]
		pack.mine(mine_params)
	end

	local buffer = EventData.buffer
	for item, count in pairs(inventory.get_contents()) do
		-- inventory.remove{name=item, count=count}
		buffer.insert{name=item, count=count}
	end
	inventory.destroy()
end

script.on_event(defines.events.on_robot_mined_entity, mined_handler)
script.on_event(defines.events.on_player_mined_entity, mined_handler)

--MARK: Construction

---@param EventData EventData.on_script_trigger_effect
script_trigger_handlers["cip-site-finished"] = function (EventData)
	local source_entity = EventData.source_entity
	if not source_entity then return end

	local surface = source_entity.surface
	local entity = game.item_prototypes[source_entity.get_recipe().products[1].name].place_result
	local dir_data = global.entities[source_entity.unit_number--[[@as int]]]
	global.entities[source_entity.unit_number--[[@as int8]]] = nil

	if not entity then error("Recipe is invalid for contruct in place") end

	local entity_box = entity.collision_box
	local entity_size = {
		x = math.ceil(entity_box.right_bottom.x - entity_box.left_top.x),
		y = math.ceil(entity_box.right_bottom.y - entity_box.left_top.y),
	}

	if entity_size.x ~= dir_data.width then
		if entity_size.x ~= dir_data.height or entity_size.y ~= dir_data.width then
			error("width and height of the recipe does not match the place result of the item")
		end
		dir_data.orientation = dir_data.orientation + 0.25 % 1
	end

	local position = source_entity.position
	local last_user = source_entity.last_user
	local force = source_entity.force_index

	local modules = source_entity.get_inventory(defines.inventory.assembling_machine_modules) --[[@as LuaInventory]]
	local inputs = source_entity.get_inventory(defines.inventory.assembling_machine_input) --[[@as LuaInventory]]
	local module_size, input_size = #modules, #inputs
	for index = 1, module_size, 1 do
		surface.spill_item_stack(position, modules[index], true, force, false)
	end
	for index = 1, input_size, 1 do
		surface.spill_item_stack(position, inputs[index], true, force, false)
	end
	source_entity.destroy{}

	local direction = math.floor(dir_data.orientation * 8)--[[@as defines.direction]]

	surface.create_entity{
		name = entity.name,
		direction = direction,
		position = position,
		player = last_user,
		force = force,
	}
end

--MARK: Entity Cleanup

script.on_event(defines.events.on_entity_destroyed, function (EventData)
	local unit_number = EventData.unit_number
	if not unit_number then return end

	global.entities[unit_number] = nil
	global.unlocked_silos[unit_number] = nil
	global.registered[unit_number] = nil
	log("The unit '"..unit_number.."' has been cleaned up")
end)