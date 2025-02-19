local difficulty = Global.game_settings and Global.game_settings.difficulty or "normal"
local difficulty_index = tweak_data:difficulty_to_index(difficulty)
	
	if tweak_data:difficulty_to_index(difficulty) <= 5 then
		ponr_value = 590	
	elseif tweak_data:difficulty_to_index(difficulty) == 6 or tweak_data:difficulty_to_index(difficulty) == 7 then
		ponr_value = 560	
	elseif tweak_data:difficulty_to_index(difficulty) == 8 then
		ponr_value = 500		
	end

return {
	--Pro Job PONR 
	[106282] = {
		ponr = ponr_value
	},
	[105069] = {
		ponr = ponr_value
	},
	[100288] = {
		values = {
            sound_event = "earthquake_siren"
		}
	},
	[104193] = {
		values = {
            sound_event = "earthquake_siren"
		}
	},
	[106309] = {
		values = {
            enabled = false
		}
	}
}