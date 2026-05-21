-- GuildLogUI.lua
-- Scrollable log window with filter buttons and real timestamps

local UI = {}
GuildLogUI = UI

-- ── Constants ────────────────────────────────────────────────────────────────

local WINDOW_W   = 620
local WINDOW_H   = 440
local ROW_H      = 18
local VISIBLE    = 20   -- rows visible at once
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
        msg = (actor or "?") .. color .. " invited " .. COLOR_RESET .. (target or "?")
    elseif entry.type == "REMOVE" then
        msg = (actor or "?") .. color .. " kicked " .. COLOR_RESET .. (target or "?")
    elseif entry.type == "LEAVE" then
        msg = (target or "?") .. color .. " left the guild" .. COLOR_RESET
    elseif entry.type == "PROMOTE" then
        local rank = entry.newRank ~= "" and (COLOR_RANK .. " → " .. entry.newRank .. COLOR_RESET) or ""
        msg = (actor or "?") .. color .. " promoted " .. COLOR_RESET .. (target or "?") .. rank
    elseif entry.type == "DEMOTE" then
        local rank = entry.newRank ~= "" and (COLOR_RANK .. " → " .. entry.newRank .. COLOR_RESET) or ""
        msg = (actor or "?") .. color .. " demoted " .. COLOR_RESET .. (target or "?") .. rank
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
    -- Clamp offset
    local maxOffset = math.max(0, total - VISIBLE)
    scrollOffset = math.max(0, math.min(scrollOffset, maxOffset))

    -- Update scrollbar
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
            -- Alternate row backgrounds
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

    -- Entry count label
    if UI.countLabel then
        UI.countLabel:SetText("Showing " .. total .. " / " .. #(GuildLogDB and GuildLogDB.entries or {}) .. " entries")
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

    -- Main window
    mainFrame = CreateFrame("Frame", "GuildLogMainFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(WINDOW_W, WINDOW_H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    mainFrame.TitleText:SetText("Guild Log")

    -- ── Filter buttons ───────────────────────────────────────────────────────
    local filterY = -30
    CreateFilterButton(mainFrame, "Invites",   "INVITE",  PAD,      filterY)
    CreateFilterButton(mainFrame, "Removals",  "REMOVE",  PAD+78,   filterY)
    CreateFilterButton(mainFrame, "Leaves",    "LEAVE",   PAD+156,  filterY)
    CreateFilterButton(mainFrame, "Promotions","PROMOTE", PAD+234,  filterY)
    CreateFilterButton(mainFrame, "Demotions", "DEMOTE",  PAD+312,  filterY)

    -- ── Search box ───────────────────────────────────────────────────────────
    local searchBox = CreateFrame("EditBox", "GuildLogSearch", mainFrame, "SearchBoxTemplate")
    searchBox:SetSize(140, 20)
    searchBox:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -30, filterY - 2)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText()
        RebuildList()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- ── Entry count label ────────────────────────────────────────────────────
    UI.countLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.countLabel:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -30, filterY - 28)
    UI.countLabel:SetTextColor(0.5, 0.5, 0.5)

    -- ── Scroll area ──────────────────────────────────────────────────────────
    local listTop = -62

    local listBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetColorTexture(0, 0, 0, 0.5)
    listBg:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  PAD,  listTop)
    listBg:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -30, PAD + 4)

    -- Rows
    for i = 1, VISIBLE do
        local row = CreateFrame("Frame", nil, mainFrame)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  PAD, listTop - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -30, listTop - (i - 1) * ROW_H)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        rowFrames[i] = row
    end

    -- Scrollbar
    scrollBar = CreateFrame("Slider", "GuildLogScrollBar", mainFrame, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -8, listTop - 16)
    scrollBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -8, PAD + 20)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    scrollBar:SetScript("OnValueChanged", function(_, val)
        scrollOffset = math.floor(val + 0.5)
        UI.RefreshRows()
    end)

    -- Mouse wheel scrolling
    mainFrame:EnableMouseWheel(true)
    mainFrame:SetScript("OnMouseWheel", function(_, delta)
        local cur = scrollBar:GetValue()
        local mn, mx = scrollBar:GetMinMaxValues()
        scrollBar:SetValue(math.max(mn, math.min(mx, cur - delta * 3)))
    end)

    -- ── Bottom bar ───────────────────────────────────────────────────────────
    local clearBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", PAD, PAD)
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
            timeout   = 0,
            whileDead = false,
            hideOnEscape = true,
        }
        StaticPopup_Show("GUILDLOG_CONFIRM_CLEAR")
    end)

    local refreshBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", PAD + 86, PAD)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        RebuildList()
    end)

    -- Close with Escape
    table.insert(UISpecialFrames, "GuildLogMainFrame")
end

-- ── Public API ────────────────────────────────────────────────────────────────

function GuildLogUI_Open()
    BuildUI()
    RebuildList()
    mainFrame:Show()
end

-- Called by GuildLog.lua when a new entry arrives while window is open
GuildLog.OnNewEntry = function(_)
    if mainFrame and mainFrame:IsShown() then
        RebuildList()
    end
end
