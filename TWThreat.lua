-- TWThreat needs ClassicAPI and SuperWoW 2.2 or later.
local superVersion = tonumber(SUPERWOW_VERSION)
if type(CLASSIC_API_VERSION) ~= "number"
        or not superVersion or superVersion < 2.2 or not C_Timer or not C_Timer.NewTicker then
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[TWThreat]|r needs ClassicAPI and SuperWoW 2.2 or later. Check that both DLLs are loaded.", 1, 0.2, 0.2)
    end
    return
end

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local find, sub, lower = string.find, string.sub, string.lower
local tremove, tsort = table.remove, table.sort

local TWT = CreateFrame("Frame", "TWThreatCore")
TWT.addonVer = '1.5.0'
TWT.addonName = 'TWThreat'

-- The server's threat protocol: we ask with an addon message, the answer comes
-- back as CHAT_MSG_ADDON "TWTv4=name:tank:threat:perc:melee;..." with an
-- optional "#TMTv1=creature:guid:player:perc;..." part for tank mode.
local THREAT_API = 'TWTv4='
local TANK_MODE_API = 'TMTv1='
local QUERY_PREFIX = 'TWT_UDTSv4'
local PREFIX = 'TWT'
local AGRO = '-Pull Aggro at-'

local QUERY_EVERY = 0.5   -- seconds between queries: the original addon's fastest per-spec rate
local MOVE_TIME = 0.25    -- a bar sliding to its new rank
local TEXT_EVERY = 0.1    -- numbers roll ten times a second
local SAMPLES = 8         -- threat samples kept per player for threat per second
local KEEP_UNSEEN = 3     -- seconds a player missing from the answers keeps its history
local MIN_BARS, MAX_BARS = 5, 11

local FONTS = 'Interface\\AddOns\\TWThreat\\fonts\\'
local IMAGES = 'Interface\\AddOns\\TWThreat\\images\\'
local SOUND = 'Interface\\AddOns\\TWThreat\\sounds\\warn.ogg'
local WHITE = '|cffffffff'

local DEFAULTS = {
    visible = true, lock = false, windowScale = 1, combatAlpha = 1, oocAlpha = 1,
    showInCombat = false, hideOOC = false, labelRow = true,
    colTPS = true, colThreat = true, colPerc = true,
    font = 'Roboto', barHeight = 20, visibleBars = MIN_BARS,
    glow = false, perc = false, fullScreenGlow = false, aggroSound = false, aggroThreshold = 85,
    tankMode = false, tankModeStick = 'Free',
}

local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = 'raid' .. i end
for i = 1, 4 do PARTY_UNITS[i] = 'party' .. i end

TWT.name = UnitName('player') or ''
local _, playerClass = UnitClass('player')
TWT.class = playerClass and lower(playerClass) or 'warrior'
local canTank = TWT.class == 'warrior' or TWT.class == 'paladin' or TWT.class == 'druid'

TWT.targetName = ''
TWT.roles = {}     -- player name -> talent tree icon, from their TWTRoleTexture messages
TWT.classes = {}   -- player name -> class, from the group roster

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

local function twtprint(msg)
    local color = TWT.classColors[TWT.class]
    DEFAULT_CHAT_FRAME:AddMessage((color and color.c or WHITE) .. "[TWT] " .. WHITE .. msg)
end

local function round(n)
    return floor(n + 0.5)
end

-- Green to yellow below 50%, yellow to red above.
local function heat(perc)
    if perc < 0 then perc = 0 elseif perc > 100 then perc = 100 end
    if perc < 50 then return perc / 50, 1, 0 end
    return 1, 1 - (perc - 50) / 50, 0
end

local function inCombat()
    return UnitAffectingCombat('player')
end

local function groupChannel()
    if GetNumRaidMembers() > 0 then return 'RAID' end
    if GetNumPartyMembers() > 0 then return 'PARTY' end
end

function TWT.send(msg)
    local channel = groupChannel()
    if channel then SendAddonMessage(PREFIX, msg, channel) end
end

local function settingsShown()
    return TWTMainSettings:IsVisible()
end

-- Group roster ----------------------------------------------------------------

function TWT.getClass(name)
    return TWT.classes[name] or 'priest'
end

function TWT.getClasses()
    local units, n = RAID_UNITS, GetNumRaidMembers()
    if n == 0 then units, n = PARTY_UNITS, GetNumPartyMembers() end
    for i = 1, n do
        local unit = units[i]
        local name = UnitName(unit)
        local _, cls = UnitClass(unit)
        if name and cls then TWT.classes[name] = lower(cls) end
    end
    TWT.classes[TWT.name] = TWT.class
end

-- The icon of the talent tree with the most points, sent to the group so that
-- other TWThreat users show it on our bar. Kept until the talents change.
local roleTexture
local function findRoleTexture()
    local best, bestPoints = 1, -1
    for t = 1, GetNumTalentTabs() do
        local points = 0
        for i = 1, GetNumTalents(t) do
            local _, _, _, _, rank = GetTalentInfo(t, i)
            points = points + (rank or 0)
        end
        if points > bestPoints then best, bestPoints = t, points end
    end
    local _, texture = GetSpellTabInfo(best + 1)   -- tab 1 is General
    local icon = texture and string.match(texture, '([^\\]+)$')
    if not icon then return nil end
    -- The Arms tree shows a rogue icon on this client.
    if TWT.class == 'warrior' and lower(icon) == 'ability_rogue_eviscerate' then
        icon = 'ability_warrior_savageblow'
    end
    return icon
end

-- Threat entries --------------------------------------------------------------
-- One entry per player for the current target. An entry keeps the answer it
-- shows and the values it started from, so the bar can glide between answers.

local entries, pool = {}, {}
local order = {}       -- the entries of the last answer, highest threat first
local answer = 0       -- counts answers, to find players missing from one
local querySent = false
local lastAnswer
local pace = QUERY_EVERY
local glide = QUERY_EVERY * 1.15
local agro = { name = AGRO, agro = true, class = 'agro', threat = 1, perc = 110, tps = 0,
               fromPerc = 110, fromThreat = 1, fromTps = 0, start = 0 }
local playerEntry, tankEntry

local function newEntry()
    return { name = '', class = 'priest', tank = false, melee = false,
             threat = 0, perc = 0, tps = 0, fromThreat = 0, fromPerc = 0, fromTps = 0, start = 0,
             times = {}, values = {}, samples = 0, head = 0, seen = 0, seenAt = 0 }
end

local function progress(e, now)
    local p = (now - e.start) / glide
    if p >= 1 then return 1 end
    if p < 0 then return 0 end
    return p
end

-- Start a glide from what the entry shows now to new values.
local function retarget(e, now, threat, perc, tps, snap)
    if snap then
        e.fromThreat, e.fromPerc, e.fromTps = threat, perc, tps
    else
        local p = progress(e, now)
        e.fromThreat = e.fromThreat + (e.threat - e.fromThreat) * p
        e.fromPerc = e.fromPerc + (e.perc - e.fromPerc) * p
        e.fromTps = e.fromTps + (e.tps - e.fromTps) * p
    end
    e.threat, e.perc, e.tps = threat, perc, tps
    e.start = now
end

-- Threat per second over the samples kept, from real time.
local function threatPerSecond(e, now, threat)
    e.head = e.head % SAMPLES + 1
    e.times[e.head], e.values[e.head] = now, threat
    if e.samples < SAMPLES then e.samples = e.samples + 1 end
    local oldest = e.head - e.samples + 1
    if oldest < 1 then oldest = oldest + SAMPLES end
    local span = now - e.times[oldest]
    if span < 1 then return e.tps end
    return max(0, (threat - e.values[oldest]) / span)
end

local releaseBar   -- set with the bars below

local function releaseEntry(name, e)
    releaseBar(e)
    entries[name] = nil
    pool[#pool + 1] = e
end

local function releaseAll()
    for name, e in pairs(entries) do releaseEntry(name, e) end
    releaseBar(agro)
    table.wipe(order)
    playerEntry, tankEntry = nil, nil
end

local function setEntry(name, tank, threat, perc, melee, now, snap)
    local e = entries[name]
    local fresh = not e
    if fresh then
        e = tremove(pool) or newEntry()
        e.name, e.samples, e.head, e.tps, e.bar = name, 0, 0, 0, nil
        entries[name] = e
    end
    -- A player who had no bar last time starts where the answer puts them.
    retarget(e, now, threat, perc, threatPerSecond(e, now, threat), snap or fresh or not e.bar)
    e.tank, e.melee = tank, melee
    e.class = TWT.getClass(name)
    e.seen, e.seenAt = answer, now
    return e
end

local function byThreat(a, b)
    if a.perc ~= b.perc then return a.perc > b.perc end
    return a.name < b.name
end

-- Tank-mode rows: creatures we tank, by GUID.
local tankRows, tankPool, tankOrder = {}, {}, {}

local function setTankRow(guid, creature, name, perc, now)
    local r = tankRows[guid]
    local fresh = not r
    if fresh then
        r = tremove(tankPool) or { perc = 0, fromPerc = 0, start = 0 }
        tankRows[guid] = r
    end
    r.guid, r.creature, r.name = guid, creature, name
    r.fromPerc = fresh and perc or (r.fromPerc + (r.perc - r.fromPerc) * progress(r, now))
    r.perc, r.start, r.seen = perc, now, answer
end

local function releaseTankRows()
    for guid, r in pairs(tankRows) do
        tankRows[guid] = nil
        tankPool[#tankPool + 1] = r
    end
    table.wipe(tankOrder)
end

local function byTankPerc(a, b)
    if a.perc ~= b.perc then return a.perc > b.perc end
    return a.creature < b.creature
end

-- Bars ------------------------------------------------------------------------

local bars, freeBars = {}, {}
local track, top, barHeight = 298, -40, 20
local layoutVersion = 0

local function newBar()
    local n = #bars + 1
    local name = 'TWThreat' .. n
    local f = CreateFrame('Frame', name, TWTMain, 'TWThreat')
    local bar = { frame = f, bg = _G[name .. 'BG'], nameText = _G[name .. 'Name'], tps = _G[name .. 'TPS'],
                  threat = _G[name .. 'Threat'], perc = _G[name .. 'Perc'], role = _G[name .. 'Role'],
                  agroIcon = _G[name .. 'AGRO'] }
    f:ClearAllPoints()
    local fade = f:CreateAnimationGroup()
    local alpha = fade:CreateAnimation('Alpha')
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.2)
    fade:SetIgnoreFramerateThrottle(true)
    bar.fadeIn = fade
    bars[n] = bar
    return bar
end

local function applyLayout(bar)
    local cfg = TWT_CONFIG
    local font = FONTS .. cfg.font .. '.ttf'
    local f = bar.frame
    f:SetWidth(track)
    f:SetHeight(barHeight - 1)
    bar.bg:SetHeight(barHeight - 2)
    bar.nameText:SetFont(font, 15, 'OUTLINE')
    bar.tps:SetFont(font, 15, 'OUTLINE')
    bar.threat:SetFont(font, 15, 'OUTLINE')
    bar.perc:SetFont(font, 15, 'OUTLINE')
    bar.role:SetWidth(barHeight - 2)
    bar.role:SetHeight(barHeight - 2)
    bar.nameText:SetPoint('LEFT', bar.role, 'RIGHT', 1 + barHeight / 15, -1)
    if cfg.colPerc then bar.perc:Show() else bar.perc:Hide() end
    if cfg.colThreat then
        bar.threat:SetPoint('RIGHT', cfg.colPerc and -76 or -6, 0)
        bar.threat:Show()
    else
        bar.threat:Hide()
    end
    if cfg.colTPS then
        local x = -6
        if cfg.colThreat and cfg.colPerc then x = -146 elseif cfg.colThreat or cfg.colPerc then x = -76 end
        bar.tps:SetPoint('RIGHT', x, 0)
        bar.tps:Show()
    else
        bar.tps:Hide()
    end
    bar.layout = layoutVersion
    bar.w, bar.y, bar.pk, bar.tk, bar.sk, bar.colorKey = nil, nil, nil, nil, nil, nil
end

local function setRole(bar, e)
    if e.agro then
        bar.role:Hide()
        bar.agroIcon:Show()
        bar.roleKey = AGRO
        return
    end
    local role = TWT.roles[e.name]
    local key = role or e.class
    if bar.roleKey == key then return end
    bar.roleKey = key
    bar.agroIcon:Hide()
    if role then
        bar.role:SetTexture('Interface\\Icons\\' .. role)
        bar.role:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        bar.role:SetTexture('Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes')
        local c = TWT.classCoords[e.class] or TWT.classCoords['priest']
        bar.role:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    bar.role:Show()
end

local function setColor(bar, e)
    if e.agro then return end   -- follows the player's threat, see renderTexts
    local key = e.name == TWT.name and '' or e.class
    if bar.colorKey == key then return end
    bar.colorKey = key
    if key == '' then
        bar.bg:SetVertexColor(1, 0.2, 0.2, 1)
    else
        local c = TWT.classColors[e.class] or TWT.classColors['priest']
        bar.bg:SetVertexColor(c.r, c.g, c.b, 0.9)
    end
end

local function acquireBar(e, slot, fade)
    local bar = tremove(freeBars) or newBar()
    if bar.layout ~= layoutVersion then applyLayout(bar) end
    bar.entry = e
    bar.slot, bar.fromSlot, bar.slotStart = slot, slot, -1
    bar.w, bar.y, bar.pk, bar.tk, bar.sk, bar.roleKey, bar.colorKey = nil, nil, nil, nil, nil, nil, nil
    bar.nameText:SetText(WHITE .. e.name)
    setRole(bar, e)
    setColor(bar, e)
    bar.frame:Show()
    if fade then bar.fadeIn:Play() end
    e.bar = bar
    return bar
end

releaseBar = function(e)
    local bar = e.bar
    if not bar then return end
    bar.fadeIn:Stop()
    bar.frame:Hide()
    bar.entry = nil
    e.bar = nil
    freeBars[#freeBars + 1] = bar
end

-- Drawing ---------------------------------------------------------------------
-- One frame redraws the bars while something moves and sleeps when it settles.

TWT.animator = CreateFrame('Frame', 'TWTBarAnimatorFrame')
TWT.animator:Hide()
local textClock = 0
local titleKey, indicatorKey
local glowTexture = IMAGES .. 'elite'

local function shownPerc(e, now)
    return e.fromPerc + (e.perc - e.fromPerc) * progress(e, now)
end

local function shownThreat(e, now)
    return e.fromThreat + (e.threat - e.fromThreat) * progress(e, now)
end

local function renderTexts(bar, e, now)
    local p = progress(e, now)
    local cfg = TWT_CONFIG
    if e.agro then
        local mine = playerEntry and shownPerc(playerEntry, now) or 0
        local isTank = playerEntry and playerEntry.tank
        local pk = isTank and -1 or round(mine)
        if pk ~= bar.pk then
            bar.pk = pk
            if cfg.colPerc then bar.perc:SetText(isTank and '' or (100 - pk) .. '%') end
            if isTank then bar.bg:SetVertexColor(1, 0, 0, 1) else
                local r, g, b = heat(mine)
                bar.bg:SetVertexColor(r, g, b, 0.9)
            end
        end
        if cfg.colThreat then
            local gap = floor(e.fromThreat + (e.threat - e.fromThreat) * p
                    - (playerEntry and shownThreat(playerEntry, now) or 0))
            if gap < 0 then gap = 0 end
            if gap ~= bar.tk then bar.tk = gap; bar.threat:SetText('+' .. AbbreviateNumbers(gap)) end
        end
        if cfg.colTPS and bar.sk ~= '' then bar.sk = ''; bar.tps:SetText('') end
        return
    end
    if cfg.colPerc then
        local pk = round(e.fromPerc + (e.perc - e.fromPerc) * p)
        if pk ~= bar.pk then bar.pk = pk; bar.perc:SetText(pk .. '%') end
    end
    if cfg.colThreat then
        local tk = floor(e.fromThreat + (e.threat - e.fromThreat) * p)
        if tk < 0 then tk = 0 end
        if tk ~= bar.tk then bar.tk = tk; bar.threat:SetText(AbbreviateNumbers(tk)) end
    end
    if cfg.colTPS then
        local sk = round(e.fromTps + (e.tps - e.fromTps) * p)
        if sk ~= bar.sk then bar.sk = sk; bar.tps:SetText(sk) end
    end
end

local function hideIndicator()
    TWThreatDisplayTarget:Hide()
    indicatorKey = nil
end

-- The glow and number on the target frame, from what the player's bar shows.
local function renderIndicator(now)
    local cfg = TWT_CONFIG
    if not playerEntry or not (cfg.glow or cfg.perc) or not TargetFrame:IsVisible() then
        if indicatorKey then hideIndicator() end
        return
    end
    local perc = round(shownPerc(playerEntry, now))
    local second = cfg.tankMode and order[3]   -- in tank mode: the highest after the AGRO row and us
    local secondPerc = second and round(shownPerc(second, now)) or -1
    local key = perc * 1000 + secondPerc
    if key == indicatorKey then return end
    indicatorKey = key
    TWThreatDisplayTarget:Show()
    if cfg.glow then
        local r, g, b = heat(perc)
        TWThreatDisplayTargetGlow:SetTexture(glowTexture)
        TWThreatDisplayTargetGlow:SetVertexColor(r, g, b, perc < 50 and perc / 50 or 1)
        TWThreatDisplayTargetGlow:Show()
    else
        TWThreatDisplayTargetGlow:Hide()
    end
    if cfg.perc then
        if second then
            TWThreatDisplayTargetNumericPerc:SetText(TWT.unitNameForTitle(second.name, 6) .. ' ' .. secondPerc .. '%')
        else
            TWThreatDisplayTargetNumericPerc:SetText(perc .. '%')
        end
        local r, g, b = heat(second and secondPerc ~= 0 and secondPerc or perc)
        TWThreatDisplayTargetNumericBG:SetVertexColor(r, g, b, 1)
        TWThreatDisplayTargetNumericPerc:Show()
        TWThreatDisplayTargetNumericBG:Show()
        TWThreatDisplayTargetNumericBorder:Show()
    else
        TWThreatDisplayTargetNumericPerc:Hide()
        TWThreatDisplayTargetNumericBG:Hide()
        TWThreatDisplayTargetNumericBorder:Hide()
    end
end

local function renderTitle(now)
    local key = playerEntry and round(shownPerc(playerEntry, now)) or -1
    if key == titleKey then return end
    titleKey = key
    if key < 0 then TWT.updateTitleBarText() else
        TWT.updateTitleBarText(TWT.targetName .. ' (' .. key .. '%)')
    end
end

local rowFrames = {}   -- the five TMEF rows of the tank window, looked up once
local function tankRow(i)
    local row = rowFrames[i]
    if not row then
        local name = 'TMEF' .. i
        row = { frame = _G[name], target = _G[name .. 'Target'], player = _G[name .. 'Player'],
                perc = _G[name .. 'Perc'], bg = _G[name .. 'BG'], button = _G[name .. 'TargetButton'],
                icon = _G[name .. 'RaidTargetIcon'] }
        rowFrames[i] = row
    end
    return row
end

local function renderTankRows(now)
    for i = 1, #tankOrder do
        local r = tankOrder[i]
        local pk = round(shownPerc(r, now))
        if pk ~= r.pk then
            r.pk = pk
            local row = tankRow(i)
            row.perc:SetText(pk .. '%')
            local red, green, blue = heat(pk)
            row.bg:SetVertexColor(red, green, blue, 0.5)
        end
    end
end

local function render(now, texts)
    local moving = false
    local mainShown = TWTMain:IsVisible()
    for i = 1, #order do
        local e = order[i]
        local bar = e.bar
        if bar and mainShown then
            if now - e.start < glide then moving = true end
            local w = e.agro and track or track * max(0, min(100, shownPerc(e, now))) / 100
            if w < 1 then w = 1 end
            if not bar.w or abs(w - bar.w) > 0.05 then bar.bg:SetWidth(w); bar.w = w end
            local slot = bar.slot
            local s = (now - bar.slotStart) / MOVE_TIME
            if s < 1 then
                moving = true
                s = s * s * (3 - 2 * s)
                slot = bar.fromSlot + (bar.slot - bar.fromSlot) * s
            end
            local y = top - (slot - 1) * barHeight
            if y ~= bar.y then bar.frame:SetPoint('TOPLEFT', TWTMain, 'TOPLEFT', 0, y); bar.y = y end
            if texts then renderTexts(bar, e, now) end
        elseif now - e.start < glide then
            moving = true
        end
    end
    for i = 1, #tankOrder do
        if now - tankOrder[i].start < glide then moving = true end
    end
    if texts then
        renderTitle(now)
        renderIndicator(now)
        renderTankRows(now)
    end
    return moving
end

TWT.animator:SetScript('OnUpdate', function()
    local now = GetTime()
    textClock = textClock + (arg1 or 0)
    local texts = textClock >= TEXT_EVERY
    if texts then textClock = 0 end
    if not render(now, texts) then
        render(now, true)   -- the last frame shows the exact numbers
        this:Hide()
    end
end)

local function wake(now)
    render(now, true)
    textClock = 0
    TWT.animator:Show()
end

-- Rank the entries of the last answer and give the top ones a bar.
function TWT.rank(now, snap)
    for name, e in pairs(entries) do
        if e.seen ~= answer and now - e.seenAt > KEEP_UNSEEN then releaseEntry(name, e) end
    end
    table.wipe(order)
    playerEntry, tankEntry = nil, nil
    for _, e in pairs(entries) do
        if e.seen == answer then
            order[#order + 1] = e
            if e.tank then tankEntry = e end
            if e.name == TWT.name then playerEntry = e end
        else
            releaseBar(e)
        end
    end
    if playerEntry then
        -- The AGRO row: where we pull aggro, 110% of the tank's threat in melee range, 130% outside it.
        local mult = playerEntry.melee and 1.1 or 1.3
        local threat = tankEntry and tankEntry.threat * mult or 0
        if threat == 0 then threat = 1 end
        retarget(agro, now, threat, playerEntry.melee and 110 or 130, 0, snap or not agro.bar)
        order[#order + 1] = agro
    else
        releaseBar(agro)
    end
    tsort(order, byThreat)

    local visible = playerEntry and min(#order, TWT_CONFIG.visibleBars) or 0
    for i = 1, #order do
        local e = order[i]
        if i <= visible then
            local bar = e.bar
            if not bar then
                acquireBar(e, i, not snap)
            else
                setRole(bar, e)
                setColor(bar, e)
                if bar.slot ~= i then
                    local s = (now - bar.slotStart) / MOVE_TIME
                    local from = bar.slot
                    if s < 1 then from = bar.fromSlot + (bar.slot - bar.fromSlot) * s * s * (3 - 2 * s) end
                    bar.fromSlot, bar.slot, bar.slotStart = from, i, snap and -1 or now
                end
            end
        else
            releaseBar(e)
        end
    end
    wake(now)
end

-- Answers ---------------------------------------------------------------------

local function parseThreatItem(item)
    local p1 = find(item, ':', 1, true); if not p1 then return end
    local p2 = find(item, ':', p1 + 1, true); if not p2 then return end
    local p3 = find(item, ':', p2 + 1, true); if not p3 then return end
    local p4 = find(item, ':', p3 + 1, true); if not p4 then return end
    return sub(item, 1, p1 - 1), sub(item, p1 + 1, p2 - 1) == '1',
           tonumber(sub(item, p2 + 1, p3 - 1)) or 0, tonumber(sub(item, p3 + 1, p4 - 1)) or 0,
           sub(item, p4 + 1) == '1'
end

local function parseTankItem(item)
    local p1 = find(item, ':', 1, true); if not p1 then return end
    local p2 = find(item, ':', p1 + 1, true); if not p2 then return end
    local p3 = find(item, ':', p2 + 1, true); if not p3 then return end
    return sub(item, 1, p1 - 1), sub(item, p1 + 1, p2 - 1), sub(item, p2 + 1, p3 - 1),
           tonumber(sub(item, p3 + 1)) or 0
end

local function eachItem(list, from, fn, now)
    local len = #list
    while from <= len do
        local semi = find(list, ';', from, true) or (len + 1)
        if semi > from then fn(sub(list, from, semi - 1), now) end
        from = semi + 1
    end
end

local function readThreatItem(item, now)
    local name, tank, threat, perc, melee = parseThreatItem(item)
    if name then setEntry(name, tank, threat, perc, melee, now) end
end

local function readTankItem(item, now)
    local creature, guid, name, perc = parseTankItem(item)
    if creature and guid then setTankRow(guid, creature, name, perc, now) end
end

local function warn(now)
    local cfg = TWT_CONFIG
    if cfg.tankMode or not (cfg.fullScreenGlow or cfg.aggroSound) then return end
    if not playerEntry or playerEntry.perc < cfg.aggroThreshold then return end
    if TWT.lastWarning and now - TWT.lastWarning < 5 then return end
    TWT.lastWarning = now
    if cfg.fullScreenGlow then TWT.pulse() end
    if cfg.aggroSound then
        PlaySoundFile(SOUND, 'Master')
        FlashClientIcon()
    end
end

function TWT.showTankRows()
    local window = TWTMainTankModeWindow
    if not TWT_CONFIG.tankMode then window:Hide() return end
    table.wipe(tankOrder)
    for guid, r in pairs(tankRows) do
        if r.seen == answer then tankOrder[#tankOrder + 1] = r else
            tankRows[guid] = nil
            tankPool[#tankPool + 1] = r
        end
    end
    tsort(tankOrder, byTankPerc)
    if #tankOrder < 2 then window:Hide() return end
    local rows = min(#tankOrder, 5)
    for i = rows + 1, #tankOrder do tankOrder[i] = nil end
    window:SetHeight(rows * 25 + 23)
    for i = 1, 5 do
        local row = tankRow(i)
        local r = tankOrder[i]
        if r then
            row.target:SetText(r.creature)
            local c = TWT.classColors[TWT.getClass(r.name)]
            row.player:SetText((c and c.c or WHITE) .. r.name)
            -- ClassicAPI unit button: left click targets this creature by its GUID,
            -- hovering makes it the mouseover unit. Test rows have no GUID.
            -- UNVERIFIED: test in game that the server sends GUIDs as "0x" + hex.
            local button = row.button
            local unit = find(r.guid, '^0x%x+$') and r.guid or nil
            if button:GetAttribute('unit') ~= unit then button:SetAttribute('unit', unit) end
            if not button:GetAttribute('type1') then button:SetAttribute('type1', 'target') end
            row.frame:SetPoint('TOPLEFT', window, 'TOPLEFT', 0, 3 - i * 25)
            row.icon:Hide()
            r.pk = nil
            row.frame:Show()
        else
            row.frame:Hide()
        end
    end
    window:Show()
end

function TWT.handleAnswer(msg)
    local now = GetTime()
    answer = answer + 1
    local hash = find(msg, '#', 1, true)
    local tankStart = hash and find(msg, TANK_MODE_API, hash + 1, true)
    if tankStart then
        eachItem(msg, tankStart + #TANK_MODE_API, readTankItem, now)
        TWT.showTankRows()
        wake(now)
    end
    -- An answer that arrives before we asked about the current target is for the old one.
    if TWT.targetName == '' or not querySent then return end
    local start = find(msg, THREAT_API, 1, true)
    local snap = not next(entries)
    if lastAnswer then
        local gap = now - lastAnswer
        if gap > 0.1 and gap < 2 then pace = pace * 0.7 + gap * 0.3 end
    end
    lastAnswer = now
    local listEnd = hash and hash - 1 or #msg
    eachItem(sub(msg, 1, listEnd), start + #THREAT_API, readThreatItem, now)
    TWT.rank(now, snap)
    glide = max(0.2, min(1.5, pace * 1.15))
    warn(now)
end

-- Clear the threat display: a new target, the end of a fight, the settings closing.
-- Tank-mode rows do not depend on the target; the end of a fight clears them.
function TWT.clear()
    releaseAll()
    querySent = false
    titleKey = nil
    TWT.updateTitleBarText()
    hideIndicator()
    TWT.animator:Hide()
end

-- Query cadence: one native ticker per fight. Hiding the frame cancels it, and a
-- callback from an earlier fight cannot query.
TWT.threatQuery = CreateFrame('Frame', 'TWTThreatQueryFrame')
TWT.threatQuery:Hide()

function TWT.query()
    local channel = groupChannel()
    if not channel then return end
    SendAddonMessage(QUERY_PREFIX .. (TWT_CONFIG.tankMode and '_TM' or ''),
            'limit=' .. (TWT_CONFIG.visibleBars - 1), channel)
    querySent = true
end

TWT.threatQuery:SetScript('OnShow', function()
    local frame = this
    if frame.timer then frame.timer:Cancel() end
    local timer
    timer = C_Timer.NewTicker(QUERY_EVERY, function()
        if frame.timer ~= timer or not frame:IsVisible() then return end
        if not groupChannel() or not inCombat() or not UnitAffectingCombat('target') then return end
        if TWT.targetName == '' then
            TWT.targetChanged()
            return
        end
        local cfg = TWT_CONFIG
        if cfg.visible or cfg.glow or cfg.perc or cfg.fullScreenGlow or cfg.aggroSound or cfg.tankMode then
            TWT.query()
        end
    end)
    frame.timer = timer
end)

TWT.threatQuery:SetScript('OnHide', function()
    if this.timer then this.timer:Cancel(); this.timer = nil end
end)

-- Target and combat -----------------------------------------------------------

-- Threat is shown for elite and boss targets in combat, in a group.
function TWT.targetChanged()
    TWT.targetName = ''
    if not UnitExists('target') or UnitIsDead('target') or UnitIsPlayer('target') then return false end
    local classification = UnitClassification('target')
    if classification ~= 'worldboss' and classification ~= 'elite' and classification ~= 'rareelite' then
        return false
    end
    if not groupChannel() or not inCombat() or not UnitAffectingCombat('target') then return false end
    glowTexture = IMAGES .. (classification == 'worldboss' and 'elite' or classification)
    TWT.targetName = TWT.unitNameForTitle(UnitName('target'))
    titleKey = nil
    TWT.updateTitleBarText(TWT.targetName)
    return true
end

function TWT.combatStart()
    TWT.clear()
    TWTMain:SetAlpha(TWT_CONFIG.combatAlpha)
    if not groupChannel() then return end
    if TWT_CONFIG.showInCombat then TWTMain:Show() end
    if not roleTexture then roleTexture = findRoleTexture() end
    if roleTexture then TWT.send('TWTRoleTexture:' .. roleTexture) end
    TWT.getClasses()
    TWT.threatQuery:Show()
    TWTTankModeWindowChangeStick_OnClick()
end

function TWT.combatEnd()
    TWT.clear()
    releaseTankRows()
    TWT.threatQuery:Hide()
    if TWT_CONFIG.hideOOC then TWTMain:Hide() end
    TWTMainTankModeWindow:Hide()
    TWTMain:SetAlpha(TWT_CONFIG.oocAlpha)
end

-- Full-screen warning glow: one native fade in and out.
function TWT.pulse()
    TWT.glowPulse:Stop()
    TWTFullScreenGlow:Show()
    TWT.glowPulse:Play()
end

local function sizeGlow()
    TWTFullScreenGlowTexture:SetWidth(GetScreenWidth())
    TWTFullScreenGlowTexture:SetHeight(GetScreenHeight())
end

-- Events ----------------------------------------------------------------------

TWT:RegisterEvent('ADDON_LOADED')
TWT:RegisterEvent('CHAT_MSG_ADDON')
TWT:RegisterEvent('PLAYER_REGEN_DISABLED')
TWT:RegisterEvent('PLAYER_REGEN_ENABLED')
TWT:RegisterEvent('PLAYER_TARGET_CHANGED')
TWT:RegisterEvent('PLAYER_ENTERING_WORLD')
TWT:RegisterEvent('PARTY_MEMBERS_CHANGED')
TWT:RegisterEvent('RAID_ROSTER_UPDATE')
TWT:RegisterEvent('CHARACTER_POINTS_CHANGED')
TWT:RegisterEvent('UI_SCALE_CHANGED')

TWT:SetScript('OnEvent', function()
    if event == 'CHAT_MSG_ADDON' then
        if not arg2 then return end
        if find(arg2, THREAT_API, 1, true) then return TWT.handleAnswer(arg2) end
        if arg1 ~= PREFIX then return end
        if sub(arg2, 1, 15) == 'TWTRoleTexture:' then
            if arg4 then TWT.roles[arg4] = sub(arg2, 16) end
        elseif sub(arg2, 1, 7) == 'TWT_WHO' then
            TWT.send('TWT_ME:' .. TWT.addonVer)   -- answers another TWThreat's addon check
        end
    elseif event == 'PLAYER_TARGET_CHANGED' then
        if not inCombat() and settingsShown() then return end   -- the settings show test bars
        TWT.clear()
        TWT.targetChanged()
    elseif event == 'PLAYER_REGEN_DISABLED' then
        TWT.combatStart()
    elseif event == 'PLAYER_REGEN_ENABLED' then
        TWT.combatEnd()
    elseif event == 'PARTY_MEMBERS_CHANGED' or event == 'RAID_ROSTER_UPDATE' then
        TWT.getClasses()
    elseif event == 'CHARACTER_POINTS_CHANGED' then
        roleTexture = nil
    elseif event == 'UI_SCALE_CHANGED' then
        TWThreatDisplayTarget:SetScale(UIParent:GetScale())
        sizeGlow()
    elseif event == 'PLAYER_ENTERING_WORLD' then
        TWT.combatEnd()
        if inCombat() then TWT.combatStart() end
    elseif event == 'ADDON_LOADED' and arg1 == 'TWThreat' then
        TWT:UnregisterEvent('ADDON_LOADED')
        TWT.init()
    end
end)

-- Window and settings ---------------------------------------------------------

function TWT.show()
    TWTMain:Show()
    TWT_CONFIG.visible = true
end

local function headerHeight()
    return TWT_CONFIG.labelRow and 40 or 20
end

function TWT.setMinMaxResize()
    TWTMain:SetMinResize(TWT.windowWidth, barHeight * MIN_BARS + headerHeight())
    TWTMain:SetMaxResize(TWT.windowWidth, barHeight * MAX_BARS + headerHeight())
end

-- Window size, columns, label row and bar layout, after any setting change.
function TWT.layout()
    local cfg = TWT_CONFIG
    local main = TWTMain
    local width, columns = 90, 0
    if cfg.colPerc then
        columns = columns + 1
        TWTMainPercLabel:Show()
    else
        TWTMainPercLabel:Hide()
    end
    if cfg.colThreat then
        columns = columns + 1
        TWTMainThreatLabel:SetPoint('TOPRIGHT', main, cfg.colPerc and -85 or -10, -21)
        TWTMainThreatLabel:Show()
    else
        TWTMainThreatLabel:Hide()
    end
    if cfg.colTPS then
        columns = columns + 1
        local x = -10
        if cfg.colThreat and cfg.colPerc then x = -150 elseif cfg.colThreat or cfg.colPerc then x = -80 end
        TWTMainTPSLabel:SetPoint('TOPRIGHT', main, 'TOPRIGHT', x, -21)
        TWTMainTPSLabel:Show()
    else
        TWTMainTPSLabel:Hide()
    end
    width = max(190, width + 70 * columns)
    TWT.nameLimit = max(14, 5 + 8 * columns)
    TWT.windowWidth = width
    main:SetWidth(width)

    if cfg.labelRow then
        TWTMainBarsBG:SetPoint('TOPLEFT', 1, -40)
        TWTMainNameLabel:Show()
    else
        TWTMainBarsBG:SetPoint('TOPLEFT', 1, -20)
        TWTMainNameLabel:Hide()
        TWTMainTPSLabel:Hide()
        TWTMainThreatLabel:Hide()
        TWTMainPercLabel:Hide()
    end

    barHeight = cfg.barHeight
    track = width - 2
    top = -headerHeight() - 1
    main:SetHeight(barHeight * cfg.visibleBars + headerHeight())
    TWT.setMinMaxResize()

    if cfg.tankMode then
        TWThreatDisplayTargetNumericBG:SetPoint('TOPLEFT', 24, -7)
        TWThreatDisplayTargetNumericBG:SetWidth(79)
        TWThreatDisplayTargetNumericBorder:SetPoint('TOPLEFT', 20, -3)
        TWThreatDisplayTargetNumericBorder:SetWidth(128)
        TWThreatDisplayTargetNumericBorder:SetTexture(IMAGES .. 'numericthreatborder_wide')
        TWThreatDisplayTargetNumericPerc:SetPoint('TOPLEFT', -1, 3)
        TWThreatDisplayTargetNumericPerc:SetWidth(128)
    else
        TWThreatDisplayTargetNumericBG:SetPoint('TOPLEFT', 44, -7)
        TWThreatDisplayTargetNumericBG:SetWidth(36)
        TWThreatDisplayTargetNumericBorder:SetPoint('TOPLEFT', 38, -3)
        TWThreatDisplayTargetNumericBorder:SetWidth(64)
        TWThreatDisplayTargetNumericBorder:SetTexture(IMAGES .. 'numericthreatborder')
        TWThreatDisplayTargetNumericPerc:SetPoint('TOPLEFT', 31, 3)
        TWThreatDisplayTargetNumericPerc:SetWidth(64)
    end

    layoutVersion = layoutVersion + 1
    for i = 1, #bars do
        local bar = bars[i]
        applyLayout(bar)
        if bar.entry then setRole(bar, bar.entry); setColor(bar, bar.entry) end
    end
    indicatorKey, titleKey = nil, nil
    if #order > 0 then TWT.rank(GetTime(), true) end
end

local function updateLock()
    TWTMainLockButton:SetNormalTexture(IMAGES .. (TWT_CONFIG.lock and 'icon_locked' or 'icon_unlocked'))
end

-- In tank mode the full-screen glow and the warning sound stay quiet; their
-- settings are kept for when tank mode is turned off.
local function updateTankModeControls()
    if TWT_CONFIG.tankMode then
        TWTMainSettingsFullScreenGlow:Disable()
        TWTMainSettingsAggroSound:Disable()
    else
        TWTMainSettingsFullScreenGlow:Enable()
        TWTMainSettingsAggroSound:Enable()
    end
end

local function showStickButtons(show)
    local method = show and 'Show' or 'Hide'
    TWTMainTankModeWindowStickTopButton[method](TWTMainTankModeWindowStickTopButton)
    TWTMainTankModeWindowStickRightButton[method](TWTMainTankModeWindowStickRightButton)
    TWTMainTankModeWindowStickBottomButton[method](TWTMainTankModeWindowStickBottomButton)
    TWTMainTankModeWindowStickLeftButton[method](TWTMainTankModeWindowStickLeftButton)
end

function TWT.init()
    if not TWT_CONFIG then TWT_CONFIG = {} end
    local cfg = TWT_CONFIG
    for key, value in pairs(DEFAULTS) do
        if cfg[key] == nil then cfg[key] = value end
    end
    -- Retired settings.
    cfg.skeram, cfg.debug = nil, nil
    if not canTank then
        TWTMainSettingsTankMode:Disable()
        cfg.tankMode = false
    end

    if cfg.visible then TWTMain:Show() else TWTMain:Hide() end
    updateLock()
    updateTankModeControls()
    sizeGlow()
    TWThreatDisplayTarget:SetScale(UIParent:GetScale())

    local pulse = TWTFullScreenGlow:CreateAnimationGroup()
    local rise = pulse:CreateAnimation('Alpha')
    rise:SetFromAlpha(0); rise:SetToAlpha(0.6); rise:SetDuration(0.4); rise:SetSmoothing('OUT'); rise:SetOrder(1)
    local fall = pulse:CreateAnimation('Alpha')
    fall:SetFromAlpha(0.6); fall:SetToAlpha(0); fall:SetDuration(0.4); fall:SetSmoothing('IN'); fall:SetOrder(2)
    pulse:SetIgnoreFramerateThrottle(true)
    pulse:SetScript('OnFinished', function() TWTFullScreenGlow:Hide() end)
    TWT.glowPulse = pulse

    TWTMainSettingsFrameHeightSlider:SetValue(cfg.barHeight)
    TWTMainSettingsWindowScaleSlider:SetValue(cfg.windowScale)
    TWTMainSettingsCombatAlphaSlider:SetValue(cfg.combatAlpha)
    TWTMainSettingsOOCAlphaSlider:SetValue(cfg.oocAlpha)
    TWTMainSettingsAggroThresholdSlider:SetValue(cfg.aggroThreshold)
    TWTMainSettingsFontButton:SetText(cfg.font)
    TWTMainSettingsTargetFrameGlow:SetChecked(cfg.glow)
    TWTMainSettingsPercNumbers:SetChecked(cfg.perc)
    TWTMainSettingsShowInCombat:SetChecked(cfg.showInCombat)
    TWTMainSettingsHideOOC:SetChecked(cfg.hideOOC)
    TWTMainSettingsFullScreenGlow:SetChecked(cfg.fullScreenGlow)
    TWTMainSettingsAggroSound:SetChecked(cfg.aggroSound)
    TWTMainSettingsTankMode:SetChecked(cfg.tankMode)
    TWTMainSettingsColumnsTPS:SetChecked(cfg.colTPS)
    TWTMainSettingsColumnsThreat:SetChecked(cfg.colThreat)
    TWTMainSettingsColumnsPercent:SetChecked(cfg.colPerc)
    TWTMainSettingsLabelRow:SetChecked(cfg.labelRow)
    TWTMainSettingsFontButtonNT:SetVertexColor(0.4, 0.4, 0.4)

    local color = TWT.classColors[TWT.class] or TWT.classColors['warrior']
    TWTMainTitleBG:SetVertexColor(color.r, color.g, color.b)
    TWTMainSettingsTitleBG:SetVertexColor(color.r, color.g, color.b)
    TWTMainTankModeWindowTitleBG:SetVertexColor(color.r, color.g, color.b)

    for i, font in ipairs(TWT.fonts) do
        local name = 'TWTFont' .. i
        local button = CreateFrame('Button', name, TWTMainSettingsFontList, 'TWTFontFrameTemplate')
        button:SetPoint('TOPLEFT', TWTMainSettingsFontList, 'TOPLEFT', 0, 17 - i * 17)
        button:SetID(i)
        _G[name .. 'Name']:SetFont(FONTS .. font .. '.ttf', 15)
        _G[name .. 'Name']:SetText(font)
        _G[name .. 'HT']:SetVertexColor(1, 1, 1, 0.5)
        button:Show()
    end

    TWT.layout()
    TWT.updateTitleBarText()
    TWT.updateSettingsTabs(1)
    twtprint(TWT.addonName .. ' |cffabd473v' .. TWT.addonVer .. WHITE .. ' loaded.')
end

function TWT.updateSettingsTabs(tab)
    local color = TWT.classColors[TWT.class] or TWT.classColors['warrior']
    TWTMainSettingsTabsUnderline:SetVertexColor(color.r, color.g, color.b)
    for i = 1, 3 do
        local name = 'TWTMainSettingsTab' .. i
        _G[name]:Hide()
        _G[name .. 'ButtonNT']:SetVertexColor(color.r, color.g, color.b, 0.4)
        _G[name .. 'ButtonHT']:SetVertexColor(color.r, color.g, color.b, 0.4)
        _G[name .. 'ButtonPT']:SetVertexColor(color.r, color.g, color.b, 0.4)
        _G[name .. 'ButtonText']:SetTextColor(0.4, 0.4, 0.4)
    end
    local name = 'TWTMainSettingsTab' .. tab
    _G[name .. 'ButtonNT']:SetVertexColor(color.r, color.g, color.b, 1)
    _G[name .. 'ButtonText']:SetTextColor(1, 1, 1)
    _G[name]:Show()
end

function TWTSettingsTab_OnClick(tab)
    TWT.updateSettingsTabs(tab)
end

function TWTMainWindow_Resizing()
    TWTMain:SetAlpha(0.4)
end

function TWTMainMainWindow_Resized()
    TWTMain:SetAlpha(inCombat() and TWT_CONFIG.combatAlpha or TWT_CONFIG.oocAlpha)
    TWT_CONFIG.visibleBars = max(MIN_BARS, round((TWTMain:GetHeight() - headerHeight()) / TWT_CONFIG.barHeight))
    TWT.layout()
end

function TWTFrameHeightSlider_OnValueChanged()
    TWT_CONFIG.barHeight = TWTMainSettingsFrameHeightSlider:GetValue()
    TWT.layout()
end

function TWTWindowScaleSlider_OnValueChanged()
    TWT_CONFIG.windowScale = TWTMainSettingsWindowScaleSlider:GetValue()
    local main, tank = TWTMain, TWTMainTankModeWindow
    local x, y, s = main:GetLeft(), main:GetTop(), main:GetEffectiveScale()
    local tx, ty, ts = tank:GetLeft(), tank:GetTop(), tank:GetEffectiveScale()
    main:SetScale(TWT_CONFIG.windowScale)
    tank:SetScale(TWT_CONFIG.windowScale)
    if x and y then
        main:ClearAllPoints()
        main:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x * s / main:GetEffectiveScale(), y * s / main:GetEffectiveScale())
    end
    if tx and ty then
        tank:ClearAllPoints()
        tank:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', tx * ts / tank:GetEffectiveScale(), ty * ts / tank:GetEffectiveScale())
    end
    if TWT_CONFIG.tankModeStick ~= 'Free' then
        TWTTankModeWindowChangeStick_OnClick(TWT_CONFIG.tankModeStick)
    end
end

function TWTCombatOpacitySlider_OnValueChanged()
    TWT_CONFIG.combatAlpha = TWTMainSettingsCombatAlphaSlider:GetValue()
    TWTMain:SetAlpha(inCombat() and TWT_CONFIG.combatAlpha or TWT_CONFIG.oocAlpha)
end

function TWTOOCOpacitySlider_OnValueChanged()
    TWT_CONFIG.oocAlpha = TWTMainSettingsOOCAlphaSlider:GetValue()
    TWTMain:SetAlpha(inCombat() and TWT_CONFIG.combatAlpha or TWT_CONFIG.oocAlpha)
end

function TWTAggroThresholdSlider_OnValueChanged()
    TWT_CONFIG.aggroThreshold = TWTMainSettingsAggroThresholdSlider:GetValue()
end

function TWTChangeSetting_OnClick(checked, code)
    if code == 'lock' then checked = not TWT_CONFIG.lock end
    TWT_CONFIG[code] = checked and true or false
    if code == 'lock' then updateLock() end
    if code == 'tankMode' then
        updateTankModeControls()
        if TWT_CONFIG.tankMode then
            showStickButtons(true)
            TWTMainTankModeWindow:Show()
            if settingsShown() then TWT.testBars(true) end
        else
            TWTMainTankModeWindow:Hide()
        end
    end
    if code == 'aggroSound' and checked and not inCombat() then PlaySoundFile(SOUND, 'Master') end
    if code == 'fullScreenGlow' and checked and not inCombat() then TWT.pulse() end
    TWT.layout()
end

function TWT.testBars(show)
    if inCombat() then return end
    if not show then
        TWT.combatEnd()
        return
    end
    local roles = TWT.roles
    roles['Tenk'] = 'ability_warrior_defensivestance'
    roles['Chad'] = 'spell_holy_auraoflight'
    roles[TWT.name] = 'ability_hunter_pet_turtle'
    roles['Olaf'] = 'ability_racial_bearform'
    roles['Jimmy'] = 'ability_backstab'
    roles['Miranda'] = 'spell_shadow_shadowwordpain'
    roles['Karen'] = 'spell_holy_powerinfusion'
    roles['Felix'] = 'spell_fire_sealoffire'
    roles['Tom'] = 'spell_shadow_shadowbolt'
    roles['Bill'] = 'ability_marksmanship'
    TWT.classes['Tenk'], TWT.classes['Chad'], TWT.classes['Olaf'] = 'warrior', 'paladin', 'druid'
    TWT.classes['Jimmy'], TWT.classes['Miranda'], TWT.classes['Karen'] = 'rogue', 'priest', 'priest'
    TWT.classes['Felix'], TWT.classes['Tom'], TWT.classes['Bill'] = 'mage', 'warlock', 'hunter'
    TWT.classes[TWT.name] = TWT.class

    TWT.clear()
    releaseTankRows()
    local now = GetTime()
    answer = answer + 1
    local test = {
        { 'Tenk', true, 1000, 100, true }, { 'Chad', false, 990, 99, true },
        { TWT.name, false, 750, 75, false }, { 'Olaf', false, 700, 70, true },
        { 'Jimmy', false, 500, 50, true }, { 'Miranda', false, 450, 45, false },
        { 'Karen', false, 400, 40, true }, { 'Felix', false, 350, 35, false },
        { 'Tom', false, 250, 25, false }, { 'Bill', false, 100, 10, false },
    }
    for _, t in ipairs(test) do
        local e = setEntry(t[1], t[2], t[3], t[4], t[5], now, true)
        e.tps, e.fromTps = t[4], t[4]   -- a sample threat per second
    end
    setTankRow('1', 'Infectious Ghoul', 'Bob', 78, now)
    setTankRow('2', 'Venom Stalker', 'Alice', 95, now)
    setTankRow('3', 'Living Monstrosity', 'Chad', 52, now)
    setTankRow('4', 'Deathknight Captain', 'Olaf', 81, now)
    setTankRow('5', 'Patchwerk TEST', 'Jimmy', 12, now)
    TWT.targetName = 'Patchwerk TEST'
    TWT.showTankRows()
    TWT.rank(now, true)
end

function TWTCloseButton_OnClick()
    TWTMain:Hide()
    twtprint('Window closed. Type |cff69ccf0/twt show|cffffffff or |cff69ccf0/twtshow|cffffffff to restore it.')
    TWT_CONFIG.visible = false
end

function TWTTankModeWindowCloseButton_OnClick()
    twtprint('Tank Mode disabled. Type |cff69ccf0/twt tankmode|cffffffff to enable it or go into settings.')
    TWTMainSettingsTankMode:SetChecked(false)
    TWTChangeSetting_OnClick(false, 'tankMode')
end

function TWTTankModeWindowChangeStick_OnClick(to)
    if to then TWT_CONFIG.tankModeStick = to end
    local stick = TWT_CONFIG.tankModeStick
    local window, main = TWTMainTankModeWindow, TWTMain
    if stick == 'Free' then return end
    window:ClearAllPoints()
    if stick == 'Top' then
        window:SetPoint('BOTTOMLEFT', main, 'TOPLEFT', 0, 1)
    elseif stick == 'Right' then
        window:SetPoint('TOPLEFT', main, 'TOPRIGHT', 1, 0)
    elseif stick == 'Bottom' then
        window:SetPoint('TOPLEFT', main, 'BOTTOMLEFT', 0, -1)
    elseif stick == 'Left' then
        window:SetPoint('TOPRIGHT', main, 'TOPLEFT', -1, 0)
    end
end

function TWTSettingsToggle_OnClick()
    if settingsShown() then
        TWTMainSettings:Hide()
        TWT.testBars(false)
        showStickButtons(false)
    else
        TWTMainSettings:Show()
        if TWT_CONFIG.tankMode then
            TWTTankModeWindowChangeStick_OnClick()
            showStickButtons(true)
        end
        TWT.testBars(true)
    end
end

function TWTFontButton_OnClick()
    if TWTMainSettingsFontList:IsVisible() then TWTMainSettingsFontList:Hide() else TWTMainSettingsFontList:Show() end
end

function TWTFontSelect(id)
    TWT_CONFIG.font = TWT.fonts[id]
    TWTMainSettingsFontButton:SetText(TWT_CONFIG.font)
    TWTMainSettingsFontList:Hide()
    TWT.layout()
end

function TWT.unitNameForTitle(name, limit)
    if not name then return '' end
    limit = limit or TWT.nameLimit or 14
    if #name > limit then return sub(name, 1, limit) .. ' ' end
    return name
end

function TWT.updateTitleBarText(text)
    TWTMainTitle:SetText(text or (TWT.addonName .. ' |cffabd473v' .. TWT.addonVer))
end

-- Slash commands --------------------------------------------------------------

SLASH_TWT1 = '/twt'
SlashCmdList['TWT'] = function(cmd)
    cmd = lower(cmd or '')
    if find(cmd, '^show') then
        TWT.show()
    elseif find(cmd, '^tankmode') then
        if not canTank then
            twtprint('Tank Mode is for warriors, paladins and druids.')
            return
        end
        local on = not TWT_CONFIG.tankMode
        TWTMainSettingsTankMode:SetChecked(on)
        TWTChangeSetting_OnClick(on, 'tankMode')
        twtprint(on and 'Tank Mode enabled.' or 'Tank Mode disabled.')
    else
        twtprint(TWT.addonName .. ' |cffabd473v' .. TWT.addonVer .. WHITE .. ' commands:')
        twtprint('/twt show - shows the main window (also /twtshow)')
        twtprint('/twt tankmode - turns the tank window on or off')
    end
end

SLASH_TWTSHOW1 = '/twtshow'
SlashCmdList['TWTSHOW'] = function() TWT.show() end

-- Game Menu > AddOn Options > TWThreat (ClassicAPI).
local entry = CreateFrame("Frame", "TWThreatOptionsEntry")
entry.name = "TWThreat"
local entryTitle = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
entryTitle:SetPoint("TOPLEFT", entry, "TOPLEFT", 16, -16)
entryTitle:SetText("TWThreat")
local entryText = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
entryText:SetPoint("TOPLEFT", entryTitle, "BOTTOMLEFT", 0, -8)
entryText:SetWidth(380)
entryText:SetJustifyH("LEFT")
entryText:SetText("Threat meter. Type /twtshow to show the window at any time.")
local entryOpen = CreateFrame("Button", "TWThreatOptionsEntryOpen", entry, "UIPanelButtonTemplate")
entryOpen:SetWidth(172); entryOpen:SetHeight(22)
entryOpen:SetPoint("TOPLEFT", entry, "TOPLEFT", 16, -80)
entryOpen:SetText("Show threat window")
entryOpen:SetScript("OnClick", function()
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame:Hide() end
    if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
    TWT.show()
end)
InterfaceOptions_AddCategory(entry)
