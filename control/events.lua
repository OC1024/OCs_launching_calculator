local state = require("control.state")
local calculation = require("control.helpers")
local gui = require("control.gui")
local const = state.constants

local MANE_NAME = const.mod_name
local FRAME_NAME = const.frame_name
local RECIPE_PICKER_NAME = const.recipe_picker_name
local HISTORY_TOGGLE_NAME = const.mod_name .. "_history_toggle"
local vanilla_silo = const.vanilla_silo
local vanilla_r_part = const.vanilla_rocket_part

---Lua Things
---@class EventData

---Creates main buttons when the mod is initialized.
script.on_init(function()
  for _, player in pairs(game.players) do gui.create_main_button(player) end
end)

---Creates main buttons after a mod configuration change.
script.on_configuration_changed(function()
  for _, player in pairs(game.players) do gui.create_main_button(player) end
end)

---Resets the invoking player's saved calculator state for testing.
---@param command CommandData
commands.add_command("ocs-launching-calculator-reset", "Reset your calculator state for testing.", function(command)
  if not command.player_index then
    log("The ocs-launching-calculator-reset command must be run by a player.")
    return
  end

  storage.calculator_state = storage.calculator_state or {}
  storage.calculator_state[command.player_index] = nil

  local player = game.get_player(command.player_index)
  if not player then return end
  gui.destroy_calculator(player)
  player.print({ "ocs-launching-calculator.storage-reset" })
end)

---Creates the main button for a newly created player.
---@param event EventData
script.on_event(defines.events.on_player_created, function(event)
  gui.create_main_button(game.get_player(event.player_index))
end)

---Closes the calculator when its frame is closed with the standard GUI controls.
---@param event EventData
script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local element = event.element
  if element and element.valid and (element.name == FRAME_NAME or element.name == MANE_NAME .. "_history") then
    gui.destroy_calculator(player)
  end
end)

---Toggle main window
---@param event EventData
script.on_event("ocs-launching-calculator-toggle", function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local frame = player.gui.screen[FRAME_NAME]
  if frame and frame.valid then
    gui.destroy_calculator(player)
  else
    gui.create_calculator(player)
  end
end)

---Handle calculator open/close clicks and recipe selection via item icons.
---@param event EventData
script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  local element = event.element
  if not (element and element.valid) then return end
  if element.name == "ocs_launching_calculator_button" then -- interact
    local frame = player.gui.screen[FRAME_NAME]
    if frame then gui.destroy_calculator(player) else gui.create_calculator(player) end
    return
  elseif element.name == "ocs_launching_calculator_close" then -- MANE close
    local frame = player.gui.screen[FRAME_NAME]
    if frame then gui.destroy_calculator(player) end
    return
  elseif element.name == "ocs_launching_calculator_minimise" then -- MANE minimise
    local state = state.player_calculator_state(player)
    state.is_minimised = not state.is_minimised
    local frame = player.gui.screen[FRAME_NAME]
    if frame and frame.valid then
      local content = frame["ocs_launching_calculator_content"]
      if content and content.valid then
        content.visible = not state.is_minimised
      end
      element.sprite = state.is_minimised
          and "utility/expand"
          or "utility/collapse"
      element.tooltip = state.is_minimised
          and { "gui-crafting-queue.expand" }
          or { "gui-crafting-queue.collapse" }
    end
    return
  elseif element.name == HISTORY_TOGGLE_NAME then
    gui.toggle_history(player, element)
    return
  end

  -- clicking on icon selects "obvious" recipe
  local tags = element.tags
  if tags.action == "select-recipe-for-product" then
    local recipe = calculation.find_unique_recipe_for_product(tags.item_name, tags.item_type)
    if recipe then
      gui.select_recipe(player, recipe.name)
    end
    return
  end
  if tags.action == "select-history-recipe" then
    gui.select_recipe(player, tags.recipe_name)
    return
  end
end)

---Saves the calculator window position after it is moved.
---@param event EventData
script.on_event(defines.events.on_gui_location_changed, function(event)
  local element = event.element
  if not (element and element.valid and element.name == FRAME_NAME) then
    return
  end
  local player = game.get_player(event.player_index)
  local state = state.player_calculator_state(player)
  state.window_location = element.location
  gui.update_history_position(player)
end)

---Update the calculator when player changes the recipe picker
---@param event EventData
script.on_event(defines.events.on_gui_elem_changed, function(event)
  local element = event.element
  if not (element and element.valid and element.name == RECIPE_PICKER_NAME) then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then return end
  gui.select_recipe(player, element.elem_value)
end)

---Handle changes to the selected silo or rocket recipe.
---@param event EventData
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end

  local player = game.get_player(event.player_index)
  local gui_settings = state.player_gui_settings(player)
  local state = state.player_calculator_state(player)
  local head_frame = player.gui.screen[FRAME_NAME]
  if not (head_frame and head_frame.valid) then return end
  local frame = head_frame["ocs_launching_calculator_content"]
  if not (frame and frame.valid) then return end

  if element.name == MANE_NAME .. "_silo_dropdown" then
    local silos = calculation.get_rocket_silos()
    local silo = silos[element.selected_index]
    if not silo then return end
    state.selected_silo_name = silo.name

    local icon = frame[MANE_NAME .. "_rocket_silo"]
        [MANE_NAME .. "_silo_frame"]
        [MANE_NAME .. "_silo_selection"]
        [MANE_NAME .. "_silo_icon"]

    if icon and icon.valid then
      icon.sprite = silo.sprite
    end
    local lift_weight_label = frame[MANE_NAME .. "_rocket_silo"]
        [MANE_NAME .. "_silo_frame"]
        [MANE_NAME .. "_silo_lift_weight"]

    if lift_weight_label and lift_weight_label.valid then
      lift_weight_label.caption = { "ocs-launching-calculator.max-lift-weight",
        calculation.display_number(silo.lift_weight / 1e3, gui_settings.decimals, true) .. " kg", }
    end

    -- Update required rocket-part recipe cycles
    local rocket_frame = frame[MANE_NAME .. "_rocket_silo"][MANE_NAME .. "_rocket_frame"]
    local cycles_label = rocket_frame and rocket_frame[MANE_NAME .. "_rocket_recipe_tip"]
    if cycles_label and cycles_label.valid then
      local rocket_recipes = calculation.get_rocket_recipes()
      local _, _, selected_recipe = calculation.prepare_selection(rocket_recipes, state.selected_rocket_recipe_name,
        vanilla_r_part)
      local parts_per_cycle = 0
      local cycles = 0
      if selected_recipe then
        for _, product in pairs(selected_recipe.products or {}) do
          if product.name == "rocket-part" then
            parts_per_cycle = product.amount or product.amount_max or 0
            break
          end
        end
      end
      if silo.rocket_parts_required and parts_per_cycle > 0 then
        cycles = math.ceil(silo.rocket_parts_required / parts_per_cycle)
      end
      cycles_label.caption = {
        "ocs-launching-calculator.rocket-recipe-tip",
        cycles > 0 and calculation.display_number(cycles, gui_settings.decimals, true) or "—",
      }
    end
    -- Recalculate item ratios and recommendation for the new silo.
    gui.recalculate(player, state.selected_recipe)
  elseif element.name == MANE_NAME .. "_rocket_dropdown" then
    local rocket_recipes = calculation.get_rocket_recipes()
    local recipe = rocket_recipes[element.selected_index]
    if not recipe then return end
    state.selected_rocket_recipe_name = recipe.name

    local icon = frame[MANE_NAME .. "_rocket_silo"]
        [MANE_NAME .. "_rocket_frame"]
        [MANE_NAME .. "_rocket_selection"]
        [MANE_NAME .. "_rocket_icon"]

    if icon and icon.valid then
      icon.sprite = recipe.sprite
    end
  end
end)

---Recalculate totals and recommendation when an input/output row is toggled.
---Saves changes on checkboxes in the state storage.
---@param event EventData
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local tags = element.tags
  if tags.row_type ~= "item" and tags.row_type ~= "barrelled-fluid" then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local state = state.player_calculator_state(player)
  local recipe_name = tags.recipe_name
  local table_type = tags.table_type
  local entry_name = tags.item_name or tags.fluid_name

  -- Save only unchecked rows; checked is the default.
  if recipe_name and table_type and entry_name then
    local recipe_states = state.checkbox_states[recipe_name]
    if element.state then
      -- Checked: remove the saved false entry, if present.
      if recipe_states then
        recipe_states[table_type] = recipe_states[table_type] or {}
        recipe_states[table_type][entry_name] = nil
        -- Remove the recipe entry when everything is checked.
        if next(recipe_states.inputs) == nil
            and next(recipe_states.outputs) == nil then
          state.checkbox_states[recipe_name] = nil
        end
      end
    else
      -- Unchecked: create storage as needed.
      if not recipe_states then
        recipe_states = { inputs = {}, outputs = {} }
        state.checkbox_states[recipe_name] = recipe_states
      end
      recipe_states[table_type][entry_name] = false
    end
  end
  -- Update barrelled-fluid row display.
  if tags.row_type == "barrelled-fluid" then
    gui.update_fluid_row(player, element)
  end
  -- Recalculate using the recipe identified by this checkbox.
  gui.recalculate(player, recipe_name)
end)
