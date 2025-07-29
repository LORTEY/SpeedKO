local Dispatcher = require("dispatcher") -- luacheck:ignore
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")
local Geom = require("ui/geometry")
local LeftContainer = require("ui/widget/container/inputcontainer")

local ImageWidget = require("ui/widget/imagewidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
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
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("speedko_indicator", self)
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
    end
    local result = {}
    if debug then
        for _, subtable in ipairs(text) do
            if subtable.text then -- Check if "a" exists
                table.insert(result, dump(subtable.box)) -- Add to result list
            end
        end
        logger.dbg("Lortey Text On Page " .. table.concat(result, "|"))
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
        for _, rect in pairs(rects) do -- if multiple rectangles are present for example one word is split between lines because the line ends
            if rect.x and rect.y and rect.w and rect.h then
                self.ui.view:drawHighlightRect(Screen.bb, 0, 0, rect, type, color)
            end
            UIManager:setDirty(nil, "ui", rect, nil)
        end
    end
end
local function getScriptDirectory()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or "./"
end
function speedko:addToMainMenu(menu_items)
    menu_items.speedko_menu = {
        text = _("Speed Reading Settings"),
        sorting_hint = "setting",

        callback = function()
            local words = self:mapWholePage(false)
            UIManager:show(InfoMessage:new({
                text = _("Speed reading settings menu"), -- Fixed: Added proper text
            }))

            logger.dbg("Lortey indicator " .. dump(UIManager:getTopmostVisibleWidget()))
            -- UIManager:show(WidgetContainer:new({
            --     dimen = Geom:new({ w = 32, h = 32 }),
            --     icon,
            -- }))
            self:set_indicator(getScriptDirectory() .. "icons/hourglass.svg", true)
            self:createUI()
            --UIManager:show(self)

            --UIManager:nextTick(function()
            --    for _, value in pairs(words) do
            --        if #value.box > 0 then
            --            self:drawHighlight(value.box, "invert")
            --        end
            --    end
            --end)
        end,
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
return speedko
