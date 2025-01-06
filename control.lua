
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
storage = {
	entities={},
	unlocked_silos={},
	registered={},
}
--- A lookup of if an entity is cip'ed
---@type table<data.EntityID,data.RecipeID>
local ciped_entities = {}
--- The mapping of items to their entities
---@type table<data.ItemID,LuaEntityPrototype>
local ciped_items = {}

---@type table<string,fun(E:EventData.on_script_trigger_effect)>
local script_trigger_handlers = {}
script.on_event(defines.events.on_script_trigger_effect, function (EventData)
	local handler = script_trigger_handlers[EventData.effect_id]
	if handler then handler(EventData) end
end)

-- Hold a reference locally so on_tick is slightly faster
local unlocked_silos = storage.unlocked_silos
script.on_load(function ()
	unlocked_silos = storage.unlocked_silos
end)


---@param prototype LuaEntityPrototype
---@return int Width The short dimension
---@return int Height The long dimension
local function get_dimensions(prototype)
	local collision = prototype.collision_box
	-- Tile width seems to lie between data and runtime
	local width = math.ceil(collision.right_bottom.x - collision.left_top.x)
	local height = math.ceil(collision.right_bottom.y - collision.left_top.y)
	return width, height
end

--MARK: Get CIP'ed

---@param name data.RecipeID
---@param recipe LuaRecipePrototype
local function process_recipe(name, recipe)
	local item = prototypes.item[recipe.main_product.name]
	local entity = item.place_result

	if not entity then return error("Main result of recipe with dummy-item does not have a place_result") end

	ciped_items[item.name] = entity
	ciped_entities[entity.name] = name
end

---@type RecipePrototypeFilter[]
local recipe_filter, category_count = {}, 0
for key in pairs(prototypes.recipe_category) do
	if key:sub(1, 13) == "cip-category-" then
		category_count = category_count + 1
		recipe_filter[category_count] = {
			filter = "category",
			category = key,
			mode = "or"
		}
	end
end

for name, recipe in pairs(prototypes.get_recipe_filtered(recipe_filter)) do
	process_recipe(name, recipe)
end

--MARK: Placement

---@param EventData EventData.on_script_trigger_effect
script_trigger_handlers["cip-site-placed"] = function (EventData)
	local source_entity = EventData.source_entity
	if not source_entity then return end

	local surface = game.get_surface(EventData.surface_index) --[[@as LuaSurface]]

	local item_name = source_entity.name
	local size = item_name:sub(10)
	local width_len = size:find("x")
	local width,height = tonumber(size:sub(1,width_len-1)),tonumber(size:sub(width_len+1))
	if not width or not height then error("cip-site-placed was ran on an invalid entity") end

	local orientation = source_entity.orientation
	local direction = source_entity.direction
	local last_user = source_entity.last_user
	local position = source_entity.position
	local recipe = source_entity.get_recipe()
	local dir_info = {
		orientation = orientation,
		width = width,
		height = height,
		circuit_connection = {},
	}--[[@as DirectionInformation]]

	if direction == defines.direction.east
	or direction == defines.direction.west then
		width,height = height,width --[[@as number]] --FIXME: This should not be needed
	end

	local entity_name = "cip-site-"..width.."x"..height
	if not prototypes.entity[entity_name] then
		source_entity.destroy{raise_destroy = false}
		surface.spill_item_stack{
			position = position,
			stack = {name = item_name}
		}
		if last_user then
			last_user.create_local_flying_text{
				create_at_cursor = true,
				text = {"cip-no-recipe"}
			}
		end
		return
	end

	source_entity.destroy{raise_destroy = false}

	local silo = surface.create_entity{
		name = "cip-site-"..width.."x"..height,
		position = position,
		player = last_user,
		force = last_user and last_user.force_index or "player",
		raise_built = false, -- I can be convinced to enable this
		create_build_effect_smoke = false,
		recipe = recipe and recipe.name or nil
	}
	if not silo then error("Could not place actual silo") end
	local unit_number = silo.unit_number
	if not unit_number then error("The silo has no unit number!?") end
	storage.entities[unit_number] = dir_info
	storage.unlocked_silos[unit_number--[[@as uint]]] = silo
	storage.registered[unit_number--[[@as uint]]] = silo
	script.register_on_object_destroyed(silo)
end

--MARK: Ghost placement

script.on_event(defines.events.on_built_entity, function (EventData)
	local ghost = EventData.entity
	local entity_proto = ghost.ghost_prototype
	-- Can't be a tile
	---@cast entity_proto -LuaTilePrototype
	local recipe_name = ciped_entities[entity_proto.name]
	-- Do not process ghost if it's not cip'ed
	if not recipe_name then return end

	local surface = ghost.surface
	local orientation = ghost.orientation
	-- local width, height = entity_proto.tile_width, entity_proto.tile_height
	local width, height = get_dimensions(entity_proto)

	if width > height then
		width,height = height,width--[[@as int]]
		orientation = (orientation + 0.75) % 1
	end

	local entity_name = "cip-item-"..width.."x"..height
	local position = ghost.position
	local direction = math.floor(orientation * 16)--[[@as defines.direction]]
	local player = ghost.last_user
	local force = ghost.force_index

	ghost.destroy{raise_destroy = false}
	surface.create_entity{
		name = "entity-ghost",
		inner_name = entity_name,
		position = position,
		direction = direction,
		player = player,
		force = force,

		recipe = recipe_name,
		create_build_effect_smoke = false,
	}

end, {
	{filter = "type", type = "entity-ghost"}
})

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
	if not unit_number or not storage.registered[unit_number] then return	end
	storage.registered[unit_number] = nil

	local count = entity.rocket_parts
	if count == 0 then
		EventData.buffer.insert(entity.prototype.items_to_place_this[1])
		return
	end

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
	for _, item in pairs(inventory.get_contents()) do
		-- inventory.remove{name=item, count=count}
		buffer.insert(item--[[@as ItemStackDefinition]])
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
	local entity = ciped_items[source_entity.get_recipe().products[1].name]
	local dir_data = storage.entities[source_entity.unit_number--[[@as int]]]
	storage.entities[source_entity.unit_number--[[@as int8]]] = nil

	if not entity then error("Recipe is invalid for contruct in place") end

	local entity_size = {
		width = entity.tile_width,
		height = entity.tile_height,
	}

	if entity_size.width ~= dir_data.width or entity_size.height ~= dir_data.height then
		if entity_size.width ~= dir_data.height or entity_size.height ~= dir_data.width then
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
		surface.spill_item_stack{
			position = position,
			stack = modules[index],
			enable_looted = true,
			force = force,
			allow_belts = false
		}
	end
	for index = 1, input_size, 1 do
		surface.spill_item_stack{
			position = position,
			stack = inputs[index],
			enable_looted = true,
			force = force,
			allow_belts = false
		}
	end
	source_entity.destroy{}

	local direction = math.floor(dir_data.orientation * 16)--[[@as defines.direction]]

	surface.create_entity{
		name = entity.name,
		direction = direction,
		position = position,
		player = last_user,
		force = force,
	}
end

--MARK: Entity Cleanup

script.on_event(defines.events.on_object_destroyed, function (EventData)
	local unit_id = EventData.useful_id
	if not unit_id then return end

	storage.entities[unit_id] = nil
	storage.unlocked_silos[unit_id] = nil
	storage.registered[unit_id] = nil
	log("The unit '"..unit_id.."' has been cleaned up")
end)


--TODO:
-- [ ] Make mining the cip'ed entities drop the recipe ingredients
-- [ ] Make picking the silos return the construction site item
-- [ ] Make bp'ing any cip'ed entities get replaced with the construction site w/ recipe set
--	[ ] Maybe make it item request the required items?
-- [ ] Make placed ghosts of the cip'ed entitites get converted just like when placing a blueprint