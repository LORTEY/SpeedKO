local Dispatcher = require("dispatcher") -- luacheck:ignore
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local speedko = WidgetContainer:extend({
    name = "speedko",
    is_doc_only = false,
})
local Blitbuffer = require("ffi/blitbuffer")
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
function mysplit(inputstr, sep)
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
    local page_map = {}
    local pos0 = { x = 0, y = 0 }
    local pos1 = { x = Screen:getWidth(), y = Screen:getHeight() }

    local page_text = self.ui.view.document:getScreenBoxesFromPositions(pos0, pos1, not debug)
    if debug then
        logger.dbg("Lortey Text On Page " .. dump(page_text))
    end

    local lines = mysplit(page_text.text, "\n")
    if debug then
        logger.dbg("Lortey Text Lines " .. dump(lines))
    end
end
function speedko:addToMainMenu(menu_items)
    local rect = {
        x = 137,
        h = 27,
        w = 170,
        y = 166,
    }
    local highlight_data = {

        [1] = {
            {
                colorful = true,
                drawer = "lighten",
                color = Blitbuffer.ColorRGB32(255, 255, 51, 255),
                index = 2,
                rect = {
                    y = 287,
                    w = 180,
                    h = 27,
                    x = 154,
                },
            },
        },
    }
    local pos0 = { x = 0, y = 0 }
    local pos1 = { x = Screen:getWidth(), y = Screen:getHeight() }
    menu_items.speedko_menu = {
        text = _("Speed Reading Settings"),
        sorting_hint = "setting",

        callback = function()
            -- self.ui.view.drawHighlightRect(self.ui.view, Screen.bb, 0, 0, rect, "lighten")
            self.ui.view.visible_boxes = highlight_data
            self.ui.view:drawSavedHighlight(Screen.bb, 0, 0)
            local word0 = self.ui.document:getWordFromPosition(pos0, true).pos0
            local word1 = self.ui.document:getWordFromPosition(pos1, true).pos1
            logger.dbg(
                "Lortey SBoxes "
                    .. word0
                    .. dump(self:getXPosAndPosition(self.ui.document:getNextVisibleWordStart(word0), true))
            )

            --self.mapWholePage(self, true)

            UIManager:show(InfoMessage:new({
                text = _("Speed reading settings menu"), -- Fixed: Added proper text
            }))
        end,
    }
end

function speedko:getXPosAndPosition(lastPosX, debug)
    debug = debug or false

    -- Initialize the return table
    local NextWord = {
        xPos = {},
        box = nil,
    }

    -- Get positions with error checking
    NextWord.xPos.pos0 = self.ui.view.document:getNextVisibleWordStart(lastPosX)
    NextWord.xPos.pos1 = self.ui.view.document:getNextVisibleWordEnd(lastPosX)

    NextWord.box = self.ui.view.document:getScreenBoxesFromPositions(NextWord.xPos.pos0, NextWord.xPos.pos1, not debug)

    return NextWord
end

return speedko
