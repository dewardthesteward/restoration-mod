local difficulty = Global.game_settings and Global.game_settings.difficulty or "normal"
local difficulty_index = tweak_data:difficulty_to_index(difficulty)

	elseif tweak_data:difficulty_to_index(difficulty) <= 5 then
		ponr_value = 240	
	elseif tweak_data:difficulty_to_index(difficulty) == 6 or tweak_data:difficulty_to_index(difficulty) == 7 then
		ponr_value = 210
	elseif tweak_data:difficulty_to_index(difficulty) == 8 then
		ponr_value = 180		
	end

return {
	--Pro Job PONR 
	[102047] = {
		ponr = ponr_value
	}
}