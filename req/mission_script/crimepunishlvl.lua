local difficulty = Global.game_settings and Global.game_settings.difficulty or "normal"
local difficulty_index = tweak_data:difficulty_to_index(difficulty)
	
	if tweak_data:difficulty_to_index(difficulty) <= 5 then
		ponr_value = 660
	elseif tweak_data:difficulty_to_index(difficulty) == 6 or tweak_data:difficulty_to_index(difficulty) == 7 then
		ponr_value = 630	
	elseif tweak_data:difficulty_to_index(difficulty) == 8 then
		ponr_value = 600	
	end

return {
	--Pro Job PONR 
	[100034] = {
		ponr = ponr_value
	},
	[101050] = {
		values = {
			enemy = "units/pd2_mod_reapers/characters/ene_vip_2/ene_vip_2"
		}
	}
}
