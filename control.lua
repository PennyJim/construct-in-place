
---@class DirectionInformation
---@field orientation RealOrientation
---@field width int
---@field height int
---@field bp_stats? string -- Determine exact type later
---@field circuit_connection {[defines.wire_connector_id]:WireConnection[]}

---@class PlayerRecord
---@field picked_bp table -- Same type as DirectionInformation::bp_stats

---@class CIPGlobal
--- The silos and their direction information
---@field entities table<uint, DirectionInformation>
--- The silos that can still change their recipe
---@field unlocked_silos table<uint, LuaEntity>
--- The silos we care about
---@field registered table<uint, LuaEntity>
---@field players table<uint, PlayerRecord>
---@field bp_inventory LuaInventory
storage = {
	entities={},
	unlocked_silos={},
	registered={},
	players={},
	-- bp_inventory=nil,
}
script.on_init(function ()
	storage.bp_inventory = game.create_inventory(1)
end)
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

--MARK: Get requester tech

---@type table<data.RecipeID, true>
local requester_recipes = {}
do
	---@type ItemPrototypeFilter[]
	local requester_chests, requester_count = {}, 0
	for logistic_name, logistic_chest in pairs(prototypes.get_entity_filtered{
		{filter = "type", type = "logistic-container"}
	}) do
		if logistic_chest.logistic_mode == "requester" then
			requester_count = requester_count + 1
			requester_chests[requester_count] = {
				filter = "name",
				name = logistic_name,
				mode = "or",
			}
		end
	end

	---@type TechnologyPrototypeFilter[]
	local tech_filter, filter_count = {}, 0
	for recipe_name in pairs(prototypes.get_recipe_filtered{
		{filter = "has-product-item", elem_filters = {
			{filter = "place-result", elem_filters = requester_chests}
		}}
	}) do
		requester_recipes[recipe_name] = true
	end
end

---@param force LuaForce
---@return boolean
local function has_requesters_unlocked(force)
	local recipes = force.recipes
	for recipe_name in pairs(requester_recipes) do
		if recipes[recipe_name].enabled then return true end
	end
	return false
end
--MARK: Placement

local recipe_count = settings.startup["cip-parts-required"].value --[[@as int]]
---@param built_entity LuaEntity
---@param tags? {cip_bp:string?}
local function site_placed(built_entity, tags)
	local surface = built_entity.surface

	local item_name = built_entity.name
	local size = item_name:sub(10)
	local width_len = size:find("x")
	local width,height = tonumber(size:sub(1,width_len-1)),tonumber(size:sub(width_len+1))
	-- If the given entity is invalid now, justlet the error happen when trying to concatenate it
	---@cast width -?
	---@cast height -?

	local orientation = built_entity.orientation
	local direction = built_entity.direction
	local last_user = built_entity.last_user
	local position = built_entity.position
	local recipe, quality = built_entity.get_recipe()
	quality = quality or prototypes.quality["normal"]
	local dir_info = {
		orientation = orientation,
		width = width,
		height = height,
		circuit_connection = {},
		bp_stats = tags and tags.cip_bp,
	}--[[@as DirectionInformation]]

	if direction == defines.direction.east
	or direction == defines.direction.west then
		width,height = height,width --[[@as number]] --FIXME: This should not be needed
	end

	local entity_name = "cip-site-"..width.."x"..height
	if not prototypes.entity[entity_name] then
		built_entity.destroy{raise_destroy = false}
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

	built_entity.destroy{raise_destroy = false}
	local force_id = last_user and last_user.force_index or "player"

	local silo = surface.create_entity{
		name = "cip-site-"..width.."x"..height,
		position = position,
		player = last_user,
		force = force_id,
		raise_built = false, -- I can be convinced to enable this
		create_build_effect_smoke = false,
		recipe = recipe and recipe.name or nil,
		quality = quality,
	}
	if not silo then error("Could not place actual silo") end
	local unit_number = silo.unit_number
	---@cast unit_number -?

	storage.entities[unit_number] = dir_info
	storage.unlocked_silos[unit_number--[[@as uint]]] = silo
	storage.registered[unit_number--[[@as uint]]] = silo
	script.register_on_object_destroyed(silo)



	-- TODO: Also check a technology
	if recipe and has_requesters_unlocked(game.forces[force_id]) then
		---@type BlueprintInsertPlan[]
		local insert_plan = {}
		for index, ingredient in pairs(recipe.ingredients) do
			insert_plan[index] = {
				id = {name = ingredient.name, quality = quality.name},
				items = {
					in_inventory = {
						{
							inventory = defines.inventory.assembling_machine_input,
							stack = index-1,
							count = ingredient.amount * recipe_count,
						}
					}
				}
			}
		end

		surface.create_entity{
			name = "item-request-proxy",
			target = silo,
			modules = insert_plan,

			position = position,
			last_user = last_user,
			force = force_id,
		}
	end
end

--MARK: Ghost placement

---@param EventData BuiltEventData
local function on_ghost_built(EventData)
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
	local quality = ghost.quality

	local bp_stack = storage.bp_inventory[1]
	bp_stack.set_stack("blueprint")
	local entities = bp_stack.create_blueprint{
		area = ghost.selection_box,
		surface = surface,
		force = force,
	}

	local real_entity_number = ghost.unit_number
	local real_entity, has_extra = 0, false
	for index, source_entity in pairs(entities) do
		if source_entity.unit_number ~= real_entity_number then
			has_extra = true
			if real_entity ~= 0 then break end
		else
			real_entity = index
			if has_extra then break end
		end
	end
	if real_entity == 0 then error("Didn't grab the entity inside its own collision box??") end

	if has_extra then
		local bp_entities = bp_stack.get_blueprint_entities()
		---@cast bp_entities -?
		bp_stack.set_blueprint_entities{bp_entities[real_entity]}
	end

	ghost.destroy{raise_destroy = false}
	local new_entity = surface.create_entity{
		name = "entity-ghost",
		inner_name = entity_name,
		position = position,
		direction = direction,
		player = player,
		force = force,

		-- recipe = recipe_name,
		create_build_effect_smoke = false,
		tags = {cip_bp = bp_stack.export_stack()}
	}
	if not new_entity then error("Couldn't make the new enity ghost!?") end
	new_entity.set_recipe(recipe_name, quality) -- Get rid of once `recipe` is a functional parameter
end

--MARK: Generic on_built

---@param EventData BuiltEventData
local function on_built(EventData)
	local entity = EventData.entity
	if entity.type == "entity-ghost" then return on_ghost_built(EventData) end

	local name = entity.name
	if name:sub(1,9) ~= "cip-item-" then return end

	site_placed(entity, EventData.tags--[[@as {cip_bp:string?}? ]])
end


---@diagnostic disable-next-line: duplicate-doc-alias
---@alias BuiltEventData
---| EventData.on_built_entity
---| EventData.on_robot_built_entity
---| EventData.on_space_platform_built_entity
---| EventData.script_raised_built
---| EventData.script_raised_revive
script.on_event(defines.events.on_built_entity, on_built)
script.on_event(defines.events.on_robot_built_entity, on_built)
script.on_event(defines.events.on_space_platform_built_entity, on_built)
script.on_event(defines.events.script_raised_built, on_built)
script.on_event(defines.events.script_raised_revive, on_built)

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

--MARK: Bp'ing
---TODO: implement blueprint handling to make copied sites just work

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
	local width, height = get_dimensions(entity)

	if width ~= dir_data.width or height ~= dir_data.height then
		if width ~= dir_data.height or height ~= dir_data.width then
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

	if dir_data.bp_stats then
		local bp_stack = storage.bp_inventory[1]
		bp_stack.import_stack(dir_data.bp_stats)
		bp_stack.build_blueprint{
			force = force,
			surface = surface,
			position = position,
		}
	end
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
-- [x] Make mining the cip'ed entities drop the recipe ingredients
-- [x] Make picking the silos return the construction site item
-- [x] Make cip'ed entities ghosts get replaced with the construction site w/ recipe set
--	[x] Maybe make it item request the required items?
-- [ ] Change out cip sites with recipes set to the cip'ed entity when copying
-- [ ] Change out the cip sites without recipes set to the assembling machine entity