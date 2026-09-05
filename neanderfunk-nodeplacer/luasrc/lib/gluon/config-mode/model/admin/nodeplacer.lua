-- SPDX-License-Identifier: BSD-2-Clause
-- SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk
--
-- One flag: nodeplacer.settings.disable. The UCI option is a negative
-- switch (D-009, matching other packages' *-disable options), but a
-- checkbox reading "Disable" would be the odd one out on this page next
-- to "Automatic updates" and "Remote access" - like every other tab here
-- it shows a positive "Enabled" flag and inverts it on write.

local uci = require('simple-uci').cursor()

local pkg_i18n = i18n 'neanderfunk-nodeplacer'

-- 510-nodeplacer always creates this section, but do not assume nodeplacer
-- itself has already run (e.g. right after an opkg install).
if not uci:get('nodeplacer', 'settings') then
	uci:section('nodeplacer', 'nodeplacer', 'settings')
	uci:save('nodeplacer')
end

local f = Form(pkg_i18n.translate('Nodeplacer'), pkg_i18n.translate(
	'Nodeplacer can move this node to another domain of the community '
	.. 'when a signed instruction for it is published. You can forbid '
	.. 'that here.'))

local s = f:section(Section)

local enabled = s:option(Flag, 'enabled', pkg_i18n.translate('Enabled'))
enabled.default = not uci:get_bool('nodeplacer', 'settings', 'disable')
enabled.optional = false
function enabled:write(data)
	uci:set('nodeplacer', 'settings', 'disable', not data)
end

function f:write()
	uci:commit('nodeplacer')
end

return f
