local Dispatcher = require("dispatcher") -- luacheck:ignore
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local IconWidget = require("ui/widget/iconwidget")
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
function wait(seconds)
    local start = os.time()
    while os.time() - start < seconds do
    end
end
function speedko:mapWholePage(debug)
    debug = debug or false
    local page_map = {}
    local pos0 = { x = 0, y = 0 }
    local pos1 = { x = Screen:getWidth(), y = Screen:getHeight() }

    local first_x_pointer = self.ui.view.document:getWordFromPosition(pos0).pos0

    local text = {}
    while self.ui.document:isXPointerInCurrentPage(first_x_pointer) do
        local success, _ = pcall(function()
            local current = self:getXPosAndPosition(first_x_pointer, debug)

            first_x_pointer = current.xPos.pos1
            table.insert(text, current)
        end)
        if not success then
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

function speedko:drawHighlight(rect, type, color)
    if rect.x and rect.y and rect.w and rect.h then
        self.ui.view:drawHighlightRect(Screen.bb, 0, 0, rect, type, color)
    end
    UIManager:setDirty("ui", "full", rect, true)
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
            local icon_size = Screen:scaleBySize(32)

            local icon = IconWidget:new({
                icon = "book.opened",
                width = icon_size,
                height = icon_size,
            })

            --UIManager:nextTick(function()
            --    self.ui.view.flipping[1][1] = icon
            --    WidgetContainer:paintTo(self.ui.view.flipping[1][1].dimen, Screen.bb, 0, 0)
            --    logger.dbg("Lorety rectttt " .. dump(self.ui.view.flipping[1][1]))
            --    UIManager:setDirty("reader", "partial", {
            --        self.ui.view.flipping.dimen,
            --    }, false)
            --end)
            UIManager:scheduleIn(0, function()
                UIManager:nextTick(function()
                    for _, value in pairs(words) do
                        if #value.box == 1 then
                            self:drawHighlight(value.box[1], "lighten", Blitbuffer.Gray)
                        end
                    end
                end)
            end)
        end,
    }
end
function speedko:getXPosAndPosition(lastPosX, debug)
    debug = debug or false

    -- Initialize the return table
    local NextWord = {
        xPos = {},
        box = {},
        --position = {
        --  pos_start = nil,
        --pos_end = nil,
        --},
        text = {},
    }

    -- Get positions with error checking
    NextWord.xPos.pos0 = self.ui.view.document:getNextVisibleWordStart(lastPosX)
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

return speedko
