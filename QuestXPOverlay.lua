-- QuestXPOverlay
-- Classic/TBC compatible addon that overlays potential quest turn-in XP on MainMenuExpBar.

local addonFrame = CreateFrame("Frame")

local state = {
    pendingUpdate = false,
    potentialXP = 0,
    completedCount = 0,
}

local overlay

local function EnsureOverlay()
    if overlay and overlay:GetParent() == MainMenuExpBar then
        return true
    end

    if not MainMenuExpBar then
        return false
    end

    overlay = CreateFrame("StatusBar", "QuestXPOverlayBar", MainMenuExpBar)
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(1)
    overlay:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    overlay:SetStatusBarColor(0.2, 0.6, 1.0, 0.45) -- semi-transparent blue

    overlay:SetFrameStrata(MainMenuExpBar:GetFrameStrata())
    overlay:SetFrameLevel(MainMenuExpBar:GetFrameLevel() + 2)

    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", MainMenuExpBar, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMLEFT", MainMenuExpBar, "BOTTOMLEFT", 0, 0)
    overlay:SetWidth(0)
    overlay:Hide()

    return true
end

local function IsXPAvailable(maxXP)
    if not maxXP or maxXP <= 0 then
        return false
    end

    -- Most compatible check across Classic/TBC variants: if UnitLevel returns nil, treat as XP available.
    local level = UnitLevel("player")
    local maxLevel = MAX_PLAYER_LEVEL_TABLE and MAX_PLAYER_LEVEL_TABLE[GetAccountExpansionLevel() or 0]
    if level and maxLevel and level >= maxLevel then
        return false
    end

    return true
end

local function ComputePotentialQuestXP()
    local totalXP = 0
    local completed = 0

    local numEntries = GetNumQuestLogEntries() or 0
    if numEntries <= 0 then
        return 0, 0
    end

    -- Preserve selected quest when possible (Classic/TBC API by quest log index).
    local previousSelection = GetQuestLogSelection and GetQuestLogSelection() or nil

    for i = 1, numEntries do
        local _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)

        if not isHeader and isComplete == 1 then
            SelectQuestLogEntry(i)
            local xp = GetQuestLogRewardXP() or 0
            if xp > 0 then
                totalXP = totalXP + xp
                completed = completed + 1
            end
        end
    end

    if previousSelection and previousSelection > 0 and previousSelection <= numEntries then
        SelectQuestLogEntry(previousSelection)
    end

    return totalXP, completed
end

local function UpdateOverlay()
    if not EnsureOverlay() then
        return
    end

    local currentXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 0

    local potentialXP, completedCount = ComputePotentialQuestXP()
    state.potentialXP = potentialXP
    state.completedCount = completedCount

    if potentialXP <= 0 or not IsXPAvailable(maxXP) then
        overlay:Hide()
        return
    end

    local barWidth = MainMenuExpBar:GetWidth() or 0
    if barWidth <= 0 then
        overlay:Hide()
        return
    end

    local currentRatio = currentXP / maxXP
    local endRatio = math.min(1, (currentXP + potentialXP) / maxXP)
    local widthRatio = math.max(0, endRatio - currentRatio)
    local overlayWidth = barWidth * widthRatio

    if overlayWidth <= 0 then
        overlay:Hide()
        return
    end

    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", MainMenuExpBar, "TOPLEFT", barWidth * currentRatio, 0)
    overlay:SetPoint("BOTTOMLEFT", MainMenuExpBar, "BOTTOMLEFT", barWidth * currentRatio, 0)
    overlay:SetWidth(overlayWidth)
    overlay:Show()
end

local function QueueUpdate()
    if state.pendingUpdate then
        return
    end

    state.pendingUpdate = true
    C_Timer.After(0.08, function()
        state.pendingUpdate = false
        UpdateOverlay()
    end)
end

local function PrintDebug()
    local currentXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 0

    -- Recompute for fresh debug output.
    local potentialXP, completedCount = ComputePotentialQuestXP()
    state.potentialXP = potentialXP
    state.completedCount = completedCount

    DEFAULT_CHAT_FRAME:AddMessage("[QXP] current XP: " .. currentXP)
    DEFAULT_CHAT_FRAME:AddMessage("[QXP] max XP: " .. maxXP)
    DEFAULT_CHAT_FRAME:AddMessage("[QXP] potential quest XP: " .. potentialXP)
    DEFAULT_CHAT_FRAME:AddMessage("[QXP] completed quests counted: " .. completedCount)

    QueueUpdate()
end

addonFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        QueueUpdate()
    elseif event == "QUEST_LOG_UPDATE" then
        QueueUpdate()
    elseif event == "PLAYER_XP_UPDATE" then
        QueueUpdate()
    elseif event == "UPDATE_EXHAUSTION" then
        QueueUpdate()
    elseif event == "PLAYER_LEVEL_UP" then
        QueueUpdate()
    end
end)

addonFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
addonFrame:RegisterEvent("QUEST_LOG_UPDATE")
addonFrame:RegisterEvent("PLAYER_XP_UPDATE")
addonFrame:RegisterEvent("UPDATE_EXHAUSTION")
addonFrame:RegisterEvent("PLAYER_LEVEL_UP")

SLASH_QUESTXPOVERLAY1 = "/qxp"
SlashCmdList.QUESTXPOVERLAY = function(msg)
    local cmd = msg and strtrim(msg) or ""
    if cmd == "update" then
        QueueUpdate()
        DEFAULT_CHAT_FRAME:AddMessage("[QXP] overlay update queued.")
        return
    end

    PrintDebug()
end
