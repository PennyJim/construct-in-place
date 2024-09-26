
---@type table<string,fun(EventData.on_script_trigger_effect)>
local script_trigger_handlers = {}
---@class DirectionInformation
---@field direction defines.direction
---@field width int
---@field height int
---@class CIPGlobal
---@field entities table<LuaEntity,DirectionInformation>
---@field unlocked_silos table<uint,LuaEntity>
global = {
	entities={},
	unlocked_silos={},
}
local unlocked_silos = global.unlocked_silos

---@param EventData EventData.on_script_trigger_effect
script_trigger_handlers["cip-site-finished"] = function (EventData)
	
end

---@param EventData EventData.on_script_trigger_effect
script_trigger_handlers["cip-site-placed"] = function (EventData)
	__DebugAdapter.print(EventData)
	local source_entity = EventData.source_entity
	if not source_entity then return end

	local surface = game.get_surface(EventData.surface_index) --[[@as LuaSurface]]

	local size = source_entity.name:sub(10)
	local width_len = size:find("x")
	local width,height = tonumber(size:sub(1,width_len-1)),tonumber(size:sub(width_len+1))
	if not width or not height then error("cip-site-placed was ran on an invalid entity") end

	local direction = source_entity.direction
	local last_user = source_entity.last_user
	local position = source_entity.position
	local dir_info = {
		direction = direction,
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
	global.entities[silo] = dir_info
	global.unlocked_silos[silo.unit_number--[[@as uint]]] = silo
end


script.on_event(defines.events.on_script_trigger_effect, function (EventData)
	local handler = script_trigger_handlers[EventData.effect_id]
	if handler then handler(EventData) end
end)

---@param unit uint
---@param entity LuaEntity
local function check_entities(unit, entity)
	-- Remove entry if it's invalid
	if not entity.valid then
		unlocked_silos[unit] = nil
		return
	end

	-- Lock and remove entity if it's progressed
	if entity.rocket_parts > 0 then
		entity.recipe_locked = true
		unlocked_silos[unit] = nil
		return
	end
end

script.on_event(defines.events.on_tick, function (EventData)
	for unit, entity in pairs(unlocked_silos) do
		check_entities(unit, entity)
	end
end)

script.on_load(function ()
	unlocked_silos = global.unlocked_silos
end)