-- QuestXPOverlay
-- Classic/TBC-compatible addon that overlays potential quest turn-in XP on MainMenuExpBar.

local addonFrame = CreateFrame("Frame")

local state = {
    pendingUpdate = false,
    potentialXP = 0,
    completedCount = 0,
}

local overlayTexture
local QueueUpdate

local function EnsureOverlay()
    if overlayTexture and overlayTexture:GetParent() == MainMenuExpBar then
        return true
    end

    if not MainMenuExpBar then
        return false
    end

    -- Use a plain texture instead of a nested StatusBar for maximum compatibility with Classic/TBC XP bar internals.
    overlayTexture = MainMenuExpBar:CreateTexture("QuestXPOverlayTexture", "OVERLAY", nil, 1)
    overlayTexture:SetColorTexture(0.2, 0.6, 1.0, 0.45) -- semi-transparent blue
    overlayTexture:Hide()

    -- Keep the overlay aligned if XP bar size changes (UI scale, resolution, edit mode style movement).
    MainMenuExpBar:HookScript("OnSizeChanged", function()
        QueueUpdate()
    end)

    return true
end

local function IsXPAvailable(maxXP)
    if not maxXP or maxXP <= 0 then
        return false
    end

    -- Most compatible check across Classic/TBC variants.
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
        overlayTexture:Hide()
        return
    end

    local barWidth = MainMenuExpBar:GetWidth() or 0
    local barHeight = MainMenuExpBar:GetHeight() or 0
    if barWidth <= 0 or barHeight <= 0 then
        overlayTexture:Hide()
        return
    end

    local currentRatio = currentXP / maxXP
    local endRatio = math.min(1, (currentXP + potentialXP) / maxXP)
    local widthRatio = math.max(0, endRatio - currentRatio)

    if widthRatio <= 0 then
        overlayTexture:Hide()
        return
    end

    overlayTexture:ClearAllPoints()
    overlayTexture:SetPoint("TOPLEFT", MainMenuExpBar, "TOPLEFT", barWidth * currentRatio, 0)
    overlayTexture:SetPoint("BOTTOMLEFT", MainMenuExpBar, "BOTTOMLEFT", barWidth * currentRatio, 0)
    overlayTexture:SetWidth(barWidth * widthRatio)
    overlayTexture:Show()
end

QueueUpdate = function()
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
