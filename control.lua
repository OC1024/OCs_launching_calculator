local mod_gui = require("mod-gui")

local FRAME_NAME = "ocs_launching_calculator_frame"
local RECIPE_PICKER_NAME = "ocs_launching_calculator_recipe_picker"
local INPUT_TABLE_NAME = "ocs_launching_calculator_inputs"
local OUTPUT_TABLE_NAME = "ocs_launching_calculator_outputs"
local INPUT_SUM_TABLE_NAME = "ocs_launching_calculator_input_sum_table"
local OUTPUT_SUM_TABLE_NAME = "ocs_launching_calculator_output_sum_table"
local RECOMMENDATION_NAME = "ocs_launching_calculator_recommendation"
local WEIGHT_PER_KILOGRAM = 1000
local WINDOW_WIDTH = 1100
local COLUMN_WIDTH = 536
-- Future rocket-ratio feature:
-- local ROCKET_LIFT_WEIGHT = prototypes.utility_constants.default_rocket_lift_weight

-- ==============================================================================
-- Helper Functions

local function display_number(value, decimals)
  decimals = math.max(0, math.floor(tonumber(decimals) or 0))
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

  local fill_recipe = prototypes.recipe[barrel_name]
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
    return { prototype = barrel, amount = fluid_amount, note = { "ocs-launching-calculator.no-fill-recipe" } }
  end
  local barrel_amount = fluid_amount * barrels_per_batch / fluid_per_batch
  return {
    prototype = barrel,
    amount = barrel_amount,
    note = { "ocs-launching-calculator.converted-from-fluid" }
  }
end

---Returns Factorio's own expected amount, including product probability/ranges.
local function expected_product_amount(recipe, product_index)
  return recipe.get_product_amount(product_index)
end

-- ==============================================================================
-- GUI Functions
local function add_headers(gui_table)
  for _, caption in ipairs({ "", { "ocs-launching-calculator.header-icon" }, { "ocs-launching-calculator.header-item" }, { "ocs-launching-calculator.header-amount" }, { "ocs-launching-calculator.header-unit-mass" }, { "ocs-launching-calculator.header-total-mass" } }) do
    gui_table.add { type = "label", caption = caption, style = "caption_label" }
  end
  -- Future rocket-ratio column: {"ocs-launching-calculator.header-rocket-ratio"}
end

---Updates a row's icon, label, quantities, and the mass used in its sum.
local function set_row_display(gui_table, row_id, prototype, amount, unit_mass, note, is_fluid, decimals)
  local total_mass = amount * unit_mass
  -- Future rocket-ratio calculation:
  -- local rocket_ratio = total_mass / ROCKET_LIFT_WEIGHT
  local icon_holder = gui_table[row_id .. "_icon_holder"]
  icon_holder.clear()
  icon_holder.add {
    type = "sprite-button",
    sprite = (is_fluid and "fluid/" or "item/") .. prototype.name,
    style = "slot_button",
    tooltip = note or prototype.localised_name
  }
  gui_table[row_id .. "_name"].caption = prototype.localised_name
  gui_table[row_id .. "_name"].tooltip = note
  gui_table[row_id .. "_amount"].caption = display_number(amount, decimals)
  gui_table[row_id .. "_unit_mass"].caption = display_number(unit_mass, decimals)
  gui_table[row_id .. "_total_mass"].caption = display_number(total_mass, decimals)
  -- gui_table[row_id .. "_rocket_ratio"].caption = display_number(rocket_ratio, decimals)

  local tags = gui_table[row_id .. "_include"].tags
  tags.total_mass = total_mass
  gui_table[row_id .. "_include"].tags = tags
end

---Creates the cells shared by item and fluid rows and returns their checkbox.
local function add_row_cells(gui_table, row_id, checkbox_spec)
  local checkbox = gui_table.add(checkbox_spec)
  gui_table.add { type = "flow", name = row_id .. "_icon_holder", direction = "horizontal" }
  gui_table.add { type = "label", name = row_id .. "_name" }
  gui_table.add { type = "label", name = row_id .. "_amount" }
  gui_table.add { type = "label", name = row_id .. "_unit_mass" }
  gui_table.add { type = "label", name = row_id .. "_total_mass" }
  return checkbox
end

---Adds an item row or a fluid row with an optional barrel representation.
local function add_item_row(gui_table, side, index, entry, amount, decimals)
  local row_id = "ocs_launching_calculator_" .. side .. "_" .. index
  if entry.type ~= "fluid" then
    local prototype = prototypes.item[entry.name]
    local unit_mass = prototype and prototype.weight / WEIGHT_PER_KILOGRAM or 0
    add_row_cells(gui_table, row_id, {
      type = "checkbox",
      name = row_id .. "_include",
      state = true,
      tooltip = { "ocs-launching-calculator.include-row" },
      tags = { row_type = "item", total_mass = amount * unit_mass }
    })
    set_row_display(gui_table, row_id, prototype, amount, unit_mass, nil, false, decimals)
    return
  end

  local fluid = prototypes.fluid[entry.name]
  local barrel = fluid_barrel_details(entry.name, amount)
  if not barrel then
    add_row_cells(gui_table, row_id, {
      type = "checkbox",
      name = row_id .. "_include",
      state = false,
      enabled = false,
      tooltip = { "ocs-launching-calculator.no-barrel-tooltip" },
      tags = { row_type = "unbarrelled-fluid", total_mass = 0 }
    })
    set_row_display(gui_table, row_id, fluid, amount, 0, { "ocs-launching-calculator.no-barrel-note" }, true, decimals)
    return
  end

  add_row_cells(gui_table, row_id, {
    type = "checkbox",
    name = row_id .. "_include",
    state = true,
    tooltip = { "ocs-launching-calculator.toggle-barrel" },
    tags = {
      row_type = "barrelled-fluid",
      fluid_name = entry.name,
      fluid_amount = amount,
      barrel_name = barrel.prototype.name,
      barrel_amount = barrel.amount,
      total_mass = 0
    }
  })
  set_row_display(gui_table, row_id, barrel.prototype, barrel.amount,
    barrel.prototype.weight / WEIGHT_PER_KILOGRAM, { "ocs-launching-calculator.converted-from-fluid" }, false, decimals)
end

---Switches a barrel-capable fluid row between its fluid and barrel displays.
local function update_fluid_row(checkbox, decimals)
  local gui_table = checkbox.parent
  local row_id = checkbox.name:gsub("_include$", "")
  local tags = checkbox.tags
  if checkbox.state then
    local barrel = prototypes.item[tags.barrel_name]
    set_row_display(gui_table, row_id, barrel, tags.barrel_amount,
      barrel.weight / WEIGHT_PER_KILOGRAM, { "ocs-launching-calculator.converted-from-fluid" }, false, decimals)
  else
    local fluid = prototypes.fluid[tags.fluid_name]
    set_row_display(gui_table, row_id, fluid, tags.fluid_amount, 0,
      { "ocs-launching-calculator.fluid-direct-note" }, true, decimals)
  end
end

local function add_sum_row(gui_table, side, total, decimals)
  gui_table.add { type = "label", caption = "" }
  gui_table.add { type = "label", caption = "Σ", style = "caption_label" }
  gui_table.add {
    type = "label",
    caption = { side == "input" and "ocs-launching-calculator.sum-inputs" or "ocs-launching-calculator.sum-outputs" },
    style = "caption_label"
  }
  gui_table.add { type = "label", caption = "" }
  gui_table.add { type = "label", caption = "" }
  gui_table.add {
    type = "label",
    name = "ocs_launching_calculator_" .. side .. "_mass_sum",
    caption = display_number(total, decimals),
    style = "caption_label"
  }
  -- Future rocket-ratio sum cell:
  -- gui_table.add { type = "label", caption = display_number(total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals) }
end

local function included_total(gui_table)
  local total = 0
  for _, child in pairs(gui_table.children) do
    if child.type == "checkbox" and child.tags and child.tags.total_mass and child.state then
      total = total + child.tags.total_mass
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

---Returns the dedicated sum table so both sides always share one baseline.
local function get_sum_table(frame, side)
  local sums_flow = frame["ocs_launching_calculator_sums"]
  if not (sums_flow and sums_flow.valid) then return nil end
  return sums_flow[side == "input" and INPUT_SUM_TABLE_NAME or OUTPUT_SUM_TABLE_NAME]
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
  local input_sum_table = get_sum_table(frame, "input")
  local output_sum_table = get_sum_table(frame, "output")
  local input_mass_sum = input_sum_table and input_sum_table["ocs_launching_calculator_input_mass_sum"]
  local output_mass_sum = output_sum_table and output_sum_table["ocs_launching_calculator_output_mass_sum"]

  if not (input_mass_sum and input_mass_sum.valid
        and output_mass_sum and output_mass_sum.valid) then
    return
  end

  input_mass_sum.caption = display_number(input_total, decimals)
  output_mass_sum.caption = display_number(output_total, decimals)
  -- Future rocket-ratio updates:
  -- input_ratio_sum.caption = display_number(input_total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals)
  -- output_ratio_sum.caption = display_number(output_total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals)

  local recommendation = frame[RECOMMENDATION_NAME]
  if not (recommendation and recommendation.valid) then return end
  if input_total < output_total then
    recommendation.caption = { "ocs-launching-calculator.recommend-inputs" }
  elseif output_total < input_total then
    recommendation.caption = { "ocs-launching-calculator.recommend-outputs" }
  else
    recommendation.caption = { "ocs-launching-calculator.recommend-equal" }
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
    local sum_table = get_sum_table(frame, side)
    sum_table.clear()
    add_sum_row(sum_table, side, 0, decimals)
  end
  frame[RECOMMENDATION_NAME].caption = { "ocs-launching-calculator.select-recipe" }
end

local function show_recipe(player, recipe_name)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.valid) then return end

  local recipe = recipe_name and prototypes.recipe[recipe_name]
  if not recipe then
    frame["ocs_launching_calculator_selection"].ocs_launching_calculator_recipe_name.caption = {
      "ocs-launching-calculator.no-recipe" }
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
    add_item_row(output_table, "output", index, product, expected_product_amount(recipe, index), decimals)
  end
  local input_sum_table = get_sum_table(frame, "input")
  local output_sum_table = get_sum_table(frame, "output")
  input_sum_table.clear()
  output_sum_table.clear()
  add_sum_row(input_sum_table, "input", 0, decimals)
  add_sum_row(output_sum_table, "output", 0, decimals)
  recalculate(player)
end

local function create_calculator(player)
  local old_frame = player.gui.screen[FRAME_NAME]
  if old_frame then old_frame.destroy() end
  local frame = player.gui.screen.add { type = "frame", name = FRAME_NAME, direction = "vertical" }
  frame.auto_center = true
  frame.style.width = WINDOW_WIDTH

  local titlebar = frame.add { type = "flow", direction = "horizontal" }
  titlebar.drag_target = frame
  titlebar.style.horizontally_stretchable = true
  titlebar.add { type = "label", caption = { "ocs-launching-calculator.title" }, style = "frame_title" }
  local filler = titlebar.add { type = "empty-widget", style = "draggable_space_header" }
  filler.style.horizontally_stretchable = true
  filler.drag_target = frame
  titlebar.add {
    type = "sprite-button",
    name = "ocs_launching_calculator_close",
    sprite = "utility/close",
    style = "frame_action_button",
    tooltip = { "ocs-launching-calculator.close" }
  }

  local selection = frame.add {
    type = "frame",
    name = "ocs_launching_calculator_selection",
    direction = "horizontal",
    style = "inside_shallow_frame_with_padding"
  }
  selection.add { type = "label", caption = { "ocs-launching-calculator.recipe" } }
  selection.add { type = "choose-elem-button", name = RECIPE_PICKER_NAME, elem_type = "recipe" }
  selection.add { type = "label", name = "ocs_launching_calculator_recipe_name", caption = { "ocs-launching-calculator.no-recipe" } }

  local body = frame.add {
    type = "flow",
    name = "ocs_launching_calculator_body",
    direction = "horizontal"
  }
  local input_column = body.add {
    type = "frame",
    name = "ocs_launching_calculator_input_column",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  }
  input_column.add { type = "label", caption = { "ocs-launching-calculator.inputs" }, style = "heading_2_label" }
  input_column.style.width = COLUMN_WIDTH
  input_column.add { type = "table", name = INPUT_TABLE_NAME, column_count = 6 }
  local output_column = body.add {
    type = "frame",
    name = "ocs_launching_calculator_output_column",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  }
  output_column.add { type = "label", caption = { "ocs-launching-calculator.outputs" }, style = "heading_2_label" }
  output_column.style.width = COLUMN_WIDTH
  output_column.add { type = "table", name = OUTPUT_TABLE_NAME, column_count = 6 }
  local sums_flow = frame.add {
    type = "frame", name = "ocs_launching_calculator_sums", direction = "horizontal",
    style = "inside_shallow_frame_with_padding"
  }
  sums_flow.add { type = "table", name = INPUT_SUM_TABLE_NAME, column_count = 6 }
  sums_flow.add { type = "table", name = OUTPUT_SUM_TABLE_NAME, column_count = 6 }
  sums_flow[INPUT_SUM_TABLE_NAME].style.width = COLUMN_WIDTH
  sums_flow[OUTPUT_SUM_TABLE_NAME].style.width = COLUMN_WIDTH
  frame.add { type = "label", name = RECOMMENDATION_NAME, caption = { "ocs-launching-calculator.select-recipe" }, style = "heading_2_label" }
  clear_recipe_tables(player)
end

local function create_main_button(player)
  local flow = mod_gui.get_button_flow(player)
  if flow.ocs_launching_calculator_button then return end
  flow.add {
    type = "sprite-button", name = "ocs_launching_calculator_button", sprite = "item/rocket-part",
    tooltip = { "ocs-launching-calculator.title" }, style = mod_gui.button_style
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
    if element.tags.row_type == "barrelled-fluid" then
      update_fluid_row(element, player_decimals(game.get_player(event.player_index)))
    end
    recalculate(game.get_player(event.player_index))
  end
end)
