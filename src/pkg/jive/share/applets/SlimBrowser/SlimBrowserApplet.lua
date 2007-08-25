
--[[
=head1 NAME

applets.SlimBrowser.SlimBrowserApplet - Browse music and control players.

=head1 DESCRIPTION

TODO

=head1 SYNOPSIS

TODO

=head1 FUNCTIONS

=cut
--]]

-- stuff we use
local tostring, tonumber, type = tostring, tonumber, type
local pairs, ipairs, select, assert = pairs, ipairs, select, assert

local oo               = require("loop.simple")
local table            = require("table")
local string           = require("string")

local Applet           = require("jive.Applet")
local Player           = require("jive.slim.Player")
local SlimServer       = require("jive.slim.SlimServer")
local Framework        = require("jive.ui.Framework")
local Window           = require("jive.ui.Window")
local Popup            = require("jive.ui.Popup")
local Menu             = require("jive.ui.Menu")
local Label            = require("jive.ui.Label")
local Icon             = require("jive.ui.Icon")
local Slider           = require("jive.ui.Slider")
local Timer            = require("jive.ui.Timer")
local Textinput        = require("jive.ui.Textinput")
local Textarea         = require("jive.ui.Textarea")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Checkbox         = require("jive.ui.Checkbox")

local DB               = require("applets.SlimBrowser.DB")

local debug = require("jive.utils.debug")

local log              = require("jive.utils.log").logger("player.browse")
local logd             = require("jive.utils.log").logger("player.browse.data")

local EVENT_KEY_ALL    = jive.ui.EVENT_KEY_ALL
local EVENT_KEY_DOWN   = jive.ui.EVENT_KEY_DOWN
local EVENT_KEY_UP     = jive.ui.EVENT_KEY_UP
local EVENT_KEY_PRESS  = jive.ui.EVENT_KEY_PRESS
local EVENT_KEY_HOLD   = jive.ui.EVENT_KEY_HOLD
local EVENT_CONSUME    = jive.ui.EVENT_CONSUME
local EVENT_UNUSED     = jive.ui.EVENT_UNUSED
local EVENT_ACTION     = jive.ui.EVENT_ACTION
local KEY_FWD          = jive.ui.KEY_FWD
local KEY_REW          = jive.ui.KEY_REW
local KEY_HOME         = jive.ui.KEY_HOME
local KEY_PLAY         = jive.ui.KEY_PLAY
local KEY_ADD          = jive.ui.KEY_ADD
local KEY_BACK         = jive.ui.KEY_BACK
local KEY_PAUSE        = jive.ui.KEY_PAUSE
local KEY_VOLUME_DOWN  = jive.ui.KEY_VOLUME_DOWN
local KEY_VOLUME_UP    = jive.ui.KEY_VOLUME_UP
-- 
-- local Context          = require("applets.SlimBrowser.Context")

local jiveMain         = jiveMain
local jnt              = jnt
local jiveMain         = jiveMain


module(...)
oo.class(_M, Applet)


--==============================================================================
-- Global "constants"
--==============================================================================

-- number of items to get for missing items in status.
-- Note the first/pushed number of items is defined in Player.lua
local STATUS_MISSING_FETCH = 100 

-- number of items to fetch initially (window opens) for browse items
local BROWSE_FIRST_FETCH = 100
-- number of items to get for browse missing items
local BROWSE_MISSING_FETCH = 100

--==============================================================================
-- Global variables
--==============================================================================

-- The string function, for easy reference
local _string

-- The player we're browsing and it's server
local _player = false
local _server = false

-- The path of enlightenment
local _browsePath = false
local _statusPath = false

-- The system home menu
local _homeWindow = false
local _homeHandler = false

-- The last entered text
local _lastInput = ""

--==============================================================================
-- Local functions
--==============================================================================


-- Forward declaration 
local _newDestination
local _actionHandler

-- _safeDeref
-- safely derefence a structure in depth
-- doing a.b.c.d will fail if b or c are not defined
-- _safeDeref(a, "b", "c", "d") will always work (of course, it returns nil if b or c are not defined!)
local function _safeDeref(struct, ...)
--	log:debug("_safeDeref()")
--	log:debug(struct)
	local res = struct
	for i=1, select('#', ...) do
		local v = select(i, ...)
		if type(res) != 'table' then return nil end
--		log:debug(v)
		if v then
			res = res[v]
			if not res then return nil end
		end
	end
--	log:debug("_safeDeref =>")
--	log:debug(res)
	return res
end


-- _priorityAssign(key, defaultValue, table1, table2, ...)
-- returns the first non nil value of table1[key], table2[key], etc.
-- if no table match, defaultValue is returned
local function _priorityAssign(key, defaultValue, ...)
--	log:debug("_priorityAssign(", key, ")")
	for i=1, select('#', ...) do
		local v = select(i, ...)
--		log:debug(v)
		if v then 
			local res = v[key]
			if res then return res end
		end
	end
	return defaultValue
end


-- artworkThumbUri
-- returns a URI to fetch artwork on the server
-- FIXME: should this be styled?
local function _artworkThumbUri(iconId)
	return '/music/' .. iconId .. '/cover_50x50_f_000000.jpg'
end


-- _openVolumePopup
-- manages the volume pop up window
local function _openVolumePopup(vol)

--	log:debug("_openVolumePopup START ------------------- (", vol, ")")

	local popup = Popup("popup")

	local label = Label("title", "Volume")
	popup:addWidget(label)

	local slider = Slider("volume")
	slider:setRange(-1, 100, _player:getVolume())
	popup:addWidget(slider)
	popup:addWidget(Icon("iconVolumeMin"))
	popup:addWidget(Icon("iconVolumeMax"))

	local rate = vol
	local cnt = 0
	
	-- timer to change volume
	local timer = Timer(200,
		function()
--			log:debug("_openVolumePopup - timer ", timer)

			if vol > 0 or vol < 0 then
				slider:setValue(_player:volume(rate))
			end
			popup:showBriefly()
			
			cnt = cnt + 1
			if cnt > 10 then
				rate = 6 * vol
			elseif cnt > 5 then
				rate = 4 * vol
			else
				rate = 2 * vol
			end
		end
	)

	-- listener for volume up and down keys
	popup:addListener(
		EVENT_KEY_ALL,
		function(event)
			local evtCode = event:getKeycode()

			-- we're only interested in volume keys
			if evtCode == KEY_VOLUME_UP then
				if vol == -1 then cnt = 0 end
--				log:debug("************* VOL +1")
				vol = 1
				
			elseif evtCode == KEY_VOLUME_DOWN then
				if vol == 1 then cnt = 0 end
--				log:debug("************* VOL -1")
				vol = -1
				
			else
				return EVENT_UNUSED
			end

			-- if timer is gone, don't do anything => the window is closing
			if not timer then
				return EVENT_CONSUME
			end

			local evtType = event:getType()
			if evtType == EVENT_KEY_UP then
				-- stop volume timer
--				log:debug("stop timer (listener) ", timer)
				timer:stop()
			elseif evtType == EVENT_KEY_DOWN then
				-- start volume timer
--				log:debug("start timer (listener) ", timer)
				timer:start()
			end

			-- make sure we don't hide popup
			return EVENT_CONSUME
		end
	)

	popup:showBriefly(2000,
		function()
			if timer then
--				log:debug("stop timer (showBriefly timeout), ", timer)
				timer:stop()
				-- make sure it cannot ever be started again
				timer = nil
			end
		end,
		Window.transitionNone,
		Window.transitionPushPopupLeft
	)

	-- start the timer
	if vol > 0 then
--		_player:button('volume_up')
--		_player:volumeUp()
		_player:volume(1)
--		log:debug("start timer ", timer)
		timer:start()
	elseif vol < 0 then
--		_player:button('volume_down')
--		_player:volumeDown()
		_player:volume(-1)
--		log:debug("start timer ", timer)
		timer:start()
	end
--	log:debug("_openVolumePopup END --------------------------")
end


-- _newWindowSpec
-- returns a Window spec based on the concatenation of base and item
-- window definition
local function _newWindowSpec(db, item)
	log:debug("_newWindowSpec()")
	
	local bWindow
	local iWindow = _safeDeref(item, 'window')

	if db then
		bWindow = _safeDeref(db:chunk(), 'base', 'window')
	end
	
	-- determine style
	local menuStyle = _priorityAssign('menuStyle', "", iWindow, bWindow)
	return {
		["windowStyle"]      = "",
		["labelTitleStyle"]  = _priorityAssign('titleStyle', "",              iWindow, bWindow) .. "title",
		["menuStyle"]        = menuStyle .. "menu",
		["labelItemStyle"]   = menuStyle .. "item",
		["text"]             = _priorityAssign('text',       item["text"],    iWindow, bWindow),
		["icon-id"]          = _priorityAssign('icon-id',    item["icon-id"], iWindow, bWindow),
		["icon"]             = _priorityAssign('icon',       item["icon"],    iWindow, bWindow),
	} 
end


-- _artworkItem
-- returns an icon for the item artwork, nil if no icon for this item
local function _artworkItem(item)

	local icon = item["_jive_icon"]
	
	if icon == nil then
		-- keep the icon, but be smart, remember if we have no artwork to display!
		item["_jive_icon"] = false
	
		local iconId = item["icon-id"]
		if iconId then
			icon = Icon("icon")
			_server:fetchArtworkThumb(iconId, icon, _artworkThumbUri)
			item["_jive_icon"] = icon
		end
	
	elseif icon == false then
		icon = nil
	end
	
	return icon
end

-- _checkboxItem
-- returns a checkbox button for use on a given item
local function _checkboxItem(item, db)
	local checkboxFlag = item["checkbox"]
	if checkboxFlag and not item["_jive_button"] then
		item["_jive_button"] = Checkbox(
			"checkbox",
			function(_, checkboxFlag)
				log:debug("checkbox updated: ", checkboxFlag)
				if (checkboxFlag) then
					log:debug("ON: ", checkboxFlag)
					_actionHandler(nil, nil, db, nil, nil, 'on', item) 
				else
					log:debug("OFF: ", checkboxFlag)
					_actionHandler(nil, nil, db, nil, nil, 'off', item) 
				end
			end,
			checkboxFlag == 1
		)
	end
	return item["_jive_button"]
end

-- _radioItem
-- returns a radio button for use on a given item
local function _radioItem(item, db)
	local radioFlag = item["radio"]
	if radioFlag and not item["_jive_button"] then
		item["_jive_button"] = RadioButton(
			"radio",
			db:getRadioGroup(),
			function() 
				log:warn('Callback has been called') 
				_actionHandler(nil, nil, db, nil, nil, 'do', item) 
			end,
			radioFlag == 1
		)
	end
	return item["_jive_button"]
end

-- _newDecoratedLabel
-- generates a label cum decoration in the given labelStyle
local function _newDecoratedLabel(labelStyle, item, db)
	-- if item is a windowSpec, then the icon is kept in the spec for nothing (overhead)
	-- however it guarantees the icon in the title is not shared with (the same) icon in the menu.
	if item["radio"] then
		return Label(labelStyle, item["text"], _radioItem(item, db))
	elseif item["checkbox"] then
		return Label(labelStyle, item["text"], _checkboxItem(item, db))
	elseif item then
		return Label(labelStyle, item["text"], _artworkItem(item))
	else
		return Label(labelStyle, "")
	end
end

-- _performJSONAction
-- performs the JSON action...
local function _performJSONAction(jsonAction, from, qty, sink)
	log:debug("_performJSONAction(from:", from, ", qty:", qty, "):")
--	debug.dump(jsonAction)
	
	local cmdArray = jsonAction["cmd"]
	
	-- sanity check
	if not cmdArray or type(cmdArray) != 'table' then
		log:error("JSON action for ", actionName, " has no cmd or not of type table")
		return
	end
	
	-- replace player if needed
	local playerid = jsonAction["player"]
	if not playerid or playerid == 0 then
		playerid = _player.id
	end
	
	-- look for __INPUT__ as a param value
	local params = jsonAction["params"]
	local newparams
	if params then
		newparams = {}
		for k, v in pairs(params) do
			if v == '__INPUT__' then
				table.insert( newparams, _lastInput )
			else
				table.insert( newparams, k .. ":" .. v )
			end
		end
	end
	
	local request = {}
	
	for i, v in ipairs(cmdArray) do
		table.insert(request, v)
	end
	
	table.insert(request, from)
	table.insert(request, qty)
	
	if newparams then
		for i, v in ipairs(newparams) do
			table.insert(request, v)
		end
	end
	
	-- send the command
	_server.comet:request(sink, playerid, request)
end


local function _goNowPlaying()
	if _statusPath then
		log:debug("_goNowPlaying()")
	
		-- show our NowPlaying window!
		_statusPath.window:show()
		
		-- arrange so that menuListener works
		_statusPath.origin = _browsePath
		_browsePath.destination = _statusPath
		_browsePath = _statusPath
		
		return EVENT_CONSUME
	end
	return EVENT_UNUSED
end


-- _getStepSink
-- returns a closure to a sink embedding step
local function _getStepSink(step, sink)
	return function(chunk, err)
		sink(step, chunk, err)
	end
end


-- _devnull
-- sinks that silently swallows data
-- used for actions that go nowhere (play, add, etc.)
local function _devnull(chunk, err)
	log:debug('_devnull()')
	log:debug(chunk)
end


-- _browseSink
-- sink that sets the data for our go action
local function _browseSink(step, chunk, err)
	log:debug("_browseSink()")
	
	-- check we're still relevant
	if step.origin then
		-- only the main window has got no origin...
		
		-- are we still supposed to make this step?
		-- the unlock closure sets step.origin.destination to false...
		if step.origin.destination != step then
			log:info("_browseSink(): ignoring data, action cancelled...")
			return
		end
	end
	
	-- we're relevant
	log:debug("step: ", step)
	log:debug("_browsePath: ", _browsePath)
	if _browsePath != step and not step.destination then
		-- install us as the new top of the world, unless we went somewhere from there
		_browsePath = step
		step.window:show()
		if step.origin and step.origin.menu then
			step.origin.menu:unlock()
		end
	end

	if chunk then
		local data
		
		-- move result key up to top-level
		if chunk.result then
			data = chunk.result
		else
			data = chunk.data
		end
		
		if logd:isDebug() then
			debug.dump(chunk, 8)
		end
	
		-- if our window has a menu - some windows don't :(
		if step.menu then
			step.menu:setItems(step.db:menuItems(data))

			-- what's missing?
			local from, qty = step.db:missing(BROWSE_MISSING_FETCH)
		
			if from then
				_performJSONAction(step.data, from, qty, step.sink)
			end
		end
		
	else
		log:error(err)
	end
end


-- _mainMenuSink
-- Jive modifies the main menu to add Now Playing and Exit items
-- FIXME: Modify for player off?
-- We set this sink instead of the main one (_browseSink) in openPlayer
local function _mainMenuSink(step, chunk, err)
	log:debug("_mainMenuSink()")
--	log:debug(chunk)

	local data = chunk.data
	
	if data then
	
		-- FIXME: we probably want exit in all cases, even and above in case of error...
		
		-- FIXME: set step.origin


		-- we want to add a Now playing item (at the top)
		table.insert(data.item_loop,
			1,
			{
				text = _string("SLIMBROWSER_NOW_PLAYING"),
				_go = _goNowPlaying
			}
		)

		-- and clone the home menu items (at the bottom)
		local count = 0
		for _, item in jiveMain:iterator() do
			count = count + 1
			table.insert(data.item_loop, 
				     {
					     text = item.text,
					     _go = function(event)
							   return item.callback(event, item) or EVENT_CONSUME
						   end
				     }
			     )
		end

		data.count = data.count + count + 1
	else
		log:error(err)
		-- FIXME: Cancel opening plugin, bla bla bla
	end
	
	-- call the regular sink
	_browseSink(step, chunk, err)
end


-- _statusSink
-- sink that sets the data for our status window(s)
local function _statusSink(step, chunk, err)
	log:debug("_statusSink()")
	
	-- currently we're not going anywhere with Now Playing...
	assert(step == _statusPath)

	-- Just in case we get passed a full event
	local data = chunk
	if data.data then
		data = data.data
	end
	
	if data then
		if logd:isDebug() then
			debug.dump(data, 8)
		end
		
		-- stuff from the player is just json.result
		-- stuff from our completion calls below will be full json
		-- adapt
		-- XXX: still needed?
		if data.id and data.result then
			data = data.result
		end
		
		step.menu:setItems(step.db:menuItems(data))

		-- what's missing?
		local from, qty = step.db:missing(STATUS_MISSING_FETCH)

		if from then
			_server.comet:request(
				step.sink,
				_player.id,
				{ 'status', from, qty, 'menu:menu' }
			)
		end

	else
		log:error(err)
	end
end


-- _defaultActions
-- provides a function for each actionName for which Jive provides a default behaviour
-- the function prototype is the same than _actionHandler (i.e. the whole shebang to cover all cases)
local _defaultActions = {
	
	["pause"] = function()
		_player:togglePause()
		return EVENT_CONSUME
	end,

	["pause-hold"] = function()
		_player:stop()
		return EVENT_CONSUME
	end,

	["rew"] = function()
		_player:rew()
		return EVENT_CONSUME
	end,

	["fwd"] = function()
		_player:fwd()
		return EVENT_CONSUME
	end,

	-- default commands in Now Playing
	
	["play-status"] = function(_1, _2, _3, dbIndex)
		if _player:isPaused() and _player:isCurrent(dbIndex) then
			_player:togglePause()
		else
			-- the DB index IS the playlist index + 1
			_player:playlistJumpIndex(dbIndex)
		end
		return EVENT_CONSUME
	end,

	["add-status"] = function(_1, _2, _3, dbIndex)
		_player:playlistDeleteIndex(dbIndex)
		return EVENT_CONSUME
	end,

	["add-hold-status"] = function(_1, _2, _3, dbIndex)
		_player:playlistZapIndex(dbIndex)
		return EVENT_CONSUME
	end,
}


-- _actionHandler
-- sorts out the action business: item action, base action, default action...
_actionHandler = function(menu, menuItem, db, dbIndex, event, actionName, item)
	log:warn("_actionHandler(", actionName, ")")

	if logd:isDebug() then
		debug.dump(item, 4)
	end

	-- some actions work (f.e. pause) even with no item around
	if item then
	
		local chunk = db:chunk()
		local bAction
		local iAction
		local onAction
		local offAction
		
		-- special cases for go action:
		if actionName == 'go' then
			
			-- check first for a hierarchical menu or a input to perform 
			if item['count'] or (item['input'] and not item['_inputDone']) then
				log:debug("_actionHandler(", actionName, "): hierachical or input")

				-- make a new window
				local step, sink = _newDestination(_browsePath, item, _newWindowSpec(db, item), _browseSink)

				-- the item is the data, wrapped into a result hash
				local res = {
					["result"] = item,
				}
				_browseSink(step, res)
				return EVENT_CONSUME
			end
			
			-- check for a 'do' action (overrides a straight 'go')
			-- actionName is corrected below!!
			bAction = _safeDeref(chunk, 'base', 'actions', 'do')
			iAction = _safeDeref(item, 'actions', 'do')
			onAction = _safeDeref(item, 'actions', 'on')
			offAction = _safeDeref(item, 'actions', 'off')
		end
	
		
		-- now check for a run-of-the mill action
		if not (iAction or bAction or onAction or offAction) then
			bAction = _safeDeref(chunk, 'base', 'actions', actionName)
			iAction = _safeDeref(item, 'actions', actionName)
		else
			-- if we reach here, it's a DO action...
			-- okay to call on or off this, as they are just special cases of 'do'
			actionName = 'do'
		end
		
	
		if iAction or bAction then
	
			-- the resulting action, if any
			local jsonAction
	
			-- process an item action first
			if iAction then
				log:debug("_actionHandler(", actionName, "): item action")
			
				-- found a json command
				if type(iAction) == 'table' then
					jsonAction = iAction
				end
			
			-- not item action, look for a base one
			elseif bAction then
				log:debug("_actionHandler(", actionName, "): base action")
			
				-- found a json command
				if type(bAction) == 'table' then
			
					jsonAction = bAction
				
					-- this guy may want to be completed by something in the item
					-- base gives the name of item key in key itemParams
					-- we're looking for item[base.itemParams]
					local paramName = jsonAction["itemsParams"]
					log:debug("..paramName:", paramName)
					if paramName then
					
						-- sanity check
						if type(paramName) != 'string' then
							log:error("Base action for ", actionName, " has itemParams field but not of type string!")
							return EVENT_UNUSED
						end

						local iParams = item[paramName]
						if iParams then
						
							-- sanity check, can't hurt
							if type(iParams) != 'table' then
								log:error("Base action for ", actionName, " has itemParams: ", paramName, " found in item but not of type table!")
								return EVENT_UNUSED
							end
						
							-- found 'em!
							-- add them to the command
							-- make sure the base has a params item!
							local params = jsonAction["params"]
							if not params then
								params = {}
								jsonAction["params"] = params
							end
							for k,v in pairs(iParams) do
								params[k] = v
							end
						end
					end
				end
			end -- elseif bAction
	
			-- now we may have found a command
			if jsonAction then
				log:debug("_actionHandler(", actionName, "): json action")
			
				-- set good or dummy sink as needed
				-- prepare the window if needed
				local sink = _devnull
				local from
				local to
				if actionName == 'go' then
					local step
					from = 0
					to = BROWSE_FIRST_FETCH
					step, sink = _newDestination(_browsePath, item, _newWindowSpec(db, item), _browseSink, jsonAction)
				end
			
				-- send the command
				 _performJSONAction(jsonAction, from, to, sink)
			
				return EVENT_CONSUME
			end
		end
	end
	
	-- fallback to built-in
	-- these may work without an item
	
	-- Note the assumption here: event handling happens for front window only
	if _browsePath.actionModifier then
		local builtInAction = actionName .. _browsePath.actionModifier

		local func = _defaultActions[builtInAction]
		if func then
			log:debug("_actionHandler(", builtInAction, "): built-in")
			return func(menu, menuItem, db, dbIndex, event, builtInAction, item)
		end
	end
	
	local func = _defaultActions[actionName]
	if func then
		log:debug("_actionHandler(", actionName, "): built-in")
		return func(menu, menuItem, db, dbIndex, event, actionName, item)
	end
	
	-- no success here for this event
	return EVENT_UNUSED
end


--  Go           right, return, mouse middle button
--  Back         left, mouse right button
--  Scroll up    up, mouse wheel
--  Scroll down  down, mouse wheel
--  Up           i
--  Down         k
--  Left         j
--  Right        l
--  Play         x p, mouse left button
--  Pause        c space
--  Add          a
--  Rew          z <
--  Fwd          b >
--  Home         h
--  Volume up    + =
--  Volume down  -


-- map from a key to an actionName
local _keycodeActionName = {
	[KEY_PAUSE] = 'pause', 
	[KEY_PLAY]  = 'play',
	[KEY_FWD]   = 'fwd',
	[KEY_REW]   = 'rew',
	[KEY_ADD]   = 'add',
}
-- internal actionNames:
--				  'inputDone'

-- _browseMenuListener
-- called 
local function _browseMenuListener(menu, menuItem, db, dbIndex, event)
	log:warn("_browseMenuListener(", event:tostring(), ", " , index, ")")
	
	-- we don't care about events not on the current window
	-- assumption for event handling code: _browsePath corresponds to current window!
	if _browsePath.menu != menu then
		log:debug("_browsePath: ", _browsePath)

		log:debug("Ignoring, not visible")
		return
	end
	
	-- we don't want to do anything if this menu item involves an active decoration
	-- like a radio, checkbox, or set of choices
	-- further, we want the event to propagate to the active widget, so return EVENT_UNUSED
	local item = db:item(dbIndex)
	if item["_jive_button"] then
		return EVENT_UNUSED
	end

	-- ok so joe did press a key while in our menu...
	-- figure out the item action...
	local evtType = event:getType()
	
	-- actions on button down
	if evtType == EVENT_KEY_DOWN then
		log:debug("_browseMenuListener: EVENT_KEY_DOWN")

		local evtCode = event:getKeycode()

		if evtCode == KEY_VOLUME_UP then
			log:debug("_browseMenuListener: KEY_VOLUME_UP")
		
			_openVolumePopup(1)
			return EVENT_CONSUME
		
		elseif evtCode == KEY_VOLUME_DOWN then
			log:debug("_browseMenuListener: KEY_VOLUME_DOWN")

			_openVolumePopup(-1)
			return EVENT_CONSUME
		end
		
	else
	
		
		if evtType == EVENT_ACTION then
			log:debug("_browseMenuListener: EVENT_ACTION")
		
			if item then
				-- check for a local action
				local func = item._go
				if func then
					log:debug("_browseMenuListener: Calling found func")
					return func()
				end
		
				-- otherwise, check for a handler
				return _actionHandler(menu, menuItem, db, dbIndex, event, 'go', item)
			end

		elseif evtType == EVENT_KEY_PRESS then
			log:debug("_browseMenuListener: EVENT_KEY_PRESS")
		
			local actionName = _keycodeActionName[event:getKeycode()]

			if actionName then
				return _actionHandler(menu, menuItem, db, dbIndex, event, actionName, item)
			end
		
		elseif evtType == EVENT_KEY_HOLD then
			log:debug("_browseMenuListener: EVENT_KEY_HOLD")
		
			local actionName = _keycodeActionName[event:getKeycode()]

			if actionName then
				return _actionHandler(menu, menuItem, db, dbIndex, event, actionName .. "-hold", item)
			end
		end
	end

	-- if we reach here, we did not handle the event :(
	return EVENT_UNUSED
end


-- _browseMenuRenderer
-- renders a basic menu
local function _browseMenuRenderer(menu, widgets, toRenderIndexes, toRenderSize, db)
	--	log:debug("_browseMenuRenderer(", toRenderSize, ", ", db, ")")
	-- we must create or update the widgets for the indexes in toRenderIndexes.
	-- this last list can contain null, so we iterate from 1 to toRenderSize
	
	local labelItemStyle = db:labelItemStyle()
	
	for widgetIndex = 1, toRenderSize do
		local dbIndex = toRenderIndexes[widgetIndex]
		
		if dbIndex then
			
			-- the widget in widgets[widgetIndex] shall correspond to data[dataIndex]
--			log:debug(
--				"_browseMenuRenderer: rendering widgetIndex:", 
--				widgetIndex, ", dataIndex:", dbIndex, ")"
--			)
			
			local widget = widgets[widgetIndex]
			local item, current = db:item(dbIndex)
			local style = labelItemStyle
			
			if current then
				style = "albumcurrent"
			end
			
			if not widget then
				widgets[widgetIndex] = _newDecoratedLabel(style, item, db)
			else
				if item and type(item) == 'table' then
					-- change the label text...
					widget:setValue(item.text)

					if (item["radio"]) then
						-- and change the radio button
						widget:setWidget(_radioItem(item, db))
					elseif (item["checkbox"]) then
						-- and change the radio button
						widget:setWidget(_checkboxItem(item, db))
					else 
						-- and change the icon!
						widget:setWidget(_artworkItem(item))
					end
					widget:setStyle(style)
				else
					widget:setValue("")
					widget:setWidget()
					widget:setStyle("label")
				end
			end
		end
	end
end


-- _newDestination
-- origin is the step we are coming from
-- item is the source item
-- windowSpec is the window spec, generally computed by _newWindowSpec to aggregate base and item
-- sink is the sink this destination will use: we must create a closure so that on receiving the data
--  the destination can be retrieved (i.e. reunite data and window)
-- data is generic data that is stored in the step; it is used f.e. to keep the json action between the
--  first incantation and the subsequent ones needed to capture all data (see _browseSink).
_newDestination = function(origin, item, windowSpec, sink, data)
	log:debug("_newDestination():")
	log:debug(windowSpec)
	
	
	-- a DB (empty...) 
	local db = DB(windowSpec)
	
	-- create a window in all cases
	local window = Window(windowSpec.windowStyle)
	window:setTitleWidget(_newDecoratedLabel(windowSpec.labelTitleStyle, windowSpec, db))
	
	local menu

	-- if the item has an input field, we must ask for it
	if item and item['input'] and not item['_inputDone'] then

		local inputSpec
		
		-- legacy SS compatibility
		-- FIXME: remove SS compatibility with legacy JiveMLON generation
		if type(item['input']) != "table" then
			inputSpec = {
				len = item['input'],
				help = {
					token = "SLIMBROWSER_SEARCH_HELP",
				},
			}
		else
			inputSpec = item["input"]
		end
		
		-- make sure it's a number for the comparison below
		-- Lua insists on checking type while Perl couldn't care less :(
		inputSpec.len = tonumber(inputSpec.len)
		
		-- default allowedChars
		if not inputSpec.allowedChars then
			inputSpec.allowedChars = " abcdefghijklmnopqrstuvwxyz!@#$%^&*()_+{}|:\\\"'<>?-=,./~`[];0123456789"
		end

		-- create a text input
		local input = Textinput(
			"textinput", 
			"",
			function(_, value)
				-- check for min number of chars
				if #value < inputSpec.len then
					return false
				end

				
				log:debug("Input: " .. value)
				_lastInput = value
				item['_inputDone'] = value
				
				-- now we should perform the action !
				_actionHandler(nil, nil, db, nil, nil, 'go', item)
				return true
			end,
			inputSpec.allowedChars
		)

		-- fix up help
		local helpText
		if inputSpec.help then
			local help = inputSpec.help
			helpText = help.text
			if not helpText then
				if help.token then
					helpText = _string(help.token)
				end
			end
		end
		
		if helpText then
			local help = Textarea("help", helpText)
			window:addWidget(help)
		end
		
		window:addWidget(input)

	else
	
		-- create a cozy place for our items...
		-- a db above
	
		-- a menu. We manage closing ourselves to guide our path
		menu = Menu(windowSpec.menuStyle, _browseMenuRenderer, _browseMenuListener)
		menu:setCloseable(false)

		-- alltogether now
		menu:setItems(db:menuItems())
		window:addWidget(menu)
	
	end
	
	
	-- a step for our enlightenment path
	local step = {
		origin          = origin,   -- origin step
		destination     = false,    -- destination step
		window          = window,   -- step window
		menu            = menu,     -- step menu
		db              = db,       -- step db
		sink            = false,    -- sink closure embedding this step
		data            = data,     -- data (generic)
		actionModifier  = false,    -- modifier
	}
	
	log:debug("new step: " , step)
	
	-- indicate where we're going
	if origin then
	
		assert(origin.destination == false)
		
		-- we're going there
		origin.destination = step
		
		-- so please wait dear user...
		if origin.menu then
			origin.menu:lock(
				function()
					-- huh, no, we're no longer going...
					log:info("_newDestination(): cancelling action...")
					origin.destination = false
				end
			)
		end
	end
	
	-- hide the window on back key and restore paths
	window:addListener(
		EVENT_KEY_PRESS,
		function(evt)
			if evt:getKeycode() == KEY_BACK then
				
				
				-- if there's no origin to go back to, don't go :)
				if _browsePath.origin then
				
					-- clear it if present
					if item then
						item['_inputDone'] = nil
					end
					
					window:hide()
				
					_browsePath = _browsePath.origin
					_browsePath.destination = false
					
					log:debug("back, browsePath: ", _browsePath)

					-- if we show now playing, it takes over _browsePath
					-- reset statusPath.origin to false, we don't come from browsepath any longer
					_statusPath.origin = false
					
					return EVENT_CONSUME 
				end
			end
		end
	)
		
	-- manage sink
	local stepSink = _getStepSink(step, sink)
	step.sink = stepSink
	
	return step, stepSink
end


function _homeAction(self, homePath)
	local windowStack = Framework.windowStack

	-- are we in home?
	if #windowStack > 1 then

		-- no, unroll
		local step = homePath.destination
		-- FIXME: loop looks weird, can probably be simplified.
		while step do
			if step.destination then
				-- hide the window
				step.window:hide(nil, "JUMP")
				-- destroy scaffholding to data coming in is stopped
				step.origin = false
				step = step.destination
			else
				break
			end
		end

		_browsePath = homePath
		-- if we were going somewhere, we're no longer
		_browsePath.destination = false
		_browsePath.menu:unlock()

		-- close any non SlimBrowser windows

		while #windowStack > 1 do
			windowStack[#windowStack - 1]:hide(nil, "JUMP")
		end
	else
		_goNowPlaying()
	end
end


--==============================================================================
-- SlimBrowserApplet public methods
--==============================================================================




-- notify_playerDelete
-- this is called by jnt when the playerDelete message is sent
function notify_playerDelete(self, player)

	-- if this concerns our player
	if player == _player then
		-- panic!
		log:warn("Player gone while browsing it ! -- packing home!")
		self:free()
	end
end


-- notify_playerCurrent
-- this is called when the player changes
function notify_playerCurrent(self, player)
	log:debug(
		"SlimBrowserApplet:notify_playerCurrent(", 
		player, 
		")"
	)

	-- has the player actually changed?
	if _player == player then
		return
	end

	-- free current player
	if _player then
		self:free()
	end

	-- nothing to do if we don't have a player
	if not player then
		return
	end
	

	-- assign our locals
	_player = player
	_server = player:getSlimServer()
	_string = function(token) return self:string(token) end
	
	-- create a window for Now Playing
	local path, sink = _newDestination(
		nil,
		nil,
		_newWindowSpec(nil, {
			text = _string("SLIMBROWSER_NOW_PLAYING"),
			window = { ["menuStyle"] = "album", },
		}),
		_statusSink
	)
	_statusPath = path
	
	-- make sure it has our modifier (so that we use different default action in Now Playing)
	_statusPath.actionModifier = "-status"

	-- showtime for the player
	-- FIXME: handle player off...
	_player:onStage(sink)
	
	-- prepare the window
	path, sink = _newDestination(
		nil, -- FIXME the menu should be passed in here
		nil,
		_newWindowSpec(nil, {
			["text"] = player:getName(),
		}),
		_mainMenuSink
	)
	_browsePath = path
	
	-- fetch the menu, pronto...
	_server.comet:request(sink, nil, { 'menu', 0, 100 })
	
	-- implement the home button using a global handler, this will work even
	-- when other applets/screensavers are displayed
	_homeHandler = Framework:addListener(EVENT_KEY_PRESS,
					     function(event)
						     if event:getKeycode() == KEY_HOME then
							     self:_homeAction(path)
							     return EVENT_CONSUME
						     end

						     return EVENT_UNUSED
					     end,
					     false)

	-- switch out the standard home menu, and replace with our window
	if not _homeWindow then
		_homeWindow = Framework.windowStack[#Framework.windowStack]
	end
	Framework.windowStack[#Framework.windowStack] = _browsePath.window
end


--[[

=head2 applets.SlimBrowser.SlimBrowserApplet:free()

Overridden to dispose of our stuff.

=cut
--]]
function free(self)
	log:debug("SlimBrowserApplet:free()")
	
	_player:offStage()

	-- restore the system home menu
	if _homeWindow then
		local window = Framework.windowStack[#Framework.windowStack]
		Framework.windowStack[#Framework.windowStack] = _homeWindow
		window:hide()
	end

	if _homeHandler then
		Framework:removeListener(_homeHandler)
	end
		
	_player = false
	_server = false
	_string = false
	_homeWindow = false
	_homeHandler = false

	-- walk down our path and close...
	local step = _browsePath
	
	while step do
		step.window:hide()
		step.destination = false
		local prev = step
		step = step.origin
		prev.origin = nil
	end
	
	local step = _statusPath
	
	while step do
		step.window:hide()
		step.destination = false
		local prev = step
		step = step.origin
		prev.origin = nil
	end
	
	return true
end


function init(self)
	jnt:subscribe(self)
end

--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

