local PAYLOAD = 1000 -- kg per rocket
local mod_gui = require("mod-gui") -- needed for the open-up button

-- ====  helpers  ==== --

-- add header row to the inputs or outputs table
local function add_header_row(parent_table)
    local row = parent_table.add { type = "flow", direction = "horizontal" }

    -- Empty cell for checkbox column (kept for alignment)
    row.add { type = "label", caption = "" }
    -- Icon header
    row.add { type = "label", caption = "Icon", style = "caption_label" }
    -- Name header
    row.add { type = "label", caption = "Item", style = "caption_label" }
    -- Amount header
    row.add { type = "label", caption = "Amount", style = "caption_label" }
    -- Ratio header
    row.add { type = "label", caption = "Ratio", style = "caption_label" }
end

-- add a row for the inputs or outputs table
local function add_item_row(parent_table, item_name, amount)
    -- Resolve prototype
    local proto = nil
    if game and game.item_prototypes then
        proto = game.item_prototypes[item_name]
            or game.fluid_prototypes[item_name]
            or game.ammo_prototypes[item_name]
    end
    -- local proto = game.item_prototypes[item_name] or game.fluid_prototypes[item_name] or game.ammo_prototypes[item_name]
    local display_name = item_name
    local weight = proto and proto.weight or 0
    local tooltip_note = ""

    -- Handle fluids: replace with barreled version if exists
    if proto and proto.type == "fluid" then
        local barrel_name = item_name .. "-barrel"
        if game.item_prototypes[barrel_name] then
            display_name = barrel_name
            proto = game.item_prototypes[barrel_name]
            tooltip_note = "(fluid must be barreled)"
        else
            tooltip_note = "(fluid, no barrel found!)"
        end
    end

    local ratio = (amount * (proto and proto.weight or 0)) / PAYLOAD

    -- -- Get player's rounding
    -- local settings = global.player_data[player.index] or { round_decimals = 2 }
    -- local round_dec = settings.round_decimals or 2
    -- local ratio_display = tonumber(string.format("%." .. round_dec .. "f", ratio))
    local ratio_display = string.format("%.2f", ratio) -- fixed 2 decimals for simplicity

    -- Row container
    local row = parent_table.add { type = "flow", direction = "horizontal" }

    -- Checkbox for this row (ingredients and products)
    local cb = row.add {
        type = "checkbox",
        name = "include_row_" .. item_name,
        state = true, -- default: included
        caption = ""
    }
    row.include_checkbox = cb

    local sprite = "item/iron-plate" -- fallback
    if proto then
        if game.item_prototypes[item_name] then
            sprite = "item/" .. item_name
        elseif game.fluid_prototypes[item_name] then
            sprite = "fluid/" .. item_name
        end
    end
    -- Icon
    row.add {
        type = "sprite-button",
        sprite = sprite,
        style = "slot_button",
        tooltip = tooltip_note ~= "" and display_name .. " " .. tooltip_note or display_name,
        enabled = false
    }

    -- Name label
    row.add { type = "label", caption = display_name, style = "caption_label" }

    -- Amount label
    row.add { type = "label", caption = tostring(amount) }

    -- Launch ratio label
    local ratio_label = row.add { type = "label", caption = tostring(ratio_display) }
    row.launch_ratio = ratio_label
    row.launch_ratio_value = ratio -- store numeric value for calculations

    return row
end

-- Shows the sum row at the bottom of the table
local function add_sum_row(parent_table, total_ratio)
    local row = parent_table.add {
        type = "flow",
        direction = "horizontal"
    }

    -- Sigma icon/label
    row.add {
        type = "label",
        caption = "Σ",
        style = "caption_label"
    }

    -- Name
    row.add {
        type = "label",
        caption = "Sum",
        style = "caption_label"
    }

    -- Amount (blank)
    row.add {
        type = "label",
        caption = ""
    }

    -- Total ratio
    row.add {
        type = "label",
        caption = tostring(total_ratio) -- later has to be rounded up to the next integer
    }

    return row
end

-- actual calculations
local function recalc_launch_sums(player)
    --[[
    --Sums up the included ingredients and products launch ratios, updates the sum rows and the result label. 
    local frame = player.gui.screen.calc_frame
    if not (frame and frame.valid) then return end

    local settings = global.player_data[player.index] or { round_decimals = 2 }
    local round_dec = settings.round_decimals or 2

    local input_sum, output_sum = 0, 0

    -- Inputs
    local ing_table = frame.calc_body.ingredients_table
    if ing_table then
        for _, row in pairs(ing_table.children) do
            if row.include_checkbox and row.launch_ratio_value then
                if row.include_checkbox.state then
                    input_sum = input_sum + row.launch_ratio_value
                end
            end
        end
    end

    -- Outputs
    local prod_table = frame.calc_body.products_table
    if prod_table then
        for _, row in pairs(prod_table.children) do
            if row.include_checkbox and row.launch_ratio_value then
                if row.include_checkbox.state then
                    output_sum = output_sum + row.launch_ratio_value
                end
            end
        end
    end

    -- Round sums for display
    local factor = 10 ^ round_dec
    input_sum = math.floor(input_sum * factor + 0.5) / factor
    output_sum = math.floor(output_sum * factor + 0.5) / factor

    -- Update sum rows
    if ing_table and ing_table.sum_row then
        ing_table.sum_row.children[4].caption = tostring(input_sum)
    end
    if prod_table and prod_table.sum_row then
        prod_table.sum_row.children[4].caption = tostring(output_sum)
    end

    -- Update result label
    local result_label = frame.sums_flow and frame.sums_flow.result_label
    if result_label then
        local decision = (input_sum > output_sum) and "locally" or "before launch"
        result_label.caption = "Cheaper to craft: " .. decision
        -- optionally color the "decision" part green
        result_label.style.font_color = { r = 0, g = 1, b = 0 }
    end
    --]]
end

-- Create the main calculator window
local function create_calc_window(player)
    -- Avoid duplicates
    if player.gui.screen.calc_frame then
        player.gui.screen.calc_frame.destroy()
    end

    -- Main frame
    local frame = player.gui.screen.add {
        type = "frame",
        name = "calc_frame",
        direction = "vertical"
    }
    frame.auto_center = true

    -- Titlebar
    local titlebar = frame.add { type = "flow", direction = "horizontal" }
    titlebar.drag_target = frame
    titlebar.add { type = "label", style = "frame_title", caption = "Launch Calculator" }
    -- Draggable filler
    local filler = titlebar.add { type = "empty-widget", style = "draggable_space_header" }
    filler.style.horizontally_stretchable = true
    filler.drag_target = frame
    -- Close button
    titlebar.add { type = "sprite-button", name = "calc_close_button", sprite = "utility/close", style = "frame_action_button" }

    -- -- recipe selector button + label
    -- local recipe_selector = frame.add { type = "flow", name = "selected_recipe_flow", direction = "horizontal" }
    -- recipe_selector.add { type = "sprite-button", name = "select_recipe_button", sprite = "utility/questionmark", style = "slot_button" }
    -- recipe_selector.add { type = "label", name = "selected_recipe_label", caption = "No recipe selected" }

    -- Sample data for testing
    -- Dummy items for testing
    local test_ingredients = {
        {name="iron-plate", amount=10},
        {name="copper-plate", amount=5},
        {name="steel-plate", amount=2}
    }
    local test_products = {
        {name="iron-gear-wheel", amount=4},
        {name="copper-cable", amount=8}
    }

    -- Body: ingredients/products tables
    local body = frame.add { type = "flow", name = "calc_body", direction = "horizontal" }

    -- Ingredients table
    local ing_table = body.add { type = "table", name = "ingredients_table", column_count = 5 }
    -- Header row
    ing_table.add { type = "label", caption = "Local" }
    ing_table.add { type = "label", caption = "Icon" }
    ing_table.add { type = "label", caption = "Item" }
    ing_table.add { type = "label", caption = "Amount" }
    ing_table.add { type = "label", caption = "Ratio" }
    -- Optional placeholder row
    for i=1,5 do ing_table.add { type = "label", caption = "x" } end
    -- Populate ingredients table
    -- local ing_table = frame.calc_body.ingredients_table
    for _, ing in pairs(test_ingredients) do
        add_item_row(ing_table, ing.name, ing.amount)
    end

    -- Products table
    local prod_table = body.add { type = "table", name = "products_table", column_count = 5 }
    -- Header row
    prod_table.add { type = "label", caption = "Local" }
    prod_table.add { type = "label", caption = "Icon" }
    prod_table.add { type = "label", caption = "Item" }
    prod_table.add { type = "label", caption = "Amount" }
    prod_table.add { type = "label", caption = "Ratio" }
    -- Optional placeholder row
    for i=1,5 do prod_table.add { type = "label", caption = "o" } end
    -- Populate products table
    local prod_table = frame.calc_body.products_table
    for _, prod in pairs(test_products) do
        add_item_row(prod_table, prod.name, prod.amount)
    end

    -- Sums and result label
    local sums_flow = frame.add { type = "flow", direction = "horizontal", name = "sums_flow" }
    sums_flow.add { type = "label", name = "sum_ing", caption = "Sum ingredients:" }
    sums_flow.add { type = "label", name = "sum_prod", caption = "Sum products:" }
    sums_flow.add { type = "label", name = "result_label", caption = "Cheaper to craft:" }
end

-- Create Recipe Selection Popup window
local function open_recipe_selector(player)
    -- Avoid duplicates
    local existing = player.gui.screen.recipe_select_frame
    if existing then existing.destroy() end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "recipe_select_frame",
        direction = "vertical"
    }
    frame.auto_center = true

    -- Titlebar
    local titlebar = frame.add { type = "flow", direction = "horizontal" }
    titlebar.drag_target = frame
    titlebar.add { type = "label", style = "frame_title", caption = "Select Recipe" }
    local filler = titlebar.add { type = "empty-widget", style = "draggable_space_header" }
    filler.style.horizontally_stretchable = true
    filler.drag_target = frame
    titlebar.add { type = "sprite-button", name = "recipe_select_close", sprite = "utility/close_white", style = "frame_action_button" }


    -- Groups flow
    local group_flow = frame.add { type = "flow", name = "group_flow", direction = "horizontal" }
    group_flow.style.vertical_align = "center"
    for _, group in pairs(game.item_group_prototypes) do
        group_flow.add {
            type = "sprite-button",
            name = "selector_group_" .. group.name,
            sprite = "item/" .. group.name, -- placeholder sprite, adjust if needed
            tooltip = group.localised_name,
            style = "slot_button"
        }
    end

    -- Recipe scroll pane
    local recipe_scroll = frame.add { type = "scroll-pane", name = "recipe_scroll", direction = "vertical" }
    recipe_scroll.style.maximal_height = 400
end

local function show_recipe_details(player, recipe_name)
    local frame = player.gui.screen.calc_frame
    if not (frame and frame.valid) then return end
    local recipe = game.recipe_prototypes[recipe_name]
    if not recipe then return end

    -- Clear old content if any
    local body = frame.calc_body
    if body.details_flow then body.details_flow.destroy() end

    local ing_table = frame.calc_body.ingredients_table
    local prod_table = frame.calc_body.products_table
    ing_table.clear()
    prod_table.clear()

    -- Ingredients table
    add_header_row(ing_table)
    for _, ing in pairs(recipe.ingredients) do
        add_item_row(ing_table, ing.name, ing.amount)
    end

    -- Products table
    add_header_row(prod_table)
    for _, prod in pairs(recipe.products) do
        -- Use expected amount for probabilistic products
        local amount = prod.amount or (((prod.amount_min or 0) + (prod.amount_max or 0)) / 2)
        add_item_row(prod_table, prod.name, amount)
    end

    -- Add sum rows (initially zero)
    add_sum_row(ing_table, 0)
    add_sum_row(prod_table, 0)

    -- Trigger initial calculation to populate sums and result label
    -- recalc_launch_sums(player) -- disabled for now
end

-- Create the main button in the mod GUI (top-left corner)
local function create_main_button(player)
    local flow = mod_gui.get_button_flow(player)
    if flow.calc_button then return end

    flow.add{
        type = "sprite-button",
        name = "calc_button",
        sprite = "item/rocket-silo", -- needs a prototype, not a graphics path
        tooltip = "Launch Calculator",
        style = mod_gui.button_style
    }
end

-- === main code === --

-- Initialize global storage
script.on_init(function()
    -- Initialize all existing players (in case mod is added mid-game)
    for _, player in pairs(game.players) do
        create_main_button(player)
    end
end)

-- -- Handle mod updates / configuration changes
-- script.on_configuration_changed(function()
--     global.player_data = global.player_data or {}
--     for _, player in pairs(game.players) do
--         global.player_data[player.index] = global.player_data[player.index] or { round_decimals = 2 }
--     end
-- end)

-- Handle new player creation
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    create_main_button(player)
end)

script.on_configuration_changed(function()
    for _, player in pairs(game.players) do
        create_main_button(player)
    end
end)

-- Handle all GUI clicks
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    local element = event.element
    if not (element and element.valid) then return end

    -- Open/close main window
    if element.name == "calc_button" then
        local existing = player.gui.screen.calc_frame
        if existing then
            existing.destroy()
            return
        end
        create_calc_window(player) -- move all window building to a separate function
        return
    end

    -- Close button
    if element.name == "calc_close_button" then
        local frame = player.gui.screen.calc_frame
        if frame then frame.destroy() end
        return
    end

    -- -- Open recipe selector from main window
    -- if element.name == "select_recipe_button" then
    --     open_recipe_selector(player)
    --     return
    -- end

    -- -- Close recipe selector
    -- if element.name == "recipe_select_close" then
    --     local frame = player.gui.screen.recipe_select_frame
    --     if frame then frame.destroy() end
    --     return
    -- end

    -- -- Click a group in recipe selector
    -- if element.name:find("^selector_group_") then
    --     local group_name = element.name:sub(15)
    --     local frame = player.gui.screen.recipe_select_frame
    --     if frame then
    --         local scroll = frame.recipe_scroll
    --         scroll.clear()
    --         for rname, recipe in pairs(game.recipe_prototypes) do
    --             if recipe.group.name == group_name then
    --                 scroll.add {
    --                     type = "sprite-button",
    --                     name = "selector_recipe_" .. rname,
    --                     sprite = "item/" .. (recipe.products[1] and recipe.products[1].name or "iron-plate"),
    --                     tooltip = recipe.localised_name,
    --                     style = "slot_button"
    --                 }
    --             end
    --         end
    --     end
    --     return
    -- end

    -- -- Click a recipe in selector
    -- if element.name:find("^selector_recipe_") then
    --     local recipe_name = element.name:sub(17)
    --     local frame = player.gui.screen.calc_frame
    --     if frame then
    --         local recipe = game.recipe_prototypes[recipe_name]
    --         if recipe then
    --             -- Update main window recipe icon and label
    --             local sel_flow = frame.selected_recipe_flow
    --             sel_flow.selected_recipe_button.sprite = "item/" ..
    --                 (recipe.products[1] and recipe.products[1].name or "iron-plate")
    --             sel_flow.selected_recipe_label.caption = recipe.localised_name

    --             -- Populate ingredient/product tables
    --             show_recipe_details(player, recipe_name)
    --         end
    --     end
    --     -- Close selector popup
    --     local selector_frame = player.gui.screen.recipe_select_frame
    --     if selector_frame then selector_frame.destroy() end
    --     return
    -- end

    -- -- Checkbox clicks
    -- if element.name:find("^include_row_") then
    --     recalc_launch_sums(player)
    --     return
    -- end
end)
