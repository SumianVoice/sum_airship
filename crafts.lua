local S = minetest.get_translator(minetest.get_current_modname())


minetest.register_craftitem("sum_airship:canvas_roll", {
	description = S("Canvas Roll"),
	_doc_items_longdesc = S("Used in crafting airships."),
	inventory_image = "sum_airship_canvas.png",
	stack_max = 64,
	groups = { craftitem = 1 },
})
minetest.register_craftitem("sum_airship:hull", {
	description = S("Airship Hull"),
	_doc_items_longdesc = S("Used in crafting airships."),
	inventory_image = "sum_airship_hull.png",
	stack_max = 1,
	groups = { craftitem = 1 },
})
if true then
	local w = "default:paper"
	local b = "group:wood"
	local m = "default:steel_ingot"
	if minetest.get_modpath("mcl_boats")
	and minetest.get_modpath("mcl_wool")
	and minetest.get_modpath("mcl_core") then
		w = "mcl_wool:white"
		b = "mcl_boats:boat"
		m = "mcl_core:iron_ingot"
	end
	minetest.register_craft({
		output = "sum_airship:canvas_roll",
		recipe = {
			{w, w, w},
			{w, w, w},
			{w, w, w},
		},
	})
	minetest.register_craft({
		output = "sum_airship:hull",
		recipe = {
			{b, b, b},
			{m, m, m},
		},
	})
end