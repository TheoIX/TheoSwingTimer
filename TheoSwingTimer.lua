-- TheoSwingTimer - TBC 2.4.3 / TBC Classic 2.5.3 compatible build
-- Default behavior: ON, hidden out of combat, visible in combat.
-- Visual style: dark track, white fill scrolling left -> right, white spark, timer text.
--
-- Compatibility note:
-- 2.5.3-style clients usually use CombatLogGetCurrentEventInfo().
-- 2.4.3-style clients usually pass combat-log values directly through COMBAT_LOG_EVENT_UNFILTERED.
-- This file supports both paths.

local TSW = {}
_G.TheoSwingTimer = TSW

SLASH_THEOSWINGTIMER1 = "/tsw"
SlashCmdList["THEOSWINGTIMER"] = function(msg)
    msg = msg or ""
    if TSW and TSW.Slash then
        TSW:Slash(msg)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TheoSwingTimer:|r slash is alive, still initializing.")
    end
end

local function Chat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TheoSwingTimer:|r " .. tostring(msg))
    end
end

local function Lower(s)
    if s then return string.lower(s) end
    return ""
end

local function Trim(s)
    if not s then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local defaults = {
    enabled = true,
    locked = false,
    showOOC = false,
    debug = false,
    scale = 1.0,
    width = 260,
    height = 14,
    x = 0,
    y = -120,
    version = 7,
}

local db
local eventFrame = CreateFrame("Frame")
local frame, title, mhBar, ohBar
local playerGUID
local playerName
local inCombat = false
local testMode = false

local mhStart, ohStart = nil, nil
local mhDur, ohDur = 2.0, nil
local lastMHSpeed, lastOHSpeed = 2.0, nil
local lastMHSwing, lastOHSwing = 0, 0
local lastSpeedPoll = 0

local function CopyDefaults()
    if not TheoSwingTimerDB then TheoSwingTimerDB = {} end
    db = TheoSwingTimerDB

    local k, v
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end

    -- Migration from earlier test/visible builds:
    -- preserve position/size, but force the requested default behavior.
    if db.version ~= 7 then
        db.enabled = true
        db.showOOC = false
        db.version = 7
    end
end

local function SafeRegister(ev)
    local ok = pcall(function() eventFrame:RegisterEvent(ev) end)
    if not ok then
        Chat("could not register event " .. tostring(ev))
    end
end

local function GetSpeeds()
    local mh, oh = UnitAttackSpeed("player")
    if not mh or mh <= 0 then mh = 2.0 end
    if oh and oh <= 0 then oh = nil end
    return mh, oh
end

local function SavePosition()
    if not frame or not db then return end
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    db.x = x or db.x or 0
    db.y = y or db.y or -120
end

local function ForceCenter()
    if not db then return end
    db.x = 0
    db.y = -120
    db.scale = db.scale or 1
end

local function MakeBar(parent, name, yOfs, labelText)
    local bar = CreateFrame("StatusBar", name, parent)
    bar:SetWidth(db.width)
    bar:SetHeight(db.height)
    bar:SetPoint("TOP", parent, "TOP", 0, yOfs)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(1, 1, 1, 0.92)
    bar:SetFrameLevel(parent:GetFrameLevel() + 2)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(0, 0, 0, 0.72)
    bar.bg = bg

    local top = bar:CreateTexture(nil, "OVERLAY")
    top:SetTexture(1, 1, 1, 0.35)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    bar.top = top

    local bottom = bar:CreateTexture(nil, "OVERLAY")
    bottom:SetTexture(1, 1, 1, 0.20)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.bottom = bottom

    local left = bar:CreateTexture(nil, "OVERLAY")
    left:SetTexture(1, 1, 1, 0.20)
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.left = left

    local right = bar:CreateTexture(nil, "OVERLAY")
    right:SetTexture(1, 1, 1, 0.20)
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.right = right

    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(1, 1, 1, 1)
    spark:SetWidth(3)
    spark:SetHeight((db.height or 14) + 8)
    spark:SetPoint("CENTER", bar, "LEFT", 0, 0)
    bar.spark = spark

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", bar, "LEFT", 5, 0)
    label:SetText(labelText)
    label:SetTextColor(0, 0, 0, 1)

    local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    txt:SetText("0.0")
    txt:SetTextColor(0, 0, 0, 1)

    local labelShadow = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelShadow:SetPoint("LEFT", bar, "LEFT", 6, -1)
    labelShadow:SetText(labelText)
    labelShadow:SetTextColor(1, 1, 1, 0.85)

    local txtShadow = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txtShadow:SetPoint("RIGHT", bar, "RIGHT", -4, -1)
    txtShadow:SetText("0.0")
    txtShadow:SetTextColor(1, 1, 1, 0.85)

    bar.label = label
    bar.timeText = txt
    bar.labelShadow = labelShadow
    bar.timeShadow = txtShadow
    return bar
end

local function ApplyLayout()
    if not frame or not db then return end

    local w = db.width or 260
    local h = db.height or 14
    local totalH = (h * 2) + 32

    frame:SetScale(db.scale or 1)
    frame:SetWidth(w + 16)
    frame:SetHeight(totalH)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -120)

    if title then
        title:ClearAllPoints()
        title:SetPoint("TOP", frame, "TOP", 0, -5)
    end

    if mhBar then
        mhBar:SetWidth(w)
        mhBar:SetHeight(h)
        mhBar:ClearAllPoints()
        mhBar:SetPoint("TOP", frame, "TOP", 0, -20)
        if mhBar.spark then mhBar.spark:SetHeight(h + 8) end
    end

    if ohBar then
        ohBar:SetWidth(w)
        ohBar:SetHeight(h)
        ohBar:ClearAllPoints()
        ohBar:SetPoint("TOP", frame, "TOP", 0, -(20 + h + 6))
        if ohBar.spark then ohBar.spark:SetHeight(h + 8) end
    end
end

local function SetVisible(show)
    if not frame then return end
    if show then
        frame:Show()
    else
        frame:Hide()
    end
end

local function ShouldShow()
    if not db or not db.enabled then return false end
    if testMode then return true end
    if db.showOOC then return true end
    if inCombat then return true end
    return false
end

local function ResetSwing(hand, dur, now)
    now = now or GetTime()
    if hand == "OH" then
        if not dur then return end
        ohStart = now
        ohDur = dur
        lastOHSwing = now
    else
        mhStart = now
        mhDur = dur or 2.0
        lastMHSwing = now
    end
end

local function SoftStart()
    local now = GetTime()
    local mh, oh = GetSpeeds()
    mhDur = mh
    ohDur = oh
    lastMHSpeed = mh
    lastOHSpeed = oh
    if not mhStart then mhStart = now end
    if oh and not ohStart then ohStart = now end
end

local function RescaleSwing(oldStart, oldDur, newDur, now)
    if not oldStart or not oldDur or oldDur <= 0 then
        return now
    end

    local progress = (now - oldStart) / oldDur
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end

    return now - (progress * newDur)
end

local function CheckSpeedChange(force)
    local now = GetTime()
    if not force and now - lastSpeedPoll < 0.05 then return end
    lastSpeedPoll = now

    local mh, oh = GetSpeeds()

    if force or mh ~= lastMHSpeed then
        mhStart = RescaleSwing(mhStart, mhDur, mh, now)
        mhDur = mh
        lastMHSpeed = mh
    end

    if oh then
        if not ohStart then ohStart = now end
        if force or oh ~= lastOHSpeed then
            ohStart = RescaleSwing(ohStart, ohDur or oh, oh, now)
            ohDur = oh
            lastOHSpeed = oh
        end
    else
        ohStart = nil
        ohDur = nil
        lastOHSpeed = nil
    end
end

local function UpdateBar(bar, startTime, dur, now)
    if not bar then return end

    if not startTime or not dur or dur <= 0 then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        if bar.spark then bar.spark:Hide() end
        bar.timeText:SetText("-")
        bar.timeShadow:SetText("-")
        return
    end

    local elapsed = now - startTime
    if elapsed < 0 then elapsed = 0 end

    local remain = dur - elapsed
    if remain < 0 then
        elapsed = dur
        remain = 0
    end

    bar:SetMinMaxValues(0, dur)
    bar:SetValue(elapsed)

    local t = string.format("%.1f", remain)
    bar.timeText:SetText(t)
    bar.timeShadow:SetText(t)

    if bar.spark then
        local width = bar:GetWidth() or (db and db.width) or 260
        local progress = elapsed / dur
        if progress < 0 then progress = 0 end
        if progress > 1 then progress = 1 end
        local x = width * progress
        bar.spark:ClearAllPoints()
        bar.spark:SetPoint("CENTER", bar, "LEFT", x, 0)
        bar.spark:Show()
    end
end

local function OnUpdate(self, elapsed)
    if not db or not db.enabled then
        SetVisible(false)
        return
    end

    local now = GetTime()

    if testMode then
        if not mhStart or now - mhStart >= (mhDur or 2.0) then
            ResetSwing("MH", mhDur or 2.0, now)
        end
        if not ohDur then
            ohDur = 2.0
        end
        if not ohStart or now - ohStart >= (ohDur or 2.0) then
            ResetSwing("OH", ohDur or 2.0, now)
        end
    else
        CheckSpeedChange(false)
    end

    UpdateBar(mhBar, mhStart, mhDur, now)

    if ohDur then
        ohBar:Show()
        UpdateBar(ohBar, ohStart, ohDur, now)
    else
        ohBar:Hide()
    end

    if title then
        if testMode then
            title:SetText("TheoSwingTimer - TEST")
        elseif inCombat then
            title:SetText("TheoSwingTimer")
        else
            title:SetText("TheoSwingTimer - OOC")
        end
    end

    SetVisible(ShouldShow())
end

local function CreateUI()
    if frame then return end

    frame = CreateFrame("Frame", "TheoSwingTimerFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture(0, 0, 0, 0.35)
    frame.bg = bg

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText("TheoSwingTimer")
    title:SetTextColor(1, 1, 1, 0.92)

    frame:SetScript("OnDragStart", function(self)
        if db and not db.locked then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    mhBar = MakeBar(frame, "TheoSwingTimerMHBar", -20, "MH")
    ohBar = MakeBar(frame, "TheoSwingTimerOHBar", -40, "OH")

    ApplyLayout()
    frame:SetScript("OnUpdate", OnUpdate)
    frame:Hide()
end

local function PrintHelp()
    Chat("commands:")
    Chat("/tsw status")
    Chat("/tsw combatonly - ON in combat, hidden out of combat")
    Chat("/tsw teston     - force visible fake bars")
    Chat("/tsw testoff    - stop fake bars")
    Chat("/tsw test       - toggle fake bars")
    Chat("/tsw center     - move bars to center for setup")
    Chat("/tsw unlock / /tsw lock")
    Chat("/tsw showooc    - toggle showing out of combat")
    Chat("/tsw scale 1.0")
    Chat("/tsw width 260")
    Chat("/tsw height 14")
    Chat("/tsw reset")
    Chat("/tsw on / /tsw off")
end

function TSW:Slash(msg)
    msg = Trim(msg or "")
    local lower = Lower(msg)

    if lower == "" or lower == "help" then
        PrintHelp()
        return
    end

    if not db then
        CopyDefaults()
        CreateUI()
        SoftStart()
    end

    if lower == "status" then
        local mh, oh = GetSpeeds()
        local cleuMode = "old-vararg"
        if CombatLogGetCurrentEventInfo then cleuMode = "new-function" end

        Chat("loaded. enabled=" .. tostring(db.enabled) ..
            " locked=" .. tostring(db.locked) ..
            " combat=" .. tostring(inCombat) ..
            " showOOC=" .. tostring(db.showOOC) ..
            " test=" .. tostring(testMode) ..
            " x=" .. tostring(db.x) ..
            " y=" .. tostring(db.y) ..
            " MH=" .. tostring(mh) ..
            " OH=" .. tostring(oh) ..
            " CLEU=" .. cleuMode ..
            " frameShown=" .. tostring(frame and frame:IsShown()))
        return
    end

    if lower == "combatonly" then
        db.enabled = true
        db.showOOC = false
        testMode = false
        SoftStart()
        SetVisible(ShouldShow())
        Chat("combat-only mode: ON. Visible in combat, hidden out of combat.")
        return
    end

    if lower == "test" then
        testMode = not testMode
        db.enabled = true
        db.showOOC = true
        SoftStart()
        SetVisible(true)
        Chat("test mode: " .. (testMode and "ON" or "OFF"))
        return
    end

    if lower == "teston" then
        testMode = true
        db.enabled = true
        db.showOOC = true
        SoftStart()
        SetVisible(true)
        Chat("test mode: ON. White bars should scroll left to right.")
        return
    end

    if lower == "testoff" then
        testMode = false
        db.showOOC = false
        SetVisible(ShouldShow())
        Chat("test mode: OFF. Combat-only visibility restored.")
        return
    end

    if lower == "center" then
        ForceCenter()
        ApplyLayout()
        db.enabled = true
        db.showOOC = true
        testMode = true
        SoftStart()
        SetVisible(true)
        Chat("centered and test mode ON. Use /tsw combatonly when done.")
        return
    end

    if lower == "unlock" then
        db.locked = false
        db.enabled = true
        db.showOOC = true
        testMode = true
        SoftStart()
        SetVisible(true)
        Chat("unlocked. Drag the panel. Use /tsw lock when done.")
        return
    end

    if lower == "lock" then
        db.locked = true
        testMode = false
        db.enabled = true
        db.showOOC = false
        SavePosition()
        SetVisible(ShouldShow())
        Chat("locked. Combat-only mode ON.")
        return
    end

    if lower == "showooc" then
        db.showOOC = not db.showOOC
        testMode = false
        SetVisible(ShouldShow())
        Chat("show out of combat: " .. (db.showOOC and "ON" or "OFF"))
        return
    end

    if lower == "debug" then
        db.debug = not db.debug
        Chat("debug: " .. (db.debug and "ON" or "OFF"))
        return
    end

    if lower == "reset" then
        db.x = defaults.x
        db.y = defaults.y
        db.scale = defaults.scale
        db.width = defaults.width
        db.height = defaults.height
        db.enabled = true
        db.showOOC = false
        testMode = false
        ApplyLayout()
        SoftStart()
        SetVisible(ShouldShow())
        Chat("reset. Combat-only mode ON.")
        return
    end

    if lower == "on" then
        db.enabled = true
        db.showOOC = false
        testMode = false
        SoftStart()
        SetVisible(ShouldShow())
        Chat("enabled. Combat-only visibility ON.")
        return
    end

    if lower == "off" then
        db.enabled = false
        SetVisible(false)
        Chat("disabled.")
        return
    end

    if string.find(lower, "^scale ") then
        local n = tonumber(string.sub(lower, 7))
        if n and n >= 0.5 and n <= 3 then
            db.scale = n
            ApplyLayout()
            SetVisible(ShouldShow())
            Chat("scale set to " .. tostring(n))
        else
            Chat("usage: /tsw scale 1.0")
        end
        return
    end

    if string.find(lower, "^width ") then
        local n = tonumber(string.sub(lower, 7))
        if n and n >= 80 and n <= 800 then
            db.width = n
            ApplyLayout()
            Chat("width set to " .. tostring(n))
        else
            Chat("usage: /tsw width 260")
        end
        return
    end

    if string.find(lower, "^height ") then
        local n = tonumber(string.sub(lower, 8))
        if n and n >= 8 and n <= 50 then
            db.height = n
            ApplyLayout()
            Chat("height set to " .. tostring(n))
        else
            Chat("usage: /tsw height 14")
        end
        return
    end

    Chat("unknown command: " .. msg)
    PrintHelp()
end

local function FindOldCombatLogOffhandFlag(...)
    -- Old 2.4.3 combat-log varargs usually put the offhand flag at/near the end.
    -- Scan backward for the last boolean. That avoids depending on one exact private-server layout.
    local n = select("#", ...)
    local i
    for i = n, 1, -1 do
        local v = select(i, ...)
        if type(v) == "boolean" then
            return v
        end
    end
    return false
end

local function HandleCombatLog(...)
    local subevent
    local sourceIsPlayer = false
    local isOffHand = false

    if CombatLogGetCurrentEventInfo then
        -- 2.5.3 / modern Classic style.
        local _, ev, _, sourceGUID = CombatLogGetCurrentEventInfo()
        subevent = ev

        if sourceGUID and playerGUID and sourceGUID == playerGUID then
            sourceIsPlayer = true
        end

        if not sourceIsPlayer then return end
        if subevent ~= "SWING_DAMAGE" and subevent ~= "SWING_MISSED" then return end

        if subevent == "SWING_DAMAGE" then
            isOffHand = select(21, CombatLogGetCurrentEventInfo())
        else
            isOffHand = select(13, CombatLogGetCurrentEventInfo())
        end
    else
        -- True 2.4.3 style: COMBAT_LOG_EVENT_UNFILTERED gives the values as ...
        -- Common layouts:
        --   timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID...
        --   timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, destGUID...
        local a3, a4, a5 = select(3, ...)
        subevent = select(2, ...)

        if subevent ~= "SWING_DAMAGE" and subevent ~= "SWING_MISSED" then return end

        if playerGUID and (a3 == playerGUID or a4 == playerGUID) then
            sourceIsPlayer = true
        elseif playerName and (a4 == playerName or a5 == playerName) then
            -- Fallback for odd/private 2.4.3 combat-log layouts.
            sourceIsPlayer = true
        end

        if not sourceIsPlayer then return end
        isOffHand = FindOldCombatLogOffhandFlag(...)
    end

    local now = GetTime()
    local mh, oh = GetSpeeds()

    if isOffHand then
        if oh and now - lastOHSwing > 0.25 then
            ResetSwing("OH", oh, now)
            if db and db.debug then Chat("OH swing reset") end
        end
    else
        if now - lastMHSwing > 0.25 then
            ResetSwing("MH", mh, now)
            if db and db.debug then Chat("MH swing reset") end
        end
    end
end

local function ResetForSpell(spellName)
    if not spellName then return end
    if spellName == "Slam" or string.find(spellName, "Slam") then
        local now = GetTime()
        local mh, oh = GetSpeeds()
        ResetSwing("MH", mh, now)
        if oh then ResetSwing("OH", oh, now) end
        if db and db.debug then Chat("Slam reset") end
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        CopyDefaults()
        if UnitGUID then playerGUID = UnitGUID("player") end
        playerName = UnitName("player")
        CreateUI()
        SoftStart()
        CheckSpeedChange(true)
        SetVisible(ShouldShow())
        Chat("loaded. Default ON, combat-only. 2.4.3/2.5.3 compatible. Type /tsw unlock to move.")
        return
    end

    if not db then return end

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        SoftStart()
        SetVisible(ShouldShow())
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        SetVisible(ShouldShow())
        return
    end

    if event == "UNIT_ATTACK_SPEED" then
        local unit = ...
        if unit == "player" then CheckSpeedChange(true) end
        return
    end

    if event == "PLAYER_EQUIPMENT_CHANGED" then
        CheckSpeedChange(true)
        SoftStart()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog(...)
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, arg2, arg3 = ...
        if unit == "player" then
            local spellName

            -- 2.5.3-style: unit, castGUID, spellID
            if arg3 and type(arg3) == "number" and GetSpellInfo then
                spellName = GetSpellInfo(arg3)
            end

            -- 2.4.3-style: unit, spellName, rank
            if not spellName and arg2 and type(arg2) == "string" then
                spellName = arg2
            end

            ResetForSpell(spellName)
        end
        return
    end
end)

SafeRegister("PLAYER_LOGIN")
SafeRegister("PLAYER_ENTERING_WORLD")
SafeRegister("PLAYER_REGEN_DISABLED")
SafeRegister("PLAYER_REGEN_ENABLED")
SafeRegister("UNIT_ATTACK_SPEED")
SafeRegister("PLAYER_EQUIPMENT_CHANGED")
SafeRegister("COMBAT_LOG_EVENT_UNFILTERED")
SafeRegister("UNIT_SPELLCAST_SUCCEEDED")
