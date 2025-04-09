local log = log
local json = json
local sdk = sdk
local thread = thread
local imgui = imgui
local re = re

log.info("[Filter SOS List] started loading")

local configPath = "filter_sos_list.json"

local SOS_CATEGORY <const> = 12

local config = {
	enabled = true,
    general_filters_enabled = true,
    item_filters_enabled = true,
    filter_style = "Custom",
    custom_list_style = "AND",
    item_filters = {},
    maximum_item = "469",
    filter_monster_count = false,
    monster_count_filter = 2,
    monster_count_comparison = "at least",
    filter_monster_threat = false,
    monster_threat_filter = 2,
    monster_threat_comparison = "at least",
    filter_wishlist = false,
    filter_current_players = false,
    current_players_filter = 2,
    current_players_comparison = "at least",
    filter_max_players = false,
    max_players_filter = 2,
    max_players_comparison = "at least",
    filter_started_time = false,
    started_time_filter = 1,
    filter_auto_accept = false,
    filter_multiplay_setting = false,
    multiplay_setting_filter = "Players & NPCs",
    filter_locale = false,
    locale_filter = { ["Plains"] = true, ["Forest"] = false, ["Basin"] = false, ["Cliffs"] = false, ["Wyveria"] = false, ["Wounded Hollow"] = false, ["Rimechain Peak"] = false },
    filter_environment = false,
    environment_filter = { ["Plenty"] = true, ["Fallow"] = false, ["Inclemency"] = false }
}

if json ~= nil then
    local file = json.load_file(configPath)
    if file ~= nil then
        for key, value in pairs(config) do
            if file[key] == nil then
                file[key] = value
            end
        end
		config = file
        json.dump_file(configPath, file)
    else
        json.dump_file(configPath, config)
    end
end

function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

local item_map = {
    ["469"] = "Basic Material",
    ["470"] = "Valuable Material",
    ["478"] = "Ancient Weapon Fragment",
    ["157"] = "Ancient Orb - Armor",
    ["620"] = "Ancient Orb - Sword",
    ["WISHLIST"] = "Wishlisted Item",
    ["GEM"] = "Monster Gem"
}

local id_map = {
    ["Basic Material"] = "469",
    ["Valuable Material"] = "470",
    ["Ancient Weapon Fragment"] = "478",
    ["Ancient Orb - Armor"] = "157",
    ["Ancient Orb - Sword"] = "620"
}

local gem_ids = { "36", "91", "333", "350", "387", "423", "436", "451", "464", "485", "533", "567", "105", "704", "559", "727", "716" }

local comparison_types = { "at least", "at most", "exactly" }
local comparison_type_lookup = { ["at least"] = 1, ["at most"] = 2, ["exactly"] = 3 }

local multiplay_types = { "Players & NPCs", "Players" }
local multiplay_type_lookup = { ["Players & NPCs"] = 1, ["Players"] = 2 }

local selected_item_list_index = 1

local filter_styles = { "Custom", "Maximum" }
local filter_style_lookup = { ["Custom"] = 1, ["Maximum"] = 2 }

local custom_list_styles = { "AND", "OR" }
local custom_list_style_lookup = { ["AND"] = 1, ["OR"] = 2 }

local maximum_items = { "Basic Material", "Valuable Material", "Ancient Weapon Fragment", "Ancient Orb - Armor", "Ancient Orb - Sword" }
local maximum_item_lookup = { ["469"] = 1, ["470"] = 2, ["478"] = 3, ["157"] = 4, ["620"] = 5 }

local stages = { "Plains", "Forest", "Basin", "Cliffs", "Wyveria", "Wounded Hollow", "Rimechain Peak" }
local stage_id_map = { [0] = "Plains", [1] = "Forest", [2] = "Basin", [3] = "Cliffs", [4] = "Wyveria", [9] = "Wounded Hollow", [10] = "Rimechain Peak" }

local environments = { "Plenty", "Fallow", "Inclemency" }
local environment_id_map  = { [2] = "Plenty", [0] = "Fallow", [1] = "Inclemency" }

local function should_filter_quest(reward_table)
    if next(config.item_filters) == nil then return false end

    for item_id, min_required in pairs(config.item_filters) do
        --log.debug("[Filter SOS List] Checking if " .. item_map[item_id] .. " is at least " .. min_required .. "...")
        if config.custom_list_style == "AND" then
            local quest_amount = reward_table[item_id]

            if quest_amount == nil then
                --log.debug("[Filter SOS List] AND condition FAILED... " .. item_map[item_id] .. " is not in the quest rewards!")
                return true
            end

            if quest_amount < min_required then
                --log.debug("[Filter SOS List] AND condition FAILED... " .. item_map[item_id] .. " is only " .. quest_amount .. ", needed at least " .. min_required .. "!")
                return true
            end
        elseif config.custom_list_style == "OR" then
            local quest_amount = reward_table[item_id]

            if quest_amount ~= nil and quest_amount >= min_required then
                --log.debug("[Filter SOS List] OR condition SUCCEEDED! " .. item_map[item_id] .. " is " .. quest_amount .. ", needed at least " .. min_required .. "!")
                return false
            end
        end
    end

    if config.custom_list_style == "AND" then
        --log.debug("[Filter SOS List] AND conditions SUCCEEDED! Quest will NOT be filtered out!")
        return false
    else
        --log.debug("[Filter SOS List] OR conditions FAILED! Quest will be filtered out!")
        return true
    end
end

local function filter_quest_list(quest_list)
    if quest_list == nil then
        log.error("[Filter SOS List] Could not get the quest list!")
        return nil
    end

    local quest_list_size = quest_list:call("get_Count")

    if quest_list_size == nil then
        log.error("[Filter SOS List] Could not get the quest list size!")
        return nil
    end

    local reward_util = sdk.find_type_definition("app.ExQuestRewardUtil")
    local export_rewards = reward_util:get_method("exportExRewardInfoToItemWorkList(app.cExEnemyRewardItemInfo)")

    local wishlist_util = sdk.find_type_definition("app.WishlistUtil")
    local is_wishlist_item = wishlist_util:get_method("isItemRequiredForWishlist(app.ItemDef.ID)")
    local is_wishlist_quest = wishlist_util:get_method("isExQuestRequiredForWishlist(app.cExEnemyRewardItemInfo, app.EnemyDef.ID[], app.EnemyDef.ROLE_ID[], app.EnemyDef.LEGENDARY_ID[], app.QuestDef.RANK, System.Boolean)")

    --local message_util = sdk.find_type_definition("app.MessageUtil")
    --local create_message = message_util:get_method("createMessage(ace.cGUIMessageInfo)")

    local quests_to_remove = {}
    local quests_to_keep = {}
    local max_item_quantity = 0

    for i = 0, quest_list_size - 1 do
        local quest_data = quest_list:call("get_Item", i)
        if quest_data == nil then
            log.warn("[Filter SOS List] Quest [" .. i .. "] is nil!")
            goto continue
        end

        local session_data = quest_data.Session

        -- app.net_session_manager.SessionManager.cSearchResultQuest
        -- This is the holy grail of quest data structures, everything is extremely accessible in its fields
        local search_result = session_data:get_field("<SearchResult>k__BackingField")

        if config.general_filters_enabled and config.filter_multiplay_setting and search_result.multiplaySetting ~= multiplay_type_lookup[config.multiplay_setting_filter] - 1 then
            log.info("[Filter SOS List] Quest [" .. i .. "] is set to allow " .. multiplay_types[search_result.multiplaySetting + 1] .. ", but the multiplay setting filter is enable and set to " .. config.multiplay_setting_filter .. " - removing!")
            if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
            goto continue
        end

        if config.general_filters_enabled and config.filter_auto_accept and search_result.isAutoAccept == false then
            log.info("[Filter SOS List] Quest [" .. i .. "] is not set to auto-accept join requests, but the auto accept filter is enabled - removing!")
            if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
            goto continue
        end

        if config.general_filters_enabled and config.filter_started_time then
            local started_at = search_result.startedAt
            local started_difference = (os.time() - started_at) / 60

            --log.debug("started_at: " .. started_at)
            --log.debug(i + 1 .. " started_difference: " .. started_difference)
            --log.debug(i + 1 .. " accepted_difference: " .. (os.time() - accepted_at) / 60)

            if started_at == 0 then
                --log.debug("ABNORMAL STARTED_AT, acceptedAt: " .. accepted_at)
                local accepted_at = search_result.acceptedAt
                started_difference = (os.time() - accepted_at) / 60
            end
            --log.debug("--------------------------------------")

            if started_difference > config.started_time_filter then
                log.info("[Filter SOS List] Quest [" .. i .. "] was started " .. started_difference .. " minutes ago, but the started time filter is enabled and set to " .. config.started_time_filter .. " minutes - removing!")
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                goto continue
            end
        end

        if config.general_filters_enabled and config.filter_locale then
            local locale = stage_id_map[search_result.fieldId]
            if config.locale_filter[locale] == false then
                log.info("[Filter SOS List] Quest [" .. i .. "] is in " .. locale .. ", but the locale filter is enabled and not set to show quests in " .. locale .. " - removing!")
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                goto continue
            end
        end

        if config.general_filters_enabled and config.filter_environment then
            if search_result.envType == -1 then
                log.info("[Filter SOS List] Quest [" .. i .. "] has no environment, but the environment filter is enabled - removing!")
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                goto continue
            else
                local environment = environment_id_map[search_result.envType]
                if config.environment_filter[environment] == false then
                    log.info("[Filter SOS List] Quest [" .. i .. "] is in " .. environment .. ", but the environment filter is enabled and not set to show quests in " .. environment .. " - removing!")
                    if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                    goto continue
                end
            end
        end

        -- app.EnemyDef.ID[] get_TargetEmId()
        local monster_ids = quest_data:call("get_TargetEmId()")
        local monster_count = monster_ids:get_size()

        if config.general_filters_enabled and config.filter_monster_count then
            local should_remove = false

            if (config.monster_count_comparison == "at least" and monster_count < config.monster_count_filter)
            or (config.monster_count_comparison == "at most" and monster_count > config.monster_count_filter)
            or (config.monster_count_comparison == "exactly" and monster_count ~= config.monster_count_filter) then
                log.info("[Filter SOS List] Quest [" .. i .. "] has " .. monster_count .. " monsters, but the monster count filter is enabled and set to " .. config.monster_count_comparison .. " " .. config.monster_count_filter .. " - removing!")
                should_remove = true
            end

            if should_remove then
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                goto continue
            end
        end

        local monster_ids_str = ""
        for monster_index = 0, monster_count - 1 do
            local monster_id = monster_ids:get_element(monster_index)
            if monster_index == 0 then
                monster_ids_str = monster_ids_str .. tostring(monster_id.value__)
            else
                monster_ids_str = monster_ids_str .. ", " .. tostring(monster_id.value__)
            end
        end

        if config.general_filters_enabled and config.filter_monster_threat then
            local monster_difficulties = quest_data:call("getTragetEmDifficulityRank()")
            local monster_difficulties_count = monster_difficulties:get_size()

            local passes_difficulty_check = false

            if config.monster_threat_comparison == "at most" then
                passes_difficulty_check = true
            end

            for diff_index = 0, monster_difficulties_count - 1 do
                local monster_difficulty = monster_difficulties:call("get_Item", diff_index)
                if (config.monster_threat_comparison == "at least" and monster_difficulty >= config.monster_threat_filter)
                or (config.monster_threat_comparison == "exactly" and monster_difficulty == config.monster_threat_filter) then
                    passes_difficulty_check = true
                    break
                elseif (config.monster_threat_comparison == "at most" and monster_difficulty > config.monster_threat_filter) then
                    passes_difficulty_check = false
                    break
                end
            end

            if passes_difficulty_check == false then
                log.info("[Filter SOS List] Quest [" .. i .. "] does not have a monster with a difficulty of " .. config.monster_threat_comparison .. " " .. config.monster_threat_filter .. " - removing!")
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                goto continue
            end
        end

        if config.general_filters_enabled and config.filter_current_players then
            local current_players = search_result.memberNum
            local should_remove = false

            if (config.current_players_comparison == "at least" and current_players < config.current_players_filter)
            or (config.current_players_comparison == "at most" and current_players > config.current_players_filter)
            or (config.current_players_comparison == "exactly" and current_players ~= config.current_players_filter) then
                log.info("[Filter SOS List] Quest [" .. i .. "] has " .. current_players .. " current players, but the current players filter is enabled and set to " .. config.current_players_comparison .. " " .. config.current_players_filter .. " - removing!")
                should_remove = true
            end

            if should_remove then
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                goto continue
            end
        end

        if config.general_filters_enabled and config.filter_max_players then
            local max_players = search_result.maxMemberNum
            local should_remove = false

            if (config.max_players_comparison == "at least" and max_players < config.max_players_filter)
            or (config.max_players_comparison == "at most" and max_players > config.max_players_filter)
            or (config.max_players_comparison == "exactly" and max_players ~= config.max_players_filter) then
                log.info("[Filter SOS List] Quest [" .. i .. "] has " .. max_players .. " max players, but the max players filter is enabled and set to " .. config.max_players_comparison .. " " .. config.max_players_filter .. " - removing!")
                should_remove = true
            end

            if should_remove then
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                goto continue
            end
        end

        --log.debug("---------------------------------------------")
        --log.debug(tostring(i + 1))
        --log.debug("monster_count: " .. tostring(monster_count))
        --log.debug("monster_ids: " .. monster_ids_str)

        -- app.cExEnemyRewardItemInfo get_ExEnemyRewardItemInfo()
        local quest_reward_obj = quest_data:call("get_ExEnemyRewardItemInfo()")

        -- app.EnemyDef.ROLE_ID[] get_TargetEmRoleId()
        local quest_role_ids = quest_data:call("get_TargetEmRoleId()")

        -- app.EnemyDef.LEGENDARY_ID[] get_TargetEmLegendaryId()
        local quest_legendary_ids = quest_data:call("get_TargetEmLegendaryId()")

        -- app.QuestDef.RANK
        local quest_rank = search_result.questRank

        -- isExQuestRequiredForWishlist(app.cExEnemyRewardItemInfo, app.EnemyDef.ID[], app.EnemyDef.ROLE_ID[], app.EnemyDef.LEGENDARY_ID[], app.QuestDef.RANK, System.Boolean)

        if config.general_filters_enabled and config.filter_wishlist then
            local is_quest_wishlisted = false

            is_quest_wishlisted = is_wishlist_quest:call(wishlist_util, quest_reward_obj, monster_ids, quest_role_ids, quest_legendary_ids, quest_rank, true)

            if is_quest_wishlisted == false then
                log.info("[Filter SOS List] Quest [" .. i .. "] does not have any wishlisted items, but the wishlisted items filter is enabled - removing!")
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
                goto continue
            end
        end

        local reward_table = {}

        local item_work_list = export_rewards:call(reward_util, quest_reward_obj)
        local item_work_list_size = item_work_list._size
        --log.debug("item_work_list_size = " .. tostring(item_work_list_size))
        for item_i = 0, item_work_list_size - 1 do
            local item_work = item_work_list:call("get_Item", item_i)
            local item_id = tostring(item_work:call("get_ItemId()"))
            local item_num = item_work:get_field("Num")

            local quest_reward_on_wishlist = nil

            if config.filter_style == "Custom" then
                quest_reward_on_wishlist = is_wishlist_item:call(wishlist_util, tonumber(item_id))
            end

            if quest_reward_on_wishlist then
                if reward_table["WISHLIST"] then
                    reward_table["WISHLIST"] = reward_table["WISHLIST"] + item_num
                else
                    reward_table["WISHLIST"] = item_num
                end
            end

            if table.contains(gem_ids, item_id) then
                item_id = "GEM"
            end

            if reward_table[item_id] then
                reward_table[item_id] = reward_table[item_id] + item_num
            else
                reward_table[item_id] = item_num
            end
        end

        local item_num = reward_table[config.maximum_item]

        if config.item_filters_enabled and config.filter_style == "Maximum" and item_num ~= nil then
            if item_num > max_item_quantity then
                max_item_quantity = item_num
                quests_to_keep = {}
                table.insert(quests_to_keep, i)
            elseif item_num == max_item_quantity then
                table.insert(quests_to_keep, i)
            end
        end

        if config.item_filters_enabled and config.filter_style == "Custom" and should_filter_quest(reward_table) then
            if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
        end

        ::continue::
    end

    if config.item_filters_enabled and config.filter_style == "Maximum" then
        for i = 0, quest_list_size - 1 do
            if table.contains(quests_to_keep, i) == false then
                if table.contains(quests_to_remove, i) == false then table.insert(quests_to_remove, i) end
            end
        end
    end

    local quest_nums_to_remove = ""
    for _, quest_to_remove in ipairs(quests_to_remove) do
        quest_nums_to_remove = quest_nums_to_remove .. quest_to_remove + 1 .. ", "
    end

    --log.debug("quest_nums_to_remove = " .. quest_nums_to_remove)

    for index = #quests_to_remove, 1, -1 do
        quest_list:RemoveAt(quests_to_remove[index])
    end

    log.info("[Filter SOS List] SOS list filtered!")
end

sdk.hook(sdk.find_type_definition("app.GUI050000QuestListParts"):get_method("sortQuestDataList(System.Boolean)"),
function(args)
    --log.debug("[Filter SOS List] sortQuestDataList(System.Boolean) called!")

    if config.enabled == false then
        log.info("[Filter SOS List] is disabled, canceling execution!")
        return nil
    end

    local storage = thread.get_hook_storage()

    if storage == nil then
        log.error("[Filter SOS List] Could not get hook storage!")
        return nil
    end

    storage["gui050000_remo"] = sdk.to_managed_object(args[2])
end,
function(retval)
    if config.enabled == false then
        log.info("[Filter SOS List] is disabled, canceling execution!")
        return retval
    end

    local storage = thread.get_hook_storage()

    if storage == nil then
        log.error("[Filter SOS List] Could not get hook storage!")
        return retval
    end

    local gui050000_remo = storage["gui050000_remo"]

    if gui050000_remo == nil then
        log.error("[Filter SOS List] gui050000_remo was nil!")
        return retval
    end

    local category = gui050000_remo:get_field("<ViewCategory>k__BackingField")

    if category and category == SOS_CATEGORY then
        filter_quest_list(gui050000_remo:get_field("<ViewQuestDataList>k__BackingField"))
    end

    return retval
end
)

local function draw_settings_checkbox(setting_name)
    local changed, value = imgui.checkbox("##filter_sos_list_" .. setting_name, config[setting_name])
    if changed then
        config[setting_name] = value
        log.info("[Filter SOS List] set [" .. setting_name .. "] to [" .. tostring(value) .. "]!")
        if json ~= nil then json.dump_file(configPath, config) end
        log.info("[Filter SOS List] config updated!")
    end
    return value
end

local function draw_settings_text_input(setting_name, min, max, default, width)
    imgui.push_item_width(width)

    local changed, value, selection_start, selection_end = imgui.input_text("##filter_sos_list_" .. setting_name, config[setting_name], default)
    if changed and tonumber(value) >= min and tonumber(value) <= max then
        config[setting_name] = tonumber(value)
        log.info("[Filter SOS List] set [" .. setting_name .. "] to [" .. value .. "]!")
        if json ~= nil then json.dump_file(configPath, config) end
        log.info("[Filter SOS List] config updated!")
    end

    imgui.pop_item_width()

    return value
end

local function draw_settings_comparison(setting_name, width)
    imgui.push_item_width(width)

    local comparison_index = comparison_type_lookup[config[setting_name]] or 1
    local changed, new_index = imgui.combo("##filter_sos_list_" .. setting_name, comparison_index, comparison_types)

    imgui.pop_item_width()

    if changed then
        config[setting_name] = comparison_types[new_index]
        log.info("[Filter SOS List] set [" .. setting_name .. "] to [" .. config[setting_name] .. "]")
        if json ~= nil then json.dump_file(configPath, config) end
        log.info("[Filter SOS List] config updated!")
    end
end

local function draw_mod_settings()
    local font_size = imgui.get_default_font_size()

    draw_settings_checkbox("enabled")

    imgui.same_line()

    imgui.text("Mod")

    imgui.same_line()

    if config.enabled then
        imgui.text_colored("Enabled", -16711936)
    else
        imgui.text_colored("Disabled", -16776961)
    end

    -------------------------------------------------------------------------------------------------------------------------------------------------------
    -- General Filters
    -------------------------------------------------------------------------------------------------------------------------------------------------------

    imgui.separator()

    draw_settings_checkbox("general_filters_enabled")

    imgui.same_line()

    imgui.text("General Filters")

    imgui.same_line()

    if config.general_filters_enabled then
        imgui.text_colored("Enabled", -16711936)
    else
        imgui.text_colored("Disabled", -16776961)
    end

    if config.general_filters_enabled then
        -- Monster Count ----------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_monster_count")

        if config.filter_monster_count == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests with")

        imgui.same_line()

        draw_settings_comparison("monster_count_comparison", font_size * 5)

        imgui.same_line()

        local value = draw_settings_text_input("monster_count_filter", 1, 4, 1, font_size * 1.875)

        imgui.same_line()

        if tonumber(value) == 1 then
            imgui.text("monster")
        else
            imgui.text("monsters")
        end

        if config.filter_monster_count == false then
            imgui.end_disabled()
        end

        -- Monster Threat ---------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_monster_threat")

        if config.filter_monster_threat == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests with")

        imgui.same_line()

        draw_settings_comparison("monster_threat_comparison", font_size * 5)

        imgui.same_line()

        draw_settings_text_input("monster_threat_filter", 1, 10, 1, font_size * 1.875)

        imgui.same_line()

        imgui.text("threat level")

        if config.filter_monster_threat == false then
            imgui.end_disabled()
        end

        -- Wishlist Monster -----------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_wishlist")

        if config.filter_wishlist == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests with wishlisted monster drops")

        if config.filter_wishlist == false then
            imgui.end_disabled()
        end

        -- Current Player Count -------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_current_players")

        if config.filter_current_players == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests with")

        imgui.same_line()

        draw_settings_comparison("current_players_comparison", font_size * 5)

        imgui.same_line()

        local value = draw_settings_text_input("current_players_filter", 1, 3, 1, font_size * 1.875)

        imgui.same_line()

        if tonumber(value) == 1 then
            imgui.text("current player")
        else
            imgui.text("current players")
        end

        if config.filter_current_players == false then
            imgui.end_disabled()
        end

        -- Max Player Count -----------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_max_players")

        if config.filter_max_players == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests with")

        imgui.same_line()

        draw_settings_comparison("max_players_comparison", font_size * 5)

        imgui.same_line()

        draw_settings_text_input("max_players_filter", 2, 4, 2, font_size * 1.875)

        imgui.same_line()

        imgui.text("max players")

        if config.filter_max_players == false then
            imgui.end_disabled()
        end

        -- Started Time ---------------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_started_time")

        if config.filter_started_time == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests started at most")

        imgui.same_line()

        local value = draw_settings_text_input("started_time_filter", 1, 60, 1, font_size * 1.875)

        imgui.same_line()

        if tonumber(value) == 1 then
            imgui.text("minute ago")
        else
            imgui.text("minutes ago")
        end

        if config.filter_started_time == false then
            imgui.end_disabled()
        end

        -- Auto Accept ----------------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_auto_accept")

        if config.filter_auto_accept == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests that auto-accept join requests")

        if config.filter_auto_accept == false then
            imgui.end_disabled()
        end

        -- Multiplay Setting ----------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_multiplay_setting")

        if config.filter_multiplay_setting == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests that allow")

        imgui.same_line()

        imgui.push_item_width(font_size * 8)

        local multiplay_index = multiplay_type_lookup[config.multiplay_setting_filter] or 1
        local changed, new_index = imgui.combo("##filter_sos_list_multiplay_setting_filter", multiplay_index, multiplay_types)

        imgui.pop_item_width()

        if changed then
            config.multiplay_setting_filter = multiplay_types[new_index]
            log.info("[Filter SOS List] set [multiplay_setting_filter] to [" .. config.multiplay_setting_filter .. "]")
            if json ~= nil then json.dump_file(configPath, config) end
            log.info("[Filter SOS List] config updated!")
        end

        if config.filter_multiplay_setting == false then
            imgui.end_disabled()
        end

        -- Locale Setting -------------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_locale")

        if config.filter_locale == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests in")

        imgui.same_line()

        imgui.push_item_width(font_size * 8)

        local selected_locales = {}
        for _, locale in ipairs(stages) do
            if config.locale_filter[locale] == true then table.insert(selected_locales, locale) end
        end

        local locales_str = ""
        if #selected_locales == 1 then
            locales_str = selected_locales[1]
        elseif #selected_locales == 2 then
            locales_str = selected_locales[1] .. " or " .. selected_locales[2]
        elseif #selected_locales > 2 then
            for i = 1, #selected_locales - 1 do
                locales_str = locales_str .. selected_locales[i] .. ", "
            end
            locales_str = locales_str .. "or " .. selected_locales[#selected_locales]
        else
            locales_str = "<None Selected>"
        end

        if imgui.begin_menu(locales_str .. "##Locale", true) then
            for _, locale in ipairs(stages) do
                local locale_filtered = config.locale_filter[locale] == true
                if imgui.menu_item(locale, nil, locale_filtered, config.filter_locale) then
                    if locale_filtered then
                        config.locale_filter[locale] = false
                        log.info("[Filter SOS List] set [locale_filter[" .. locale .. "]] to [false]")
                        if json ~= nil then json.dump_file(configPath, config) end
                        log.info("[Filter SOS List] config updated!")
                    else
                        config.locale_filter[locale] = true
                        log.info("[Filter SOS List] set [locale_filter[" .. locale .. "]] to [true]")
                        if json ~= nil then json.dump_file(configPath, config) end
                        log.info("[Filter SOS List] config updated!")
                    end
                end
            end
            imgui.end_menu()
        end

        imgui.pop_item_width()

        if config.filter_locale == false then
            imgui.end_disabled()
        end

        -- Environment Setting --------------------------------------------------------------------------------------------------------------------------------
        draw_settings_checkbox("filter_environment")

        if config.filter_environment == false then
            imgui.begin_disabled()
        end

        imgui.same_line()

        imgui.text("Only show quests in")

        imgui.same_line()

        imgui.push_item_width(font_size * 8)

        local selected_environments = {}
        for _, environment in ipairs(environments) do
            if config.environment_filter[environment] == true then table.insert(selected_environments, environment) end
        end

        local environments_str = ""
        if #selected_environments == 1 then
            environments_str = selected_environments[1]
        elseif #selected_environments == 2 then
            environments_str = selected_environments[1] .. " or " .. selected_environments[2]
        elseif #selected_environments > 2 then
            for i = 1, #selected_environments - 1 do
                environments_str = environments_str .. selected_environments[i] .. ", "
            end
            environments_str = environments_str .. "or " .. selected_environments[#selected_environments]
        else
            environments_str = "<None Selected>"
        end

        if imgui.begin_menu(environments_str .. "##Environment", true) then
            for _, environment in ipairs(environments) do
                local environment_filtered = config.environment_filter[environment] == true
                if imgui.menu_item(environment, nil, environment_filtered, config.filter_environment) then
                    if environment_filtered then
                        config.environment_filter[environment] = false
                        log.info("[Filter SOS List] set [environment_filter[" .. environment .. "]] to [false]")
                        if json ~= nil then json.dump_file(configPath, config) end
                        log.info("[Filter SOS List] config updated!")
                    else
                        config.environment_filter[environment] = true
                        log.info("[Filter SOS List] set [environment_filter[" .. environment .. "]] to [true]")
                        if json ~= nil then json.dump_file(configPath, config) end
                        log.info("[Filter SOS List] config updated!")
                    end
                end
            end
            imgui.end_menu()
        end

        imgui.pop_item_width()

        if config.filter_environment == false then
            imgui.end_disabled()
        end
    end

    -------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Item Filters
    -------------------------------------------------------------------------------------------------------------------------------------------------------

    imgui.separator()

    draw_settings_checkbox("item_filters_enabled")

    imgui.same_line()

    imgui.text("Bonus Rewards Filters")

    imgui.same_line()

    if config.item_filters_enabled then
        imgui.text_colored("Enabled", -16711936)
    else
        imgui.text_colored("Disabled", -16776961)
    end

    if config.item_filters_enabled then
        imgui.text("Filter Style:")

        imgui.same_line()

        imgui.push_item_width(font_size * 6.25)

        local filter_style_index = filter_style_lookup[config.filter_style] or 1
        local changed, new_index = imgui.combo("##filter_sos_list_Filter_Style", filter_style_index, filter_styles)

        imgui.pop_item_width()

        if changed then
            config.filter_style = filter_styles[new_index]
            log.info("[Filter SOS List] Filter Style set to [" .. config.filter_style .. "]")
            if json ~= nil then json.dump_file(configPath, config) end
            log.info("[Filter SOS List] config updated!")
        end

        if filter_style_index == 1 then
            imgui.text("Custom List Style:")

            imgui.same_line()

            imgui.push_item_width(font_size * 3.75)

            if config.item_filters == nil then config.item_filters = {} end
            if config.custom_list_style == nil then config.custom_list_style = "AND" end

            local custom_list_style_index = custom_list_style_lookup[config.custom_list_style] or 1
            local changed, new_index = imgui.combo("##filter_sos_list_Custom_List_Style", custom_list_style_index, custom_list_styles)

            if changed then
                config.custom_list_style = custom_list_styles[new_index]
                log.info("[Filter SOS List] Custom List Style set to [" .. config.custom_list_style .. "]")
                if json ~= nil then json.dump_file(configPath, config) end
                log.info("[Filter SOS List] config updated!")
            end

            imgui.pop_item_width()

            imgui.text("Display SOS Quests where:")

            for item_id, item_num in pairs(config.item_filters) do
                if imgui.button("-##filter_sos_list_Remove_" .. item_id, {font_size * 1.375, font_size * 1.375}) then
                    config.item_filters[item_id] = nil
                    log.info("[Filter SOS List] set [item_filters[" .. item_id .. "]] to [nil]!")
                    if json ~= nil then json.dump_file(configPath, config) end
                    log.info("[Filter SOS List] config updated!")
                end

                imgui.same_line()

                imgui.text(item_map[item_id])

                imgui.same_line()

                imgui.text("appears at least")

                imgui.same_line()

                imgui.push_item_width(font_size * 1.875)

                local changed, value, selection_start, selection_end = imgui.input_text("##filter_sos_list_" .. item_id .. "_Amount", item_num, 1)
                if changed and tonumber(value) >= 1 and tonumber(value) <= 99 then
                    config.item_filters[item_id] = tonumber(value)
                    log.info("[Filter SOS List] set [item_filters[" .. item_id .. "]] to [" .. value .. "]!")
                    if json ~= nil then json.dump_file(configPath, config) end
                    log.info("[Filter SOS List] config updated!")
                end

                imgui.pop_item_width()

                imgui.same_line()

                if tonumber(value) == 1 then
                    imgui.text("time")
                else
                    imgui.text("times")
                end

                imgui.indent(font_size * 1.875)
                imgui.text(config.custom_list_style)
                imgui.unindent(font_size * 1.875)
            end

            imgui.same_line()

            imgui.text("..?")

            local filtered_items = {}
            local item_id_lookup = {}

            for item_id, item_name in pairs(item_map) do
                if not config.item_filters[item_id] then
                    table.insert(filtered_items, item_name)
                    item_id_lookup[#filtered_items] = item_id
                end
            end

            if #filtered_items > 0 then
                if imgui.button("+##filter_sos_list_Add", {font_size * 1.375, font_size * 1.375}) and selected_item_list_index > 0 then
                    local selected_item_id = item_id_lookup[selected_item_list_index]
                    config.item_filters[selected_item_id] = 1
                    log.info("[Filter SOS List] set [item_filters[" .. selected_item_id .. "]] to [" .. tostring(1) .. "]!")
                    if json ~= nil then json.dump_file(configPath, config) end
                    log.info("[Filter SOS List] config updated!")
                end

                imgui.same_line()

                imgui.push_item_width(font_size * 12.5)

                local changed, new_index = imgui.combo("##filter_sos_list_Add_Combo", selected_item_list_index, filtered_items)

                imgui.pop_item_width()

                if changed then
                    selected_item_list_index = new_index
                end
            end
        else
            imgui.text("Maximum Item:")

            imgui.same_line()

            imgui.push_item_width(font_size * 12.5)

            local maximum_item_index = maximum_item_lookup[config.maximum_item] or 1
            local changed, new_index = imgui.combo("##filter_sos_list_Add_Combo", maximum_item_index, maximum_items)

            imgui.pop_item_width()

            if changed then
                maximum_item_index = new_index
                local maximum_item_id = id_map[maximum_items[maximum_item_index]]
                config.maximum_item = maximum_item_id
                log.info("[Filter SOS List] set [maximum_item] to [" .. maximum_item_id .. "]!")
                if json ~= nil then json.dump_file(configPath, config) end
                log.info("[Filter SOS List] config updated!")
            end
        end
    end
end

re.on_draw_ui(function()
	if imgui.tree_node("Filter SOS List##filter_sos_list_config") then
		draw_mod_settings()
        imgui.tree_pop()
	end
end)

-- local show_filter_settings = false

-- sdk.hook(sdk.find_type_definition("app.cGUI050000ViewFlow.cGUI050000ViewFlowBase"):get_method("setActive(app.GUI050000.ACTIVE_TYPE)"),
-- function(args)
--     show_filter_settings = sdk.to_int64(args[3]) == 4
-- end)

-- re.on_frame(function()
--     if show_filter_settings then
--         imgui.begin_window("SOS Filter Settings", nil, nil)

--         draw_mod_settings()

--         imgui.end_window()
--     end
-- end)

log.info("[Filter SOS List] finished loading")