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

---@param prototype data.EntityPrototype
---@return int Width The short dimension
---@return int Height The long dimension
local function get_dimensions(prototype)
	local collision = prototype.collision_box or {{0,0},{0,0}}
	local width = prototype.tile_width or math.ceil(collision[2][1] - collision[1][1])
	local height = prototype.tile_height or math.ceil(collision[2][2] - collision[1][2])
	return math.min(width, height), math.max(width, height)
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
	if entity_type == "curved-rail" then goto skip_entity_type end
	for name, prototype in pairs(data.raw[entity_type]--[[@as table<data.EntityID,data.EntityPrototype>]]) do
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
	for name, prototype in pairs(data.raw[item_type]--[[@as table<data.ItemID,data.ItemPrototype>]]) do

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
		local entity_map = entity_to_item[entity.name] or {}--[[@as item_desc[] ]]
		table.insert(entity_map, {name, item_type})
		entity_to_item[entity.name] = entity_map

		item_to_entity[name] = entity

		::continue_item::
	end
end

--MARK: Recipe processing
for name, prototype in pairs(data.raw["recipe"]) do
	local recipe_data = prototype.normal or prototype.expensive or prototype
	local results = recipe_data.results or {{recipe_data.result, recipe_data.result_count}}

	--Make sure it only produces the building
	if #results ~= 1 then goto next_product end
	local product = results[1]

	-- Skip fluids
	if product.type == "fluid" then goto next_product end

	-- Skip products with a chance result
	if product.probability then goto next_product end

	-- Skip products that make more than one (or are a range)
	if product[1] then
		if product[2] ~= nil and product[2] ~= 1 then goto next_product end
	else
		if product.amount ~= 1 then goto next_product end
	end

	-- Make sure it's an item we care about
	local ingredient = product.name or product[1]
	if not important_items[ingredient] then goto next_product end

	-- Add it to the map
	local recipes = item_to_recipe[ingredient] or {}
	table.insert(recipes, name)
	item_to_recipe[ingredient] = recipes

	-- Make sure the recipe is marked as important
	important_recipes[name] = true

	::next_product::
end

--MARK: Technology processing
for name, prototype in pairs(data.raw["technology"]) do
	local technology_data = prototype.normal or prototype.expensive or prototype
	for _, effect in pairs(technology_data.effects or {}) do
		-- Make sure it's unlocking a recipe
		if effect.type ~= "unlock-recipe" then goto continue_effect end

		-- Make sure it's unlocking a recipe we care about
		if not important_recipes[effect.recipe] then goto continue_effect end

		-- Add it to the map
		local technologies = recipe_to_technology[effect.recipe] or {}
		table.insert(technologies, name)
		recipe_to_technology[effect.recipe] = technologies


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

__DebugAdapter.print(important_recipes)

local old = {
	important_entities = important_entities,
	important_items = important_items,
}

important_entities = {}
important_items = {}

--MARK: Important Trimming
for recipe in pairs(important_recipes) do
	local recipe_prototype = data.raw["recipe"][recipe]
	local recipe_data = recipe_prototype.normal or recipe_prototype.expensive or recipe_prototype
	local products = recipe_data.results or {{recipe_data.result, recipe_data.result_count}}
	for _, value in pairs(products) do
		if value.type == "fluid" then goto skip_product end

		local name = value.name or value[1]
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

__DebugAdapter.print(important_entities)
print("tmp")
--MARK: Recipe modification

---@type table<int,table<int,true>>
local sizes = {}
local parts_required = settings.startup["cip-parts-required"].value --[[@as int]]

for item in pairs(important_items) do
	local recipes = item_to_recipe[item]
	local entity = item_to_entity[item]
	local width, height = get_dimensions(entity)

	local width_array = sizes[width] or {}
	sizes[width] = width_array
	width_array[height] = true

	local category_name = "cip-category-"..width.."x"..height

	for _, recipe_name in pairs(recipes) do
		local recipe = data.raw["recipe"][recipe_name]
		recipe.category = category_name

		local ingredients =
				(recipe.normal and recipe.normal.ingredients)
				or (recipe.expensive and recipe.expensive.ingredients)
				or recipe.ingredients
		---@cast ingredients -?

		for _, ingredient in pairs(ingredients) do
			if ingredient.amount then
				ingredient.amount = math.ceil(ingredient.amount / parts_required)
			else
				ingredient[2] = math.ceil(ingredient[2] / parts_required)
			end
			if ingredient.catalyst_amount then
				ingredient.catalyst_amount = math.ceil(ingredient.catalyst_amount / parts_required)
			end
		end
	end
end

--MARK: Size creation

local dummy_animation = {
	frame_count = 1,
	filename = "__core__/graphics/empty.png",
	size = {1,1}
}--[[@as data.Animation]]
local dummy_sprite = {
	filename = "__core__/graphics/empty.png",
	size = {1,1}
}--[[@as data.Sprite]]

for width, heights in pairs(sizes) do
	for height in pairs(heights) do
		local size_name = width.."x"..height
		local item_name = "cip-item-"..size_name
		local silo_name = "cip-site-"..size_name
		local category_name = "cip-category-"..size_name
		data:extend{
		--[[ FIXME:
			Silo's can't be rotated.
			They also retain the numebr of parts crafted when changing recipe
			Maybe replace with assembling machines and ditch the 
		]]
			{
				type = "rocket-silo",
				name = silo_name,

				active_energy_usage = "1W",
				lamp_energy_usage = "0W",
				rocket_entity = "cip-dummy-rocket",
				arm_02_right_animation = dummy_animation,
				arm_01_back_animation = dummy_animation,
				arm_03_front_animation = dummy_animation,
				shadow_sprite = dummy_sprite, -- TODO: Implement this
				hole_sprite = dummy_sprite, -- TODO: Implement this?
				hole_light_sprite = dummy_sprite, -- TODO: ?
				rocket_shadow_overlay_sprite = dummy_sprite,
				rocket_glow_overlay_sprite = dummy_sprite,
				door_back_sprite = dummy_sprite,
				door_front_sprite = dummy_sprite,
				base_day_sprite = dummy_sprite,
				base_front_sprite = dummy_sprite,
				red_lights_back_sprites = dummy_sprite,
				red_lights_front_sprites = dummy_sprite,
				hole_clipping_box = {{0,0},{0,0}},
				door_back_open_offset = {0,0},
				door_front_open_offset = {0,0},
				silo_fade_out_start_distance = 10, -- TODO: Figure out what this is
				silo_fade_out_end_distance = 20,
				times_to_blink = 5,
				light_blinking_speed = 1.0,
				door_opening_speed = 1.0,
				rocket_parts_required = parts_required,
				alarm_trigger = {
					type = "script",
					effect_id = "constructed-in-place"
				},

				energy_usage = "1W",
				crafting_speed = 1.0,
				crafting_categories = {category_name},
				energy_source = {type="void"},
				animation = {
					north = {
						frame_count = 1,
						filename = "__core__/graphics/color_luts/lut-day.png",
						size = {1,1},
						position = {0,15},
						scale = math.min(width,height)*32
					},
					east = {
						frame_count = 1,
						filename = "__core__/graphics/color_luts/lut-day.png",
						size = {1,1},
						position = {15,0},
						scale = math.min(width,height)*32
					},
					south = {
						frame_count = 1,
						filename = "__core__/graphics/color_luts/lut-day.png",
						size = {1,1},
						position = {255,0},
						scale = math.min(width,height)*32
					},
					west = {
						frame_count = 1,
						filename = "__core__/graphics/color_luts/lut-day.png",
						size = {1,1},
						position = {240,15},
						scale = math.min(width,height)*32
					},
				},

				collision_box = {{(width-0.01)/-2, (height-0.01)/-2},{(width-0.01)/2,(height-0.01)/2}},
				selection_box = {{width/-2, height/-2},{width/2,height/2}},
			}--[[@as data.RocketSiloPrototype]],
			{
				type = "recipe-category",
				name = category_name
			}--[[@as data.RecipeCategory]],

			{
				type = "recipe",
				name = "cip-recipe-"..size_name,
				ingredients = {
					{name = "wood", amount = width*height}
				},
				results = {
					{name = item_name, amount = 1 }
				}
			} --[[@as data.RecipePrototype]],
			{
				type = "item",
				name = item_name,
				icon = "__core__/graphics/icons/unknown.png",
				icon_size = 64,
				stack_size = 50,
				place_result = silo_name,
			} --[[@as data.ItemPrototype]]
		}
	end
end

data:extend{{
	type = "rocket-silo-rocket",
	name = "cip-dummy-rocket",

	rocket_sprite = dummy_sprite,
	rocket_shadow_sprite = dummy_sprite,
	rocket_glare_overlay_sprite = dummy_sprite,
	rocket_smoke_bottom1_animation = dummy_animation,
	rocket_smoke_bottom2_animation = dummy_animation,
	rocket_smoke_top1_animation = dummy_animation,
	rocket_smoke_top2_animation = dummy_animation,
	rocket_smoke_top3_animation = dummy_animation,
	rocket_flame_animation = dummy_animation,
	rocket_flame_left_animation = dummy_animation,
	rocket_flame_right_animation = dummy_animation,
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
}--[[@as data.RocketSiloRocketPrototype]]}

--TODO: Figure out how to make them drop (almost) all the ingredients when mined

