local TOOLTIP_NAME = {"item-weight-tooltip.name"}

local function get_weight_localised(weight)
  if weight >= 1000000 then
    local tons = weight / 1000000
    return {"tons", tostring(tons), tostring(tons)}
  else
    local kg = weight / 1000
    return {"", tostring(kg), " ", {"si-unit-kilogram"}}
  end
end

local function add_weight_tooltip(item)
  -- Automatic weights may not be available in data.raw.
  if item.weight == nil then
    return
  end

  item.custom_tooltip_fields = item.custom_tooltip_fields or {}

  -- Avoid adding the field twice.
  for _, field in pairs(item.custom_tooltip_fields) do
    if field.name == TOOLTIP_NAME then
      return
    end
  end

  table.insert(item.custom_tooltip_fields, {
    name = TOOLTIP_NAME,
    value = get_weight_localised(item.weight),
    order = 99,
    show_in_tooltip = true,
    show_in_factoriopedia = true,
  })
end

for _, item in pairs(data.raw.item or {}) do
  add_weight_tooltip(item)
end

-- diagnostics
local list = {}
for name, item in pairs(data.raw.item or {}) do
  if item.weight == nil then
    table.instert(list, name)
  end
end
log("[Weight tooltip] Missing explicit item weight: " .. serpent.block(list))
