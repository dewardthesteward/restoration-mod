local mvec3_set = mvector3.set
local mvec3_set_z = mvector3.set_z
local mvec3_set_l = mvector3.set_length
local mvec3_sub = mvector3.subtract
local mvec3_add = mvector3.add
local mvec3_mul = mvector3.multiply
local mvec3_dot = mvector3.dot
local mvec3_cross = mvector3.cross
local mvec3_norm = mvector3.normalize
local mvec3_dir = mvector3.direction
local mvec3_rand_orth = mvector3.random_orthogonal
local mvec3_dis = mvector3.distance
local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()
local tmp_vec3 = Vector3()

function CopActionHurt:init(action_desc, common_data)
	self._common_data = common_data
	self._ext_movement = common_data.ext_movement
	self._ext_inventory = common_data.ext_inventory
	self._ext_anim = common_data.ext_anim
	self._body_part = action_desc.body_part
	self._unit = common_data.unit
	self._machine = common_data.machine
	self._attention = common_data.attention
	self._action_desc = action_desc
	local t = TimerManager:game():time()
	local tweak_table = self._unit:base()._tweak_table
	local is_civilian = CopDamage.is_civilian(tweak_table)
	local is_female = (self._machine:get_global("female") or 0) == 1
	local crouching = self._ext_anim.crouch or self._ext_anim.crouching or self._ext_anim.hurt and self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "crh") > 0
	local fire_variant = "fire"
	local redir_res = nil
	local action_type = action_desc.hurt_type

	if action_type == "knock_down" then
		action_type = "heavy_hurt"
	end

	if action_type == "fatal" then
		redir_res = self._ext_movement:play_redirect("fatal")

		if not redir_res then
			debug_pause("[CopActionHurt:init] fatal redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		managers.hud:set_mugshot_downed(self._unit:unit_data().mugshot_id)
	elseif action_desc.variant == "tase" then
		redir_res = self._ext_movement:play_redirect("tased")

		if not redir_res then
			debug_pause("[CopActionHurt:init] tased redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		managers.hud:set_mugshot_tased(self._unit:unit_data().mugshot_id)
	elseif action_type == "fire_hurt" then
		local weapon_unit = action_desc.weapon_unit
		local base_ext = alive(weapon_unit) and weapon_unit:base()

		if base_ext then
			local td = base_ext.weapon_tweak_data and base_ext:weapon_tweak_data() or base_ext.get_name_id and tweak_data.weapon[base_ext:get_name_id()]

			if td then
				fire_variant = td.fire_variant or fire_variant
			end
		end

		redir_res = self._ext_movement:play_redirect(tostring(fire_variant) .. "_hurt")

		if not redir_res then
			debug_pause("[CopActionHurt:init] " .. tostring(fire_variant) .. "_hurt redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		local dir_str = nil
		local fwd_dot = action_desc.direction_vec:dot(common_data.fwd)

		if fwd_dot < 0 then
			local hit_pos = action_desc.hit_pos
			local hit_vec = (hit_pos - common_data.pos):with_z(0):normalized()

			if mvector3.dot(hit_vec, common_data.right) > 0 then
				dir_str = "r"
			else
				dir_str = "l"
			end
		else
			dir_str = "bwd"
		end

		self._machine:set_parameter(redir_res, dir_str, 1)

		if self._unit:character_damage().set_last_time_unit_got_fire_damage then
			self._unit:character_damage():set_last_time_unit_got_fire_damage(t + 20)
		end
	elseif action_type == "taser_tased" then
		if self._unit:brain() and self._unit:brain()._current_logic_name ~= "intimidated" then
			local tase_data = tweak_data.tase_data[action_desc.variant] or tweak_data.tase_data.light

			if tase_data.duration then
				redir_res = self._ext_movement:play_redirect("explosion_tased")

				if not redir_res then
					debug_pause("[CopActionHurt:init] explosion_tased redirect failed in", self._machine:segment_state(Idstring("upper_body")))

					return
				end

				local nr_variants = self.explosion_tased_variants
				local variant = 1

				if nr_variants > 1 then
					variant = self:_pseudorandom(nr_variants)
				end

				self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
			else
				redir_res = self._ext_movement:play_redirect("taser")

				if not redir_res then
					debug_pause("[CopActionHurt:init] taser redirect failed in", self._machine:segment_state(Idstring("upper_body")))

					return
				end

				local nr_variants = self.tased_variants
				local variant = 1

				if nr_variants > 1 then
					variant = self:_pseudorandom(nr_variants)
				end

				self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
			end
		end
	elseif action_type == "light_hurt" then
		if not self._ext_anim.upper_body_active or self._ext_anim.upper_body_empty or self._ext_anim.recoil then
			redir_res = self._ext_movement:play_redirect(action_type)

			if not redir_res then
				debug_pause("[CopActionHurt:init] light_hurt redirect failed in", self._machine:segment_state(Idstring("upper_body")))

				return
			end

			local dir_str = nil
			local fwd_dot = action_desc.direction_vec:dot(common_data.fwd)

			if fwd_dot < 0 then
				local hit_pos = action_desc.hit_pos
				local hit_vec = (hit_pos - common_data.pos):with_z(0):normalized()

				if mvector3.dot(hit_vec, common_data.right) > 0 then
					dir_str = "r"
				else
					dir_str = "l"
				end
			else
				dir_str = "bwd"
			end

			self._machine:set_parameter(redir_res, dir_str, 1)

			local height_str = self._ext_movement:m_com().z < action_desc.hit_pos.z and "high" or "low"

			self._machine:set_parameter(redir_res, height_str, 1)
		end

		self._expired = true

		return true
	elseif action_type == "hurt_sick" then
		local ecm_hurts_table = self._common_data.char_tweak.ecm_hurts

		if not ecm_hurts_table or not next(ecm_hurts_table) then
			debug_pause_unit(self._unit, "[CopActionHurt:init] Unit missing ecm_hurts in Character Tweak Data", self._unit)

			return
		end

		local sick_variants = {}

		for i, d in pairs(ecm_hurts_table) do
			table.insert(sick_variants, i)
		end

		local variant = #sick_variants == 1 and sick_variants[1] or sick_variants[self:_pseudorandom(#sick_variants)]
		redir_res = self._ext_movement:play_redirect("hurt_sick_" .. tostring(variant))

		if not redir_res then
			debug_pause("[CopActionHurt:init] hurt_sick_" .. tostring(variant) .. " redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		local duration = ecm_hurts_table[variant]
		self._sick_time = t + duration
	elseif action_type == "poison_hurt" then
		redir_res = self._ext_movement:play_redirect("hurt_poison")

		if not redir_res then
			debug_pause("[CopActionHurt:init] hurt_poison redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end
	elseif action_type == "bleedout" then
		redir_res = self._ext_movement:play_redirect("bleedout")

		if not redir_res then
			debug_pause("[CopActionHurt:init] bleedout redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end
	elseif action_type == "death" and action_desc.variant == "fire" then
		local variant = 1
		local weapon_unit = action_desc.weapon_unit
		local base_ext = alive(weapon_unit) and weapon_unit:base()

		if base_ext then
			local td = base_ext.weapon_tweak_data and base_ext:weapon_tweak_data() or base_ext.get_name_id and tweak_data.weapon[base_ext:get_name_id()]

			if td then
				fire_variant = td.fire_variant or fire_variant
			end
		end

		if self._ext_anim.ragdoll and not self._ext_anim.hurt_fire or self._ext_movement:died_on_rope() then
			variant = 0

			self:force_ragdoll()
		else
			local variant_count = CopActionHurt.fire_death_anim_variants[fire_variant] or 5

			if variant_count > 1 then
				variant = self:_pseudorandom(variant_count)
			end

			self:_prepare_ragdoll()

			redir_res = self._ext_movement:play_redirect("death_" .. fire_variant)

			if not redir_res then
				debug_pause("[CopActionHurt:init] death_fire redirect failed in", self._machine:segment_state(Idstring("base")))

				return
			end

			for i = 1, variant_count do
				local state_value = 0

				if i == variant then
					state_value = 1
				end

				self._machine:set_parameter(redir_res, "var" .. tostring(i), state_value)
			end
		end

		self:_start_enemy_fire_effect_on_death(variant, fire_variant)
	elseif action_type == "death" and (action_desc.variant == "poison" or action_desc.variant == "bleed" or action_desc.variant == "dot") then
		if self._ext_anim.run or self._ext_anim.sprint or self._ext_anim.ragdoll or action_desc.variant == "bleed" then
			self:force_ragdoll()
		else
			self:_prepare_ragdoll()

			redir_res = self._ext_movement:play_redirect("death_poison")

			if not redir_res then
				debug_pause("[CopActionHurt:init] death_poison redirect failed in", self._machine:segment_state(Idstring("base")))

				return
			end

			local variant = CopActionHurt.forced_death_var or self.poison_death_anim_variants[is_female and "female" or "male"] or 1

			if not CopActionHurt.forced_death_var and variant > 1 then
				variant = self:_pseudorandom(variant)
			end

			self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
		end
	elseif action_type == "death" and not crouching and (self._ext_anim.run or self._ext_anim.sprint) and self._ext_anim.move_fwd and not common_data.char_tweak.no_run_death_anim then
		self:_prepare_ragdoll()

		redir_res = self._ext_movement:play_redirect("death_run")

		if not redir_res then
			debug_pause("[CopActionHurt:init] death_run redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		local variant = self.running_death_anim_variants[is_female and "female" or "male"] or 1

		if variant > 1 then
			variant = self:_pseudorandom(variant)
		end

		self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
	elseif action_type == "death" and (self._ext_anim.run or self._ext_anim.sprint or self._ext_anim.ragdoll) and self:_start_ragdoll() then
		self.update = self._upd_ragdolled
	elseif action_type == "heavy_hurt" and not crouching and (self._ext_anim.run or self._ext_anim.sprint) and self._ext_anim.move_fwd then
		redir_res = self._ext_movement:play_redirect("heavy_hurt_run")

		if not redir_res then
			debug_pause("[CopActionHurt:init] heavy_hurt_run redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		local variant = self.running_hurt_anim_variants.fwd or 1

		if variant > 1 then
			variant = self:_pseudorandom(variant)
		end

		self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
	elseif action_type == "shield_knock" then
		redir_res = self._ext_movement:play_redirect("shield_knock")

		if not redir_res then
			debug_pause("[CopActionHurt:init] shield_knock redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		local variant = 1
		local variant_count = CopActionHurt.shield_knock_variants or 5

		if variant_count > 1 then
			variant = self:_pseudorandom(variant_count)
		end

		self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
	else
		local variant, height, old_variant, old_info = nil

		if (action_type == "hurt" or action_type == "heavy_hurt") and self._ext_anim.hurt then
			for i = 1, self.hurt_anim_variants_highest_num do
				if self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "var" .. i) then
					old_variant = i

					break
				end
			end

			if old_variant ~= nil then
				old_info = {
					fwd = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "fwd"),
					bwd = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "bwd"),
					l = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "l"),
					r = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "r"),
					high = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "high"),
					low = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "low"),
					crh = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "crh"),
					mod = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "mod"),
					hvy = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "hvy")
				}
			end
		end

		local redirect = action_type

		if redirect == "concussion" then
			redirect = "concussion_stun"
		end

		if redirect then
			redir_res = self._ext_movement:play_redirect(redirect)
		else
			Application:stack_dump_error("There's no redirect in CopActionHurt!")
		end

		if not redir_res then
			debug_pause_unit(self._unit, "[CopActionHurt:init]", redirect, "redirect failed in", self._machine:segment_state(Idstring("base")), self._unit)

			return
		end

		if action_desc.variant ~= "bleeding" then
			local nr_variants = self._ext_anim.base_nr_variants
			local death_type = nil

			if nr_variants then
				variant = self:_pseudorandom(nr_variants)
			else
				local fwd_dot = action_desc.direction_vec:dot(common_data.fwd)
				local right_dot = action_desc.direction_vec:dot(common_data.right)
				local dir_str = nil

				if math.abs(right_dot) < math.abs(fwd_dot) then
					if fwd_dot < 0 then
						dir_str = "fwd"
					else
						dir_str = "bwd"
					end
				elseif right_dot > 0 then
					dir_str = "l"
				else
					dir_str = "r"
				end

				self._machine:set_parameter(redir_res, dir_str, 1)

				local hit_z = action_desc.hit_pos.z
				height = self._ext_movement:m_com().z < hit_z and "high" or "low"

				if action_type == "death" then
					if is_civilian then
						death_type = "normal"
					else
						death_type = action_desc.death_type
					end

					if is_female then
						variant = self.death_anim_fe_variants[death_type][crouching and "crouching" or "not_crouching"][dir_str][height]
					else
						variant = self.death_anim_variants[death_type][crouching and "crouching" or "not_crouching"][dir_str][height]
					end

					if variant > 1 then
						variant = self:_pseudorandom(variant)
					end

					self:_prepare_ragdoll()
				elseif action_type ~= "counter_tased" and action_type ~= "taser_tased" then
					if old_variant and (old_info[dir_str] == 1 and old_info[height] == 1 and old_info.mod == 1 and action_type == "hurt" or old_info.hvy == 1 and action_type == "heavy_hurt") then
						variant = old_variant
					end

					if not variant then
						variant = self.hurt_anim_variants[action_type][crouching and "crouching" or "not_crouching"][dir_str][height]

						if variant > 1 then
							variant = self:_pseudorandom(variant)
						end
					end
				end
			end

			variant = variant or 1

			if variant then
				self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
			end

			if height then
				self._machine:set_parameter(redir_res, height, 1)
			end

			if crouching then
				self._machine:set_parameter(redir_res, "crh", 1)
			end

			if action_type == "hurt" then
				self._machine:set_parameter(redir_res, "mod", 1)
			elseif action_type == "heavy_hurt" then
				self._machine:set_parameter(redir_res, "hvy", 1)
			elseif action_type == "death" and (death_type or action_desc.death_type) == "heavy" and not is_civilian then
				self._machine:set_parameter(redir_res, "heavy", 1)
			elseif action_type == "expl_hurt" then
				self._machine:set_parameter(redir_res, "expl", 1)
			end
		end
	end

	if self._ext_anim.upper_body_active and not self._ext_anim.upper_body_empty and not self._ragdolled then
		self._ext_movement:play_redirect("up_idle")
	end

	self._last_vel_z = 0
	self._hurt_type = action_type
	self._variant = action_desc.variant
	self._body_part = action_desc.body_part

	if action_type == "bleedout" then
		self.update = self._upd_bleedout
		self._shoot_t = t + 1

		if Network:is_server() then
			self._ext_inventory:equip_selection(1, true)
		end

		local weapon_unit = self._ext_inventory:equipped_unit()
		self._weapon_base = weapon_unit:base()
		local weap_tweak = weapon_unit:base():weapon_tweak_data()
		local weapon_usage_tweak = common_data.char_tweak.weapon[weap_tweak.usage]
		self._weapon_unit = weapon_unit
		self._weap_tweak = weap_tweak
		self._w_usage_tweak = weapon_usage_tweak
		self._reload_speed = weapon_usage_tweak.RELOAD_SPEED
		self._spread = weapon_usage_tweak.spread
		self._falloff = weapon_usage_tweak.FALLOFF
		self._head_modifier_name = Idstring("look_head")
		self._arm_modifier_name = Idstring("aim_r_arm")
		self._head_modifier = self._machine:get_modifier(self._head_modifier_name)
		self._arm_modifier = self._machine:get_modifier(self._arm_modifier_name)
		self._aim_vec = mvector3.copy(common_data.fwd)
		self._anim = redir_res

		if not self._shoot_history then
			self._shoot_history = {
				focus_error_roll = self:_pseudorandom(360),
				focus_start_t = t,
				focus_delay = weapon_usage_tweak.focus_delay,
				m_last_pos = common_data.pos + common_data.fwd * 500
			}
		end
	elseif self._sick_time then
		self.update = self._upd_sick
	elseif action_desc.variant == "tase" then
		-- Nothing
	elseif self._ragdolled then
		-- Nothing
	elseif self._unit:anim_data().skip_force_to_graph then
		self.update = self._upd_empty
	else
		self.update = self._upd_hurt
	end

	local shoot_chance = nil

	if self._ext_inventory and not self._weapon_dropped and common_data.char_tweak.shooting_death and not self._ext_movement:cool() and t - self._ext_movement:not_cool_t() > 3 then
		local weapon_unit = self._ext_inventory:equipped_unit()

		if weapon_unit then
			if action_type == "counter_tased" or action_type == "taser_tased" then
				weapon_unit:base():on_reload()

				shoot_chance = 1
			elseif action_type == "death" or action_type == "hurt" or action_type == "heavy_hurt" then
				shoot_chance = 0.1
			end
		end
	end

	if shoot_chance then
		local equipped_weapon = self._ext_inventory:equipped_unit()
		local rand = self:_pseudorandom()

		if equipped_weapon and (not equipped_weapon:base().clip_empty or not equipped_weapon:base():clip_empty()) and rand <= shoot_chance then
			self._weapon_unit = equipped_weapon

			self._unit:movement():set_friendly_fire(true)

			self._friendly_fire = true

			if equipped_weapon:base():weapon_tweak_data().auto then
				equipped_weapon:base():start_autofire()

				self._shooting_hurt = true
			else
				self._delayed_shooting_hurt_clbk_id = "shooting_hurt" .. tostring(self._unit:key())

				managers.enemy:add_delayed_clbk(self._delayed_shooting_hurt_clbk_id, callback(self, self, "clbk_shooting_hurt"), TimerManager:game():time() + math.lerp(0.2, 0.4, self:_pseudorandom()))
			end
		end
	end

	if not self._unit:base().nick_name then
		if action_desc.variant == "fire" then
			local base_ext = self._unit:base()

			if action_desc.hurt_type == "fire_hurt" then
				local sound_data = CopActionHurt.fire_hurt_sounds[fire_variant] or CopActionHurt.fire_hurt_sounds.fire

				if sound_data.skip_prefix or not base_ext or not base_ext.has_tag or not base_ext:has_any_tag({
					"spooc",
					"tank",
					"shield"
				}) then
					self._unit:sound():say(sound_data.sound_name, nil, sound_data.skip_prefix)
				end
			elseif action_desc.hurt_type == "death" then
				local sound_data = CopActionHurt.fire_death_sounds[fire_variant] or CopActionHurt.fire_death_sounds.fire

				if not sound_data.skip_prefix and base_ext and base_ext.has_tag and base_ext:has_tag("tank") then
					self._unit:sound():say("x02a_any_3p")
				else
					self._unit:sound():say(sound_data.sound_name, nil, sound_data.skip_prefix)
				end
			end
		elseif action_type == "death" then
			self._unit:sound():say("x02a_any_3p")
		elseif action_type == "counter_tased" or action_type == "taser_tased" then
			self._unit:sound():say("tasered")
		else
			self._unit:sound():say("x01a_any_3p")
		end

		if Network:is_server() then
			local radius, filter_name = nil
			local default_radius = managers.groupai:state():whisper_mode() and tweak_data.upgrades.cop_hurt_alert_radius_whisper or tweak_data.upgrades.cop_hurt_alert_radius

			if action_desc.attacker_unit and alive(action_desc.attacker_unit) and action_desc.attacker_unit:base().upgrade_value then
				radius = action_desc.attacker_unit:base():upgrade_value("player", "silent_kill") or default_radius
			elseif action_desc.attacker_unit and alive(action_desc.attacker_unit) and action_desc.attacker_unit:base().is_local_player then
				radius = managers.player:upgrade_value("player", "silent_kill", default_radius)
			end

			local new_alert = {
				"vo_distress",
				common_data.ext_movement:m_head_pos(),
				radius or default_radius,
				self._unit:brain():SO_access(),
				self._unit
			}

			managers.groupai:state():propagate_alert(new_alert)
		end
	end

	if action_type == "death" or action_type == "bleedout" or action_desc.variant == "tased" or action_type == "fatal" then
		self._floor_normal = self:_get_floor_normal(common_data.pos, common_data.fwd, common_data.right)
	end

	CopActionAct._create_blocks_table(self, action_desc.blocks)
	self._ext_movement:enable_update()

	if (self._body_part == 1 or self._body_part == 2) and Network:is_server() then
		local stand_rsrv = self._unit:brain():get_pos_rsrv("stand")

		if not stand_rsrv or mvector3.distance_sq(stand_rsrv.position, common_data.pos) > 400 then
			self._unit:brain():add_pos_rsrv("stand", {
				radius = 30,
				position = mvector3.copy(common_data.pos)
			})
		end
	end

	if self:is_network_allowed(action_desc) then
		local params = {
			CopActionHurt.hurt_type_to_idx(action_desc.hurt_type),
			action_desc.body_part,
			CopActionHurt.death_type_to_idx(action_desc.death_type),
			CopActionHurt.type_to_idx(action_desc.type),
			CopActionHurt.variant_to_idx(action_desc.variant),
			action_desc.direction_vec or Vector3(),
			action_desc.hit_pos or Vector3()
		}

		self._common_data.ext_network:send("action_hurt_start", unpack(params))
	end

	return true
end

-- Remove position reservations on death
-- Improve reaction to ECM feedback by playing specific voicelines and pain sounds
if Network:is_server() then
	Hooks:PostHook(CopActionHurt, "init", "sh_init", function (self)
		if self._hurt_type == "death" then
			self._unit:brain():rem_all_pos_rsrv()
		elseif self._hurt_type == "hurt_sick" then
			local t = TimerManager:game():time()
			self._say_sick_t = t + math.rand((self._sick_time - t) * 0.5)
			self._say_hurt_t = t + math.rand(2, 5)
		end
	end)
end

-- Make sick update finish their hurt exit anims before expiring
Hooks:OverrideFunction(CopActionHurt, "_upd_sick", function (self, t)
	if self._sick_time then
		if self._say_sick_t and t > self._say_sick_t then
			managers.groupai:state():chk_say_enemy_chatter(self._unit, self._common_data.pos, "jammer")
			self._say_sick_t = nil
		elseif self._say_hurt_t and t > self._say_hurt_t and not self._unit:sound():speaking(t) then
			self._unit:sound():say("x01a_any_3p", true)
			self._say_hurt_t = t + math.rand(2, 5)
		end

		if t > self._sick_time then
			self._ext_movement:play_redirect("idle")
			self._sick_time = nil
		end
	elseif not self._ext_anim.hurt then
		self._expired = true
	end
end)

-- Prevent hurt and knockdown animations stacking, once one plays it needs to finish for another one to trigger
CopActionHurt.hurt_blocks = {
	heavy_hurt = true,
	hurt = true,
	hurt_sick = true,
	knock_down = true,
	poison_hurt = true,
	shield_knock = true,
	stagger = true
}

Hooks:OverrideFunction(CopActionHurt, "chk_block", function (self, action_type, t)
	if self._hurt_type == "death" then
		return true
	elseif self.hurt_blocks[action_type] and not self._ext_anim.hurt_exit then
		return true
	elseif action_type == "turn" then
		return true
	elseif action_type == "death" then
		return false
	end

	return CopActionAct.chk_block(self, action_type, t)
end)

-- Fix pseudo random number generator having very low entropy
function CopActionHurt:_pseudorandom(a, b)
	if CopActionHurt._host_peer == nil then
		CopActionHurt._host_peer = Network:is_client() and managers.network:session():peer(1) or false
	end

	local ht = managers.game_play_central:get_heist_timer()
	if CopActionHurt._host_peer then
		ht = ht + Network:qos(CopActionHurt._host_peer:rpc()).ping / 1000
	end

	-- Switch seed 4 times a second, switching too much would make the PRNG depend on client ping too much
	ht = math.round(ht * 4)

	-- Adapted from https://stackoverflow.com/a/35377265
	ht = ht * 3266489917 + 374761393;
	ht = bit.bor(bit.lshift(ht, 17), bit.rshift(ht, 15))
	ht = ht + self._unit:id() * 3266489917;
	ht = ht * 668265263;
	ht = bit.bxor(ht, bit.rshift(ht, 15)) * 2246822519;
	ht = bit.bxor(ht, bit.rshift(ht, 13)) * 3266489917;
	ht = bit.bxor(ht, bit.rshift(ht, 16));

	local val = bit.band(ht, 0xffffff) / 0x1000000
	if a and b then
		return math.floor(math.lerp(a, b + 1, val))
	elseif a then
		return math.floor(math.lerp(1, a + 1, val))
	else
		return val
	end
end