local MACRO_NAME = "Quest Target"
local MACRO_ICON = 132177
local MACRO_LIMIT = 255
local IDLE_BODY = "/stopmacro"
local defaults = { enemyMarker = 8, npcMarker = 4, includeTagged = false, showMinimap = true }
local settings
local CREATURE_OBJECTIVES, ITEM_OBJECTIVES, SHARED_KILL_OBJECTIVES = 1, 3, 5

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function List(value)
    return type(value) == "table" and value or {}
end

local function GetDatabase()
    local db = LibQuestieDB
    if db and db.RequireContract and db.RequireContract(4)
        and db.Quest and db.Npc and db.Item then
        return db
    end
end

local function Matches(text, name)
    return type(name) == "string" and name ~= "" and text:find(name:lower(), 1, true)
end

local function AddNpcNames(targets, db, ids)
    for _, id in ipairs(List(ids)) do
        local name = db.Npc.name(id)
        if name and not name:find("UNUSED", 1, true) then
            targets[#targets + 1] = name
        end
    end
end

local function AddObjectiveTargets(targets, db, entries, objective)
    local text = objective.text
    if objective.finished or IsSecret(text) or type(text) ~= "string" then
        return
    end

    local lowerText = text:lower()
    if db and objective.type == "item" then
        for _, entry in ipairs(List(entries[ITEM_OBJECTIVES])) do
            if Matches(lowerText, db.Item.name(entry[1])) or Matches(lowerText, entry[2]) then
                AddNpcNames(targets, db, db.Item.npcDrops(entry[1]))
                return
            end
        end
    end

    if db and objective.type ~= "item" and objective.type ~= "object" then
        for _, entry in ipairs(List(entries[CREATURE_OBJECTIVES])) do
            if Matches(lowerText, db.Npc.name(entry[1])) or Matches(lowerText, entry[2]) then
                AddNpcNames(targets, db, {entry[1]})
                return
            end
        end
        for _, entry in ipairs(List(entries[SHARED_KILL_OBJECTIVES])) do
            local matched = Matches(lowerText, entry[3]) or Matches(lowerText, db.Npc.name(entry[2]))
            for _, id in ipairs(List(entry[1])) do
                matched = matched or Matches(lowerText, db.Npc.name(id))
            end
            if matched then
                AddNpcNames(targets, db, entry[1])
                return
            end
        end
    end

    if objective.type == "monster" then
        local name = text:match("^(.-):%s*%d+%s*/%s*%d+%s*$")
            or text:match("^%s*%d+%s*/%s*%d+%s+(.+)$")
        if name then
            name = name:gsub("%s+slain$", ""):gsub("%s+killed$", "")
            targets[#targets + 1] = name
        end
    end
end

local function GetQuestTargets()
    local targets = {}
    local questID = C_SuperTrack.GetSuperTrackedQuestID()
    if IsSecret(questID) or not questID or questID == 0 then
        return targets
    end

    local db = GetDatabase()
    if C_QuestLog.ReadyForTurnIn(questID) then
        if db then
            AddNpcNames(targets, db, List(db.Quest.finishedBy(questID))[1])
        end
        return targets
    end

    local entries = db and List(db.Quest.objectives(questID))
    for _, objective in ipairs(List(C_QuestLog.GetQuestObjectives(questID))) do
        AddObjectiveTargets(targets, db, entries, objective)
    end
    return targets
end

local function TaggedMobNames()
    local tagged, available = {}, {}
    if not (C_NamePlate and C_NamePlate.GetNamePlates and UnitIsTapDenied) then
        return tagged
    end

    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken
        if not IsSecret(unit) and unit and UnitExists(unit) then
            local enemy = UnitCanAttack("player", unit)
            local dead = UnitIsDeadOrGhost(unit)
            if not IsSecret(enemy) and enemy and not IsSecret(dead) and not dead then
                local name = UnitName(unit)
                local denied = UnitIsTapDenied(unit)
                if not IsSecret(name) and type(name) == "string" then
                    local key = name:lower()
                    if not IsSecret(denied) and denied then
                        tagged[key] = true
                    else
                        available[key] = true
                    end
                end
            end
        end
    end
    for key in pairs(available) do
        tagged[key] = nil
    end
    return tagged
end

local function BuildMacro(targets)
    local lines = {"/cleartarget"}
    -- A later name can replace a corpse. If only corpses matched, clear the last one.
    local trailer = "\n/cleartarget [dead]"
    local markers = {}
    if settings.enemyMarker > 0 then
        markers[#markers + 1] = "[harm,nodead] !" .. settings.enemyMarker
    end
    if settings.npcMarker > 0 then
        markers[#markers + 1] = "[exists,noharm,nodead] !" .. settings.npcMarker
    end
    if #markers > 0 then
        trailer = trailer .. "\n/tm " .. table.concat(markers, ";")
    end
    local size = #lines[1] + #trailer
    local seen = {}
    local tagged = #targets > 0 and not settings.includeTagged and TaggedMobNames() or {}
    local skippedTagged = false

    for _, name in ipairs(targets) do
        name = name:match("^%s*(.-)%s*$")
        local key = name:lower()
        if tagged[key] then
            skippedTagged = true
        elseif name ~= "" and not name:find("[%c%[%];]") and not seen[key] then
            local line = "/targetexact [noexists][dead] " .. name
            if size + 1 + #line <= MACRO_LIMIT then
                lines[#lines + 1] = line
                size = size + 1 + #line
                seen[key] = true
            end
        end
    end

    if #lines == 1 then
        return skippedTagged and lines[1] or IDLE_BODY
    end
    return table.concat(lines, "\n") .. trailer
end

local warnedNoSlot
local questTargets = {}
local function RefreshMacro(updateQuest)
    if not settings or InCombatLockdown() then
        return
    end

    if updateQuest then
        questTargets = GetQuestTargets()
    end
    local body = BuildMacro(questTargets)
    local _, characterCount = GetNumMacros()
    local accountLimit = MAX_ACCOUNT_MACROS or 120
    for index = accountLimit + 1, accountLimit + characterCount do
        local name, _, previousBody = GetMacroInfo(index)
        if name == MACRO_NAME then
            if body ~= previousBody then
                EditMacro(index, nil, nil, body)
            end
            warnedNoSlot = false
            return
        end
    end

    if characterCount < (MAX_CHARACTER_MACROS or 30) then
        CreateMacro(MACRO_NAME, MACRO_ICON, body, true)
        warnedNoSlot = false
    elseif not warnedNoSlot then
        print("Forever Quest Target needs one free character macro slot.")
        warnedNoSlot = true
    end
end

local function SetupOptions()
    ForeverQuestTargetDB = type(ForeverQuestTargetDB) == "table" and ForeverQuestTargetDB or {}
    settings = ForeverQuestTargetDB
    for key, value in pairs(defaults) do
        local saved = settings[key]
        if type(saved) ~= type(value) or (type(saved) == "number" and (saved < 0 or saved > 8 or saved % 1 ~= 0)) then
            settings[key] = value
        end
    end

    local panel = CreateFrame("Frame")
    panel.name = "Forever Quest Target"
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(panel.name)
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)

    local function OpenOptions()
        Settings.OpenToCategory(category:GetID())
    end

    local icon = CreateFrame("Button", nil, Minimap)
    icon:SetSize(28, 28)
    icon:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 2, 2)
    icon:SetNormalTexture(MACRO_ICON)
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    icon:SetScript("OnClick", OpenOptions)
    icon:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:SetText(panel.name)
        GameTooltip:AddLine("Click to open options", 1, 1, 1)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local controls = {}
    local function RefreshOptions()
        icon:SetShown(settings.showMinimap)
        for _, update in ipairs(controls) do update() end
        RefreshMacro(false)
    end

    local markerNames = {[0] = "None", "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull"}
    local function MarkerOptions(label, key, y)
        local caption = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        caption:SetPoint("TOPLEFT", 16, y)
        caption:SetText(label)
        for index = 0, 8 do
            local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            button:SetSize(index == 0 and 54 or 32, 26)
            button:SetPoint("TOPLEFT", index == 0 and 16 or 72 + (index - 1) * 34, y - 20)
            button:SetText(index == 0 and "None" or ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:16|t"):format(index))
            button:SetScript("OnClick", function()
                settings[key] = index
                RefreshOptions()
            end)
            button:SetScript("OnEnter", function(control)
                GameTooltip:SetOwner(control, "ANCHOR_TOP")
                GameTooltip:SetText(markerNames[index])
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            controls[#controls + 1] = function()
                if settings[key] == index then button:LockHighlight() else button:UnlockHighlight() end
            end
        end
    end

    local function Checkbox(label, key, y)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 16, y)
        local caption = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        caption:SetPoint("LEFT", check, "RIGHT", 4, 0)
        caption:SetText(label)
        check:SetScript("OnClick", function()
            settings[key] = not not check:GetChecked()
            RefreshOptions()
        end)
        controls[#controls + 1] = function() check:SetChecked(settings[key]) end
    end

    MarkerOptions("Enemy marker", "enemyMarker", -54)
    MarkerOptions("NPC marker", "npcMarker", -112)
    Checkbox("Include mobs tagged by others", "includeTagged", -171)
    Checkbox("Show minimap icon", "showMinimap", -205)
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(120, 24)
    reset:SetPoint("TOPLEFT", 16, -246)
    reset:SetText("Reset defaults")
    reset:SetScript("OnClick", function()
        for key, value in pairs(defaults) do settings[key] = value end
        RefreshOptions()
    end)
    SLASH_FOREVERQUESTTARGET1 = "/fqt"
    SlashCmdList.FOREVERQUESTTARGET = OpenOptions
    RefreshOptions()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SUPER_TRACKING_CHANGED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ADDON_LOADED")

local queued = false
frame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "ForeverQuestTarget" then
        SetupOptions()
        return
    end
    if event == "ADDON_LOADED" and addonName ~= "QuestieDB" then
        return
    end
    if not queued then
        queued = true
        C_Timer.After(0, function()
            queued = false
            RefreshMacro(true)
        end)
    end
end)

-- Tap ownership can change while an existing nameplate stays visible.
C_Timer.NewTicker(0.5, function()
    if #questTargets > 0 then
        RefreshMacro(false)
    end
end)
