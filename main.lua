local Dispatcher = require("dispatcher") -- luacheck:ignore
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")
local Geom = require("ui/geometry")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/inputcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local ImageWidget = require("ui/widget/imagewidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local time = require("ui/time")

local T = require("ffi/util").template
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")

local speedko = WidgetContainer:extend({
    name = "speedko",
    is_doc_only = false,
    indicator_enabled = true,
})
local Device = require("device")
local Screen = Device.screen
function speedko:onDispatcherRegisterActions()
    Dispatcher:registerAction("speedko_action", {
        category = "none",
        event = "SpeedkoEvent",
        title = _("Speed Reading"),
        general = true,
    })
end

function speedko:init()
    if not self.settings then
        self:readSettingsFile()
    end
    self.pointer_enabled = false
    self.current_page = nil
    self.pointer_word_sec = 60.0 / 500
    self.pointer_mapped_page = nil
    self.pointer_type = "underscore"
    self.pointer_index = nil
    self.pointer_render_mode = "lazy" -- "lazy" "smart" "heavy"
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end
function speedko:readSettingsFile()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/speedko.lua")
end
function speedko:loadSettings()
    if not self.settings then
        self:readSettingsFile()
    end

    self.pointer_type = self.settings:readSetting("pointer_type")

    self.pointer_word_sec = tonumber(self.settings:readSetting("pointer_word_sec"))
end

function speedko:onReaderReady()
    self.view:registerViewModule("speedko_indicator", self)
    self:loadSettings()
    self:pointer() -- auto start pointer on doccument opened if it is enabled
end
function speedko:showSettingsDialog()
    self.settings_dialog = MultiInputDialog:new({
        title = _("Perception expander settings"),
        fields = {
            {
                text = "",
                input_type = "number",
                hint = T(_("Pointer speed in pwm. Current value: %1"), tonumber(60.0 / self.pointer_word_sec)),
            },
            {
                text = "",
                input_type = "string",
                hint = T(_("Type of pointer. Current value: " .. self.pointer_type)),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end,
                },
                {
                    text = _("Apply"),
                    callback = function()
                        self:saveSettings(self.settings_dialog:getFields())
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end,
                },
            },
        },
    })
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end
function speedko:saveSettings(fields)
    if fields then
        if fields[1] ~= "" and tonumber(fields[1]) > 0 then
            self.pointer_word_sec = 60.0 / tonumber(fields[1])
        end
        self.pointer_type = fields[2] ~= "" and fields[2] or self.pointer_type
    end

    self.settings:saveSetting("pointer_type", self.pointer_type)
    self.settings:saveSetting("pointer_word_sec", self.pointer_word_sec)
    self.settings:flush()
end

function dump(var, depth)
    depth = depth or 0
    local indent = string.rep("  ", depth)

    if type(var) == "table" then
        local s = "{\n"
        for k, v in pairs(var) do
            s = s .. indent .. "  [" .. tostring(k) .. "] = " .. dump(v, depth + 1) .. ",\n"
        end
        return s .. indent .. "}"
    elseif type(var) == "string" then
        return '"' .. var .. '"'
    else
        return tostring(var)
    end
end
function split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function speedko:mapWholePage(debug)
    debug = debug or false
    local pos0 = { x = 0, y = 0 }

    local x_pointer = self.ui.view.document:getWordFromPosition(pos0).pos0

    local text = {}
    while true do
        local current = self:getXPosAndPosition(x_pointer, debug)
        table.insert(text, current)

        x_pointer = self.ui.view.document:getNextVisibleWordStart(current.xPos.pos1)
        if x_pointer == nil or not self.ui.document:isXPointerInCurrentPage(x_pointer) then
            break
        end
        if not self.ui.document:isXPointerInCurrentPage(x_pointer) then
            current = self:getXPosAndPosition(x_pointer, debug)
            table.insert(text, current)
            break
        end
    end
    local result = {}
    if debug then
        for _, subtable in ipairs(text) do
            if subtable.text then -- Check if "a" exists
                table.insert(result, dump(subtable.text)) -- Add to result list
            end
        end
    end

    return text
end

-- Invoke Like this
--UIManager:nextTick(function()
--  if #value.box == 1 then
--      self:drawHighlight(value.box[1], "lighten", Blitbuffer.ColorRGB32(255, 0, 255, 0xFF * 0.5))
--  end
--end)

function speedko:drawHighlight(rects, type, color)
    if rects.x and rects.y and rects.w and rects.h then --if rectangles contain only one rectangle
        self.ui.view:drawHighlightRect(Screen.bb, 0, 0, rects, type, color)
        UIManager:setDirty(nil, "ui", rects, nil)
    else
        for _, rect in pairs(rects) do -- if multiple rectangles are present for example one word is split between lines because the line ends in the middle of this word
            if rect.x and rect.y and rect.w and rect.h then
                self.ui.view:drawHighlightRect(Screen.bb, 0, 0, rect, type, color)
            end
            rect.h = rect.h + 1 -- We need to refresh one pixel below so that underscores are rendered properly
            UIManager:setDirty(nil, "ui", rect, nil)
        end
    end
end
local function getScriptDirectory()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or "./"
end
function speedko:refreshRectangles(rects)
    for _, rect in pairs(rects) do -- if multiple rectangles are present for example one word is split between lines because the line ends in the middle of this word
        UIManager:setDirty(nil, "full", rect, nil)
    end
end
function speedko:addToMainMenu(menu_items)
    menu_items.speedko_menu = {
        text = _("Speed Reading Settings"),
        sorting_hint = "setting",
        sub_item_table = {
            {
                text = _("Start Pointer"),
                callback = function()
                    --local words = self:mapWholePage(true)
                    --UIManager:show(InfoMessage:new({
                    --    text = _("Speed reading settings menu"), -- Fixed: Added proper text
                    --}))
                    self.pointer_enabled = true

                    self:loadSettings()
                    self:pointer()
                end,
            },
            {
                text = _("Pointer settings"),
                callback = function()
                    self:showSettingsDialog()
                end,
            },
            -- UIManager:show(WidgetContainer:new({
            --     dimen = Geom:new({ w = 32, h = 32 }),
            --     icon,
            -- }))
            --self:set_indicator(getScriptDirectory() .. "icons/hourglass.svg", true)
            --self:createUI()
            ----UIManager:show(self)

            --UIManager:nextTick(function()
            --    for _, value in pairs(words) do
            --        if #value.box > 0 then
            --            self:drawHighlight(value.box, "invert")
            --        end
            --    end
            --end)
        },
    }
end

--Gets X Pointer and rectangle(s) of words from provided X Pointer use debug flag to log verbose responses
function speedko:getXPosAndPosition(lastPosX, debug)
    debug = debug or false

    -- Initialize the return table
    local NextWord = {
        xPos = {},
        box = {},
        text = {},
    }

    -- Get X Pointers error checking
    NextWord.xPos.pos0 = lastPosX
    NextWord.xPos.pos1 = self.ui.view.document:getNextVisibleWordEnd(NextWord.xPos.pos0)

    if debug then
        logger.dbg(
            "Lortey Word Xpos "
                .. NextWord.xPos.pos0
                .. " "
                .. self.ui.view.document:getTextFromXPointer(NextWord.xPos.pos0)
                .. " "
                .. NextWord.xPos.pos1
                .. " "
                .. self.ui.view.document:getTextFromXPointer(NextWord.xPos.pos1)
                .. " "
                .. self.ui.view.document:compareXPointers(NextWord.xPos.pos0, NextWord.xPos.pos1)
        )
    end

    NextWord.box = self.ui.view.document:getScreenBoxesFromPositions(NextWord.xPos.pos0, NextWord.xPos.pos1, not debug)
    if debug then
        logger.dbg("Lortey Word Boxes " .. dump(NextWord.box))
    end

    NextWord.text = self.ui.view.document:getTextFromXPointers(NextWord.xPos.pos0, NextWord.xPos.pos1, debug)

    if debug then
        logger.dbg("Lortey Text Xpointers " .. NextWord.text)
    end

    return NextWord
end

function speedko:paintTo(bb, x, y)
    if self.indicator_enabled and self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

function speedko:set_indicator(icon_name, transparent)
    transparent = transparent or false
    local icon_size = Screen:scaleBySize(32)

    self.icon = ImageWidget:new({
        file = icon_name,
        width = icon_size,
        height = icon_size,
        alpha = transparent,
    })
end
function speedko:createUI()
    local icon_size = Screen:scaleBySize(32)
    if self.icon then
        self[1] = LeftContainer:new({
            dimen = Geom:new({
                x = 0,
                y = 0,
                w = icon_size,
                h = icon_size,
            }),

            self.icon,
        })
    end
end
function speedko:onPageUpdate(pageno)
    self:loadSettings()
    self:pointer()
end
function speedko:pointer()
    local enter_time = time.now()
    if self.pointer_enabled and self.ui.document ~= nil then
        if self.ui:getCurrentPage() ~= self.current_page then
            self.current_page = self.ui:getCurrentPage()
            self.pointer_mapped_page = self:mapWholePage(false)
            self.pointer_index = 0
        end
        local a = self.pointer_index -- copy to avoid value change before nexttick is invoked

        if #self.pointer_mapped_page >= self.pointer_index then
            UIManager:nextTick(function()
                if self.pointer_mapped_page[a] ~= nil and #self.pointer_mapped_page[a].box > 0 then
                    self:drawHighlight(self.pointer_mapped_page[a].box, self.pointer_type)
                end

                --refresh the previous word's highlight
            end)

            --advance pointer
            self.pointer_index = self.pointer_index + 1

            local time_schedule_in = self.pointer_word_sec - time.since(enter_time) -- take time of execution into account
            logger.dbg(
                "Lortey execution time "
                    .. time.now()
                    .. " "
                    .. time.since(enter_time)
                    .. " next in "
                    .. time_schedule_in
            )
            if time_schedule_in < 0 then -- prevent negative time
                UIManager:scheduleIn(self.pointer_word_sec, function() --not zero to prevent crash on kindle
                    self:pointer()
                end)
            else
                UIManager:scheduleIn(time_schedule_in, function()
                    self:pointer()
                end)
            end
        end

        --for some reason refreshing does not work
        --if self.pointer_index > 0 and self.pointer_mapped_page[a] ~= nil then
        --    if #self.pointer_mapped_page[a].box > 0 then
        --        UIManager:scheduleIn(time_schedule_in, function()
        --            logger.dbg("Lortey REFRESHEDPREVIOUS")
        --            for _, rect in pairs(self.pointer_mapped_page[a].box) do -- if multiple rectangles are present for example one word is split between lines because the line ends in the middle of this word
        --                UIManager:setDirty(self.ui.highlight.dialog, "ui", rect)
        --            end
        --        end)
        --    end --apply highlight to current word
        --end
    end
end
return speedko
