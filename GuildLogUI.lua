-- GuildLogUI.lua
-- Scrollable log window with filter buttons, built entirely on raw frames
-- (no AceGUI-3.0 -- only the outer window chrome ever used it, and everything
-- else here was already hand-built).

local UI = {}
GuildLogUI = UI

-- == Constants ================================================================

local WINDOW_W   = 830
local WINDOW_H   = 610
local WINDOW_MIN_W = 620
local WINDOW_MIN_H = 340
local WINDOW_MAX_W = 1600
local WINDOW_MAX_H = 1200
local TITLE_H    = 30
local FILTER_H   = 26
local BTN_H      = 24
local ROW_H      = 24
local VISIBLE    = 18    -- display-line slots visible at once (an entry with
                          -- two lines -- see BuildDisplayLines -- uses two of these);
                          -- mutable -- EnsureRowCapacity grows/shrinks it to fit the
                          -- window's current height (see below)
local MAX_VISIBLE = 60   -- hard cap on row frames, however tall the window gets
local PAD        = 10

-- Column widths default here but are mutable and persisted (GuildLogDB.ui.columns)
-- once the user drags a column divider -- see RestoreColumns/SaveColumns.
local DEFAULT_COL_TIME_W   = 145
local DEFAULT_COL_TYPE_W   = 110
local DEFAULT_COL_PLAYER_W = 132
local COL_MIN_W = 50
local colTimeW, colTypeW, colPlayerW = DEFAULT_COL_TIME_W, DEFAULT_COL_TYPE_W, DEFAULT_COL_PLAYER_W

-- Theme -- dark panels with a gold/bronze accent, consistent across the
-- window chrome, list panel, and buttons instead of mixing custom dark
-- panels with Blizzard's stock red/parchment widgets.
local THEME_BORDER = { 0.6, 0.5, 0.2 }
local THEME_GOLD   = { 0.9, 0.8, 0.5 }

-- Colors per event type
local TYPE_COLORS = {
    INVITE  = "|cff00cc44",   -- green
    JOIN    = "|cff44ff88",   -- lighter green
    REMOVE  = "|cffcc2222",   -- red
    LEAVE   = "|cffff8800",   -- orange
    PROMOTE = "|cff88ccff",   -- sky blue
    DEMOTE  = "|cffcc88ff",   -- purple
    NOTE    = "|cffffdd44",   -- yellow
    ONOTE   = "|cffffaa22",   -- amber
}
-- Shorter labels for the narrow Event column; GuildLog.EVENT_LABELS stays
-- unabbreviated since search/filter logic elsewhere reads off it too.
local TYPE_COLUMN_LABEL = {
    ONOTE = "Officer Note",
    NOTE  = "Note",
}
local COLOR_RESET   = "|r"
local COLOR_ACTOR   = "|cffffff88"
local COLOR_TARGET  = "|cffffffff"
local COLOR_RANK    = "|cffaaaaaa"
local COLOR_UNKNOWN = "|cff666666(unknown)|r"

-- Converts a "|cffRRGGBB" color code to 0-1 RGB floats. Falls back to white.
local function HexToRGB(colorCode)
    local hex = colorCode and colorCode:match("|cff(%x%x%x%x%x%x)") or "ffffff"
    return tonumber(hex:sub(1, 2), 16) / 255,
           tonumber(hex:sub(3, 4), 16) / 255,
           tonumber(hex:sub(5, 6), 16) / 255
end

local function SolidBackdrop()
    return {
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    }
end

-- == State =====================================================================

local mainFrame   = nil
local rowFrames   = {}
local scrollBar   = nil
local statusText  = nil

local activeFilters = {
    INVITE  = true,
    JOIN    = true,
    REMOVE  = true,
    LEAVE   = true,
    PROMOTE = true,
    DEMOTE  = true,
    NOTE    = true,
    ONOTE   = true,
}
-- Each filter chip's UpdateAppearance, so clicking one chip (which can change
-- every chip's active state -- see CreateFilterButton) can refresh them all.
local filterRefreshers = {}
local function RefreshFilterButtons()
    for _, fn in ipairs(filterRefreshers) do fn() end
end

local searchText   = ""
local filteredList = {}  -- entries matching the current filter/search
local displayRows  = {}  -- filteredList flattened into 1-2 display lines each
local scrollOffset = 0

-- == Display line builder ======================================================
-- Each entry renders as one or two lines: the first carries Time/Event/Player,
-- any second line is an indented, dimmed continuation showing extra detail
-- (who performed a rank change, or the "new" half of a note edit) -- similar
-- to how Guild Roster Manager's log breaks a single change across two lines
-- instead of cramming everything into one.

local function BuildDisplayLines(entry)
    local player  -- always set below, in every branch
    local lines = {}

    if entry.type == "INVITE" then
        player = entry.target ~= "" and entry.target or ""
        local by = entry.actor ~= "" and (COLOR_ACTOR .. entry.actor .. COLOR_RESET) or COLOR_UNKNOWN
        lines[1] = { details = "Invited by " .. by }

    elseif entry.type == "JOIN" then
        player = entry.actor ~= "" and entry.actor or ""
        -- entry.target holds the inviter when known (folded in by ScanGuildLog
        -- so an accepted invite reads as one line instead of two).
        if entry.target ~= "" then
            lines[1] = { details = "Invited by " .. COLOR_ACTOR .. entry.target .. COLOR_RESET }
            lines[2] = { details = entry.rank ~= "" and ("Rank: " .. entry.rank) or "Joined the guild", dim = true }
        else
            lines[1] = { details = entry.rank ~= "" and ("Rank: " .. entry.rank) or "Joined the guild" }
        end

    elseif entry.type == "REMOVE" then
        player = entry.target ~= "" and entry.target or ""
        local by = entry.actor ~= "" and (COLOR_ACTOR .. entry.actor .. COLOR_RESET) or COLOR_UNKNOWN
        lines[1] = { details = "Kicked by " .. by }

    elseif entry.type == "LEAVE" then
        player = entry.actor ~= "" and entry.actor or ""
        lines[1] = { details = "Left the guild" }

    elseif entry.type == "PROMOTE" or entry.type == "DEMOTE" then
        player = entry.target ~= "" and entry.target or ""
        local oldRank = entry.rank    ~= "" and entry.rank    or "?"
        local newRank = entry.newRank ~= "" and entry.newRank or "?"
        lines[1] = { details = COLOR_RANK .. oldRank .. COLOR_RESET .. "  ->  " .. COLOR_RANK .. newRank .. COLOR_RESET }
        if entry.actor ~= "" then
            lines[2] = { details = "by " .. COLOR_ACTOR .. entry.actor .. COLOR_RESET, dim = true }
        end

    elseif entry.type == "NOTE" or entry.type == "ONOTE" then
        player = entry.actor ~= "" and entry.actor or ""
        local oldNote = entry.rank    ~= "" and entry.rank    or "(empty)"
        local newNote = entry.newRank ~= "" and entry.newRank or "(empty)"
        lines[1] = { details = "Old: " .. COLOR_RANK .. oldNote .. COLOR_RESET }
        lines[2] = { details = "New: " .. COLOR_RANK .. newNote .. COLOR_RESET, dim = true }

    else
        player = entry.target ~= "" and entry.target or ""
        lines[1] = { details = "" }
    end

    return player, lines
end

-- == Filtering ==================================================================

local function RebuildList()
    filteredList = {}
    local search = searchText:lower()

    for _, entry in ipairs(GuildLogDB and GuildLogDB.entries or {}) do
        if activeFilters[entry.type] then
            local match = true
            if search ~= "" then
                local combined = (entry.actor .. entry.target .. entry.rank .. entry.newRank):lower()
                if not combined:find(search, 1, true) then
                    match = false
                end
            end
            if match then
                filteredList[#filteredList + 1] = entry
            end
        end
    end

    table.sort(filteredList, function(a, b) return a.timestamp > b.timestamp end)

    displayRows = {}
    for ei, entry in ipairs(filteredList) do
        local player, lines = BuildDisplayLines(entry)
        local zebra = (ei % 2 == 0)
        for li, line in ipairs(lines) do
            displayRows[#displayRows + 1] = {
                entry   = entry,
                player  = (li == 1) and player or "",
                details = line.details,
                dim     = line.dim,
                isFirst = (li == 1),
                isLast  = (li == #lines),
                zebra   = zebra,
            }
        end
    end

    scrollOffset = 0
    UI.RefreshRows()
end

-- == Row rendering ==============================================================

function UI.RefreshRows()
    if not mainFrame or not mainFrame:IsShown() then return end

    local total = #displayRows
    local maxOffset = math.max(0, total - VISIBLE)
    scrollOffset = math.max(0, math.min(scrollOffset, maxOffset))

    if scrollBar then
        scrollBar:SetMinMaxValues(0, maxOffset)
        scrollBar:SetValue(scrollOffset)
        if scrollBar.thumb then
            local trackH = scrollBar:GetHeight()
            if trackH and trackH > 0 then
                local ratio = math.min(1, VISIBLE / math.max(total, VISIBLE))
                scrollBar.thumb:SetHeight(math.max(24, trackH * ratio))
            end
        end
    end

    for i = 1, VISIBLE do
        local row = rowFrames[i]
        local idx = scrollOffset + i
        if idx <= total then
            local dr = displayRows[idx]
            local entry = dr.entry
            local r, g, b = HexToRGB(TYPE_COLORS[entry.type])

            if dr.isFirst then
                row.timeText:SetText(GuildLog.FormatTimestamp(entry.timestamp))
                row.typeText:SetText(TYPE_COLUMN_LABEL[entry.type] or GuildLog.EVENT_LABELS[entry.type] or entry.type)
                row.typeText:SetTextColor(r, g, b)
                row.playerText:SetText(dr.player ~= "" and (COLOR_TARGET .. dr.player .. COLOR_RESET) or COLOR_UNKNOWN)
            else
                row.timeText:SetText("")
                row.typeText:SetText("")
                row.playerText:SetText("")
            end

            row.detailsText:SetFontObject(dr.dim and GameFontDisable or GameFontHighlight)
            row.detailsText:SetText(dr.details or "")

            row.accent:SetColorTexture(r, g, b, dr.isFirst and 0.85 or 0.35)
            row.bg:SetColorTexture(r, g, b, dr.zebra and 0.05 or 0.02)
            row.divider:SetAlpha(dr.isLast and 1.0 or 0.0)
            row:Show()
        else
            row.timeText:SetText("")
            row.typeText:SetText("")
            row.playerText:SetText("")
            row.detailsText:SetText("")
            row.accent:SetColorTexture(0, 0, 0, 0)
            row.bg:SetColorTexture(0, 0, 0, 0)
            row.divider:SetAlpha(0.0)
            row:Show()
        end
    end

    if statusText then
        local n = #(GuildLogDB and GuildLogDB.entries or {})
        statusText:SetText("Showing " .. #filteredList .. " / " .. n .. " entries")
    end
end

-- == Reusable themed widgets ====================================================

-- eventTypes may be a single string or an array of strings.
-- All types in the array toggle together; appearance tracks the first.
-- Chips are colored by event type so they read at a glance and match the
-- accent bar used in the rows.
--
-- Clicking a chip solos it: only its type(s) show, everything else hides.
-- Clicking the currently-soloed chip again restores every filter to active
-- (shift-click adds/removes just this chip from the current set, for
-- combining a few types without giving up the rest).
local function CreateFilterButton(parent, label, eventTypes, x, y, width)
    local types = type(eventTypes) == "table" and eventTypes or { eventTypes }
    local r, g, b = HexToRGB(TYPE_COLORS[types[1]])

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, FILTER_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetBackdrop(SolidBackdrop())

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(label)

    local function UpdateAppearance()
        local active = activeFilters[types[1]]
        btn:SetBackdropColor(r, g, b, active and 0.30 or 0.05)
        btn:SetBackdropBorderColor(r, g, b, active and 1.0 or 0.30)
        text:SetTextColor(r, g, b, active and 1.0 or 0.55)
    end
    filterRefreshers[#filterRefreshers + 1] = UpdateAppearance

    btn:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            local newVal = not activeFilters[types[1]]
            for _, t in ipairs(types) do
                activeFilters[t] = newVal
            end
        else
            local isSolo = true
            for t, active in pairs(activeFilters) do
                local inGroup = false
                for _, myType in ipairs(types) do
                    if t == myType then inGroup = true break end
                end
                if active ~= inGroup then isSolo = false break end
            end

            if isSolo then
                for t in pairs(activeFilters) do activeFilters[t] = true end
            else
                for t in pairs(activeFilters) do activeFilters[t] = false end
                for _, t in ipairs(types) do activeFilters[t] = true end
            end
        end
        RefreshFilterButtons()
        RebuildList()
    end)
    btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(r, g, b, 1.0) end)
    btn:SetScript("OnLeave", UpdateAppearance)

    UpdateAppearance()
    return btn
end

-- Gold-on-dark action button, replacing the stock red UIPanelButtonTemplate
-- so the bottom bar matches the rest of the window's theme.
local function CreateActionButton(parent, label, x, width, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, BTN_H)
    btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, PAD)
    btn:SetBackdrop(SolidBackdrop())
    btn:SetBackdropColor(0.15, 0.13, 0.08, 0.9)
    btn:SetBackdropBorderColor(THEME_BORDER[1], THEME_BORDER[2], THEME_BORDER[3], 0.7)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(label)
    text:SetTextColor(THEME_GOLD[1], THEME_GOLD[2], THEME_GOLD[3])

    btn:SetScript("OnEnter", function()
        btn:SetBackdropBorderColor(1.0, 0.85, 0.35, 1.0)
        btn:SetBackdropColor(0.22, 0.19, 0.10, 0.95)
    end)
    btn:SetScript("OnLeave", function()
        btn:SetBackdropBorderColor(THEME_BORDER[1], THEME_BORDER[2], THEME_BORDER[3], 0.7)
        btn:SetBackdropColor(0.15, 0.13, 0.08, 0.9)
    end)
    btn:SetScript("OnClick", onClick)

    return btn
end

-- == Position persistence ========================================================
-- Stored directly in GuildLogDB rather than through AceGUI's status-table
-- convention, since the window is no longer an AceGUI widget.

local function RestorePosition()
    local pos = GuildLogDB.ui and GuildLogDB.ui.pos
    mainFrame:ClearAllPoints()
    if pos and pos.point then
        mainFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function SavePosition()
    local point, _, relPoint, x, y = mainFrame:GetPoint(1)
    GuildLogDB.ui = GuildLogDB.ui or {}
    GuildLogDB.ui.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

-- == Size persistence ==========================================================
-- GuildLogDB.ui.width/height predate the custom-frame rewrite (an older
-- AceGUI-backed version saved size through its own status table using those
-- same field names) -- reused here rather than introducing new fields.

local function RestoreSize()
    local ui = GuildLogDB.ui
    local w = (ui and ui.width)  or WINDOW_W
    local h = (ui and ui.height) or WINDOW_H
    w = math.max(WINDOW_MIN_W, math.min(WINDOW_MAX_W, w))
    h = math.max(WINDOW_MIN_H, math.min(WINDOW_MAX_H, h))
    mainFrame:SetSize(w, h)
end

local function SaveSize()
    GuildLogDB.ui = GuildLogDB.ui or {}
    GuildLogDB.ui.width  = mainFrame:GetWidth()
    GuildLogDB.ui.height = mainFrame:GetHeight()
end

-- == Column width persistence ==================================================

local function RestoreColumns()
    local cols = GuildLogDB.ui and GuildLogDB.ui.columns
    colTimeW   = (cols and cols.time)   or DEFAULT_COL_TIME_W
    colTypeW   = (cols and cols.type)   or DEFAULT_COL_TYPE_W
    colPlayerW = (cols and cols.player) or DEFAULT_COL_PLAYER_W
end

local function SaveColumns()
    GuildLogDB.ui = GuildLogDB.ui or {}
    GuildLogDB.ui.columns = { time = colTimeW, type = colTypeW, player = colPlayerW }
end

-- == Main frame construction ====================================================

local function BuildUI()
    if mainFrame then return end

    GuildLogDB.ui = GuildLogDB.ui or {}

    mainFrame = CreateFrame("Frame", "GuildLogMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    mainFrame:SetResizeBounds(WINDOW_MIN_W, WINDOW_MIN_H, WINDOW_MAX_W, WINDOW_MAX_H)
    mainFrame:SetBackdrop(SolidBackdrop())
    mainFrame:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
    mainFrame:SetBackdropBorderColor(THEME_BORDER[1], THEME_BORDER[2], THEME_BORDER[3], 0.9)
    RestorePosition()
    RestoreSize()
    RestoreColumns()
    mainFrame:Hide()

    local content = mainFrame

    -- -- Title bar --
    local titleBar = CreateFrame("Frame", nil, content)
    titleBar:SetHeight(TITLE_H)
    titleBar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        SavePosition()
    end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(THEME_BORDER[1], THEME_BORDER[2], THEME_BORDER[3], 0.18)

    local titleDivider = content:CreateTexture(nil, "ARTWORK")
    titleDivider:SetHeight(1)
    titleDivider:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -TITLE_H)
    titleDivider:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -TITLE_H)
    titleDivider:SetColorTexture(THEME_BORDER[1], THEME_BORDER[2], THEME_BORDER[3], 0.6)

    local titleLabel = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLabel:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleLabel:SetText("Guild Log")
    titleLabel:SetTextColor(THEME_GOLD[1], THEME_GOLD[2], THEME_GOLD[3])

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    closeText:SetTextColor(0.8, 0.75, 0.65)
    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1.0, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.8, 0.75, 0.65) end)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- -- Filter buttons --
    local filterY = -(TITLE_H + PAD)
    local chipW, chipGap = 86, 94
    -- INVITE stays grouped in here for backward compat with entries logged
    -- before invites were folded into their join (see ScanGuildLog) -- new
    -- scans never create standalone INVITE entries anymore.
    CreateFilterButton(content, "Joins",       {"INVITE", "JOIN"}, PAD + chipGap*0, filterY, chipW)
    CreateFilterButton(content, "Removals",   "REMOVE",           PAD + chipGap*1, filterY, chipW)
    CreateFilterButton(content, "Leaves",     "LEAVE",            PAD + chipGap*2, filterY, chipW)
    CreateFilterButton(content, "Promotions", "PROMOTE",          PAD + chipGap*3, filterY, chipW)
    CreateFilterButton(content, "Demotions",  "DEMOTE",           PAD + chipGap*4, filterY, chipW)
    CreateFilterButton(content, "Notes",      {"NOTE", "ONOTE"},  PAD + chipGap*5, filterY, chipW)

    -- -- Search box --
    local searchBox = CreateFrame("EditBox", "GuildLogSearch", content, "SearchBoxTemplate")
    searchBox:SetSize(140, 20)
    searchBox:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, filterY - 2)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText()
        RebuildList()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- -- List panel --
    local listTop = filterY - FILTER_H - PAD  -- below filter buttons
    local bottomReserve = PAD + BTN_H + PAD

    local listPanel = CreateFrame("Frame", nil, content, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT",     content, "TOPLEFT",     PAD, listTop)
    listPanel:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -24, bottomReserve)
    listPanel:SetBackdrop(SolidBackdrop())
    listPanel:SetBackdropColor(0, 0, 0, 0.55)
    listPanel:SetBackdropBorderColor(THEME_BORDER[1], THEME_BORDER[2], THEME_BORDER[3], 0.6)

    -- Column headers -- each anchored to the previous one's right edge (like
    -- the row text below) so resizing a column only ever needs a SetWidth
    -- call; the anchor chain handles repositioning everything after it.
    local function AddHeader(text, anchorTo, w)
        local fs = listPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if anchorTo then
            fs:SetPoint("LEFT", anchorTo, "RIGHT", 6, 0)
        else
            fs:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -5)
        end
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(THEME_GOLD[1]*0.8, THEME_GOLD[2]*0.75, THEME_GOLD[3]*0.65)
        return fs
    end
    local headerTime   = AddHeader("Time",    nil,        colTimeW)
    local headerType   = AddHeader("Event",   headerTime, colTypeW)
    local headerPlayer = AddHeader("Player",  headerType, colPlayerW)
    AddHeader("Details", headerPlayer, 200)  -- fills remaining space; no resizer needed
    headerTime:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -5)  -- pin the chain's start

    local headerDivider = listPanel:CreateTexture(nil, "ARTWORK")
    headerDivider:SetHeight(1)
    headerDivider:SetPoint("TOPLEFT",  listPanel, "TOPLEFT",  2, -24)
    headerDivider:SetPoint("TOPRIGHT", listPanel, "TOPRIGHT", -2, -24)
    headerDivider:SetColorTexture(THEME_BORDER[1], THEME_BORDER[2], THEME_BORDER[3], 0.5)

    local rowsTop = -26  -- below the column header row, relative to listPanel

    -- Creates one row frame at slot i, anchored purely by index -- called both
    -- for the initial VISIBLE rows and later by EnsureRowCapacity as the
    -- window grows tall enough to fit more.
    local function CreateRow(i)
        local row = CreateFrame("Frame", nil, listPanel)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  listPanel, "TOPLEFT",  2, rowsTop - (i-1)*ROW_H)
        row:SetPoint("TOPRIGHT", listPanel, "TOPRIGHT", -2, rowsTop - (i-1)*ROW_H)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetWidth(3)
        row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

        -- Only shown under the last line of each entry (see dr.isLast), so
        -- multi-line entries read as one visually grouped block.
        row.divider = row:CreateTexture(nil, "ARTWORK")
        row.divider:SetHeight(1)
        row.divider:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  4, 0)
        row.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.divider:SetColorTexture(1, 1, 1, 0.08)

        row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        row.timeText:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.timeText:SetWidth(colTimeW)
        row.timeText:SetJustifyH("LEFT")
        row.timeText:SetWordWrap(false)

        row.typeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.typeText:SetPoint("LEFT", row.timeText, "RIGHT", 6, 0)
        row.typeText:SetWidth(colTypeW)
        row.typeText:SetJustifyH("LEFT")
        row.typeText:SetWordWrap(false)

        row.playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.playerText:SetPoint("LEFT", row.typeText, "RIGHT", 6, 0)
        row.playerText:SetWidth(colPlayerW)
        row.playerText:SetJustifyH("LEFT")
        row.playerText:SetWordWrap(false)

        row.detailsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.detailsText:SetPoint("LEFT", row.playerText, "RIGHT", 6, 0)
        row.detailsText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.detailsText:SetJustifyH("LEFT")
        row.detailsText:SetWordWrap(false)

        return row
    end

    for i = 1, VISIBLE do
        rowFrames[i] = CreateRow(i)
    end

    -- Applies the current colTimeW/colTypeW/colPlayerW to every header and
    -- row -- each element's anchor is relative to the previous one's right
    -- edge, so a width change alone repositions everything after it.
    local function RelayoutColumns()
        headerTime:SetWidth(colTimeW)
        headerType:SetWidth(colTypeW)
        headerPlayer:SetWidth(colPlayerW)
        for _, row in ipairs(rowFrames) do
            row.timeText:SetWidth(colTimeW)
            row.typeText:SetWidth(colTypeW)
            row.playerText:SetWidth(colPlayerW)
        end
    end

    -- Thin draggable divider between two columns. getW/setW read and write
    -- the column immediately to the divider's left; dragging right widens
    -- that column, dragging left narrows it, and the Details column (which
    -- has no divider of its own) simply absorbs whatever space is left.
    local function CreateColumnResizer(anchorTo, getW, setW)
        local handle = CreateFrame("Frame", nil, listPanel)
        handle:SetWidth(8)
        handle:SetPoint("TOP",    anchorTo, "TOPRIGHT", 3, 0)
        handle:SetPoint("BOTTOM", listPanel, "BOTTOM", 0, 0)
        handle:EnableMouse(true)

        local line = handle:CreateTexture(nil, "OVERLAY")
        line:SetWidth(1)
        line:SetPoint("TOP", handle, "TOP", 0, 0)
        line:SetPoint("BOTTOM", handle, "BOTTOM", 0, 0)
        line:SetColorTexture(THEME_GOLD[1], THEME_GOLD[2], THEME_GOLD[3], 0.25)

        handle:SetScript("OnEnter", function() line:SetAlpha(1.0) end)
        handle:SetScript("OnLeave", function() if not handle.dragging then line:SetAlpha(0.25) end end)

        handle:SetScript("OnMouseDown", function(self)
            self.dragging   = true
            self.startX     = GetCursorPosition()
            self.startWidth = getW()
            line:SetAlpha(1.0)
        end)
        handle:SetScript("OnMouseUp", function(self)
            self.dragging = false
            line:SetAlpha(0.25)
            SaveColumns()
        end)
        handle:SetScript("OnUpdate", function(self)
            if not self.dragging then return end
            local scale = listPanel:GetEffectiveScale()
            local delta = (GetCursorPosition() - self.startX) / scale
            setW(math.max(COL_MIN_W, self.startWidth + delta))
            RelayoutColumns()
        end)

        return handle
    end

    CreateColumnResizer(headerTime,   function() return colTimeW   end, function(w) colTimeW   = w end)
    CreateColumnResizer(headerType,   function() return colTypeW   end, function(w) colTypeW   = w end)
    CreateColumnResizer(headerPlayer, function() return colPlayerW end, function(w) colPlayerW = w end)

    -- Grows (never shrinks the frame count, just hides the excess) the row
    -- pool to fit however tall listPanel currently is, up to MAX_VISIBLE.
    local function EnsureRowCapacity()
        local available = listPanel:GetHeight() + rowsTop  -- rowsTop is negative
        local newVisible = math.max(1, math.min(MAX_VISIBLE, math.floor(available / ROW_H)))
        if newVisible > #rowFrames then
            for i = #rowFrames + 1, newVisible do
                rowFrames[i] = CreateRow(i)
            end
        end
        VISIBLE = newVisible
        for i = VISIBLE + 1, #rowFrames do
            rowFrames[i]:Hide()
        end
    end

    -- -- Scrollbar -- themed track + pill thumb instead of the stock Blizzard
    -- slider art, sized to the window's dark/gold look. Thumb height is
    -- resized in UI.RefreshRows to reflect how much of the log is visible.
    local scrollTrack = CreateFrame("Frame", nil, content, "BackdropTemplate")
    scrollTrack:SetWidth(8)
    scrollTrack:SetPoint("TOP",    content, "TOPRIGHT",    -14, listTop)
    scrollTrack:SetPoint("BOTTOM", content, "BOTTOMRIGHT", -14, bottomReserve)
    scrollTrack:SetBackdrop(SolidBackdrop())
    scrollTrack:SetBackdropColor(0, 0, 0, 0.5)
    scrollTrack:SetBackdropBorderColor(THEME_BORDER[1], THEME_BORDER[2], THEME_BORDER[3], 0.4)

    scrollBar = CreateFrame("Slider", "GuildLogScrollBar", scrollTrack)
    scrollBar:SetWidth(8)
    scrollBar:SetPoint("TOP",    scrollTrack, "TOP",    0, 0)
    scrollBar:SetPoint("BOTTOM", scrollTrack, "BOTTOM", 0, 0)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)

    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(THEME_GOLD[1], THEME_GOLD[2], THEME_GOLD[3], 0.85)
    thumb:SetWidth(8)
    thumb:SetHeight(30)
    scrollBar:SetThumbTexture(thumb)
    scrollBar.thumb = thumb

    scrollBar:SetScript("OnValueChanged", function(_, val)
        scrollOffset = math.floor(val + 0.5)
        UI.RefreshRows()
    end)

    mainFrame:EnableMouseWheel(true)
    mainFrame:SetScript("OnMouseWheel", function(_, delta)
        local cur = scrollBar:GetValue()
        local mn, mx = scrollBar:GetMinMaxValues()
        scrollBar:SetValue(math.max(mn, math.min(mx, cur - delta * 3)))
    end)

    -- -- Bottom bar: action buttons + status text --
    CreateActionButton(content, "Clear Log", PAD, 90, function()
        StaticPopupDialogs["GUILDLOG_CONFIRM_CLEAR"] = {
            text      = "Clear all stored Guild Log entries?",
            button1   = "Clear",
            button2   = "Cancel",
            OnAccept  = function()
                GuildLogDB.entries = {}
                RebuildList()
                GuildLog.ForceRescan()
                print("|cff00ccff[GuildLog]|r Log cleared.")
            end,
            timeout      = 0,
            whileDead    = false,
            hideOnEscape = true,
        }
        StaticPopup_Show("GUILDLOG_CONFIRM_CLEAR")
    end)

    CreateActionButton(content, "Refresh", PAD + 96, 90, function()
        RebuildList()
        GuildLog.ForceRescan()
    end)

    CreateActionButton(content, "Blizzard Log", PAD + 192, 110, function()
        GuildLog.OpenNativeLog()
    end)

    statusText = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    statusText:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PAD - 20, PAD + 6)

    -- -- Resize grip -- drag to resize the whole window. --
    local resizeGrip = CreateFrame("Button", nil, content)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -3, 3)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function()
        mainFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        SaveSize()
    end)

    mainFrame:SetScript("OnSizeChanged", function()
        EnsureRowCapacity()
        UI.RefreshRows()
    end)
    EnsureRowCapacity()

    -- Register with UISpecialFrames so Escape closes the window.
    -- CreateFrame's name argument already registers GuildLogMainFrame globally.
    table.insert(UISpecialFrames, "GuildLogMainFrame")
end

-- == Public API ==================================================================

function GuildLogUI_Open()
    BuildUI()
    RebuildList()
    mainFrame:Show()
end

function GuildLogUI_IsOpen()
    return mainFrame ~= nil and mainFrame:IsShown()
end

-- Called by GuildLog.lua when a new entry arrives while window is open
GuildLog.OnNewEntry = function(_)
    if mainFrame and mainFrame:IsShown() then
        RebuildList()
    end
end
