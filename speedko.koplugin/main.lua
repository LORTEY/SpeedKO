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
    Dispatcher:registerAction(
        "speedko_toggle_pointer",
        { category = "none", event = "TogglePointer", title = _("Toggle SpeedKO Pointer"), general = true }
    )
end

function speedko:onTogglePointer()
    local id = self.current_pointer_id + 1 -- id is ussed to make it impossible that two pointer recursive loops are runing silmultanieusly
    self.current_pointer_id = id
    self.pointer_enabled = not self.pointer_enabled
    self:pointer(id)
end
function speedko:init()
    if not self.settings then
        self:readSettingsFile()
    end
    self.pointer_enabled = false
    self.current_page = nil
    self.current_pointer_id = 0
    self.pointer_word_sec = 60.0 / 500
    self.pointer_mapped_page = nil
    self.pointer_type = "underscore"
    self.pointer_index = nil
    self.pointer_render_mode = "lazy" -- "lazy" "smart" "heavy"
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.pageno = 1
end
function speedko:readSettingsFile()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/speedko.lua")
end
function speedko:loadSettings()
    if not self.settings then
        self:readSettingsFile()
    end
    if self.settings:readSetting("pointer_type") then
        self.pointer_type = self.settings:readSetting("pointer_type")
    end
    if self.settings:readSetting("pointer_word_sec") then
        self.pointer_word_sec = tonumber(self.settings:readSetting("pointer_word_sec"))
    end
end

function speedko:onReaderReady()
    self.view:registerViewModule("speedko_indicator", self)
    self:loadSettings()
    self:pointer(self.current_pointer_id) -- auto start pointer on doccument opened if it is enabled
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
function findCharPositions(str, char)
    local positions = {}
    for i = 1, #str do
        if str:sub(i, i) == char then
            table.insert(positions, i)
        end
    end
    return positions
end
function speedko:mapWholePage(debug)
    self.pageno = self.view.state.page
    debug = debug or false
    local pos0 = { x = 0, y = 0, page = self.pageno }
    local word = self.ui.view.document:getWordFromPosition(pos0)

    if not word or not word.pos0 then
        local res = self.ui.view.document:getTextFromPositions(
            pos0,
            { x = Screen:getWidth(), y = Screen:getHeight(), page = self.pageno }
        )
        local text = self:fallbackPageMap(res)
        --logger.info("Lortey text " .. dump(ret))
        local result = {}
        for _, subtable in ipairs(text) do
            if subtable.text then -- Check if "a" exists
                table.insert(result, dump(subtable.text)) -- Add to result list
            end
        end
        logger.info("Lortey text concat " .. table.concat(result, " "))
        return text
    end
    local x_pointer = word.pos0

    local text = {}
    while true do
        local current = self:getXPosAndPosition(x_pointer, debug)
        table.insert(text, current)

        x_pointer = self.ui.view.document:getNextVisibleWordStart(current.xPos.pos1)
        if x_pointer == nil or not self.ui.view.document:isXPointerInCurrentPage(x_pointer) then
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

    logger.dbg(dump(text))
    return text
end

function hasChar(str, char)
    return string.find(str, char, 1, true) ~= nil
end
local function concatTables(t1, t2)
    local result = {}
    for _, v in ipairs(t1) do
        table.insert(result, v)
    end
    for _, v in ipairs(t2) do
        table.insert(result, v)
    end
    return result
end
function charactersInStr(str, char)
    local count = 0
    for i in str:gmatch(char) do
        count = count + 1
    end
    return count
end
function speedko:getWordsFromLineRecursively(line)
    logger.dbg("Lortey recurs1 " .. dump(line))
    if not hasChar(line.text, " ") then
        return { line }
    end
    logger.dbg("Finished")
    local y = line.sboxes[1].y

    local w = line.sboxes[1].w
    local x = line.sboxes[1].x
    local page = line.pos0.page
    local split_pos = { page = page, x = x + w / 2.0, y = y }

    local part1 = self.ui.document:getTextFromPositions(line.pos0, split_pos)
    local part2 = self.ui.document:getTextFromPositions(split_pos, line.pos1)
    logger.dbg("Lortey recurs2 " .. dump(part1) .. " " .. dump(part2))
    if part1.sboxes[1].x + part1.sboxes[1].w <= part2.sboxes[1].x then
        local t1 = self:getWordsFromLineRecursively(part1)
        local t2 = self:getWordsFromLineRecursively(part2)
        return concatTables(t1, t2)
    else
        logger.dbg("Lortey overlap")

        local p1_words = charactersInStr(part1.text, " ")
        local p2_words = charactersInStr(part2.text, " ")
        if p1_words < p2_words then
            split_pos =
                { page = page, x = x + w / 2.0 + (part1.sboxes[1].x + part1.sboxes[1].w - part2.sboxes[1].x), y = y }
            part2 = self.ui.document:getTextFromPositions(split_pos, line.pos1)
        else
            split_pos =
                { page = page, x = x + w / 2.0 - (part1.sboxes[1].x + part1.sboxes[1].w - part2.sboxes[1].x), y = y }
            part1 = self.ui.document:getTextFromPositions(line.pos0, split_pos)
        end
        local t1 = self:getWordsFromLineRecursively(part1)
        local t2 = self:getWordsFromLineRecursively(part2)
        return concatTables(t1, t2)
    end
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

function speedko:fallbackPageMap(res) --used when xpointers not present
    local lines = {}
    logger.dbg(dump(res))
    for _, pos in ipairs(res.sboxes) do
        local line = self.ui.document:getTextFromPositions(
            { x = pos.x, y = pos.y, page = res.pos0.page },
            { x = pos.x + pos.w, y = pos.y, page = res.pos0.page },
            true -- do not highlight
        )
        table.insert(lines, line)
    end
    local words = {}

    for _, line in ipairs(lines) do
        --[[local line_length = #line.text * 1.0
        local spaces = findCharPositions(line.text, " ")
        local lastpos = 0
        for _, space in ipairs(spaces) do
            local word = self.ui.document:getTextFromPositions({
                x = line.sboxes[1].x + (line.sboxes[1].w / line_length) * ((lastpos + space) / 2.0),
                y = line.sboxes[1].y,
                page = res.pos0.page,
            }, {
                x = line.sboxes[1].x + (line.sboxes[1].w / line_length) * ((lastpos + space) / 2.0),
                y = line.sboxes[1].y,
                page = res.pos0.page,
            }, false)

            lastpos = space
            local NextWord = {
                box = {},
                text = {},
            }
            NextWord.box = word.sboxes
            NextWord.text = word.text
            --logger.dbg("Lortey wordsss " .. dump(word))
            table.insert(words, NextWord)
        end
        local word = self.ui.document:getTextFromPositions({
            x = line.sboxes[1].x + (line.sboxes[1].w / line_length) * ((lastpos + line_length) / 2.0),
            y = line.sboxes[1].y,
            page = res.pos0.page,
        }, {
            x = line.sboxes[1].x + (line.sboxes[1].w / line_length) * ((lastpos + line_length) / 2.0),
            y = line.sboxes[1].y,
            page = res.pos0.page,
        }, false)
        local NextWord = {
            box = { {} },
            text = {},
        }
        NextWord.box[1] = word.sbox
        NextWord.text = word.word]]
        --

        local word = self:getWordsFromLineRecursively(line)
        logger.dbg("Lortey wordsss " .. dump(word))

        table.insert(words, word)
    end
    return words
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
                text = _("Toggle Pointer"),
                callback = function()
                    --local words = self:mapWholePage(true)
                    --UIManager:show(InfoMessage:new({
                    --    text = _("Speed reading settings menu"), -- Fixed: Added proper text
                    --}))
                    self.pointer_enabled = not self.pointer_enabled

                    self:loadSettings()
                    self:pointer(self.current_pointer_id)
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
    self.pageno = pageno
    self.pointer_index = 0
    self:loadSettings()
    local id = self.current_pointer_id + 1 -- id is ussed to make it impossible that two pointer recursive loops are runing silmultanieusly
    self.current_pointer_id = id
    self:pointer(id)
end
function speedko:pointer(id)
    local enter_time = time.now()
    if self.pointer_enabled and self.ui.document ~= nil and id == self.current_pointer_id then
        if self.ui:getCurrentPage() ~= self.current_page then
            self.current_page = self.ui:getCurrentPage()
            self.pointer_mapped_page = self:mapWholePage(false)

            if not self.pointer_mapped_page then -- if page does not contain words stop the function
                return
            end

            self.pointer_index = 0
        end
        local a = self.pointer_index -- copy to avoid value change before nexttick is invoked
        if self.pointer_mapped_page then
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
                        self:pointer(id)
                    end)
                else
                    UIManager:scheduleIn(time_schedule_in, function()
                        self:pointer(id)
                    end)
                end
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
