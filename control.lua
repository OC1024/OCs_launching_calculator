local mod_gui = require("mod-gui")

local FRAME_NAME = "ocs_launching_calculator_frame"
local RECIPE_PICKER_NAME = "ocs_launching_calculator_recipe_picker"
local INPUT_TABLE_NAME = "ocs_launching_calculator_inputs"
local OUTPUT_TABLE_NAME = "ocs_launching_calculator_outputs"
local RECOMMENDATION_NAME = "ocs_launching_calculator_recommendation"
local ROCKET_LIFT_WEIGHT = prototypes.utility_constants.default_rocket_lift_weight
local WEIGHT_PER_KILOGRAM = 1000

-- ==============================================================================
-- Helper Functions

local function display_number(value, decimals)
  return string.format("%." .. decimals .. "f", value)
end

local function player_decimals(player)
  local setting = settings.get_player_settings(player)["round_decimals"]
  return setting and setting.value or 2
end

---A barrel normally has a matching fill recipe. This supports modded barrel
---sizes instead of assuming vanilla's 50 fluid units per barrel.
---Fluids without a barreled equivalent are shown with no mass and a disabled checkbox.
local function fluid_barrel_details(fluid_name, fluid_amount)
  local barrel_name = fluid_name .. "-barrel"
  local barrel = prototypes.item[barrel_name]
  if not barrel then return nil end

  local fill_recipe = prototypes.recipe["fill-" .. barrel_name]
  local fluid_per_batch, barrels_per_batch
  if fill_recipe then
    for _, ingredient in pairs(fill_recipe.ingredients) do
      if ingredient.type == "fluid" and ingredient.name == fluid_name then
        fluid_per_batch = ingredient.amount
        break
      end
    end
    for _, product in pairs(fill_recipe.products) do
      if product.type == "item" and product.name == barrel_name then
        barrels_per_batch = product.amount
        break
      end
    end
  end

  if not fluid_per_batch or fluid_per_batch <= 0 or not barrels_per_batch then
    return { prototype = barrel, amount = 0, note = "No fill recipe found for this barrel" }
  end
  return {
    prototype = barrel,
    amount = fluid_amount * barrels_per_batch / fluid_per_batch,
    note = "Converted from fluid"
  }
end

local function expected_product_amount(product)
  local amount = product.amount
  if not amount then
    amount = ((product.amount_min or 0) + (product.amount_max or 0)) / 2
  end
  return amount * (product.probability or 1)
end

local function resolve_entry(entry, amount)
  if entry.type == "fluid" then
    local barrel = fluid_barrel_details(entry.name, amount)
    if barrel then return barrel.prototype, barrel.amount, barrel.note end
    return prototypes.fluid[entry.name], amount, "No barrel item exists for this fluid", true
  end
  return prototypes.item[entry.name], amount, nil, false
end

-- ==============================================================================
-- GUI Functions
local function add_headers(gui_table)
  for _, caption in ipairs({ "", "Icon", "Item", "Amount", "Mass (kg)", "Rocket ratio" }) do
    gui_table.add { type = "label", caption = caption, style = "caption_label" }
  end
end

local function add_item_row(gui_table, side, index, entry, amount, decimals)
  local prototype, converted_amount, note, is_unbarreled_fluid = resolve_entry(entry, amount)
  local unit_weight = (prototype and not is_unbarreled_fluid) and prototype.weight / WEIGHT_PER_KILOGRAM or 0
  local total_weight = converted_amount * unit_weight
  local rocket_ratio = total_weight / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM)
  local row_id = "ocs_launching_calculator_" .. side .. "_" .. index

  gui_table.add {
    type = "checkbox", name = row_id .. "_include", state = not is_unbarreled_fluid,
    enabled = not is_unbarreled_fluid,
    tooltip = is_unbarreled_fluid and "This fluid has no barrel alternative and cannot be launched"
      or "Include this row in the launch-weight total",
    tags = { total_weight = total_weight }
  }
  local sprite = is_unbarreled_fluid and "fluid/" .. entry.name
      or (prototype and "item/" .. prototype.name) or "utility/questionmark"
  gui_table.add {
    type = "sprite-button", sprite = sprite, style = "slot_button",
    tooltip = note or (prototype and prototype.localised_name) or entry.name
  }
  gui_table.add { type = "label", caption = prototype and prototype.localised_name or entry.name, tooltip = note }
  gui_table.add { type = "label", caption = display_number(converted_amount, decimals) }
  gui_table.add { type = "label", caption = tostring(total_weight), tooltip = "Unit mass: " .. tostring(unit_weight) .. " kg" }
  gui_table.add { type = "label", caption = display_number(rocket_ratio, decimals) }
end

local function add_sum_row(gui_table, side, total, decimals)
  gui_table.add { type = "label", caption = "" }
  gui_table.add { type = "label", caption = "Σ", style = "caption_label" }
  gui_table.add { type = "label", caption = "Sum", style = "caption_label" }
  gui_table.add { type = "label", caption = "" }
  gui_table.add {
    type = "label", name = "ocs_launching_calculator_" .. side .. "_mass_sum",
    caption = tostring(total), style = "caption_label"
  }
  gui_table.add {
    type = "label", name = "ocs_launching_calculator_" .. side .. "_ratio_sum",
    caption = display_number(total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals),
    style = "caption_label"
  }
end

local function add_empty_rows(gui_table, row_count)
  for _ = 1, row_count do
    for _ = 1, 6 do
      gui_table.add { type = "label", caption = "" }
    end
  end
end

local function included_total(gui_table)
  local total = 0
  for _, child in pairs(gui_table.children) do
    if child.type == "checkbox" and child.tags and child.tags.total_weight and child.state then
      total = total + child.tags.total_weight
    end
  end
  return total
end

-- ==============================================================================
-- GUI Functions

local function get_recipe_table(frame, side)
  if not (frame and frame.valid) then return end
  local body = frame["ocs_launching_calculator_body"]
  if not (body and body.valid) then return nil end

  local column_name = side == "input"
      and "ocs_launching_calculator_input_column"
      or "ocs_launching_calculator_output_column"

  local column = body[column_name]
  if not (column and column.valid) then return nil end

  local table_name = side == "input"
      and INPUT_TABLE_NAME
      or OUTPUT_TABLE_NAME

  return column[table_name]
end

local function recalculate(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.valid) then return end

  local input_table = get_recipe_table(frame, "input")
  local output_table = get_recipe_table(frame, "output")

  if not (input_table and input_table.valid and output_table and output_table.valid) then
    return
  end

  local decimals = player_decimals(player)
  local input_total = included_total(input_table)
  local output_total = included_total(output_table)
  local input_mass_sum = input_table["ocs_launching_calculator_input_mass_sum"]
  local output_mass_sum = output_table["ocs_launching_calculator_output_mass_sum"]
  local input_ratio_sum = input_table["ocs_launching_calculator_input_ratio_sum"]
  local output_ratio_sum = output_table["ocs_launching_calculator_output_ratio_sum"]

  if not (input_mass_sum and input_mass_sum.valid
        and output_mass_sum and output_mass_sum.valid
        and input_ratio_sum and input_ratio_sum.valid
        and output_ratio_sum and output_ratio_sum.valid) then
    return
  end

  input_mass_sum.caption = tostring(input_total)
  output_mass_sum.caption = tostring(output_total)
  input_ratio_sum.caption = display_number(input_total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals)
  output_ratio_sum.caption = display_number(output_total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals)

  local recommendation = frame[RECOMMENDATION_NAME]
  if not (recommendation and recommendation.valid) then return end
  if input_total < output_total then
    recommendation.caption = "Recommendation: Launch inputs"
  elseif output_total < input_total then
    recommendation.caption = "Recommendation: Launch outputs"
  else
    recommendation.caption =
    "Recommendation: Either side; launch weights are equal"
  end
end

local function clear_recipe_tables(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.valid) then return end
  local decimals = player_decimals(player)
  for _, side in ipairs({ "input", "output" }) do
    local gui_table = get_recipe_table(frame, side)
    if not (gui_table and gui_table.valid) then
      return
    end
    gui_table.clear()
    add_headers(gui_table)
    add_sum_row(gui_table, side, 0, decimals)
  end
  frame[RECOMMENDATION_NAME].caption = "Select a recipe to compare launch weights"
end

local function show_recipe(player, recipe_name)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.valid) then return end

  local recipe = recipe_name and prototypes.recipe[recipe_name]
  if not recipe then
    frame.ocs_launching_calculator_recipe_name.caption = "No recipe selected"
    clear_recipe_tables(player)
    return
  end

  local input_table = get_recipe_table(frame, "input")
  local output_table = get_recipe_table(frame, "output")
  if not (input_table and input_table.valid and output_table and output_table.valid) then
    return
  end

  local decimals = player_decimals(player)
  frame["ocs_launching_calculator_selection"].ocs_launching_calculator_recipe_name.caption = recipe.localised_name

  input_table.clear()
  output_table.clear()
  add_headers(input_table)
  add_headers(output_table)
  for index, ingredient in ipairs(recipe.ingredients) do
    add_item_row(input_table, "input", index, ingredient, ingredient.amount, decimals)
  end
  for index, product in ipairs(recipe.products) do
    add_item_row(output_table, "output", index, product, expected_product_amount(product), decimals)
  end
  local row_difference = #recipe.ingredients - #recipe.products
  if row_difference > 0 then
    add_empty_rows(output_table, row_difference)
  elseif row_difference < 0 then
    add_empty_rows(input_table, -row_difference)
  end
  add_sum_row(input_table, "input", 0, decimals)
  add_sum_row(output_table, "output", 0, decimals)
  recalculate(player)
end

local function create_calculator(player)
  local old_frame = player.gui.screen[FRAME_NAME]
  if old_frame then old_frame.destroy() end
  local frame = player.gui.screen.add { type = "frame", name = FRAME_NAME, direction = "vertical" }
  frame.auto_center = true

  local titlebar = frame.add { type = "flow", direction = "horizontal" }
  titlebar.drag_target = frame
  titlebar.add { type = "label", caption = "Launch Calculator", style = "frame_title" }
  local filler = titlebar.add { type = "empty-widget", style = "draggable_space_header" }
  filler.style.horizontally_stretchable = true
  filler.drag_target = frame
  titlebar.add { type = "sprite-button", name = "ocs_launching_calculator_close", sprite = "utility/close", style = "frame_action_button" }

  local selection = frame.add {
    type = "flow",
    name = "ocs_launching_calculator_selection",
    direction = "horizontal"
  }
  selection.add { type = "label", caption = "Recipe:" }
  selection.add { type = "choose-elem-button", name = RECIPE_PICKER_NAME, elem_type = "recipe" }
  selection.add { type = "label", name = "ocs_launching_calculator_recipe_name", caption = "No recipe selected" }

  local body = frame.add {
    type = "flow",
    name = "ocs_launching_calculator_body",
    direction = "horizontal"
  }
  local input_column = body.add {
    type = "flow",
    name = "ocs_launching_calculator_input_column",
    direction = "vertical"
  }
  input_column.add { type = "label", caption = "Inputs", style = "heading_2_label" }
  input_column.add { type = "table", name = INPUT_TABLE_NAME, column_count = 6 }
  local output_column = body.add {
    type = "flow",
    name = "ocs_launching_calculator_output_column",
    direction = "vertical"
  }
  output_column.add { type = "label", caption = "Outputs", style = "heading_2_label" }
  output_column.add { type = "table", name = OUTPUT_TABLE_NAME, column_count = 6 }
  frame.add { type = "label", name = RECOMMENDATION_NAME, caption = "Select a recipe to compare launch weights", style = "heading_2_label" }
  clear_recipe_tables(player)
end

local function create_main_button(player)
  local flow = mod_gui.get_button_flow(player)
  if flow.ocs_launching_calculator_button then return end
  flow.add {
    type = "sprite-button", name = "ocs_launching_calculator_button", sprite = "item/rocket-silo",
    tooltip = "Launch Calculator", style = mod_gui.button_style
  }
end

-- ==============================================================================
-- Scripts
script.on_init(function()
  for _, player in pairs(game.players) do create_main_button(player) end
end)

script.on_configuration_changed(function()
  for _, player in pairs(game.players) do create_main_button(player) end
end)

script.on_event(defines.events.on_player_created, function(event)
  create_main_button(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  local element = event.element
  if not (element and element.valid) then return end
  if element.name == "ocs_launching_calculator_button" then
    local frame = player.gui.screen[FRAME_NAME]
    if frame then frame.destroy() else create_calculator(player) end
  elseif element.name == "ocs_launching_calculator_close" then
    local frame = player.gui.screen[FRAME_NAME]
    if frame then frame.destroy() end
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  local element = event.element
  if element and element.valid and element.name == RECIPE_PICKER_NAME then
    show_recipe(game.get_player(event.player_index), element.elem_value)
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  if element.name:find("^ocs_launching_calculator_input_") or element.name:find("^ocs_launching_calculator_output_") then
    recalculate(game.get_player(event.player_index))
  end
end)
