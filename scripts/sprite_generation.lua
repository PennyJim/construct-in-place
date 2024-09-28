---Taken from https://mods.factorio.com/mod/WideChests
---Then adapted to make sense to me

-- prng.lua
-- Code from https://github.com/bobbens/ArtTreeKS/blob/master/examples/prng.lua

prng = { z = 1 }

---@param str string
function prng.initHash(str)
	local hash = 5381
	local i = 1
	local bytes = { string.byte(str, 1, string.len(str)) }
	for _,c in ipairs(bytes) do
		hash = hash * 33 + c
	end
	prng.z = math.abs(math.fmod(hash, 4294967295))
end

---@return number
function prng.num()
	prng.z = math.abs(math.fmod(prng.z * 279470273, 4294967295))
	return prng.z / 4294967295
end

---@param min int
---@param max int
---@return int
function prng.range(min, max)
	local n = prng.num()
	return math.floor(min + n * (max - min) + 0.5)
end

prng.initHash('Construct in Place')
-- math_utils.lua

---@param num number
---@return integer
function math.round(num)
	if num >= 0 then
		return math.floor(num + 0.5)
	else
		return math.ceil(num - 0.5)
	end
end

---@param num1 number
---@param num2 number
---@return number
function math.gcd(num1, num2)
	if num1 == num2 then
		return num1
	elseif num1 > num2 then
		return math.gcd(num1 - num2, num2)
	else
		return math.gcd(num1, num2 - num1)
	end
end

---@param num1 number
---@param num2 number
---@return number
function math.lcm(num1, num2)
	return num1 * num2 / math.gcd(num1, num2)
end

--- @class sprite_data_core
--- @field filename? string
--- @field frame_count? int
--- @field scale? double
--- @field shift? data.Vector.struct
--- @field tint? Color

--- @class sprite_data : sprite_data_core
--- @field width? int
--- @field height? int
--- @field hr? sprite_segment_variants

--- @class sprite_segment : data.AnimationParameters
--- The path to the sprite file to use.
--- 
--- Required if the parent `sprite_definition` doesn't define `filename`.
--- @field filename data.FileName?
--- Default: `{0, 0}`
--- 
--- The shift in tiles. Compounds with the shift in the parent `sprite_definition`.
--- @field shift data.Vector?
--- Default: `sprite_definiton.shift` or `1`
--- 
--- Values other than `1` specify the scale of the sprite on default zoom. A scale of `2` means that the picture will be two times bigger on screen (and thus more pixelated).
--- @field scale double?
--- Default: `false`
--- 
--- This is overriden by the value in the parent `sprite_definition` if it is set.
---
--- Only one of `draw_as_shadow`, `draw_as_glow` and `draw_as_light` can be true. This takes precedence over `draw_as_glow` and `draw_as_light`.
--- @field draw_as_shadow? boolean
--- Default: `false`
--- 
--- This is overriden by the value in the parent `sprite_definition` if it is set.
---
--- Only one of `draw_as_shadow`, `draw_as_glow` and `draw_as_light` can be true. This takes precedence over `draw_as_light`.
--- @field draw_as_glow? boolean
--- Default: `false`
--- 
--- This is overriden by the value in the parent `sprite_definition` if it is set.
---
--- Only one of `draw_as_shadow`, `draw_as_glow` and `draw_as_light` can be true.
--- @field draw_as_light? boolean
--- Default: `sprite_definition.tint`
--- @field tint? Color
--- Default: `sprite_definition.run_mode`
--- @field run_mode? "forward"|"backward"|"forward-then-backward"
--- Default: `sprite_definition.frame_count` or `1`
--- 
--- Can't be `0`.
--- @field frame_count? uint32
--- Default: `sprite_definition.line_length` or `0`
--- 
--- Specifies how many pictures are on each horizontal line in the image file. `0` means that all the pictures are in one horizontal line. Once the specified number of pictures are loaded from a line, the pictures from the next line are loaded. This is to allow having longer animations loaded in to Factorio's graphics matrix than the game engine's width limit of 8192px per input file. The restriction on input files is to be compatible with most graphics cards.
--- @field line_length? uint32
--- Default: `sprite_definition.animation_speed` or `1`
--- 
--- Modifier of the animation playing speed, the default of `1` means one animation frame per tick (60 fps). The speed of playing can often vary depending on the usage (output of steam engine for example). Has to be greater than `0`.
--- @field animation_speed? float
--- Default: `sprite_definition.max_advance` or MAX_FLOAT
--- 
--- Maximum amount of frames the animation can move forward in one update. Useful to cap the animation speed on entities where it is variable, such as car animations.
--- @field max_advance? float
--- Default: `sprite_definition.repeat_count` or `1`
--- 
--- How many times to repeat the animation to complete an animation cycle. E.g. if one layer is 10 frames, a second layer of 1 frame would need `repeat_count = 10` to match the complete cycle.
--- @field repeat_count? uint8

--- @alias sprite_segment_variants sprite_segment | sprite_segment[]

--- @alias section_names
--- | -- Top row
--- | "top_left"
--- | "top_middle"
--- | "top_right"
--- | -- Middle row
--- | "left"
--- | "middle"
--- | "right"
--- | -- Bottom row
--- | "bottom_left"
--- | "bottom_middle"
--- | "bottom_right"
--- |
--- | -- Width of 1
--- | "top_corners",
--- | "vertical_edges"
--- | "bottom_corners"
--- | -- Height of 1
--- | "left_corners"
--- | "horizontal_edges"
--- | "right_corners"
--- | -- Both a height and width of 1
--- | "all_corners"
--- |
--- | -- Decoration?
--- | "top_center"
--- | "left_center"
--- | "center"
--- | "right_center"
--- | "bottom_center"

--- @class sprite_definition : data.AnimationParameters
--- @field [section_names] sprite_segment_variants?
--- The path to the default sprite file to use
--- @field filename? data.FileName
--- Not used. Set it in the `sprite_segment`
--- @field x nil
--- Not used. Set it in the `sprite_segment`
--- @field y nil
--- Not used. Set it in the `sprite_segment`
--- @field position nil
--- Default: `false`
--- 
--- This overrides the value in any `sprite_segment`.
---
--- Only one of `draw_as_shadow`, `draw_as_glow` and `draw_as_light` can be true. This takes precedence over `draw_as_glow` and `draw_as_light`.
--- @field draw_as_shadow? boolean
--- Default: `false`
--- 
--- This overrides the value in any `sprite_segment`.
---
--- Only one of `draw_as_shadow`, `draw_as_glow` and `draw_as_light` can be true. This takes precedence over `draw_as_light`.
--- @field draw_as_glow? boolean
--- Default: `false`
--- 
--- This overrides the value in any `sprite_segment`.
---
--- Only one of `draw_as_shadow`, `draw_as_glow` and `draw_as_light` can be true.
--- @field draw_as_light? boolean
--- Not used. Set it in the `sprite_segment`
--- @field mipmap_count nil
--- The high resolution definition
--- @field hr_version? sprite_definition

--- @class entity_sprite
--- @field entity  sprite_definition
--- @field shadow? sprite_definition

---@param sprite data.Animation[]
local function postprocess_sprite(sprite)
	local lcm = 1
	for _, layer in ipairs(sprite) do
		if layer.frame_count then
			lcm = math.lcm(lcm, layer.frame_count)
		end
	end

	if lcm > 1 then
		for _, layer in ipairs(sprite) do
			layer.repeat_count = lcm / (layer.frame_count or 1)
		end
	end
end

-- top left corner of sprite will be placed onto center of entity (plus shifts)
-- random decals may be used
-- shiftX, shiftY = local segment tile shift
-- shifts in segment(s) are pixel shifts
--- @param segments sprite_definition
--- @param segment_name section_names
--- @param shift_x number
--- @param shift_y number
--- @return data.Animation?
local function create_sprite_tile(segments, segment_name, shift_x, shift_y)
	local segment = segments--[[@as table<section_names,sprite_segment_variants>]][segment_name]
	if not segment then return end

	-- Choose a variant
	if segment[1] ~= nil then
		if prng.range(1, 100) > 20 then
			segment = segment[1]
		else
			segment = segment[prng.range(2, #segment)]
		end
	end

	-- Get the hr_version if defined
	---@type data.Animation?
	local hr_version
	if segments.hr_version then
		hr_version = create_sprite_tile(segments.hr_version, segment_name, shift_x, shift_y)
	end

	-- Get the width and height
	local default_size = segments.size or {segments.width, segments.height}
	if type(default_size) == "number" then default_size = {default_size,default_size}	end
	local size = segment.size or {segment.width, segment.height}
	if type(size) == "number" then size = {size,size}	end
	local width,height = size[1]or default_size[1],size[2]or default_size[2]

	-- Get the sprite position
	local x,y = segment.x or 0,segment.y or 0
	if x == 0 and y == 0 then
		x,y = table.unpack(segment.position or {0,0})--[[@as data.SpriteSizeType]]
	end

	local scale = segment.scale or segments.scale or 1

	-- Get the shift
	local default_shift = segments.shift or {x=0,y=0}
	default_shift.x = default_shift[1]or default_shift.x
	default_shift.y = default_shift[1]or default_shift.y
	local shift = segment.shift or {x=0,y=0}
	shift.x = shift[1]or shift.x
	shift.y = shift[1]or shift.y

	-- Update the shift
	shift = { -- What exactly is this math?
		shift_x + (width / 2.0 * scale + shift.x + default_shift.x) / 32.0,
		shift_y + (height / 2.0 * scale + shift.y) / 32.0
	}

	return
	{
		-- SpriteParameters
		filename = segment.filename or segments.filename,
		-- priority = 'medium',
		flags = segment.flags or segments.flags,
		width = width, height = height,
		x = x, y = y,
		shift = shift,
		scale = scale,
		draw_as_shadow = segments.draw_as_shadow or segment.draw_as_shadow,
		draw_as_glow = segments.draw_as_glow or segment.draw_as_glow,
		draw_as_light = segments.draw_as_light or segment.draw_as_light,
		mipmap_count = segment.mipmap_count,
		apply_runtime_tint = segment.apply_runtime_tint ~= nil and segment.apply_runtime_tint or segments.apply_runtime_tint,
		tint = segment.tint or segments.tint,
		-- blend_mode = segment.blend_mode or segments.blend_mode, -- I don't see a single good use for this
		premul_alpha = segment.premul_alpha ~= nil and segment.premul_alpha or segments.premul_alpha,

		-- AnimationParameters
		run_mode = segment.run_mode or segments.run_mode,
		frame_count = segment.frame_count or segments.frame_count or 1,
		line_length = segment.line_length or segments.line_length,
		animation_speed = segment.animation_speed or segments.animation_speed,
		max_advance = segment.max_advance or segments.max_advance,
		repeat_count = segment.repeat_count or segments.repeat_count,
		frame_sequence = segment.frame_sequence,

		-- To support hr_version :)
		hr_version = hr_version
	}--[[@as data.Animation]]
end

---@class row_names
---@field [1] section_names left
---@field [2] section_names middle
---@field [3] section_names right
---@field [4] section_names corner or edges

---@param sprite_layers data.Animation[]
---@param segments sprite_definition
---@param names row_names
---@param x0 number
---@param xM number
---@param width int
---@param y number
local function create_sprite_row(sprite_layers, segments, names, x0, xM, width, y)
	---@type data.Animation[]
	local temp = {}

	if width ~= 1 then
		-- Do row of sprites
		temp[1] = create_sprite_tile(segments, names[1], x0, y)
		for x = 1, width - 2 do
			temp[x+1] = create_sprite_tile(segments, names[2], x0 + x, y)
		end
		temp[width] = create_sprite_tile(segments, names[3], xM, y)
	else
		-- Do single sprite
		temp[1] = create_sprite_tile(segments, names[4], x0, y)
	end

	-- Add created tiles to the layers
	for _, animation in pairs(temp) do
		table.insert(sprite_layers, animation)
	end
end

--- @param width int
--- @param height int
--- @param segments sprite_definition
--- @param sprite_layers data.Animation[]
local function create_entity_sprite(width, height, segments, sprite_layers)
	local x0 = -width / 2
	local y0 = -height / 2
	local xM = width / 2 - 1
	local yM = height / 2 - 1

	if height > 1 then
		-- Do top line
		create_sprite_row(sprite_layers, segments,
			{"top_left", "top_middle", "top_right", "top_corners"},
			x0, xM, width, y0
		)

		-- do middle lines
		for y = 1, height - 2 do
			create_sprite_row(sprite_layers, segments,
				{"left", "middle", "right", "vertical_edges"},
				x0, xM, width, y0 + y
			)
		end

		-- do bottom line
		create_sprite_row(sprite_layers, segments,
			{"bottom_left", "bottom_middle", "bottom_right", "bottom_corners"},
			x0, xM, width, yM
		)
	else

		-- Do only row
		create_sprite_row(sprite_layers, segments,
			{"left_corners", "horizontal_edges", "right_corners", "all_corners"},
			x0, xM, width, yM
		)
	end

	-- centers
	if segments.top_center then
		table.insert(sprite_layers, create_sprite_tile(segments, "top_center", (x0 + xM) / 2, y0))
	end
	if segments.left_center then
		table.insert(sprite_layers, create_sprite_tile(segments, "left_center", x0, (y0 + yM) / 2))
	end
	if segments.center then
		table.insert(sprite_layers, create_sprite_tile(segments, "center", (x0 + xM) / 2, (y0 + yM) / 2))
	end
	if segments.right_center then
		table.insert(sprite_layers, create_sprite_tile(segments, "right_center", xM, (y0 + yM) / 2))
	end
	if segments.bottom_center then
		table.insert(sprite_layers, create_sprite_tile(segments, "bottom_center", (x0 + xM) / 2, yM))
	end
end

--- @param width int
--- @param height int
--- @param segments entity_sprite
--- @return data.Animation
local function create_sprite(width, height, segments)
	local sprite_layers = {}

	create_entity_sprite(width, height, segments.entity, sprite_layers)
	if segments.shadow then
		create_entity_sprite(width, height, segments.shadow, sprite_layers)
	end

	postprocess_sprite(sprite_layers)

	return {
		layers = sprite_layers
	}
end

return create_sprite