-- SPDX-License-Identifier: BSD-2-Clause
-- SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk

package 'neanderfunk-nodeplacer'

local site = require 'gluon.site'

-- Communities that do not want the tab in "Advanced settings" at all can
-- turn it off in site.conf (nodeplacer.config_mode = false); default is
-- to show it. This has to be a site.conf switch, not a build-time
-- Kconfig one, because gluon-web-admin is a hard dependency of this
-- package either way (see docs/DECISIONS.md D-039).
if site.nodeplacer.config_mode(true) then
	-- "Automatic updates" (gluon-web-autoupdater) sits at weight 80 on the
	-- same "admin" ("Advanced settings") page; nodeplacer is closely
	-- related, so it follows right after it.
	entry({"admin", "nodeplacer"}, model("admin/nodeplacer"), _("Nodeplacer"), 85)
end
