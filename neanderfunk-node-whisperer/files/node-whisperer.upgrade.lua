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

-- Auf welchen Interfaces angekuendigt wird: aus uci, nicht geraten.
--
-- Hier stand fest {'client0', 'client1'} mit dem Hinweis, dass das auch auf
-- Einband-Geraeten funktioniert - nicht vorhandene Interfaces schaden also
-- nicht. Umgekehrt fehlte aber alles jenseits von client1.
--
-- Damit das hier ueberhaupt etwas findet, muss dieses Skript NACH
-- 320-gluon-client-bridge-wireless laufen - dort entstehen die
-- client_radio*-Sektionen. Es lief frueher als 150-, also davor, und haette
-- eine dynamische Aufzaehlung ins Leere laufen lassen. Siehe Makefile.
local interfaces = {}
uci:foreach('wireless', 'wifi-iface', function(s)
	if s['.name'] and s['.name']:match('^client_radio%d+$') and s.ifname then
		table.insert(interfaces, s.ifname)
	end
end)
table.sort(interfaces)

-- Ohne WLAN - ein EdgeRouter X etwa hat gar kein /etc/config/wireless - bleibt
-- die Liste leer. Dann die bisherige Vorgabe behalten statt eine leere Liste zu
-- schreiben: was node-whisperer mit einer leeren Liste tut, ist nicht geprueft,
-- und mit client0/client1 laeuft es dort seit jeher.
if #interfaces == 0 then
	interfaces = {'client0', 'client1'}
end

uci:set('neanderfunk-node-whisperer', 'settings', 'interface', interfaces)
uci:commit('neanderfunk-node-whisperer')
