-- nodeplacer: site.conf validation
--
-- nodeplacer = {
--   mirrors = { 'http://firmware.example.org/nodeplacer', ... },  -- optional; default: mirrors of the autoupdater branch
--   good_signatures = 2,          -- optional; default: threshold of the autoupdater branch
--   pubkeys = { '<hex>', ... },   -- optional; default: pubkeys of the autoupdater branch
--   disable = 0,                  -- optional; default 0
--   config_mode = true,           -- optional; default true (D-039)
-- }

-- The whole block is optional (D-042): installed means active, with the
-- autoupdater branch's mirrors, keys and threshold as defaults.
need_string_array_match(in_site({'nodeplacer', 'mirrors'}), '^http://', false)

-- Both are optional overrides. By default the control file is verified with
-- the keys and the threshold of the autoupdater branch the node is running,
-- so that whoever may release a firmware may also move the node (D-031).
local good_signatures = need_number(in_site({'nodeplacer', 'good_signatures'}), false)

local pubkeys = need_string_array_match(in_site({'nodeplacer', 'pubkeys'}), '^%x+$', false)
if pubkeys and good_signatures then
	need(in_site({'nodeplacer', 'good_signatures'}), function(gs)
		return gs <= #pubkeys
	end, nil, string.format('be less than or equal to the number of public keys (%d)', #pubkeys))
end

alternatives(function()
	need_number_range(in_site({'nodeplacer', 'disable'}), 0, 1, false)
end, function()
	need_boolean(in_site({'nodeplacer', 'disable'}), false)
end)

-- whether the config-mode tab (owner opt-out) is registered at all
need_boolean(in_site({'nodeplacer', 'config_mode'}), false)
