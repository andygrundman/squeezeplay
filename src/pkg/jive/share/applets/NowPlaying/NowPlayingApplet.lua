local pairs, ipairs, tostring, type, setmetatable = pairs, ipairs, tostring, type, setmetatable

local math             = require("math")
local table            = require("table")
local string	       = require("string")

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Font             = require("jive.ui.Font")
local Framework        = require("jive.ui.Framework")
local Icon             = require("jive.ui.Icon")
local Choice           = require("jive.ui.Choice")
local Label            = require("jive.ui.Label")
local Group            = require("jive.ui.Group")
local Slider	       = require("jive.ui.Slider")
local RadioButton      = require("jive.ui.RadioButton")
local RadioGroup       = require("jive.ui.RadioGroup")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Window           = require("jive.ui.Window")
local Tile             = require("jive.ui.Tile")
local Timer            = require("jive.ui.Timer")
                       
local log              = require("jive.utils.log").logger("applets.screensavers")
local debug            = require("jive.utils.debug")
local datetime         = require("jive.utils.datetime")

local appletManager    = appletManager


local WH_FILL                = jive.ui.WH_FILL
local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE

local EVENT_KEY_ALL          = jive.ui.EVENT_KEY_ALL
local EVENT_KEY_DOWN         = jive.ui.EVENT_KEY_DOWN
local EVENT_KEY_UP           = jive.ui.EVENT_KEY_UP
local EVENT_KEY_PRESS        = jive.ui.EVENT_KEY_PRESS
local EVENT_KEY_HOLD         = jive.ui.EVENT_KEY_HOLD
local EVENT_SCROLL           = jive.ui.EVENT_SCROLL
local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_UNUSED           = jive.ui.EVENT_UNUSED
local EVENT_ACTION           = jive.ui.EVENT_ACTION
local EVENT_FOCUS_GAINED     = jive.ui.EVENT_FOCUS_GAINED
local EVENT_FOCUS_LOST       = jive.ui.EVENT_FOCUS_LOST
local EVENT_WINDOW_POP       = jive.ui.EVENT_WINDOW_POP
local EVENT_WINDOW_INACTIVE  = jive.ui.EVENT_WINDOW_INACTIVE
local EVENT_WINDOW_ACTIVE    = jive.ui.EVENT_WINDOW_ACTIVE
local EVENT_HIDE             = jive.ui.EVENT_HIDE
local EVENT_SHOW             = jive.ui.EVENT_SHOW
local KEY_GO                 = jive.ui.KEY_GO
local KEY_FWD                = jive.ui.KEY_FWD
local KEY_REW                = jive.ui.KEY_REW
local KEY_HOME               = jive.ui.KEY_HOME
local KEY_PLAY               = jive.ui.KEY_PLAY
local KEY_ADD                = jive.ui.KEY_ADD
local KEY_BACK               = jive.ui.KEY_BACK
local KEY_PAUSE              = jive.ui.KEY_PAUSE
local KEY_VOLUME_DOWN        = jive.ui.KEY_VOLUME_DOWN
local KEY_VOLUME_UP          = jive.ui.KEY_VOLUME_UP

local jiveMain               = jiveMain
local jnt                    = jnt

module(...)
oo.class(_M, Applet)

-- with drop shadow
local ARTWORK_SIZE = 154
-- without drop shadow
--local ARTWORK_SIZE = 166


----------------------------------------------------------------------------------------
-- Helper Functions
--

local windowStyle

-- defines a new style that inherits from an existing style
local function _uses(parent, value)
        local style = {}
        setmetatable(style, { __index = parent })

        for k,v in pairs(value or {}) do
                if type(v) == "table" and type(parent[k]) == "table" then
                        -- recursively inherit from parent style
                        style[k] = _uses(parent[k], v)
                else
                        style[k] = v
                end
        end

        return style
end

local function _nowPlayingArtworkThumbUri(iconId)
        return '/music/' .. iconId .. '/cover_' .. ARTWORK_SIZE .. 'x' .. ARTWORK_SIZE .. '_p.png'
end

local function SecondsToString(seconds)
	local min = math.floor(seconds / 60)
	local sec = math.floor(seconds - (min*60))

	return string.format("%d:%02d", min, sec)
end

local function _getIcon(self, item, icon)
	local server = self.player:getSlimServer()

	if windowStyle == 'ss' then
		-- without drop shadow
		--ARTWORK_SIZE = 184
		-- with drop shadow
		ARTWORK_SIZE = 172
	else
		-- without drop shadow
		--ARTWORK_SIZE = 166
		-- with drop shadow
		ARTWORK_SIZE = 154
	end

	if item and item["icon-id"] then
		-- Fetch an image from SlimServer
		server:fetchArtworkThumb(item["icon-id"], icon, _nowPlayingArtworkThumbUri, ARTWORK_SIZE) 
	elseif item and item["icon"] then
		-- Fetch a remote image URL, sized to ARTWORK_SIZE x ARTWORK_SIZE
		server:fetchArtworkURL(item["icon"], icon, ARTWORK_SIZE)
	else
		icon:setValue(nil)
	end
end

local function updatePosition(self)
	local strElapsed = ""
	local strRemain = ""
	local pos = 0

	if self.trackPos then
		strElapsed = SecondsToString(self.trackPos)
	end

	if self.trackLen and self.trackLen > 0 then
		strRemain = "-" .. SecondsToString(self.trackLen - self.trackPos)
		pos = self.trackPos
	end

	self.progressGroup:setWidgetValue("elapsed", strElapsed)
	self.progressGroup:setWidgetValue("remain", strRemain)
	self.progressSlider:setValue(pos)
end

function init(self)
	jnt:subscribe(self)
end

function notify_playerCurrent(self, player)

	log:debug("NowPlaying.notify_playerCurrent()")

	jiveMain:addItem( 
		{
			id = 'appletNowPlaying',
			node = 'home',
			text = self:string('SCREENSAVER_NOWPLAYING'),
			sound = 'WINDOWSHOW',
			weight = 1,
			callback = function(event, menuItem)
				self:showNowPlaying('browse')
			end
		}
	)

end

function updateTrack(self, trackinfo, pos, length)
	self.trackGroup:setWidgetValue("text", trackinfo);
end

function updateProgress(self, trackpos, tracklen)
	self.trackPos = trackpos
	self.trackLen = tracklen	

	if tracklen and tracklen > 0 then
		self.progressSlider:setRange(0, tracklen, trackpos)
	else 
		-- If 0 just set it to 100
		self.progressSlider:setRange(0, 100, 0)
	end

	updatePosition(self)

end

function updatePlaylist(self, enabled, nr, count)
	if enabled == true and count > 1 then
		nr = nr + 1
		self.titleGroup:setWidgetValue("playlist", self:string("SCREENSAVER_NOWPLAYING_OF", nr, count))
	else 
		self.titleGroup:setWidgetValue("playlist", "")
	end
end

function tick(self)
	if self.mode ~= "play" then
		return
	end

	self.trackPos = self.trackPos + 1
	if self.trackLen and self.trackLen > 0 then
		if self.trackPos > self.trackLen then self.trackPos = self.trackLen end
	end

	updatePosition(self)
end

-----------------------------------------------------------------------------------------
-- Settings
--
function openSettings(self, menuItem)
	local window = Window("Now Playing Settings")

	self:tieAndShowWindow(window)
	return window
end

----------------------------------------------------------------------------------------
-- Screen Saver Display 
--

function _process_status(self, data)
	log:debug("_process_status")

	local createdWindow = false

	if data.item_loop 
		and data.item_loop[1].params.track_id ~= self.track_id 
		then

		-- create new window
		-- FIXME this can now be combined in _process_status, may help fixing bug 6087
		_createUI(self)
		createdWindow = true

		self.track_id = data.item_loop[1].params.track_id
	end

	self.mode = data.mode

	if self.mode == "play" then
		self.titleGroup:setWidgetValue("title", self:string("SCREENSAVER_NOWPLAYING"))
	elseif self.mode == "pause" then
		self.titleGroup:setWidgetValue("title", self:string("SCREENSAVER_PAUSED"))
	else
		self.titleGroup:setWidgetValue("title", self:string("SCREENSAVER_STOPPED"))
	end

	if data.item_loop then
		local text = data.item_loop[1].text
		-- XXX: current_title of null is a function value??
		if data.remote == 1 and type(data.current_title) == 'string' then 
			text = text .. "\n" .. data.current_title
		end

		local item = data.item_loop[1]

		_getIcon(self, item, self.artwork)
		self:updateTrack(text)
		self:updateProgress(data.time, data.duration)
		self:updatePlaylist(true, data.playlist_cur_index, data.playlist_tracks)

		-- preload artwork for next track
		if data.item_loop[2] then
			_getIcon(self, data.item_loop[2], Icon("artwork"))
		end
	else
		_getIcon(self, nil, self.artwork)
		self:updateTrack("\n\n\n")
		self:updateProgress(0, 0)
		self:updatePlaylist(false, 0, 0)
	end

	return createdWindow
end


function _createUI(self)
	local window = Window("window")

	if windowStyle == 'ss' then
		local sw, sh = Framework:getScreenSize()
		local newBg = Framework:getBackground()
		local srf = Surface:newRGBA(sw, sh)
		newBg:blit(srf, 0, 0, sw, sh)
		window:addWidget(Icon("iconbg", srf))
	end

	local components = { 
		nptitle = "nptitle", 
		nptrack = "nptrack", 
		progressB = "progressB", 
		progress = "progress", 
		npartwork = "npartwork" 
	}
	for k, v in pairs(components) do
		local new = windowStyle .. v
		components[k] = new
	end

	self.titleGroup = Group(components.nptitle, {
				   title = Label("text", self:string("SCREENSAVER_NOWPLAYING")),
				   playlist = Label("playlist", "")
			   })
	

	self.trackGroup = Group(components.nptrack, {
				   text = Label("text", "\n\n\n")
			   })
	
	
	self.progressSlider = Slider(components.progressB, 0, 100, 0)
	self.progressSlider:addTimer(1000, function() self:tick() end)

	self.progressGroup = Group(components.progress, {
				      elapsed = Label("text", ""),
				      slider = self.progressSlider,
				      remain = Label("text", "")
			      })

	self.artwork = Icon("artwork")
	artworkGroup = Group(components.npartwork, {
				     artwork = self.artwork    
			     })
	
	self.preartwork = Icon("artwork") -- not disabled, used for preloading

	window:addWidget(self.titleGroup)
	window:addWidget(self.trackGroup)
	window:addWidget(artworkGroup)
	window:addWidget(self.progressGroup)

	window:focusWidget(self.trackGroup)
	-- register window as a screensaver, unless we are explicitly not in that mode
	if windowStyle == 'ss' then
		local manager = appletManager:getAppletInstance("ScreenSavers")
		manager:screensaverWindow(window)
	end

	self:tieWindow(window)
	self.window = window
end


function showNowPlaying(self, style)
	-- this is to show the window to be opened in two modes: 
	-- ss and browse

	if not style then style = 'ss' end

	windowStyle = style

	local discovery = appletManager:getAppletInstance("SlimDiscovery")
	self.player = discovery:getCurrentPlayer()


	local transitionOn
	if style == 'ss' then
		transitionOn = Window.transitionFadeIn
	elseif style == 'browse' then
		transitionOn = Window.transitionPushLeft
	end

	if not self.player then
		-- No current player - don't start screensaver
		return
	end

	local playerid = self.player:getId()

	-- Register our own functions to be called when we receive data
	self.statusSink =
		function(chunk, err)
			if err then
				log:warn(err)
			else
				-- only update if previous now playing window is
				-- on the top of the stack
				if Framework.windowStack[1] ~= self.window then
					return
				end

				if self:_process_status(chunk.data) then
					self.window:showInstead(Window.transitionFadeIn)
				end
			end
		end

	self.player.slimServer.comet:addCallback(
		'/slim/playerstatus/' .. playerid, self.statusSink
	)

	-- Initialize with current data from Player
	-- FIXME, if this gets called when it shouldn't, we write a window over our current one and mess up the stack (easy way to reproduce: hit fwd to go to the next track when on the NowPlaying window)
	self:_process_status(self.player.state)
	self.window:show(transitionOn)

	if windowStyle == 'browse' then

		local browser = appletManager:getAppletInstance("SlimBrowser")

		-- don't allow a screensaver on this window
		-- FIXME: ideally, screensaver would only be repressed if the screensaver was set to NowPlaying 
		self.window:setAllowScreensaver(false)

		-- install listeners to this "special" window, if opened not in a screensaver context
		self.window:addListener(
			EVENT_KEY_PRESS | EVENT_KEY_HOLD,
			function(event)
				local type = event:getType()
				local keyPress = event:getKeycode()
				if (keyPress == KEY_BACK) then
					-- back to Home
					self.window:hide(Window.transitionPushRight)
					return EVENT_CONSUME
				elseif (keyPress == KEY_GO) then
					browser:showPlaylist()
					return EVENT_CONSUME
				end
				return EVENT_UNUSED
			end
		)

	end
end


function free(self)
	if self.player then
		self.player.slimServer.comet:removeCallback( '/slim/playerstatus/' .. self.player:getId(), self.statusSink )
		-- this will cause the window to be recreated when moving between ss and browse styles
		self.track_id = nil
	end
end


function skin(self, s)

	-- this skin is established in two forms,
	-- one for the Screensaver windowStyle (ss), one for the browse windowStyle (browse)
	-- a lot of it can be recycled from one to the other

	local imgpath = "applets/DefaultSkin/images/"
	local npimgpath = "applets/NowPlaying/"
	local fontpath = "fonts/"

	local screenWidth, screenHeight = Framework:getScreenSize()

        local titleBox =
                Tile:loadTiles({
                                       imgpath .. "titlebox.png",
                                       imgpath .. "titlebox_tl.png",
                                       imgpath .. "titlebox_t.png",
                                       imgpath .. "titlebox_tr.png",
                                       imgpath .. "titlebox_r.png",
                                       imgpath .. "bghighlight_tr.png",
                                       imgpath .. "titlebox_b.png",
                                       imgpath .. "bghighlight_tl.png",
                                       imgpath .. "titlebox_l.png"
                               })

        local highlightBox =
                Tile:loadTiles({
                                       imgpath .. "bghighlight.png",
                                       nil,
                                       nil,
                                       nil,
                                       imgpath .. "bghighlight_r.png",
                                       imgpath .. "bghighlight_br.png",
                                       imgpath .. "bghighlight_b.png",
                                       imgpath .. "bghighlight_bl.png",
                                       imgpath .. "bghighlight_l.png"
                               })

	-- Title
	s.ssnptitle = {}
	s.ssnptitle.border = { 4, 4, 4, 0 }
	s.ssnptitle.position = LAYOUT_NORTH
	s.ssnptitle.bgImg = titleBox
	s.ssnptitle.order = { "title", "playlist" }
	s.ssnptitle.text = {}
	s.ssnptitle.text.w = WH_FILL
	s.ssnptitle.text.padding = { 10, 7, 8, 9 }
	s.ssnptitle.text.align = "top-left"
	s.ssnptitle.text.font = Font:load(fontpath .. "FreeSansBold.ttf", 20)
	s.ssnptitle.text.fg = { 0x00, 0x00, 0x00 }
	s.ssnptitle.playlist = {}
	s.ssnptitle.playlist.padding = { 10, 7, 8, 9 }
	s.ssnptitle.playlist.font = Font:load(fontpath .. "FreeSans.ttf", 15)
	s.ssnptitle.playlist.fg = { 0x00, 0x00, 0x00 }
	s.ssnptitle.playlist.textAlign = "top-right"


	-- nptitle style is the same for both windowStyles
	s.browsenptitle = _uses(s.ssnptitle, browsenptitle)

	-- Song
	s.ssnptrack = {}
	s.ssnptrack.border = { 4, 0, 4, 0 }
        s.ssnptrack.bgImg = highlightBox
	s.ssnptrack.text = {}
	s.ssnptrack.text.w = WH_FILL
	s.ssnptrack.text.padding = { 10, 7, 8, 9 }
	s.ssnptrack.text.align = "top-left"
        s.ssnptrack.text.font = Font:load(fontpath .. "FreeSans.ttf", 14)
	s.ssnptrack.text.lineHeight = 17
        s.ssnptrack.text.line = {
		{
			font = Font:load(fontpath .. "FreeSansBold.ttf", 14),
			height = 17
		}
	}
	s.ssnptrack.text.fg = { 0x00, 0x00, 0x00 }

	-- nptrack is identical between the two windowStyles
	s.browsenptrack = _uses(s.ssnptrack)

	-- Artwork
	local browseArtWidth = 166
	local ssArtWidth = 184

	local ssnoartworkoffset = (screenWidth - ssArtWidth) / 2
	s.ssnpartwork = {}
	s.ssnpartwork.w = ssArtWidth
	s.ssnpartwork.border = { ssnoartworkoffset, 4, ssnoartworkoffset, 6 }
	s.ssnpartwork.align = "center"
	s.ssnpartwork.bgImg = Tile:loadImage(imgpath .. "album_shadow_" .. ssArtWidth .. ".png")
	s.ssnpartwork.artwork = {}
	s.ssnpartwork.artwork.padding = 3
	s.ssnpartwork.artwork.img = Surface:loadImage(imgpath .. "album_noartwork_" .. ssArtWidth .. ".png")

	-- artwork layout is not the same between the two windowStyles
	local browsenoartworkoffset = (screenWidth - browseArtWidth) / 2
	local browsenpartwork = {
		w = browseArtWidth,
		border = { browsenoartworkoffset, 4, browsenoartworkoffset, 6 },
		bgImg = Tile:loadImage(imgpath .. "album_shadow_" .. browseArtWidth .. ".png"),
		artwork = { padding = 3, img = Surface:loadImage(imgpath .. "album_noartwork_" .. browseArtWidth .. ".png") }
	}
	s.browsenpartwork = _uses(s.ssnpartwork, browsenpartwork)

	-- Progress bar
        local progressBackground =
                Tile:loadHTiles({
                                        npimgpath .. "progressbar_bkgrd_l.png",
                                        npimgpath .. "progressbar_bkgrd.png",
                                        npimgpath .. "progressbar_bkgrd_r.png",
                               })

        local progressBar =
                Tile:loadHTiles({
                                        npimgpath .. "progressbar_fill_l.png",
                                        npimgpath .. "progressbar_fill.png",
                                        npimgpath .. "progressbar_fill_r.png",
                               })

	s.ssprogress = {}
	s.ssprogress.order = { "elapsed", "slider", "remain" }
	s.ssprogress.text = {}
	s.ssprogress.text.w = 50
	s.ssprogress.padding = { 0, 10, 0, 0 }
	s.ssprogress.text.padding = { 8, 0, 8, 0 }
	s.ssprogress.text.font = Font:load(fontpath .. "FreeSansBold.ttf", 12)
	s.ssprogress.text.fg = { 0xe7,0xe7, 0xe7 }
	s.ssprogress.text.sh = { 0x37, 0x37, 0x37 }

	-- browse has different positioning than ss windowStyle
	local browseprogress = {
		padding = { 0, 0, 0, 0 } 
	}
	s.browseprogress = _uses(s.ssprogress)

	s.ssprogressB             = {}
        s.ssprogressB.horizontal  = 1
        s.ssprogressB.bgImg       = progressBackground
        s.ssprogressB.img         = progressBar

	s.browseprogressB = _uses(s.ssprogressB)

	-- background style should start at x,y = 0,0
        s.iconbg = {}
        s.iconbg.x = 0
        s.iconbg.y = 0
        s.iconbg.h = screenHeight
        s.iconbg.w = screenWidth
	s.iconbg.border = { 0, 0, 0, 0 }
	s.iconbg.position = LAYOUT_NONE
end


