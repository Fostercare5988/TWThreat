-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.15.15+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11515
local superVersion = tonumber(SUPERWOW_VERSION)
if type(CLASSIC_API_VERSION) ~= "number" or CLASSIC_API_VERSION < MIN_CLASSIC_API
        or not superVersion or superVersion < 2.2 or not C_Timer or not C_Timer.NewTicker then
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[TWThreat Fatal Error]|r TWThreat requires ClassicAPI (v1.15.15+) & SuperWoW (v2.2+)! Please ensure both DLLs are loaded.", 1, 0.2, 0.2)
    end
    return
end

local _G = _G or getfenv()

-- Fast local cache for performance-critical standard functions
local __lower = string.lower
local __repeat = string.rep
local __strlen = string.len
local __find = string.find
local __substr = string.sub
local __parseint = tonumber
local __parsestring = tostring
local table_wipe = table.wipe
local __tinsert = table.insert
local __tremove = table.remove
local __tsort = table.sort
local __pairs = pairs
local __next = next
local __floor = math.floor
local __abs = math.abs
local __min = math.min
local __max = math.max

local TWT = CreateFrame("Frame", "TWThreatCore")

-- Pre-allocated static Unit ID arrays (Part D2)
local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end

TWT.addonVer = '1.4.0'
TWT.addonName = 'TWThreat'

-- Threat Server Protocol Constants
TWT.threatApi = 'TWTv4='
TWT.tankModeApi = 'TMTv1='
TWT.UDTS = 'TWT_UDTSv4'

TWT.prefix = 'TWT'
TWT.channel = 'RAID'

TWT.name = UnitName('player') or ''
local _, cl = UnitClass('player')
TWT.class = cl and __lower(cl) or 'warrior'

TWT.lastAggroWarningSoundTime = 0
TWT.lastAggroWarningGlowTime = 0

TWT.AGRO = '-Pull Aggro at-'
TWT.threatsFrames = {}

-- Threat data tables & zero-GC recycling pools
TWT.threats = {}
TWT.threatPool = {}

TWT.tankModeThreats = {}
TWT.tankModePool = {}

-- Sort buffer (pre-allocated 40 slots to avoid combat GC churn)
TWT.sortList = {}
for i = 1, 40 do
    TWT.sortList[i] = { name = '', threat = 0, perc = 0, tps = 0, class = 'priest', tank = false, melee = false }
end
TWT.sortCount = 0

TWT.targetName = ''
TWT.relayTo = {}
TWT.shouldRelay = false
TWT.healerMasterTarget = ''

TWT.updateSpeed = 1
TWT.targetFrameVisible = false

TWT.nameLimit = 30
TWT.windowStartWidth = 300
TWT.windowWidth = 300
TWT.minBars = 5
TWT.maxBars = 11

TWT.roles = {}
TWT.spec = {}
TWT.classes = {}
TWT.history = {}

TWT.withAddon = 0
TWT.addonStatus = {}

TWT.classColors = {
    ["warrior"] = { r = 0.78, g = 0.61, b = 0.43, c = "|cffc79c6e" },
    ["mage"]    = { r = 0.41, g = 0.80, b = 0.94, c = "|cff69ccf0" },
    ["rogue"]   = { r = 1.00, g = 0.96, b = 0.41, c = "|cfffff569" },
    ["druid"]   = { r = 1.00, g = 0.49, b = 0.04, c = "|cffff7d0a" },
    ["hunter"]  = { r = 0.67, g = 0.83, b = 0.45, c = "|cffabd473" },
    ["shaman"]  = { r = 0.14, g = 0.35, b = 1.00, c = "|cff0070de" },
    ["priest"]  = { r = 1.00, g = 1.00, b = 1.00, c = "|cffffffff" },
    ["warlock"] = { r = 0.58, g = 0.51, b = 0.79, c = "|cff9482c9" },
    ["paladin"] = { r = 0.96, g = 0.55, b = 0.73, c = "|cfff58cba" },
    ["agro"]    = { r = 0.96, g = 0.10, b = 0.10, c = "|cffff1111" }
}

TWT.classCoords = {
    ["priest"]  = { 0.52, 0.73, 0.27, 0.48 },
    ["mage"]    = { 0.23, 0.48, 0.02, 0.23 },
    ["warlock"] = { 0.77, 0.98, 0.27, 0.48 },
    ["rogue"]   = { 0.48, 0.73, 0.02, 0.23 },
    ["druid"]   = { 0.77, 0.98, 0.02, 0.23 },
    ["hunter"]  = { 0.02, 0.23, 0.27, 0.48 },
    ["shaman"]  = { 0.27, 0.48, 0.27, 0.48 },
    ["warrior"] = { 0.02, 0.23, 0.02, 0.23 },
    ["paladin"] = { 0.02, 0.23, 0.52, 0.73 },
}

TWT.fonts = {
    'BalooBhaina', 'BigNoodleTitling',
    'Expressway', 'Homespun', 'Hooge', 'LondrinaSolid',
    'Myriad-Pro', 'PT-Sans-Narrow-Bold', 'PT-Sans-Narrow-Regular',
    'Roboto', 'Share', 'ShareBold',
    'Sniglet', 'SquadaOne',
}

TWT.updateSpeeds = {
    ['warrior'] = { 0.7, 0.5, 0.5 },
    ['paladin'] = { 1.0, 0.5, 0.7 },
    ['hunter']  = { 0.7, 0.7, 0.7 },
    ['rogue']   = { 0.5, 0.5, 0.5 },
    ['priest']  = { 1.0, 1.0, 0.6 },
    ['shaman']  = { 0.7, 0.5, 1.0 },
    ['mage']    = { 1.0, 0.5, 0.7 },
    ['warlock'] = { 0.8, 1.0, 0.6 },
    ['druid']   = { 0.8, 0.5, 1.0 },
}

function twtprint(a)
    if a == nil then
        DEFAULT_CHAT_FRAME:AddMessage('[TWT]|cff0070de:' .. GetTime() .. '|cffffffff attempt to print a nil value.')
        return false
    end
    DEFAULT_CHAT_FRAME:AddMessage((TWT.classColors[TWT.class] and TWT.classColors[TWT.class].c or "|cffffffff") .. "[TWT] |cffffffff" .. a)
end

function twtdebug(a)
    if not (TWT_CONFIG and TWT_CONFIG.debug) then
        return false
    end
    local timeStr = __parsestring(GetTime())
    if a == nil then
        twtprint('|cff0070de[TWTDEBUG:' .. timeStr .. ']|cffffffff attempt to print a nil value.')
        return
    end
    if type(a) == 'boolean' then
        twtprint('|cff0070de[TWTDEBUG:' .. timeStr .. ']|cffffffff[' .. (a and 'true' or 'false') .. ']')
        return true
    end
    twtprint('|cff0070de[D:' .. timeStr .. ']|cffffffff[' .. __parsestring(a) .. ']')
end

-- Slash Commands
SLASH_TWT1 = "/twt"
SlashCmdList["TWT"] = function(cmd)
    if cmd then
        if __substr(cmd, 1, 4) == 'show' then
            _G['TWTMain']:Show()
            TWT_CONFIG.visible = true
            return true
        end
        if __substr(cmd, 1, 8) == 'tankmode' then
            if TWT_CONFIG.tankMode then
                twtprint('Tank Mode is already enabled.')
                return false
            else
                TWT_CONFIG.tankMode = true
                twtprint('Tank Mode enabled.')
            end
            return true
        end
        if __substr(cmd, 1, 6) == 'skeram' then
            if TWT_CONFIG.skeram then
                TWT_CONFIG.skeram = false
                twtprint('Skeram module disabled.')
                return true
            end
            TWT_CONFIG.skeram = true
            twtprint('Skeram module enabled.')
            return true
        end
        if __substr(cmd, 1, 5) == 'debug' then
            if TWT_CONFIG.debug then
                TWT_CONFIG.debug = false
                if _G['pps'] then _G['pps']:Hide() end
                twtprint('Debugging disabled')
                return true
            end
            TWT_CONFIG.debug = true
            if _G['pps'] then _G['pps']:Show() end
            twtdebug('Debugging enabled')
            return true
        end
        if __substr(cmd, 1, 3) == 'who' then
            TWT.queryWho()
            return true
        end

        twtprint(TWT.addonName .. ' |cffabd473v' .. TWT.addonVer .. '|cffffffff available commands:')
        twtprint('/twt show - shows the main window (also /twtshow)')
        twtprint('/twt tankmode - toggles tank companion window')
    end
end

SLASH_TWTSHOW1 = "/twtshow"
SlashCmdList["TWTSHOW"] = function(cmd)
    _G['TWTMain']:Show()
    TWT_CONFIG.visible = true
end

SLASH_TWTDEBUG1 = "/twtdebug"
SlashCmdList["TWTDEBUG"] = function(cmd)
    if TWT_CONFIG.debug then
        TWT_CONFIG.debug = false
        twtprint('Debugging disabled')
        return true
    end
    TWT_CONFIG.debug = true
    twtdebug('Debugging enabled')
    return true
end

-- Event Registration
TWT:RegisterEvent("ADDON_LOADED")
TWT:RegisterEvent("VARIABLES_LOADED")
TWT:RegisterEvent("CHAT_MSG_ADDON")
TWT:RegisterEvent("PLAYER_REGEN_DISABLED")
TWT:RegisterEvent("PLAYER_REGEN_ENABLED")
TWT:RegisterEvent("PLAYER_TARGET_CHANGED")
TWT:RegisterEvent("PLAYER_ENTERING_WORLD")
TWT:RegisterEvent("PARTY_MEMBERS_CHANGED")
TWT:RegisterEvent("RAID_ROSTER_UPDATE")

TWT.threatQuery = CreateFrame("Frame", "TWTThreatQueryFrame")
TWT.threatQuery:Hide()

local timeStart = GetTime()
local totalPackets = 0
local totalData = 0
local uiUpdates = 0

TWT:SetScript("OnEvent", function()
    if not event then return end

    if event == 'ADDON_LOADED' and arg1 == 'TWThreat' then
        return TWT.init()
    end
    if event == 'VARIABLES_LOADED' then
        return TWT.init()
    end
    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        return TWT.getClasses()
    end
    if event == "PLAYER_ENTERING_WORLD" then
        TWT.combatEnd()
        if UnitAffectingCombat('player') then
            TWT.combatStart()
        end
        return true
    end
    if event == 'CHAT_MSG_ADDON' and arg2 and __find(arg2, TWT.threatApi, 1, true) then
        totalPackets = totalPackets + 1
        totalData = totalData + __strlen(arg2)

        local threatData = arg2
        local hashPos = __find(threatData, '#', 1, true)
        if hashPos and __find(threatData, TWT.tankModeApi, hashPos + 1, true) then
            local mainThreat = __substr(threatData, 1, hashPos - 1)
            local tankPacket = __substr(threatData, hashPos + 1)
            TWT.handleTankModePacket(tankPacket)
            threatData = mainThreat
        end

        return TWT.handleThreatPacket(threatData)
    end
    if event == 'CHAT_MSG_ADDON' and arg1 == TWT.prefix and arg2 then
        if __substr(arg2, 1, 11) == 'TWTVersion:' then
            return true
        end

        if __substr(arg2, 1, 7) == 'TWT_WHO' then
            TWT.send('TWT_ME:' .. TWT.addonVer)
            return true
        end

        if __substr(arg2, 1, 15) == 'TWTRoleTexture:' then
            local pPos = __find(arg2, ':', 1, true)
            local tex = pPos and __substr(arg2, pPos + 1) or ''
            if arg4 then
                TWT.roles[arg4] = tex
            end
            return true
        end

        if __substr(arg2, 1, 7) == 'TWT_ME:' and arg4 then
            if TWT.addonStatus[arg4] then
                local pPos = __find(arg2, ':', 1, true)
                local msg = pPos and __substr(arg2, pPos + 1) or ''
                local verColor = TWT.classColors['hunter'].c
                if TWT.version(msg) < TWT.version(TWT.addonVer) then
                    verColor = '|cffff1111'
                end
                TWT.addonStatus[arg4]['v'] = '    ' .. verColor .. msg
                TWT.withAddon = TWT.withAddon + 1
                TWT.updateWithAddon()
                return true
            end
            return false
        end

        return false
    end
    if event == "PLAYER_REGEN_DISABLED" then
        return TWT.combatStart()
    end
    if event == "PLAYER_REGEN_ENABLED" then
        return TWT.combatEnd()
    end
    if event == "PLAYER_TARGET_CHANGED" then
        if not TWT.targetChanged() then
            TWT.hideThreatFrames(true)
        end
        return true
    end
end)

function QueryWho_OnClick()
    TWT.queryWho()
end

function TWT.queryWho()
    TWT.withAddon = 0
    table_wipe(TWT.addonStatus)
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local n, _, _, _, _, _, z = GetRaidRosterInfo(i)
            if n then
                local _, class = UnitClass('raid' .. i)
                TWT.addonStatus[n] = {
                    ['class'] = class and __lower(class) or 'priest',
                    ['v'] = (z == 'Offline') and '|cffff0000offline' or '|cff888888   -   '
                }
            end
        end
    end
    twtprint('Sending who query...')
    _G['TWTWithAddonList']:Show()
    TWT.send('TWT_WHO')
end

function TWT.updateWithAddon()
    local rosterList = ''
    local i = 0
    for n, data in __pairs(TWT.addonStatus) do
        i = i + 1
        local clsColor = TWT.classColors[data['class']] and TWT.classColors[data['class']].c or '|cffffffff'
        rosterList = rosterList .. clsColor .. n .. __repeat(' ', __max(0, 12 - __strlen(n))) .. ' ' .. data['v'] .. ' |cff888888'
        if i < 4 then
            rosterList = rosterList .. '| '
        else
            rosterList = rosterList .. '\n'
            i = 0
        end
    end
    _G['TWTWithAddonListText']:SetText(rosterList)
    _G['TWTWithAddonListTitle']:SetText('Addon Raid Status ' .. TWT.withAddon .. '/' .. GetNumRaidMembers())
end

-- Full Screen Glow Fader Frame (Delta-Time Normalized)
TWT.glowFader = CreateFrame('Frame', "TWTGlowFaderFrame")
TWT.glowFader:Hide()
TWT.glowFader.elapsed = 0
TWT.glowFader.dir = 1

TWT.glowFader:SetScript("OnShow", function()
    this.elapsed = 0
    this.dir = 1
    local glow = _G['TWTFullScreenGlow']
    if glow then
        glow:SetAlpha(0.01)
        glow:Show()
    end
end)

TWT.glowFader:SetScript("OnUpdate", function()
    local dt = arg1 or 0.016
    if dt > 0.1 then dt = 0.1 end

    local glow = _G['TWTFullScreenGlow']
    if not glow then return end

    local alpha = glow:GetAlpha()
    if alpha >= 0.6 then
        this.dir = -1
    end

    local newAlpha = alpha + (this.dir * 1.5 * dt)
    if newAlpha <= 0 then
        glow:SetAlpha(0)
        glow:Hide()
        this:Hide()
    else
        glow:SetAlpha(newAlpha)
    end
end)

-- Object Recycling & Memory Pools
function TWT.releaseThreats()
    for name, entry in __pairs(TWT.threats) do
        TWT.threats[name] = nil
        TWT.threatPool[#TWT.threatPool + 1] = entry
    end
end

function TWT.getThreatEntry(name)
    local entry = TWT.threats[name]
    if not entry then
        entry = __tremove(TWT.threatPool)
        if not entry then
            entry = { threat = 0, tank = false, perc = 0, melee = false, tps = 0, class = 'priest' }
        end
        TWT.threats[name] = entry
    end
    return entry
end

function TWT.releaseTankModeThreats()
    for guid, entry in __pairs(TWT.tankModeThreats) do
        TWT.tankModeThreats[guid] = nil
        TWT.tankModePool[#TWT.tankModePool + 1] = entry
    end
end

function TWT.getTankModeEntry(guid)
    local entry = TWT.tankModeThreats[guid]
    if not entry then
        entry = __tremove(TWT.tankModePool)
        if not entry then
            entry = { creature = '', name = '', perc = 0 }
        end
        TWT.tankModeThreats[guid] = entry
    end
    return entry
end

function TWT.init()
    if TWT.initialized then return end
    TWT.initialized = true

    if not TWT_CONFIG then
        TWT_CONFIG = {
            visible = true,
            colTPS = true,
            colThreat = true,
            colPerc = true,
            labelRow = true,
        }
    end

    TWT_CONFIG.windowScale = TWT_CONFIG.windowScale or 1
    TWT_CONFIG.glow = TWT_CONFIG.glow or false
    TWT_CONFIG.perc = TWT_CONFIG.perc or false
    TWT_CONFIG.showInCombat = TWT_CONFIG.showInCombat or false
    TWT_CONFIG.hideOOC = TWT_CONFIG.hideOOC or false
    TWT_CONFIG.font = TWT_CONFIG.font or 'Roboto'
    TWT_CONFIG.barHeight = TWT_CONFIG.barHeight or 20
    TWT_CONFIG.visibleBars = TWT_CONFIG.visibleBars or TWT.minBars
    TWT_CONFIG.fullScreenGlow = TWT_CONFIG.fullScreenGlow or false
    TWT_CONFIG.aggroSound = TWT_CONFIG.aggroSound or false
    TWT_CONFIG.aggroThreshold = TWT_CONFIG.aggroThreshold or 85
    TWT_CONFIG.tankMode = TWT_CONFIG.tankMode or false
    TWT_CONFIG.tankModeStick = TWT_CONFIG.tankModeStick or 'Free'
    TWT_CONFIG.lock = TWT_CONFIG.lock or false
    TWT_CONFIG.visible = TWT_CONFIG.visible or false
    TWT_CONFIG.colTPS = TWT_CONFIG.colTPS or false
    TWT_CONFIG.colThreat = TWT_CONFIG.colThreat or false
    TWT_CONFIG.colPerc = TWT_CONFIG.colPerc or false
    TWT_CONFIG.labelRow = TWT_CONFIG.labelRow or false
    TWT_CONFIG.skeram = TWT_CONFIG.skeram or false

    -- Clean stale keys from saved variables
    TWT_CONFIG.glowPFUI = nil
    TWT_CONFIG.percPFUI = nil
    TWT_CONFIG.percPFUItop = nil
    TWT_CONFIG.percPFUIbottom = nil

    TWT_CONFIG.combatAlpha = TWT_CONFIG.combatAlpha or 1
    TWT_CONFIG.oocAlpha = TWT_CONFIG.oocAlpha or 1

    if TWT.class ~= 'paladin' and TWT.class ~= 'warrior' and TWT.class ~= 'druid' then
        _G['TWTMainSettingsTankMode']:Disable()
        TWT_CONFIG.tankMode = false
    end

    TWT_CONFIG.debug = TWT_CONFIG.debug or false

    if TWT_CONFIG.visible then
        _G['TWTMain']:Show()
    else
        _G['TWTMain']:Hide()
    end

    if TWT_CONFIG.tankMode then
        _G['TWTMainSettingsFullScreenGlow']:SetChecked(TWT_CONFIG.fullScreenGlow)
        _G['TWTMainSettingsFullScreenGlow']:Disable()
        _G['TWTMainSettingsAggroSound']:SetChecked(TWT_CONFIG.fullScreenGlow)
        _G['TWTMainSettingsAggroSound']:Disable()
    end

    if TWT_CONFIG.lock then
        _G['TWTMainLockButton']:SetNormalTexture('Interface\\addons\\TWThreat\\images\\icon_locked')
    else
        _G['TWTMainLockButton']:SetNormalTexture('Interface\\addons\\TWThreat\\images\\icon_unlocked')
    end

    _G['TWTFullScreenGlowTexture']:SetWidth(GetScreenWidth())
    _G['TWTFullScreenGlowTexture']:SetHeight(GetScreenHeight())

    _G['TWTMain']:SetHeight(TWT_CONFIG.barHeight * TWT_CONFIG.visibleBars + (TWT_CONFIG.labelRow and 40 or 20))

    _G['TWTMainSettingsFrameHeightSlider']:SetValue(TWT_CONFIG.barHeight)
    _G['TWTMainSettingsWindowScaleSlider']:SetValue(TWT_CONFIG.windowScale)
    _G['TWTMainSettingsCombatAlphaSlider']:SetValue(TWT_CONFIG.combatAlpha)
    _G['TWTMainSettingsOOCAlphaSlider']:SetValue(TWT_CONFIG.oocAlpha)
    _G['TWTMainSettingsAggroThresholdSlider']:SetValue(TWT_CONFIG.aggroThreshold)

    _G['TWTMainSettingsFontButton']:SetText(TWT_CONFIG.font)

    _G['TWTMainSettingsTargetFrameGlow']:SetChecked(TWT_CONFIG.glow)
    _G['TWTMainSettingsPercNumbers']:SetChecked(TWT_CONFIG.perc)
    _G['TWTMainSettingsShowInCombat']:SetChecked(TWT_CONFIG.showInCombat)
    _G['TWTMainSettingsHideOOC']:SetChecked(TWT_CONFIG.hideOOC)
    _G['TWTMainSettingsFullScreenGlow']:SetChecked(TWT_CONFIG.fullScreenGlow)
    _G['TWTMainSettingsAggroSound']:SetChecked(TWT_CONFIG.aggroSound)
    _G['TWTMainSettingsTankMode']:SetChecked(TWT_CONFIG.tankMode)

    _G['TWTMainSettingsColumnsTPS']:SetChecked(TWT_CONFIG.colTPS)
    _G['TWTMainSettingsColumnsThreat']:SetChecked(TWT_CONFIG.colThreat)
    _G['TWTMainSettingsColumnsPercent']:SetChecked(TWT_CONFIG.colPerc)
    _G['TWTMainSettingsLabelRow']:SetChecked(TWT_CONFIG.labelRow)

    TWT.setColumnLabels()

    if TWT_CONFIG.labelRow then
        _G['TWTMainBarsBG']:SetPoint('TOPLEFT', 1, -40)
        _G['TWTMainNameLabel']:Show()
    else
        _G['TWTMainBarsBG']:SetPoint('TOPLEFT', 1, -20)
        _G['TWTMainNameLabel']:Hide()
        _G['TWTMainTPSLabel']:Hide()
        _G['TWTMainThreatLabel']:Hide()
        _G['TWTMainPercLabel']:Hide()
    end

    _G['TWTMainSettingsFontButtonNT']:SetVertexColor(0.4, 0.4, 0.4)

    local color = TWT.classColors[TWT.class] or TWT.classColors['warrior']
    _G['TWTMainTitleBG']:SetVertexColor(color.r, color.g, color.b)
    _G['TWTMainSettingsTitleBG']:SetVertexColor(color.r, color.g, color.b)
    _G['TWTMainTankModeWindowTitleBG']:SetVertexColor(color.r, color.g, color.b)

    _G['TWThreatDisplayTarget']:SetScale(UIParent:GetScale())

    -- Dynamic Font Frame Generation
    local fontFrames = {}
    for i, font in TWT.fonts do
        fontFrames[i] = CreateFrame('Button', 'Font_' .. font, _G['TWTMainSettingsFontList'], 'TWTFontFrameTemplate')
        fontFrames[i]:SetPoint("TOPLEFT", _G["TWTMainSettingsFontList"], "TOPLEFT", 0, 17 - i * 17)
        _G['Font_' .. font]:SetID(i)
        _G['Font_' .. font .. 'Name']:SetFont("Interface\\addons\\TWThreat\\fonts\\" .. font .. ".ttf", 15)
        _G['Font_' .. font .. 'Name']:SetText(font)
        _G['Font_' .. font .. 'HT']:SetVertexColor(1, 1, 1, 0.5)
        fontFrames[i]:Show()
    end

    TWT.updateTitleBarText()
    TWT.updateSettingsTabs(1)
    TWT.checkTargetFrames()

    twtprint(TWT.addonName .. ' |cffabd473v' .. TWT.addonVer .. '|cffffffff loaded.')
    return true
end

function TWT.updateSettingsTabs(tab)
    local color = TWT.classColors[TWT.class] or TWT.classColors['warrior']
    _G['TWTMainSettingsTabsUnderline']:SetVertexColor(color.r, color.g, color.b)

    for i = 1, 3 do
        _G['TWTMainSettingsTab' .. i]:Hide()
        _G['TWTMainSettingsTab' .. i .. 'ButtonNT']:SetVertexColor(color.r, color.g, color.b, 0.4)
        _G['TWTMainSettingsTab' .. i .. 'ButtonHT']:SetVertexColor(color.r, color.g, color.b, 0.4)
        _G['TWTMainSettingsTab' .. i .. 'ButtonPT']:SetVertexColor(color.r, color.g, color.b, 0.4)
        _G['TWTMainSettingsTab' .. i .. 'ButtonText']:SetTextColor(0.4, 0.4, 0.4)
    end

    _G['TWTMainSettingsTab' .. tab .. 'ButtonNT']:SetVertexColor(color.r, color.g, color.b, 1)
    _G['TWTMainSettingsTab' .. tab .. 'ButtonText']:SetTextColor(1, 1, 1)
    _G['TWTMainSettingsTab' .. tab]:Show()
end

function TWTSettingsTab_OnClick(tab)
    TWT.updateSettingsTabs(tab)
end

function TWTHealerMasterTarget_OnClick()
    TWT.getClasses()

    if not UnitExists('target') or not UnitIsPlayer('target') or UnitName('target') == TWT.name then
        if TWT.healerMasterTarget == '' then
            twtprint('Please target a tank.')
        else
            TWT.removeHealerMasterTarget()
        end
        return false
    end

    local targetName = UnitName('target')
    if targetName == TWT.healerMasterTarget then
        return TWT.removeHealerMasterTarget()
    end

    TWT.send('TWT_HMT:' .. targetName)
    local color = TWT.classColors[TWT.getClass(targetName)] or TWT.classColors['priest']
    twtprint('Trying to set Healer Master Target to ' .. color.c .. targetName)
end

function TWT.removeHealerMasterTarget()
    if TWT.healerMasterTarget ~= '' then
        TWT.send('TWT_HMT_REM:' .. TWT.healerMasterTarget)
    end
    twtprint('Healer Master Target cleared.')
    TWT.healerMasterTarget = ''
    TWT.targetName = ''
    TWT.releaseThreats()

    _G['TWTMainSettingsHealerMasterTargetButton']:SetText('From Target')
    _G['TWTMainSettingsHealerMasterTargetButtonNT']:SetVertexColor(1, 1, 1, 1)
    TWT.updateUI('removeHealerMasterTarget')
    return true
end

function TWT.getClass(name)
    return TWT.classes[name] or 'priest'
end

function TWT.getClasses()
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local unit = RAID_UNITS[i]
            if unit then
                local name = UnitName(unit)
                if name then
                    local _, raidCls = UnitClass(unit)
                    if raidCls then
                        TWT.classes[name] = __lower(raidCls)
                    end
                end
            end
        end
    else
        local numParty = GetNumPartyMembers()
        if numParty > 0 then
            for i = 1, numParty do
                local unit = PARTY_UNITS[i]
                if unit then
                    local name = UnitName(unit)
                    if name then
                        local _, partyCls = UnitClass(unit)
                        if partyCls then
                            TWT.classes[name] = __lower(partyCls)
                        end
                    end
                end
            end
        end
    end
    if TWT.name and TWT.class then
        TWT.classes[TWT.name] = TWT.class
    end
    return true
end

TWT.tankName = ''

-- Fast Zero-Allocation Threat Entry Parser
local function parseThreatItem(itemStr)
    local p1 = __find(itemStr, ':', 1, true)
    if not p1 then return end
    local p2 = __find(itemStr, ':', p1 + 1, true)
    if not p2 then return end
    local p3 = __find(itemStr, ':', p2 + 1, true)
    if not p3 then return end
    local p4 = __find(itemStr, ':', p3 + 1, true)
    if not p4 then return end

    local name = __substr(itemStr, 1, p1 - 1)
    local tank = __substr(itemStr, p1 + 1, p2 - 1) == '1'
    local threat = __parseint(__substr(itemStr, p2 + 1, p3 - 1)) or 0
    local perc = __parseint(__substr(itemStr, p3 + 1, p4 - 1)) or 0
    local melee = __substr(itemStr, p4 + 1) == '1'

    return name, tank, threat, perc, melee
end

function TWT.handleThreatPacket(packet)
    local apiPos = __find(packet, TWT.threatApi, 1, true)
    if not apiPos then return end

    local playersString = __substr(packet, apiPos + __strlen(TWT.threatApi))
    TWT.releaseThreats()
    TWT.tankName = ''

    local curTime = time()
    local startPos = 1
    local totalLen = __strlen(playersString)

    while startPos <= totalLen do
        local semiPos = __find(playersString, ';', startPos, true) or (totalLen + 1)
        local itemStr = __substr(playersString, startPos, semiPos - 1)

        if __strlen(itemStr) > 0 then
            local player, tank, threat, perc, melee = parseThreatItem(itemStr)
            if player then
                if not TWT.history[player] then
                    TWT.history[player] = {}
                end
                TWT.history[player][curTime] = threat

                local entry = TWT.getThreatEntry(player)
                entry.threat = threat
                entry.tank = tank
                entry.perc = perc
                entry.melee = melee
                entry.tps = TWT.calcTPS(player)
                entry.class = TWT.getClass(player)

                if tank then
                    TWT.tankName = player
                end
            end
        end
        startPos = semiPos + 1
    end

    TWT.calcAGROPerc()
    TWT.updateUI()
end

-- Fast Zero-Allocation Tank Mode Packet Parser
local function parseTankModeItem(itemStr)
    local p1 = __find(itemStr, ':', 1, true)
    if not p1 then return end
    local p2 = __find(itemStr, ':', p1 + 1, true)
    if not p2 then return end
    local p3 = __find(itemStr, ':', p2 + 1, true)
    if not p3 then return end

    local creature = __substr(itemStr, 1, p1 - 1)
    local guid = __substr(itemStr, p1 + 1, p2 - 1)
    local name = __substr(itemStr, p2 + 1, p3 - 1)
    local perc = __parseint(__substr(itemStr, p3 + 1)) or 0

    return creature, guid, name, perc
end

function TWT.handleTankModePacket(packet)
    local apiPos = __find(packet, TWT.tankModeApi, 1, true)
    if not apiPos then return end

    local playersString = __substr(packet, apiPos + __strlen(TWT.tankModeApi))
    TWT.releaseTankModeThreats()

    local startPos = 1
    local totalLen = __strlen(playersString)

    while startPos <= totalLen do
        local semiPos = __find(playersString, ';', startPos, true) or (totalLen + 1)
        local itemStr = __substr(playersString, startPos, semiPos - 1)

        if __strlen(itemStr) > 0 then
            local creature, guid, name, perc = parseTankModeItem(itemStr)
            if creature and guid then
                local entry = TWT.getTankModeEntry(guid)
                entry.creature = creature
                entry.name = name
                entry.perc = perc
            end
        end
        startPos = semiPos + 1
    end
end

function TWT.calcAGROPerc()
    local tankThreat = 0
    for _, data in __pairs(TWT.threats) do
        if data.tank then
            tankThreat = data.threat
            break
        end
    end

    local agroEntry = TWT.getThreatEntry(TWT.AGRO)
    agroEntry.class = 'agro'
    agroEntry.threat = 0
    agroEntry.perc = 100
    agroEntry.tps = ''
    agroEntry.tank = false
    agroEntry.melee = false

    local playerEntry = TWT.threats[TWT.name]
    if not playerEntry then
        return false
    end

    local multiplier = playerEntry.melee and 1.1 or 1.3
    agroEntry.threat = tankThreat * multiplier
    if agroEntry.threat == 0 then
        agroEntry.threat = 1
    end
    agroEntry.perc = playerEntry.melee and 110 or 130
end

function TWT.combatStart()
    TWT.updateTargetFrameThreatIndicators(-1, '')
    timeStart = GetTime()
    totalPackets = 0
    totalData = 0

    TWT.hideThreatFrames(true)
    TWT.shouldRelay = TWT.checkRelay()

    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then
        return false
    end

    if TWT_CONFIG.showInCombat then
        _G['TWTMain']:Show()
    end

    table_wipe(TWT.spec)
    for t = 1, GetNumTalentTabs() do
        TWT.spec[t] = { talents = 0, texture = '' }
        for i = 1, GetNumTalents(t) do
            local _, _, _, _, currRank = GetTalentInfo(t, i)
            TWT.spec[t].talents = TWT.spec[t].talents + (currRank or 0)
        end
    end

    local specIndex = 1
    for i = 2, 4 do
        local name, texture = GetSpellTabInfo(i)
        if name and texture then
            TWT.spec[specIndex].name = name
            local lastSlash = 1
            while true do
                local found = __find(texture, '\\', lastSlash, true)
                if not found then break end
                lastSlash = found + 1
            end
            TWT.spec[specIndex].texture = __substr(texture, lastSlash)
            specIndex = specIndex + 1
        end
    end

    local sendTex = TWT.spec[1] and TWT.spec[1].texture or ''
    TWT.updateSpeed = (TWT.updateSpeeds[TWT.class] and TWT.updateSpeeds[TWT.class][1]) or 0.7

    if TWT.spec[2] and TWT.spec[1] and TWT.spec[3] then
        if TWT.spec[2].talents > TWT.spec[1].talents and TWT.spec[2].talents > TWT.spec[3].talents then
            sendTex = TWT.spec[2].texture
            TWT.updateSpeed = (TWT.updateSpeeds[TWT.class] and TWT.updateSpeeds[TWT.class][2]) or 0.5
        elseif TWT.spec[3].talents > TWT.spec[1].talents and TWT.spec[3].talents > TWT.spec[2].talents then
            sendTex = TWT.spec[3].texture
            TWT.updateSpeed = (TWT.updateSpeeds[TWT.class] and TWT.updateSpeeds[TWT.class][3]) or 0.5
        end
    end

    if TWT.class == 'warrior' and __lower(sendTex) == 'ability_rogue_eviscerate' then
        sendTex = 'ability_warrior_savageblow'
    end

    if sendTex and sendTex ~= '' then
        TWT.send('TWTRoleTexture:' .. sendTex)
    end

    TWT.getClasses()
    TWT.updateUI('combatStart')

    TWT.threatQuery:Show()

    TWTTankModeWindowChangeStick_OnClick()
    _G['TWTMain']:SetAlpha(TWT_CONFIG.combatAlpha)

    return true
end

function TWT.combatEnd()
    TWT.updateTargetFrameThreatIndicators(-1, '')

    timeStart = GetTime()
    totalPackets = 0
    totalData = 0

    TWT.releaseThreats()
    TWT.releaseTankModeThreats()
    table.wipe(TWT.history)

    if TWT_CONFIG.hideOOC then
        _G['TWTMain']:Hide()
    end

    TWT.updateUI('combatEnd')
    TWT.threatQuery:Hide()
    TWT.barAnimator:Hide()

    if TWT_CONFIG.tankMode then
        _G['TWTMainTankModeWindow']:Hide()
    end

    _G['TWTWarning']:Hide()
    TWT.updateTitleBarText()
    _G['TWTMain']:SetAlpha(TWT_CONFIG.oocAlpha)
    TWT.hideThreatFrames(true)

    return true
end

function TWT.checkRelay()
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    if numRaid == 0 and numParty == 0 then
        return false
    end
    if #TWT.relayTo == 0 then
        return false
    end

    if TWT.channel == 'RAID' and numRaid > 0 then
        for index, name in __pairs(TWT.relayTo) do
            local found = false
            for i = 1, numRaid do
                if UnitName('raid' .. i) == name then
                    found = true
                    break
                end
            end
            if not found then
                TWT.relayTo[index] = nil
            end
        end
    elseif TWT.channel == 'PARTY' and numParty > 0 then
        for index, name in __pairs(TWT.relayTo) do
            local found = false
            for i = 1, numParty do
                if UnitName('party' .. i) == name then
                    found = true
                    break
                end
            end
            if not found then
                TWT.relayTo[index] = nil
            end
        end
    end

    return (#TWT.relayTo > 0)
end

function TWT.checkTargetFrames()
    local tf
    if FostercareTweaks and FostercareTweaks.GetActiveTargetFrame then
        tf = FostercareTweaks.GetActiveTargetFrame()
    else
        tf = _G['TargetFrame']
    end
    local indicator = _G['TWThreatDisplayTarget']
    if tf and indicator and TWT.targetIndicatorAnchor ~= tf then
        indicator:ClearAllPoints()
        indicator:SetPoint('TOPLEFT', tf, 'TOPLEFT', 1, 0)
        TWT.targetIndicatorAnchor = tf
    end
    TWT.targetFrameVisible = (tf and tf:IsVisible() ~= nil)
end

function TWT.hideThreatFrames(force)
    if TWT.tableSize(TWT.threats) > 0 or force then
        for name, frame in __pairs(TWT.threatsFrames) do
            frame:Hide()
        end
    end
end

function TWT.targetChanged()
    if not UnitAffectingCombat('player') and _G['TWTMainSettings']:IsVisible() == 1 then
        return true
    end

    TWT.channel = (GetNumRaidMembers() > 0) and 'RAID' or 'PARTY'

    if UIParent:GetScale() ~= _G['TWThreatDisplayTarget']:GetScale() then
        _G['TWThreatDisplayTarget']:SetScale(UIParent:GetScale())
    end

    if TWT.healerMasterTarget ~= '' then
        return true
    end

    TWT.targetName = ''
    TWT.updateTargetFrameThreatIndicators(-1)

    if not UnitExists('target') or UnitIsDead('target') or UnitIsPlayer('target') then
        return false
    end

    local classification = UnitClassification('target')
    if classification ~= 'worldboss' and classification ~= 'elite' and classification ~= 'rareelite' then
        return false
    end

    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then
        return false
    end

    if not UnitAffectingCombat('player') or not UnitAffectingCombat('target') then
        return false
    end

    TWT.releaseThreats()
    for k in __pairs(TWT.history) do
        TWT.history[k] = nil
    end

    TWT.targetName = TWT.unitNameForTitle(UnitName('target'))
    TWT.updateTitleBarText(TWT.targetName)
    return true
end

function TWT.send(msg)
    SendAddonMessage(TWT.prefix, msg, TWT.channel)
end

function TWT.UnitDetailedThreatSituation(limit)
    SendAddonMessage(TWT.UDTS .. (TWT_CONFIG.tankMode and '_TM' or ''), "limit=" .. limit, TWT.channel)
end

-- Fast In-Place Threat Sorting (Zero-GC)
local function threatSortComparator(a, b)
    return a.perc > b.perc
end

function TWT.sortThreats()
    local count = 0
    for name, data in __pairs(TWT.threats) do
        count = count + 1
        local item = TWT.sortList[count]
        if not item then
            item = { name = '', threat = 0, perc = 0, tps = 0, class = 'priest', tank = false }
            TWT.sortList[count] = item
        end
        item.name = name
        item.threat = data.threat
        item.perc = data.perc
        item.tps = data.tps
        item.class = data.class
        item.tank = data.tank
    end
    for i = count + 1, #TWT.sortList do
        TWT.sortList[i] = nil
    end
    TWT.sortCount = count
    __tsort(TWT.sortList, threatSortComparator)
    return TWT.sortList, count
end

function TWT.updateUI(from)
    TWT.checkTargetFrames()

    if TWT_CONFIG.debug then
        local elapsed = __max(0.001, GetTime() - timeStart)
        _G['pps']:SetText('Traffic: ' .. TWT.round((totalPackets / elapsed) * 10) / 10
                .. ' pkts/s (' .. TWT.round(totalData / elapsed) .. ' cps) '
                .. TWT.round(uiUpdates / elapsed) .. ' ups')
        _G['pps']:Show()
    else
        _G['pps']:Hide()
    end

    uiUpdates = uiUpdates + 1

    TWT.hideThreatFrames()

    if not UnitAffectingCombat('player') and not _G['TWTMainSettings']:IsVisible() then
        TWT.updateTargetFrameThreatIndicators(-1)
        return false
    end

    if TWT.targetName == '' then
        return false
    end

    if _G['TWTMainSettings']:IsVisible() and not UnitAffectingCombat('player') then
        TWT.tankName = 'Tenk'
    end

    local sortList, count = TWT.sortThreats()
    local displayBars = __min(count, TWT_CONFIG.visibleBars)

    for index = 1, displayBars do
        local data = sortList[index]
        local name = data.name

        if data and TWT.threats[TWT.name] then
            if not TWT.threatsFrames[index] then
                TWT.threatsFrames[index] = CreateFrame('Frame', 'TWThreat' .. index, _G["TWTMain"], 'TWThreat')
            end

            local frame = TWT.threatsFrames[index]
            frame:SetAlpha(TWT_CONFIG.combatAlpha)
            frame:SetWidth(TWT.windowWidth - 2)

            _G['TWThreat' .. index .. 'Name']:SetFont("Interface\\addons\\TWThreat\\fonts\\" .. TWT_CONFIG.font .. ".ttf", 15, "OUTLINE")
            _G['TWThreat' .. index .. 'TPS']:SetFont("Interface\\addons\\TWThreat\\fonts\\" .. TWT_CONFIG.font .. ".ttf", 15, "OUTLINE")
            _G['TWThreat' .. index .. 'Threat']:SetFont("Interface\\addons\\TWThreat\\fonts\\" .. TWT_CONFIG.font .. ".ttf", 15, "OUTLINE")
            _G['TWThreat' .. index .. 'Perc']:SetFont("Interface\\addons\\TWThreat\\fonts\\" .. TWT_CONFIG.font .. ".ttf", 15, "OUTLINE")

            frame:SetHeight(TWT_CONFIG.barHeight - 1)
            _G['TWThreat' .. index .. 'BG']:SetHeight(TWT_CONFIG.barHeight - 2)

            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", _G["TWTMain"], "TOPLEFT", 0,
                    (TWT_CONFIG.labelRow and -40 or -20) + TWT_CONFIG.barHeight - 1 - index * TWT_CONFIG.barHeight)

            -- Role / Aggro Icons
            if name ~= TWT.AGRO then
                _G['TWThreat' .. index .. 'AGRO']:Hide()
                local roleTex = _G['TWThreat' .. index .. 'Role']
                roleTex:SetWidth(TWT_CONFIG.barHeight - 2)
                roleTex:SetHeight(TWT_CONFIG.barHeight - 2)
                _G['TWThreat' .. index .. 'Name']:SetPoint('LEFT', roleTex, 'RIGHT', 1 + (TWT_CONFIG.barHeight / 15), -1)

                if TWT.roles[name] then
                    roleTex:SetTexture('Interface\\Icons\\' .. TWT.roles[name])
                    roleTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                else
                    roleTex:SetTexture('Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes')
                    local coords = TWT.classCoords[data.class] or TWT.classCoords['priest']
                    roleTex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                end
                roleTex:Show()
            else
                _G['TWThreat' .. index .. 'AGRO']:Show()
                _G['TWThreat' .. index .. 'Role']:Hide()
            end

            -- TPS, Labels & Percentage
            _G['TWThreat' .. index .. 'TPS']:SetText(data.tps)
            TWT.setBarLabels(_G['TWThreat' .. index .. 'Perc'], _G['TWThreat' .. index .. 'Threat'], _G['TWThreat' .. index .. 'TPS'])
            _G['TWThreat' .. index .. 'Perc']:SetText(TWT.round(data.perc) .. '%')

            if TWT.name ~= TWT.tankName and name == TWT.AGRO and TWT.threats[TWT.name] then
                _G['TWThreat' .. index .. 'Perc']:SetText(100 - TWT.round(TWT.threats[TWT.name].perc) .. '%')
            end

            _G['TWThreat' .. index .. 'Name']:SetText(TWT.classColors['priest'].c .. name)

            -- Color & Bar Width Animation
            local color = TWT.classColors[data.class] or TWT.classColors['priest']

            if name == TWT.name then
                local now = time()
                if TWT_CONFIG.aggroSound and data.perc >= TWT_CONFIG.aggroThreshold and now - TWT.lastAggroWarningSoundTime > 5
                        and not TWT_CONFIG.fullScreenGlow then
                    PlaySoundFile('Interface\\AddOns\\TWThreat\\sounds\\warn.ogg', 'Master')
                    if FlashClientIcon then FlashClientIcon() end
                    TWT.lastAggroWarningSoundTime = now
                end

                if TWT_CONFIG.fullScreenGlow and data.perc >= TWT_CONFIG.aggroThreshold and now - TWT.lastAggroWarningGlowTime > 5 then
                    TWT.glowFader:Show()
                    TWT.lastAggroWarningGlowTime = now
                    if TWT_CONFIG.aggroSound then
                        PlaySoundFile('Interface\\AddOns\\TWThreat\\sounds\\warn.ogg', 'Master')
                        if FlashClientIcon then FlashClientIcon() end
                    end
                end

                TWT.updateTitleBarText(TWT.targetName .. ' (' .. TWT.round(data.perc) .. '%)')
                _G['TWThreat' .. index .. 'Threat']:SetText(TWT.formatNumber(data.threat))
                TWT.barAnimator:animateTo(index, data.perc)

            elseif name == TWT.AGRO then
                TWT.barAnimator:animateTo(index, nil)
                _G['TWThreat' .. index .. 'BG']:SetWidth(TWT.windowWidth - 2)

                local playerThreat = TWT.threats[TWT.name] and TWT.threats[TWT.name].threat or 0
                _G['TWThreat' .. index .. 'Threat']:SetText('+' .. TWT.formatNumber(data.threat - playerThreat))

                local playerPerc = TWT.threats[TWT.name] and TWT.threats[TWT.name].perc or 0
                local colorLimit = 50
                if playerPerc >= 0 and playerPerc < colorLimit then
                    _G['TWThreat' .. index .. 'BG']:SetVertexColor(playerPerc / colorLimit, 1, 0, 0.9)
                elseif playerPerc >= colorLimit then
                    _G['TWThreat' .. index .. 'BG']:SetVertexColor(1, 1 - (playerPerc - colorLimit) / colorLimit, 0, 0.9)
                end

                if TWT.tankName == TWT.name then
                    _G['TWThreat' .. index .. 'BG']:SetVertexColor(1, 0, 0, 1)
                    _G['TWThreat' .. index .. 'Perc']:SetText('')
                end
            else
                TWT.barAnimator:animateTo(index, data.perc)
                _G['TWThreat' .. index .. 'Threat']:SetText(TWT.formatNumber(data.threat))
                _G['TWThreat' .. index .. 'BG']:SetVertexColor(color.r, color.g, color.b, 0.9)
            end

            if data.tank then
                TWT.barAnimator:animateTo(index, 100, true)
            end

            if name == TWT.name then
                _G['TWThreat' .. index .. 'BG']:SetVertexColor(1, 0.2, 0.2, 1)
                TWT.updateTargetFrameThreatIndicators(data.perc)
            end

            frame:Show()
        end
    end

    -- Tank Mode Display
    if TWT_CONFIG.tankMode then
        for i = 1, 5 do
            _G['TMEF' .. i]:Hide()
        end
        _G['TWTMainTankModeWindow']:SetHeight(0)

        if TWT.tableSize(TWT.tankModeThreats) > 1 then
            local i = 0
            for guid, data in __pairs(TWT.tankModeThreats) do
                i = i + 1
                if i > 5 then break end

                _G['TWTMainTankModeWindow']:SetHeight(i * 25 + 23)
                _G['TMEF' .. i .. 'Target']:SetText(data.creature)

                local targetClsColor = TWT.classColors[TWT.getClass(data.name)] and TWT.classColors[TWT.getClass(data.name)].c or '|cffffffff'
                _G['TMEF' .. i .. 'Player']:SetText(targetClsColor .. data.name)
                _G['TMEF' .. i .. 'Perc']:SetText(TWT.round(data.perc) .. '%')
                _G['TMEF' .. i .. 'TargetButton']:SetID(guid)
                _G['TMEF' .. i]:SetPoint("TOPLEFT", _G["TWTMainTankModeWindow"], "TOPLEFT", 0, -21 + 24 - i * 25)
                _G['TMEF' .. i .. 'RaidTargetIcon']:Hide()

                if data.perc >= 0 and data.perc < 50 then
                    _G['TMEF' .. i .. 'BG']:SetVertexColor(data.perc / 50, 1, 0, 0.5)
                else
                    _G['TMEF' .. i .. 'BG']:SetVertexColor(1, 1 - (data.perc - 50) / 50, 0, 0.5)
                end

                _G['TMEF' .. i]:Show()
                _G['TWTMainTankModeWindow']:Show()
            end
        else
            _G['TWTMainTankModeWindow']:Hide()
        end
    else
        _G['TWTMainTankModeWindow']:Hide()
    end
end

-- Render-frame smoothing runs only while a bar has an unfinished width change.
TWT.barAnimator = CreateFrame('Frame', "TWTBarAnimatorFrame")
TWT.barAnimator:Hide()
TWT.barAnimator.frames = {}

function TWT.barAnimator:animateTo(index, perc, instant)
    local key = 'TWThreat' .. index .. 'BG'
    if perc == nil then
        TWT.barAnimator.frames[key] = nil
        if not next(TWT.barAnimator.frames) then TWT.barAnimator:Hide() end
        return false
    end

    perc = __min(100, __max(0, TWT.round(perc)))
    local width = TWT.round((TWT.windowWidth - 2) * perc / 100)
    if instant then
        local bg = _G[key]
        if bg then bg:SetWidth(width) end
        TWT.barAnimator.frames[key] = nil
        if not next(TWT.barAnimator.frames) then TWT.barAnimator:Hide() end
        return true
    end
    TWT.barAnimator.frames[key] = width
    TWT.barAnimator:Show()
end

TWT.barAnimator:SetScript("OnHide", function()
    table_wipe(this.frames)
end)

TWT.barAnimator:SetScript("OnUpdate", function()
    local dt = arg1 or 0.016
    if dt > 0.1 then dt = 0.1 end

    for frameName, targetW in __pairs(TWT.barAnimator.frames) do
        local frame = _G[frameName]
        if frame and targetW then
            local currentW = frame:GetWidth()
            local diff = targetW - currentW
            if __abs(diff) > 0.5 then
                local step = diff * __min(1.0, dt * 18.0)
                if __abs(step) < 0.2 then
                    step = diff > 0 and 0.2 or -0.2
                end
                frame:SetWidth(currentW + step)
            else
                frame:SetWidth(targetW)
                TWT.barAnimator.frames[frameName] = nil
            end
        else
            TWT.barAnimator.frames[frameName] = nil
        end
    end
    if not next(TWT.barAnimator.frames) then TWT.barAnimator:Hide() end
end)

-- One native timer owns the query cadence; hiding cancels it and invalidates
-- callbacks from an earlier combat session.
TWT.threatQuery:SetScript("OnShow", function()
    local frame = this
    if frame.timer then frame.timer:Cancel() end
    local timer
    timer = C_Timer.NewTicker(TWT.updateSpeed, function()
        if frame.timer ~= timer or not frame:IsVisible() then return end
        if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return end
        if UnitAffectingCombat('player') and UnitAffectingCombat('target') then
            if TWT.targetName == '' then
                TWT.targetChanged()
                return
            end

            if TWT_CONFIG.glow or TWT_CONFIG.perc or
                    TWT_CONFIG.fullScreenGlow or TWT_CONFIG.tankMode or
                    TWT_CONFIG.visible then
                if TWT.healerMasterTarget == '' then
                    TWT.UnitDetailedThreatSituation(TWT_CONFIG.visibleBars - 1)
                end
            end
        end
    end)
    frame.timer = timer
end)

TWT.threatQuery:SetScript("OnHide", function()
    if this.timer then this.timer:Cancel(); this.timer = nil end
end)

function TWT.calcTPS(name)
    local data = TWT.history[name]
    if not data then return 0 end

    local older = time()
    local count = 0
    for t in __pairs(data) do
        count = count + 1
        if t < older then
            older = t
        end
    end

    if count > 10 then
        data[older] = nil
    end

    local tps = 0
    local mean = 0
    local curTime = time()

    for i = 0, count - 1 do
        local t1 = data[curTime - i]
        local t2 = data[curTime - i - 1]
        if t1 and t2 then
            tps = tps + (t1 - t2)
            mean = mean + 1
        end
    end

    if mean > 0 and tps > 0 then
        return TWT.round(tps / mean)
    end

    return 0
end

function TWT.updateTargetFrameThreatIndicators(perc)
    TWT.checkTargetFrames()
    if TWT_CONFIG.fullScreenGlow then
        _G['TWTFullScreenGlow']:Show()
    else
        _G['TWTFullScreenGlow']:Hide()
    end

    if perc == -1 then
        TWT.updateTitleBarText()
        _G['TWThreatDisplayTarget']:Hide()
        return false
    end

    if not TWT_CONFIG.glow and not TWT_CONFIG.perc and not TWT.targetFrameVisible then
        _G['TWThreatDisplayTarget']:Hide()
    end

    if not TWT.targetFrameVisible then
        return false
    end

    _G['TWThreatDisplayTarget']:Show()
    perc = TWT.round(perc)

    if TWT_CONFIG.glow then
        local unitClassification = UnitClassification('target')
        if unitClassification == 'worldboss' then
            unitClassification = 'elite'
        end

        _G['TWThreatDisplayTargetGlow']:SetTexture('Interface\\addons\\TWThreat\\images\\' .. unitClassification)
        if perc >= 0 and perc < 50 then
            _G['TWThreatDisplayTargetGlow']:SetVertexColor(perc / 50, 1, 0, perc / 50)
        elseif perc >= 50 then
            _G['TWThreatDisplayTargetGlow']:SetVertexColor(1, 1 - (perc - 50) / 50, 0, 1)
        end
        _G['TWThreatDisplayTargetGlow']:Show()
    else
        _G['TWThreatDisplayTargetGlow']:Hide()
    end

    if TWT_CONFIG.perc then
        if TWT_CONFIG.tankMode then
            _G['TWThreatDisplayTargetNumericBG']:SetPoint('TOPLEFT', 24, -7)
            _G['TWThreatDisplayTargetNumericBG']:SetWidth(79)
            _G['TWThreatDisplayTargetNumericBorder']:SetPoint('TOPLEFT', 20, -3)
            _G['TWThreatDisplayTargetNumericBorder']:SetWidth(128)
            _G['TWThreatDisplayTargetNumericBorder']:SetTexture('Interface\\addons\\TWThreat\\images\\numericthreatborder_wide')
            _G['TWThreatDisplayTargetNumericPerc']:SetPoint('TOPLEFT', -1, 3)
            _G['TWThreatDisplayTargetNumericPerc']:SetWidth(128)
        else
            _G['TWThreatDisplayTargetNumericBG']:SetPoint('TOPLEFT', 44, -7)
            _G['TWThreatDisplayTargetNumericBG']:SetWidth(36)
            _G['TWThreatDisplayTargetNumericBorder']:SetPoint('TOPLEFT', 38, -3)
            _G['TWThreatDisplayTargetNumericBorder']:SetWidth(64)
            _G['TWThreatDisplayTargetNumericBorder']:SetTexture('Interface\\addons\\TWThreat\\images\\numericthreatborder')
            _G['TWThreatDisplayTargetNumericPerc']:SetPoint('TOPLEFT', 31, 3)
            _G['TWThreatDisplayTargetNumericPerc']:SetWidth(64)
        end

        local tankModePerc = 0
        if TWT_CONFIG.tankMode then
            local second = ''
            local sortList, count = TWT.sortThreats()
            if count >= 3 then
                local data = sortList[3]
                tankModePerc = TWT.round(data.perc)
                second = TWT.unitNameForTitle(data.name, 6) .. ' ' .. tankModePerc .. '%'
            end
            if second ~= '' then
                _G['TWThreatDisplayTargetNumericPerc']:SetText(second)
            else
                _G['TWThreatDisplayTargetNumericPerc']:SetText(perc .. '%')
            end
        else
            _G['TWThreatDisplayTargetNumericPerc']:SetText(perc .. '%')
        end

        if tankModePerc ~= 0 then
            perc = tankModePerc
        end

        if perc >= 0 and perc < 50 then
            _G['TWThreatDisplayTargetNumericBG']:SetVertexColor(perc / 50, 1, 0, 1)
        elseif perc >= 50 then
            _G['TWThreatDisplayTargetNumericBG']:SetVertexColor(1, 1 - (perc - 50) / 50, 0)
        end

        _G['TWThreatDisplayTargetNumericPerc']:Show()
        _G['TWThreatDisplayTargetNumericBG']:Show()
        _G['TWThreatDisplayTargetNumericBorder']:Show()
    else
        _G['TWThreatDisplayTargetNumericPerc']:Hide()
        _G['TWThreatDisplayTargetNumericBG']:Hide()
        _G['TWThreatDisplayTargetNumericBorder']:Hide()
    end
end

function TWTMainWindow_Resizing()
    _G['TWTMain']:SetAlpha(0.4)
end

function TWTMainMainWindow_Resized()
    _G['TWTMain']:SetAlpha(UnitAffectingCombat('player') and TWT_CONFIG.combatAlpha or TWT_CONFIG.oocAlpha)
    TWT_CONFIG.visibleBars = TWT.round((_G['TWTMain']:GetHeight() - (TWT_CONFIG.labelRow and 40 or 20)) / TWT_CONFIG.barHeight)
    TWT_CONFIG.visibleBars = __max(4, TWT_CONFIG.visibleBars)
    FrameHeightSlider_OnValueChanged()
end

function FrameHeightSlider_OnValueChanged()
    TWT_CONFIG.barHeight = _G['TWTMainSettingsFrameHeightSlider']:GetValue()
    _G['TWTMain']:SetHeight(TWT_CONFIG.barHeight * TWT_CONFIG.visibleBars + (TWT_CONFIG.labelRow and 40 or 20))
    TWT.setMinMaxResize()
    TWT.updateUI('FrameHeightSlider_OnValueChanged')
end

function WindowScaleSlider_OnValueChanged()
    TWT_CONFIG.windowScale = _G['TWTMainSettingsWindowScaleSlider']:GetValue()

    local x, y = _G['TWTMain']:GetLeft(), _G['TWTMain']:GetTop()
    local sx, sy = _G['TWTMainTankModeWindow']:GetLeft(), _G['TWTMainTankModeWindow']:GetTop()
    local s = _G['TWTMain']:GetEffectiveScale()
    local ss = _G['TWTMainTankModeWindow']:GetEffectiveScale()
    local posX, posY, sposX, sposY

    if x and y and s then
        posX = x * s
        posY = y * s
    end
    if sx and sy and ss then
        sposX = sx * ss
        sposY = sy * ss
    end

    _G['TWTMain']:SetScale(TWT_CONFIG.windowScale)
    _G['TWTMainTankModeWindow']:SetScale(TWT_CONFIG.windowScale)

    s = _G['TWTMain']:GetEffectiveScale()
    ss = _G['TWTMainTankModeWindow']:GetEffectiveScale()
    if posX and posY and s then
        _G['TWTMain']:ClearAllPoints()
        _G['TWTMain']:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", posX / s, posY / s)
    end
    if sposX and sposY and ss then
        _G['TWTMainTankModeWindow']:ClearAllPoints()
        _G['TWTMainTankModeWindow']:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sposX / ss, sposY / ss)
    end

    if TWT_CONFIG.tankModeStick ~= 'Free' then
        TWTTankModeWindowChangeStick_OnClick(TWT_CONFIG.tankModeStick)
    end
end

function CombatOpacitySlider_OnValueChanged()
    TWT_CONFIG.combatAlpha = _G['TWTMainSettingsCombatAlphaSlider']:GetValue()
    _G['TWTMain']:SetAlpha(UnitAffectingCombat('player') and TWT_CONFIG.combatAlpha or TWT_CONFIG.oocAlpha)
end

function OOCombatSlider_OnValueChanged()
    TWT_CONFIG.oocAlpha = _G['TWTMainSettingsOOCAlphaSlider']:GetValue()
    _G['TWTMain']:SetAlpha(UnitAffectingCombat('player') and TWT_CONFIG.combatAlpha or TWT_CONFIG.oocAlpha)
end

function AggroThresholdSlider_OnValueChanged()
    TWT_CONFIG.aggroThreshold = _G['TWTMainSettingsAggroThresholdSlider']:GetValue()
end

function TWTChangeSetting_OnClick(checked, code)
    if code == 'lock' then
        checked = not TWT_CONFIG[code]
        if checked then
            _G['TWTMainLockButton']:SetNormalTexture('Interface\\addons\\TWThreat\\images\\icon_locked')
        else
            _G['TWTMainLockButton']:SetNormalTexture('Interface\\addons\\TWThreat\\images\\icon_unlocked')
        end
    end
    TWT_CONFIG[code] = checked

    if code == 'tankMode' then
        if checked then
            TWT.testBars(true)
            TWT_CONFIG.fullScreenGlow = false
            TWT_CONFIG.aggroSound = false
            _G['TWTMainSettingsFullScreenGlow']:SetChecked(TWT_CONFIG.fullScreenGlow)
            _G['TWTMainSettingsFullScreenGlow']:Disable()
            _G['TWTMainSettingsAggroSound']:SetChecked(TWT_CONFIG.fullScreenGlow)
            _G['TWTMainSettingsAggroSound']:Disable()

            _G['TWTMainTankModeWindowStickTopButton']:Show()
            _G['TWTMainTankModeWindowStickRightButton']:Show()
            _G['TWTMainTankModeWindowStickBottomButton']:Show()
            _G['TWTMainTankModeWindowStickLeftButton']:Show()
            _G['TWTMainTankModeWindow']:Show()
        else
            _G['TWTMainSettingsFullScreenGlow']:Enable()
            _G['TWTMainSettingsAggroSound']:Enable()
            _G['TWTMainTankModeWindow']:Hide()
        end
    end

    if code == 'aggroSound' and checked and not UnitAffectingCombat('player') then
        PlaySoundFile('Interface\\AddOns\\TWThreat\\sounds\\warn.ogg', 'Master')
    end

    if code == 'fullScreenGlow' and checked and not UnitAffectingCombat('player') then
        TWT.glowFader:Show()
    end

    TWT.setColumnLabels()

    if TWT_CONFIG.labelRow then
        _G['TWTMainBarsBG']:SetPoint('TOPLEFT', 1, -40)
        _G['TWTMainNameLabel']:Show()
    else
        _G['TWTMainBarsBG']:SetPoint('TOPLEFT', 1, -20)
        _G['TWTMainNameLabel']:Hide()
        _G['TWTMainTPSLabel']:Hide()
        _G['TWTMainThreatLabel']:Hide()
        _G['TWTMainPercLabel']:Hide()
    end

    FrameHeightSlider_OnValueChanged()
    TWT.updateUI('TWTChangeSetting_OnClick')
end

function TWT.setColumnLabels()
    _G['TWTMain']:SetWidth(TWT.windowStartWidth - 210)
    TWT.nameLimit = 5

    if TWT_CONFIG.colPerc then
        _G['TWTMainPercLabel']:Show()
        _G['TWTMain']:SetWidth(_G['TWTMain']:GetWidth() + 70)
        TWT.nameLimit = TWT.nameLimit + 8
    else
        _G['TWTMainPercLabel']:Hide()
    end

    if TWT_CONFIG.colThreat then
        _G['TWTMain']:SetWidth(_G['TWTMain']:GetWidth() + 70)
        TWT.nameLimit = TWT.nameLimit + 8
        if TWT_CONFIG.colPerc then
            _G['TWTMainThreatLabel']:SetPoint('TOPRIGHT', _G['TWTMain'], -85, -21)
        else
            _G['TWTMainThreatLabel']:SetPoint('TOPRIGHT', _G['TWTMain'], -10, -21)
        end
        _G['TWTMainThreatLabel']:Show()
    else
        _G['TWTMainThreatLabel']:Hide()
    end

    if TWT_CONFIG.colTPS then
        _G['TWTMain']:SetWidth(_G['TWTMain']:GetWidth() + 70)
        TWT.nameLimit = TWT.nameLimit + 8

        if TWT_CONFIG.colThreat then
            if TWT_CONFIG.colPerc then
                _G['TWTMainTPSLabel']:SetPoint('TOPRIGHT', _G['TWTMain'], -150, -21)
            else
                _G['TWTMainTPSLabel']:SetPoint('TOPRIGHT', _G['TWTMain'], -80, -21)
            end
        elseif TWT_CONFIG.colPerc then
            _G['TWTMainTPSLabel']:SetPoint('TOPRIGHT', _G['TWTMain'], -80, -21)
        else
            _G['TWTMainTPSLabel']:SetPoint('TOPRIGHT', _G['TWTMain'], 'TOPRIGHT', -10, -21)
        end
        _G['TWTMainTPSLabel']:Show()
    else
        _G['TWTMainTPSLabel']:Hide()
    end

    if TWT.nameLimit < 14 then TWT.nameLimit = 14 end
    if _G['TWTMain']:GetWidth() < 190 then _G['TWTMain']:SetWidth(190) end

    TWT.windowWidth = _G['TWTMain']:GetWidth()
    TWT.setMinMaxResize()
end

function TWT.setMinMaxResize()
    _G['TWTMain']:SetMinResize(TWT.windowWidth, TWT_CONFIG.barHeight * TWT.minBars + (TWT_CONFIG.labelRow and 40 or 20))
    _G['TWTMain']:SetMaxResize(TWT.windowWidth, TWT_CONFIG.barHeight * TWT.maxBars + (TWT_CONFIG.labelRow and 40 or 20))
end

function TWT.setBarLabels(perc, threat, tps)
    if TWT_CONFIG.colPerc then
        perc:Show()
    else
        perc:Hide()
    end

    if TWT_CONFIG.colThreat then
        if TWT_CONFIG.colPerc then
            threat:SetPoint('RIGHT', -76, 0)
        else
            threat:SetPoint('RIGHT', -6, 0)
        end
        threat:Show()
    else
        threat:Hide()
    end

    if TWT_CONFIG.colTPS then
        if TWT_CONFIG.colThreat then
            if TWT_CONFIG.colPerc then
                tps:SetPoint('RIGHT', -146, 0)
            else
                tps:SetPoint('RIGHT', -76, 0)
            end
        elseif TWT_CONFIG.colPerc then
            tps:SetPoint('RIGHT', -76, 0)
        else
            tps:SetPoint('RIGHT', -6, 0)
        end
        tps:Show()
    else
        tps:Hide()
    end
end

function TWT.testBars(show)
    if UnitAffectingCombat('player') then
        return false
    end

    if show then
        TWT.roles['Tenk'] = 'ability_warrior_defensivestance'
        TWT.roles['Chad'] = 'spell_holy_auraoflight'
        TWT.roles[TWT.name] = 'ability_hunter_pet_turtle'
        TWT.roles['Olaf'] = 'ability_racial_bearform'
        TWT.roles['Jimmy'] = 'ability_backstab'
        TWT.roles['Miranda'] = 'spell_shadow_shadowwordpain'
        TWT.roles['Karen'] = 'spell_holy_powerinfusion'
        TWT.roles['Felix'] = 'spell_fire_sealoffire'
        TWT.roles['Tom'] = 'spell_shadow_shadowbolt'
        TWT.roles['Bill'] = 'ability_marksmanship'

        TWT.releaseThreats()
        local testData = {
            { name = TWT.AGRO, class = 'agro', threat = 1100, perc = 110, tps = '', melee = true, tank = false },
            { name = 'Tenk', class = 'warrior', threat = 1000, perc = 100, tps = 100, melee = true, tank = true },
            { name = 'Chad', class = 'paladin', threat = 990, perc = 99, tps = 99, melee = true, tank = false },
            { name = TWT.name, class = TWT.class, threat = 750, perc = 75, tps = 75, melee = false, tank = false },
            { name = 'Olaf', class = 'druid', threat = 700, perc = 70, tps = 70, melee = true, tank = false },
            { name = 'Jimmy', class = 'rogue', threat = 500, perc = 50, tps = 50, melee = true, tank = false },
            { name = 'Miranda', class = 'priest', threat = 450, perc = 45, tps = 45, melee = false, tank = false },
            { name = 'Karen', class = 'priest', threat = 400, perc = 40, tps = 40, melee = true, tank = false },
            { name = 'Felix', class = 'mage', threat = 350, perc = 35, tps = 35, melee = false, tank = false },
            { name = 'Tom', class = 'warlock', threat = 250, perc = 25, tps = 25, melee = false, tank = false },
            { name = 'Bill', class = 'hunter', threat = 100, perc = 10, tps = 10, melee = false, tank = false },
        }

        for _, d in __pairs(testData) do
            local e = TWT.getThreatEntry(d.name)
            e.class = d.class
            e.threat = d.threat
            e.perc = d.perc
            e.tps = d.tps
            e.melee = d.melee
            e.tank = d.tank
        end

        TWT.releaseTankModeThreats()
        local tmTestData = {
            ["1"] = { creature = 'Infectious Ghoul', name = 'Bob', perc = 78 },
            ["2"] = { creature = 'Venom Stalker', name = 'Alice', perc = 95 },
            ["3"] = { creature = 'Living Monstrosity', name = 'Chad', perc = 52 },
            ["4"] = { creature = 'Deathknight Captain', name = 'Olaf', perc = 81 },
            ["5"] = { creature = 'Patchwerk TEST', name = 'Jimmy', perc = 12 },
        }
        for k, v in __pairs(tmTestData) do
            local e = TWT.getTankModeEntry(k)
            e.creature = v.creature
            e.name = v.name
            e.perc = v.perc
        end

        TWT.targetChanged()
        TWT.targetName = "Patchwerk TEST"
        TWT.updateUI('testBars')
    else
        TWT.combatEnd()
    end
end

function TWTCloseButton_OnClick()
    _G['TWTMain']:Hide()
    twtprint('Window closed. Type |cff69ccf0/twt show|cffffffff or |cff69ccf0/twtshow|cffffffff to restore it.')
    TWT_CONFIG.visible = false
end

function TWTTankModeWindowCloseButton_OnClick()
    twtprint('Tank Mode disabled. Type |cff69ccf0/twt tankmode|cffffffff to enable it or go into settings.')
    TWTChangeSetting_OnClick(false, 'tankMode')
    _G['TWTMainSettingsTankMode']:SetChecked(false)
end

function TWTTankModeWindowChangeStick_OnClick(to)
    if to then
        TWT_CONFIG.tankModeStick = to
    end
    local stick = TWT_CONFIG.tankModeStick
    local tmWindow = _G['TWTMainTankModeWindow']
    local main = _G['TWTMain']

    if stick == 'Top' then
        tmWindow:ClearAllPoints()
        tmWindow:SetPoint('BOTTOMLEFT', main, 'TOPLEFT', 0, 1)
    elseif stick == 'Right' then
        tmWindow:ClearAllPoints()
        tmWindow:SetPoint('TOPLEFT', main, 'TOPRIGHT', 1, 0)
    elseif stick == 'Bottom' then
        tmWindow:ClearAllPoints()
        tmWindow:SetPoint('TOPLEFT', main, 'BOTTOMLEFT', 0, -1)
    elseif stick == 'Left' then
        tmWindow:ClearAllPoints()
        tmWindow:SetPoint('TOPRIGHT', main, 'TOPLEFT', -1, 0)
    end
end

function TWTSettingsToggle_OnClick()
    if _G['TWTMainSettings']:IsVisible() == 1 then
        _G['TWTMainSettings']:Hide()
        TWT.testBars(false)

        _G['TWTMainTankModeWindowStickTopButton']:Hide()
        _G['TWTMainTankModeWindowStickRightButton']:Hide()
        _G['TWTMainTankModeWindowStickBottomButton']:Hide()
        _G['TWTMainTankModeWindowStickLeftButton']:Hide()
    else
        _G['TWTMainSettings']:Show()
        if TWT_CONFIG.tankMode then
            TWTTankModeWindowChangeStick_OnClick()
            _G['TWTMainTankModeWindowStickTopButton']:Show()
            _G['TWTMainTankModeWindowStickRightButton']:Show()
            _G['TWTMainTankModeWindowStickBottomButton']:Show()
            _G['TWTMainTankModeWindowStickLeftButton']:Show()
        end
        TWT.testBars(true)
    end
end

function TWTFontButton_OnClick()
    local fontList = _G['TWTMainSettingsFontList']
    if fontList:IsVisible() then
        fontList:Hide()
    else
        fontList:Show()
    end
end

function TWTFontSelect(id)
    TWT_CONFIG.font = TWT.fonts[id]
    _G['TWTMainSettingsFontButton']:SetText(TWT_CONFIG.font)
    TWT.updateUI('TWTFontSelect')
end

-- SuperWoW Direct GUID Targeting Integration
function TWTTargetButton_OnClick(guidOrIndex)
    local key = __parsestring(guidOrIndex)
    local data = TWT.tankModeThreats[key]

    if data then
        -- SuperWoW direct GUID targeting if available
        if TargetUnit and type(TargetUnit) == "function" then
            TargetUnit(guidOrIndex)
            if UnitExists("target") and (not GetUnitGUID or GetUnitGUID("target") == guidOrIndex) then
                return true
            end
        end

        -- Exact whole-name targeting (SuperWoW) or AssistByName fallback
        if data.name and data.name ~= '' then
            if TargetByName then
                TargetByName(data.name, true)
                if UnitExists("target") then return true end
            end
            AssistByName(data.name)
            return true
        end
    end

    twtprint('Cannot target tankmode target.')
    return false
end

function TWT.formatNumber(n)
    if not n or n < 0 then n = 0 end
    if n < 999 then
        return TWT.round(n)
    end
    if n < 999999 then
        return (TWT.round(n / 10) / 100) .. 'K'
    end
    return (TWT.round(n / 10000) / 100) .. 'M'
end

function TWT.tableSize(t)
    if not t then return 0 end
    local size = 0
    for _ in __pairs(t) do
        size = size + 1
    end
    return size
end

function TWT.unitNameForTitle(name, limit)
    if not name then return '' end
    limit = limit or TWT.nameLimit
    if __strlen(name) > limit then
        return __substr(name, 1, limit) .. ' '
    end
    return name
end

function TWT.updateTitleBarText(text)
    if not text then
        _G['TWTMainTitle']:SetText(TWT.addonName .. ' |cffabd473v' .. TWT.addonVer)
        return true
    end
    _G['TWTMainTitle']:SetText(text)
end

function TWT.round(num, numDecimalPlaces)
    if not num then return 0 end
    local mult = 10 ^ (numDecimalPlaces or 0)
    return __floor(num * mult + 0.5) / mult
end

function TWT.version(ver)
    if not ver then return 0 end
    local p1 = __find(ver, '.', 1, true)
    if not p1 then return __parseint(ver) or 0 end
    local p2 = __find(ver, '.', p1 + 1, true)

    if p2 then
        local v1 = __parseint(__substr(ver, 1, p1 - 1)) or 0
        local v2 = __parseint(__substr(ver, p1 + 1, p2 - 1)) or 0
        local v3 = __parseint(__substr(ver, p2 + 1)) or 0
        return v1 * 100 + v2 * 10 + v3
    end

    local v1 = __parseint(__substr(ver, 1, p1 - 1)) or 0
    local v2 = __parseint(__substr(ver, p1 + 1)) or 0
    return v1 * 10 + v2
end

function TWT.wipe(src)
    if not src then return src end
    for k in __pairs(src) do
        src[k] = nil
    end
    return src
end
