

local oo              = require("loop.base")
local io              = require("io")
local coroutine       = require("coroutine")

local Task            = require("jive.ui.Task")

local debug           = require("jive.utils.debug")
local log             = require("jive.utils.log").logger("net.socket")


module(..., oo.class)


function __init(self, jnt, prog)
	local obj = oo.rawnew(self, {
		jnt = jnt,
		prog = prog,
		_status = "suspended",
	})

	return obj
end


function read(self, sink)
	self.fh, err = io.popen(self.prog, "r")

	if self.fh == nil then
		sink(nil, err)

		self._status = "dead"
		return
	end

	local task = Task("prog:" .. self.prog,
			nil,
			function(_, ...)
				while true do
					local chunk = self.fh:read(8096)
					sink(chunk)

					if chunk == nil then
						self.fh:close()
						self.jnt:t_removeRead(self)

						self._status = "dead"
						return
					end

					Task:yield()
				end
			end)

	self._status = "running"
	self.jnt:t_addRead(self, task, 0)
end


function status(self, sink)
	return self._status
end


function getfd(self)
	return self.fh:fileno()
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
