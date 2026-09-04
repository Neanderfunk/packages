-- nodeplacer: site.conf validation
--
-- nodeplacer = {
--   mirrors = { 'http://firmware.example.org/nodeplacer', ... },  -- required
--   good_signatures = 2,                                           -- required
--   pubkeys = { '<hex>', ... },   -- optional; default: pubkeys of the autoupdater branch
--   disable = 0,                  -- optional; default 0
-- }

need_string_array_match(in_site({'nodeplacer', 'mirrors'}), '^http://')

need_number(in_site({'nodeplacer', 'good_signatures'}))

local pubkeys = need_string_array_match(in_site({'nodeplacer', 'pubkeys'}), '^%x+$', false)
if pubkeys then
	need(in_site({'nodeplacer', 'good_signatures'}), function(good_signatures)
		return good_signatures <= #pubkeys
	end, nil, string.format('be less than or equal to the number of public keys (%d)', #pubkeys))
end

alternatives(function()
	need_number_range(in_site({'nodeplacer', 'disable'}), 0, 1, false)
end, function()
	need_boolean(in_site({'nodeplacer', 'disable'}), false)
end)
