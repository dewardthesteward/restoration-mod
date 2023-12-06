function IncendiaryGrenade:_setup_from_tweak_data()
	local tweak_entry = IncendiaryGrenade.super._setup_from_tweak_data(self)

	self._mass_look_up_modifier = tweak_entry.mass_look_up_modifier
	self._dot_data = tweak_entry.dot_data_name and tweak_data.dot:get_dot_data(tweak_entry.dot_data_name)
end


function IncendiaryGrenade:_detonate(tag, unit, body, other_unit, other_body, position, normal, collision_velocity, velocity, other_velocity, new_velocity, direction, damage, ...)
	if self._detonated then
		return
	end

	self._detonated = true
	local pos = self._unit:position()
	local explosion_normal = math.UP
	local range = self._range
	local slot_mask = managers.slot:get_mask("explosion_targets")

	managers.explosion:give_local_player_dmg(pos, range, self._player_damage or self._damage, self:thrower_unit() or self._unit, self._curve_pow)
	managers.explosion:play_sound_and_effects(pos, explosion_normal, range, self._custom_params)

	local params = {
		player_damage = 0,
		hit_pos = pos,
		range = range,
		collision_slotmask = slot_mask,
		curve_pow = self._curve_pow,
		damage = self._damage,
		ignore_unit = self._unit,
		alert_radius = self._alert_radius,
		user = self:thrower_unit() or self._unit,
		owner = self._unit,
		dot_data = self._dot_data
	}
	local hit_units, splinters = managers.explosion:detect_and_give_dmg(params)
	normal = normal or explosion_normal
	local destruction_delay = self:_spawn_environment_fire(normal)

	if self._unit:id() ~= -1 then
		managers.network:session():send_to_peers_synched("sync_detonate_incendiary_grenade", self._unit, "base", GrenadeBase.EVENT_IDS.detonate, normal)
	end

	self:_handle_hiding_and_destroying(true, destruction_delay)
end

function IncendiaryGrenade:_spawn_environment_fire(normal)
	local position = self._unit:position()
	local rotation = self._unit:rotation()
	local data = tweak_data.env_effect:incendiary_launcher_fire()
	local tweak = tweak_data.projectiles[self._tweak_projectile_entry] or {}
	data.damage = tweak.damage or data.damage or 6
	data.player_damage = tweak.player_damage or data.player_damage or 3
	data.burn_duration = tweak.burn_duration or data.burn_duration or 6
	data.sound_event_impact_duration = tweak.sound_event_impact_duration or data.sound_event_impact_duration or 1
	local groundfire_unit, time_until_destruction = EnvironmentFire.spawn(position, rotation, data, normal, self._thrower_unit, self._unit, 0, 1)

	if self._dot_data then
		local explosion_dot_length = self._dot_data.dot_length + 1
		time_until_destruction = time_until_destruction and math.max(time_until_destruction, explosion_dot_length) or explosion_dot_length
	end

	return time_until_destruction
end


function IncendiaryGrenade:_detonate_on_client(normal)
	if self._detonated then
		return
	end

	self._detonated = true
	local pos = self._unit:position()
	local range = self._range
	local explosion_normal = math.UP

	managers.explosion:give_local_player_dmg(pos, range, self._player_damage or self._damage, self:thrower_unit() or self._unit, self._curve_pow)
	managers.explosion:play_sound_and_effects(pos, explosion_normal, range, self._custom_params)
	managers.fire:client_damage_and_push(pos, explosion_normal, nil, self._damage, range, self._curve_pow)

	local destruction_delay = self:_spawn_environment_fire(normal)

	self:_handle_hiding_and_destroying(true, destruction_delay)
end