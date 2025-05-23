---@type table<data.EntityID,data.EntityPrototype>
local important_entities = {}
---@alias item_desc {[1]:data.ItemID,[2]:defines.prototypes.item}
---@type table<data.ItemID,item_desc|data.EntityPrototype>
local important_items = {}
---@type table<data.RecipeID, true>
local important_recipes = {}

---@type table<data.EntityID,item_desc[]>
local entity_to_item = {}
---@type table<data.ItemID,data.EntityPrototype>
local item_to_entity = {}
---@type table<data.ItemID,data.RecipeID[]>
local item_to_recipe = {}
---@type table<data.RecipeID,data.TechnologyID[]>
local recipe_to_technology = {}

---@generic I
---@generic A
---@param map table<I,A[]>
---@param index I
---@param new_item A
---@overload fun(map:table<data.EntityID,item_desc[]>,index:data.EntityID,new_item:item_desc)
---@overload fun(map:table<data.ItemID,data.RecipeID[]>,index:data.ItemID,new_item:data.RecipeID)
---@overload fun(map:table<data.RecipeID,data.TechnologyID[]>,index:data.RecipeID,new_item:data.TechnologyID)
local function append_to_map_array(map, index, new_item)
	local array = map[index]
	if not array then
		map[index] = {new_item}
	else
		table.insert(array, new_item)
	end
end

---@param prototype data.EntityPrototype
---@return int Width The short dimension
---@return int Height The long dimension
local function get_dimensions(prototype)
	local collision = prototype.collision_box or {{0,0},{0,0}}
	-- Tile width seems to lie between data and runtime
	local width = math.ceil(collision[2][1] - collision[1][1])
	local height = math.ceil(collision[2][2] - collision[1][2])
	return width, height
end

---@param prototype data.EntityPrototype
---@return int
local function calc_area(prototype)
	local width, height = get_dimensions(prototype)
	return width * height
end

local minimum_size = settings.startup["cip-minimum-size"].value --[[@as int]]

--MARK: Entity processing
for entity_type in pairs(defines.prototypes.entity) do
	---@diagnostic disable-next-line: cast-type-mismatch
		---@cast entity_type defines.prototypes.entity
	for name, prototype in pairs(data.raw[entity_type]--[[@as table<data.EntityID,data.EntityPrototype>]] or {}) do
		-- Check that' it's large enough
		if calc_area(prototype) < minimum_size then goto continue_entity end

		-- Add entity to array of important entities
		important_entities[name] = prototype

		-- Leave now if it doesn't have an item that places it
		if not prototype.placeable_by then goto continue_entity end
		-- Make sure it's an array
		---@type data.ItemToPlace[]
		local placeable_by = prototype.placeable_by.count and {prototype.placeable_by} or prototype.placeable_by

		---@type data.ItemID[]
		local items,index = {},1
		for _,value in pairs(placeable_by) do
			important_items[value.item] = prototype
			items[index] = value.item
			index = index + 1

			item_to_entity[value.item] = prototype -- Might not be necessary?
		end
		entity_to_item[name] = items

		::continue_entity::
	end
	::skip_entity_type::
end

--MARK: Item processing
for item_type in pairs(defines.prototypes.item) do
---@diagnostic disable-next-line: cast-type-mismatch
	---@cast item_type defines.prototypes.item
	for name, prototype in pairs(data.raw[item_type]--[[@as table<data.ItemID,data.ItemPrototype>]] or {}) do

		local entity = important_items[name] --[[@as data.EntityPrototype]]

		-- If it's not already marked important
		if not entity then
			-- Make sure it has a place result
			local entity_name = prototype.place_result
			if not entity_name then goto continue_item end
			-- Then make sure that result was marked important
			entity = important_entities[entity_name]
			if not entity then goto continue_item end
		end

		-- Update or add the important_items entry
		important_items[name] = {name, item_type}

		-- Add item to array for placed entity's lookup
		append_to_map_array(entity_to_item, entity.name, {name, item_type})

		item_to_entity[name] = entity

		::continue_item::
	end
end

--MARK: Recipe processing
for name, recipe in pairs(data.raw["recipe"]) do
	-- Skip parameter recipes
	if recipe.parameter then goto next_product end
	local results = recipe.results or {}

	-- Make sure it only produces the building
	if #results ~= 1 then goto next_product end
	local product = results[1]

	-- Skip fluids
	if product.type == "fluid" then goto next_product end

	-- Skip products with a chance result
	if product.probability then goto next_product end

	-- Skip products that make more than one (or are a range)
	if product.amount ~= 1 then goto next_product end

	-- Skip products that use a fluid (for now)
	for _, ingredient in pairs(recipe.ingredients) do
		if ingredient.type == "fluid" then goto next_product end
	end

	-- Make sure it's an item we care about
	local product_name = product.name
	if not important_items[product_name] then goto next_product end

	-- Add it to the map
	append_to_map_array(item_to_recipe, product_name, name)

	-- Make sure the recipe is marked as important
	important_recipes[name] = true

	::next_product::
end

--MARK: Technology processing
for name, technology in pairs(data.raw["technology"]) do
	for _, effect in pairs(technology.effects or {}) do
		-- Make sure it's unlocking a recipe
		if effect.type ~= "unlock-recipe" then goto continue_effect end

		-- Make sure it's unlocking a recipe we care about
		if not important_recipes[effect.recipe] then goto continue_effect end

		-- Add it to the map
		append_to_map_array(recipe_to_technology, effect.recipe, name)

		::continue_effect::
	end
end

--MARK: Duplicate removal

---@param list any[]
---@return any[]
local function remove_duplicates(list)
	---@type table<any,true>
	local visited = {}
	for _, value in pairs(list) do
		visited[value] = true
	end
	---@type any[]
	local new_list,index = {},0
	for value in pairs(visited) do
		index = index + 1
		new_list[index] = value
	end
	return new_list
end

---comment
---@param item table<any,any>
---@param lookups table<table<any,any>,true>
---@return boolean
local function lookup_contains(item, lookups)
	for lookup in pairs(lookups) do
		---@type table<any,true>
		local small_lookup = {}
		-- Check each entry in item to see if it matches the lookup
		for key, value in pairs(item) do
			-- Leave check early if it doesn't match
			if lookup[key] ~= value then goto next_lookup end
			small_lookup[key] = true
		end
		-- Check each entry in the lookup to see if we visited it in the item check
		for key, value in pairs(lookup) do
			-- Leave this check early if it doesn't match
			if not small_lookup[key] then goto next_lookup end
		end

		do
			-- We have made sure they match, so it *does* contain this
			-- In a do/end because luals isn't happy
			return true
		end

		::next_lookup::
	end
	return false
end

---@param list table[]
---@return table[]
local function remove_duplicates_deepcheck(list)
	---@type table<table,true>
	local visited = {}
	for _, value in pairs(list) do
		if not lookup_contains(value, visited) then
			visited[value] = true
		end
	end
	---@type table[]
	local new_list,index = {},0
	for value in pairs(visited) do
		index = index + 1
		new_list[index] = value
	end
	return new_list
end

for index, value in pairs(recipe_to_technology) do
	recipe_to_technology[index] = remove_duplicates(value)
end
for index, value in pairs(item_to_recipe) do
	item_to_recipe[index] = remove_duplicates(value)
end
for index, value in pairs(entity_to_item) do
	entity_to_item[index] = remove_duplicates_deepcheck(value)
end

local old = {
	important_entities = important_entities,
	important_items = important_items,
}

important_entities = {}
important_items = {}

--MARK: Important Trimming
for recipe in pairs(important_recipes) do
	local recipe_prototype = data.raw["recipe"][recipe]
	local products = recipe_prototype.results
	---@cast products -?
	for _, value in pairs(products) do
		if value.type == "fluid" then goto skip_product end

		local name = value.name
		if old.important_items[name] then
			important_items[name] = old.important_items[name]
		end

		::skip_product::
	end
end

for item in pairs(important_items) do
	local entity = item_to_entity[item]
	important_entities[entity.name] = old.important_entities[entity.name]
end

--MARK: Recipe modification

---@type table<int,table<int,boolean>>
local sizes = {}
local parts_required = settings.startup["cip-parts-required"].value --[[@as int]]

for item in pairs(important_items) do
	local recipes = item_to_recipe[item]
	local entity = item_to_entity[item]
	local width, height = get_dimensions(entity)
	local can_rotate = false

	local width_array = sizes[width] or {}
	sizes[width] = width_array
	width_array[height] = width_array[height] or false


	-- If the entity is rotatable
	if width ~= height and (
		(
			entity.type == "rail-ramp"
		) or (
			entity--[[@as data.CraftingMachinePrototype]].graphics_set
			and entity--[[@as data.CraftingMachinePrototype]].graphics_set.animation
			and entity--[[@as data.CraftingMachinePrototype]].graphics_set.animation.east
		) or (
			entity--[[@as data.GeneratorPrototype]].horizontal_animation
			and entity--[[@as data.GeneratorPrototype]].vertical_animation
		)
	) then
		can_rotate = true
		width_array[height] = true
		-- Also mark the rotated size
		width_array = sizes[height] or {}
		sizes[height] = width_array
		width_array[width] = true -- Don't make rotatable?
	end

	local category_name = "cip-category-"..width.."x"..height
	if can_rotate then
		category_name = category_name.."-rot"
	end

	for _, recipe_name in pairs(recipes) do
		local recipe = data.raw["recipe"][recipe_name]
		recipe.category = category_name
		recipe.main_product = recipe.results[1].name
		-- Recipe surface conditions may be lost, but I think this is annoying enough
		recipe.surface_conditions = entity.surface_conditions

		local ingredients = recipe.ingredients
		---@cast ingredients -?

		--- Expand ingredients that are themselves special items
		---@type {[data.ItemID]:data.IngredientPrototype[]}
		local ingredients_map = {}
		for _, ingredient in pairs(ingredients) do
			if important_items[ingredient.name] then
				local ingredient_recipes = item_to_recipe[ingredient.name]
				local ingredient_recipe = ingredient_recipes[#ingredient_recipes]

				for _, ingredient in pairs(data.raw["recipe"][ingredient_recipe].ingredients) do
					append_to_map_array(ingredients_map, ingredient.name, table.deepcopy(ingredient))
				end

			else
				append_to_map_array(ingredients_map, ingredient.name, ingredient)
			end
		end

		-- Merge ingredients and turn back into array
		ingredients = {}
		local ingredient_count = 0
		for name, prototypes in pairs(ingredients_map) do
			local amount = 0
			local ignored_by_stats = 0
			for _, ingredient_prototype in pairs(prototypes) do
				amount = amount + ingredient_prototype.amount
				local stats = ingredient_prototype.ignored_by_stats or 0
				ignored_by_stats = amount + stats
			end

			ingredient_count = ingredient_count + 1
			ingredients[ingredient_count] = {
				type = "item", -- TODO: Maybe support fluid ingredients?
				name = name,
				amount = amount,
				ignored_by_stats = ignored_by_stats,
			}
		end
		recipe.ingredients = ingredients

		---@type data.ProductPrototype[]
		local part_mining_results = {}
		---@type data.ProductPrototype[]
		local entity_mining_results = {}

		for index, ingredient in pairs(ingredients) do
			local amount = math.ceil(ingredient.amount / parts_required)
			ingredient.amount = amount
			ingredient.ignored_by_stats = math.ceil(ingredient.ignored_by_stats / parts_required)

			-- Mining results
			local result = {
				type = ingredient.type,
				name = ingredient.name,
				amount_max = amount,
				amount_min = 0,
				-- probability = 0.8
			}--[[@as data.ProductPrototype]]

			part_mining_results[index] = table.deepcopy(result)
			result.amount_max = result.amount_max * parts_required
			entity_mining_results[index] = result
		end

		--FIXME: Currently just picks the 'last' recipe to determine the entity results
		-- This has a high chance of producing an undesirable result with multiple recipes
		local entity_mineable = entity.minable
		if entity_mineable then
			entity_mineable.result = nil
			entity_mineable.count = nil
			entity_mineable.results = entity_mining_results
		end

		data:extend{
			{
				type = "simple-entity",
				name = "cip-"..recipe_name.."-fragment",
				minable = {
					mining_time = 0.0,
					results = part_mining_results
				}
			}--[[@as data.SimpleEntityPrototype]]
		}
	end
end

--MARK: Construction Graphics

---@type entity_sprite
local construction_segments = {
	entity = {
		filename = "__construct-in-place__/graphics/entity/construction-site/site.png",
		size = {64,64}, scale = 0.5,
		top_left =      {x=0  ,y=0  , repeat_count=32},
		top_middle =    {x=64 ,y=0  , repeat_count=32},
		top_right =     {x=128,y=0  , repeat_count=32},
		left =          {x=0  ,y=64 , repeat_count=32},
		-- middle =        {x=64 ,y=64 , repeat_count=32},
		right =         {x=128,y=64 , repeat_count=32},
		bottom_left =   {x=0  ,y=128, repeat_count=32},
		bottom_middle = {x=64 ,y=128, repeat_count=32},
		bottom_right =  {x=128,y=128, repeat_count=32},

		top_corners =      {x=192,y=0  , repeat_count=32},
		vertical_edges =   {x=192,y=64 , repeat_count=32},
		bottom_corners =   {x=192,y=128, repeat_count=32},
		left_corners =     {x=0  ,y=192, repeat_count=32},
		horizontal_edges = {x=64 ,y=192, repeat_count=32},
		right_corners =    {x=128,y=192, repeat_count=32},
		all_corners =      {x=192,y=192, repeat_count=32},

		center_decoration = {
			filename = "__construct-in-place__/graphics/entity/construction-site/worker-1.png",
			size = {64,64},
			line_length = 8,
			frame_count = 32,
		},
	}
}

--MARK: RocketSilo creation

---@param silo_name data.EntityID
---@param item_name data.ItemID
---@param categories data.RecipeCategoryID[] Will deepcopy this for easy reuse of a table :)
---@param width int
---@param height int
---@param animation data.Animation
---@return data.RocketSiloPrototype
local function rocket_silo(silo_name, item_name, categories, width, height, animation)
	categories = table.deepcopy(categories)
	return {
		type = "rocket-silo",
		name = silo_name,
		localised_name = {"cip-names.site", tostring(width), tostring(height)},

		icon = "__core__/graphics/icons/unknown.png",
		icon_size = 64,

		minable = {
			mining_time = 5
		},
		placeable_by = {
			item = item_name,
			count = 1
		},
		flags = {
			"placeable-player",
			"player-creation",
		},
		alarm_trigger = {
			type = "script",
			effect_id = "cip-site-finished"
		},

		active_energy_usage = "1W",
		lamp_energy_usage = "0W",
		rocket_entity = "cip-dummy-rocket",
		hole_clipping_box = {{0,0},{0,0}},
		door_back_open_offset = {0,0},
		door_front_open_offset = {0,0},
		silo_fade_out_start_distance = 10, -- TODO: Figure out what this is
		silo_fade_out_end_distance = 20,
		times_to_blink = 5,
		light_blinking_speed = 1.0,
		door_opening_speed = 1.0,
		rocket_parts_required = parts_required,
		rocket_quick_relaunch_start_offset = 1.0,
		cargo_station_parameters = {
			hatch_definitions = {{}}
		},

		energy_usage = "1W",
		crafting_speed = 1.0,
		crafting_categories = categories,
		energy_source = {type="void"},
		graphics_set = {
			animation = animation,
		},

		collision_box = {{(width-0.01)/-2, (height-0.01)/-2},{(width-0.01)/2,(height-0.01)/2}},
		selection_box = {{width/-2, height/-2},{width/2,height/2}},
	}--[[@as data.RocketSiloPrototype]]
end

--MARK: Size creation

local create_sprite = require("scripts.sprite_generation")

---@type table<string,data.Animation>
local cached_animations = {}
---@param width int
---@param height int
function make_size(width, height)
	---FIXME: Actually handle can_rotate
	local size_name = width.."x"..height
	---@type data.RecipeID[]
	local categories = {
		"cip-category-"..size_name,              			-- Regular Category
		"cip-category-"..size_name.."-rot",      			-- Rotatable Category
		"cip-category-"..height.."x"..width.."-rot",  -- Rotated Rotatable Category
	}

	local item_name = "cip-item-"..size_name
	---@type data.Animation,data.Animation
	local north_animation,east_animation
	if width > height then
		north_animation = cached_animations[size_name]
		if not north_animation then error("Didn't already cache this orientation") end
		item_name = "cip-item-"..height.."x"..width
	else
		north_animation = create_sprite(width, height, construction_segments)
		east_animation = create_sprite(height, width, construction_segments)
		cached_animations[height.."x"..width] = east_animation
	end

	data:extend{
		rocket_silo("cip-site-"..size_name, item_name, categories, width, height, north_animation),
	}
	-- rocket_silo deepcopies it, so this just makes the code easier
	categories[4] = "cip-category-"..height.."x"..width
	data:extend{
		{
			type = "recipe-category",
			name = categories[1] -- Regular size
		}--[[@as data.RecipeCategory]],
		{
			type = "recipe-category",
			name = categories[2] -- Rotated size
		}--[[@as data.RecipeCategory]],
		{
			type = "recipe-category",
			name = categories[3] -- Rotated Rotatable size
		}--[[@as data.RecipeCategory]],
		{
			type = "recipe-category",
			name = categories[4] -- Rotated Rotatable size
		}--[[@as data.RecipeCategory]],
	}

	-- Don't recreate the reused items
	if width > height then return end

	data:extend{
		{
			type = "item",
			name = item_name,
			-- localised_name = {"cip-names.item", width, height},
			icon = "__core__/graphics/icons/unknown.png",
			icon_size = 64,
			stack_size = 50,
			place_result = item_name,
		} --[[@as data.ItemPrototype]],
		{
			type = "recipe",
			name = item_name,
			ingredients = {
				{type = "item", name = "wood", amount = width*height}
			},
			results = {
				{type = "item", name = item_name, amount = 1 }
			}
		} --[[@as data.RecipePrototype]],
		{
			type = "assembling-machine",
			name = item_name,
			localised_name = {"cip-names.item", tostring(width), tostring(height)},

			icon = "__core__/graphics/icons/unknown.png",
			icon_size = 64,
			flags = {
				"placeable-player",
				"player-creation",
			},

			created_effect = {
				type = "direct",
				action_delivery = {
					type = "instant",
					source_effects = {
						type = "script",
						effect_id = "cip-site-placed"
					}
				}
			},
			collision_box = {{(width-0.01)/-2, (height-0.01)/-2},{(width-0.01)/2,(height-0.01)/2}},
			selection_box = {{width/-2, height/-2},{width/2,height/2}},

			energy_usage = "1J",
			crafting_speed = 0.01,
			crafting_categories = categories,
			energy_source = {type = "void"},
			fluid_boxes = {
				{
					pipe_connections = {{
						direction = defines.direction.north --[[@as data.Direction]],
						position = {0,-height/2+1},
						flow_direction = "output",
					}},
					volume = 100,
					-- hide_connection_info = true,
					off_when_no_fluid_recipe = false,
					production_type = "output",
				}
			},

			graphics_set = {
				animation = {
					north = north_animation,
					east = east_animation,
					south = north_animation,
					west = east_animation,
				},
			}
		}--[[@as data.AssemblingMachinePrototype]],
	}
end

for width, heights in pairs(sizes) do
	for height, can_rotate in pairs(heights) do
		make_size(width, height)
	end
end

data:extend{
	{
		type = "rocket-silo-rocket",
		name = "cip-dummy-rocket",

		cargo_pod_entity = "cip-dummy-cargopod",

		rocket_rise_offset = {0,0},
		rocket_flame_left_rotation = 0,
		rocket_flame_right_rotation = 0,
		rocket_render_layer_switch_distance = 0,
		full_render_layer_switch_distance = 0,
		rocket_launch_offset = {0,0},
		effects_fade_in_start_distance = 0,
		effects_fade_in_end_distance = 0,
		shadow_fade_out_start_ratio = 0,
		shadow_fade_out_end_ratio = 0,
		rocket_visible_distance_from_center = 0,
		rising_speed = 1,
		engine_starting_speed = 1,
		flying_speed = 1,
		flying_acceleration = 1,
		inventory_size = 0,
	}--[[@as data.RocketSiloRocketPrototype]],
	{
		type = "cargo-pod",
		name = "cip-dummy-cargopod",
		inventory_size = 0,
		spawned_container = "cip-dummy-rocket",
	}--[[@as data.CargoPodPrototype]],
}

