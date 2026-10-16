data:extend({
  {
    type = "int-setting",
    name = "round_decimals",
    setting_type = "runtime-per-user",
    order = "a",
    default_value = 2,
    minimum_value = 0,
    maximum_value = 5,
  },
  {
    type = "int-setting",
    name = "oc-calc-window-width",
    setting_type = "runtime-per-user",
    order = "ba",
    default_value = 1100,
    minimum_value = 360,
  },
  {
    type = "bool-setting",
    name = "oc-calc-show-item-name",
    setting_type = "runtime-per-user",
    ordre = "bb",
    default_value = true,
  }
})