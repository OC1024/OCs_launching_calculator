local helpers = {}
local const = require("control.state").constants
local WEIGHT_PER_KILOGRAM = const.weight_per_kilogram
local WEIGHT_PER_TON = const.weight_per_ton
local ROCKET_LIFT_WEIGHT = const.rocket_lift_weight

---Lua Things
---@class uint
---@class LuaEntity
---@class LuaPlayer
---@class EventData
---@class ItemPrototype
---@class FluidPrototype
---@class LuaRecipePrototype
---@class LocalisedString
---@class LuaGuiElement
---@class CommandData

---Rounds to a given decimal place, zero possible; adds thousands separators. Integer display possible.
---@param value number
---@param decimals number
---@param keep_int boolean|nil Display integer values without decimals.
---@return string
function helpers.display_number(value, decimals, keep_int)
  decimals = math.max(0, math.floor(tonumber(decimals) or 0))
  if keep_int and (value % 1 == 0) then
    decimals = 0
  elseif value ~= 0 and math.abs(value) < 1 then
    local significant_decimals = decimals - math.floor(math.log(math.abs(value), 10)) - 1
    decimals = math.max(decimals, significant_decimals)
  end
  local formatted = string.format("%." .. decimals .. "f", value)
  local integer, fraction = formatted:match("^(-?%d+)(.*)$")
  integer = integer:reverse():gsub("(%d%d%d)", "%1'"):reverse():gsub("^'", "")
  return integer .. fraction
end

---A barrel normally has a matching fill recipe. This supports modded barrel
---sizes instead of assuming vanilla's 50 fluid units per barrel.
---Fluids without a barreled equivalent are shown with no mass and a disabled checkbox.
---@param fluid_name string
---@param fluid_amount number
---@return table|nil barrel_details
function helpers.fluid_barrel_details(fluid_name, fluid_amount)
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
---@param gui_table LuaGuiElement
---@return number total
function helpers.included_amount_total(gui_table)
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
---@param item_name string
---@param item_type string
---@return LuaRecipePrototype|nil recipe
function helpers.find_unique_recipe_for_product(item_name, item_type)
  local unique_recipe = nil
  for _, recipe in pairs(prototypes.recipe) do
    -- Exclude recycling recipes.
    local function is_recycling_recipe(r)
      for _, category in pairs(r.categories) do
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
function helpers.array_contains(array, value)
  for _, entry in pairs(array) do
    if entry == value then return true end
  end
  return false
end

-- ==============================================================================
-- Rockets and Silo Functions

---Get all entities usable as rocket silos.
---@return table[] silos
function helpers.get_rocket_silos()
  local silos = {}
  for name, prototype in pairs(prototypes.entity) do
    local is_rocket_silo = prototype.type == "rocket-silo"
    local has_rocket_building_category =
        prototype.crafting_categories
        and prototype.crafting_categories["rocket-building"]
    if (is_rocket_silo or has_rocket_building_category)
        and prototype.lift_weight
        and prototype.lift_weight > 0 then
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
function helpers.get_rocket_recipes()
  local recipes = {}
  for name, prototype in pairs(prototypes.recipe) do
    if prototype.categories and helpers.array_contains(prototype.categories, "rocket-building") then
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
function helpers.prepare_selection(entries, selected_name, default_name)
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

  -- default path
  if not selected_entry and default_name then
    for i, entry in ipairs(entries) do
      if entry.name == default_name then
        selected_index = i
        selected_entry = entry
        break
      end
    end
  end
  -- if also no default name (or missing)
  if not selected_entry and #entries > 0 then
    selected_index = 1
    selected_entry = entries[1]
  end

  return items, selected_index, selected_entry
end

return helpers
