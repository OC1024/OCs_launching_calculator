local mod_gui = require("mod-gui")

local MANE_NAME = "ocs_launching_calculator" -- easteregg
local FRAME_NAME = MANE_NAME .. "_frame"
local RECIPE_PICKER_NAME = MANE_NAME .. "_recipe_picker"
local INPUT_TABLE_NAME = MANE_NAME .. "_inputs"
local OUTPUT_TABLE_NAME = MANE_NAME .. "_outputs"
local INPUT_SUM_TABLE_NAME = MANE_NAME .. "_input_sum_table"
local OUTPUT_SUM_TABLE_NAME = MANE_NAME .. "_output_sum_table"
local RECOMMENDATION_NAME = MANE_NAME .. "_recommendation"

local WEIGHT_PER_KILOGRAM = 1e3 -- mass is in grams
local WEIGHT_PER_TON = 1e6      -- mass is in grams
local ROCKET_LIFT_WEIGHT = prototypes.utility_constants.default_rocket_lift_weight
local rocket_capacity = ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM

--- Lua Things
---@class uint
---@class LuaEntity
---@class LuaPlayer
---@class EventData
---@class ItemPrototype
---@class FluidPrototype
---@class LocalisedString
---@class LuaGuiElement

-- ==============================================================================
-- Helper Functions

---Rounds to a given decimal place, zero possible; adds spaces as thousands separators.
---@param value number
---@param decimals number
---@return string
local function display_number(value, decimals)
  decimals = math.max(0, math.floor(tonumber(decimals) or 0))
  local formatted = string.format("%." .. decimals .. "f", value)
  local integer, fraction = formatted:match("^(-?%d+)(.*)$")
  integer = integer:reverse():gsub("(%d%d%d)", "%1'"):reverse():gsub("^'", "")
  return integer .. fraction
end

---Returns GUI settings for a player.
local function player_gui_settings(player)
  local settings = settings.get_player_settings(player)

  local window_width = settings["oc-calc-window-width"].value
  local show_item_name = settings["oc-calc-show-item-name"].value
  local slim_factor  = settings["oc-calc-compact-window-factor"].value / 100 or 0.7 -- in per cent
  window_width = show_item_name and window_width or window_width * slim_factor  -- arbitrary reduction
  local decimals = settings["round_decimals"].value

  return {
    window_width = window_width,
    column_width = window_width / 2 - 14, -- 12 is the usual padding size
    show_item_name = show_item_name,
    decimals = decimals
  }
end

---Get persistent calculator state for a player. Contains recipe, rocket, and silo.
---@param player LuaPlayer
---@return table
local function player_calculator_state(player)
  storage.calculator_state = storage.calculator_state or {}
  local state = storage.calculator_state[player.index]
  if not state then
    state = {
      selected_recipe = nil,             -- main recipe for the calculator
      selected_silo_name = nil,          -- entity where the rocket is crafted
      selected_rocket_recipe_name = nil, -- recipe of the rocket
      window_location = nil,
      is_minimised = false,

    }
    storage.calculator_state[player.index] = state
  end
  return state
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

---Check whether an array contains a value.
---@param array table
---@param value any
---@return boolean
local function array_contains(array, value)
  for _, entry in pairs(array) do
    if entry == value then return true end
  end
  return false
end

-- ==============================================================================
-- Rockets and Silo Functions

---Get all entities usable as rocket silos.
---@return table[] silos
local function get_rocket_silos()
  local silos = {}
  for name, prototype in pairs(prototypes.entity) do
    local is_rocket_silo = prototype.type == "rocket-silo"
    local has_rocket_building_category =
        prototype.crafting_categories
        and prototype.crafting_categories["rocket-building"]
    if is_rocket_silo or has_rocket_building_category then
      silos[#silos + 1] = {
        name = name,
        localised_name = prototype.localised_name,
        sprite = "entity/" .. name,
        lift_weight = prototype.lift_weight,
        rocket_parts_required = prototype.rocket_parts_required,
      }
    end
  end
  table.sort(silos, function(a, b)
    return a.name < b.name
  end)
  return silos
end

---Get recipes in the rocket-building category.
---@return table[] recipes
local function get_rocket_recipes()
  local recipes = {}
  for name, prototype in pairs(prototypes.recipe) do
    if prototype.categories and array_contains(prototype.categories, "rocket-building") then
      recipes[#recipes + 1] = {
        name = name,
        localised_name = prototype.localised_name,
        sprite = "recipe/" .. name,
        products = prototype.products,
      }
    end
  end
  table.sort(recipes, function(a, b)
    return a.name < b.name
  end)
  return recipes
end

---Build dropdown items and resolve the saved selection.
---@param entries table[]
---@param selected_name string?
---@return string[] items
---@return integer selected_index
---@return table? selected_entry
local function prepare_selection(entries, selected_name)
  local items = {}
  local selected_index = 0
  local selected_entry = nil

  for i, entry in ipairs(entries) do
    items[i] = entry.localised_name or entry.name

    if entry.name == selected_name then
      selected_index = i
      selected_entry = entry
    end
  end

  if not selected_entry and #entries > 0 then
    selected_index = 1
    selected_entry = entries[1]
  end

  return items, selected_index, selected_entry
end

-- ==============================================================================
-- GUI Helper Functions

---Headers for Input/Output tables
local function add_headers(gui_table, gui_settings)
  local headers = {
    { caption = "" }, -- checkbox
    { caption = { "ocs-launching-calculator.header-icon" } },
  }

  if gui_settings.show_item_name then
    table.insert(headers, {
      caption = { "ocs-launching-calculator.header-item" },
    })
  end

  for _, header in ipairs({
    { caption = "#",                      tooltip = { "ocs-launching-calculator.header-amount" } },
    { caption = "m [kg]",                 tooltip = { "ocs-launching-calculator.header-unit-mass" } },
    { caption = "# × m [kg]",             tooltip = { "ocs-launching-calculator.header-total-mass" } }, -- "# · m" "# × m"
    { caption = "[img=item/rocket-part]", tooltip = { "ocs-launching-calculator.header-rocket-ratio" } },
    { caption = "" },                                                                                   -- warnings
  }) do
    table.insert(headers, header)
  end

  for _, header in ipairs(headers) do
    gui_table.add {
      type = "label",
      caption = header.caption,
      tooltip = header.tooltip,
      style = "caption_label",
    }
  end
end

---Updates a row's icon, optional item name, quantities, and mass used in aggregate calculations.
---@param gui_table LuaGuiElement The table containing the row.
---@param row_id string The row's identifier prefix.
---@param prototype ItemPrototype|FluidPrototype The item or fluid prototype to display.
---@param amount number The quantity of the item or fluid.
---@param unit_mass number The mass of one unit, in kilograms.
---@param note LocalisedString|nil Optional tooltip note.
---@param is_fluid boolean Whether the displayed prototype is a fluid.
---@param gui_settings table Contains decimals, windwow size settings per player.
local function set_row_display(gui_table, row_id, prototype, amount, unit_mass, note, is_fluid, gui_settings)
  local total_mass = amount * unit_mass
  local rocket_ratio = total_mass / rocket_capacity
  local exceeds_capacity = not is_fluid and unit_mass > rocket_capacity

  -- Item icon
  local icon_holder = gui_table[row_id .. "_icon_holder"]
  icon_holder.clear()
  -- Item name OR tooltip
  local tooltip = { "" }
  if not gui_settings.show_item_name then
    table.insert(tooltip, prototype.localised_name)
  end
  if note then
    if #tooltip > 1 then
      table.insert(tooltip, "\n")
    end
    table.insert(tooltip, note)
  end
  icon_holder.add {
    type = "sprite-button",
    sprite = (is_fluid and "fluid/" or "item/") .. prototype.name,
    style = "slot_button",
    tooltip = tooltip,
    tags = {
      action = "select-recipe-for-product",
      item_name = prototype.name,
      item_type = is_fluid and "fluid" or "item"
    },
  }
  if gui_settings.show_item_name then
    gui_table[row_id .. "_name"].caption = prototype.localised_name
    gui_table[row_id .. "_name"].tooltip = note
  else
    table.insert(tooltip, prototype.localised_name)
  end

  -- Quantity and mass values
  gui_table[row_id .. "_amount"].caption = display_number(amount, gui_settings.decimals)
  gui_table[row_id .. "_unit_mass"].caption = display_number(unit_mass, gui_settings.decimals)
  gui_table[row_id .. "_unit_mass"].style = exceeds_capacity and "bold_red_label" or "label"
  gui_table[row_id .. "_total_mass"].caption = display_number(total_mass, gui_settings.decimals)
  gui_table[row_id .. "_rocket_ratio"].caption = display_number(rocket_ratio, gui_settings.decimals)

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
local function add_row_cells(gui_table, row_id, checkbox_spec, gui_settings)
  local checkbox = gui_table.add(checkbox_spec)
  gui_table.add { type = "flow", name = row_id .. "_icon_holder", direction = "horizontal" }
  if gui_settings.show_item_name then
    gui_table.add { type = "label", name = row_id .. "_name" }
  end
  gui_table.add { type = "label", name = row_id .. "_amount" }
  gui_table.add { type = "label", name = row_id .. "_unit_mass" }
  gui_table.add { type = "label", name = row_id .. "_total_mass" }
  gui_table.add { type = "label", name = row_id .. "_rocket_ratio" }
  gui_table.add { type = "label", name = row_id .. "_warning" }
  return checkbox
end

---Adds an item row or a fluid row with an optional barrel representation.
local function add_item_row(gui_table, side, index, entry, amount, gui_settings)
  local row_id = "ocs_launching_calculator_" .. side .. "_" .. index
  -- if non-barrel solid
  if entry.type ~= "fluid" then
    local prototype = prototypes.item[entry.name]
    local unit_mass = prototype and prototype.weight / WEIGHT_PER_KILOGRAM or 0
    add_row_cells(gui_table, row_id, {
      type = "checkbox",
      name = row_id .. "_include",
      state = true,
      tooltip = { "ocs-launching-calculator.include-row" },
      tags = { row_type = "item", amount = amount, total_mass = amount * unit_mass }
    }, gui_settings)
    set_row_display(gui_table, row_id, prototype, amount, unit_mass, nil, false, gui_settings)
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
    }, gui_settings)
    set_row_display(gui_table, row_id, fluid, amount, 0, { "ocs-launching-calculator.no-barrel-note" }, true,
      gui_settings)
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
  }, gui_settings)
  set_row_display(gui_table, row_id, barrel.prototype, barrel.amount, barrel.prototype.weight / WEIGHT_PER_KILOGRAM,
    { "ocs-launching-calculator.converted-from-fluid" }, false, gui_settings)
end

---Switches a barrel-capable fluid row between its fluid and barrel displays.
local function update_fluid_row(checkbox, gui_settings)
  local gui_table = checkbox.parent
  local row_id = checkbox.name:gsub("_include$", "")
  local tags = checkbox.tags
  if checkbox.state then
    local barrel = prototypes.item[tags.barrel_name]
    set_row_display(gui_table, row_id, barrel, tags.barrel_amount,
      barrel.weight / WEIGHT_PER_KILOGRAM, { "ocs-launching-calculator.converted-from-fluid" }, false, gui_settings)
  else
    local fluid = prototypes.fluid[tags.fluid_name]
    set_row_display(gui_table, row_id, fluid, tags.fluid_amount, 0,
      { "ocs-launching-calculator.fluid-direct-note" }, true, gui_settings)
  end
end

---Add header and totals rows to a recipe summary table.
---@param gui_table LuaGuiElement
---@param side "input"|"output"
---@param amount_total number Total item amount.
---@param total number Total mass.
---@param gui_settings table
---@return nil
local function add_sum_row(gui_table, side, amount_total, total, gui_settings)
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
    caption = display_number(amount_total, gui_settings.decimals),
    style = "label",
  }
  gui_table.add {
    type = "label",
    name = "ocs_launching_calculator_" .. side .. "_mass_sum",
    caption = display_number(total, gui_settings.decimals),
    style = "label",
  }
  gui_table.add {
    type = "label",
    name = "ocs_launching_calculator_" .. side .. "_rocket_ratio_sum",
    caption = display_number(total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), gui_settings.decimals),
    style = "label",
  }
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
  local io_body = frame["ocs_launching_calculator_io_body"]
  if not (io_body and io_body.valid) then return nil end

  local column_name = side == "input"
      and "ocs_launching_calculator_input_column"
      or "ocs_launching_calculator_output_column"

  local column = io_body[column_name]
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
local function recalculate(player, selected_recipe)
  local head_frame = player.gui.screen[FRAME_NAME]
  if not (head_frame and head_frame.valid) then return end
  local frame = head_frame["ocs_launching_calculator_content"]
  if not (frame and frame.valid) then return end
  local input_table = get_recipe_table(frame, "input")
  local output_table = get_recipe_table(frame, "output")
  if not (input_table and input_table.valid and output_table and output_table.valid) then
    return
  end

  local gui_settings = player_gui_settings(player)
  local decimals = gui_settings.decimals
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

  if not ( -- valid
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
  input_ratio_sum.caption = display_number(input_total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals)
  output_ratio_sum.caption = display_number(output_total / (ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM), decimals)

  local recommendation = frame[RECOMMENDATION_NAME]
  local detail1 = frame["ocs_launching_calculator_recommendation_detail1"]
  local detail2 = frame["ocs_launching_calculator_recommendation_detail2"]
  detail1.visible = false
  detail2.visible = false
  if not (recommendation and recommendation.valid
        and detail1 and detail1.valid
        and detail2 and detail2.valid
      ) then
    return
  end

  -- No recipe selected: hide recommendation details
  if not selected_recipe then
    recommendation.caption = { "ocs-launching-calculator.select-recipe" }
    return
  end

  -- Equal totals: no recommendation needed
  if input_total == output_total then
    recommendation.caption = { "ocs-launching-calculator.recommend-equal" }
    return
  end

  -- Unequal totals
  local heavier_total = math.max(input_total, output_total)
  local lighter_total = math.min(input_total, output_total)
  local improvement = (heavier_total - lighter_total) / heavier_total * 100
  local ratio = (lighter_total == 0) and "∞" or display_number(heavier_total / lighter_total, decimals)
  recommendation.caption = input_total < output_total
      and { "ocs-launching-calculator.recommend-inputs" }
      or { "ocs-launching-calculator.recommend-outputs" }
  detail1.visible = true
  detail2.visible = true
  detail1.caption = { "ocs-launching-calculator.recommendation-detail1", ratio }
  detail2.caption = { "ocs-launching-calculator.recommendation-detail2", display_number(improvement, decimals) }
end

local function clear_recipe_tables(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.valid) then return end
  local gui_settings = player_gui_settings(player)
  for _, side in ipairs({ "input", "output" }) do
    local gui_table = get_recipe_table(frame, side)
    if not (gui_table and gui_table.valid) then return end
    gui_table.clear()
    add_headers(gui_table, gui_settings)
    local sum_table = get_sum_table(frame, side)
    if sum_table and sum_table.valid then
      sum_table.clear()
      add_sum_row(sum_table, side, 0, 0, gui_settings)
    end
  end
  frame[RECOMMENDATION_NAME].caption = { "ocs-launching-calculator.select-recipe" }
end

---Recipe Picker Frame
---@param player LuaPlayer
---@param recipe_name string|nil
local function show_recipe(player, recipe_name)
  local head_frame = player.gui.screen[FRAME_NAME]
  if not (head_frame and head_frame.valid) then return end
  local mane_frame = head_frame["ocs_launching_calculator_content"]
  if not (mane_frame and mane_frame.valid) then return end
  local gui_settings = player_gui_settings(player)

  -- Update recipe picker when a recipe is selected by clicking an item.
  local selection = mane_frame["ocs_launching_calculator_selection"]
  if not (selection and selection.valid) then return end
  local recipe_row = selection["ocs_launching_calculator_recipe_row"]
  local recipe_picker = recipe_row and recipe_row[RECIPE_PICKER_NAME]
  local recipe_name_label = recipe_row and recipe_row["ocs_launching_calculator_recipe_name"]

  log("SHOW picker valid: " .. tostring(recipe_picker and recipe_picker.valid))--debug
  log("SHOW label valid: " .. tostring(recipe_name_label and recipe_name_label.valid)) -- debug
  if not (recipe_picker and recipe_picker.valid and recipe_name_label and recipe_name_label.valid) then
    return
  end

  local recipe = recipe_name and prototypes.recipe[recipe_name]
  log("SHOW recipe_name: " .. serpent.line(recipe_name)) -- debug
  log("SHOW prototype exists: " .. tostring(recipe ~= nil)) -- debug
  if not recipe then
    recipe_picker.elem_value = nil
    recipe_name_label.caption = { "ocs-launching-calculator.no-recipe" }
    clear_recipe_tables(player)
    recalculate(player, nil)
    return
  end
  local state = player_calculator_state(player)
  state.selected_recipe = recipe_name
  if recipe_picker.elem_value ~= recipe_name then
    recipe_picker.elem_value = recipe_name
  end
  recipe_name_label.caption = recipe.localised_name
  log("SHOW label updated for: " .. recipe.name) -- debug

  local input_table = get_recipe_table(mane_frame, "input")
  local output_table = get_recipe_table(mane_frame, "output")
  if not (input_table and input_table.valid and output_table and output_table.valid) then
    return
  end

  input_table.clear()
  output_table.clear()
  add_headers(input_table, gui_settings)
  add_headers(output_table, gui_settings)
  for index, ingredient in ipairs(recipe.ingredients) do
    add_item_row(input_table, "input", index, ingredient, ingredient.amount, gui_settings)
  end
  for index, product in ipairs(recipe.products) do
    add_item_row(output_table, "output", index, product, recipe.get_product_amount(index), gui_settings)
  end
  local input_sum_table = get_sum_table(mane_frame, "input")
  local output_sum_table = get_sum_table(mane_frame, "output")
  if input_sum_table and input_sum_table.valid then
    input_sum_table.clear()
    add_sum_row(input_sum_table, "input", 0, 0, gui_settings)
  end
  if output_sum_table and output_sum_table.valid then
    output_sum_table.clear()
    add_sum_row(output_sum_table, "output", 0, 0, gui_settings)
  end
  recalculate(player, recipe_name)
end

-- ------------------------------------------------------------------------------
---GUI Main Frame
local function create_calculator(player)
  local old_frame = player.gui.screen[FRAME_NAME]
  if old_frame then old_frame.destroy() end
  local head_frame = player.gui.screen.add { type = "frame", name = FRAME_NAME, direction = "vertical" }
  -- State settings
  local state = player_calculator_state(player)
  -- GUI settings
  local gui_settings = player_gui_settings(player)
  if state.window_location then
    head_frame.location = state.window_location
  else
    head_frame.auto_center = true
  end
  head_frame.style.width = gui_settings.window_width

  -- =======================================
  -- Titlebar
  local titlebar = head_frame.add { type = "flow", direction = "horizontal" }
  titlebar.drag_target = head_frame
  titlebar.style.horizontally_stretchable = true
  titlebar.add {
    type = "label",
    caption = { "ocs-launching-calculator.title" },
    style = "frame_title",
    ignored_by_interaction = true,
  }
  -- Titlebar-flow
  local mane_frame = head_frame.add { type = "flow", name = "ocs_launching_calculator_content", direction = "vertical" }
  mane_frame.visible = not state.is_minimised
  -- Draggable Filler
  local filler = titlebar.add {
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  }
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  filler.style.right_margin = 4
  -- Collapse Button
  titlebar.add {
    type = "sprite-button",
    name = "ocs_launching_calculator_minimise",
    sprite = state.is_minimised and "utility/expand" or "utility/collapse",
    style = "frame_action_button",
    tooltip = state.is_minimised
        and { "ocs-launching-calculator.restore" }
        or { "ocs-launching-calculator.minimise" }
  }
  -- Close Button
  titlebar.add {
    type = "sprite-button",
    name = "ocs_launching_calculator_close",
    sprite = "utility/close",
    style = "frame_action_button",
    tooltip = { "ocs-launching-calculator.close" }
  }

  -- =======================================
  -- Rocket Silo and Rocke Recipe Frame (optional)
  local rocket_silo_frame = mane_frame.add {
    type = "flow",
    name = MANE_NAME .. "_rocket_silo",
    direction = "horizontal",
  }
  -- ---------------------------------------
  -- Silo Subframe
  local silo_frame = rocket_silo_frame.add {
    type = "frame",
    name = MANE_NAME .. "_silo_frame",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding",
  }
  silo_frame.style.width = gui_settings.column_width
  silo_frame.add { type = "label", caption = { "ocs-launching-calculator.silo-types" }, style = "heading_2_label" }
  -- Silo selection row (icon + dropdown)
  local silo_selection = silo_frame.add {
    type = "flow",
    name = MANE_NAME .. "_silo_selection",
    direction = "horizontal",
  }
  local silos = get_rocket_silos()
  local silo_items, silo_index, selected_silo = prepare_selection(silos, state.selected_silo_name)
  if selected_silo then
    state.selected_silo_name = selected_silo.name
  end
  -- Current silo icon
  silo_selection.add {
    type = "sprite",
    name = MANE_NAME .. "_silo_icon",
    sprite = selected_silo and selected_silo.sprite or "entity/rocket-silo",
  }
  -- Silo dropdown
  silo_selection.add {
    type = "drop-down",
    name = MANE_NAME .. "_silo_dropdown",
    items = silo_items,
    selected_index = silo_index,
    enabled = #silo_items > 0,
  }
  -- Maximum lift weight
  silo_frame.add {
    type = "label",
    name = MANE_NAME .. "_silo_lift_weight",
    caption = { "ocs-launching-calculator.max-lift-weight",
      selected_silo and display_number(selected_silo.lift_weight / 1e3, 0) .. " kg" or "—", } -- hardcoded 0 decimals
  }

  -- ---------------------------------------
  -- Rocket Subframe
  local rocket_frame = rocket_silo_frame.add {
    type = "frame",
    name = MANE_NAME .. "_rocket_frame",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding",
  }
  rocket_frame.style.width = gui_settings.column_width
  rocket_frame.add { type = "label", caption = { "ocs-launching-calculator.rocket-types" }, style = "heading_2_label" }
  local rocket_recipes = get_rocket_recipes()
  local r_items, recipe_index, selected_r_recipe = prepare_selection(rocket_recipes, state.selected_rocket_recipe_name)
  -- Rocket recipe selection row
  local rocket_selection = rocket_frame.add {
    type = "flow",
    name = MANE_NAME .. "_rocket_selection",
    direction = "horizontal",
  }
  -- Current rocket-part icon
  rocket_selection.add {
    type = "sprite",
    name = MANE_NAME .. "_rocket_icon",
    sprite = selected_r_recipe and selected_r_recipe.sprite or "item/rocket-part",
  }
  -- Rocket-recipe dropdown
  rocket_selection.add {
    type = "drop-down",
    name = MANE_NAME .. "_rocket_dropdown",
    items = r_items,
    selected_index = recipe_index,
    enabled = #r_items > 0,
  }
  -- Rocket recipe cycles required
  local parts_per_cycle = 0
  if selected_r_recipe then
    for _, product in pairs(selected_r_recipe.products or {}) do
      if product.name == "rocket-part" then
        parts_per_cycle = product.amount or product.amount_max or 0
        break
      end
    end
  end
  local cycles = 0
  if selected_silo and parts_per_cycle > 0 then
    cycles = math.ceil(selected_silo.rocket_parts_required / parts_per_cycle)
  end
  rocket_frame.add {
    type = "label",
    name = MANE_NAME .. "_rocket_recipe_tip",
    caption = {
      "ocs-launching-calculator.rocket-recipe-tip",
      cycles > 0 and display_number(cycles, gui_settings.decimals) or "—",
    },
  }

  -- =======================================
  -- Recipe Selection Section

  -- Recipe Selection Frame
  local selection = mane_frame.add {
    type = "frame",
    name = MANE_NAME .. "_selection",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  }
  -- Recipe picker line
  local recipe_row = selection.add {
    type = "flow",
    name = MANE_NAME .. "_recipe_row",
    direction = "horizontal"
  }
  recipe_row.add { type = "label", caption = { "ocs-launching-calculator.recipe" } }
  recipe_row.add { type = "choose-elem-button", name = RECIPE_PICKER_NAME, elem_type = "recipe" }
  recipe_row.add { type = "label", name = "ocs_launching_calculator_recipe_name", caption = { "ocs-launching-calculator.no-recipe" } }
  -- info line
  selection.add { type = "label", caption = { "ocs-launching-calculator.click-to-select-recipe" } }

  -- =======================================
  -- Input/Output Frame
  local io_frame = mane_frame.add {
    type = "flow",
    name = "ocs_launching_calculator_io_body",
    direction = "horizontal"
  }
  local TABLE_COLUMN_COUNT = gui_settings.show_item_name and 8 or 7
  local TABLE_SPACING = 8 * 2

  -- ---------------------------------------
  -- Input Frame
  local input_column = io_frame.add {
    type = "frame",
    name = "ocs_launching_calculator_input_column",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  }
  input_column.add { type = "label", caption = { "ocs-launching-calculator.inputs" }, style = "heading_2_label" }
  input_column.style.width = gui_settings.column_width
  local input_table = input_column.add {
    type = "table",
    name = INPUT_TABLE_NAME,
    column_count = TABLE_COLUMN_COUNT
  }
  input_table.style.horizontal_spacing = TABLE_SPACING

  -- ---------------------------------------
  -- Output Frame
  local output_column = io_frame.add {
    type = "frame",
    name = "ocs_launching_calculator_output_column",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  }
  output_column.add { type = "label", caption = { "ocs-launching-calculator.outputs" }, style = "heading_2_label" }
  output_column.style.width = gui_settings.column_width
  local output_table = output_column.add {
    type = "table",
    name = OUTPUT_TABLE_NAME,
    column_count = TABLE_COLUMN_COUNT
  }
  output_table.style.horizontal_spacing = TABLE_SPACING

  -- =======================================
  -- Sum Frame
  local sums_flow = mane_frame.add {
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
  input_sum_table.style.width = gui_settings.column_width
  local output_sum_table = sums_flow.add {
    type = "table",
    name = OUTPUT_SUM_TABLE_NAME,
    column_count = 5
  }
  output_sum_table.style.width = gui_settings.column_width
  output_sum_table.style.horizontal_spacing = TABLE_SPACING

  -- =======================================
  -- Recomendation Frame
  mane_frame.add {
    type = "label",
    name = RECOMMENDATION_NAME,
    caption = { "ocs-launching-calculator.select-recipe" },
    style = "heading_2_label",
  }
  mane_frame.add {
    type = "label",
    name = "ocs_launching_calculator_recommendation_detail1",
    caption = "",
    style = "label",
    visible = false,
  }
  mane_frame.add {
    type = "label",
    name = "ocs_launching_calculator_recommendation_detail2",
    caption = "",
    style = "label",
    visible = false,
  }
  -- =======================================
  -- After building the Mane Frame
  local recipe_name = state.selected_recipe
  -- debug start
  log("OPEN recipe: " .. serpent.line(recipe_name))
  log("Recipe exists: " .. tostring(recipe_name and prototypes.recipe[recipe_name] ~= nil))
  -- debug end
  if recipe_name and prototypes.recipe[recipe_name] then
    show_recipe(player, recipe_name)
  else
    show_recipe(player, nil)
  end
  -- clear_recipe_tables(player) --clearing the user inputs
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

--Create main button
script.on_init(function()
  for _, player in pairs(game.players) do create_main_button(player) end
end)

script.on_configuration_changed(function()
  for _, player in pairs(game.players) do create_main_button(player) end
end)

script.on_event(defines.events.on_player_created, function(event)
  create_main_button(game.get_player(event.player_index))
end)

---Handle calculator open/close clicks and recipe selection via item icons.
script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  local element = event.element
  if not (element and element.valid) then return end
  if element.name == "ocs_launching_calculator_button" then -- interact
    local frame = player.gui.screen[FRAME_NAME]
    if frame then frame.destroy() else create_calculator(player) end
    return
  elseif element.name == "ocs_launching_calculator_close" then   -- MANE close
    local frame = player.gui.screen[FRAME_NAME]
    local state = player_calculator_state(player)                --debug
    log("CLOSE recipe: " .. serpent.line(state.selected_recipe)) --debug
    if frame then frame.destroy() end
    return
  elseif element.name == "ocs_launching_calculator_minimise" then -- MANE minimise
    local state = player_calculator_state(player)
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
          and { "ocs-launching-calculator.restore" }
          or { "ocs-launching-calculator.minimise" }
    end
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

--Save and Update Window position
script.on_event(defines.events.on_gui_location_changed, function(event)
  local element = event.element
  if not (element and element.valid and element.name == FRAME_NAME) then
    return
  end
  local player = game.get_player(event.player_index)
  local state = player_calculator_state(player)
  state.window_location = element.location
end)

---Update the calculator when player changes the recipe picker
--- @param event EventData
script.on_event(defines.events.on_gui_elem_changed, function(event)
  local element = event.element
  if not (element and element.valid and element.name == RECIPE_PICKER_NAME) then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then return end
  local recipe_name = element.elem_value
  log("before SAVE: " .. serpent.line(element.elem_value))
  player_calculator_state(player).selected_recipe = recipe_name
  -- debug
  local state = player_calculator_state(player)
  state.selected_recipe = element.elem_value
  log("SAVE recipe: " .. serpent.line(state.selected_recipe))
  -- debug
  show_recipe(player, element.elem_value)
end)

---Handle changes to the selected silo or rocket recipe.
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end

  local player = game.get_player(event.player_index)
  local state = player_calculator_state(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.valid) then return end

  if element.name == MANE_NAME .. "_silo_dropdown" then
    local silos = get_rocket_silos()
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
  elseif element.name == MANE_NAME .. "_rocket_dropdown" then
    local rocket_recipes = get_rocket_recipes()
    local recipe = rocket_recipes[element.selected_index]
    if not recipe then return end

    state.selected_rocket_recipe_name = recipe.name

    local icon                        = frame[MANE_NAME .. "_rocket_silo"]
        [MANE_NAME .. "_rocket_frame"]
        [MANE_NAME .. "_rocket_selection"]
        [MANE_NAME .. "_rocket_icon"]

    if icon and icon.valid then
      icon.sprite = recipe.sprite
    end
  end
end)

--- Recalculate totals and recommendation when an input/output row is toggled.
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  if element.name:find("^ocs_launching_calculator_input_") or element.name:find("^ocs_launching_calculator_output_") then
    local player = game.get_player(event.player_index)
    if element.tags.row_type == "barrelled-fluid" then
      update_fluid_row(element, player_gui_settings(player))
    end
    local frame = player.gui.screen[FRAME_NAME]
    local selection = frame and frame["ocs_launching_calculator_selection"]
    local recipe_row = selection and selection["ocs_launching_calculator_recipe_row"]
    local recipe_picker = recipe_row and recipe_row[RECIPE_PICKER_NAME]
    local recipe_name = recipe_picker and recipe_picker.elem_value
    recalculate(game.get_player(event.player_index), recipe_name)
  end
end)
