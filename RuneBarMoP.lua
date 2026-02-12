--[[
RuneBarMoP.lua
Author: enjoymygripz
A minimalistic Rune resource bar for Death Knights in MoP Classic.
Hold Shift + drag to reposition. Use /runebar scale <number> to adjust size.
]]--

local addonName, addon = ...
local db

-- Rune Types for MoP Classic
local RUNE_TYPE_BLOOD = 1
local RUNE_TYPE_FROST = 2
local RUNE_TYPE_UNHOLY = 3
local RUNE_TYPE_DEATH = 4

-- Rune Colors (Enhanced for visibility)
local RUNE_COLORS = {
    [RUNE_TYPE_BLOOD] = {1.0, 0.0, 0.0}, -- Rot
    [RUNE_TYPE_UNHOLY] = {0.0, 0.8, 0.0}, -- Green
    [RUNE_TYPE_FROST] = {0.0, 0.8, 1.0}, -- Cyan
    [RUNE_TYPE_DEATH] = {1.0, 0.4, 1.0}, -- Original Blizzard Pink/Lila
}

-------------------------------------------------------------
-- Utility
-------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffC41E3ARuneBarMoP:|r " .. msg)
end

-- Localization (enUS default, deDE overrides)
local L = {
    Title = "RuneBarMoP Settings",
    Scale = "Scale: %.2f",
    OOCOpacity = "OOC Opacity: %.2f",
    ICOpacity = "In-Combat Opacity: %.2f",
    RPZeroOpacity = "RP Opacity (0 RP): %.2f",
    EnableRPBar = "Show Runic Power Bar",
    RPBarOpacity = "RP Bar Opacity: %.2f",
    ShowRPText = "Show RP Text",
    ResetPosition = "Reset Position",
    LockBar = "Lock Bar (disable mouse)",
    HideOOC = "Hide when Out of Combat",
    Close = "Close",
    Instructions = "Hold Shift + drag the rune bar to move it",
}

if GetLocale() == "deDE" then
    L.Title = "RuneBarMoP Einstellungen"
    L.Scale = "Skalierung: %.2f"
    L.OOCOpacity = "OOC Deckkraft: %.2f"
    L.ICOpacity = "Im-Kampf Deckkraft: %.2f"
    L.RPZeroOpacity = "Runenmacht-Deckkraft (0 RP): %.2f"
    L.EnableRPBar = "Runenmacht-Leiste anzeigen"
    L.RPBarOpacity = "Deckkraft der Runenmacht-Leiste: %.2f"
    L.ShowRPText = "Runenmacht-Text anzeigen"
    L.ResetPosition = "Position zurücksetzen"
    L.LockBar = "Leiste sperren (Maus deaktivieren)"
    L.HideOOC = "Außerhalb des Kampfes ausblenden"
    L.Close = "Schließen"
    L.Instructions = "Halte Shift und ziehe die Leiste zum Verschieben"
end

-- NEW: Default settings
local DEFAULTS = {
    scale = 1,
    locked = false,
    hideOOC = false,
    oocAlpha = 0.35,
    icAlpha = 1.0,
    rpZeroAlpha = 0.35,
    enableRPBar = false,
    rpBarAlpha = 1,
    showRPText = false,
}

-------------------------------------------------------------
-- Frame Setup
-------------------------------------------------------------
local bar = CreateFrame("Frame", "RuneBarMoPFrame", UIParent)
bar:SetPoint("CENTER", UIParent, "CENTER", 0, -250)
bar:SetSize(250, 35)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then
        self:StartMoving()
    end
end)
bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

-- Background for debugging
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetTexture(0, 0, 0, 0.3)

-------------------------------------------------------------
-- Rune System
-------------------------------------------------------------
local MAX_RUNES = 6
local RUNE_SIZE = 32
local GAP = 6
local runes = {}
local optionsPanel -- forward declaration for GUI
local CreateOptionsPanel -- forward declaration for function
local UpdateVisibility -- forward declaration for visibility update function
local UpdateAlpha -- forward declaration for alpha update function
local RUNIC_POWER_ID = 6
local rpBar -- optional Runic Power bar
local rpText -- centered RP text on the rune bar
local EnsureRPText -- forward declaration for RP text creator
local rpTextFrame -- overlay frame for RP text above rune frames
local PositionRPText -- forward declaration for positioning helper

local function CreateRPBar()
    if rpBar then return end
    -- Parent to UIParent so it doesn't inherit rune bar alpha
    rpBar = CreateFrame("StatusBar", "RuneBarMoPRPBar", UIParent)
    rpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    rpBar:GetStatusBarTexture():SetHorizTile(false)
    rpBar:SetMinMaxValues(0, 100)
    rpBar:SetValue(0)
    rpBar:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    rpBar:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
    rpBar:SetHeight(10)
    rpBar:SetStatusBarColor(0.0, 0.6, 1.0, 1)

    local bgTex = rpBar:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    bgTex:SetVertexColor(0, 0, 0, 0.5)

    rpBar:Hide()
end

local function UpdateRPBar()
    local current = UnitPower("player", RUNIC_POWER_ID) or 0
    local max = UnitPowerMax("player", RUNIC_POWER_ID) or 0

    if db and db.enableRPBar then
        if not rpBar then CreateRPBar() end
        local _, class = UnitClass("player")
        if class ~= "DEATHKNIGHT" then 
            if rpBar then rpBar:Hide() end 
        else
            -- Only show RP bar if main bar is visible (unless settings are open)
            if not bar:IsShown() and not (optionsPanel and optionsPanel:IsShown()) then
                if rpBar then rpBar:Hide() end
                return
            end
            rpBar:SetMinMaxValues(0, max > 0 and max or 100)
            rpBar:SetValue(current)
            local alpha = (current <= 0) and (db.rpZeroAlpha or 1) or (db.rpBarAlpha or 1)
            rpBar:SetAlpha(math.max(0.05, math.min(1, alpha)))
            rpBar:ClearAllPoints()
            rpBar:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
            rpBar:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
            rpBar:Show()
            PositionRPText()
        end
    elseif rpBar then
        rpBar:Hide()
    end
end

local function UpdateRPText()
    if not db or not db.showRPText then
        if rpText then rpText:Hide() end
        return
    end
    -- Only show RP text if main bar is visible (unless settings are open)
    if not bar:IsShown() and not (optionsPanel and optionsPanel:IsShown()) then
        if rpText then rpText:Hide() end
        return
    end
    -- Hide RP text if World Map is open
    if WorldMapFrame and WorldMapFrame:IsVisible() then
        if rpText then rpText:Hide() end
        return
    end
    EnsureRPText()
    local current = UnitPower("player", RUNIC_POWER_ID) or 0
    rpText:SetText(string.format("%d", current))
    PositionRPText()
    rpText:Show()
end

local function LayoutRunes()
    local scale = (db and db.scale or 1)
    local size = scale * RUNE_SIZE
    
    for i, rune in ipairs(runes) do
        rune.frame:SetSize(size, size)
        if i == 1 then
            rune.frame:SetPoint("LEFT", bar, "LEFT", 0, 0)
        else
            rune.frame:SetPoint("LEFT", runes[i - 1].frame, "RIGHT", GAP * scale, 0)
        end
        
        -- Scale the inner textures
        rune.texture:SetSize(size * 0.8, size * 0.8)
        rune.border:SetSize(size, size)
        rune.cooldown:SetSize(size * 0.9, size * 0.9)
    end
    
    local width = MAX_RUNES * size + (MAX_RUNES - 1) * GAP * scale
    bar:SetSize(width, size)
    if rpText then PositionRPText() end
    if rpBar then
        rpBar:ClearAllPoints()
        rpBar:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
        rpBar:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
        rpBar:SetHeight(math.max(6, floor(size * 0.35)))
    end
end

local function CreateRunes()
    for i = 1, MAX_RUNES do
        local rune = {}
        
        -- Main frame
        rune.frame = CreateFrame("Frame", "RuneBarMoPRune" .. i, bar)
        rune.frame:SetSize(RUNE_SIZE, RUNE_SIZE)
        
        -- Rune texture (the actual rune symbol)
        rune.texture = rune.frame:CreateTexture(nil, "ARTWORK")
        rune.texture:SetAllPoints()
        rune.texture:SetTexture("Interface\\PlayerFrame\\UI-PlayerFrame-DeathKnight-SingleRune")
        rune.texture:SetVertexColor(0.3, 0.3, 0.3, 0.8) -- Default dimmed
        
        -- Border
        rune.border = rune.frame:CreateTexture(nil, "BORDER")
        rune.border:SetAllPoints()
        rune.border:SetTexture("Interface\\PlayerFrame\\UI-PlayerFrame-DeathKnight-Ring")
        rune.border:SetVertexColor(0.5, 0.5, 0.5, 1)
        
        -- Cooldown spiral
        rune.cooldown = CreateFrame("Cooldown", "RuneBarMoPCooldown" .. i, rune.frame, "CooldownFrameTemplate")
        rune.cooldown:SetAllPoints()
        rune.cooldown:SetReverse(true)
        
        -- Rune ID for tracking
        rune.id = i
        
        runes[i] = rune
    end
    
    LayoutRunes()
end

function EnsureRPText()
    if not rpTextFrame then
        rpTextFrame = CreateFrame("Frame", nil, bar)
        rpTextFrame:SetAllPoints(bar)
        rpTextFrame:SetFrameStrata("HIGH")
        rpTextFrame:SetFrameLevel(bar:GetFrameLevel() + 20)
    end
    if not rpText then
        rpText = rpTextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        rpText:SetPoint("CENTER", rpTextFrame, "CENTER", 0, 0)
        rpText:SetText("")
        rpText:Hide()
    end
end

-- Position RP text either on RP bar (if visible) or centered on rune bar
function PositionRPText()
    if not rpText then return end
    local useRPBar = (db and db.enableRPBar) and rpBar and rpBar:IsShown()
    local anchor = useRPBar and rpBar or bar
    rpText:ClearAllPoints()
    rpText:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    if useRPBar then
        local h = (rpBar and rpBar:GetHeight()) or 10
        local f = math.max(10, floor(h * 0.85))
        rpText:SetFont("Fonts\\FRIZQT__.TTF", f, "OUTLINE")
    else
        local scale = (db and db.scale or 1)
        local size = math.max(12, floor(scale * RUNE_SIZE * 0.6))
        rpText:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end
end


-------------------------------------------------------------
-- Updates
-------------------------------------------------------------
local function UpdateRunes()
    UpdateVisibility()
    -- Bail out early if player is not a DK (avoids GetRuneCooldown nils on other classes)
    if select(2, UnitClass("player")) ~= "DEATHKNIGHT" then return end

    -- Define desired rune order and mapping to actual rune positions
    local desiredRuneTypes = {RUNE_TYPE_BLOOD, RUNE_TYPE_BLOOD, RUNE_TYPE_FROST, RUNE_TYPE_FROST, RUNE_TYPE_UNHOLY, RUNE_TYPE_UNHOLY}
    local runeMapping = {1, 2, 5, 6, 3, 4}  -- Maps display position to actual rune index (swapped Frost and Unholy)

    for i = 1, MAX_RUNES do
        local rune = runes[i]
        if rune then
            local actualIndex = runeMapping[i]
            local start, duration, runeReady = GetRuneCooldown(actualIndex)
            local actualRuneType = GetRuneType(actualIndex)

            -- Use actual rune type if it's a Death Rune, otherwise use desired type
            local runeType
            if actualRuneType == RUNE_TYPE_DEATH then
                runeType = RUNE_TYPE_DEATH
            else
                runeType = desiredRuneTypes[i]
            end

            -- Enhanced error handling
            if not runeType or runeType == 0 then
                runeType = RUNE_TYPE_BLOOD -- fallback
            end
            
            if runeReady then
                -- Rune is ready
                local color = RUNE_COLORS[runeType] or {1, 1, 1}
                rune.texture:SetVertexColor(color[1], color[2], color[3], 1)
                rune.border:SetVertexColor(color[1], color[2], color[3], 1)
                rune.cooldown:Hide()
            else
                -- Rune is on cooldown
                local color = RUNE_COLORS[runeType] or {1, 1, 1}
                rune.texture:SetVertexColor(color[1] * 0.3, color[2] * 0.3, color[3] * 0.3, 0.8)
                rune.border:SetVertexColor(0.5, 0.5, 0.5, 1)
                
                if type(start) == "number" and type(duration) == "number" and duration > 0 then
                    rune.cooldown:Show()
                    rune.cooldown:SetCooldown(start, duration)
                else
                    -- Fallback when API returns nils sporadically; treat as no active cooldown
                    rune.cooldown:Hide()
                end
            end
        end
    end
    UpdateAlpha()
end

-- NEW: Handle mouse interactivity (lock/unlock)
local function UpdateInteractivity()
    if not db then return end
    if db.locked then
        bar:EnableMouse(false)
    else
        bar:EnableMouse(true)
    end
end

-- NEW: Force show bar for settings (better UX)
local function ForceShowForSettings()
    local _, class = UnitClass("player")
    if class == "DEATHKNIGHT" then
        bar:Show()
    end
end

-- REPLACE UpdateVisibility implementation
UpdateVisibility = function()
    local _, class = UnitClass("player")
    if class ~= "DEATHKNIGHT" then
        bar:Hide()
        return
    end

    -- Always show while settings/options panel is open (better UX)
    if optionsPanel and optionsPanel:IsShown() then
        bar:Show()
        if db and db.enableRPBar then UpdateRPBar() end
        if db and db.showRPText then UpdateRPText() end
        UpdateAlpha()
        return
    end
    
    local inCombat = UnitAffectingCombat("player")
    if db and db.hideOOC and not inCombat then
        bar:Hide()
        if rpBar then rpBar:Hide() end
        if rpText then rpText:Hide() end
        return
    else
        bar:Show()
        if db and db.enableRPBar then UpdateRPBar() end
        if db and db.showRPText then UpdateRPText() end
    end
    UpdateAlpha()
end

-- Alpha handling (OOC fade and optional Runic Power fade)
UpdateAlpha = function()
    if not db then return end
    local _, class = UnitClass("player")
    if class ~= "DEATHKNIGHT" then return end
    if not bar:IsShown() then return end

    local alpha = tonumber(db.icAlpha) or 1
    local inCombat = UnitAffectingCombat("player")

    if not inCombat then
        local configuredOOCAlpha = tonumber(db.oocAlpha) or 1
        if configuredOOCAlpha and configuredOOCAlpha > 0 and configuredOOCAlpha < 1 then
            alpha = math.max(0.05, math.min(1, configuredOOCAlpha))
        end
    end

    -- Rune bar alpha only; RP bar alpha handled separately

    bar:SetAlpha(alpha)
end

-------------------------------------------------------------
-- Event Handler
-------------------------------------------------------------
bar:SetScript("OnEvent", function(_, event, ...)
    if addon[event] then
        addon[event](addon, ...)
    end
end)

bar:RegisterEvent("PLAYER_LOGIN")
bar:RegisterEvent("RUNE_POWER_UPDATE")
bar:RegisterEvent("RUNE_TYPE_UPDATE")
bar:RegisterEvent("PLAYER_LEVEL_UP")
bar:RegisterEvent("PLAYER_REGEN_ENABLED")
bar:RegisterEvent("PLAYER_REGEN_DISABLED")
bar:RegisterEvent("UNIT_POWER_UPDATE")
bar:RegisterEvent("PLAYER_ENTERING_WORLD")

function addon:PLAYER_LOGIN()
    -- Initialize database
    RuneBarMoPDB = RuneBarMoPDB or {}
    for k, v in pairs(DEFAULTS) do
        if RuneBarMoPDB[k] == nil then RuneBarMoPDB[k] = v end
    end
    db = RuneBarMoPDB

    -- Hook WorldMapFrame to hide RP text when map opens
    if WorldMapFrame then
        hooksecurefunc(WorldMapFrame, "Show", function() UpdateRPText() end)
        hooksecurefunc(WorldMapFrame, "Hide", function() UpdateRPText() end)
    end

    -- Create the UI
    CreateRunes()
    if db.enableRPBar then CreateRPBar() end
    UpdateVisibility()
    LayoutRunes()
    UpdateRunes()
    UpdateInteractivity()
    UpdateAlpha()
    UpdateRPBar()
    UpdateRPText()
    PositionRPText()
    UpdateRPBar()

    Print("Addon loaded! Use /runebar for options.")
end

function addon:RUNE_POWER_UPDATE(runeIndex)
    UpdateRunes()
end

function addon:RUNE_TYPE_UPDATE(runeIndex)
    UpdateRunes()
end

function addon:PLAYER_LEVEL_UP()
    -- Update in case something changed
    UpdateRunes()
end

function addon:PLAYER_REGEN_ENABLED()
    -- Left combat → apply OOC visibility rules
    UpdateVisibility()
    UpdateAlpha()
end

function addon:PLAYER_REGEN_DISABLED()
    -- Entered combat → ensure bar is shown and alpha recalculated
    UpdateVisibility()
    UpdateAlpha()
end

function addon:UNIT_POWER_UPDATE(unit, powerType)
    if unit ~= "player" then return end
    -- Only update RP components, do not trigger visibility changes
    UpdateAlpha()
    if db and db.enableRPBar then UpdateRPBar() end
    if db and db.showRPText then UpdateRPText() end
    if rpText then PositionRPText() end
end

function addon:PLAYER_ENTERING_WORLD()
    UpdateVisibility()
    UpdateAlpha()
    UpdateRPBar()
    UpdateRPText()
    PositionRPText()
    if db and db.showRPText then EnsureRPText() rpText:Show() end
end


-------------------------------------------------------------
-- Slash Commands
-------------------------------------------------------------
SLASH_RUNEBARMOP1 = "/runebar"
SlashCmdList.RUNEBARMOP = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "" or cmd == "gui" then
        if not optionsPanel then CreateOptionsPanel() end
        if optionsPanel:IsShown() then
            optionsPanel:Hide()
            UpdateVisibility() -- restore normal visibility when closing
        else
            optionsPanel:Show()
            -- Do not force-show bar while menu is open; honor hide OOC
            optionsPanel:SetPropagateKeyboardInput(true)
            UpdateVisibility()
        end
        return
    elseif cmd == "scale" and arg ~= "" then
        local value = tonumber(arg)
        if value and value > 0 then
            db.scale = value
            LayoutRunes()
            Print("Scale set to " .. value)
        else
            Print("Invalid scale value. Example: /runebar scale 1.25")
        end
    elseif cmd == "lock" then
        db.locked = true
        UpdateInteractivity()
        Print("Bar locked. It is now click-through.")
    elseif cmd == "unlock" then
        db.locked = false
        UpdateInteractivity()
        Print("Bar unlocked. You can drag it while holding Shift.")
    elseif cmd == "hideooc" then
        arg = arg:lower()
        if arg == "on" then
            db.hideOOC = true
            UpdateVisibility()
            Print("Bar will hide when out of combat.")
        elseif arg == "off" then
            db.hideOOC = false
            UpdateVisibility()
            Print("Bar will remain visible out of combat.")
        else
            Print("Usage: /runebar hideooc on|off")
        end
    else
        Print("Commands:\n  /runebar            - Open settings GUI.\n  /runebar scale <number>   - Set bar scale (e.g., 1.25).\n  /runebar lock / unlock    - Toggle mouse interaction (click-through).\n  /runebar hideooc on|off   - Toggle hiding out of combat.\nHold Shift + Left-drag the bar to move it.")
    end
end

-- GUI --------------------------------------------------------
CreateOptionsPanel = function()
    -- Create standalone window
    optionsPanel = CreateFrame("Frame", "RuneBarMoPOptionsPanel", UIParent)
    optionsPanel:SetSize(560, 600) -- extra room so all controls fit comfortably in all locales
    optionsPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    optionsPanel:SetMovable(true)
    optionsPanel:EnableMouse(true)
    optionsPanel:RegisterForDrag("LeftButton")
    optionsPanel:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    optionsPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    optionsPanel:SetFrameStrata("DIALOG")
    optionsPanel:Hide()
    
    -- Dark background (Death Knight theme)
    local bg = optionsPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.95)
    
    -- Red border (Death Knight theme)
    local border = optionsPanel:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0.77, 0.12, 0.23, 1) -- Death Knight red
    
    -- Inner black background
    local innerBg = optionsPanel:CreateTexture(nil, "ARTWORK")
    innerBg:SetPoint("TOPLEFT", 2, -2)
    innerBg:SetPoint("BOTTOMRIGHT", -2, 2)
    innerBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    innerBg:SetVertexColor(0.1, 0.1, 0.1, 1)
    
    -- Allow game controls while panel is open; Esc closes via UISpecialFrames
    optionsPanel:EnableKeyboard(false)
    tinsert(UISpecialFrames, "RuneBarMoPOptionsPanel")

    -- Title
    local title = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", optionsPanel, "TOP", 0, -15)
    title:SetText(L.Title)
    title:SetTextColor(0.77, 0.12, 0.23) -- Death Knight red

    -- Scale slider
    local scaleSlider = CreateFrame("Slider", "RuneBarMoPScaleSlider", optionsPanel, "OptionsSliderTemplate")
    scaleSlider:SetWidth(280)
    scaleSlider:SetPoint("TOP", title, "BOTTOM", 0, -30)
    scaleSlider:SetMinMaxValues(0.5, 2)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    _G[scaleSlider:GetName() .. "Low"]:SetText("0.5")
    _G[scaleSlider:GetName() .. "High"]:SetText("2")

    scaleSlider.Text = scaleSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleSlider.Text:SetPoint("TOP", scaleSlider, "BOTTOM", 0, -8)
    scaleSlider.Text:SetTextColor(1, 1, 1) -- White text

    scaleSlider:SetScript("OnShow", function(self)
        self:SetValue(db and db.scale or 1)
        self.Text:SetText(string.format(L.Scale, db and db.scale or 1))
    end)

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.scale = value
        self.Text:SetText(string.format(L.Scale, value))
        LayoutRunes()
    end)

    -- OOC Alpha slider
    local oocSlider = CreateFrame("Slider", "RuneBarMoPOOCSlider", optionsPanel, "OptionsSliderTemplate")
    oocSlider:SetWidth(320)
    oocSlider:SetPoint("TOP", scaleSlider.Text, "BOTTOM", 0, -30)
    oocSlider:SetMinMaxValues(0.1, 1)
    oocSlider:SetValueStep(0.05)
    oocSlider:SetObeyStepOnDrag(true)
    _G[oocSlider:GetName() .. "Low"]:SetText("0.1")
    _G[oocSlider:GetName() .. "High"]:SetText("1")
    oocSlider.Text = oocSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    oocSlider.Text:SetPoint("TOP", oocSlider, "BOTTOM", 0, -8)
    oocSlider.Text:SetTextColor(1, 1, 1)
    oocSlider:SetScript("OnShow", function(self)
        self:SetValue(db and db.oocAlpha or 1)
        self.Text:SetText(string.format(L.OOCOpacity, db and db.oocAlpha or 1))
    end)
    oocSlider:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.oocAlpha = value
        self.Text:SetText(string.format(L.OOCOpacity, value))
        UpdateAlpha()
    end)

    -- In-Combat Alpha slider
    local icSlider = CreateFrame("Slider", "RuneBarMoPICSlider", optionsPanel, "OptionsSliderTemplate")
    icSlider:SetWidth(320)
    icSlider:SetPoint("TOP", oocSlider.Text, "BOTTOM", 0, -30)
    icSlider:SetMinMaxValues(0.1, 1)
    icSlider:SetValueStep(0.05)
    icSlider:SetObeyStepOnDrag(true)
    _G[icSlider:GetName() .. "Low"]:SetText("0.1")
    _G[icSlider:GetName() .. "High"]:SetText("1")
    icSlider.Text = icSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    icSlider.Text:SetPoint("TOP", icSlider, "BOTTOM", 0, -8)
    icSlider.Text:SetTextColor(1, 1, 1)
    icSlider:SetScript("OnShow", function(self)
        self:SetValue(db and db.icAlpha or 1)
        self.Text:SetText(string.format(L.ICOpacity, db and db.icAlpha or 1))
    end)
    icSlider:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.icAlpha = value
        self.Text:SetText(string.format(L.ICOpacity, value))
        UpdateAlpha()
    end)

    -- Reset Position Button
    local resetButton = CreateFrame("Button", "RuneBarMoPResetButton", optionsPanel, "UIPanelButtonTemplate")
    resetButton:SetSize(120, 25)
    resetButton:SetPoint("TOP", icSlider.Text, "BOTTOM", 0, -20)
    resetButton:SetText(L.ResetPosition)
    resetButton:SetScript("OnClick", function()
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, -250)
        Print("Position reset to center")
    end)

    -- Lock checkbox
    local lockCheckbox = CreateFrame("CheckButton", "RuneBarMoPLockCheckbox", optionsPanel, "UICheckButtonTemplate")
    lockCheckbox:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 20, -220)
    _G[lockCheckbox:GetName() .. "Text"]:SetText(L.LockBar)
    lockCheckbox:SetScript("OnShow", function(self)
        self:SetChecked(db.locked)
    end)
    lockCheckbox:SetScript("OnClick", function(self)
        db.locked = self:GetChecked()
        UpdateInteractivity()
    end)

    -- Hide OOC checkbox
    local oocCheckbox = CreateFrame("CheckButton", "RuneBarMoPOOCCheckbox", optionsPanel, "UICheckButtonTemplate")
    oocCheckbox:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -18)
    _G[oocCheckbox:GetName() .. "Text"]:SetText(L.HideOOC)
    oocCheckbox:SetScript("OnShow", function(self)
        self:SetChecked(db.hideOOC)
    end)
    oocCheckbox:SetScript("OnClick", function(self)
        db.hideOOC = self:GetChecked()
        UpdateVisibility()
    end)

    -- Toggle RP Bar
    local rpBarCheckbox = CreateFrame("CheckButton", "RuneBarMoPEnableRPBar", optionsPanel, "UICheckButtonTemplate")
    rpBarCheckbox:SetPoint("TOPLEFT", oocCheckbox, "BOTTOMLEFT", 0, -22)
    _G[rpBarCheckbox:GetName() .. "Text"]:SetText(L.EnableRPBar)
    rpBarCheckbox:SetScript("OnShow", function(self)
        self:SetChecked(db.enableRPBar)
    end)
    rpBarCheckbox:SetScript("OnClick", function(self)
        db.enableRPBar = self:GetChecked()
        if db.enableRPBar then CreateRPBar() end
        UpdateRPBar()
        UpdateRPText()
    end)

    -- RP Zero opacity slider (affects only RP bar)
    local rpZeroSlider = CreateFrame("Slider", "RuneBarMoPRPZeroSlider", optionsPanel, "OptionsSliderTemplate")
    rpZeroSlider:SetWidth(320)
    rpZeroSlider:SetPoint("TOPLEFT", rpBarCheckbox, "BOTTOMLEFT", 5, -26)
    rpZeroSlider:SetMinMaxValues(0.1, 1)
    rpZeroSlider:SetValueStep(0.05)
    rpZeroSlider:SetObeyStepOnDrag(true)
    _G[rpZeroSlider:GetName() .. "Low"]:SetText("0.1")
    _G[rpZeroSlider:GetName() .. "High"]:SetText("1")
    rpZeroSlider.Text = rpZeroSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rpZeroSlider.Text:SetPoint("TOP", rpZeroSlider, "BOTTOM", 0, -8)
    rpZeroSlider.Text:SetTextColor(1, 1, 1)
    rpZeroSlider:SetScript("OnShow", function(self)
        self:SetValue(db and db.rpZeroAlpha or 0.35)
        self.Text:SetText(string.format(L.RPZeroOpacity, db and db.rpZeroAlpha or 0.35))
    end)
    rpZeroSlider:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.rpZeroAlpha = value
        self.Text:SetText(string.format(L.RPZeroOpacity, value))
        UpdateRPBar()
        UpdateRPText()
    end)

    -- RP Bar opacity slider
    local rpBarAlphaSlider = CreateFrame("Slider", "RuneBarMoPRPBarAlphaSlider", optionsPanel, "OptionsSliderTemplate")
    rpBarAlphaSlider:SetWidth(320)
    rpBarAlphaSlider:SetPoint("TOPLEFT", rpZeroSlider.Text, "BOTTOMLEFT", -5, -30)
    rpBarAlphaSlider:SetMinMaxValues(0.1, 1)
    rpBarAlphaSlider:SetValueStep(0.05)
    rpBarAlphaSlider:SetObeyStepOnDrag(true)
    _G[rpBarAlphaSlider:GetName() .. "Low"]:SetText("0.1")
    _G[rpBarAlphaSlider:GetName() .. "High"]:SetText("1")
    rpBarAlphaSlider.Text = rpBarAlphaSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rpBarAlphaSlider.Text:SetPoint("TOP", rpBarAlphaSlider, "BOTTOM", 0, -8)
    rpBarAlphaSlider.Text:SetTextColor(1, 1, 1)
    rpBarAlphaSlider:SetScript("OnShow", function(self)
        self:SetValue(db and db.rpBarAlpha or 1)
        self.Text:SetText(string.format(L.RPBarOpacity, db and db.rpBarAlpha or 1))
    end)
    rpBarAlphaSlider:SetScript("OnValueChanged", function(self, value)
        if not db then return end
        db.rpBarAlpha = value
        self.Text:SetText(string.format(L.RPBarOpacity, value))
        UpdateRPBar()
    end)

    -- RP text checkbox (centered number on rune bar)
    local rpTextCheckbox = CreateFrame("CheckButton", "RuneBarMoPShowRPText", optionsPanel, "UICheckButtonTemplate")
    rpTextCheckbox:SetPoint("TOPLEFT", rpBarAlphaSlider.Text, "BOTTOMLEFT", -5, -24)
    _G[rpTextCheckbox:GetName() .. "Text"]:SetText(L.ShowRPText)
    rpTextCheckbox:SetScript("OnShow", function(self)
        self:SetChecked(db.showRPText)
    end)
    rpTextCheckbox:SetScript("OnClick", function(self)
        db.showRPText = self:GetChecked()
        UpdateRPText()
        PositionRPText()
    end)

    -- Close button
    local closeButton = CreateFrame("Button", "RuneBarMoPCloseButton", optionsPanel, "UIPanelButtonTemplate")
    closeButton:SetSize(60, 25)
    closeButton:SetPoint("BOTTOMRIGHT", optionsPanel, "BOTTOMRIGHT", -20, 20)
    closeButton:SetText(L.Close)
    closeButton:SetScript("OnClick", function()
        optionsPanel:Hide()
        UpdateVisibility() -- restore normal visibility when closing
    end)

    -- Instructions
    local instructions = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("BOTTOMLEFT", optionsPanel, "BOTTOMLEFT", 20, 95)
    instructions:SetText(L.Instructions)

    -- removed extra RP bar controls to keep UI simple
    instructions:SetTextColor(0.77, 0.12, 0.23, 0.8) -- Death Knight red with transparency
end 