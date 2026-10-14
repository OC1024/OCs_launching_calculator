local mod_gui = require("mod-gui")

local FRAME_NAME = "ocs_launching_calculator_frame"
local RECIPE_PICKER_NAME = "ocs_launching_calculator_recipe_picker"
local INPUT_TABLE_NAME = "ocs_launching_calculator_inputs"
local OUTPUT_TABLE_NAME = "ocs_launching_calculator_outputs"
local INPUT_SUM_TABLE_NAME = "ocs_launching_calculator_input_sum_table"
local OUTPUT_SUM_TABLE_NAME = "ocs_launching_calculator_output_sum_table"
local RECOMMENDATION_NAME = "ocs_launching_calculator_recommendation"
local WEIGHT_PER_KILOGRAM = 1000 -- mass is in grams
local WEIGHT_PER_TON = 1e6       -- mass is in grams
local WINDOW_WIDTH = 1100
local COLUMN_WIDTH = 536
-- Future rocket-ratio feature:
local ROCKET_LIFT_WEIGHT = prototypes.utility_constants.default_rocket_lift_weight
local rocket_capacity = ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM

-- ==============================================================================
-- Helper Functions

local function display_number(value, decimals)
  decimals = math.max(0, math.floor(tonumber(decimals) or 0))
  return string.format("%." .. decimals .. "f", value)
end

-- per player value, so not gobal/local variable
local function player_decimals(player)
  return settings.get_player_settings(player)["round_decimals"].value or 2
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

---Returns the total quantity of included items, including barrels but excluding unbarrelled fluids.
local function included_amount_total(gui_table)
  local total = 0
  for _, element in pairs(gui_table.children) do
    if element.type == "checkbox" and element.valid and element.state then
      local tags = element.tags
      if tags.row_type == "item" then
        total = total + (tags.amount or 0)
      elseif tags.row_type == "barrelled-fluid" then
        total = total + (tags.barrel_amount or 0)
      end
    end
  end
  return total
end


---Returns the best recipe for a clicked item or fluid.
---Prefers an exact recipe-name match, otherwise requires a unique match.
local function find_unique_recipe_for_product(item_name, item_type)
  local unique_recipe = nil
  for _, recipe in pairs(prototypes.recipe) do
    -- Exclude recycling recipes.
    local function is_recycling_recipe(recipe)
      for _, category in pairs(recipe.categories) do
        if category == "recycling" then return true end
      end
      return false
    end
    if not is_recycling_recipe(recipe) then
      for _, product in ipairs(recipe.products) do
        local product_type = product.type or "item"

        if product.name == item_name and product_type == item_type then
          -- Prefer a recipe whose name matches the product.
          if recipe.name == item_name then
            return recipe
          end
          -- Otherwise, track whether the match is unique.
          if unique_recipe then
            unique_recipe = false
            break
          end
          unique_recipe = recipe
          break
        end
      end
    end
  end

  return unique_recipe or nil
end

-- ==============================================================================
-- GUI Functions

---Input/Output tables
local function add_headers(gui_table)
  for _, header in ipairs({
    { caption = "" }, -- checkbox
    { caption = { "ocs-launching-calculator.header-icon" } },
    { caption = { "ocs-launching-calculator.header-item" } },
    { caption = "#",                                       tooltip = { "ocs-launching-calculator.header-amount" } },
    { caption = "m [kg]",                                  tooltip = { "ocs-launching-calculator.header-unit-mass" } },
    { caption = "# × m [kg]",                              tooltip = { "ocs-launching-calculator.header-total-mass" } }, -- "# · m" "# × m"
    { caption = "[img=item/rocket-part]",                  tooltip = { "ocs-launching-calculator.header-rocket-ratio" } },
    { caption = "" },                                                                                                    -- warnings
  }) do
    gui_table.add {
      type = "label",
      caption = header.caption,
      tooltip = header.tooltip,
      style = "caption_label",
    }
  end
  -- Future rocket-ratio column: {"ocs-launching-calculator.header-rocket-ratio"}
end

---Updates a row's icon, label, quantities, and the mass used in its sum.
local function set_row_display(gui_table, row_id, prototype, amount, unit_mass, note, is_fluid, decimals)
  local total_mass = amount * unit_mass
  local rocket_ratio = total_mass / rocket_capacity
  local exceeds_capacity = not is_fluid and unit_mass > rocket_capacity

  -- Item icon and name
  local icon_holder = gui_table[row_id .. "_icon_holder"]
  icon_holder.clear()
  icon_holder.add {
    type = "sprite-button",
    sprite = (is_fluid and "fluid/" or "item/") .. prototype.name,
    style = "slot_button",
    tooltip = { "", note or prototype.localised_name, "\n", { "ocs-launching-calculator.click-to-select-recipe" } },
    tags = {
      action = "select-recipe-for-product",
      item_name = prototype.name,
      item_type = is_fluid and "fluid" or "item"
    },
  }
  gui_table[row_id .. "_name"].caption = prototype.localised_name
  gui_table[row_id .. "_name"].tooltip = note

  -- Quantity and mass values
  gui_table[row_id .. "_amount"].caption = display_number(amount, decimals)
  gui_table[row_id .. "_unit_mass"].caption = display_number(unit_mass, decimals)
  gui_table[row_id .. "_unit_mass"].style = exceeds_capacity and "bold_red_label" or "label"
  gui_table[row_id .. "_total_mass"].caption = display_number(total_mass, decimals)
  gui_table[row_id .. "_rocket_ratio"].caption = display_number(rocket_ratio, decimals)

  -- Launchability warning
  gui_table[row_id .. "_warning"].caption = exceeds_capacity and "[img=utility/warning_icon]" or ""
  gui_table[row_id .. "_warning"].tooltip = exceeds_capacity and
      { "ocs-launching-calculator.unit-mass-exceeds-rocket-capacity" } or nil

  -- Update mass used by aggregate calculations
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
  gui_table.add { type = "label", name = row_id .. "_rocket_ratio" }
  gui_table.add { type = "label", name = row_id .. "_warning" }
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
      tags = { row_type = "item", amount = amount, total_mass = amount * unit_mass }
    })
    set_row_display(gui_table, row_id, prototype, amount, unit_mass, nil, false, decimals)
    return
  end

  -- if barreled
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

  -- if fluid
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

local function add_sum_row(gui_table, side, amount_total, total, decimals)
  local type_caption = {
    side == "input"
    and "ocs-launching-calculator.sum-inputs"
    or "ocs-launching-calculator.sum-outputs"
  }

  -- Header row
  gui_table.add {
    type = "label",
    caption = { "ocs-launching-calculator.header-type" },
    style = "caption_label",
  }
  gui_table.add {
    type = "label",
    caption = "",
  }
  gui_table.add {
    type = "label",
    caption = "Σ #",
    tooltip = { "ocs-launching-calculator.header-sum-amount" },
    style = "caption_label",
  }
  gui_table.add {
    type = "label",
    caption = "Σ (# × m)",
    tooltip = { "ocs-launching-calculator.header-sum-mass" },
    style = "caption_label",
  }
  gui_table.add {
    type = "label",
    caption = "[img=item/rocket-part]",
    -- caption = { "ocs-launching-calculator.header-rocket-ratio" },
    tooltip = { "ocs-launching-calculator.header-rocket-ratio-tooltip" },
    style = "caption_label",
  }

  -- Values row
  gui_table.add {
    type = "label",
    caption = type_caption,
    style = "caption_label",
  }
  gui_table.add {
    type = "label",
    caption = "",
  }
  gui_table.add {
    type = "label",
    name = "ocs_launching_calculator_" .. side .. "_amount_sum",
    caption = display_number(amount_total, decimals),
    style = "label",
  }
  gui_table.add {
    type = "label",
    name = "ocs_launching_calculator_" .. side .. "_mass_sum",
    caption = display_number(total, decimals),
    style = "label",
  }
  gui_table.add {
    type = "label",
    name = "ocs_launching_calculator_" .. side .. "_rocket_ratio_sum",
    caption = display_number(total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals),
    style = "label",
  }

  -- Future rocket-ratio cell:
  -- gui_table.add {
  --   type = "label",
  --   name = "ocs_launching_calculator_" .. side .. "_rocket_ratio_sum",
  --   caption = display_number(total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals),
  --   style = "caption_label",
  -- }
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

---Standard Recipe Frame
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

---Filling tables for inputs/outputs/summs and display recommendation
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
  local input_amount_total = included_amount_total(input_table)
  local output_amount_total = included_amount_total(output_table)
  local input_sum_table = get_sum_table(frame, "input")
  local output_sum_table = get_sum_table(frame, "output")
  local input_mass_sum = input_sum_table and input_sum_table["ocs_launching_calculator_input_mass_sum"]
  local output_mass_sum = output_sum_table and output_sum_table["ocs_launching_calculator_output_mass_sum"]
  local input_amount_sum = input_sum_table and input_sum_table["ocs_launching_calculator_input_amount_sum"]
  local output_amount_sum = output_sum_table and output_sum_table["ocs_launching_calculator_output_amount_sum"]
  -- rocket_ratio
  local input_ratio_sum = input_sum_table and input_sum_table["ocs_launching_calculator_input_rocket_ratio_sum"]
  local output_ratio_sum = output_sum_table and output_sum_table["ocs_launching_calculator_output_rocket_ratio_sum"]

  if not (
        input_mass_sum and input_mass_sum.valid
        and output_mass_sum and output_mass_sum.valid
        and input_amount_sum and input_amount_sum.valid
        and output_amount_sum and output_amount_sum.valid
        and input_ratio_sum and input_ratio_sum.valid
        and output_ratio_sum and output_ratio_sum.valid
      ) then
    return
  end

  input_amount_sum.caption = display_number(input_amount_total, decimals)
  output_amount_sum.caption = display_number(output_amount_total, decimals)
  input_mass_sum.caption = display_number(input_total, decimals)
  output_mass_sum.caption = display_number(output_total, decimals)
  -- Future rocket-ratio updates:
  input_ratio_sum.caption = display_number(input_total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals)
  output_ratio_sum.caption = display_number(output_total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals)

  local recommendation = frame[RECOMMENDATION_NAME]
  if not (recommendation and recommendation.valid) then return end
  local detail = frame["ocs_launching_calculator_recommendation_detail"]
  if not (detail and detail.valid) then return end
  if input_total < output_total then
    recommendation.caption = { "ocs-launching-calculator.recommend-inputs" }
  elseif output_total < input_total then
    recommendation.caption = { "ocs-launching-calculator.recommend-outputs" }
  else
    recommendation.caption = { "ocs-launching-calculator.recommend-equal" }
  end
  local heavier_total = math.max(input_total, output_total)
  local lighter_total = math.min(input_total, output_total)

  if heavier_total > 0 and lighter_total < heavier_total then
    local improvement = (heavier_total - lighter_total) / heavier_total * 100
    local ratio = heavier_total / lighter_total
    detail.caption = {
      "ocs-launching-calculator.recommendation-detail",
      display_number(improvement, decimals)
    }
    local detail2 = frame["ocs_launching_calculator_recommendation_detail2"]
    if detail2 and detail2.valid then
      detail2.caption = {
        "ocs-launching-calculator.recommendation-detail2",
        display_number(ratio, decimals)
      }
    end
  else
    detail.caption = ""
    local detail2 = frame["ocs_launching_calculator_recommendation_detail2"]
    if detail2 and detail2.valid then
      detail2.caption = ""
    end
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
    if sum_table and sum_table.valid then
      sum_table.clear()
      add_sum_row(sum_table, side, 0, 0, decimals)
    end
  end
  frame[RECOMMENDATION_NAME].caption = { "ocs-launching-calculator.select-recipe" }
end

local function show_recipe(player, recipe_name)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.valid) then return end

  -- Update recipe picker when a recipe is selected by clicking an item.
  local selection = frame["ocs_launching_calculator_selection"]
  local recipe_picker = selection and selection[RECIPE_PICKER_NAME]
  if recipe_picker and recipe_picker.valid then
    recipe_picker.elem_value = recipe_name
  end

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
    add_item_row(output_table, "output", index, product, recipe.get_product_amount(index), decimals)
  end
  local input_sum_table = get_sum_table(frame, "input")
  local output_sum_table = get_sum_table(frame, "output")
  if input_sum_table and input_sum_table.valid then
    input_sum_table.clear()
    add_sum_row(input_sum_table, "input", 0, 0, decimals)
  end
  if output_sum_table and output_sum_table.valid then
    output_sum_table.clear()
    add_sum_row(output_sum_table, "output", 0, 0, decimals)
  end
  recalculate(player)
end

---Main GUI frame
local function create_calculator(player)
  local old_frame = player.gui.screen[FRAME_NAME]
  if old_frame then old_frame.destroy() end
  local frame = player.gui.screen.add { type = "frame", name = FRAME_NAME, direction = "vertical" }
  frame.auto_center = true
  frame.style.width = WINDOW_WIDTH

  -- titlebar
  local titlebar = frame.add { type = "flow", direction = "horizontal" }
  titlebar.drag_target = frame
  titlebar.style.horizontally_stretchable = true
  titlebar.add {
    type = "label",
    caption = { "ocs-launching-calculator.title" },
    style = "frame_title",
    ignored_by_interaction = true,
  }

  -- filler
  local filler = titlebar.add {
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  }
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  filler.style.right_margin = 4
  titlebar.add {
    type = "sprite-button",
    name = "ocs_launching_calculator_close",
    sprite = "utility/close",
    style = "frame_action_button",
    tooltip = { "ocs-launching-calculator.close" }
  }

  -- Recipe Selection Frame
  local selection = frame.add {
    type = "frame",
    name = "ocs_launching_calculator_selection",
    direction = "horizontal",
    style = "inside_shallow_frame_with_padding"
  }
  selection.add { type = "label", caption = { "ocs-launching-calculator.recipe" } }
  selection.add { type = "choose-elem-button", name = RECIPE_PICKER_NAME, elem_type = "recipe" }
  selection.add { type = "label", name = "ocs_launching_calculator_recipe_name", caption = { "ocs-launching-calculator.no-recipe" } }

  -- Input/Output Frame
  local body = frame.add {
    type = "flow",
    name = "ocs_launching_calculator_body",
    direction = "horizontal"
  }
  local TABLE_COLUMN_COUNT = 8
  local TABLE_SPACING = 8 * 2

  -- Input Frame
  local input_column = body.add {
    type = "frame",
    name = "ocs_launching_calculator_input_column",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  }
  input_column.add { type = "label", caption = { "ocs-launching-calculator.inputs" }, style = "heading_2_label" }
  input_column.style.width = COLUMN_WIDTH
  local input_table = input_column.add {
    type = "table",
    name = INPUT_TABLE_NAME,
    column_count = TABLE_COLUMN_COUNT
  }
  input_table.style.horizontal_spacing = TABLE_SPACING

  -- Output Frame
  local output_column = body.add {
    type = "frame",
    name = "ocs_launching_calculator_output_column",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  }
  output_column.add { type = "label", caption = { "ocs-launching-calculator.outputs" }, style = "heading_2_label" }
  output_column.style.width = COLUMN_WIDTH
  local output_table = output_column.add {
    type = "table",
    name = OUTPUT_TABLE_NAME,
    column_count = TABLE_COLUMN_COUNT
  }
  output_table.style.horizontal_spacing = TABLE_SPACING

  -- Sum Frame
  local sums_flow = frame.add {
    type = "frame",
    name = "ocs_launching_calculator_sums",
    direction = "horizontal",
    style = "inside_shallow_frame_with_padding"
  }
  local input_sum_table = sums_flow.add {
    type = "table",
    name = INPUT_SUM_TABLE_NAME,
    column_count = 5
  }
  input_sum_table.style.horizontal_spacing = TABLE_SPACING
  input_sum_table.style.width = COLUMN_WIDTH
  local output_sum_table = sums_flow.add {
    type = "table",
    name = OUTPUT_SUM_TABLE_NAME,
    column_count = 5
  }
  output_sum_table.style.width = COLUMN_WIDTH
  output_sum_table.style.horizontal_spacing = TABLE_SPACING

  -- Recomendation Frame
  frame.add {
    type = "label",
    name = RECOMMENDATION_NAME,
    caption = { "ocs-launching-calculator.select-recipe" },
    style = "heading_2_label",
  }
  frame.add {
    type = "label",
    name = "ocs_launching_calculator_recommendation_detail",
    caption = "",
    style = "label"
  }
  frame.add {
    type = "label",
    name = "ocs_launching_calculator_recommendation_detail2",
    caption = "",
    style = "label"
  }
  clear_recipe_tables(player)
end

---Main button (top left corner)
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
    return
  elseif element.name == "ocs_launching_calculator_close" then
    local frame = player.gui.screen[FRAME_NAME]
    if frame then frame.destroy() end
    return
  end

  -- clicking on icon selects "obvious" recipe
  local tags = element.tags
  if tags.action == "select-recipe-for-product" then
    local recipe = find_unique_recipe_for_product(tags.item_name, tags.item_type)
    if recipe then
      show_recipe(player, recipe.name)
    end
    return
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
