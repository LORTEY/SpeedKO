local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local reader = require("apps/reader/readerui")
local highlight = require("apps/reader/modules/readerhighlight")
local speedko = WidgetContainer:extend({
	name = "hello",
	is_doc_only = false,
})

function speedko:onDispatcherRegisterActions()
	Dispatcher:registerAction(
		"helloworld_action",
		{ category = "none", event = "HelloWorld", title = _("Hello World"), general = true }
	)
end

function speedko:init()
	self:onDispatcherRegisterActions()
	self.ui.menu:registerToMainMenu(self)
end
local logger = require("logger")
function speedko:addToMainMenu(menu_items)
	menu_items.hello_world = {
		text = _("Speed Reading Settings"),
		-- in which menu this should be appended
		sorting_hint = "setting",

		-- a callback when tapping
		callback = function()
			highlight.saveHighlight(0)
			UIManager:show(InfoMessage:new({
				text = _(reader.name),
			}))
		end,
	}
end

function speedko:onHelloWorld()
	local popup = InfoMessage:new({
		text = _("Hello World"),
	})
	UIManager:show(popup)
end

return speedko
