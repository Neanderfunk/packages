#!/usr/bin/lua5.1

-- Seeds /etc/config/neanderfunk-node-whisperer from the site.conf.
--
-- Der site.conf-Schluessel heisst weiterhin `node_whisperer`, wie beim
-- Original: so muss eine Site beim Wechsel auf dieses Paket nichts aendern,
-- und ein Wechsel zurueck kostet ebenfalls nichts. Nur das uci-Paket traegt
-- unseren Namen, damit sich die Dateien nicht in die Quere kommen.

local site = require 'gluon.site'
local uci = require('simple-uci').cursor()

-- `domain` fehlt hier bewusst, wie schon beim Original: auf einer
-- Single-Domain-Firmware gibt es keine Domain zu melden. Unser Patch 0001
-- sorgt zwar dafuer, dass das kein Fehler mehr ist - aber die Information
-- waere trotzdem leer, also wird sie gar nicht erst angefordert.
local default_sources = {
	'hostname',
	'node_id',
	'uptime',
	'site_code',
	'system_load',
	'firmware_version',
	'batman_adv',
}

local sources = {}
local disabled = false
local sources_set = false

if not site.node_whisperer.enabled(false) then
	disabled = true
end

for _, information in ipairs(site.node_whisperer.information({})) do
	table.insert(sources, information)
	sources_set = true
end

if not sources_set then
	sources = default_sources
end

uci:delete('neanderfunk-node-whisperer', 'settings')
uci:section('neanderfunk-node-whisperer', 'settings', 'settings', {
	disabled = disabled,
})
uci:set('neanderfunk-node-whisperer', 'settings', 'information', sources)
-- This also works on single-band devices
uci:set('neanderfunk-node-whisperer', 'settings', 'interface', {'client0', 'client1'})
uci:commit('neanderfunk-node-whisperer')
