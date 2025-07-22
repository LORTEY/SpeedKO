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

function speedko:addToMainMenu(menu_items)
    local rect = {
        x = 137,
        h = 27,
        w = 170,
        y = 166,
    }
    menu_items.speedko_menu = {
        text = _("Speed Reading Settings"),
        sorting_hint = "setting",
        callback = function()
            self.ui.view.drawHighlightRect(self.ui.view, Screen.bb, 0, 0, rect, "lighten")
            UIManager:show(InfoMessage:new({
                text = _("Speed reading settings menu"), -- Fixed: Added proper text
            }))
        end,
    }
end

function speedko:onSpeedkoEvent()
    UIManager:show(InfoMessage:new({
        text = _("Speed reading mode activated"), -- Fixed: Added proper text
    }))
end
return speedko
