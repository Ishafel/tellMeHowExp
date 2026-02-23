-- QuestXPOverlay
-- Classic/TBC-compatible addon that overlays potential quest turn-in XP on MainMenuExpBar.

local addonFrame = CreateFrame("Frame")

local state = {
    pendingUpdate = false,
    potentialXP = 0,
    completedCount = 0,
    forceTest = false,
}

local overlayFrame
local overlayTexture
local QueueUpdate

local function Chat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

local function EnsureOverlay()
    if overlayFrame and overlayTexture then
        return true
    end

    if not MainMenuExpBar then
        return false
    end

    -- Draw above the standard XP bar stack for Anniversary/Classic compatibility.
    overlayFrame = CreateFrame("Frame", "QuestXPOverlayFrame", UIParent)
    overlayFrame:SetFrameStrata("TOOLTIP")
    overlayFrame:SetFrameLevel(1)
    overlayFrame:EnableMouse(false)
    overlayFrame:Hide()

    overlayTexture = overlayFrame:CreateTexture(nil, "OVERLAY")
    overlayTexture:SetAllPoints(overlayFrame)
    overlayTexture:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    overlayTexture:SetVertexColor(0.10, 0.65, 1.0, 0.85)
    overlayTexture:SetBlendMode("BLEND")

    MainMenuExpBar:HookScript("OnSizeChanged", function()
        QueueUpdate()
    end)

    return true
end

local function IsXPAvailable(maxXP)
    -- Safer for Classic/TBC variants: rely on UnitXPMax; avoid expansion APIs that may be absent.
    if not maxXP or maxXP <= 0 then
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

local function HideOverlay()
    if overlayFrame then
        overlayFrame:Hide()
    end
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

    if state.forceTest then
        potentialXP = maxXP
    end

    if potentialXP <= 0 or not IsXPAvailable(maxXP) then
        HideOverlay()
        return
    end

    local barWidth = MainMenuExpBar:GetWidth() or 0
    local barHeight = MainMenuExpBar:GetHeight() or 0
    if barWidth <= 0 or barHeight <= 0 then
        HideOverlay()
        return
    end

    local currentRatio = currentXP / maxXP
    local endRatio = math.min(1, (currentXP + potentialXP) / maxXP)
    local widthRatio = math.max(0, endRatio - currentRatio)

    if widthRatio <= 0 then
        HideOverlay()
        return
    end

    overlayFrame:ClearAllPoints()
    overlayFrame:SetPoint("TOPLEFT", MainMenuExpBar, "TOPLEFT", barWidth * currentRatio, -1)
    overlayFrame:SetPoint("BOTTOMLEFT", MainMenuExpBar, "BOTTOMLEFT", barWidth * currentRatio, 1)
    overlayFrame:SetWidth(barWidth * widthRatio)
    overlayFrame:Show()
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

    local potentialXP, completedCount = ComputePotentialQuestXP()
    state.potentialXP = potentialXP
    state.completedCount = completedCount

    local barWidth = MainMenuExpBar and MainMenuExpBar:GetWidth() or -1
    local barHeight = MainMenuExpBar and MainMenuExpBar:GetHeight() or -1

    Chat("[QXP] current XP: " .. currentXP)
    Chat("[QXP] max XP: " .. maxXP)
    Chat("[QXP] potential quest XP: " .. potentialXP)
    Chat("[QXP] completed quests counted: " .. completedCount)
    Chat("[QXP] bar size: " .. barWidth .. " x " .. barHeight)
    Chat("[QXP] test mode: " .. (state.forceTest and "ON" or "OFF"))
    Chat("[QXP] hint: use slash command '/qxp' (with /)")

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
SLASH_QUESTXPOVERLAY2 = "/questxp"
SlashCmdList.QUESTXPOVERLAY = function(msg)
    local cmd = msg and strtrim(msg) or ""

    if cmd == "update" then
        QueueUpdate()
        Chat("[QXP] overlay update queued.")
        return
    end

    if cmd == "test" then
        state.forceTest = not state.forceTest
        Chat("[QXP] test mode: " .. (state.forceTest and "ON" or "OFF"))
        QueueUpdate()
        return
    end

    PrintDebug()
end
