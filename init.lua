local S = minetest.get_translator(minetest.get_current_modname())

-- globalscope var for the whole mod
sum_airship = {
	i = {},
}

local boat_visual_size = {x = 1, y = 1, z = 1}
local boat_y_offset = 0.35
local boat_y_offset_ground = boat_y_offset + 0.6
local boat_side_offset = 1.001
local boat_max_hp = 4
local speed_mult = 4


-- make sure silly people don't try to run it without the needed dependencies.
if not (minetest.get_modpath("mcl_boats")
and minetest.get_modpath("mcl_wool")
and minetest.get_modpath("mcl_core"))
and not minetest.get_modpath("default") then
	error("\n\n===\nYou need either mcl2 or minetest_game to run sum_airship mod. \n" ..
	"These are listed in the optional dependencies for cross compatibility, " ..
	"but at least one is needed.\n===\n")
end

local has_air_currents = minetest.get_modpath("sum_air_currents") ~= nil
local mcl = minetest.get_modpath("mcl_player") ~= nil

dofile(minetest.get_modpath("sum_airship") .. DIR_DELIM .. "crafts.lua")

local function is_group(pos, group)
	local nn = minetest.get_node(pos).name
	return minetest.get_item_group(nn, group) ~= 0
end

local function is_river_water(p)
	return true
end

local function is_ice(pos)
	return false
end

local function get_sign(i)
	if i == 0 then
		return 0
	else
		return i / math.abs(i)
	end
end

local function get_velocity(v, yaw, y)
	local x = -math.sin(yaw) * v
	local z =  math.cos(yaw) * v
	return {x = x, y = y, z = z}
end

local function get_v(v)
	return math.sqrt(v.x ^ 2 + v.z ^ 2)
end

local function check_object(obj)
	return obj and (obj:is_player() or obj:get_luaentity()) and obj
end

local function get_visual_size(obj)
	return obj:is_player() and {x = 1, y = 1, z = 1} or obj:get_luaentity()._old_visual_size or obj:get_properties().visual_size
end

local function set_attach(boat)
	boat._driver:set_attach(boat.object, "",
		{x = 0, y = 0.42, z = -2}, {x = 0, y = 0, z = 0})
end

local function set_double_attach(boat)
	boat._driver:set_attach(boat.object, "",
		{x = 0, y = 0.8, z = -2}, {x = 0, y = 0, z = 0})
	boat._passenger:set_attach(boat.object, "",
		{x = 0, y = 0.8, z = -3.2}, {x = 0, y = 0, z = 0})
end

local function attach_object(self, obj)
	if self._driver then
		if self._driver:is_player() then
			self._passenger = obj
		else
			self._passenger = self._driver
			self._driver = obj
		end
		set_double_attach(self)
	else
		self._driver = obj
		set_attach(self)
	end

	local visual_size = get_visual_size(obj)
	local yaw = self.object:get_yaw()
	obj:set_properties({visual_size = vector.divide(visual_size, boat_visual_size)})
	if obj:is_player() then
		local name = obj:get_player_name()
		if mcl then mcl_player.player_attached[name] = true end
		minetest.after(0.2, function(player)
			if player and mcl then
				mcl_player.player_set_animation(player, "sit" , 30)
			end
		end, obj)
		obj:set_look_horizontal(yaw)
	else
		obj:get_luaentity()._old_visual_size = visual_size
	end
end

local function detach_object(obj, change_pos)
	obj:set_detach()
	obj:set_properties({visual_size = get_visual_size(obj)})
	if obj:is_player() and mcl then
		mcl_player.player_attached[obj:get_player_name()] = false
		mcl_player.player_set_animation(obj, "stand" , 30)
	else
		local luaent = obj:get_luaentity()
		if luaent then luaent._old_visual_size = nil end
	end
	if change_pos then
		obj:set_pos(vector.add(obj:get_pos(), vector.new(0, 0.2, 0)))
	end
	obj:set_pos(vector.offset(obj:get_pos(), 0, 0.7, 0))
	minetest.after(0.1, function(obj, change_pos)
		obj:set_pos(vector.offset(obj:get_pos(), 0, 0.7, 0))
	end, obj, change_pos)
end

--
-- Boat entity
--

local boat = {
	physical = true,
	pointable = true,
	-- collisionbox = {-0.5, -0.35, -0.5, 0.5, 0.3, 0.5},
	collisionbox = {-0.6, -0.2, -0.6, 0.6, 0.3, 0.6},
	selectionbox = {-0.7, -0.35, -0.7, 0.7, 0.3, 0.7},
	visual = "mesh",
	mesh = "sum_airship_boat.b3d",
	textures = {"sum_airship_texture_oak_boat.png"},
	animations = {
		idle = {x=  10, y= 90},
	},
	visual_size = boat_visual_size,
	hp_max = boat_max_hp,
	damage_texture_modifier = "^[colorize:white:0",

	_driver = nil, -- Attached driver (player) or nil if none
	_passenger = nil,
	_v = 0, -- Speed
	_last_v = 0, -- Temporary speed variable
	_removed = false, -- If true, boat entity is considered removed (e.g. after punch) and should be ignored
	_itemstring = "sum_airship:boat", -- Itemstring of the boat item (implies boat type)
	_animation = 0, -- 0: not animated; 1: paddling forwards; -1: paddling forwards
	_regen_timer = 0,
	_damage_anim = 0,
}

minetest.register_on_respawnplayer(detach_object)

function boat.on_rightclick(self, clicker)
	if self._passenger or not clicker or clicker:get_attach() then
		return
	end
	attach_object(self, clicker)
end


function boat.on_activate(self, staticdata, dtime_s)
	self.object:set_armor_groups({fleshy = 100})
	self.object:set_animation(self.animations.idle, 25)
	local data = minetest.deserialize(staticdata)
	if type(data) == "table" then
		self._v = data.v
		self._last_v = self._v
		self._itemstring = data.itemstring

		while #data.textures < 5 do
			table.insert(data.textures, data.textures[1])
		end

		self.object:set_properties({textures = data.textures})
	end
end

function boat.get_staticdata(self)
	return minetest.serialize({
		v = self._v,
		itemstring = self._itemstring,
		textures = self.object:get_properties().textures
	})
end

function boat.on_death(self, killer)
	if minetest.get_modpath("mcl_burning") then
		mcl_burning.extinguish(self.object) end

	if killer and killer:is_player() and minetest.is_creative_enabled(killer:get_player_name()) then
		local inv = killer:get_inventory()
		if not inv:contains_item("main", self._itemstring) then
			inv:add_item("main", self._itemstring)
		end
	else
		minetest.add_item(self.object:get_pos(), self._itemstring)
	end
	if self._driver then
		detach_object(self._driver)
	end
	if self._passenger then
		detach_object(self._passenger)
	end
	self._driver = nil
	self._passenger = nil
end

function boat.on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
	if damage > 0 then
		self._regen_timer = 0
	end
end

function boat.on_step(self, dtime, moveresult)
	if minetest.get_modpath("mcl_burning") then
		mcl_burning.tick(self.object, dtime, self) end

	self._v = get_v(self.object:get_velocity()) * get_sign(self._v)
	local v_factor = 1
	local v_slowdown = 0.1
	local p = self.object:get_pos()
	local on_water = false
	local in_water = minetest.get_item_group(minetest.get_node(p).name, "liquid") ~= 0
	local node_below = minetest.get_node(vector.offset(p, 0, -0.3, 0)).name
	local is_on_floor = minetest.registered_nodes[node_below].walkable

	local hp = self.object:get_hp()
	local regen_timer = self._regen_timer + dtime
	if hp >= boat_max_hp then
		regen_timer = 0
	elseif regen_timer >= 3 then
		hp = hp + 1
		self.object:set_hp(hp)
		regen_timer = 0
	end
	self._regen_timer = regen_timer

	if moveresult and moveresult.collides then
		for _, collision in pairs(moveresult.collisions) do
			local pos = collision.node_pos
			if collision.type == "node" and minetest.get_item_group(minetest.get_node(pos).name, "dig_by_boat") > 0 then
				minetest.dig_node(pos)
			end
		end
	end


  local climb = 0
  local forward = 0


	local had_passenger = self._passenger

	self._driver = check_object(self._driver)
	self._passenger = check_object(self._passenger)

	if self._passenger then
		if not self._driver then
			self._driver = self._passenger
			self._passenger = nil
		else
			local ctrl = self._passenger:get_player_control()
			if ctrl and ctrl.sneak then
				detach_object(self._passenger, true)
				self._passenger = nil
			end
		end
	end

	if self._driver then
		if had_passenger and not self._passenger then
			set_attach(self)
		end
		local ctrl = self._driver:get_player_control()
		if ctrl and ctrl.sneak then
			detach_object(self._driver, true)
			self._driver = nil
			return
		end
		local yaw = self.object:get_yaw()
		-- if mcl and mcl_player.player_get_animation(self._driver).animation ~= "sit" then
		-- 	mcl_player.player_set_animation(self._driver, "sit" , 30)
		-- end
		if ctrl and not in_water then
			if ctrl.up then
				-- Forwards
				forward = forward + 1
	    elseif ctrl.down then
	      forward = forward - 1
	    end
			if ctrl.aux1 then
				climb = climb - 1
	    elseif ctrl.jump then
	      climb = climb + 1
	    end

			if ctrl.left then
				if self._v < 0 then
					self.object:set_yaw(yaw - (1 + dtime) * 0.03 * v_factor)
				else
					self.object:set_yaw(yaw + (1 + dtime) * 0.03 * v_factor)
				end
			elseif ctrl.right then
				if self._v < 0 then
					self.object:set_yaw(yaw + (1 + dtime) * 0.03 * v_factor)
				else
					self.object:set_yaw(yaw - (1 + dtime) * 0.03 * v_factor)
				end
			end
		end
	end

		-- for _, obj in pairs(minetest.get_objects_inside_radius(self.object:get_pos(), 1.3)) do
		-- 	local entity = obj:get_luaentity()
		-- 	if entity and entity.is_mob then
		-- 		attach_object(self, obj)
		-- 		break
		-- 	end
		-- end
	local s = get_sign(self._v)

	local yaw = self.object:get_yaw()
  local yaw_dir = minetest.yaw_to_dir(yaw)
	local anim = (boat_max_hp - hp - regen_timer / 3) / boat_max_hp * math.pi / 8

	self.object:set_rotation(vector.new(anim, yaw, anim))

  local vel = vector.new(0, 0, 0)
  if self._driver and not in_water then
    dir = vector.multiply(yaw_dir, forward)
    dir.y = climb
    vel = vector.multiply(dir, speed_mult)
  elseif in_water then
		vel = {x=0, y=5, z=0}
	else
		vel = {x=0, y=-0.6, z=0}
  end

	if has_air_currents and (self._driver or not is_on_floor) then
		vel = sum_air_currents.apply_wind(vel)
	end

  local v = self.object:get_velocity()
	local slowdown = 0.983
	if forward == 0 then
		slowdown = 0.97
	end
  v.x = v.x * slowdown
  v.z = v.z * slowdown
	v.y = v.y * 0.97
	if is_on_floor and not self._driver then
		vel = vector.new(0, 0, 0)
		self.object:set_velocity(vel)
	else
	  self.object:set_velocity(v)
	end

	self.object:set_acceleration(vel)

	-- I hate trig
	local chimney_dist = -1.0
	local chimney_pos = {
		x=p.x + (chimney_dist * math.sin(-yaw+0.13)),
		y=p.y+0.9,
		z=p.z + (chimney_dist * math.cos(-yaw+0.13))}

	local spread = 0.06
	minetest.add_particle({
		pos = vector.offset(chimney_pos, math.random(-1, 1)*spread, 0, math.random(-1, 1)*spread),
		velocity = {x=0, y=math.random(0.2*100,0.7*100)/100, z=0},
		expirationtime = math.random(0.5, 2),
		size = math.random(0.1, 4),
		collisiondetection = false,
		vertical = false,
		texture = "sum_airship_smoke.png",
	})
end

-- Register one entity for all boat types
minetest.register_entity("sum_airship:boat", boat)

local boat_ids = { "main" }
local names = { S("Oak Airship") }
local images = { "oak" }

for b=1, #boat_ids do
	local itemstring = "sum_airship:"..boat_ids[b]

	local longdesc, usagehelp, tt_help, help, helpname
	help = false
	-- Only create one help entry for all boats
	if b == 1 then
		help = true
		longdesc = S("Airship are used to travel in the air and stuff.")
		usagehelp = S("thing")
		helpname = S("Airship")
	end
	tt_help = S("Air vehicle")

	minetest.register_craftitem(itemstring, {
		description = names[b],
		_tt_help = tt_help,
		_doc_items_create_entry = help,
		_doc_items_entry_name = helpname,
		_doc_items_longdesc = longdesc,
		_doc_items_usagehelp = usagehelp,
		inventory_image = "sum_airship_"..images[b].."_boat.png",
		liquids_pointable = true,
		groups = { boat = 1, transport = 1},
		stack_max = 1,
		on_place = function(itemstack, placer, pointed_thing)
			if pointed_thing.type ~= "node" then
				return itemstack
			end

			-- Call on_rightclick if the pointed node defines it
			local node = minetest.get_node(pointed_thing.under)
			if placer and not placer:get_player_control().sneak then
				if minetest.registered_nodes[node.name] and minetest.registered_nodes[node.name].on_rightclick then
					return minetest.registered_nodes[node.name].on_rightclick(pointed_thing.under, node, placer, itemstack) or itemstack
				end
			end

			local pos = table.copy(pointed_thing.under)
			local dir = vector.subtract(pointed_thing.above, pointed_thing.under)

			if math.abs(dir.x) > 0.9 or math.abs(dir.z) > 0.9 then
				pos = vector.add(pos, vector.multiply(dir, boat_side_offset))
			else
				pos = vector.add(pos, vector.multiply(dir, boat_y_offset_ground))
			end
			local boat = minetest.add_entity(pos, "sum_airship:boat")
			local texture = "sum_airship_texture_"..images[b].."_boat.png"
			boat:get_luaentity()._itemstring = itemstring
			boat:set_properties({textures = { texture, texture, texture, texture, texture }})
			boat:set_yaw(placer:get_look_horizontal())
			if not minetest.is_creative_enabled(placer:get_player_name()) then
				itemstack:take_item()
			end
			return itemstack
		end,
		_on_dispense = function(stack, pos, droppos, dropnode, dropdir)
			local below = {x=droppos.x, y=droppos.y-1, z=droppos.z}
			local belownode = minetest.get_node(below)
			-- Place boat as entity on or in water
			if minetest.get_item_group(dropnode.name, "water") ~= 0 or (dropnode.name == "air" and minetest.get_item_group(belownode.name, "water") ~= 0) then
				minetest.add_entity(droppos, "sum_airship:boat")
			else
				minetest.add_item(droppos, stack)
			end
		end,
	})

	local cvs = "sum_airship:canvas_roll"
	local hul = "sum_airship:hull"
	local sng = "default:paper"
	local iro = "default:steel_ingot"
	if minetest.get_modpath("mcl_mobitems")
	and minetest.get_modpath("mcl_core") then
		sng = "mcl_mobitems:string"
		iro = "mcl_core:iron_ingot"
	end
	minetest.register_craft({
		output = itemstring,
		recipe = {
			{cvs, cvs, cvs},
			{sng, iro, sng},
			{sng, hul, sng},
		},
	})
end

minetest.register_craft({
	type = "fuel",
	recipe = "group:boat",
	burntime = 20,
})

if minetest.get_modpath("doc_identifier") and doc.sub.identifier then
	doc.sub.identifier.register_object("sum_airship:boat", "craftitems", "sum_airship:boat")
end
