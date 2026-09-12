-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
-- SPDX-License-Identifier: BSD-3-Clause
--
-- Puts the one-page setup on {"wizard"} (and so on {}, which aliases it).
--
-- This works because of the load order: the dispatcher loads
-- controller/*.lua, then controller/*/*.lua, each sorted by posix.glob, and
-- "neanderfunk-setup-mode/" sorts after "admin/" and "gluon-config-mode/".
-- entry() on an existing path replaces its target. Should the order ever
-- change, Gluon's wizard simply comes back; nothing breaks.

package 'neanderfunk-setup-mode'

local setup = require 'neanderfunk.setup-mode'

local scan = setup.scan()

if scan.wizard then
	scan.links = {}

	-- The forms of "Advanced settings" are on the setup page now. Its other
	-- pages (Information, Upgrade firmware, ...) move up into the top menu,
	-- with the same target, package and upload handler. The old addresses
	-- below admin/ keep working.
	local admin = node('admin')
	if admin then
		for _, p in ipairs(scan.pages) do
			local n = node('admin', p.name)
			if n and n.target and not node(p.name) then
				local c = entry({p.name}, n.target, n.title, 10 + (n.order or 90))
				c.pkg = n.pkg
				c.filehandler = n.filehandler
				table.insert(scan.links, {name = p.name, title = n.title, pkg = n.pkg})
			end
		end
		admin.hidden = true
	end

	entry({'wizard'}, call(setup.run, scan), _('Setup'), 5)
end
