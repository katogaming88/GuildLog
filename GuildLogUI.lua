-- GuildLogUI.lua
-- Scrollable log window with filter buttons, built on AceGUI-3.0 Frame

local UI = {}
GuildLogUI = UI

-- ── Constants ────────────────────────────────────────────────────────────────

local WINDOW_W   = 620
local WINDOW_H   = 480   -- extra height accommodates AceGUI title/status chrome
local ROW_H      = 18
local VISIBLE    = 18    -- rows visible at once
local PAD        = 10

-- Colors per event type
local TYPE_COLORS = {
    INVITE  = "|cff00cc44",   -- green
    REMOVE  = "|cffcc2222",   -- red
    LEAVE   = "|cffff8800",   -- orange
    PROMOTE = "|cff88ccff",   -- sky blue
    DEMOTE  = "|cffcc88ff",   -- purple
}
local COLOR_RESET  = "|r"
local COLOR_TS     = "|cff888888"
local COLOR_ACTOR  = "|cffffff88"
local COLOR_TARGET = "|cffffffff"
local COLOR_RANK   = "|cffaaaaaa"

-- ── State ────────────────────────────────────────────────────────────────────

local aceFrame    = nil
local mainFrame   = nil
local rowFrames   = {}
local scrollBar   = nil

local activeFilters = {
    INVITE  = true,
    REMOVE  = true,
    LEAVE   = true,
    PROMOTE = true,
    DEMOTE  = true,
}

local searchText   = ""
local filteredList = {}  -- current view
local scrollOffset = 0

-- ── Row text builder ─────────────────────────────────────────────────────────

local function BuildRowText(entry)
    local ts    = COLOR_TS .. GuildLog.FormatTimestamp(entry.timestamp) .. COLOR_RESET
    local label = GuildLog.EVENT_LABELS[entry.type] or entry.type
    local color = TYPE_COLORS[entry.type] or "|cffffffff"

    local actor  = entry.actor  ~= "" and (COLOR_ACTOR  .. entry.actor  .. COLOR_RESET) or nil
    local target = entry.target ~= "" and (COLOR_TARGET .. entry.target .. COLOR_RESET) or nil

    local msg
    if entry.type == "INVITE" then
        msg = (actor or "(unknown)") .. color .. " invited " .. COLOR_RESET .. (target or "(unknown)")
    elseif entry.type == "REMOVE" then
        msg = (actor or "(unknown)") .. color .. " kicked " .. COLOR_RESET .. (target or "(unknown)")
    elseif entry.type == "LEAVE" then
        msg = (actor or "(unknown)") .. color .. " left the guild" .. COLOR_RESET
    elseif entry.type == "PROMOTE" then
        local rank = entry.newRank ~= "" and (COLOR_RANK .. " -> " .. entry.newRank .. COLOR_RESET) or ""
        msg = (actor or "(unknown)") .. color .. " promoted " .. COLOR_RESET .. (target or "(unknown)") .. rank
    elseif entry.type == "DEMOTE" then
        local rank = entry.newRank ~= "" and (COLOR_RANK .. " -> " .. entry.newRank .. COLOR_RESET) or ""
        msg = (actor or "(unknown)") .. color .. " demoted " .. COLOR_RESET .. (target or "(unknown)") .. rank
    else
        msg = color .. label .. COLOR_RESET .. " " .. (target or "")
    end

    return ts .. "  " .. msg
end

-- ── Filtering ────────────────────────────────────────────────────────────────

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

    scrollOffset = 0
    UI.RefreshRows()
end

-- ── Row rendering ────────────────────────────────────────────────────────────

function UI.RefreshRows()
    if not mainFrame or not mainFrame:IsShown() then return end

    local total = #filteredList
    local maxOffset = math.max(0, total - VISIBLE)
    scrollOffset = math.max(0, math.min(scrollOffset, maxOffset))

    if scrollBar then
        scrollBar:SetMinMaxValues(0, maxOffset)
        scrollBar:SetValue(scrollOffset)
    end

    for i = 1, VISIBLE do
        local row = rowFrames[i]
        local idx = scrollOffset + i
        if idx <= total then
            row.text:SetText(BuildRowText(filteredList[idx]))
            row:Show()
            if i % 2 == 0 then
                row.bg:SetColorTexture(0.08, 0.08, 0.12, 0.4)
            else
                row.bg:SetColorTexture(0, 0, 0, 0)
            end
        else
            row.text:SetText("")
            row.bg:SetColorTexture(0, 0, 0, 0)
            row:Show()
        end
    end

    if aceFrame then
        local n = #(GuildLogDB and GuildLogDB.entries or {})
        aceFrame:SetStatusText("Showing " .. total .. " / " .. n .. " entries")
    end
end

-- ── Main frame construction ───────────────────────────────────────────────────

local function CreateFilterButton(parent, label, eventType, x, y)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(72, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetText(label)

    local function UpdateAppearance()
        if activeFilters[eventType] then
            btn:SetAlpha(1.0)
        else
            btn:SetAlpha(0.35)
        end
    end

    btn:SetScript("OnClick", function()
        activeFilters[eventType] = not activeFilters[eventType]
        UpdateAppearance()
        RebuildList()
    end)

    UpdateAppearance()
    return btn
end

local function BuildUI()
    if mainFrame then return end

    local AceGUI = LibStub("AceGUI-3.0")

    aceFrame = AceGUI:Create("Frame")
    aceFrame:SetTitle("Guild Log")
    aceFrame:SetWidth(WINDOW_W)
    aceFrame:SetHeight(WINDOW_H)
    aceFrame:EnableResize(false)
    aceFrame:SetCallback("OnClose", function(widget) widget:Hide() end)

    -- Route position tracking through GuildLogDB so it persists across sessions.
    -- AceGUI writes top/left into this table on drag-stop and restores from it on open.
    GuildLogDB.ui = GuildLogDB.ui or {}
    aceFrame:SetStatusTable(GuildLogDB.ui)

    aceFrame:Hide()

    mainFrame = aceFrame.frame
    local content = aceFrame.content

    -- ── Filter buttons ───────────────────────────────────────────────────────
    local filterY = -PAD
    CreateFilterButton(content, "Invites",    "INVITE",  PAD,      filterY)
    CreateFilterButton(content, "Removals",   "REMOVE",  PAD+78,   filterY)
    CreateFilterButton(content, "Leaves",     "LEAVE",   PAD+156,  filterY)
    CreateFilterButton(content, "Promotions", "PROMOTE", PAD+234,  filterY)
    CreateFilterButton(content, "Demotions",  "DEMOTE",  PAD+312,  filterY)

    -- ── Search box ───────────────────────────────────────────────────────────
    local searchBox = CreateFrame("EditBox", "GuildLogSearch", content, "SearchBoxTemplate")
    searchBox:SetSize(140, 20)
    searchBox:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -PAD-2)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText()
        RebuildList()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- ── Scroll area ──────────────────────────────────────────────────────────
    local listTop = -(PAD + 22 + PAD)  -- below filter buttons

    local listBg = content:CreateTexture(nil, "BACKGROUND")
    listBg:SetColorTexture(0, 0, 0, 0.5)
    listBg:SetPoint("TOPLEFT",     content, "TOPLEFT",     PAD, listTop)
    listBg:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -24, PAD + 22 + PAD)

    for i = 1, VISIBLE do
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD, listTop - (i-1)*ROW_H)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -24, listTop - (i-1)*ROW_H)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("LEFT",  row, "LEFT",  4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        rowFrames[i] = row
    end

    -- ── Scrollbar ────────────────────────────────────────────────────────────
    scrollBar = CreateFrame("Slider", "GuildLogScrollBar", content)
    scrollBar:SetWidth(16)
    scrollBar:SetPoint("TOPRIGHT",    content, "TOPRIGHT",    -4, listTop)
    scrollBar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, PAD + 22 + PAD)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    local thumb = scrollBar:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Vertical")
    thumb:SetSize(16, 32)
    scrollBar:SetThumbTexture(thumb)
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

    -- ── Bottom buttons ───────────────────────────────────────────────────────
    local clearBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", PAD, PAD)
    clearBtn:SetText("Clear Log")
    clearBtn:SetScript("OnClick", function()
        StaticPopupDialogs["GUILDLOG_CONFIRM_CLEAR"] = {
            text      = "Clear all stored Guild Log entries?",
            button1   = "Clear",
            button2   = "Cancel",
            OnAccept  = function()
                GuildLogDB.entries = {}
                RebuildList()
                print("|cff00ccff[GuildLog]|r Log cleared.")
            end,
            timeout      = 0,
            whileDead    = false,
            hideOnEscape = true,
        }
        StaticPopup_Show("GUILDLOG_CONFIRM_CLEAR")
    end)

    local refreshBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", PAD+86, PAD)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        RebuildList()
    end)

    local blizzBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    blizzBtn:SetSize(90, 22)
    blizzBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", PAD+172, PAD)
    blizzBtn:SetText("Blizzard Log")
    blizzBtn:SetScript("OnClick", function()
        GuildLog.OpenNativeLog()
    end)

    -- Register with UISpecialFrames so Escape closes the window
    _G["GuildLogMainFrame"] = mainFrame
    table.insert(UISpecialFrames, "GuildLogMainFrame")
end

-- ── Public API ────────────────────────────────────────────────────────────────

function GuildLogUI_Open()
    BuildUI()
    RebuildList()
    aceFrame:Show()
end

-- Called by GuildLog.lua when a new entry arrives while window is open
GuildLog.OnNewEntry = function(_)
    if mainFrame and mainFrame:IsShown() then
        RebuildList()
    end
end
