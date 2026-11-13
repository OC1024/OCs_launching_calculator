local mod_gui = require("mod-gui")
local gui = {}
local state = require("control.state")
local helpers = require("control.helpers")
local C = state.constants

local MANE_NAME = C.mod_name
local FRAME_NAME = C.frame_name
local RECIPE_PICKER_NAME = C.recipe_picker_name
local INPUT_TABLE_NAME = C.input_table_name
local OUTPUT_TABLE_NAME = C.output_table_name
local INPUT_SUM_TABLE_NAME = C.input_sum_table_name
local OUTPUT_SUM_TABLE_NAME = C.output_sum_table_name
local RECOMMENDATION_NAME = C.recommendation_name
local vanilla_silo = C.vanilla_silo
local vanilla_r_part = C.vanilla_rocket_part
local WEIGHT_PER_KILOGRAM = C.weight_per_kilogram
local ROCKET_LIFT_WEIGHT = C.rocket_lift_weight
local HISTORY_FRAME_NAME = MANE_NAME .. "_history"
local HISTORY_CONTENT_FRAME_NAME = HISTORY_FRAME_NAME.."_content"
local HISTORY_TOGGLE_NAME = MANE_NAME .. "_history_toggle"
local HISTORY_SLOT_PREFIX = MANE_NAME .. "_history_slot_"
local HISTORY_SLOT_COUNT = 5
local HISTORY_FRAME_WIDTH = 88
local HISTORY_FRAME_GAP_HORIZONTAL = 0
local HISTORY_FRAME_GAP_VERTICAL = 0

local display_number = helpers.display_number

---Headers for Input/Output tables
---@param gui_table LuaGuiElement
---@param gui_settings table
local function add_headers(gui_table, gui_settings)
  local headers = {
    { caption = "" }, -- checkbox
    { caption = { "gui-blueprint.icon" } },
  }

  if gui_settings.show_item_name then
    table.insert(headers, {
      caption = { "factoriopedia.item" },
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
---@param player LuaPlayer Active player
---@param gui_table LuaGuiElement The table containing the row.
---@param row_id string The row's identifier prefix.
---@param prototype ItemPrototype|FluidPrototype The item or fluid prototype to display.
---@param amount number The quantity of the item or fluid.
---@param unit_mass number The mass of one unit, in kilograms.
---@param note LocalisedString|nil Optional tooltip note.
---@param is_fluid boolean Whether the displayed prototype is a fluid.
local function set_row_display(player, gui_table, row_id, prototype, amount, unit_mass, note, is_fluid)
  -- General settings
  local gui_settings = state.player_gui_settings(player)
  local state = state.player_calculator_state(player)
  local silos = helpers.get_rocket_silos()
  local _, _, selected_silo = helpers.prepare_selection(silos, state.selected_silo_name, vanilla_silo)
  local rocket_capacity = selected_silo
      and selected_silo.lift_weight / WEIGHT_PER_KILOGRAM
      or ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM
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
  gui_table[row_id .. "_amount"].caption = display_number(amount, gui_settings.decimals, true)
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

---Creates the cells shared by item and fluid rows. Adds the checkbox, icon holder, and optional item-name label,
---followed by the quantity, unit-mass, total-mass, rocket-ratio, and warning labels.
---@param gui_table LuaGuiElement The table to which the row cells are added.
---@param row_id string The row's identifier prefix, used to name each cell.
---@param checkbox_spec table The element specification used to create the checkbox.
---@param gui_settings table The player's GUI settings, including whether item names are shown.
---@return LuaGuiElement checkbox The newly created checkbox element.
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

---Switches a barrel-capable fluid row between its fluid and barrel displays.
---@param player LuaPlayer The player whose calculator is being updated.
---@param checkbox LuaGuiElement The row's include checkbox, containing fluid and barrel metadata in its tags.
function gui.update_fluid_row(player, checkbox)
  local gui_table = checkbox.parent
  local row_id = checkbox.name:gsub("_include$", "")
  local tags = checkbox.tags
  if checkbox.state then
    local barrel = prototypes.item[tags.barrel_name]
    if not barrel then
      checkbox.state = false
      checkbox.enabled = false
      local fluid = prototypes.fluid[tags.fluid_name]
      set_row_display(player, gui_table, row_id, fluid, tags.fluid_amount, 0,
        { "ocs-launching-calculator.no-barrel-note" }, true)
      return
    end
    set_row_display(player, gui_table, row_id, barrel, tags.barrel_amount,
      barrel.weight / WEIGHT_PER_KILOGRAM, { "ocs-launching-calculator.converted-from-fluid" }, false)
  else
    local fluid = prototypes.fluid[tags.fluid_name]
    set_row_display(player, gui_table, row_id, fluid, tags.fluid_amount, 0,
      { "ocs-launching-calculator.fluid-direct-note" }, true)
  end
end

---Adds an item row or a fluid row with an optional barrel representation.
---@param player LuaPlayer Active player
---@param gui_table LuaGuiElement The table to which the row cells are added.
---@param side string Which side of the recipe: "input" or "output"
---@param index any
---@param entry table
---@param amount number The quantity of the item or fluid.
---@param recipe_name any
local function add_item_row(player, gui_table, side, index, entry, amount, recipe_name)
  local row_id = "ocs_launching_calculator_" .. side .. "_" .. index
  local table_type = side == "input" and "inputs" or "outputs"
  local gui_settings = state.player_gui_settings(player)
  local state = state.player_calculator_state(player)
  -- checkbox state (if changed before)
  local recipe_states = state.checkbox_states[recipe_name]
  local table_states = recipe_states and recipe_states[table_type]
  local saved_state = table_states and table_states[entry.name]
  -- if non-barrel solid
  if entry.type ~= "fluid" then
    local prototype = prototypes.item[entry.name]
    local unit_mass = prototype and prototype.weight / WEIGHT_PER_KILOGRAM or 0
    add_row_cells(gui_table, row_id, {
      type = "checkbox",
      name = row_id .. "_include",
      state = saved_state ~= false,
      tooltip = { "ocs-launching-calculator.include-row" },
      tags = {
        row_type = "item",
        recipe_name = recipe_name,
        table_type = table_type,
        item_name = entry.name,
        amount = amount,
        total_mass = amount * unit_mass,
      }
    }, gui_settings)
    set_row_display(player, gui_table, row_id, prototype, amount, unit_mass, nil, false)
    return
  end

  -- if barreled
  local fluid = prototypes.fluid[entry.name]
  local barrel = helpers.fluid_barrel_details(entry.name, amount)
  if not barrel then
    add_row_cells(gui_table, row_id, {
      type = "checkbox",
      name = row_id .. "_include",
      state = saved_state ~= false,
      enabled = false,
      tooltip = { "ocs-launching-calculator.no-barrel-tooltip" },
      tags = {
        row_type = "unbarrelled-fluid",
        recipe_name = recipe_name,
        table_type = table_type,
        fluid_name = entry.name,
        fluid_amount = amount,
        total_mass = 0,
      }
    }, gui_settings)
    set_row_display(player, gui_table, row_id, fluid, amount, 0, { "ocs-launching-calculator.no-barrel-note" }, true)
    return
  end

  -- if fluid (unbarreled)
  local checkbox = add_row_cells(gui_table, row_id, {
    type = "checkbox",
    name = row_id .. "_include",
    state = saved_state ~= false,
    tooltip = { "ocs-launching-calculator.toggle-barrel" },
    tags = {
      row_type = "barrelled-fluid",
      recipe_name = recipe_name,
      table_type = table_type,
      fluid_name = entry.name,
      fluid_amount = amount,
      barrel_name = barrel.prototype.name,
      barrel_amount = barrel.amount,
      total_mass = 0
    }
  }, gui_settings)
  set_row_display(player, gui_table, row_id, barrel.prototype, barrel.amount,
    barrel.prototype.weight / WEIGHT_PER_KILOGRAM,
    { "ocs-launching-calculator.converted-from-fluid" }, false)
  gui.update_fluid_row(player, checkbox)
end

---Add header and totals rows to a recipe summary table.
---@param gui_table LuaGuiElement
---@param side "input"|"output"
---@param amount_total number Total item amount.
---@param total number Total mass.
---@param gui_settings table
---@return nil
local function add_sum_row(gui_table, side, amount_total, total, gui_settings)
  local type_caption = { side == "input" and "description.ingredients" or "description.products" }

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
    caption = display_number(amount_total, gui_settings.decimals, true),
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

---Returns the total mass of checked rows in a recipe table.
---@param gui_table LuaGuiElement
---@return number total
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

---Returns the input or output table in the calculator frame.
---@param frame LuaGuiElement
---@param side "input"|"output"
---@return LuaGuiElement|nil gui_table
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

---Refreshes existing input and output rows using the player's currently selected rocket silo.
---@param player LuaPlayer The player whose calculator is being updated.
---@param frame LuaGuiElement The calculator content frame containing the recipe tables.
local function refresh_recipe_rows(player, frame)
  for _, side in ipairs({ "input", "output" }) do
    local gui_table = get_recipe_table(frame, side)
    if not (gui_table and gui_table.valid) then
      goto continue
    end
    for _, checkbox in pairs(gui_table.children) do
      if checkbox.valid
          and checkbox.type == "checkbox"
          and checkbox.name:match("_include$") then
        local tags = checkbox.tags
        if tags.row_type == "item" then
          local prototype = prototypes.item[tags.item_name]
          if prototype then
            local amount = tags.amount
            local unit_mass = prototype.weight / WEIGHT_PER_KILOGRAM
            local row_id = checkbox.name:gsub("_include$", "")
            set_row_display(player, gui_table, row_id, prototype, amount, unit_mass, nil, false)
          end
        elseif tags.row_type == "barrelled-fluid" or tags.row_type == "unbarrelled-fluid" then
          gui.update_fluid_row(player, checkbox)
        end
      end
    end
    ::continue::
  end
end

---Returns the dedicated sum table so both sides always share one baseline.
---@param frame LuaGuiElement
---@param side "input"|"output"
---@return LuaGuiElement|nil sum_table
local function get_sum_table(frame, side)
  local sums_flow = frame["ocs_launching_calculator_sums"]
  if not (sums_flow and sums_flow.valid) then return nil end
  return sums_flow[side == "input" and INPUT_SUM_TABLE_NAME or OUTPUT_SUM_TABLE_NAME]
end

---Recalculates all numbers, filling tables for inputs/outputs/summs and display recommendation.
---@param player LuaPlayer The player whose calculator is being updated.
---@param selected_recipe string|nil The currently selected recipe name.
function gui.recalculate(player, selected_recipe)
  local head_frame = player.gui.screen[FRAME_NAME]
  if not (head_frame and head_frame.valid) then return end
  local frame = head_frame["ocs_launching_calculator_content"]
  if not (frame and frame.valid) then return end
  -- general gui and state settings
  local gui_settings = state.player_gui_settings(player)
  local state = state.player_calculator_state(player)
  -- Rocket silos and parts
  local silos = helpers.get_rocket_silos()
  local _, _, selected_silo = helpers.prepare_selection(silos, state.selected_silo_name, vanilla_silo)
  local rocket_capacity = selected_silo
      and selected_silo.lift_weight / WEIGHT_PER_KILOGRAM
      or ROCKET_LIFT_WEIGHT / WEIGHT_PER_KILOGRAM
  -- IO-tables
  local input_table = get_recipe_table(frame, "input")
  local output_table = get_recipe_table(frame, "output")
  if not (input_table and input_table.valid and output_table and output_table.valid) then
    return
  end
  -- refresh rows (needed for rocket silo update)
  refresh_recipe_rows(player, frame)

  local decimals = gui_settings.decimals
  local input_total = included_total(input_table)
  local output_total = included_total(output_table)
  local input_amount_total = helpers.included_amount_total(input_table)
  local output_amount_total = helpers.included_amount_total(output_table)
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

  input_amount_sum.caption = display_number(input_amount_total, decimals, true)
  output_amount_sum.caption = display_number(output_amount_total, decimals, true)
  input_mass_sum.caption = display_number(input_total, decimals)
  output_mass_sum.caption = display_number(output_total, decimals)
  input_ratio_sum.caption = display_number(input_total / rocket_capacity, decimals)
  output_ratio_sum.caption = display_number(output_total / rocket_capacity, decimals)

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
  local ratio = (lighter_total == 0) and "∞" or display_number(heavier_total / lighter_total, decimals, true)
  recommendation.caption = input_total < output_total
      and { "ocs-launching-calculator.recommend-inputs" }
      or { "ocs-launching-calculator.recommend-outputs" }
  detail1.visible = true
  detail2.visible = true
  detail1.caption = { "ocs-launching-calculator.recommendation-detail1", ratio }
  detail2.caption = { "ocs-launching-calculator.recommendation-detail2", display_number(improvement, decimals, true) }
end

---Clears both recipe tables and resets their totals and recommendation.
---@param player LuaPlayer
local function clear_recipe_tables(player)
  local head_frame = player.gui.screen[FRAME_NAME]
  if not (head_frame and head_frame.valid) then return end
  local frame = head_frame["ocs_launching_calculator_content"]
  if not (frame and frame.valid) then return end
  local gui_settings = state.player_gui_settings(player)
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

---Shows a recipe and rebuilds its input and output rows.
---@param player LuaPlayer
---@param recipe_name string|nil
function gui.show_recipe(player, recipe_name)
  local head_frame = player.gui.screen[FRAME_NAME]
  if not (head_frame and head_frame.valid) then return end
  local mane_frame = head_frame["ocs_launching_calculator_content"]
  if not (mane_frame and mane_frame.valid) then return end
  local gui_settings = state.player_gui_settings(player)

  -- Update recipe picker when a recipe is selected by clicking an item.
  local selection = mane_frame["ocs_launching_calculator_selection"]
  if not (selection and selection.valid) then return end
  local recipe_row = selection["ocs_launching_calculator_recipe_row"]
  local recipe_picker = recipe_row and recipe_row[RECIPE_PICKER_NAME]
  local recipe_name_label = recipe_row and recipe_row["ocs_launching_calculator_recipe_name"]
  if not (recipe_picker and recipe_picker.valid and recipe_name_label and recipe_name_label.valid) then
    return
  end

  local recipe = recipe_name and prototypes.recipe[recipe_name]
  if not recipe then
    recipe_picker.elem_value = nil
    recipe_name_label.caption = { "gui-assembling-machine.no-recipe-set" }
    clear_recipe_tables(player)
    gui.recalculate(player, nil)
    return
  end
  local state = state.player_calculator_state(player)
  state.selected_recipe = recipe_name
  if recipe_picker.elem_value ~= recipe_name then
    recipe_picker.elem_value = recipe_name
  end
  recipe_name_label.caption = recipe.localised_name

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
    add_item_row(player, input_table, "input", index, ingredient, ingredient.amount, recipe_name)
  end
  for index, product in ipairs(recipe.products) do
    add_item_row(player, output_table, "output", index, product, recipe.get_product_amount(index), recipe_name)
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
  gui.recalculate(player, recipe_name)
end

---Refreshes the recent-recipe history panel.
---@param player LuaPlayer
local function refresh_history(player)
  local player_state = state.player_calculator_state(player)
  local history_frame = player.gui.screen[HISTORY_FRAME_NAME]
  if not (history_frame and history_frame.valid) then return end
  local content_frame = history_frame[HISTORY_CONTENT_FRAME_NAME]
  if not (content_frame and content_frame.valid) then return end
  content_frame.clear()
  -- Recipe slots
  for index = 1, HISTORY_SLOT_COUNT do
    local recipe_name = player_state.recipe_history[index]
    local recipe = recipe_name and prototypes.recipe[recipe_name]
    content_frame.add {
      type = "sprite-button",
      name = HISTORY_SLOT_PREFIX .. index,
      sprite = recipe and "recipe/" .. recipe.name or nil, -- "utility/slot",
      tooltip = recipe and recipe.localised_name or nil,
      enabled = recipe ~= nil,
      style = "slot_button",
      tags = recipe and {
        action = "select-history-recipe",
        recipe_name = recipe.name,
      } or {},
    }
  end
end

---Positions the history panel immediately to the left of the calculator.
---@param player LuaPlayer
function gui.update_history_position(player)
  local head_frame = player.gui.screen[FRAME_NAME]
  local history_frame = player.gui.screen[HISTORY_FRAME_NAME]
  if not (head_frame and head_frame.valid and history_frame and history_frame.valid) then return end
  local location = head_frame.location
  if location then
    history_frame.location = {
      x = location.x - HISTORY_FRAME_WIDTH - HISTORY_FRAME_GAP_HORIZONTAL,
      y = location.y + HISTORY_FRAME_GAP_VERTICAL,
    }
  end
end

---Creates the history panel when it is enabled for the player.
---@param player LuaPlayer
function gui.create_history(player)
  local old_history = player.gui.screen[HISTORY_FRAME_NAME]
  if old_history then old_history.destroy() end
  local player_state = state.player_calculator_state(player)
  if not player_state.history_visible then return end
  -- History Root Frame
  local history_frame = player.gui.screen.add { type = "frame", name = HISTORY_FRAME_NAME, direction = "vertical", }
  history_frame.style.width = HISTORY_FRAME_WIDTH
  -- Titlebar
  local titlebar = history_frame.add { type = "flow", direction = "horizontal", }
  titlebar.style.horizontally_stretchable = true -- needed?
  titlebar.add {
    type = "sprite",
    sprite = "utility/mod_last_updated",
    tooltip = { "ocs-launching-calculator.history" },
  }
  -- Content
  history_frame.add {
    type = "frame",
    name = HISTORY_CONTENT_FRAME_NAME,
    direction = "vertical",
    style = "inside_shallow_frame_with_padding",
  }
  refresh_history(player)
  gui.update_history_position(player)
end

---Toggles visibility of the recent-recipe history panel.
---@param player LuaPlayer
---@param button LuaGuiElement
function gui.toggle_history(player, button)
  local player_state = state.player_calculator_state(player)
  player_state.history_visible = not player_state.history_visible
  gui.create_history(player)
  button.sprite = player_state.history_visible and "utility/forward_arrow" or "utility/backward_arrow"
  button.tooltip = player_state.history_visible
      and { "ocs-launching-calculator.hide-history" }
      or { "ocs-launching-calculator.show-history" }
end

---Destroys the calculator and its attached history panel.
---@param player LuaPlayer
function gui.destroy_calculator(player)
  local frame = player.gui.screen[FRAME_NAME]
  if frame then frame.destroy() end
  local history_frame = player.gui.screen[HISTORY_FRAME_NAME]
  if history_frame then history_frame.destroy() end
end

---Selects a recipe and records it in recent history.
---@param player LuaPlayer
---@param recipe_name string|nil
function gui.select_recipe(player, recipe_name)
  if recipe_name and prototypes.recipe[recipe_name] then
    state.record_recipe_history(player, recipe_name)
  end
  gui.show_recipe(player, recipe_name)
  refresh_history(player)
end

-- ------------------------------------------------------------------------------

---Creates the calculator window for a player.
---@param player LuaPlayer
function gui.create_calculator(player)
  local old_frame = player.gui.screen[FRAME_NAME]
  if old_frame then old_frame.destroy() end
  local head_frame = player.gui.screen.add { type = "frame", name = FRAME_NAME, direction = "vertical" }
  -- GUI settings
  local gui_settings = state.player_gui_settings(player)
  -- State settings
  local state = state.player_calculator_state(player)
  if state.window_location then
    head_frame.location = state.window_location
  else
    head_frame.auto_center = true
  end
  head_frame.style.width = gui_settings.window_width
  player.opened = head_frame

  -- =======================================
  -- Titlebar
  local titlebar = head_frame.add { type = "flow", direction = "horizontal" }
  titlebar.drag_target = head_frame
  titlebar.style.horizontally_stretchable = true
  -- History Toggle Button
  titlebar.add {
    type = "sprite-button",
    name = HISTORY_TOGGLE_NAME,
    sprite = "utility/forward_arrow", -- "utility/mod_last_updated"
    style = "frame_action_button",
    tooltip = state.history_visible
        and { "ocs-launching-calculator.hide-history" }
        or { "ocs-launching-calculator.show-history" },
  }
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
    tooltip = state.is_minimised and { "gui-crafting-queue.expand" } or { "gui-crafting-queue.collapse" }
  }
  -- Close Button
  titlebar.add {
    type = "sprite-button",
    name = "ocs_launching_calculator_close",
    sprite = "utility/close",
    style = "frame_action_button",
    tooltip = { "gui.close-instruction" }
  }

  -- =======================================
  -- Rocket Silo and Rocke Recipe Frame (optional)
  local rocket_silo_frame = mane_frame.add {
    type = "flow",
    name = MANE_NAME .. "_rocket_silo",
    direction = "horizontal",
  }
  if not gui_settings.advanced_mode then
    rocket_silo_frame.visible = false
  end
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
  local silos = helpers.get_rocket_silos()
  local silo_items, silo_index, selected_silo = helpers.prepare_selection(silos, state.selected_silo_name, vanilla_silo)
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
      selected_silo and display_number(selected_silo.lift_weight / 1e3, gui_settings.decimals, true) .. " kg" or "—", }
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
  local rocket_recipes = helpers.get_rocket_recipes()
  local r_items, recipe_index, selected_r_recipe = helpers.prepare_selection(rocket_recipes,
    state.selected_rocket_recipe_name,
    vanilla_r_part)
  if selected_r_recipe then
    state.selected_rocket_recipe_name = selected_r_recipe.name
  end
  -- Rocket-parts selection row (icon + dropdown)
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
  -- Rocket-parts dropdown
  rocket_selection.add {
    type = "drop-down",
    name = MANE_NAME .. "_rocket_dropdown",
    items = r_items,
    selected_index = recipe_index,
    enabled = #r_items > 0,
  }
  -- Rocket-parts cycles required
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
      cycles > 0 and display_number(cycles, gui_settings.decimals, true) or "—",
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
  recipe_row.add { type = "label", caption = { "description.recipe" } }
  recipe_row.add { type = "choose-elem-button", name = RECIPE_PICKER_NAME, elem_type = "recipe" }
  recipe_row.add { type = "label", name = "ocs_launching_calculator_recipe_name", caption = { "gui-assembling-machine.no-recipe-set" } }
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
  input_column.add { type = "label", caption = { "description.ingredients" }, style = "heading_2_label" }
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
  output_column.add { type = "label", caption = { "description.products" }, style = "heading_2_label" }
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
  if recipe_name and prototypes.recipe[recipe_name] then
    gui.show_recipe(player, recipe_name)
  else
    gui.show_recipe(player, nil)
  end
  gui.create_history(player)
end

-- ==============================================================================
---Creates the mod-GUI button for a player if it does not exist yet.
---@param player LuaPlayer
function gui.create_main_button(player)
  local flow = mod_gui.get_button_flow(player)
  if flow.ocs_launching_calculator_button then return end
  flow.add {
    type = "sprite-button",
    name = "ocs_launching_calculator_button",
    sprite = "item/rocket-part",
    tooltip = { "ocs-launching-calculator.title" },
    style = "slot_button",
  }
end

return gui
