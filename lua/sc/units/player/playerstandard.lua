local norecoil_blacklist = { --From Zdann
	--Special
	["flamethrower_mk2"] = true,
	["system"] = true,
	["china"] = true,
	
	--Shotguns
	["r870_shotgun"] = true,
	["ksg"] = true,
	["boot"] = true,
	["m37"] = true,
	["m1897"] = true,
	["m590"] = true,
	
	--Sniper Rifles
	["winchester1874"] = true,
	["mosin"] = true,
	["m95"] = true,
	["r93"] = true,
	["msr"] = true,
	["model70"] = true,
	["r700"] = true,
	["sbl"] = true,
	["desertfox"] = true,
	["scout"] = true,
	
	--Pistols
	["peacemaker"] = true,
	["model3"] = true
}

local original_init = PlayerStandard.init
function PlayerStandard:init(unit)
	original_init(self, unit)

	if Global.game_settings and Global.game_settings.one_down then
		self._slotmask_bullet_impact_targets = self._slotmask_bullet_impact_targets + 3
	else
		self._slotmask_bullet_impact_targets = managers.mutators:modify_value("PlayerStandard:init:melee_slot_mask", self._slotmask_bullet_impact_targets)
		self._slotmask_bullet_impact_targets = managers.modifiers:modify_value("PlayerStandard:init:melee_slot_mask", self._slotmask_bullet_impact_targets)
	end
end

--Allows night vision to be used with any mask.
function PlayerStandard:set_night_vision_state(state)
	local mask_id = managers.blackmarket:equipped_mask().mask_id
	local mask_tweak = tweak_data.blackmarket.masks[mask_id]
	local night_vision = mask_tweak.night_vision 

	--If mask doesn't have night vision, it does.
	if not night_vision then
		night_vision = {
			effect = "color_night_vision",
			light = not _G.IS_VR and 0.3 or 0.1
		}
	end

	--This conditional is hilarious in vanilla btw.
	if self._state_data.night_vision_active == state then
		return
	end

	local ambient_color_key = CoreEnvironmentFeeder.PostAmbientColorFeeder.DATA_PATH_KEY
	--Use a proper fallback env instead of whatever vanilla does if there's an issue.
	local level_id = Global.game_settings.level_id
	local env_setting = level_id and tweak_data.levels[level_id].env_params and tweak_data.levels[level_id].env_params.color_grading
	local level_check = env_setting or managers.user:get_setting("video_color_grading")
	local effect = state and night_vision.effect or level_check

	if state then
		local function light_modifier(handler, feeder)
			local base_light = feeder._target and mvector3.copy(feeder._target) or Vector3()
			local light = night_vision.light

			return base_light + Vector3(light, light, light)
		end

		managers.viewport:create_global_environment_modifier(ambient_color_key, true, light_modifier)
	else
		managers.viewport:destroy_global_environment_modifier(ambient_color_key)
	end

	self._unit:sound():play(state and "night_vision_on" or "night_vision_off", nil, false)
	managers.environment_controller:set_default_color_grading(effect, state)
	managers.environment_controller:refresh_render_settings()

	self._state_data.night_vision_active = state
end	

--Stops disabled cameras from being markable.
local add_unit_to_char_table_old = PlayerStandard._add_unit_to_char_table
function PlayerStandard:_add_unit_to_char_table(char_table, unit, unit_type, ...)
	if unit_type ~= 3 or unit:base()._detection_delay or (Network:is_client() and unit:base().cam_disabled ~= true) then
		add_unit_to_char_table_old(self, char_table, unit, unit_type, ...)
	end
end

function PlayerStandard:push(vel, override_vel, override_vel_mult, allow_sprint)
	local override_vel_mult = override_vel_mult or 0
	if self._unit:mover() then
		if override_vel then
			--Scuffed as fuck way of doing this probably but I couldn't find another way to modify only x and y
			self._last_velocity_xy = self._last_velocity_xy:with_x(self._last_velocity_xy.x * override_vel_mult):with_y(self._last_velocity_xy.y * override_vel_mult)
		end
		self._last_velocity_xy = self._last_velocity_xy + vel

		self._unit:mover():set_velocity(self._last_velocity_xy)
	end
	if not allow_sprint then
		self:_interupt_action_running(managers.player:player_timer():time())
	end
end

function PlayerStandard:_activate_mover(mover, velocity)
	self._unit:activate_mover(mover, velocity)
	
	if not self._original_damping_standard then
		self._original_damping_standard = self._unit:mover():damping() --PLEASE DO NOT CHANGE THIS!!! WILL PROBABLY CAUSE WEIRD BEHAVIOR IN LADDERS!!!
	end

	if self._state_data.on_ladder then
		self._unit:mover():set_gravity(Vector3(0, 0, 0))
		self._unit:mover():set_damping(self._original_damping_standard)
	else
		self._unit:mover():set_gravity(Vector3(0, 0, -982)) --sets the actual gravity, you can set this to funny values if you want moon-jumping or something
		self._unit:mover():set_damping(self._tweak_data.gravity / self._tweak_data.terminal_velocity) --sets how fast the player accelerates downwards in the air, i have no clue what the value for this actually represents since its something like 0.14-ish.
	end

	if self._is_jumping then
		self._unit:mover():jump()
		self._unit:mover():set_velocity(velocity)
	end
end

function PlayerStandard:_start_action_ladder(t, ladder_unit)
	self._state_data.on_ladder = true

	self:_interupt_action_running(t)
	self._unit:mover():set_velocity(Vector3())
	self._unit:mover():set_gravity(Vector3(0, 0, 0))
	self._unit:mover():set_damping(self._original_damping_standard)
	self._unit:mover():jump()
	self._unit:movement():on_enter_ladder(ladder_unit)
end

function PlayerStandard:_end_action_ladder(t, input)
	if not self._state_data.on_ladder then
		return
	end

	self._state_data.on_ladder = false

	if self._unit:mover() then
		self._unit:mover():set_gravity(Vector3(0, 0, -982))
		self._unit:mover():set_damping(self._tweak_data.gravity / self._tweak_data.terminal_velocity)
	end

	self._unit:movement():on_exit_ladder()
end	

--These functions are for Breacher top off skill, allows reloading, shooting, and aiming while still interacting
function PlayerStandard:_start_action_interact(t, input, timer, interact_object)
	if not managers.player:has_category_upgrade("player", "no_interrupt_interaction") then
		self:_interupt_action_reload(t)
		self:_interupt_action_steelsight(t)
		self:_interupt_action_running(t)
		self:_interupt_action_charging_weapon(t)
	end

	local final_timer = timer
	final_timer = managers.modifiers:modify_value("PlayerStandard:OnStartInteraction", final_timer, interact_object)
	self._interact_expire_t = final_timer
	local start_timer = 0
	self._interact_params = {
		object = interact_object,
		timer = final_timer,
		tweak_data = interact_object:interaction().tweak_data
	}

	--Here!
	if not managers.player:has_category_upgrade("player", "no_interrupt_interaction") then
		self:_play_unequip_animation()
	end
	managers.hud:show_interaction_bar(start_timer, final_timer)
	managers.network:session():send_to_peers_synched("sync_teammate_progress", 1, true, self._interact_params.tweak_data, final_timer, false)
	self._unit:network():send("sync_interaction_anim", true, self._interact_params.tweak_data)
end

function PlayerStandard:_interupt_action_interact(t, input, complete)
	if self._interact_expire_t then
		self._interact_expire_t = nil

		if alive(self._interact_params.object) then
			self._interact_params.object:interaction():interact_interupt(self._unit, complete)
		end

		self._ext_camera:camera_unit():base():remove_limits()
		self._interaction:interupt_action_interact(self._unit)
		managers.network:session():send_to_peers_synched("sync_teammate_progress", 1, false, self._interact_params.tweak_data, 0, complete and true or false)

		self._interact_params = nil

		--Here!
		if not managers.player:has_category_upgrade("player", "no_interrupt_interaction") then
			self:_play_equip_animation()
		end
		managers.hud:hide_interaction_bar(complete)
		self._unit:network():send("sync_interaction_anim", false, "")
	end
end

function PlayerStandard:_start_action_ducking(t)
	--Here!
	if self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_on_zipline() then
		return
	end

	self:_interupt_action_running(t)

	self._state_data.ducking = true

	self:_stance_entered()
	self:_update_crosshair_offset()

	local velocity = self._unit:mover():velocity()

	self._unit:kill_mover()
	self:_activate_mover(PlayerStandard.MOVER_DUCK, velocity)
	self._ext_network:send("action_change_pose", 2, self._unit:position())
	self:_upd_attention()
	
	if AdvMov and PlayerStandard._check_slide then
		self:_check_slide()
	end
end

function PlayerStandard:_check_action_throw_projectile(t, input)
	local projectile_entry = managers.blackmarket:equipped_projectile()
	local projectile_tweak = tweak_data.blackmarket.projectiles[projectile_entry]

	if projectile_tweak.is_a_grenade then
		return self:_check_action_throw_grenade(t, input)
	elseif projectile_tweak.ability then
		return self:_check_action_use_ability(t, input)
	end

	if self._state_data.projectile_throw_wanted then
		if not self._state_data.projectile_throw_allowed_t then
			self._state_data.projectile_throw_wanted = nil

			self:_do_action_throw_projectile(t, input)
		end

		return
	end

	local action_wanted = input.btn_projectile_press or input.btn_projectile_release or self._state_data.projectile_idle_wanted

	if not action_wanted then
		return
	end

	if not managers.player:can_throw_grenade() then
		self._state_data.projectile_throw_wanted = nil
		self._state_data.projectile_idle_wanted = nil

		return
	end

	if input.btn_projectile_release then
		if self._state_data.throwing_projectile then
			if self._state_data.projectile_throw_allowed_t then
				self._state_data.projectile_throw_wanted = true

				return
			end

			self:_do_action_throw_projectile(t, input)
		end

		return
	end

	--Here!
	local action_forbidden = not PlayerBase.USE_GRENADES or not self:_projectile_repeat_allowed() or self:chk_action_forbidden("interact") or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:is_deploying() or self:_changing_weapon() or self:_is_meleeing() or self:_is_using_bipod()

	if action_forbidden then
		return
	end

	self:_start_action_throw_projectile(t, input)

	return true
end

function PlayerStandard:_check_action_throw_grenade(t, input)
	local action_wanted = input.btn_throw_grenade_press

	if not action_wanted then
		return
	end

	if not managers.player:can_throw_grenade() then
		return
	end

	--Here!
	local action_forbidden = not PlayerBase.USE_GRENADES or self:chk_action_forbidden("interact") or self._unit:base():stats_screen_visible() or self:_is_throwing_grenade() or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:is_deploying() or self:_changing_weapon() or self:_is_meleeing() or self:_is_using_bipod()

	if action_forbidden then
		return
	end

	self:_start_action_throw_grenade(t, input)

	return action_wanted
end

function PlayerStandard:_action_interact_forbidden()
	--Here!
	local action_forbidden = self:chk_action_forbidden("interact") or self._unit:base():stats_screen_visible() or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self._ext_movement:has_carry_restriction() or self:is_deploying() or self:_changing_weapon() or self:_is_throwing_projectile() or self:_is_meleeing() or self:_on_zipline()

	return action_forbidden
end

function PlayerStandard:_check_action_melee(t, input)
	if self._state_data.melee_attack_wanted then
		if not self._state_data.melee_attack_allowed_t then
			self._state_data.melee_attack_wanted = nil

			self:_do_action_melee(t, input)
		end

		return
	end

	local action_wanted = input.btn_melee_press or input.btn_melee_release or self._state_data.melee_charge_wanted

	if not action_wanted then
		return
	end

	if input.btn_melee_release then
		if self._state_data.meleeing then
			if self._state_data.melee_attack_allowed_t then
				self._state_data.melee_attack_wanted = true

				return
			end

			self:_do_action_melee(t, input)
		end
		
		self._state_data.chainsaw_t = nil

		return
	end

	--Here!
	local action_forbidden = not self:_melee_repeat_allowed() or self._use_item_expire_t or self:_changing_weapon() or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_is_throwing_projectile() or self:_is_using_bipod() or self:is_shooting_count() or self:_in_burst()

	if action_forbidden then
		return
	end

	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local instant = tweak_data.blackmarket.melee_weapons[melee_entry].instant

	self:_start_action_melee(t, input, instant)

	return true
end

function PlayerStandard:_check_action_reload(t, input)
	local new_action = nil
	local action_wanted = input.btn_reload_press

	if action_wanted then
		--Here!
		local action_forbidden = self:_is_reloading() or self:_changing_weapon() or self:_is_meleeing() or self._use_item_expire_t or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_is_throwing_projectile()
		action_forbidden = action_forbidden or self:is_shooting_count() or self:_in_burst()

		if not action_forbidden and self._equipped_unit and not self._equipped_unit:base():clip_full() then
			self:_start_action_reload_enter(t)

			new_action = true
		end
		if restoration.Options:GetValue("OTHER/WeaponHandling/SeparateBowADS") then
			if alive(self._equipped_unit) then
				local result = nil
				local weap_base = self._equipped_unit:base()
		
				if weap_base.manages_steelsight and weap_base:manages_steelsight() then
					if input.btn_reload_press and weap_base.steelsight_pressed then
						result = weap_base:steelsight_pressed()
					elseif input.btn_steelsight_release and weap_base.steelsight_released then
						result = weap_base:steelsight_released()
					end
				end
			end
		end
	end

	return new_action
end

function PlayerStandard:_check_use_item(t, input)
	local new_action = nil
	local action_wanted = input.btn_use_item_press

	--Here!
	if action_wanted then
		local action_forbidden = self._use_item_expire_t or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_changing_weapon() or self:_is_throwing_projectile() or self:_is_meleeing()

		if not action_forbidden and managers.player:can_use_selected_equipment(self._unit) then
			self:_start_action_use_item(t)

			new_action = true
		end
	end

	if input.btn_use_item_release then
		self:_interupt_action_use_item()
	end

	return new_action
end

function PlayerStandard:_check_change_weapon(t, input)
	local new_action = nil
	local action_wanted = input.btn_switch_weapon_press

	if action_wanted then
		local action_forbidden = self:_changing_weapon()
		action_forbidden = action_forbidden or self:_is_meleeing() or self._use_item_expire_t or self._change_item_expire_t
		--Here!
		action_forbidden = action_forbidden or self._unit:inventory():num_selections() == 1 or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_is_throwing_projectile() or self:_is_deploying_bipod()
		action_forbidden = action_forbidden or self:is_shooting_count() or self:_in_burst()

		if not action_forbidden then
			local data = {
				next = true
			}
			self._change_weapon_pressed_expire_t = t + 0.33

			self:_start_action_unequip_weapon(t, data)

			new_action = true

			managers.player:send_message(Message.OnSwitchWeapon)
		end
	end

	return new_action
end

function PlayerStandard:_check_action_equip(t, input)
	local new_action = nil
	local selection_wanted = input.btn_primary_choice

	if selection_wanted then
		local action_forbidden = self:chk_action_forbidden("equip")
		--Here!
		action_forbidden = action_forbidden or not self._ext_inventory:is_selection_available(selection_wanted) or self:_is_meleeing() or self._use_item_expire_t or self:_changing_weapon() or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_is_throwing_projectile() or self:_in_burst()

		if not action_forbidden then
			local new_action = not self._ext_inventory:is_equipped(selection_wanted)

			if new_action then
				self:_start_action_unequip_weapon(t, {
					selection_wanted = selection_wanted
				})
			end
		end
	end

	return new_action
end



function PlayerStandard:_check_action_jump(t, input)
	local new_action = nil
	local action_wanted = input.btn_jump_press

	if self._is_wallrunning and action_wanted then --_is_wallrunning will return nil without AdvMov, no need to check for its global
		self:_cancel_wallrun(t, "jump")
	elseif action_wanted then
		local action_forbidden = self._jump_t and t < self._jump_t + 0.55
		action_forbidden = action_forbidden or self._unit:base():stats_screen_visible() or self._state_data.in_air or self:_interacting() or self:_on_zipline() or self:_does_deploying_limit_movement() or self:_is_using_bipod()

		if not action_forbidden then
			if self._state_data.ducking and not AdvMov then --Advmov global check
				self:_interupt_action_ducking(t)
			else
				if self._state_data.on_ladder then
					self:_interupt_action_ladder(t)
				end

				local action_start_data = {}
				local jump_vel_z = tweak_data.player.movement_state.standard.movement.jump_velocity.z
				action_start_data.jump_vel_z = jump_vel_z

				if self._move_dir then
					local is_running = self._running and self._unit:movement():is_above_stamina_threshold() and t - self._start_running_t > 0.4
					local jump_vel_xy = tweak_data.player.movement_state.standard.movement.jump_velocity.xy[is_running and "run" or "walk"]
					action_start_data.jump_vel_xy = jump_vel_xy

					if is_running then
						self._unit:movement():subtract_stamina(tweak_data.player.movement_state.stamina.SPRINT_JUMP_STAMINA_DRAIN or 0)
					end
				end

				new_action = self:_start_action_jump(t, action_start_data)
			end
		end
	end

	return new_action
end

--[[
Temp disabled, might revisit this?

function PlayerStandard:_check_action_jump(t, input)
	local new_action = nil
	local action_wanted = input.btn_jump_press

	if action_wanted then
		local action_forbidden = self._jump_t and t < self._jump_t + 0.55
		--Here!
		action_forbidden = action_forbidden or self._unit:base():stats_screen_visible() or self._state_data.in_air or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_on_zipline() or self:_does_deploying_limit_movement() or self:_is_using_bipod()

		if not action_forbidden then
			if self._state_data.ducking then
				self:_interupt_action_ducking(t)
			else
				if self._state_data.on_ladder then
					self:_interupt_action_ladder(t)
				end

				local action_start_data = {}
				local jump_vel_z = tweak_data.player.movement_state.standard.movement.jump_velocity.z
				action_start_data.jump_vel_z = jump_vel_z

				if self._move_dir then
					local is_running = self._running and self._unit:movement():is_above_stamina_threshold() and t - self._start_running_t > 0.4
					local jump_vel_xy = tweak_data.player.movement_state.standard.movement.jump_velocity.xy[is_running and "run" or "walk"]
					action_start_data.jump_vel_xy = jump_vel_xy

					if is_running then
						self._unit:movement():subtract_stamina(tweak_data.player.movement_state.stamina.JUMP_STAMINA_DRAIN)
					end
				end

				new_action = self:_start_action_jump(t, action_start_data)
			end
		end
	end

	return new_action
end

function PlayerStandard:_determine_move_direction()
	self._stick_move = self._controller:get_input_axis("move")

	if self._state_data.on_zipline then
		return
	end

	--Here!
	if mvector3.length(self._stick_move) < PlayerStandard.MOVEMENT_DEADZONE or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_does_deploying_limit_movement() then
		self._move_dir = nil
		self._normal_move_dir = nil
	else
		local ladder_unit = self._unit:movement():ladder_unit()

		if alive(ladder_unit) then
			local ladder_ext = ladder_unit:ladder()
			self._move_dir = mvector3.copy(self._stick_move)
			self._normal_move_dir = mvector3.copy(self._move_dir)
			local cam_flat_rot = Rotation(self._cam_fwd_flat, math.UP)

			mvector3.rotate_with(self._normal_move_dir, cam_flat_rot)

			local cam_rot = Rotation(self._cam_fwd, self._ext_camera:rotation():z())

			mvector3.rotate_with(self._move_dir, cam_rot)

			local up_dot = math.dot(self._move_dir, ladder_ext:up())
			local w_dir_dot = math.dot(self._move_dir, ladder_ext:w_dir())
			local normal_dot = math.dot(self._move_dir, ladder_ext:normal()) * -1
			local normal_offset = ladder_ext:get_normal_move_offset(self._unit:movement():m_pos())

			mvector3.set(self._move_dir, ladder_ext:up() * (up_dot + normal_dot))
			mvector3.add(self._move_dir, ladder_ext:w_dir() * w_dir_dot)
			mvector3.add(self._move_dir, ladder_ext:normal() * normal_offset)
		else
			self._move_dir = mvector3.copy(self._stick_move)
			local cam_flat_rot = Rotation(self._cam_fwd_flat, math.UP)

			mvector3.rotate_with(self._move_dir, cam_flat_rot)

			self._normal_move_dir = mvector3.copy(self._move_dir)
		end
	end
end

]]--

function PlayerStandard:_check_action_primary_attack(t, input)
	local new_action = nil
	local action_wanted = input.btn_primary_attack_state or input.btn_primary_attack_release or self._queue_fire

	action_wanted = action_wanted or self:is_shooting_count()
	action_wanted = action_wanted or self:_is_charging_weapon()

	if action_wanted then
		local action_forbidden = self:_is_reloading() or self:_changing_weapon() or self:_is_meleeing() or self._use_item_expire_t or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_is_throwing_projectile() or self:_is_deploying_bipod() or self._menu_closed_fire_cooldown > 0 or self:is_switching_stances()

		if not action_forbidden then
			self._queue_reload_interupt = nil
			local start_shooting = false

			self._ext_inventory:equip_selected_primary(false)

			if self._equipped_unit then
				local weap_base = self._equipped_unit:base()
				local fire_mode = weap_base:fire_mode()
				local fire_on_release = weap_base:fire_on_release()
				local is_bow = table.contains(weap_base:weapon_tweak_data().categories, "bow")
				local weap_hold = weap_base.weapon_hold and weap_base:weapon_hold() or weap_base:get_name_id()
				local force_ads_recoil_anims = weap_base and weap_base:weapon_tweak_data().always_play_anims
				if weap_base and weap_base:alt_fire_active() and weap_base._alt_fire_data and weap_base._alt_fire_data.ignore_always_play_anims then
					force_ads_recoil_anims = nil
				end

				if weap_base:out_of_ammo() then
					if input.btn_primary_attack_press then
						weap_base:dryfire()
					end
				elseif weap_base.clip_empty and weap_base:clip_empty() then
					if self:_is_using_bipod() then
						if input.btn_primary_attack_press then
							weap_base:dryfire()
						end

						self._equipped_unit:base():tweak_data_anim_stop("fire")
					elseif fire_mode == "single" then
						if input.btn_primary_attack_press or self._equipped_unit:base().should_reload_immediately and self._equipped_unit:base():should_reload_immediately() then
							self:_start_action_reload_enter(t)
						end
					else
						new_action = true

						self:_start_action_reload_enter(t)
					end
				elseif self._running and not self._equipped_unit:base():run_and_shoot_allowed() then
					self:_interupt_action_running(t)
				else
					if not self._shooting then
						if weap_base:start_shooting_allowed() then
							local start = fire_mode == "single" and self._queue_fire or input.btn_primary_attack_press
							start = start or fire_mode == "auto" and input.btn_primary_attack_state
							start = start or fire_mode == "burst" and input.btn_primary_attack_press
							start = start or fire_mode == "volley" and input.btn_primary_attack_press
							start = start and not fire_on_release
							start = start or fire_on_release and input.btn_primary_attack_release
							if start then
								weap_base:start_shooting()
								self._camera_unit:base():start_shooting()

								self._shooting = true
								self._shooting_t = t
								start_shooting = true

								if fire_mode == "auto" and not weap_base:weapon_tweak_data().no_auto_anims then
									if restoration.Options:GetValue("OTHER/WeaponHandling/NoADSRecoilAnims") and self._shooting and self._state_data.in_steelsight and not weap_base.akimbo and not is_bow and not norecoil_blacklist[weap_hold] and not force_ads_recoil_anims or weap_base._disable_steelsight_recoil_anim then
									else
										self._unit:camera():play_redirect(self:get_animation("recoil_enter"))
									end

									if (not weap_base.akimbo or weap_base:weapon_tweak_data().allow_akimbo_autofire) and (not weap_base.third_person_important or weap_base.third_person_important and not weap_base:third_person_important()) then
										self._ext_network:send("sync_start_auto_fire_sound", 0)
									end
								end
							end
						else
							if restoration.Options:GetValue("OTHER/WeaponHandling/QueuedShooting") then
								if input.btn_primary_attack_press and fire_mode == "single" and not weap_base:in_burst_mode() and not weap_base:start_shooting_allowed() then
									local next_fire = weap_base:weapon_fire_rate() / weap_base:fire_rate_multiplier()
									local next_fire_last = weap_base._next_fire_allowed - next_fire
									local next_fire_delay = weap_base._next_fire_allowed - next_fire_last
									local next_fire_current_t = weap_base._next_fire_allowed - t
									local queue_window = restoration.Options:GetValue("OTHER/WeaponHandling/QueuedShootingWindow") or 0.5
									local queue_exlude = (restoration.Options:GetValue("OTHER/WeaponHandling/QueuedShootingExclude") and 60 / restoration.Options:GetValue("OTHER/WeaponHandling/QueuedShootingExclude")) or 0.6
									if queue_exlude >= next_fire and next_fire_current_t < next_fire_delay * queue_window then
										self._queue_fire = true
									end
								end
							else
								self._queue_fire = nil
							end
							self:_check_stop_shooting()

							return false
						end
					end

					local suppression_ratio = self._unit:character_damage():effective_suppression_ratio()
					local spread_mul = math.lerp(1, tweak_data.player.suppression.spread_mul, suppression_ratio)
					local autohit_mul = math.lerp(1, tweak_data.player.suppression.autohit_chance_mul, suppression_ratio)
					local suppression_mul = managers.blackmarket:threat_multiplier()
					local dmg_mul = 1
					local weapon_tweak_data = weap_base:weapon_tweak_data()
					local primary_category = weapon_tweak_data.categories[1]

					if not weapon_tweak_data.ignore_damage_multipliers then
						dmg_mul = dmg_mul * managers.player:temporary_upgrade_value("temporary", "dmg_multiplier_outnumbered", 1)

						if managers.player:has_category_upgrade("player", "overkill_all_weapons") or weap_base:is_category("shotgun", "saw") then
							dmg_mul = dmg_mul * managers.player:temporary_upgrade_value("temporary", "overkill_damage_multiplier", 1)
						end

						local health_ratio = self._ext_damage:health_ratio()
						local damage_health_ratio = managers.player:get_damage_health_ratio(health_ratio, primary_category)

						if damage_health_ratio > 0 then
							local upgrade_name = weap_base:is_category("saw") and "melee_damage_health_ratio_multiplier" or "damage_health_ratio_multiplier"
							local damage_ratio = damage_health_ratio
							dmg_mul = dmg_mul * (1 + managers.player:upgrade_value("player", upgrade_name, 0) * damage_ratio)
						end

						dmg_mul = dmg_mul * managers.player:temporary_upgrade_value("temporary", "berserker_damage_multiplier", 1)
						dmg_mul = dmg_mul * managers.player:get_property("trigger_happy", 1)
					end

					dmg_mul = dmg_mul * managers.player:get_temporary_property("birthday_multiplier", 1)
					local fired = nil

					if fire_mode == "single" then
						if (self._queue_fire or input.btn_primary_attack_press) and start_shooting then
							fired = weap_base:trigger_pressed(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
						elseif fire_on_release then
							if input.btn_primary_attack_release then
								fired = weap_base:trigger_released(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
							elseif input.btn_primary_attack_state then
								weap_base:trigger_held(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
							end
						end
					elseif fire_mode == "auto" then
						if input.btn_primary_attack_state then
							fired = weap_base:trigger_held(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
						end
					elseif fire_mode == "burst" then
						fired = weap_base:trigger_held(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
					elseif fire_mode == "volley" then
						if self._shooting then
							fired = weap_base:trigger_held(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
						end
					end
					if not restoration.Options:GetValue("OTHER/WeaponHandling/SeparateBowADS") then
						if weap_base.manages_steelsight and weap_base:manages_steelsight() then
							if weap_base:wants_steelsight() and not self._state_data.in_steelsight then
								self:_start_action_steelsight(t)
							elseif not weap_base:wants_steelsight() and self._state_data.in_steelsight then
								self:_end_action_steelsight(t)
							end
						end
					end

					local charging_weapon = weap_base:charging()

					if not self._state_data.charging_weapon and charging_weapon then
						self:_start_action_charging_weapon(t)
					elseif self._state_data.charging_weapon and not charging_weapon then
						self:_end_action_charging_weapon(t)
					end

					new_action = true

					if fired then
						self._queue_fire = nil

						if weap_base._descope_on_fire then
							self._d_scope_t = (weap_base._next_fire_allowed - t) * 0.7
						end
						
						managers.rumble:play("weapon_fire")

						local weap_tweak_data = tweak_data.weapon[weap_base:get_name_id()]
						local shake_multiplier = weap_tweak_data.shake[self._state_data.in_steelsight and "fire_steelsight_multiplier" or "fire_multiplier"]
						local fire_anim_offset = weap_base:weapon_tweak_data().fire_anim_offset
						local fire_anim_offset2 = weap_base:weapon_tweak_data().fire_anim_offset2
						local vars = {
							-1,
							1
						}
						local random = vars[math.random(#vars)]
						local no_recoil_anims = restoration.Options:GetValue("OTHER/WeaponHandling/NoADSRecoilAnims")
						if self._state_data.in_steelsight and (no_recoil_anims or weap_base._disable_steelsight_recoil_anim) then
							self._ext_camera:play_shaker("whizby", random * 0.05 * shake_multiplier, vars[math.random(#vars)] * 0.25, vars[math.random(#vars)] * 0.25  )
						end
						self._ext_camera:play_shaker("fire_weapon_rot", 1 * shake_multiplier)
						self._ext_camera:play_shaker("fire_weapon_kick", 1 * shake_multiplier * (self._state_data.in_steelsight and 0.2 or 1) , 1, 0.15)
						self._equipped_unit:base():tweak_data_anim_stop("unequip")
						self._equipped_unit:base():tweak_data_anim_stop("equip")

						if not self._state_data.in_steelsight or not weap_base:tweak_data_anim_play("fire_steelsight", weap_base:fire_rate_multiplier(), fire_anim_offset, fire_anim_offset2) then
							weap_base:tweak_data_anim_play("fire", weap_base:fire_rate_multiplier(), fire_anim_offset, fire_anim_offset2)
						end

						if (fire_mode == "single" or fire_mode == "burst" or weap_base:weapon_tweak_data().no_auto_anims) and weap_base:get_name_id() ~= "saw" then
							local state = nil

							if (not self._state_data.in_steelsight or (restoration.Options:GetValue("OTHER/WeaponHandling/SeparateBowADS") and is_bow)) then
								if (weap_base:in_burst_mode() and weap_base:weapon_tweak_data().BURST_SLAM) then
									state = self._ext_camera:play_redirect(--[[weap_base:is_second_sight_on() and self:get_animation("recoil") or]]self:get_animation("recoil_steelsight"), 1)
								else
									state = self._ext_camera:play_redirect(self:get_animation("recoil"), weap_base:fire_rate_multiplier())
								end
							elseif weap_tweak_data.animations.recoil_steelsight then
								if no_recoil_anims and self._shooting and self._state_data.in_steelsight and not weap_base.akimbo and not is_bow and not norecoil_blacklist[weap_hold] and not force_ads_recoil_anims or weap_base._disable_steelsight_recoil_anim then
								else
									state = self._ext_camera:play_redirect(--[[weap_base:is_second_sight_on() and self:get_animation("recoil") or]]self:get_animation("recoil_steelsight"), 1)
								end
							end
							
							if state then
								self._camera_unit:anim_state_machine():set_parameter(state, "alt_weight", self._equipped_unit:base():alt_fire_active() and 1 or 0)
							end
						end

						local recoil_multiplier = (weap_base:recoil() + weap_base:recoil_addend()) * weap_base:recoil_multiplier()

						cat_print("jansve", "[PlayerStandard] Weapon Recoil Multiplier: " .. tostring(recoil_multiplier))

						local kick_tweak_data = weap_tweak_data.kick[fire_mode] or weap_tweak_data.kick
						local up, down, left, right = unpack(kick_tweak_data[self._state_data.in_steelsight and "steelsight" or self._state_data.ducking and "crouching" or "standing"])

						self._camera_unit:base():recoil_kick(up * recoil_multiplier, down * recoil_multiplier, left * recoil_multiplier, right * recoil_multiplier)

						if self._shooting_t then
							local time_shooting = t - self._shooting_t
							local achievement_data = tweak_data.achievement.never_let_you_go

							if achievement_data and weap_base:get_name_id() == achievement_data.weapon_id and achievement_data.timer <= time_shooting then
								managers.achievment:award(achievement_data.award)

								self._shooting_t = nil
							end
						end

						if managers.player:has_category_upgrade(primary_category, "stacking_hit_damage_multiplier") then
							self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
							self._state_data.stacking_dmg_mul[primary_category] = self._state_data.stacking_dmg_mul[primary_category] or {
								nil,
								0
							}
							local stack = self._state_data.stacking_dmg_mul[primary_category]

							if fired.hit_enemy then
								stack[1] = t + managers.player:upgrade_value(primary_category, "stacking_hit_expire_t", 1)
								stack[2] = math.min(stack[2] + 1, tweak_data.upgrades.max_weapon_dmg_mul_stacks or 5)
							else
								stack[1] = nil
								stack[2] = 0
							end
						end

						if weap_base.set_recharge_clbk then
							weap_base:set_recharge_clbk(callback(self, self, "weapon_recharge_clbk_listener"))
						end

						managers.hud:set_ammo_amount(weap_base:selection_index(), weap_base:ammo_info())

						local impact = not fired.hit_enemy

						if weap_base.third_person_important and weap_base:third_person_important() then
							self._ext_network:send("shot_blank_reliable", impact, 0)
						elseif weap_base.akimbo and not weap_base:weapon_tweak_data().allow_akimbo_autofire or fire_mode == "single" or fire_mode == "burst" then
							self._ext_network:send("shot_blank", impact, 0)
						end

						if fire_mode == "volley" then
							self:_check_stop_shooting()
							new_action = false
						end
					elseif fire_mode == "single" then
						new_action = false
					elseif fire_mode == "burst" then
						if weap_base:shooting_count() == 0 then
							new_action = false
						end
					elseif fire_mode == "volley" then
						new_action = self:_is_charging_weapon()
					end
				end
			end
		elseif self:_is_reloading() and self._equipped_unit:base():reload_interuptable() and input.btn_primary_attack_press then
			self._queue_reload_interupt = true
		end
		self._queue_fire = nil
	end

	if not new_action then
		self:_check_stop_shooting()
	end

	return new_action
end

function PlayerStandard:_check_stop_shooting()
	if self._shooting then
		self._equipped_unit:base():stop_shooting()
		self._camera_unit:base():stop_shooting(self._equipped_unit:base():recoil_wait())

		local weap_base = self._equipped_unit:base()
		local fire_mode = weap_base:fire_mode()
		local is_auto_fire_mode = fire_mode == "auto"
		local is_volley_fire_mode = fire_mode == "volley"
		if is_volley_fire_mode then
			self:_end_action_charging_weapon()
		end
		if is_auto_fire_mode and (not weap_base.akimbo or weap_base:weapon_tweak_data().allow_akimbo_autofire) then
			self._ext_network:send("sync_stop_auto_fire_sound", 0)
		end
		local weap_base = self._equipped_unit:base()	
		local weap_hold = weap_base.weapon_hold and weap_base:weapon_hold() or weap_base:get_name_id()
		local is_bow = table.contains(weap_base:weapon_tweak_data().categories, "bow")
		local force_ads_recoil_anims = weap_base and weap_base:weapon_tweak_data().always_play_anims
		if weap_base and weap_base:alt_fire_active() and weap_base._alt_fire_data and weap_base._alt_fire_data.ignore_always_play_anims then
			force_ads_recoil_anims = nil
		end

		if restoration.Options:GetValue("OTHER/WeaponHandling/NoADSRecoilAnims") and self._state_data.in_steelsight and not weap_base.akimbo and not is_bow and not norecoil_blacklist[weap_hold] and not force_ads_recoil_anims then
			self._ext_camera:play_redirect(self:get_animation("idle"))
		else 
			if (is_auto_fire_mode or is_volley_fire_mode) and not self:_is_reloading() and not self:_is_meleeing() and not weap_base:weapon_tweak_data().no_auto_anims then
				self._ext_camera:play_redirect(self:get_animation("recoil_exit"))
			end
		end
		self._shooting = false
		self._shooting_t = nil
	end
end

function PlayerStandard:_start_action_charging_weapon(t)
	self._state_data.charging_weapon = true
	self._state_data.charging_weapon_data = {
		t = t,
		max_t = 2.5
	}
	local ANIM_LENGTH = 1.5
	local max = self._equipped_unit:base():charge_max_t()
	local speed_multiplier = ANIM_LENGTH / max
	local weap_base = self._equipped_unit:base()
	local no_charge_anims = weap_base:weapon_tweak_data().no_charge_anims
	if not no_charge_anims then
		self._equipped_unit:base():tweak_data_anim_play("charge", speed_multiplier)
		self._ext_camera:play_redirect(self:get_animation("charge"), speed_multiplier)
	end
end

function PlayerStandard:_check_action_night_vision(t, input)
	if not input.btn_night_vision_press then
		return
	end

	local action_forbidden = self:_is_throwing_projectile() or self:_is_meleeing() or self:is_equipping() or self:_changing_weapon() or self:shooting() or self:_is_reloading() or self:is_switching_stances() or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction")

	if action_forbidden then
		return
	end

	self:set_night_vision_state(not self._state_data.night_vision_active)
end

function PlayerStandard:_check_action_interact(t, input)
	if restoration.Options:GetValue("OTHER/SevenHold") then 
		local deploy_cancel = restoration.Options:GetValue("OTHER/SevenHoldDeployCancel")
		if self:_interacting() then
			if (not deploy_cancel and input.btn_interact_press) or (deploy_cancel and input.btn_use_item_press) then
				self:_interupt_action_interact()
				return false
			elseif input.btn_interact_release then
				return false
			end
		end
	end

	local keyboard = self._controller.TYPE == "pc" or managers.controller:get_default_wrapper_type() == "pc"
	local new_action, timer, interact_object = nil

	if input.btn_interact_press then
		if _G.IS_VR then
			self._interact_hand = input.btn_interact_left_press and PlayerHand.LEFT or PlayerHand.RIGHT
		end

		if not self:_action_interact_forbidden() then
			new_action, timer, interact_object = self._interaction:interact(self._unit, input.data, self._interact_hand)

			if new_action then
				self:_play_interact_redirect(t, input)
			end

			if timer then
				new_action = true

				if not managers.player:has_category_upgrade("player", "no_interrupt_interaction") then
					self._ext_camera:camera_unit():base():set_limits(80, 50)
				end
				self:_start_action_interact(t, input, timer, interact_object)
			end

			if not new_action then
				self._start_intimidate = true
				self._start_intimidate_t = t
			end
		end
	end

	local secondary_delay = tweak_data.team_ai.stop_action.delay
	local force_secondary_intimidate = false
	local HOLD_TO_STOP_ALL_AI_DURATION = 1.5 --seconds to hold down to direct all ai instead of just the one
	local skip_intimidate_action = false 
	
	--If stop bots option is enabled, replace vanilla version with a version with bot stopping support.
	if restoration.Options:GetValue("OTHER/StopAllBots") then 
		if self._start_shout_all_ai_t and self._start_shout_all_ai_t + HOLD_TO_STOP_ALL_AI_DURATION <= t then
			self._start_shout_all_ai_t = nil
			
			--tell all ai to stop
			for i, char_data in pairs(managers.criminals._characters) do
				if char_data.data.ai then
					local ai_unit = char_data.unit
					if alive(ai_unit) then 
						ai_unit:brain():on_long_dis_interacted(0, ai_unit, true)
						skip_intimidate_action = true
					end
				end
			
			end
			if skip_intimidate_action then 
				self:say_line("f48x_any", false)
				--play a voiceline if any ai were actually stopped
			end
		elseif self._controller:get_input_released("interact_secondary") then 
			--if release before the full duration required to call all ai then do normal single-target "stop ai" action
			self._start_shout_all_ai_t = nil
			force_secondary_intimidate = true
		elseif input.btn_interact_secondary_press then 
			--if pressing for the first time (not holding), start timer, do not do normal single-target "stop ai" until key release
			self._start_shout_all_ai_t = t
			skip_intimidate_action = true
		end
	end

	if not new_action and keyboard and input.btn_interact_secondary_press then
		force_secondary_intimidate = true
	end

	if input.btn_interact_release then
		local released = true

		if _G.IS_VR then
			local release_hand = input.btn_interact_left_release and PlayerHand.LEFT or PlayerHand.RIGHT
			released = release_hand == self._interact_hand
		end

		if released then
			if self._start_intimidate and not self:_action_interact_forbidden() then
				if t < self._start_intimidate_t + secondary_delay then
					self:_start_action_intimidate(t)

					self._start_intimidate = false
				end
			else
				self:_interupt_action_interact()
			end
		end
	end
	
	if (self._start_intimidate or force_secondary_intimidate) and not self:_action_interact_forbidden() and (not keyboard and t > self._start_intimidate_t + secondary_delay or force_secondary_intimidate) then
		self:_start_action_intimidate(t, true)

		self._start_intimidate = false
	end

	return new_action
end

function PlayerStandard:_start_action_intimidate(t, secondary)
	if not self._intimidate_t or tweak_data.player.movement_state.interaction_delay < t - self._intimidate_t then
		local skip_alert = managers.groupai:state():whisper_mode()
		local voice_type, plural, prime_target = self:_get_unit_intimidation_action(not secondary, not secondary, true, false, true, nil, nil, nil, secondary)
		
		if prime_target and prime_target.unit and prime_target.unit.base and (
				prime_target.unit:base().unintimidateable
				or prime_target.unit:anim_data() and prime_target.unit:anim_data().unintimidateable 
				--Stops undommable enemies from being shouted at.
				or tweak_data.character[prime_target.unit:base()._tweak_table] and tweak_data.character[prime_target.unit:base()._tweak_table].unintimidateable and prime_target.unit:movement() and not prime_target.unit:movement():cool()
			) then
			return
		end
		
		local interact_type, sound_name = nil
		local sound_suffix = plural and "plu" or "sin"
		if voice_type == "stop" then
			interact_type = "cmd_stop"
			sound_name = "f02x_" .. sound_suffix
		elseif voice_type == "stop_cop" then
			interact_type = "cmd_stop"
			sound_name = "l01x_" .. sound_suffix
		elseif voice_type == "mark_cop" or voice_type == "mark_cop_quiet" then
			interact_type = "cmd_point"
			if voice_type == "mark_cop_quiet" then
				sound_name = tweak_data.character[prime_target.unit:base()._tweak_table].silent_priority_shout .. "_any"
			elseif tweak_data.character[prime_target.unit:base()._tweak_table].custom_shout then --Special boss shoutouts.
				sound_name = tweak_data.character[prime_target.unit:base()._tweak_table].priority_shout
			else
				sound_name = tweak_data.character[prime_target.unit:base()._tweak_table].priority_shout .. "x_any"
				sound_name = managers.modifiers:modify_value("PlayerStandart:_start_action_intimidate", sound_name, prime_target.unit)
			end

			if managers.player:has_category_upgrade("player", "special_enemy_highlight") then
				prime_target.unit:contour():add(managers.player:get_contour_for_marked_enemy(), true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1))
				managers.network:session():send_to_peers_synched("spot_enemy", prime_target.unit)
			end
		elseif voice_type == "down" then
			interact_type = "cmd_down"
			sound_name = "f02x_" .. sound_suffix
			self._shout_down_t = t
		elseif voice_type == "down_cop" then
			interact_type = "cmd_down"
			sound_name = "l02x_" .. sound_suffix
		elseif voice_type == "cuff_cop" then
			interact_type = "cmd_down"
			sound_name = "l03x_" .. sound_suffix
		elseif voice_type == "down_stay" then
			interact_type = "cmd_down"

			if self._shout_down_t and t < self._shout_down_t + 2 then
				sound_name = "f03b_any"
			else
				sound_name = "f03a_" .. sound_suffix
			end
		elseif voice_type == "come" then
			interact_type = "cmd_come"
			local static_data = managers.criminals:character_static_data_by_unit(prime_target.unit)

			if static_data then
				local character_code = static_data.ssuffix
				sound_name = "f21" .. character_code .. "_sin"
			else
				sound_name = "f38_any"
			end
		elseif voice_type == "revive" then
			interact_type = "cmd_get_up"
			local static_data = managers.criminals:character_static_data_by_unit(prime_target.unit)

			if not static_data then
				return
			end

			local character_code = static_data.ssuffix
			sound_name = "f36x_any"

			if math.random() < self._ext_movement:rally_skill_data().revive_chance then
				prime_target.unit:interaction():interact(self._unit)
			end

			self._ext_movement:rally_skill_data().morale_boost_delay_t = managers.player:player_timer():time() + (self._ext_movement:rally_skill_data().morale_boost_cooldown_t or 3.5)
		elseif voice_type == "boost" then
			interact_type = "cmd_gogo"
			local static_data = managers.criminals:character_static_data_by_unit(prime_target.unit)

			if not static_data then
				return
			end

			local character_code = static_data.ssuffix
			sound_name = "g18"
			self._ext_movement:rally_skill_data().morale_boost_delay_t = managers.player:player_timer():time() + (self._ext_movement:rally_skill_data().morale_boost_cooldown_t or 3.5)
		elseif voice_type == "escort" then
			interact_type = "cmd_point"
			sound_name = "f41_" .. sound_suffix
		elseif voice_type == "escort_keep" or voice_type == "escort_go" then
			interact_type = "cmd_point"
			sound_name = "f40_any"
		elseif voice_type == "bridge_codeword" then
			sound_name = "bri_14"
			interact_type = "cmd_point"
		elseif voice_type == "bridge_chair" then
			sound_name = "bri_29"
			interact_type = "cmd_point"
		elseif voice_type == "undercover_interrogate" then
			sound_name = "f46x_any"
			interact_type = "cmd_point"
		elseif voice_type == "undercover_escort" then
			sound_name = "f41_any"
			interact_type = "cmd_point"
		elseif voice_type == "mark_camera" then
			sound_name = "f39_any"
			interact_type = "cmd_point"

			prime_target.unit:contour():add("mark_unit", true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1))
		elseif voice_type == "mark_turret" then
			sound_name = "f44x_any"
			interact_type = "cmd_point"
			local type = prime_target.unit:base().get_type and prime_target.unit:base():get_type()

			prime_target.unit:contour():add(managers.player:get_contour_for_marked_enemy(type), true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1))
		elseif voice_type == "ai_stay" then
			sound_name = "f48x_any"
			interact_type = "cmd_stop"
		end

		self:_do_action_intimidate(t, interact_type, sound_name, skip_alert)
	end
end

--Sixth sense action forbidden to let it work in loud, and only requires the player to not be moving to proc (so actions like shooting or aiming down sights no longer stop it).
function PlayerStandard:_update_omniscience(t, dt)
	local action_forbidden = not managers.player:has_category_upgrade("player", "standstill_omniscience") or managers.player:current_state() == "civilian" or self._ext_movement:has_carry_restriction() or self:_on_zipline() or self._moving or self:running() or self:in_air() or not tweak_data.player.omniscience
	if action_forbidden then
		if self._state_data.omniscience_t then
			self._state_data.omniscience_t = nil
		end

		return
	end

	self._state_data.omniscience_t = self._state_data.omniscience_t or t + tweak_data.player.omniscience.start_t

	if self._state_data.omniscience_t <= t then
		local sensed_targets = World:find_units_quick("sphere", self._unit:movement():m_pos(), tweak_data.player.omniscience.sense_radius, managers.slot:get_mask("trip_mine_targets"))

		for _, unit in ipairs(sensed_targets) do
			if alive(unit) and not unit:base():char_tweak().is_escort then
				self._state_data.omniscience_units_detected = self._state_data.omniscience_units_detected or {}

				if not self._state_data.omniscience_units_detected[unit:key()] or self._state_data.omniscience_units_detected[unit:key()] <= t then
					self._state_data.omniscience_units_detected[unit:key()] = t + tweak_data.player.omniscience.target_resense_t

					managers.game_play_central:auto_highlight_enemy(unit, true)
					break
				end
			end
		end

		self._state_data.omniscience_t = t + tweak_data.player.omniscience.interval_t
	end
end

--ADS movement speed shit
function PlayerStandard:_get_max_walk_speed(t, force_run)
	local speed_tweak = self._tweak_data.movement.speed
	local movement_speed = speed_tweak.STANDARD_MAX
	local speed_state = "walk"
	local weapon = self._equipped_unit:base()
	local weapon_tweak = weapon:weapon_tweak_data()
	local is_leaning = TacticalLean and ((TacticalLean:GetLeanDirection() or TacticalLean:IsExitingLean()) and true) or nil

	if self._is_sliding then -- should be fine without having AdvMov installed since _is_sliding will return nil if you don't have it
		movement_speed = self._slide_speed
		speed_state = "run"
	elseif self._is_wallrunning then -- ditto
		movement_speed = self._wallrun_speed
		speed_state = "run"
	elseif self._is_wallkicking then -- ditto
		movement_speed = speed_tweak.RUNNING_MAX * 1.5
		speed_state = "run"
	elseif self._state_data.in_steelsight and not managers.player:has_category_upgrade("player", "steelsight_normal_movement_speed") and not _G.IS_VR then
		movement_speed = speed_tweak.STEELSIGHT_MAX
		if alive(self._equipped_unit) then
			local base_speed = ( (self:on_ladder() and speed_tweak.CLIMBING_MAX ) or (self._state_data.ducking and speed_tweak.CROUCHING_MAX) or (self._state_data.in_air and speed_tweak.INAIR_MAX) or speed_tweak.STANDARD_MAX )
			local speed_mult = 1
			local has_ads_move_speed_mult = nil
			for _, category in ipairs(weapon_tweak.categories) do
				if tweak_data[category] and tweak_data[category].ads_move_speed_mult then
					speed_mult = speed_mult * tweak_data[category].ads_move_speed_mult
					has_ads_move_speed_mult = true
				end
			end
			if weapon_tweak.is_bullpup then 
				speed_mult = speed_mult * 1.25
			end
			speed_mult = speed_mult * (managers.player:upgrade_value("player", "steelsight_move_speed_multiplier", 1) or 1)
			movement_speed = base_speed * ((not has_ads_move_speed_mult and 0.45) or 1)
			movement_speed = math.clamp(movement_speed * speed_mult, 0, base_speed)
		end
		speed_state = "steelsight"
	elseif self:on_ladder() then
		movement_speed = speed_tweak.CLIMBING_MAX
		speed_state = "climb"
	elseif self._state_data.ducking then
		movement_speed = speed_tweak.CROUCHING_MAX
		speed_state = "crouch"
	elseif self._state_data.in_air then
		movement_speed = speed_tweak.INAIR_MAX
		speed_state = nil
	elseif self._running or force_run then
		movement_speed = speed_tweak.RUNNING_MAX
		speed_state = "run"
	end

	movement_speed = managers.modifiers:modify_value("PlayerStandard:GetMaxWalkSpeed", movement_speed, self._state_data, speed_tweak)
	local morale_boost_bonus = self._ext_movement:morale_boost()
	local multiplier = managers.player:movement_speed_multiplier(speed_state, speed_state and morale_boost_bonus and morale_boost_bonus.move_speed_bonus, nil, self._ext_damage:health_ratio())
	multiplier = multiplier * (self._tweak_data.movement.multiplier[speed_state] or 1)
	local apply_weapon_penalty = true

	if self:_is_meleeing() then
		local melee_entry = managers.blackmarket:equipped_melee_weapon()
		apply_weapon_penalty = not tweak_data.blackmarket.melee_weapons[melee_entry].stats.remove_weapon_movement_penalty
	end

	if alive(self._equipped_unit) and apply_weapon_penalty then
		multiplier = multiplier * self._equipped_unit:base():movement_penalty()
	end

	if managers.player:has_activate_temporary_upgrade("temporary", "increased_movement_speed") then
		multiplier = multiplier * managers.player:temporary_upgrade_value("temporary", "increased_movement_speed", 1)
	end

	if managers.player:has_activate_temporary_upgrade("temporary", "copr_ability") then
		local out_of_health = self._unit:character_damage():health_ratio() + 0.01 < managers.player:upgrade_value("player", "copr_static_damage_ratio", 0)

		if out_of_health then
			multiplier = multiplier * managers.player:upgrade_value("player", "copr_out_of_health_move_slow", 1)
		end
	end
	
	if self._shooting_move_speed_t then
		multiplier = multiplier * self._shooting_move_speed_mult
	elseif self:_is_reloading() and weapon and weapon._rms then
		multiplier = multiplier * weapon._rms
	end

	local final_speed = movement_speed * multiplier
	self._cached_final_speed = self._cached_final_speed or 0

	if final_speed ~= self._cached_final_speed then
		self._cached_final_speed = final_speed

		self._ext_network:send("action_change_speed", final_speed)
	end
	return final_speed
end



--Allows for melee sprinting.
function PlayerStandard:_start_action_running(t)
	local weap_base = alive(self._equipped_unit) and self._equipped_unit:base()

	local second_sight_sprint = restoration.Options:GetValue("OTHER/WeaponHandling/SecondSightSprint")
	if second_sight_sprint and weap_base.toggle_second_sight and self:in_steelsight() then
		if self._running_wanted ~= true and weap_base:has_second_sight() and weap_base:toggle_second_sight(self) then
		end
		self._running_wanted = false

		return
	end

	if self._slowdown_run_prevent then
		self._running_wanted = false

		return
	end

	--Consolidated vanilla checks.
	if not self._move_dir or self:on_ladder() or self:_on_zipline() or not self:_can_run_directional() or managers.player:get_player_rule("no_run") or not self._unit:movement():is_above_stamina_threshold() then
		self._running_wanted = true
		return
	end

	if self._shooting and not self._equipped_unit:base():run_and_shoot_allowed() or (self:_is_charging_weapon() and not self._equipped_unit:base():run_and_shoot_allowed()) or --[[self:_changing_weapon() or]] self._use_item_expire_t or self._state_data.in_air or self:_is_throwing_projectile() or self:_in_burst() or self._state_data.ducking and not self:_can_stand()then
		self._running_wanted = true
		return
	end
				
	self._queue_fire = nil
	self._running_wanted = false

	if (not self._state_data.shake_player_start_running or not self._ext_camera:shaker():is_playing(self._state_data.shake_player_start_running)) and managers.user:get_setting("use_headbob") then
		self._state_data.shake_player_start_running = self._ext_camera:play_shaker("player_start_running" , 0.75)
	end
				
	self:set_running(true)

	weap_base:tweak_data_anim_stop("fire")
	weap_base:tweak_data_anim_stop("fire_steelsight")
	if (weap_base.AKIMBO and weap_base:ammo_base():get_ammo_remaining_in_clip() > 1) or (not weap_base.AKIMBO and not weap_base:can_reload() and not weap_base:clip_empty()) then
		weap_base:tweak_data_anim_stop("reload")
		weap_base:tweak_data_anim_stop("reload_left")
		weap_base:tweak_data_anim_stop("magazine_empty")
	end

	self._end_running_expire_t = nil
	self._start_running_t = t

	local cancel_sprint = restoration.Options:GetValue("OTHER/WeaponHandling/SprintCancel")
	
	--Skip sprinting animations of player is doing melee things.
	if not self:_changing_weapon() and not self:_is_charging_weapon() and not self:_is_meleeing() and (not self:_is_reloading() or (not self.RUN_AND_RELOAD or (self.RUN_AND_RELOAD and (cancel_sprint == true or self._equipped_unit:base()._starwars)))) then
		if not self._equipped_unit:base():run_and_shoot_allowed() then
			self._ext_camera:play_redirect(self:get_animation("start_running"))	
		else
			self._ext_camera:play_redirect(self:get_animation("idle"))	
		end	
	end
	
	if not self.RUN_AND_RELOAD or (self.RUN_AND_RELOAD and cancel_sprint == true) then
		self:_interupt_action_reload(t)
	end
				
	self:_interupt_action_steelsight(t)
	self:_interupt_action_ducking(t)
end

function PlayerStandard:_end_action_running(t)
	if not self._end_running_expire_t then
		local speed_multiplier = self._equipped_unit:base():exit_run_speed_multiplier()
		local sprintout_anim_time = self._equipped_unit:base():weapon_tweak_data().sprintout_anim_time or 0.4

		self._end_running_expire_t = t + sprintout_anim_time / speed_multiplier
		--Adds a few melee related checks to avoid cutting off animations.
		local cancel_sprint = restoration.Options:GetValue("OTHER/WeaponHandling/SprintCancel")
		local stop_running = not self:_changing_weapon() and not self:_is_charging_weapon() and not self:_is_meleeing() and not self._equipped_unit:base():run_and_shoot_allowed() and ((not self:_is_reloading() or (not self.RUN_AND_RELOAD or (self.RUN_AND_RELOAD and self._equipped_unit:base()._starwars))))
		
		if stop_running then
			self._ext_camera:play_redirect(self:get_animation("stop_running"), math.min(speed_multiplier, 2) )
		end
	end
end

--Stores running input, is a workaround for other things that may interrupt running.
Hooks:PreHook(PlayerStandard, "_start_action_melee", "ResPlayerStandardPreStartActionMelee", function(self, t, input, instant)
	self._state_data.melee_running_wanted = true and self._running and not self._end_running_expire_t
end)

Hooks:PostHook(PlayerStandard, "_start_action_melee", "ResPlayerStandardPostStartActionMelee", function(self, t, input, instant)
	--Passes in running input, is a workaround for other things that may interrupt running.
	if self._state_data.melee_running_wanted then
		self._running_wanted = true
	end

	--Start chainsaw timer.
	local melee_tweak = tweak_data.blackmarket.melee_weapons[managers.blackmarket:equipped_melee_weapon()]
	if melee_tweak.chainsaw then
		self._state_data.chainsaw_t = t + melee_tweak.chainsaw.start_delay
	end
end)

Hooks:PostHook(PlayerStandard, "_check_action_melee", "ResEndChainsaw", function(self, t, input)
	--Stop chainsaw when no longer meleeing.
	if input.btn_melee_release then
		self._state_data.chainsaw_t = nil
	end
end)

--Effectively a slightly modified version of _do_melee_damage but without charging and certain melee gimmicks.
function PlayerStandard:_do_chainsaw_damage(t)
	melee_entry = managers.blackmarket:equipped_melee_weapon()
	local make_saw = tweak_data.blackmarket.melee_weapons[melee_entry].make_saw
	local charger_melee = tweak_data.blackmarket.melee_weapons[melee_entry].special_weapon and tweak_data.blackmarket.melee_weapons[melee_entry].special_weapon == "charger"
	self._state_data._charger_melee_active = true

	--Determine if attack hits.
	local sphere_cast_radius = 20
	local col_ray = self:_calc_melee_hit_ray(t, sphere_cast_radius)
	if col_ray and alive(col_ray.unit) then
		local damage, damage_effect = managers.blackmarket:equipped_melee_weapon_damage_info(0)
		local damage_effect_mul = math.max(managers.player:upgrade_value("player", "melee_knockdown_mul", 1), managers.player:upgrade_value(self._equipped_unit:base():weapon_tweak_data().categories and self._equipped_unit:base():weapon_tweak_data().categories[1], "melee_knockdown_mul", 1))
		damage = tweak_data.blackmarket.melee_weapons[melee_entry].chainsaw.tick_damage
		damage = damage * managers.player:get_melee_dmg_multiplier()
		damage_effect = damage_effect * damage_effect_mul
		col_ray.sphere_cast_radius = sphere_cast_radius
		local hit_unit = col_ray.unit

		if hit_unit:character_damage() then
			local hit_sfx = "hit_body"

			if hit_unit:character_damage() and hit_unit:character_damage().melee_hit_sfx then
				hit_sfx = hit_unit:character_damage():melee_hit_sfx()
			end

			self:_play_melee_sound(melee_entry, hit_sfx, self._melee_attack_var)
			self:_play_melee_sound(melee_entry, "charge", self._melee_attack_var)

			if not hit_unit:character_damage()._no_blood then
				managers.game_play_central:play_impact_flesh({
					col_ray = col_ray
				})
				managers.game_play_central:play_impact_sound_and_effects({
					no_decal = true,
					no_sound = true,
					col_ray = col_ray
				})
			end

			
		elseif self._on_melee_restart_drill and hit_unit:base() and (hit_unit:base().is_drill or hit_unit:base().is_saw) then
			hit_unit:base():on_melee_hit(managers.network:session():local_peer():id())
		else
			self:_play_melee_sound(melee_entry, "hit_gen", self._melee_attack_var)
			self:_play_melee_sound(melee_entry, "charge", self._melee_attack_var) -- continue playing charge sound after hit instead of silence

			managers.game_play_central:play_impact_sound_and_effects({
				decal = make_saw and "saw",
				no_decal = not make_saw and true,
				no_sound = true,
				col_ray = col_ray,
				effect = not make_saw and Idstring("effects/payday2/particles/impacts/fallback_impact_pd2") or nil
			})
		end

		local custom_data = nil

		if _G.IS_VR and hand_id then
			custom_data = {
				engine = hand_id == 1 and "right" or "left"
			}
		end

		managers.rumble:play("melee_hit", nil, nil, custom_data)
		managers.game_play_central:physics_push(col_ray)

		local character_unit, shield_knock = nil
		local can_shield_knock = managers.player:has_category_upgrade("player", "shield_knock")

		if can_shield_knock and hit_unit:in_slot(8) and alive(hit_unit:parent()) and not hit_unit:parent():character_damage():is_immune_to_shield_knockback() then
			shield_knock = true
			character_unit = hit_unit:parent()
		end

		character_unit = character_unit or hit_unit

		if character_unit:character_damage() and character_unit:character_damage().damage_melee then
			local dmg_multiplier = 1
			
			dmg_multiplier = dmg_multiplier * managers.player:upgrade_value("player", "melee_damage_multiplier", 1)

			if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
				self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
				self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
					nil,
					0
				}
				local stack = self._state_data.stacking_dmg_mul.melee

				if stack[1] and t < stack[1] then
					dmg_multiplier = dmg_multiplier * (1 + managers.player:upgrade_value("melee", "stacking_hit_damage_multiplier", 0) * stack[2])
				else
					stack[2] = 0
				end
			end

			local damage_health_ratio = managers.player:get_damage_health_ratio(self._ext_damage:health_ratio(), "melee")
			if damage_health_ratio > 0 then
				dmg_multiplier = dmg_multiplier * (1 + managers.player:upgrade_value("player", "melee_damage_health_ratio_multiplier", 0) * damage_health_ratio)
			end

			local target_dead = character_unit:character_damage().dead and not character_unit:character_damage():dead()
			local target_hostile = managers.enemy:is_enemy(character_unit) and not tweak_data.character[character_unit:base()._tweak_table].is_escort
			local life_leach_available = managers.player:has_category_upgrade("temporary", "melee_life_leech") and not managers.player:has_activate_temporary_upgrade("temporary", "melee_life_leech")

			if target_dead and target_hostile then
				if charger_melee then
					self._unit:movement():subtract_stamina(self._unit:movement():_max_stamina() * 0.15)
				end
				if life_leach_available then
					managers.player:activate_temporary_upgrade("temporary", "melee_life_leech")
					self._unit:character_damage():restore_health(managers.player:temporary_upgrade_value("temporary", "melee_life_leech", 1))
				end
			end

			local action_data = {}
			action_data.damage = shield_knock and 0 or damage * dmg_multiplier
			action_data.damage_effect = damage_effect
			action_data.attacker_unit = self._unit
			action_data.col_ray = col_ray

			if shield_knock then
				action_data.shield_knock = can_shield_knock
			end

			action_data.name_id = melee_entry
			action_data.charge_lerp_value = 0 --There is no charging this attack.

			if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
				self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
				self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
					nil,
					0
				}
				local stack = self._state_data.stacking_dmg_mul.melee

				if character_unit:character_damage().dead and not character_unit:character_damage():dead() then
					stack[1] = t + managers.player:upgrade_value("melee", "stacking_hit_expire_t", 1)
					stack[2] = math.min(stack[2] + 1, tweak_data.upgrades.max_melee_weapon_dmg_mul_stacks or 5)
				else
					stack[1] = nil
					stack[2] = 0
				end
			end

			local defense_data = character_unit:character_damage():damage_melee(action_data)

			self:_perform_sync_melee_damage(hit_unit, col_ray, action_data.damage)

			return defense_data
		else
			self:_perform_sync_melee_damage(hit_unit, col_ray, damage)
		end
	end

	if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
		self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
		self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
			nil,
			0
		}
		local stack = self._state_data.stacking_dmg_mul.melee
		stack[1] = nil
		stack[2] = 0
	end

	return col_ray
end

--Updated version of vanilla function, adding in melee sprinting, chainsaw, and repeat_hit functionality.
function PlayerStandard:_update_melee_timers(t, input)
	--Resume normal sprinting animations once melee attack is done.
	--Making it not cancel the equip animation will require a fair amount more work, since it doesn't set the timers. Is a job for another day.
	if self._running and not self._end_running_expire_t and not self._state_data.meleeing and self._state_data.melee_expire_t and t >= self._state_data.melee_expire_t and not self:_is_charging_weapon() and (not self:_is_reloading() or not self.RUN_AND_RELOAD) and (instant or not self._state_data.melee_repeat_expire_t) then
		if not self._equipped_unit:base():run_and_shoot_allowed() then
			self._ext_camera:play_redirect(self:get_animation("start_running"))
			self._equipped_unit:base():tweak_data_anim_stop("equip")
		else
			self._ext_camera:play_redirect(self:get_animation("idle"))
		end
	elseif self._state_data.meleeing then
		local lerp_value = self:_get_melee_charge_lerp_value(t)

		self._camera_unit:anim_state_machine():set_parameter(self:get_animation("melee_charge_state"), "charge_lerp", math.bezier({
			0,
			0,
			1,
			1
		}, lerp_value))

		if self._state_data.melee_charge_shake then
			self._ext_camera:shaker():set_parameter(self._state_data.melee_charge_shake, "amplitude", math.bezier({
				0,
				0,
				1,
				1
			}, lerp_value))
		end
	end

	local melee_weapon = tweak_data.blackmarket.melee_weapons[managers.blackmarket:equipped_melee_weapon()]
	local instant = melee_weapon.instant
	local melee_charger = melee_weapon.special_weapon and melee_weapon.special_weapon == "charger"
	local angle = self._stick_move and mvector3.angle(self._stick_move, math.Y)
	local moving_forwards = angle and angle <= 15
	local can_run = self._unit:movement():is_above_stamina_threshold()
	local lerp_value = self:_get_melee_charge_lerp_value(t)
	local max_charge = lerp_value and lerp_value >= 0.99

	-- No stamina regen while actively charging an attack with "charger" type melee weapons at max charge
	if melee_charger and self._state_data.meleeing and max_charge then
		self._unit:movement():_restart_stamina_regen_timer()
	end

	if self._state_data.meleeing then
		if lerp_value >= 1 and melee_weapon.special_weapon == "taser" and not self._stop_melee_sound_check then
			self._stop_melee_sound_check = true
			self._unit:sound():play("tasered_loop")
		end
	else
		if self._stop_melee_sound_check then
			self._unit:sound():play("tasered_stop")
			self._stop_melee_sound_check = nil
		end
	end

	--Trigger chainsaw damage and update timer.
	if self:_is_meleeing() and ((melee_weapon.chainsaw and not melee_charger) or (melee_charger and self._running and moving_forwards and can_run and max_charge)) and self._state_data.chainsaw_t and self._state_data.chainsaw_t < t then
		self:_do_chainsaw_damage(t)
		self._state_data.chainsaw_t = t + (melee_weapon.chainsaw.tick_delay * (1 + (1 - managers.player:upgrade_value("player", "melee_swing_multiplier", 1))))
	end

	if self._state_data.melee_damage_delay_t and self._state_data.melee_damage_delay_t <= t then
		self:_do_melee_damage(t, nil, self._state_data.melee_hit_ray)

		self._state_data.melee_damage_delay_t = nil
		self._state_data.melee_hit_ray = nil
	end

	if self._state_data.melee_attack_allowed_t and self._state_data.melee_attack_allowed_t <= t then
		self._state_data.melee_start_t = t
		local melee_charge_shaker = melee_weapon.melee_charge_shaker or "player_melee_charge"
		self._state_data.melee_charge_shake = self._ext_camera:play_shaker(melee_charge_shaker, 0)
		self._state_data.melee_attack_allowed_t = nil
	end

	if self._state_data.melee_repeat_expire_t and self._state_data.melee_repeat_expire_t <= t then
		self._state_data.melee_repeat_expire_t = nil
		if melee_weapon.force_play_charge then
			self._camera_unit:base():play_anim_melee_item("charge")
		end
		if input.btn_meleet_state then
			if melee_weapon.force_play_charge then
				self:_play_melee_sound(managers.blackmarket:equipped_melee_weapon(), "equip")
			end
			self._state_data.melee_charge_wanted = not instant and true
		end
	end
	if self._state_data.melee_expire_t and self._state_data.melee_expire_t <= t then
		self._state_data.melee_expire_t = nil
		self._state_data.melee_repeat_expire_t = nil

		self:_stance_entered()

		if self._equipped_unit and input.btn_steelsight_state then
			self._steelsight_wanted = true
		end
	end	
	if self._melee_repeat_damage_bonus and not self:_is_meleeing() then --Clear melee repeat bonus (from specialist knives and such) when melee is over.
		self._melee_repeat_damage_bonus = nil 
	end
end

function PlayerStandard:_interupt_action_melee(t)
	if not self:_is_meleeing() then
		return
	end

	self._state_data.melee_hit_ray = nil
	self._state_data.melee_charge_wanted = nil
	self._state_data.melee_expire_t = nil
	self._state_data.melee_repeat_expire_t = nil
	self._state_data.melee_attack_allowed_t = nil
	self._state_data.melee_damage_delay_t = nil
	self._state_data.meleeing = nil	
	self._state_data.chainsaw_t = nil --Stop chainsaw stuff if also no longer in melee.
	self._melee_repeat_damage_bonus = nil --Same goes for the melee repeat hitter bonus.
	if self._stop_melee_sound_check then
		self._unit:sound():play("tasered_stop")
		self._stop_melee_sound_check = nil
	end

	self._unit:sound():play("interupt_melee", nil, false)
	self:_play_melee_sound(managers.blackmarket:equipped_melee_weapon(), "hit_air", self._melee_attack_var)
	self._camera_unit:base():unspawn_melee_item()
	self._camera_unit:base():show_weapon()
	self:_play_equip_animation() --Use generic equip animation function.

	if self._state_data.melee_charge_shake then
		self._ext_camera:stop_shaker(self._state_data.melee_charge_shake)

		self._state_data.melee_charge_shake = nil
	end

	self:_stance_entered()

	--Interrupting melee attacks also interrupt melee sprinting.
	self:_interupt_action_running(t)
	local running = self._running and not self._end_running_expire_t
	if running then
		self._running_wanted = true
	end
end

function PlayerStandard:_start_action_jump(t, action_start_data)
	--Don't interrupt melee sprinting.
	if self._running and not self.RUN_AND_RELOAD and not self._equipped_unit:base():run_and_shoot_allowed() and not self._is_meleeing then
		self:_interupt_action_reload(t)
		self._ext_camera:play_redirect(self:get_animation("stop_running"), self._equipped_unit:base():exit_run_speed_multiplier())
	end

	self:_interupt_action_running(t)

	self._jump_t = t
	local jump_vec = action_start_data.jump_vel_z * math.UP

	self._unit:mover():jump()

	if self._move_dir then
		local move_dir_clamp = self._move_dir:normalized() * math.min(1, self._move_dir:length())
		self._last_velocity_xy = move_dir_clamp * action_start_data.jump_vel_xy
		self._jump_vel_xy = mvector3.copy(self._last_velocity_xy)
	else
		self._last_velocity_xy = Vector3()
	end

	self:_perform_jump(jump_vec)
end		

function PlayerStandard:_get_melee_charge_lerp_value(t, offset)
	offset = offset or 0
	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local max_charge_time = tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_time
	max_charge_time = max_charge_time * (1 + (1 - managers.player:upgrade_value("player", "melee_swing_multiplier", 1)))

	if not self._state_data.melee_start_t then
		return 0
	end

	return math.clamp(t - self._state_data.melee_start_t - offset, 0, max_charge_time) / max_charge_time
end

function PlayerStandard:_do_action_melee(t, input, skip_damage)
	self._state_data.meleeing = nil
	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local instant_hit = tweak_data.blackmarket.melee_weapons[melee_entry].instant
	local pre_calc_hit_ray = tweak_data.blackmarket.melee_weapons[melee_entry].hit_pre_calculation
	local melee_damage_delay = tweak_data.blackmarket.melee_weapons[melee_entry].melee_damage_delay or 0
	--Lets skills give faster melee charge and swing speeds.
	local charge_lerp_value = instant_hit and 0 or self:_get_melee_charge_lerp_value(t) 
	local charge_bonus_start = tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_bonus_start or 2 --i.e. never get the bonus
	local charge_bonus_speed = tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_bonus_speed or 1
	local speed = tweak_data.blackmarket.melee_weapons[melee_entry].speed_mult or 1
	local anim_speed = tweak_data.blackmarket.melee_weapons[melee_entry].anim_speed_mult or 1
	speed = speed * anim_speed
	speed = speed * managers.player:upgrade_value("player", "melee_swing_multiplier", 1)
	--Unsure if this is still needed since melee swings sync up now 
	--melee_damage_delay = melee_damage_delay * managers.player:upgrade_value("player", "melee_swing_multiplier_delay", 1)
	local melee_expire_t = tweak_data.blackmarket.melee_weapons[melee_entry].expire_t or 0 --Add fallbacks for certain stats.
	local melee_miss_expire_t = tweak_data.blackmarket.melee_weapons[melee_entry].miss_expire_t or 0
	local melee_repeat_expire_t = tweak_data.blackmarket.melee_weapons[melee_entry].repeat_expire_t or 0
	local melee_repeat_expire_t_add = tweak_data.blackmarket.melee_weapons[melee_entry].repeat_expire_t or 0
	local melee_miss_repeat_expire_t = tweak_data.blackmarket.melee_weapons[melee_entry].miss_repeat_expire_t or 0
	local weap_base = self._equipped_unit:base():weapon_tweak_data()
	if instant_hit then
		local weap_t = 1 * tweak_data.weapon.stats.mobility[self._equipped_unit:base():get_concealment() + 1]
		weap_t = math.clamp(weap_t, 0.6, 1.05)
		speed = speed * weap_t
	end
	--So the timers play nicely with the anim speed mult
	melee_expire_t = melee_expire_t / speed
	melee_miss_expire_t = melee_miss_expire_t / speed
	melee_repeat_expire_t = melee_repeat_expire_t / speed
	melee_miss_repeat_expire_t = melee_miss_repeat_expire_t / speed
	melee_damage_delay = melee_damage_delay / speed
	melee_damage_delay = math.min(melee_damage_delay, tweak_data.blackmarket.melee_weapons[melee_entry].repeat_expire_t)
	local primary = managers.blackmarket:equipped_primary()
	local primary_id = primary.weapon_id
	local bayonet_id = managers.blackmarket:equipped_bayonet(primary_id)
	local bayonet_melee = false
	local can_melee_miss = tweak_data.blackmarket.melee_weapons[melee_entry].can_melee_miss

	if bayonet_id and self._equipped_unit:base():selection_index() == 2 then
		bayonet_melee = true
	end
	
	self._melee_charge_bonus_range = false
	if charge_lerp_value and charge_lerp_value > charge_bonus_start then
		self._melee_charge_bonus_range = true
		speed = math.max(speed, speed * (charge_lerp_value * charge_bonus_speed))
		melee_damage_delay = math.min(melee_damage_delay, melee_damage_delay / (charge_lerp_value * charge_bonus_speed))
		melee_expire_t = math.min(melee_expire_t, melee_expire_t / (charge_lerp_value * charge_bonus_speed))
		melee_miss_expire_t = math.min(melee_miss_expire_t, melee_miss_expire_t / (charge_lerp_value * charge_bonus_speed))
		melee_repeat_expire_t = math.min(melee_repeat_expire_t, melee_repeat_expire_t / (charge_lerp_value * charge_bonus_speed))
		melee_miss_repeat_expire_t = math.min(melee_miss_repeat_expire_t, melee_miss_repeat_expire_t / (charge_lerp_value * charge_bonus_speed))
	end
	if not instant_hit and not skip_damage then
		self._state_data.melee_damage_delay_t = t + melee_damage_delay

		if pre_calc_hit_ray then
			self._state_data.melee_hit_ray = self:_calc_melee_hit_ray(t, 20) or true
		else
			self._state_data.melee_hit_ray = nil
		end
	end
	
	if can_melee_miss and self._state_data.melee_hit_ray == true then 
		melee_repeat_expire_t = melee_miss_repeat_expire_t
		melee_expire_t = melee_miss_expire_t
	end
	
	self._state_data.melee_expire_t = t + melee_expire_t
	self._state_data.melee_repeat_expire_t = t + math.min(melee_repeat_expire_t, melee_expire_t)

	local send_redirect = instant_hit and (bayonet_melee and "melee_bayonet" or "melee") or "melee_item"

	if instant_hit then
		managers.network:session():send_to_peers_synched("play_distance_interact_redirect", self._unit, send_redirect)
	else
		self._ext_network:send("sync_melee_discharge")
	end

	if self._state_data.melee_charge_shake then
		self._ext_camera:shaker():stop(self._state_data.melee_charge_shake)

		self._state_data.melee_charge_shake = nil
	end

	self._melee_attack_var = 0

	if instant_hit then
		local hit = skip_damage or self:_do_melee_damage(t, bayonet_melee)
		if hit then
			self._ext_camera:play_redirect(bayonet_melee and self:get_animation("melee_bayonet") or self:get_animation("melee"), math.clamp(speed, 0.7, 1.1))
		else
			self._ext_camera:play_redirect(bayonet_melee and self:get_animation("melee_miss_bayonet") or self:get_animation("melee_miss"), math.clamp(speed, 0.7, 1.1))
		end

		if can_melee_miss and not hit then 
			melee_repeat_expire_t = melee_miss_repeat_expire_t
			melee_expire_t = melee_miss_expire_t
		end
		self._state_data.melee_expire_t = t + melee_expire_t
		self._state_data.melee_repeat_expire_t = t + math.min(melee_repeat_expire_t, melee_expire_t)

	else
		local anim_attack_vars = tweak_data.blackmarket.melee_weapons[melee_entry].anim_attack_vars
		local anim_attack_charged_amount = tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_bonus_start or tweak_data.blackmarket.melee_weapons[melee_entry].anim_attack_charged_start or 0.5 --At half charge, use the charge variant
		local anim_attack_left_vars = tweak_data.blackmarket.melee_weapons[melee_entry].anim_attack_left_vars
		local anim_attack_right_vars = tweak_data.blackmarket.melee_weapons[melee_entry].anim_attack_right_vars
		local anim_attack_charged_vars = tweak_data.blackmarket.melee_weapons[melee_entry].anim_attack_charged_vars
		local anim_attack_charged_left_vars = tweak_data.blackmarket.melee_weapons[melee_entry].anim_attack_charged_left_vars
		local anim_attack_charged_right_vars = tweak_data.blackmarket.melee_weapons[melee_entry].anim_attack_charged_right_vars
		local timing_fix = tweak_data.blackmarket.melee_weapons[melee_entry].timing_fix
		local timing_fix_speed_mult = tweak_data.blackmarket.melee_weapons[melee_entry].timing_fix_speed_mult or 1
		self._melee_attack_var = anim_attack_vars and math.random(#anim_attack_vars)

		self:_play_melee_sound(melee_entry, "hit_air", self._melee_attack_var)

		local melee_item_tweak_anim = "attack"
		local melee_item_prefix = ""
		local melee_item_suffix = ""
		local anim_attack_param = anim_attack_vars and anim_attack_vars[self._melee_attack_var]
		local angle = mvector3.angle(self._stick_move, math.X)

		if anim_attack_charged_vars and charge_lerp_value >= anim_attack_charged_amount then
			self._melee_attack_var = anim_attack_charged_vars and math.random(#anim_attack_charged_vars)
			anim_attack_param = anim_attack_charged_vars and anim_attack_charged_vars[self._melee_attack_var]
			if anim_attack_charged_left_vars and angle and (angle <= 181) and (angle >= 134) then
				self._melee_attack_var = anim_attack_charged_left_vars and math.random(#anim_attack_charged_left_vars)
				anim_attack_param = anim_attack_charged_left_vars and anim_attack_charged_left_vars[self._melee_attack_var]
			elseif anim_attack_charged_right_vars and angle and (angle <= 45) and (angle >= 0) then
				self._melee_attack_var = anim_attack_charged_right_vars and math.random(#anim_attack_charged_right_vars)
				anim_attack_param = anim_attack_charged_right_vars and anim_attack_charged_right_vars[self._melee_attack_var]
			end
		elseif self._stick_move then
			if anim_attack_left_vars and angle and (angle <= 181) and (angle >= 134) then
				self._melee_attack_var = anim_attack_left_vars and math.random(#anim_attack_left_vars)
				anim_attack_param = anim_attack_left_vars and anim_attack_left_vars[self._melee_attack_var]
			elseif anim_attack_right_vars and angle and (angle <= 45) and (angle >= 0) then
				self._melee_attack_var = anim_attack_right_vars and math.random(#anim_attack_right_vars)
				anim_attack_param = anim_attack_right_vars and anim_attack_right_vars[self._melee_attack_var]
			end
		end
		local fix_anim_timer = anim_attack_param and timing_fix and table.contains(timing_fix, anim_attack_param)
		if fix_anim_timer then
			speed = speed * timing_fix_speed_mult
		end
		local state = self._ext_camera:play_redirect(self:get_animation("melee_attack"), speed) --Apply speed mult to animation.
		if anim_attack_param then
			self._camera_unit:anim_state_machine():set_parameter(state, anim_attack_param, 1)

			melee_item_prefix = anim_attack_param .. "_"
		end

		if self._state_data.melee_hit_ray and self._state_data.melee_hit_ray ~= true then
			self._camera_unit:anim_state_machine():set_parameter(state, "hit", 1)

			melee_item_suffix = "_hit"
		end

		melee_item_tweak_anim = melee_item_prefix .. melee_item_tweak_anim .. melee_item_suffix

		self._camera_unit:base():play_anim_melee_item(melee_item_tweak_anim, speed)
	end
end

--Updates burst fire and minigun spinup.
Hooks:PreHook(PlayerStandard, "update", "ResWeaponUpdate", function(self, t, dt)
	self:_update_burst_fire(t)
	self:_update_slide_locks()
		
	local weapon = self._equipped_unit and self._equipped_unit:base()
	local secondary = self._unit and self._unit:inventory():unit_by_selection(1):base()
	local primary = self._unit and self._unit:inventory():unit_by_selection(2):base()
	if weapon:get_name_id() == "m134" or weapon:get_name_id() == "shuno" then
		weapon:update_spin()
	end
	if primary then
		if primary._starwars then
			self:_primary_regen_ammo(t, dt)
		end
	end
	if secondary then
		if secondary._starwars then
			self:_secondary_regen_ammo(t, dt)
		end
	end
	self:_shooting_move_speed_timer(t, dt)
	self:_last_shot_t(t, dt)
	self:_update_d_scope_t(t, dt)
	self:_update_spread_stun_t(t, dt)

	if self._hit_in_air and not self._state_data.in_air then
		self._hit_in_air = nil
	end

	-- Shitty method to force the HUD to convey a weapon starts off on burstfire
	-- I know a boolean check would work to stop this going off every frame, but then the akimbo Type 54 fire modes stop updating correctly
	--[[
	if weapon and weapon:in_burst_mode() then
		managers.hud:set_teammate_weapon_firemode_burst(weapon:selection_index())
	end
	--]]

	--Applying (and removing) the conditon for being fully ADS'd
	if self:full_steelsight() and not self._state_data.in_full_steelsight then
		self._state_data.in_full_steelsight = true
	end
	if self._state_data.in_full_steelsight and not self:in_steelsight() then
		self._state_data.in_full_steelsight = nil
	end
	
end)

function PlayerStandard:_update_d_scope_t(t, dt, input)
	if self._d_scope_t then
		self:_interupt_action_steelsight(t)
		if self._steelsight_wanted ~= true and self._controller and self._controller:get_input_bool("secondary_attack") then
			self._steelsight_wanted = true
		end
		self._d_scope_t = self._d_scope_t - dt
		if self._d_scope_t < 0 then
			self._d_scope_t = nil
		end
	end
end


function PlayerStandard:_update_spread_stun_t(t, dt, input)
	if self._spread_stun_t then
		self._spread_stun_t = self._spread_stun_t - dt
		if self._spread_stun_t < 0 then
			self._spread_stun_t = nil
		end
	end
end

function PlayerStandard:_last_shot_t(t, dt)
	local weapon = self._equipped_unit and self._equipped_unit:base()
	local fire_mode = weapon and weapon:fire_mode()
	if weapon then
		if self._shooting and fire_mode == "auto" then
			local reset_delay_t = tweak_data.upgrades.automatic_kills_to_damage_reset_t or 1
			self._last_shooting_t = reset_delay_t
		else
			if self._last_shooting_t then
				self._last_shooting_t = self._last_shooting_t - dt
				if self._last_shooting_t < 0 then
					self._last_shooting_t = nil
					weapon._no_cheevo_kills_without_releasing_trigger = 0
				end
			end
		end
	end
end


function PlayerStandard:_shooting_move_speed_timer(t, dt)
	local weapon = self._equipped_unit and self._equipped_unit:base()
	if self._shooting and weapon._sms and (not self._is_sliding and not self._is_wallrunning and not self._is_wallkicking and not self:on_ladder()) then
		self._shooting_move_speed_t = math.min(0.75, weapon._smt)
		--self._shooting_move_speed_wait = weapon._smt * 0.15
		self._shooting_move_speed_mult = weapon._sms
	end
	if self._shooting_move_speed_wait then
		self._shooting_move_speed_wait = self._shooting_move_speed_wait - dt
		if self._shooting_move_speed_wait < 0 then
			self._shooting_move_speed_wait = nil
		end
	elseif self._shooting_move_speed_t then
		self._shooting_move_speed_t = self._shooting_move_speed_t - dt
		--self._shooting_move_speed_mult = self._shooting_move_speed_mult --too stupid to figure out the math to make 'self._shooting_move_speed_mult' transition to 1 as 'self._shooting_move_speed_t' counts down, pls help 
		if self._shooting_move_speed_t < 0 then
			self._shooting_move_speed_t = nil
			self._shooting_move_speed_mult = nil
		end
	end
end


function PlayerStandard:_primary_regen_ammo(t, dt)
	local primary = self._unit:inventory():unit_by_selection(2):base()
	local active = self._unit:inventory():equipped_selection() == 2
	primary._primary_regen_rate = primary._primary_regen_rate or primary._regen_rate or 10
	primary._primary_regenerate_ammo_timer = primary._primary_regenerate_ammo_timer or 0
	if primary:get_ammo_total() <= 0 then
		return
	end
	if active and self._shooting then
		primary._primary_recharge_yell = nil
		primary._primary_regenerate_ammo_timer = primary._regen_ammo_time or 0.5
	end
	if primary:clip_empty() then
		if active and self._shooting then
			self:_check_stop_shooting()
			self:_interupt_action_steelsight(t)
		end
		primary._primary_regen_rate = primary._regen_rate_overheat or 4.5
		primary._primary_overheat_pen = primary._overheat_pen or 2.75
	end
	if primary._primary_overheat_pen and primary._primary_overheat_pen <= 0 then
		--log( "COOL" )
		if active then
			primary._sound_fire:post_event("wp_sentrygun_swap_ammo")
		end
		primary._primary_regen_rate = primary._regen_rate or 10
		primary._primary_overheat_pen = nil
		primary._primary_overheat_yell = nil
	end
	if primary._primary_overheat_pen then
		primary._primary_overheat_pen = primary._primary_overheat_pen - dt
		--log( "OVERHEAT TIME: " .. tostring(self._primary_overheat_pen) )
		if not primary._primary_overheat_yell then
			managers.player:local_player():sound():say("g29",false,nil)
			primary._sound_fire:post_event("turret_cooldown")
			primary._primary_overheat_yell = true
		end
	end
	if (primary:get_ammo_remaining_in_clip() >= primary:get_ammo_total()) or (primary:get_ammo_remaining_in_clip() >= primary:get_ammo_max_per_clip()) then 
		--log("NO AMMO")
		primary._primary_regenerate_ammo_timer = nil
	end
	if primary._primary_regenerate_ammo_timer then
		primary._primary_regenerate_ammo_timer = primary._primary_regenerate_ammo_timer - dt
		if primary._primary_regenerate_ammo_timer < 0 then
			self:primary_add_ammo(dt * primary._primary_regen_rate)
			if not primary._primary_recharge_yell then
				primary._primary_recharge_yell = true
				if active then
					primary._sound_fire:post_event("night_vision_on")
				end
			end
		end
	end
end

function PlayerStandard:primary_add_ammo(value)
	local primary = self._unit:inventory():unit_by_selection(2):base()
	self._primary_add_bullet = self._primary_add_bullet or value
	if self._primary_add_bullet then
		self._primary_add_bullet = self._primary_add_bullet + value
		if math.floor(self._primary_add_bullet+0.5) >= 1 then
			primary:set_ammo_remaining_in_clip( primary:get_ammo_remaining_in_clip() + math.floor(self._primary_add_bullet+0.5))
			managers.hud:set_ammo_amount(primary:selection_index(), primary:ammo_info())
			self._primary_add_bullet = nil
		end
	end
end

function PlayerStandard:_secondary_regen_ammo(t, dt)
	local secondary = self._unit:inventory():unit_by_selection(1):base()
	local active = self._unit:inventory():equipped_selection() == 1
	secondary._secondary_regen_rate = secondary._secondary_regen_rate or secondary._regen_rate or 10
	secondary._secondary_regenerate_ammo_timer = secondary._secondary_regenerate_ammo_timer or 0
	if secondary:get_ammo_total() <= 0 then
		return
	end
	if active and self._shooting then
		secondary._secondary_recharge_yell = nil
		secondary._secondary_regenerate_ammo_timer = secondary._regen_ammo_time or 0.5
	end
	if secondary:clip_empty() then
		if active and self._shooting then
			self:_check_stop_shooting()
			self:_interupt_action_steelsight(t)
		end
		secondary._secondary_regen_rate = secondary._regen_rate_overheat or 4.5
		secondary._secondary_overheat_pen = secondary._overheat_pen or 2.75
	end
	if secondary._secondary_overheat_pen and secondary._secondary_overheat_pen <= 0 then
		--log( "COOL" )
		if active then
			secondary._sound_fire:post_event("wp_sentrygun_swap_ammo")
		end
		secondary._secondary_regen_rate = secondary._regen_rate or 10
		secondary._secondary_overheat_pen = nil
		secondary._secondary_overheat_yell = nil
	end
	if secondary._secondary_overheat_pen then
		secondary._secondary_overheat_pen = secondary._secondary_overheat_pen - dt
		--log( "OVERHEAT TIME: " .. tostring(self._secondary_overheat_pen) )
		if not secondary._secondary_overheat_yell then
			managers.player:local_player():sound():say("g29",false,nil)
			secondary._sound_fire:post_event("turret_cooldown")
			secondary._secondary_overheat_yell = true
		end
	end
	if (secondary:get_ammo_remaining_in_clip() >= secondary:get_ammo_total()) or (secondary:get_ammo_remaining_in_clip() >= secondary:get_ammo_max_per_clip()) then
		secondary._secondary_regenerate_ammo_timer = nil
	end
	if secondary._secondary_regenerate_ammo_timer then
		secondary._secondary_regenerate_ammo_timer = secondary._secondary_regenerate_ammo_timer - dt
		if secondary._secondary_regenerate_ammo_timer < 0 then
			self:secondary_add_ammo(dt * secondary._secondary_regen_rate)
			if not secondary._secondary_recharge_yell then
				secondary._secondary_recharge_yell = true
				if active then
					secondary._sound_fire:post_event("night_vision_on")
				end
			end
		end
	end
end

function PlayerStandard:secondary_add_ammo(value)
	local secondary = self._unit:inventory():unit_by_selection(1):base()
	self._secondary_add_bullet = self._secondary_add_bullet or value
	if self._secondary_add_bullet then
		self._secondary_add_bullet = self._secondary_add_bullet + value
		if math.floor(self._secondary_add_bullet+0.5) >= 1 then
			secondary:set_ammo_remaining_in_clip( secondary:get_ammo_remaining_in_clip() + math.floor(self._secondary_add_bullet+0.5))
			managers.hud:set_ammo_amount(secondary:selection_index(), secondary:ammo_info())
			self._secondary_add_bullet = nil
		end
	end
end

function PlayerStandard:_is_reloading()
	local primary = alive(self._unit) and self._unit:inventory():unit_by_selection(2):base()
	local secondary = alive(self._unit) and self._unit:inventory():unit_by_selection(1):base()
	return (primary and primary._primary_overheat_pen and self._unit:inventory():equipped_selection() == 2) or (secondary and secondary._secondary_overheat_pen and self._unit:inventory():equipped_selection() == 1) or self._state_data.reload_expire_t or self._state_data.reload_enter_expire_t or self._state_data.reload_exit_expire_t
end

function PlayerStandard:_in_burst()
	local in_burst = alive(self._equipped_unit) and self._equipped_unit:base():burst_rounds_remaining()
	return in_burst
end



--ADS speed stuff
function PlayerStandard:_stance_entered(unequipped, timemult)
	local stance_standard = tweak_data.player.stances.default[managers.player:current_state()] or tweak_data.player.stances.default.standard
	local head_stance = self._state_data.ducking and tweak_data.player.stances.default.crouched.head or stance_standard.head
	local stance_id = nil
	local stance_mod = {
		translation = Vector3(0, 0, 0),
		rotation = Rotation(0, 0, 0)
	}

	--[[
	local weap_base = self._equipped_unit and self._equipped_unit:base()
	local weap_tweak = weap_base and weap_base:weapon_tweak_data()
	local player_char = managers.criminals:local_character_name()
	if player_char and player_char == "jowi" and weap_tweak.jowi_grip and not self._state_data.in_steelsight then
		stance_mod.translation = stance_mod.translation + Vector3(-6, -3, -4)
		stance_mod.rotation = stance_mod.rotation * Rotation(0, 0, -15)
	end
	--]]

	local duration = tweak_data.player.TRANSITION_DURATION 
	local duration_multiplier = not self._state_data.in_full_steelsight and self._state_data.in_steelsight and 1 / self._equipped_unit:base():enter_steelsight_speed_multiplier() or 1
	
	if not unequipped then
		stance_id = self._equipped_unit:base():get_stance_id()

		if self._state_data.in_steelsight and self._equipped_unit:base().stance_mod then
			stance_mod = self._equipped_unit:base():stance_mod() or stance_mod
		end

		if self._equipped_unit:base()._has_big_scope and not self._state_data.in_steelsight then
			stance_mod.translation = stance_mod.translation + Vector3(1, 0, -2)
			stance_mod.rotation = stance_mod.rotation * Rotation(0, 0, 3)
		end
	end

	if AdvMov and AdvMov.settings then
		if not self._state_data.in_steelsight then
			if self._is_sliding and AdvMov.settings.slidewpnangle then
				stance_mod.translation = stance_mod.translation + Vector3(0, -3, 0)
				stance_mod.rotation = stance_mod.rotation * Rotation(0, 0, AdvMov.settings.slidewpnangle)
			end
			if self._is_wallrunning and AdvMov.settings.wallrunwpnangle then
				stance_mod.translation = stance_mod.translation + Vector3(0, -3, 0)
				stance_mod.rotation = stance_mod.rotation * Rotation(0, 0, -1 * AdvMov.settings.wallrunwpnangle)
			end
			if timemult then
				duration_multiplier = duration_multiplier * timemult
			end
		end
		if AdvMov.settings.goldeneye and ((AdvMov.settings.goldeneye == 2 and self._equipped_unit:base().akimbo) or AdvMov.settings.goldeneye == 3 or self._equipped_unit:base()._use_goldeneye_reload) and self:_is_reloading() then
			stance_mod.translation = Vector3(0, 0, -100)
			stance_mod.rotation = Rotation(0, 0, 0)
		end
	end

	local stances = nil
	stances = (self:_is_meleeing() or self:_is_throwing_projectile()) and tweak_data.player.stances.default or tweak_data.player.stances[stance_id] or tweak_data.player.stances.default
	local misc_attribs = stances.standard
	misc_attribs = (not self:_is_using_bipod() or self:_is_throwing_projectile() or stances.bipod) and (self._state_data.in_steelsight and stances.steelsight or self._state_data.ducking and stances.crouched or stances.standard)
	local new_fov = self:get_zoom_fov(misc_attribs) + 0

	self._camera_unit:base():clbk_stance_entered(misc_attribs.shoulders, head_stance, misc_attribs.vel_overshot, new_fov, misc_attribs.shakers, stance_mod, duration_multiplier, duration)
	managers.menu:set_mouse_sensitivity(self:in_steelsight())

	if PlayerStandard.set_ads_objects then
		local value = 0.155
		value = value / duration_multiplier
		if not unequipped then
			if self._state_data.in_steelsight then
				DelayedCalls:Add("FancyScopeCheckDelay", value, function()
					if self._state_data.in_steelsight then
						self:set_ads_objects(true)
					end
				end)
			else
				self:set_ads_objects(false)
			end
		end
	end
end
--Deals with burst fire hud stuff when swapping from an underbarrel back to a weapon in burst fire.
local _check_action_deploy_underbarrel_original = PlayerStandard._check_action_deploy_underbarrel	
function PlayerStandard:_check_action_deploy_underbarrel(...)
	local new_action = _check_action_deploy_underbarrel_original(self, ...)
	
	if new_action and alive(self._equipped_unit) and self._equipped_unit:base() and self._equipped_unit:base():in_burst_mode() then
		managers.hud:set_teammate_weapon_firemode_burst(self._equipped_unit:base():selection_index())
	end
	
	return new_action
end	

--Adds burst fire check.
function PlayerStandard:_check_action_weapon_firemode(t, input)
	local wbase = self._equipped_unit:base()
	local burst_hipfire = self._equipped_unit:base():weapon_tweak_data().BURST_FIRE_DISABLE_ADS and self._equipped_unit:base():in_burst_mode()
	if burst_hipfire then
		self:_interupt_action_steelsight(t)
		if input.btn_steelsight_state then
			self._steelsight_wanted = true
		end
	end
	if input.btn_weapon_firemode_press and wbase.toggle_firemode then
		self:_check_stop_shooting()
		if wbase:toggle_firemode() then
			if wbase:in_burst_mode() then
				managers.hud:set_teammate_weapon_firemode_burst(self._unit:inventory():equipped_selection())
			else
				local base_ext = self._equipped_unit:base()

				managers.hud:set_teammate_weapon_firemode(HUDManager.PLAYER_PANEL, self._unit:inventory():equipped_selection(), base_ext:fire_mode(), base_ext:alt_fire_active())
			end
		end
	end
end

--Fires next round in burst if needed. 
function PlayerStandard:_update_burst_fire(t)
	if alive(self._equipped_unit) and self._equipped_unit:base() then
		local burst_hipfire = self._equipped_unit:base():weapon_tweak_data().BURST_FIRE_DISABLE_ADS and self._equipped_unit:base():in_burst_mode()
		if burst_hipfire then
			self:_interupt_action_steelsight(t)
		end
		if self._equipped_unit:base():burst_rounds_remaining() or (self._equipped_unit:base():in_burst_mode() and self._equipped_unit:base()._auto_burst and not self._equipped_unit:base():clip_empty() and self._controller and self._controller:get_input_bool("primary_attack")) then
			self:_check_action_primary_attack(t, { btn_primary_attack_state = true, btn_primary_attack_press = true })
		end
	end
end

--Recoil used at the end of burst fire.
function PlayerStandard:force_recoil_kick(weap_base, shots_fired)
	local recoil_multiplier = (weap_base:recoil() + weap_base:recoil_addend()) * weap_base:recoil_multiplier() * (shots_fired or 1)
	local up, down, left, right = unpack(weap_base:weapon_tweak_data().kick[self._state_data.in_steelsight and "steelsight" or self._state_data.ducking and "crouching" or "standing"])
	self._camera_unit:base():recoil_kick(up * recoil_multiplier, down * recoil_multiplier, left * recoil_multiplier, right * recoil_multiplier)
end

function PlayerStandard:_check_action_deploy_bipod(t, input, autodeploy)
	local new_action = nil
	local action_forbidden = false

	if not input.btn_deploy_bipod then
		return
	end
	local is_leaning = TacticalLean and ((TacticalLean:GetLeanDirection() or TacticalLean:IsExitingLean()) and true) or nil

	action_forbidden = self._state_data.in_air or self._is_sliding or (autodeploy and self._move_dir) or is_leaning or self:_on_zipline() or self:_is_throwing_projectile() or self:_is_meleeing() or self:is_equipping() or self:_changing_weapon()

	local weapon = self._equipped_unit:base()
	local bipod_part = managers.weapon_factory:get_parts_from_weapon_by_perk("bipod", weapon._parts)
	if not action_forbidden then
		if bipod_part and bipod_part[1] then
			local bipod_unit = bipod_part[1].unit:base()

			bipod_unit:check_state(autodeploy)

			new_action = true
		end
	else
		if bipod_part and bipod_part [1] and not autodeploy then
			if self._state_data.in_air then
				managers.hud:show_hint({ time = 2, text = managers.localization:text("hud_hint_bipod_air") })
			elseif self._is_sliding then
				managers.hud:show_hint({ time = 2, text = managers.localization:text("hud_hint_bipod_slide") })
			elseif is_leaning then
				managers.hud:show_hint({ time = 2, text = managers.localization:text("hud_hint_bipod_lean") })
			end
		end
	end

	return new_action
end

function PlayerStandard:_check_action_steelsight(t, input)
	local new_action = nil
	if not restoration.Options:GetValue("OTHER/WeaponHandling/SeparateBowADS") then
		if alive(self._equipped_unit) then
			local result = nil
			local weap_base = self._equipped_unit:base()
	
			if weap_base.manages_steelsight and weap_base:manages_steelsight() then
				if input.btn_steelsight_press and weap_base.steelsight_pressed then
					result = weap_base:steelsight_pressed()
				elseif input.btn_steelsight_release and weap_base.steelsight_released then
					result = weap_base:steelsight_released()
				end
	
				if result then
					if result.enter_steelsight and not self._state_data.in_steelsight then
						self:_start_action_steelsight(t)
	
						new_action = true
					elseif result.exit_steelsight and self._state_data.in_steelsight then
						self:_end_action_steelsight(t)
	
						new_action = true
					end
				end
	
				return new_action
			end
		end
	end

	if managers.user:get_setting("hold_to_steelsight") and input.btn_steelsight_release then
		self._steelsight_wanted = false

		if self._state_data.in_steelsight then
			self:_end_action_steelsight(t)

			new_action = true
		end
	elseif input.btn_steelsight_press or self._steelsight_wanted then

		if self._state_data.in_steelsight then
			self:_end_action_steelsight(t)

			new_action = true
		elseif not self._state_data.in_steelsight then
			self:_start_action_steelsight(t)

			new_action = true
		end
	end

	return new_action
end

function PlayerStandard:_toggle_gadget(weap_base)
	local gadget_index = 0

	local second_sight_sprint = restoration.Options:GetValue("OTHER/WeaponHandling/SecondSightSprint")
	if not second_sight_sprint and weap_base.toggle_second_sight and self:in_steelsight() and weap_base:has_second_sight() and weap_base:toggle_second_sight(self) then
		return
	end

	if weap_base.toggle_gadget and weap_base:has_gadget() and weap_base:toggle_gadget(self) then
		gadget_index = weap_base:current_gadget_index()

		self._unit:network():send("set_weapon_gadget_state", weap_base._gadget_on)

		local gadget = weap_base:get_active_gadget()

		if gadget and gadget.color then
			local col = gadget:color()

			self._unit:network():send("set_weapon_gadget_color", col.r * 255, col.g * 255, col.b * 255)
		end

		if alive(self._equipped_unit) then
			managers.hud:set_ammo_amount(weap_base:selection_index(), weap_base:ammo_info())
		end
	end
end

function PlayerStandard:_start_action_steelsight(t, gadget_state)
	if self._equipped_unit and self._equipped_unit:base() then
		local speed_multiplier = self._equipped_unit:base():exit_run_speed_multiplier() or 1
		local sprintout_anim_time = self._equipped_unit:base():weapon_tweak_data().sprintout_anim_time or 0.4
		local orig_sprintout = sprintout_anim_time / speed_multiplier
		local burst_hipfire = self._equipped_unit:base():weapon_tweak_data().BURST_FIRE_DISABLE_ADS and self._equipped_unit:base():in_burst_mode()

		if burst_hipfire or (self._end_running_expire_t and (self._end_running_expire_t - t) > (orig_sprintout * 0.3)) then
			self._steelsight_wanted = true
			return
		end
	end
	--Here!
	if self:_changing_weapon() or self:_is_reloading() or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:_is_meleeing() or self._use_item_expire_t or self:_is_throwing_projectile() or self:_on_zipline() or self._d_scope_t then
		self._steelsight_wanted = true

		return
	end

	if self._running and not self._end_running_expire_t then
		self:_interupt_action_running(t)

		self._steelsight_wanted = true

		return
	end

	if not self:_is_using_bipod() and restoration.Options:GetValue("OTHER/WeaponHandling/AimDeploysBipod") and not self._moving then
		self:_check_action_deploy_bipod(t, {btn_deploy_bipod = true}, true)
	end

	self:_break_intimidate_redirect(t)

	self._steelsight_wanted = false
	self._state_data.in_steelsight = true

	if self._state_data.in_steelsight --[[or self._steelsight_wanted]] then
		local weapon = self._unit:inventory():equipped_unit():base()
		if weapon:get_name_id() == "m134" or weapon:get_name_id() == "shuno" then
			weapon:vulcan_enter_steelsight()
		end
	end

	self:_update_crosshair_offset()
	self:_stance_entered()
	self:_interupt_action_running(t)
	self:_interupt_action_cash_inspect(t)

	local weap_base = self._equipped_unit:base()

	if gadget_state ~= nil then
		weap_base:play_sound("gadget_steelsight_" .. (gadget_state and "enter" or "exit"))
	else
		weap_base:play_tweak_data_sound("enter_steelsight")
	end

	if weap_base:weapon_tweak_data().animations.has_steelsight_stance then
		self:_need_to_play_idle_redirect()

		self._state_data.steelsight_weight_target = 1

		self._camera_unit:base():set_steelsight_anim_enabled(true)
	end

	self._state_data.reticle_obj = weap_base.get_reticle_obj and weap_base:get_reticle_obj()

	if managers.controller:get_default_wrapper_type() ~= "pc" and managers.user:get_setting("aim_assist") then
		local closest_ray = self._equipped_unit:base():check_autoaim(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), nil, true)

		self._camera_unit:base():clbk_aim_assist(closest_ray)
	end

	self._ext_network:send("set_stance", 3, false, false)
	managers.job:set_memory("cac_4", true)
end

--Check for being fully ADS'd
function PlayerStandard:full_steelsight()
	local weap_base = self._equipped_unit:base()	
	local weap_hold = weap_base.weapon_hold and weap_base:weapon_hold() or weap_base:get_name_id()
	local is_bow = table.contains(weap_base:weapon_tweak_data().categories, "bow")
	local force_ads_recoil_anims = weap_base and weap_base:weapon_tweak_data().always_play_anims
	if weap_base and weap_base:alt_fire_active() and weap_base._alt_fire_data and weap_base._alt_fire_data.ignore_always_play_anims then
		force_ads_recoil_anims = nil
	end
	local is_turret = managers.player:current_state() and managers.player:current_state() == "player_turret"
	if restoration.Options:GetValue("OTHER/WeaponHandling/NoADSRecoilAnims") and self._shooting and self._state_data.in_steelsight and not weap_base.akimbo and not is_bow and not norecoil_blacklist[weap_hold] and not force_ads_recoil_anims and not is_turret then
		self._ext_camera:play_redirect(self:get_animation("idle"))
	end
	return self._state_data.in_steelsight and self._camera_unit:base():is_stance_done()
end


--Ends minigun spinup.
Hooks:PostHook(PlayerStandard, "_end_action_steelsight", "ResMinigunExitSteelsight", function(self, t, gadget_state)
	if not self._state_data.in_steelsight then
		local weapon = self._unit:inventory():equipped_unit():base()
		if weapon:get_name_id() == "m134" or weapon:get_name_id() == "shuno" then
			weapon:vulcan_exit_steelsight()
		end
	end
	local weap_base = self._equipped_unit:base()	
	local fire_mode = weap_base:fire_mode()
	local weap_hold = weap_base.weapon_hold and weap_base:weapon_hold() or weap_base:get_name_id()
	local is_bow = table.contains(weap_base:weapon_tweak_data().categories, "bow")
	local force_ads_recoil_anims = weap_base and weap_base:weapon_tweak_data().always_play_anims
	if weap_base and weap_base:alt_fire_active() and weap_base._alt_fire_data and weap_base._alt_fire_data.ignore_always_play_anims then
		force_ads_recoil_anims = nil
	end

	if fire_mode == "auto" and not weap_base:weapon_tweak_data().no_auto_anims then
		if restoration.Options:GetValue("OTHER/WeaponHandling/NoADSRecoilAnims") and self._shooting and not self._state_data.in_steelsight and not weap_base.akimbo and not is_bow and not norecoil_blacklist[weap_hold] and not force_ads_recoil_anims then
			self._ext_camera:play_redirect(self:get_animation("recoil_enter"))
		end
	end
end)

function PlayerStandard:_update_slide_locks()
	local weap_base = self._equipped_unit:base()
	if weap_base and weap_base:weapon_tweak_data().lock_slide and not self:_is_reloading() then
		if (weap_base.AKIMBO and weap_base:ammo_base():get_ammo_remaining_in_clip() > 1) or (not weap_base.AKIMBO and not weap_base:clip_empty()) then
			weap_base:tweak_data_anim_stop("magazine_empty")
			if weap_base:weapon_tweak_data().open_bolt_offset then
				weap_base:tweak_data_anim_offset("reload", weap_base:weapon_tweak_data().open_bolt_offset or 5)
			else
				weap_base:tweak_data_anim_stop("reload")
				weap_base:tweak_data_anim_stop("reload_left")
			end
			if weap_base.AKIMBO then
				weap_base._second_gun:base():tweak_data_anim_stop("magazine_empty")
				weap_base._second_gun:base():tweak_data_anim_stop("reload")
				weap_base._second_gun:base():tweak_data_anim_stop("reload_left")
			end
		end
		if --[[not weap_base._starwars and]] not self:_is_reloading() then
			if weap_base.AKIMBO and weap_base:ammo_base():get_ammo_remaining_in_clip() == 1 then
				weap_base:tweak_data_anim_stop("fire")
				weap_base:tweak_data_anim_stop("magazine_empty")
				weap_base._second_gun:base():tweak_data_anim_stop("magazine_empty") 
				if weap_base._fire_second_gun_next == false then
					weap_base:tweak_data_anim_offset("reload_left", 0.033, true)
				else
					weap_base:tweak_data_anim_offset("reload_left", 0.033)
				end
			elseif weap_base:clip_empty() then
				weap_base:tweak_data_anim_stop("fire")
				weap_base:tweak_data_anim_stop("magazine_empty")
				weap_base:tweak_data_anim_stop("reload")
				weap_base:tweak_data_anim_stop("reload_left")
				if weap_base:weapon_tweak_data().lock_slide_reload_objects then
					weap_base:set_reload_objects_visible(true)
				end
				if weap_base.AKIMBO then
					weap_base._second_gun:base():tweak_data_anim_stop("magazine_empty")
					weap_base._second_gun:base():tweak_data_anim_offset("reload", 0.1033) 
					weap_base:tweak_data_anim_offset("reload", 0.033)
					--weap_base:tweak_data_anim_offset("reload_left", 0.033, true)
					if (weap_base:weapon_tweak_data().animations and weap_base:weapon_tweak_data().animations.magazine_empty and weap_base:weapon_tweak_data().lock_slide_alt) then
						weap_base:tweak_data_anim_offset("magazine_empty", 1)
						weap_base._second_gun:base():tweak_data_anim_offset("magazine_empty", 1)
					end
				else
					if (weap_base:weapon_tweak_data().animations and weap_base:weapon_tweak_data().animations.magazine_empty and weap_base:weapon_tweak_data().lock_slide_alt) then
						weap_base:tweak_data_anim_offset("magazine_empty", 1)
					elseif weap_base:weapon_tweak_data().lock_slide_fire then
						weap_base:tweak_data_anim_offset("fire", weap_base:weapon_tweak_data().lock_slide_offset or 0.033)
					else 
						weap_base:tweak_data_anim_offset("reload", weap_base:weapon_tweak_data().lock_slide_offset or 0.033)
					end
				end
			end
		end	
	end
end

function PlayerStandard:_calc_melee_hit_ray(t, sphere_cast_radius)
	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local weap_base = self._equipped_unit:base()
	local wtd = weap_base:weapon_tweak_data()
	local wtd_base_range = wtd and math.max(wtd.jab_range or 0, 0)
	local active_weapon = self._unit:inventory():equipped_selection() == 1 and managers.blackmarket:equipped_secondary() or managers.blackmarket:equipped_primary()
	local active_weapon_stats = active_weapon and melee_entry == "weapon" and managers.weapon_factory:get_stats(active_weapon.factory_id, active_weapon.blueprint)
	local active_weapon_range = active_weapon_stats and math.max((active_weapon_stats and active_weapon_stats.jab_range or active_weapon_stats.bayonet_range) or 0, 0) or 0
	local range = tweak_data.blackmarket.melee_weapons[melee_entry].stats.range or 150
	local sphere_cast_radius_add = tweak_data.blackmarket.melee_weapons[melee_entry].sphere_cast_radius_add
	if sphere_cast_radius_add then
		sphere_cast_radius = sphere_cast_radius + sphere_cast_radius_add
		range = range - sphere_cast_radius_add
	end
	range = range + wtd_base_range + active_weapon_range
	local charge_bonus_range = tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_bonus_range or 0
	if self._melee_charge_bonus_range and self._melee_charge_bonus_range == true then
		range = range + charge_bonus_range
	end
	local from = self._unit:movement():m_head_pos()
	local to = from + self._unit:movement():m_head_rot():y() * range

	return self._unit:raycast("ray", from, to, "slot_mask", self._slotmask_bullet_impact_targets, "sphere_cast_radius", sphere_cast_radius, "ray_type", "body melee")
end


local melee_vars = {
	"player_melee",
	"player_melee_var2"
}
function PlayerStandard:_do_melee_damage(t, bayonet_melee, melee_hit_ray, melee_entry, hand_id)
	melee_entry = melee_entry or managers.blackmarket:equipped_melee_weapon()
	local instant_hit = tweak_data.blackmarket.melee_weapons[melee_entry].instant
	local melee_damage_delay = tweak_data.blackmarket.melee_weapons[melee_entry].melee_damage_delay or 0
	local charge_lerp_value = instant_hit and 0 or self:_get_melee_charge_lerp_value(t, melee_damage_delay)
	local sphere_cast_radius = 20
	local col_ray = nil
	local make_effect = bayonet_melee or tweak_data.blackmarket.melee_weapons[melee_entry].make_effect or nil
	local make_decal = tweak_data.blackmarket.melee_weapons[melee_entry].make_decal or nil
	local make_saw = tweak_data.blackmarket.melee_weapons[melee_entry].make_saw or nil --not implemented yet
	--Melee weapon tweakdata.
	local melee_weapon = tweak_data.blackmarket.melee_weapons[melee_entry]
	--Holds info for certain melee gimmicks (IE: Taser Shock, Psycho Knife Panic, ect)
	local special_weapon = melee_weapon.special_weapon
	self._state_data._charger_melee_active = nil

	-- If true, disables the shaker when a melee weapon connects
	if not melee_weapon.no_hit_shaker then
		self._ext_camera:play_shaker(melee_vars[math.random(#melee_vars)], math.max(0.3, charge_lerp_value))
	end
	
	if melee_hit_ray then
		col_ray = melee_hit_ray ~= true and melee_hit_ray or nil
	else
		col_ray = self:_calc_melee_hit_ray(t, sphere_cast_radius)
	end
	if col_ray and alive(col_ray.unit) then
		local damage, damage_effect = managers.blackmarket:equipped_melee_weapon_damage_info(charge_lerp_value)
		local damage_effect_mul = math.max(managers.player:upgrade_value("player", "melee_knockdown_mul", 1), managers.player:upgrade_value(self._equipped_unit:base():weapon_tweak_data().categories and self._equipped_unit:base():weapon_tweak_data().categories[1], "melee_knockdown_mul", 1))
		damage = damage * managers.player:get_melee_dmg_multiplier()
		damage_effect = damage_effect * damage_effect_mul
		col_ray.sphere_cast_radius = sphere_cast_radius
		local hit_unit = col_ray.unit
		if hit_unit:character_damage() then
			if bayonet_melee then
				self._unit:sound():play("fairbairn_hit_body", nil, false)
			elseif special_weapon == "taser" and charge_lerp_value ~= 1 then --Feedback for non-charged attacks with shock weapons. Might not do anything, need to verify.
				self._unit:sound():play("melee_hit_gen", nil, false)
			else
				self:_play_melee_sound(melee_entry, "hit_body")
			end
			if not hit_unit:character_damage()._no_blood then
				managers.game_play_central:play_impact_flesh({col_ray = col_ray})
				managers.game_play_central:play_impact_sound_and_effects({
					col_ray = col_ray,
					no_decal = true,
					no_sound = true
				})
			end
			self._camera_unit:base():play_anim_melee_item("hit_body")
		else
			if self._on_melee_restart_drill and hit_unit:base() and (hit_unit:base().is_drill or hit_unit:base().is_saw) then
				hit_unit:base():on_melee_hit(managers.network:session():local_peer():id())
			end		
		
			if bayonet_melee then
				self._unit:sound():play("knife_hit_gen", nil, false)
			elseif special_weapon == "taser" and charge_lerp_value ~= 1 then --Feedback for non-charged attacks with shock weapons. Might not do anything, need to verify.
					self._unit:sound():play("melee_hit_gen", nil, false)
			else
				self:_play_melee_sound(melee_entry, "hit_gen")
			end
			managers.game_play_central:play_impact_sound_and_effects({
				decal = make_saw and "saw",
				col_ray = col_ray,
				effect = (not make_effect and not make_saw and Idstring("effects/payday2/particles/impacts/fallback_impact_pd2")) or nil,
				no_decal = (not make_decal and not make_saw) and true,
				no_sound = true
			})
		end

		--Out of date syncing method, reenable in case it was load bearing.
		--[[if hit_unit:damage() and col_ray.body:extension() and col_ray.body:extension().damage then
			col_ray.body:extension().damage:damage_melee(self._unit, col_ray.normal, col_ray.position, col_ray.ray, damage)
			if hit_unit:id() ~= -1 then
				managers.network:session():send_to_peers_synched("sync_body_damage_melee", col_ray.body, self._unit, col_ray.normal, col_ray.position, col_ray.ray, damage)
			end
		end]]

		local custom_data = nil
			
		if _G.IS_VR then
			local melee_hand_id = self._unit:hand():get_active_hand_id("melee")
			melee_hand_id = melee_hand_id or self._unit:hand():get_active_hand_id("weapon")

			if melee_hand_id then
				custom_data = {engine = melee_hand_id == 1 and "right" or "left"}
			end
		end			

		managers.rumble:play("melee_hit", nil, nil, custom_data)
		managers.game_play_central:physics_push(col_ray)
		
		local character_unit, shield_knock
		local can_shield_knock = managers.player:has_category_upgrade("player", "shield_knock")
		if can_shield_knock and hit_unit:in_slot(8) and alive(hit_unit:parent()) then
			shield_knock = true
			character_unit = hit_unit:parent()
		end
		character_unit = character_unit or hit_unit
		if character_unit:character_damage() and character_unit:character_damage().damage_melee then
			local dmg_multiplier = self._melee_repeat_damage_bonus or 1

			dmg_multiplier = dmg_multiplier * managers.player:upgrade_value("player", "melee_damage_multiplier", 1)

			if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
				self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
				self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {nil, 0}
				local stack = self._state_data.stacking_dmg_mul.melee
				if stack[1] and t < stack[1] then
					dmg_multiplier = dmg_multiplier * (1 + managers.player:upgrade_value("melee", "stacking_hit_damage_multiplier", 0) * stack[2])
				else
					stack[2] = 0
				end
			end

			local damage_health_ratio = managers.player:get_damage_health_ratio(self._ext_damage:health_ratio(), "melee")
			if damage_health_ratio > 0 then
				dmg_multiplier = dmg_multiplier * (1 + managers.player:upgrade_value("player", "melee_damage_health_ratio_multiplier", 0) * damage_health_ratio)
			end

			if character_unit:character_damage().dead and not character_unit:character_damage():dead() and managers.enemy:is_enemy(character_unit) and managers.player:has_category_upgrade("temporary", "melee_life_leech") and not managers.player:has_activate_temporary_upgrade("temporary", "melee_life_leech") then
				managers.player:activate_temporary_upgrade("temporary", "melee_life_leech")
				self._unit:character_damage():restore_health(managers.player:temporary_upgrade_value("temporary", "melee_life_leech", 1))
			end

			--Do melee gimmick stuff. Might be worth it to use function references instead of branching later on if we get more of these.
			local action_data = {}
			action_data.variant = "melee"

			if special_weapon == "repeat_hitter" then
				self._melee_repeat_damage_bonus = 2.0
			elseif special_weapon == "talk" and character_unit:character_damage().dead and not character_unit:character_damage():dead() and managers.enemy:is_enemy(character_unit) and math.random() <= 0.2 then
				self._unit:sound():say("f46x_any", true)
			elseif special_weapon == "hyper_crit" and math.random() <= 0.05 then
				dmg_multiplier = dmg_multiplier * 10
				damage_effect = damage_effect * 10
				self._unit:sound():play("bell_ring")
			end
			
			if charge_lerp_value >= 0.99 then
				if special_weapon == "taser" then
					action_data.variant = "taser_tased"
				elseif special_weapon == "panic" then
					managers.player:spread_psycho_knife_panic()
				end
			end
				
			if _G.IS_VR and melee_entry == "weapon" and not bayonet_melee then
				dmg_multiplier = 0.1
			end				
			
			action_data.damage = shield_knock and 0 or damage * dmg_multiplier
			action_data.damage_effect = damage_effect
			action_data.attacker_unit = self._unit
			action_data.col_ray = col_ray
			action_data.shield_knock = can_shield_knock --Silly vanilla code using branching when it doesn't need to.
			action_data.name_id = melee_entry
			action_data.charge_lerp_value = charge_lerp_value
			--Damage multipliers for certain melees (IE: Butterfly Knife).
			action_data.backstab_multiplier = melee_weapon.backstab_damage_multiplier or 1
			action_data.headshot_multiplier = melee_weapon.headshot_damage_multiplier or 1
			if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
				self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
				self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {nil, 0}
				local stack = self._state_data.stacking_dmg_mul.melee
				if character_unit:character_damage().dead and not character_unit:character_damage():dead() then
					stack[1] = t + managers.player:upgrade_value("melee", "stacking_hit_expire_t", 1)
					stack[2] = math.min(stack[2] + 1, tweak_data.upgrades.max_melee_weapon_dmg_mul_stacks or 5)
				else
					stack[1] = nil
					stack[2] = 0
				end
			end
			local defense_data = character_unit:character_damage():damage_melee(action_data)
			self:_check_melee_dot_damage(col_ray, defense_data, melee_entry)
			self:_perform_sync_melee_damage(hit_unit, col_ray, action_data.damage, action_data.damage_effect)
			
			local charge_fire_check = (tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_bonus_fire and charge_lerp_value > tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_bonus_start) or (not tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_bonus_fire and true)
			if tweak_data.blackmarket.melee_weapons[melee_entry].fire_dot_data and charge_fire_check and character_unit:character_damage().damage_fire then
				local action_data = {
					variant = "fire",
					damage = 0,
					attacker_unit = self._unit,
					col_ray = col_ray,
					fire_dot_data = tweak_data.blackmarket.melee_weapons[melee_entry].fire_dot_data
				}

				character_unit:character_damage():damage_fire(action_data)
			end		

			return defense_data
		else
			self:_perform_sync_melee_damage(hit_unit, col_ray, damage, damage_effect)
		end
	else
	end
	if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
		self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
		self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {nil, 0}
		local stack = self._state_data.stacking_dmg_mul.melee
		stack[1] = nil
		stack[2] = 0
	end
	return col_ray
end


function PlayerStandard:_perform_sync_melee_damage(hit_unit, col_ray, damage, damage_effect)
	if hit_unit:damage() and col_ray.body:extension() and col_ray.body:extension().damage then
		damage = math.clamp(damage, PlayerStandard.MINMAX_MELEE_SYNC[1], PlayerStandard.MINMAX_MELEE_SYNC[2])
		if damage_effect then
			damage_effect = math.clamp(damage_effect, PlayerStandard.MINMAX_MELEE_SYNC[1], PlayerStandard.MINMAX_MELEE_SYNC[2])
			col_ray.body:extension().damage:damage_damage(self._unit, col_ray.normal, col_ray.position, col_ray.ray, damage_effect)
		end

		col_ray.body:extension().damage:damage_melee(self._unit, col_ray.normal, col_ray.position, col_ray.ray, damage)
		managers.network:session():send_to_peers_synched("sync_body_damage_melee", col_ray.body, self._unit, col_ray.normal, col_ray.position, col_ray.ray, damage, damage_effect)
	end
end

--Now also returns steelsight information. Used for referencing spread values to give steelsight bonuses.
function PlayerStandard:get_movement_state()
	if not self._spread_stun_t and self._state_data.in_steelsight and self._state_data.in_full_steelsight then
		return self._moving and "moving_steelsight" or "steelsight"
	end

	if self._state_data.ducking then
		return self._moving and "moving_crouching" or "crouching"
	else
		return self._moving and "moving_standing" or "standing"
	end
end

--Initiate dodge stuff when player enters a state where they can begin dodging stuff.
--Crashes here indicate syntax errors in playerdamage.
Hooks:PostHook(PlayerStandard, "_enter", "ResDodgeInit", function(self, enter_data)
	self._ext_damage:set_dodge_points()
end)

function PlayerStandard:_update_reload_timers(t, dt, input)
	if self._state_data.reload_enter_expire_t and self._state_data.reload_enter_expire_t <= t then
		self._equipped_unit:base():tweak_data_anim_stop("fire")
		self._equipped_unit:base():tweak_data_anim_stop("fire_steelsight")
		self._state_data.reload_enter_expire_t = nil
		self:_start_action_reload(t)
	end
	
	--Moved earlier in function to avoid math on nil value.
	local speed_multiplier = self._equipped_unit:base():reload_speed_multiplier()
	
	if self._state_data.reload_expire_t then
		local interupt = nil
		local reload_fix_offset = self._equipped_unit:base():weapon_tweak_data().reload_fix_offset
		local reload_fix_offset2 = self._equipped_unit:base():weapon_tweak_data().reload_fix_offset2
		local always_use_empty_reload = self._equipped_unit:base():weapon_tweak_data().always_use_empty_reload
		if reload_fix_offset then
			self._equipped_unit:base():tweak_data_anim_stop("reload")
		end
		if self._equipped_unit:base():update_reloading(t, dt, self._state_data.reload_expire_t - t) then
			managers.hud:set_ammo_amount(self._equipped_unit:base():selection_index(), self._equipped_unit:base():ammo_info())
			if self._queue_reload_interupt then
				self._queue_reload_interupt = nil
				interupt = true
			end
		end
		if self._state_data.reload_expire_t <= t or interupt then
			managers.player:remove_property("shock_and_awe_reload_multiplier")
			self._state_data.reload_expire_t = nil

			if (self._equipped_unit:base():weapon_tweak_data().empty_use_mag and self._equipped_unit:base():clip_empty()) or (not self._equipped_unit:base()._use_shotgun_reload and self._equipped_unit:base():reload_exit_expire_t() and self._equipped_unit:base():reload_not_empty_exit_expire_t()) then
				local is_reload_not_empty = not self._equipped_unit:base():clip_empty()
				if not interupt then
					self._equipped_unit:base():on_reload()
				end
				self._state_data.reload_exit_expire_t = t + ((is_reload_not_empty and self._equipped_unit:base():reload_not_empty_exit_expire_t()) or (self._equipped_unit:base():reload_exit_expire_t() or empty_use_mag_timer)) / speed_multiplier
				managers.statistics:reloaded()
				managers.hud:set_ammo_amount(self._equipped_unit:base():selection_index(), self._equipped_unit:base():ammo_info())
			elseif self._equipped_unit:base():reload_exit_expire_t() then
				local is_reload_not_empty = not self._equipped_unit:base():started_reload_empty()
				local animation_name = (not always_use_empty_reload and is_reload_not_empty and "reload_not_empty_exit") or "reload_exit"
				local animation = self:get_animation(animation_name)
				
				self._state_data.reload_exit_expire_t = t + ((is_reload_not_empty and self._equipped_unit:base():reload_not_empty_exit_expire_t()) or self._equipped_unit:base():reload_exit_expire_t()) / speed_multiplier

				local result = self._ext_camera:play_redirect(animation, speed_multiplier)
				
				self._equipped_unit:base():tweak_data_anim_play(animation_name, speed_multiplier, nil, reload_fix_offset2)

				if reload_fix_offset then
					local reload_anim = is_reload_not_empty and "reload_not_empty" or "reload"
					self._equipped_unit:base():tweak_data_anim_play(reload_anim, speed_multiplier, reload_fix_offset)
				end
				
				
			elseif self._state_data.reload_expire_t and self._state_data.reload_expire_t <= t then --Update timers in case player total ammo changes to allow for more to be reloaded.
				self._state_data.reload_expire_t = t + (self._equipped_unit:base():reload_expire_t() or 2.2) / speed_multiplier		
				
			elseif self._equipped_unit then
				if not interupt then
					self._equipped_unit:base():on_reload()
				end
				managers.statistics:reloaded()
				managers.hud:set_ammo_amount(self._equipped_unit:base():selection_index(), self._equipped_unit:base():ammo_info())
				if input.btn_steelsight_state then
					self._steelsight_wanted = true
				elseif self.RUN_AND_RELOAD and self._running and not self._end_running_expire_t and not self._equipped_unit:base():run_and_shoot_allowed() then
					self._ext_camera:play_redirect(self:get_animation("start_running"))
				end
			end
		end
	end
	if self._state_data.reload_exit_expire_t and self._state_data.reload_exit_expire_t <= t then
		self._state_data.reload_exit_expire_t = nil
		if self._equipped_unit then
			managers.statistics:reloaded()
			managers.hud:set_ammo_amount(self._equipped_unit:base():selection_index(), self._equipped_unit:base():ammo_info())
			if input.btn_steelsight_state then
				self._steelsight_wanted = true
			elseif self.RUN_AND_RELOAD and self._running and not self._end_running_expire_t and not self._equipped_unit:base():run_and_shoot_allowed() then
				self._ext_camera:play_redirect(self:get_animation("start_running"))
			end
			if self._equipped_unit:base().on_reload_stop then
				self._equipped_unit:base():on_reload_stop()
			end
		end
	end
	if not self._state_data.reload_expire_t and not self._state_data.reload_exit_expire_t then
		if self._equipped_unit and self._equipped_unit:base().set_reload_objects_visible and self._equipped_unit:base()._ignore_reload_objects then
			self._equipped_unit:base():tweak_data_anim_stop("reload")
			self._equipped_unit:base():set_reload_objects_visible(false)
		end
	end
end

--Fixes weapons with manually actuated parts (visually) like pumps and bolt-actions still animating upon starting a reload
--Also includes fix for Bloodthirst's reload bonus
Hooks:PostHook(PlayerStandard, "_start_action_reload_enter", "ResStopFireAnimReloadFix", function(self, t)
	local weap_base = self._equipped_unit:base()
	if weap_base and weap_base:can_reload() then
		weap_base:tweak_data_anim_stop("fire")
		weap_base:tweak_data_anim_stop("fire_steelsight")
		if weap_base.AKIMBO then
			weap_base._second_gun:base():tweak_data_anim_stop("magazine_empty")
			weap_base._second_gun:base():tweak_data_anim_stop("reload")
		end
		weap_base._current_reload_speed_multiplier = nil
	end
end)

function PlayerStandard:_start_action_reload(t)
	local weapon = self._equipped_unit:base()

	if weapon and weapon:can_reload() then
		local weapon_tweak = weapon:weapon_tweak_data()
		local anims_tweak = weapon_tweak.animations or {}
		local ignore_fullreload = anims_tweak.ignore_fullreload
		local ignore_nonemptyreload = anims_tweak.ignore_nonemptyreload
		local clip_empty = weapon:clip_empty()
		if ((ignore_fullreload and clip_empty) or (ignore_nonemptyreload and not clip_empty)) then
			weapon:tweak_data_anim_stop("fire")
	
			local speed_multiplier = weapon:reload_speed_multiplier()
			local reload_prefix = weapon:reload_prefix() or ""
			local reload_name_id = anims_tweak.reload_name_id or weapon.name_id
	
			local expire_t = weapon_tweak.timers.reload_not_empty or weapon:reload_expire_t() or (ignore_fullreload and 2.2 or 2.8)
			local reload_anim = ignore_fullreload and "reload_not_empty" or "reload"
	
			weapon:start_reload()

			self._ext_camera:play_redirect(Idstring(reload_prefix .. reload_anim .. "_" .. reload_name_id), speed_multiplier)
			self._state_data.reload_expire_t = t + expire_t / speed_multiplier
	
			if not weapon:tweak_data_anim_play(reload_anim, speed_multiplier) then
				weapon:tweak_data_anim_play("reload", speed_multiplier)
			end
	
			self._ext_network:send("reload_weapon", ignore_fullreload and 0 or 1, speed_multiplier)
	
			return
		else
			local is_reload_not_empty = weapon:clip_not_empty()
		
			weapon:tweak_data_anim_stop("fire")
			weapon:tweak_data_anim_stop("fire_steelsight")
	
			local speed_multiplier = weapon:reload_speed_multiplier()
			local empty_reload = weapon:clip_empty() and 1 or 0
	
			if weapon:use_shotgun_reload() then
				empty_reload = weapon:get_ammo_max_per_clip() - weapon:get_ammo_remaining_in_clip()
			end
	
			local tweak_data = weapon:weapon_tweak_data()
			local reload_anim = "reload"
			local reload_prefix = weapon:reload_prefix() or ""
			local reload_name_id = tweak_data.animations.reload_name_id or weapon.name_id
			local reload_default_expire_t = 2.6
			local reload_tweak = tweak_data.timers.reload_empty		
			
			weapon:start_reload() --Executed earlier to get accurate reload timers, otherwise may mess up normal and tactical for shotguns.
	
			if is_reload_not_empty then
				reload_anim = "reload_not_empty"
				reload_default_expire_t = 2.2
				reload_tweak = tweak_data.timers.reload_not_empty
			end
	
			local reload_ids = Idstring(string.format("%s%s_%s", reload_prefix, reload_anim, reload_name_id))
			local result = self._ext_camera:play_redirect(reload_ids, speed_multiplier)
	
			Application:trace("PlayerStandard:_start_action_reload( t ): ", reload_ids)
	
			self._state_data.reload_expire_t = t + (reload_tweak or weapon:reload_expire_t(is_reload_not_empty) or reload_default_expire_t) / speed_multiplier
	
			if not weapon:tweak_data_anim_play(reload_anim, speed_multiplier) then
				weapon:tweak_data_anim_play("reload", speed_multiplier)
				Application:trace("PlayerStandard:_start_action_reload( t ): ", reload_anim)
			end
	
			self._ext_network:send("reload_weapon", empty_reload, speed_multiplier)
		end
	end

	--Drop My Mag compatibilty
	--I might take the time to better integrate this into the reload timers so you're not instantly dropping a mag right when you reload
	for _, weapon_base in ipairs({ weapon, weapon._second_gun and weapon._second_gun:base() }) do
		if weapon_base and weapon_base.DMM_can_drop_magazine and weapon_base:DMM_can_drop_magazine() then
			weapon_base:drop_magazine_object()
		end
 	end
end

function PlayerStandard:_get_swap_speed_multiplier()
	local multiplier = 1
	local weapon_tweak_data = self._equipped_unit:base():weapon_tweak_data()
	multiplier = multiplier * managers.player:upgrade_value("weapon", "swap_speed_multiplier", 1)
	multiplier = multiplier * managers.player:upgrade_value("weapon", "passive_swap_speed_multiplier", 1)
	multiplier = multiplier * tweak_data.weapon.stats.mobility[self._equipped_unit:base():get_concealment() + 1] --Get concealment bonus/penalty.

	--Get per category multipliers (IE: Pistols swap faster, Akimbos swap slower, ect).
	for _, category in ipairs(weapon_tweak_data.categories) do
		multiplier = multiplier * managers.player:upgrade_value(category, "swap_speed_multiplier", 1)
		multiplier = multiplier * (tweak_data[category] and tweak_data[category].swap_bonus or 1)
	end

	if self._equipped_unit:base():got_silencer() then
		multiplier = multiplier * managers.player:upgrade_value("player", "silencer_swap_increase", 1)
	end

	--Get per weapon multiplier.
	multiplier = multiplier * (weapon_tweak_data.swap_speed_multiplier or 1)

	multiplier = multiplier * managers.player:upgrade_value("team", "crew_faster_swap", 1)

	if managers.player:has_activate_temporary_upgrade("temporary", "swap_weapon_faster") then
		multiplier = multiplier * managers.player:temporary_upgrade_value("temporary", "swap_weapon_faster", 1)
	end

	multiplier = managers.modifiers:modify_value("PlayerStandard:GetSwapSpeedMultiplier", multiplier)
	multiplier = multiplier * managers.player:upgrade_value("weapon", "mrwi_swap_speed_multiplier", 1)
	return multiplier
end

--Inspire no longer works through walls.
function PlayerStandard:_get_unit_intimidation_action(intimidate_enemies, intimidate_civilians, intimidate_teammates, only_special_enemies, intimidate_escorts, intimidation_amount, primary_only, detect_only, secondary)
	local char_table = {}
	local unit_type_enemy = 0
	local unit_type_civilian = 1
	local unit_type_teammate = 2
	local unit_type_camera = 3
	local unit_type_turret = 4
	local cam_fwd = self._ext_camera:forward()
	local my_head_pos = self._ext_movement:m_head_pos()

	if _G.IS_VR then
		local hand_unit = self._unit:hand():hand_unit(self._interact_hand)

		if hand_unit:raycast("ray", hand_unit:position(), my_head_pos, "slot_mask", 1) then
			return
		end

		cam_fwd = hand_unit:rotation():y()
		my_head_pos = hand_unit:position()
	end

	local spotting_mul = managers.player:upgrade_value("player", "marked_distance_mul", 1)
	local range_mul = managers.player:upgrade_value("player", "intimidate_range_mul", 1) * managers.player:upgrade_value("player", "passive_intimidate_range_mul", 1)
	local intimidate_range_civ = tweak_data.player.long_dis_interaction.intimidate_range_civilians * range_mul
	local intimidate_range_ene = tweak_data.player.long_dis_interaction.intimidate_range_enemies * range_mul
	local highlight_range = tweak_data.player.long_dis_interaction.highlight_range * range_mul * spotting_mul
	local intimidate_range_teammates = tweak_data.player.long_dis_interaction.intimidate_range_teammates

	if intimidate_enemies then
		local enemies = managers.enemy:all_enemies()

		for u_key, u_data in pairs(enemies) do
			if self._unit:movement():team().foes[u_data.unit:movement():team().id] and not u_data.unit:anim_data().hands_tied and not u_data.unit:anim_data().long_dis_interact_disabled and (not u_data.unit:character_damage() or not u_data.unit:character_damage():dead()) and (u_data.char_tweak.priority_shout or not only_special_enemies) then
				if managers.groupai:state():whisper_mode() then
					if u_data.char_tweak.silent_priority_shout and u_data.unit:movement():cool() then
						self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_enemy, highlight_range, false, false, 0.01, my_head_pos, cam_fwd)
					elseif not u_data.unit:movement():cool() then
						self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_enemy, intimidate_range_ene, false, false, 100, my_head_pos, cam_fwd, nil, "ai_vision mover")
					end
				elseif u_data.char_tweak.priority_shout then
					self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_enemy, highlight_range, false, false, 0.01, my_head_pos, cam_fwd)
				else
					self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_enemy, intimidate_range_ene, false, false, 100, my_head_pos, cam_fwd, nil, "ai_vision mover")
				end
			end
		end
	end

	if intimidate_civilians then
		local civilians = managers.enemy:all_civilians()

		for u_key, u_data in pairs(civilians) do
			if alive(u_data.unit) and u_data.unit:in_slot(21) and not u_data.unit:movement():cool() and not u_data.unit:anim_data().long_dis_interact_disabled then
				local is_escort = u_data.char_tweak.is_escort

				if not is_escort or intimidate_escorts then
					local dist = is_escort and 300 or intimidate_range_civ
					local prio = is_escort and 100000 or 0.001

					self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_civilian, dist, false, false, prio, my_head_pos, cam_fwd)
				end
			end
		end
	end
	
	--Failsafe so you can still shout at bots on FFD2 to stop a softlock
	local can_intimidate_teammates = nil	
	local job = Global.level_data and Global.level_data.level_id
	if not managers.groupai:state():whisper_mode() or job == "framing_frame_2" then
		can_intimidate_teammates = true
	end

	if intimidate_teammates and can_intimidate_teammates then
		local criminals = managers.groupai:state():all_char_criminals()

		for u_key, u_data in pairs(criminals) do
			local added = nil

			if u_key ~= self._unit:key() then
				local rally_skill_data = self._ext_movement:rally_skill_data()

				if rally_skill_data and rally_skill_data.long_dis_revive and mvector3.distance_sq(self._pos, u_data.m_pos) < rally_skill_data.range_sq then
					local needs_revive = nil

					if u_data.unit:base().is_husk_player then
						needs_revive = u_data.unit:interaction():active() and u_data.unit:movement():need_revive() and u_data.unit:movement():current_state_name() ~= "arrested"
					else
						needs_revive = u_data.unit:character_damage():need_revive()
					end

					if needs_revive then
						added = true
						--Disable "interaction_through_walls" from the char_table check to stop inspire from working through walls.
						self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_teammate, intimidate_range_teammates, false, true, 5000, my_head_pos, cam_fwd)
					end
				end
			end

			if not added and not u_data.is_deployable and not u_data.unit:movement():downed() and not u_data.unit:base().is_local_player and not u_data.unit:anim_data().long_dis_interact_disabled then
				self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_teammate, intimidate_range_teammates, true, not secondary, 0.01, my_head_pos, cam_fwd)
			end
		end
	end

	if intimidate_enemies and intimidate_teammates then
		local enemies = managers.enemy:all_enemies()

		for u_key, u_data in pairs(enemies) do
			if u_data.unit:movement():team() and u_data.unit:movement():team().id == "criminal1" and not u_data.unit:movement():cool() and not u_data.unit:anim_data().long_dis_interact_disabled then
				local is_escort = u_data.char_tweak.is_escort

				if not is_escort or intimidate_escorts then
					local dist = is_escort and 300 or intimidate_range_civ
					local prio = is_escort and 100000 or 0.001

					self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_civilian, dist, false, false, prio, my_head_pos, cam_fwd)
				end
			end
		end
	end

	if intimidate_enemies then
		if managers.groupai:state():whisper_mode() then
			for _, unit in ipairs(SecurityCamera.cameras) do
				if alive(unit) and unit:enabled() and not unit:base():destroyed() then
					local dist = 2000
					local prio = 0.001

					self:_add_unit_to_char_table(char_table, unit, unit_type_camera, dist, false, false, prio, my_head_pos, cam_fwd, {
						unit
					})
				end
			end
		end

		local turret_units = managers.groupai:state():turrets()

		if turret_units then
			for _, unit in pairs(turret_units) do
				if alive(unit) and unit:movement():team().foes[self._ext_movement:team().id] then
					self:_add_unit_to_char_table(char_table, unit, unit_type_turret, 2000, false, false, 0.01, my_head_pos, cam_fwd, {
						unit
					})
				end
			end
		end
	end

	local prime_target = self:_get_interaction_target(char_table, my_head_pos, cam_fwd)

	return self:_get_intimidation_action(prime_target, char_table, intimidation_amount, primary_only, detect_only, secondary)
end

--Replace coroutine with a playermanager function. The coroutine had issues with randomly not being called- or not having values get reset, and overall being jank???
function PlayerStandard:_find_pickups(t)
	local pickups = World:find_units_quick("sphere", self._unit:movement():m_pos(), self._pickup_area, self._slotmask_pickups)
	local grenade_tweak = tweak_data.blackmarket.projectiles[managers.blackmarket:equipped_grenade()]
	local may_find_grenade = not grenade_tweak.base_cooldown --and managers.player:has_category_upgrade("player", "regain_throwable_from_ammo")

	for _, pickup in ipairs(pickups) do
		if pickup:pickup() and pickup:pickup():pickup(self._unit) then
			if may_find_grenade then
				managers.player:regain_throwable_from_ammo() --Replace vanilla coroutine
			end

			for id, weapon in pairs(self._unit:inventory():available_selections()) do
				managers.hud:set_ammo_amount(id, weapon.unit:base():ammo_info())
			end
		end
	end
end

--Allowing underbarrels to update stance
function PlayerStandard:_check_action_deploy_underbarrel(t, input)
	local new_action = nil
	local action_forbidden = false

	if _G.IS_VR then
		if not input.btn_weapon_firemode_press and not self._toggle_underbarrel_wanted then
			return new_action
		end
	elseif not input.btn_deploy_bipod and not self._toggle_underbarrel_wanted then
		return new_action
	end
	
	--Removed the ADS check so you can swap to the underbarrel while doing that, also for Kick Starter top tier skill
	action_forbidden = self:_is_throwing_projectile() or self:_is_meleeing() or self:is_equipping() or self:_changing_weapon() or self:shooting() or self:_is_reloading() or self:is_switching_stances() or self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:running() and not self._equipped_unit:base():run_and_shoot_allowed()

	if self._running and not self._equipped_unit:base():run_and_shoot_allowed() and not self._end_running_expire_t then
		self:_interupt_action_running(t)

		self._toggle_underbarrel_wanted = true

		return
	end

	if not action_forbidden then
		self._toggle_underbarrel_wanted = false
		local weapon = self._equipped_unit:base()

		if weapon.record_fire_mode then
			weapon:record_fire_mode()
		end

		local underbarrel_state = weapon:underbarrel_toggle()

		if underbarrel_state ~= nil then
			local underbarrel_name_id = weapon:underbarrel_name_id()
			local underbarrel_tweak = tweak_data.weapon[underbarrel_name_id]
			new_action = true

			if weapon.reset_cached_gadget then
				weapon:reset_cached_gadget()
			end

			if weapon._update_stats_values then
				weapon:_update_stats_values(true)
			end

			local anim_ids = nil
			local switch_delay = 1

			if underbarrel_state then
				anim_ids = Idstring("underbarrel_enter_" .. weapon.name_id)
				switch_delay = underbarrel_tweak.timers.equip_underbarrel

				self:set_animation_state("underbarrel")
			else
				anim_ids = Idstring("underbarrel_exit_" .. weapon.name_id)
				switch_delay = underbarrel_tweak.timers.unequip_underbarrel

				self:set_animation_state("standard")
			end

			if anim_ids then
				self._ext_camera:play_redirect(anim_ids, 1)
			end

			self:set_animation_weapon_hold(nil)
			self:set_stance_switch_delay(switch_delay)
			
			--Updating stance
			self:_stance_entered()

			if alive(self._equipped_unit) then
				managers.hud:set_ammo_amount(self._equipped_unit:base():selection_index(), self._equipped_unit:base():ammo_info())				

				local base_ext = self._equipped_unit:base()
				managers.hud:set_teammate_weapon_firemode(HUDManager.PLAYER_PANEL, self._unit:inventory():equipped_selection(), base_ext:fire_mode(), base_ext:alt_fire_active())
			end

			managers.network:session():send_to_peers_synched("sync_underbarrel_switch", self._equipped_unit:base():selection_index(), underbarrel_name_id, underbarrel_state)
		end
	end


	return new_action
end

--Fixes weapons using shotgun-style reloads occasionally only loading one shell in
Hooks:PostHook(PlayerStandard, "_interupt_action_reload", "ResInterruptReloadFix", function(self, t)
	self._queue_reload_interupt = nil
end)

--Randomized inspect animations since rnd() doesn't work in anim xml
function PlayerStandard:_check_action_cash_inspect(t, input)
	if not input.btn_cash_inspect_press then
		return
	end

	local action_forbidden = self:_interacting() and not managers.player:has_category_upgrade("player", "no_interrupt_interaction") or self:is_deploying() or self:_changing_weapon() or self:_is_throwing_projectile() or self:_is_meleeing() or self:_on_zipline() or self:running() or self:_is_reloading() or self:in_steelsight() or self:is_equipping() or self:shooting() or self:_is_cash_inspecting(t)

	if action_forbidden then
		return
	end
	
	--Anim weight randomizing
	local anim_weight = 0
	if (math.random() < 0.5) then
		anim_weight = 1
	end
	
	local state = self._ext_camera:play_redirect(self:get_animation("cash_inspect"))

	--Applys the anim weight
	self._camera_unit:anim_state_machine():set_parameter(state, "alt_inspect", anim_weight)
	
	managers.player:send_message(Message.OnCashInspectWeapon)
end

function PlayerStandard:_start_action_unequip_weapon(t, data)
	local speed_multiplier = self:_get_swap_speed_multiplier()

	self._equipped_unit:base():tweak_data_anim_stop("equip")
	self._equipped_unit:base():tweak_data_anim_play("unequip", speed_multiplier)

	local tweak_data = self._equipped_unit:base():weapon_tweak_data()
	self._change_weapon_data = data
	self._unequip_weapon_expire_t = t + (tweak_data.timers.unequip or 0.5) / speed_multiplier

	--self:_interupt_action_running(t)
	self:_interupt_action_charging_weapon(t)

	local result = self._ext_camera:play_redirect(self:get_animation("unequip"), speed_multiplier)

	self:_interupt_action_reload(t)
	self:_interupt_action_steelsight(t)
	self._ext_network:send("switch_weapon", speed_multiplier, 1)
end

function PlayerStandard:_update_equip_weapon_timers(t, input)
	if self._unequip_weapon_expire_t and self._unequip_weapon_expire_t <= t then
		if self._change_weapon_data.unequip_callback and not self._change_weapon_data.unequip_callback() then
			return
		end

		self._unequip_weapon_expire_t = nil

		self:_start_action_equip_weapon(t)
	end

	if self._equip_weapon_expire_t and self._equip_weapon_expire_t <= t then
		self._equip_weapon_expire_t = nil

		if input.btn_steelsight_state then
			self._steelsight_wanted = true
		end

		if self._running and not self._end_running_expire_t then
			if not self._equipped_unit:base():run_and_shoot_allowed() then
				self._ext_camera:play_redirect(self:get_animation("start_running"))	
			else
				self._ext_camera:play_redirect(self:get_animation("idle"))	
			end	
		end

		TestAPIHelper.on_event("load_weapon")
		TestAPIHelper.on_event("mask_up")
	end
end

--Apply swap speed multiplier to more forms of equip/unequip animation.
function PlayerStandard:_start_action_equip(redirect, extra_time)
	local tweak_data = self._equipped_unit:base():weapon_tweak_data()
	local speed_multiplier = 1

	if redirect == self:get_animation("equip") then
		speed_multiplier = self:_get_swap_speed_multiplier()
		self._equipped_unit:base():tweak_data_anim_stop("unequip")
		self._equipped_unit:base():tweak_data_anim_play("equip", speed_multiplier)
	end

	self._equip_weapon_expire_t = (managers.player:player_timer():time() + (tweak_data.timers.equip or 0.7) / speed_multiplier + (extra_time or 0))
	self._ext_camera:play_redirect(redirect or self:get_animation("equip"), speed_multiplier)
end

function PlayerStandard:_play_equip_animation()
	local tweak_data = self._equipped_unit:base():weapon_tweak_data()
	local speed_multiplier = self:_get_swap_speed_multiplier()
	self._equip_weapon_expire_t = managers.player:player_timer():time() + (tweak_data.timers.equip or 0.7) / speed_multiplier
	local result = self._ext_camera:play_redirect(self:get_animation("equip"), speed_multiplier)
	self._equipped_unit:base():tweak_data_anim_stop("unequip")
	self._equipped_unit:base():tweak_data_anim_play("equip", speed_multiplier)
end

function PlayerStandard:_play_unequip_animation()
	local speed_multiplier = self:_get_swap_speed_multiplier()
	self._ext_camera:play_redirect(self:get_animation("unequip"), speed_multiplier)
	self._equipped_unit:base():tweak_data_anim_stop("equip")
	self._equipped_unit:base():tweak_data_anim_play("unequip", speed_multiplier)
end

function PlayerStandard:_interupt_action_throw_projectile(t)
	if not self:_is_throwing_projectile() then
		return
	end

	self._state_data.projectile_idle_wanted = nil
	self._state_data.projectile_expire_t = nil
	self._state_data.projectile_throw_allowed_t = nil
	self._state_data.throwing_projectile = nil
	self._camera_unit_anim_data.throwing = nil

	self._camera_unit:base():unspawn_grenade()
	self._camera_unit:base():show_weapon()
	self:_play_equip_animation()
	self:_stance_entered()
end
