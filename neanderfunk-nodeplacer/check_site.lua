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
-- mirrors may also be set per domain (a multi-domain image reaches each
-- domain's mirror under that domain's own ULA). 510-nodeplacer reads them
-- through gluon.site, i.e. site and active domain merged, on every
-- gluon-reconfigure, so a domain switch takes them along.
need_string_array_match(in_domain({'nodeplacer', 'mirrors'}), '^http://', false)

-- Both are optional overrides. By default the control file is verified with
-- the keys and the threshold of the autoupdater branch the node is running,
-- so that whoever may release a firmware may also move the node (D-031).
-- Since D-045 both may also be set in a domain file (neither in_site nor
-- in_domain): a domain with its own key, such as the no-parking default
-- domain 25_hvb, can then be left with that key alone. A list from the domain
-- replaces the site's list as a whole at run time (libgluonutil merges
-- objects only). Set in the domain, the threshold is an upper bound and only
-- the method 'domain' is accepted (D-045, enforced by 510-nodeplacer and
-- nodeplacer).
local good_signatures = need_number({'nodeplacer', 'good_signatures'}, false)

local pubkeys = need_string_array_match({'nodeplacer', 'pubkeys'}, '^%x+$', false)
if pubkeys and good_signatures then
	need({'nodeplacer', 'good_signatures'}, function(gs)
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
