local load_time_start = minetest.get_us_time()

local grav_acc = tonumber(minetest.setting_get("movement_gravity")) or 9.81

-- needs to work in unloaded chunks
local function get_node_hard(pos)
	local node = minetest.get_node_or_nil(pos)
	if not node then
		minetest.get_voxel_manip():read_from_map(pos, pos)
		node = minetest.get_node(pos)
	end
	return node
end

-- tests if the node is walkable
local solids = {}
local function is_walkable(name)
	if solids[name] ~= nil then
		return solids[name]
	end
	local solid = minetest.registered_nodes[name]
	if not solid then
		solids[name] = true
		return true
	end
	solid = solid.walkable ~= false
	solids[name] = solid
	return solid
end

-- tests if there's a carrier and free space
local function can_slide(pos)
	local node = get_node_hard(pos)
	if node.name ~= "slidebail:carrier"
	or is_walkable(get_node_hard({x=pos.x, y=pos.y-1, z=pos.z}).name)
	or is_walkable(get_node_hard({x=pos.x, y=pos.y-2, z=pos.z}).name) then
		return false
	end
	return true
end

local obrt2 = 2^-0.5 -- works faster than 1/sqrt(2)
-- the entity used for sliding
minetest.register_entity("slidebail:entity", {
	collisionbox = {0,0,0,0,0,0},
	textures = {
		"slidebail_ent.png", "slidebail_ent.png", "slidebail_ent.png",
		"slidebail_ent.png", "slidebail_ent.png", "slidebail_ent.png"
	},
	visual = "cube",
	visual_size = {x=0.3, y=0.5},
	makes_footstep_sound = true,

	passed = 0,
	on_step = function(self)
		-- abort if sth is wrong with the object
		if not self.startpos
		or not self.dir
		or not self.pname then
			minetest.log("info", "[slidebail] object isn't valid, removing it…")
			self.object:remove()
			return
		end

		local startpos = self.startpos
		local pos = self.object:getpos()
		local xcoord = next(self.dir)

		local passing = math.abs(math.floor(pos[xcoord]+0.5) - startpos[xcoord])

		-- abort if the player doesn't exist
		local player = minetest.get_player_by_name(self.pname)
		if not player then
			minetest.log("error", "[slidebail] missing player")
			self.object:remove()
			return
		end

		local xvalue = self.dir[xcoord]

		-- do sth if it moved to the next carrier
		if passing ~= self.passed then
			-- abort if the object is where it shouldn't be
			if math.abs(math.floor(pos.y - startpos.y + 0.5)) ~= passing then
				minetest.log("error", "[slidebail] unexpected object position")
				self.object:remove()
				return
			end

			-- stop if sliding isn't longer possible
			local lp = vector.new(startpos)
			for i = self.passed, passing do
				lp[xcoord] = startpos[xcoord] + i * xvalue
				lp.y = startpos.y - i
				if not can_slide(lp) then
					lp[xcoord] = lp[xcoord] - xvalue
					self.object:remove()

					player:set_eye_offset({x=0,y=0,z=0}, {x=0,y=0,z=0})
					minetest.after(0.2, function(player, pos)
						player:moveto(pos)
					end, player, lp)

					minetest.sound_play("slidebail_set", {pos = lp})

					return
				end
			end

			minetest.sound_play("slidebail", {pos = pos})

			self.passed = passing
		end

		-- update acceleration
		local accdir = {x=0, y=-obrt2, z=0}
		accdir[xcoord] = xvalue * obrt2
		self.object:setacceleration(
			vector.multiply(
				accdir,
				grav_acc
					- self.object:getvelocity()[xcoord]
						* xvalue
						* 50
						* math.abs(0.25 + player:get_look_pitch() / math.pi)
			)
		)
	end,
	-- do not store object
	on_serialize = function(self)
		self.object:remove()
	end,
})

-- returns information about the direction for the slidebail
local function get_carrier_dir(par2)
	par2 = par2 % 4

	if par2 == 0 then
		return {z=1}, math.pi * 0.5
	end
	if par2 == 1 then
		return {x=1}, 0
	end
	if par2 == 2 then
		return {z=-1}, math.pi * 1.5
	end
	if par2 == 3 then
		return {x=-1}, math.pi
	end
end

-- the item for the inventory
minetest.register_craftitem("slidebail:item", {
	description = "Slidebail",
	inventory_image = "slidebail.png",
	on_place = function(stack, player, pt)
		if not stack
		or not player
		or not pt then
			return
		end

		local pos = pt.under
		local carrier = minetest.get_node(pos)

		-- abort if the click didn't happen on a carrier
		if carrier.name ~= "slidebail:carrier" then
			return
		end

		-- abort if the player is already attached
		local attach = player:get_attach()
		if attach then
			-- if using a slidebail, stop sliding
			local luaentity = attach:get_luaentity()
			if luaentity.name == "slidebail:entity" then
				local pos = attach:getpos()
				pos.y = pos.y-2
				attach:remove()
				minetest.after(0.2, function(player, pos)
					player:moveto(pos)
				end, player, pos)
				player:set_eye_offset({x=0,y=0,z=0}, {x=0,y=0,z=0})
				minetest.sound_play("slidebail_set", {pos = pos})
			end
			return
		end

		-- start sliding
		local pname = player:get_player_name()

		local dir,yaw = get_carrier_dir(carrier.param2)

		minetest.sound_play("slidebail_set", {pos = pos})

		--local spawnpos = vector.new(pos)
		--spawnpos.y = spawnpos.y - 0.5

		local obj = minetest.add_entity(pos, "slidebail:entity")
		obj:setyaw(yaw)

		local ent = obj:get_luaentity()
		ent.pname = pname
		ent.dir = dir
		ent.startpos = pos

		player:set_attach(obj, "",
			{x = 0, y = -2, z = 0}, vector.new())
		player:set_eye_offset({x=0,y=-30,z=0}, {x=0,y=-10,z=0})
		--[[default.player_attached[pname] = true
		minetest.after(0.2, function()
			default.player_set_animation(player, "sit" , 30)
		end)--]]
	end
})

-- the carrier used for leading the entity
minetest.register_node("slidebail:carrier", {
	description = "Slidebail Carrier",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {"slidebail_carrier.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, 0, -0.5, 0.5, 0.5, 0.5},
			{-0.5, -0.5, 0, 0.5, 0, 0.5},
		},
	},
	sounds = default.node_sound_stone_defaults({
		footstep = {name="slidebail", gain=0.25},
		place = {name="default_place_node"}
	}),
	groups = {cracky = 3}
})


local time = (minetest.get_us_time()-load_time_start)/1000000
local msg = "[slidebail] loaded after ca. "..time
if time > 0.01 then
	print(msg)
else
	minetest.log("info", msg)
end
