-- SPDX-License-Identifier: BSD-3-Clause
-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
--
-- Hostname-Praefix der gewaehlten Domain, nur bei der Ersteinrichtung
-- (gluon-setup-mode configured nicht 1; adorfer 18.10.2026). Wer den
-- vorgeschlagenen Namen uebernimmt und nur in die Mitte etwas schreibt, soll
-- das Kuerzel der gewaehlten Domain vorn haben, nicht das der default_domain,
-- mit der der Name beim ersten Start entstand.
--
-- Zwei Wege mit derselben Regel (neanderfunk.default_hostname.swap_prefix):
--   im Browser   Template neanderfunk/hostname-prefix tauscht das Praefix im
--                Namensfeld, sobald die Domain-Auswahl wechselt
--   beim Senden  write() dieses Abschnitts; laeuft nach den write() von
--                0100-hostname und 0200-domain-select (gluon-web arbeitet die
--                Abschnitte der Reihe nach ab) und vor dem Form-write, das
--                configured setzt. Fuer Browser ohne JavaScript.
-- Beginnt der Name mit keinem bekannten Praefix, bleibt er, wie er ist.

return function(form, uci)
	local unistd = require 'posix.unistd'

	if not unistd.access('/lib/gluon/domains/') then
		return
	end
	if uci:get_first('gluon-setup-mode', 'setup_mode', 'configured') == '1' then
		return
	end

	local nf = require 'neanderfunk.default_hostname'
	local prefixes = nf.domain_prefixes()

	local s = form:section(Section)
	s.template = 'neanderfunk/hostname-prefix'
	s.prefixes = prefixes

	function s:write()
		local pretty_hostname = require 'pretty_hostname'

		local new = prefixes[uci:get('gluon', 'core', 'domain') or '']
		if not new then
			return
		end
		local name = pretty_hostname.get(uci)
		local swapped = nf.swap_prefix(name, prefixes, new)
		if swapped ~= name then
			pretty_hostname.set(uci, swapped)
			uci:save('system')
		end
	end
end
