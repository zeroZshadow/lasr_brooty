-- Archipelago auto-tracking for the "Links Awakening Switch" world (LASAP).
-- PopTracker connects to the Archipelago server as a tracker. Items the slot received set the pack's items, checked
-- locations clear their sections, and the seed's settings (slot data "settings", LASR's names) set the toggles.
ScriptHost:LoadScript("scripts/autotracking/item_mapping.lua")
ScriptHost:LoadScript("scripts/autotracking/location_mapping.lua")

-- Toggles set from a LASR setting that is true
local SETTING_TOGGLES = {
    ["Heart Pieces"] = "s_hp",
    ["Seashells"] = "s_ss",
    ["Trade Quest"] = "s_tq",
    ["Trendy Game"] = "trendy",
    ["Rapids"] = "rapids",
    ["Dampe"] = "dampe",
    ["Blue Rupees"] = "d0rupee",
    ["Golden Leaves"] = "kanalet",
    ["Open Kanalet"] = "opencastle",
    ["Completed Bridge"] = "completedbridge",
    ["Free Book"] = "freebook",
    ["Open Mabe"] = "openmabe",
    ["Open Mamu"] = "openmamu",
    ["Fast Stalfos"] = "faststalfos",
}
-- Progressive settings: LASR setting -> {item code, {LASR value -> stage}}
local SETTING_STAGES = {
    ["Preset"] = {"l_bas", {Basic = 0, Advanced = 1, Glitched = 2, Hell = 2}},
    ["Shop"] = {"shop_off", {[false] = 0, [true] = 1}},
    ["Stealing"] = {"s_never", {Never = 0, Standard = 1, Always = 2}},
    ["Classic D2"] = {"classic_off", {[false] = 0, [true] = 1}},
    ["Shuffled Dungeons"] = {"dungeon_er_off", {[false] = 0, [true] = 1}},
}

-- How many of the slot's Archipelago locations each section stands for, and how many of them are checked
local SECTION_TOTALS = {}
local SECTION_CHECKED = {}
-- Every section with an Archipelago location
local SECTIONS = {}
-- The seed the sections show: a reconnect to it keeps the sections, marked by hand or not
local section_seed = nil
-- A hidden item keeps that seed in the tracker's saved state, so the sections survive a restart of PopTracker too
local seed_item = ScriptHost:CreateLuaItem()
seed_item.Name = "Archipelago seed"
seed_item.PotentialCodes = {}
seed_item.CanProvideCodeFunc = function(self, code) return false end
seed_item.ProvidesCodeFunc = function(self, code) return false end
seed_item.SaveFunc = function(self) return {seed = section_seed} end
seed_item.LoadFunc = function(self, data) section_seed = data and data.seed or nil end
for _, codes in pairs(LOCATION_MAPPING) do
    for _, code in ipairs(codes) do
        SECTIONS[code] = true
    end
end

-- The slot's locations as a set, or nil when this PopTracker does not tell them
local function slot_locations()
    if not Archipelago.MissingLocations or not Archipelago.CheckedLocations then
        return nil
    end
    local slot = {}
    for _, id in ipairs(Archipelago.MissingLocations) do
        slot[id] = true
    end
    for _, id in ipairs(Archipelago.CheckedLocations) do
        slot[id] = true
    end
    return slot
end

-- Counts the slot's locations per section (all of them when the slot's are not known). The options leave some out,
-- such as the fairy's with Free Gifts off; a section with none of the slot's locations has nothing to check.
local function count_sections()
    local slot = slot_locations()
    SECTION_TOTALS = {}
    for id, codes in pairs(LOCATION_MAPPING) do
        if not slot or slot[id] then
            for _, code in ipairs(codes) do
                SECTION_TOTALS[code] = (SECTION_TOTALS[code] or 0) + 1
            end
        end
    end
    for code, _ in pairs(SECTIONS) do
        local section = Tracker:FindObjectForCode(code)
        if section and not SECTION_TOTALS[code] then
            section.AvailableChestCount = 0
        end
    end
end

-- The Wind Fish's Egg path, marked by hand: one arrow per step, back to its first stage for another seed
local EGG_PATH = {"up1", "up2", "up3", "up4", "up5", "up6", "up7", "up8"}
-- Dungeon ER: the dungeon each door leads into, marked by hand, back to Unknown for another seed. Slot data has the
-- doors (dungeon_entrances), but the player finds them by entering, so the tracker does not set them.
local DOORS = {"tcdX", "bgdX", "kcdX", "atdX", "cmdX", "fsdX", "etdX", "trdX", "cddX"}
-- Items a section hosts that no Archipelago item sets: PopTracker sets a hosted item only when the section is
-- clicked, and shows the section unchecked until it is set. They are set once the section's checks are all in.
local HOSTED = {
    ["@Dungeons/D0 - Color Dungeon/Fairy Queen/Red|Blue Tunic"] = "fairyq",  -- the Color Dungeon cleared
}

local function reset_item(code, kind)
    local obj = Tracker:FindObjectForCode(code)
    if not obj then
        return
    end
    if kind == "consumable" then
        obj.AcquiredCount = 0
    elseif kind == "toggle" then
        obj.Active = false
    else
        obj.CurrentStage = 0
        obj.Active = false
    end
end

local function apply_settings(settings)
    for setting, code in pairs(SETTING_TOGGLES) do
        local obj = Tracker:FindObjectForCode(code)
        if obj and settings[setting] ~= nil then
            obj.Active = settings[setting] == true
        end
    end
    for setting, entry in pairs(SETTING_STAGES) do
        local obj = Tracker:FindObjectForCode(entry[1])
        local stage = entry[2][settings[setting]]
        if obj and stage then
            obj.CurrentStage = stage
        end
    end
    -- One item for both fishing settings: No Fishing, Fishing (the pond's checks), Fast Fishing
    local fishing = Tracker:FindObjectForCode("fishing_off")
    if fishing and settings["Fishing"] ~= nil then
        fishing.CurrentStage = settings["Fishing"] and (settings["Fast Fishing"] and 2 or 1) or 0
    end
    local mansion = Tracker:FindObjectForCode("mansion")
    if mansion and settings["Seashell Mansion"] then
        mansion.Active = settings["Seashell Mansion"] > 0
    end
    local owls = Tracker:FindObjectForCode("owlstatue")
    if owls and settings["Owl Gifts"] then
        owls.Active = settings["Owl Gifts"] ~= "None"
    end
end

-- The LASAP client keeps the game's level (Field, Lv01TailCave, ...) in data storage; the tracker shows its map.
local LEVEL_TABS = {
    Lv01TailCave = "Tail Cave",
    Lv02BottleGrotto = "Bottle Grotto",
    Lv03KeyCavern = "Key Cavern",
    Lv04AnglersTunnel = "Angler's Tunnel",
    Lv05CatfishsMaw = "Catfish Maw",
    Lv06FaceShrine = "Face Shrine",
    Lv07EagleTower = "Eagle Tower",
    Lv08TurtleRock = "Turtle Rock",
    Lv10ClothesDungeon = "Color Dungeon",
}
local level_key = nil
local shown_tab = nil
-- The LASAP client sets this key to true once the player has read the sign at the egg's stairs, which names the
-- instruments the egg needs. A count left to chance (slot data instruments_known false) stays "?" until then.
local sign_key = nil
local instruments_required = 8

local function show_instruments(hidden)
    local required = Tracker:FindObjectForCode("instruments_required")
    if not required then
        return
    end
    INSTRUMENTS_HIDDEN = hidden
    required:SetOverlay(hidden and "?" or "")
    required.AcquiredCount = hidden and 0 or instruments_required
end

local function sign_read(key, value)
    if key == sign_key and value == true and INSTRUMENTS_HIDDEN then
        show_instruments(false)
    end
end

local function show_level(key, level)
    if key ~= level_key or type(level) ~= "string" or level == "" then
        return
    end
    local tab = LEVEL_TABS[level] or "Overworld"
    if tab ~= shown_tab then
        shown_tab = tab
        Tracker:UiHint("ActivateTab", tab)
    end
end

local function on_clear(slot_data)
    level_key = "las_level_" .. Archipelago.TeamNumber .. "_" .. Archipelago.PlayerNumber
    shown_tab = nil
    sign_key = "las_sign_" .. Archipelago.TeamNumber .. "_" .. Archipelago.PlayerNumber
    Archipelago:SetNotify({level_key, sign_key})
    Archipelago:Get({level_key, sign_key})
    -- the server sends every checked location again after this
    SECTION_CHECKED = {}
    local seed = slot_data and slot_data["seed_hash"] or nil
    if seed == nil or seed ~= section_seed then
        section_seed = seed
        for code, _ in pairs(SECTIONS) do
            local section = Tracker:FindObjectForCode(code)
            if section then
                section.AvailableChestCount = section.ChestCount
            end
        end
        for _, codes in ipairs({EGG_PATH, DOORS}) do
            for _, code in ipairs(codes) do
                local obj = Tracker:FindObjectForCode(code)
                if obj then
                    obj.CurrentStage = 0
                end
            end
        end
        for _, code in pairs(HOSTED) do
            local obj = Tracker:FindObjectForCode(code)
            if obj then
                obj.Active = false
            end
        end
    end
    count_sections()
    for _, entry in pairs(ITEM_MAPPING) do
        reset_item(entry[1], type(entry[2]) == "number" and "stage" or entry[2])
    end
    if slot_data and slot_data["settings"] then
        apply_settings(slot_data["settings"])
    end
    if slot_data and slot_data["instruments_required"] then
        instruments_required = slot_data["instruments_required"]
        -- slot data without instruments_known (an older world) counts as known
        show_instruments(slot_data["instruments_known"] == false)
    end
end

local function on_item(index, item_id, item_name, player_number)
    local entry = ITEM_MAPPING[item_id]
    if not entry then
        return
    end
    local obj = Tracker:FindObjectForCode(entry[1])
    if not obj then
        return
    end
    local kind = entry[2]
    if type(kind) == "number" then
        if not obj.Active or obj.CurrentStage < kind then
            obj.CurrentStage = kind
        end
        obj.Active = true
    elseif kind == "consumable" then
        obj.AcquiredCount = obj.AcquiredCount + obj.Increment
    elseif kind == "progressive" then
        if obj.Active then
            obj.CurrentStage = obj.CurrentStage + 1
        else
            obj.Active = true
        end
    else
        obj.Active = true
    end
end

local function on_location(location_id, location_name)
    local codes = LOCATION_MAPPING[location_id]
    if not codes then
        return
    end
    for _, code in ipairs(codes) do
        local section = Tracker:FindObjectForCode(code)
        if section then
            -- A section can stand for several locations (the Color Dungeon's rupees, shop slots): it empties as
            -- they are checked. It never fills up again, so a section cleared by hand stays cleared.
            SECTION_CHECKED[code] = (SECTION_CHECKED[code] or 0) + 1
            local total = math.max(SECTION_TOTALS[code] or 0, SECTION_CHECKED[code])
            local left = section.ChestCount
                - math.floor(section.ChestCount * math.min(SECTION_CHECKED[code], total) / total)
            section.AvailableChestCount = math.min(section.AvailableChestCount, left)
            local hosted = HOSTED[code] and Tracker:FindObjectForCode(HOSTED[code])
            if hosted and SECTION_CHECKED[code] >= total then
                hosted.Active = true
            end
        end
    end
end

Archipelago:AddClearHandler("clear handler", on_clear)
Archipelago:AddItemHandler("item handler", on_item)
Archipelago:AddLocationHandler("location handler", on_location)
Archipelago:AddRetrievedHandler("level retrieved", show_level)
Archipelago:AddSetReplyHandler("level changed", show_level)
Archipelago:AddRetrievedHandler("sign retrieved", sign_read)
Archipelago:AddSetReplyHandler("sign read", sign_read)
