local load_time_start = os.clock()


local friction_strength = 0.1
local grav_acc = 9.81

-- needs to work in unloaded chunks
local function get_node_hard(pos)
	local node = minetest.get_node_or_nil(pos)
	if not node then
		minetest.get_voxel_manip():read_from_map(pos, pos)
		node = minetest.get_node(pos)
	end
	return node
end

-- tests if there's a carrier and free space
local function can_slide(pos)
	local node = get_node_hard(pos)
	if node.name ~= "slidebail:carrier" then
		return false
	end
	-- todo: test walkable, not air here
	if get_node_hard({x=pos.x, y=pos.y-1, z=pos.z}).name ~= "air"
	or get_node_hard({x=pos.x, y=pos.y-2, z=pos.z}).name ~= "air" then
		return false
	end
	return true
end

local obrt2 = 1/math.sqrt(2)
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

		local x = math.floor(pos[xcoord]+0.5)
		local passing = math.abs(x - startpos[xcoord])

		local player = minetest.get_player_by_name(self.pname)
		if not player then
			minetest.log("error", "[slidebail] missing player")
			self.object:remove()
			return
		end

		local xvalue = self.dir[xcoord]
		if passing ~= self.passed then
			local y = startpos.y - passing

			if math.floor(pos.y - y + 0.5) ~= 0 then
				minetest.log("error", "[slidebail] unexpected object position")
				self.object:remove()
				return
			end

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

					return
				end
			end

			minetest.sound_play("slidebail", {pos = pos})

			self.passed = passing
		end

		local accdir = {x=0, y=-obrt2, z=0}
		accdir[xcoord] = xvalue * obrt2

		-- braking just testing
		local braking = friction_strength / math.max(
			0.5 - 2 * player:get_look_pitch() / math.pi,
			0.01 * friction_strength
		)
		--minetest.chat_send_all(braking)

		self.object:setacceleration(
			vector.multiply(
				accdir,
				grav_acc - self.object:getvelocity()[xcoord] * xvalue * braking
			)
		)
	end,
	on_serialize = function(self)
		self.object:remove()
	end,
})

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
		--[[
		if pos.y ~= pt.above.y + 1 then
			return
		end--]]

		local carrier = minetest.get_node(pos)
		if carrier.name ~= "slidebail:carrier" then
			return
		end

		local attach = player:get_attach()
		if attach then
			local luaentity = attach:get_luaentity()
			if luaentity.name == "slidebail:entity" then
				local pos = attach:getpos()
				pos.y = pos.y-2
				attach:remove()
				minetest.after(0.2, function(player, pos)
					player:moveto(pos)
				end, player, pos)
				player:set_eye_offset({x=0,y=0,z=0}, {x=0,y=0,z=0})
			end
			return
		end
		local pname = player:get_player_name()

		local dir,yaw = get_carrier_dir(carrier.param2)

		local spawnpos = vector.new(pos)
		--spawnpos.y = spawnpos.y - 0.5

		local obj = minetest.add_entity(spawnpos, "slidebail:entity")
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


local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "[slidebail] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
