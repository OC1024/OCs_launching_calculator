local M = {}

M.constants = {
  mod_name = "ocs_launching_calculator",
  frame_name = "ocs_launching_calculator_frame",
  recipe_picker_name = "ocs_launching_calculator_recipe_picker",
  input_table_name = "ocs_launching_calculator_inputs",
  output_table_name = "ocs_launching_calculator_outputs",
  input_sum_table_name = "ocs_launching_calculator_input_sum_table",
  output_sum_table_name = "ocs_launching_calculator_output_sum_table",
  recommendation_name = "ocs_launching_calculator_recommendation",
  vanilla_silo = "rocket-silo",
  vanilla_rocket_part = "rocket-part",
  weight_per_kilogram = 1e3,
  weight_per_ton = 1e6,
  rocket_lift_weight = prototypes.utility_constants.default_rocket_lift_weight,
}

---Returns GUI settings for a player.
---@param player LuaPlayer
---@return table gui_settings
function M.player_gui_settings(player)
  local player_settings = settings.get_player_settings(player)
  local window_width = player_settings["oc-calc-window-width"].value
  local show_item_name = player_settings["oc-calc-show-item-name"].value
  local slim_factor = player_settings["oc-calc-compact-window-factor"].value / 100
  window_width = show_item_name and window_width or window_width * slim_factor
  return {
    window_width = window_width,
    column_width = window_width / 2 - 14,
    show_item_name = show_item_name,
    advanced_mode = player_settings["oc-calc-advanced-mode"].value,
    decimals = player_settings["round_decimals"].value,
  }
end

---Get persistent calculator state for a player. Contains recipe, rocket, and silo.
---@param player LuaPlayer
---@return table
function M.player_calculator_state(player)
  storage.calculator_state = storage.calculator_state or {}
  local state = storage.calculator_state[player.index]
  if not state then
    state = {
      selected_recipe = nil,
      selected_silo_name = nil,
      selected_rocket_recipe_name = nil,
      window_location = nil,
      is_minimised = false,
      checkbox_states = {},
    }
    storage.calculator_state[player.index] = state
  end
  state.checkbox_states = state.checkbox_states or {}
  return state
end

return M

