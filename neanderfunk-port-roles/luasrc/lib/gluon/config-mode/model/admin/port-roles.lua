-- SPDX-License-Identifier: BSD-3-Clause
-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
--
-- Seite "Ports": eine Rolle je Port und der Mesh-Modus fuer die LAN-Mesh-Ports.
-- Die Rollen sind dieselben gluon.iface_*-Sektionen, die auch Gluons Seite
-- "Netzwerk" zeigt. Ab Werk stecken die LAN-Ports in einer Gruppe (iface_lan,
-- name='/lan'); erst wenn ein Port hier eine andere Rolle bekommt, wird er
-- herausgeloest (gluon.iface_<port>, wie beim Befehl portrole). Wer nichts
-- aendert, behaelt Gluons Aufbau. Gespeichert wird wie dort nur per commit -
-- wirksam wird es mit dem gluon-reconfigure beim "Speichern & Neustarten" im
-- Wizard.
--
-- Geschrieben wird erst in f:write, gesammelt und auf einem frisch geladenen
-- Cursor, und nur, was auf dieser Seite gegenueber der Anzeige geaendert wurde.
-- Grund ist die Sammelseite von neanderfunk-setup-mode: Dort werden Gluons Seite
-- "Netzwerk" (dieselben gluon.iface_*-Rollen) und diese Seite gemeinsam
-- gespeichert, "Netzwerk" zuerst, commit als save. Der Cursor von oben kennt nur
-- den Stand von vor dem Absenden; ein frischer sieht die schon gespeicherten
-- Deltas. Unberuehrte Zeilen dieser Seite duerfen eine Aenderung auf
-- "Netzwerk" nicht zuruecknehmen.

local uci = require('simple-uci').cursor()
local portroles = require 'neanderfunk.portroles'

local pkg_i18n = i18n 'neanderfunk-port-roles'
local translate = pkg_i18n.translate
local translatef = pkg_i18n.translatef

local f = Form(translate('Ports'), translate(
	'Assign a role to each network port. A port without a role is not used. '
	.. 'These are the same settings as the interface roles on the "Network" page.'))

local s = f:section(Section, translate('Roles'))

local function role_option(id, title, default)
	local o = s:option(MultiListValue, id, title)
	o.orientation = 'horizontal'
	o:value('uplink', 'Uplink')
	o:value('mesh', 'Mesh')
	o:value('client', 'Client')
	o:exclusive('uplink', 'client')
	o:exclusive('mesh', 'client')
	o.default = default
	return o
end

-- Was diese Seite schreiben will, gesammelt bis f:write (gluon-web schreibt
-- erst alle Optionen, dann das Formular): Rollen je Port (das Herausloesen und
-- Zurueckholen muss alle Ports einer Gruppe zugleich sehen), Rollen ganzer
-- Gruppen (swconfig), VLAN-Listen je Port, Mesh-Modus.
local desired, group_roles, vlan_lists, new_mode = {}, {}, {}, nil

local function list_key(list, numeric)
	local ret = {}
	for _, v in ipairs(list or {}) do
		if v ~= '' then
			table.insert(ret, numeric and tostring(tonumber(v)) or tostring(v))
		end
	end
	table.sort(ret)
	return table.concat(ret, ' ')
end

for _, row in ipairs(portroles.rows(uci)) do
	if row.port then
		local port = row.port
		-- hinter swconfig heisst der einzige "Port" einer Gruppe eth0.1 - dann
		-- die Gruppe dazuschreiben: "LAN (eth0.1)"
		local title = port
		local group = row.section and row.section:match('^iface_(%a+)$')
		if not portroles.splittable(port) and (group == 'lan' or group == 'wan' or group == 'single') then
			title = group:upper() .. ' (' .. port .. ')'
		end
		local shown = row.section and uci:get_list('gluon', row.section, 'role') or {}
		local o = role_option('port_' .. port:gsub('[^%w]', '_'), title, shown)
		function o:write(data)
			if list_key(data) ~= list_key(shown) then
				desired[port] = data or {}
			end
		end
	else
		local section_name = row.section
		local shown = uci:get_list('gluon', section_name, 'role')
		local o = role_option(section_name, table.concat(row.ports, ' '), shown)
		function o:write(data)
			if list_key(data) ~= list_key(shown) then
				group_roles[section_name] = data or {}
			end
		end
	end
end

-- VLANs je Port: jedes VLAN ist eine eigene gluon.iface_*-Sektion mit
-- name='<port>.<vid>'. netifd legt das VLAN-Unterinterface an, wenn es in einer
-- Bridge oder einem Interface auftaucht. Neue VLANs kommen ohne Rolle an; ihre
-- Zeile erscheint nach dem Speichern oben bei den Rollen. f:write legt erst die
-- VLANs an bzw. loescht sie und setzt dann die Rollen; die Rolle eines in
-- derselben Speicherung entfernten VLANs faellt damit weg.
local physical = {}
for _, row in ipairs(portroles.rows(uci)) do
	if row.port and portroles.splittable(row.port) then
		table.insert(physical, row.port)
	end
end
if #physical > 0 then
	local v = f:section(Section, translate('VLANs'), translate(
		'Tagged VLANs on a single port, entered as VLAN IDs (1-4094). After saving, '
		.. 'each VLAN appears as its own line under "Roles" (for example "lan3.5") '
		.. 'and gets its roles there; a VLAN without a role is not used. The same '
		.. 'VLAN ID can have different roles on different ports.'))
	for _, port in ipairs(physical) do
		local o = v:option(DynamicList, 'vlans_' .. port:gsub('[^%w]', '_'), port)
		o.datatype = 'irange(1, 4094)'
		o.optional = true
		local shown = portroles.vlans_of(uci, port)
		o.default = shown
		function o:write(data)
			if list_key(data, true) ~= list_key(shown, true) then
				vlan_lists[port] = data or {}
			end
		end
	end
end

-- Hinweis fuer Ports hinter swconfig
local groups = portroles.group_only_sections(uci)
if #groups > 0 then
	local names = {}
	for _, g in ipairs(groups) do
		table.insert(names, table.concat(g.ports, ' '))
	end
	f:section(Section, translate('Ports behind a switch without per-port access'), translatef(
		'%s: the ports behind this interface sit on a switch configured with swconfig '
		.. 'and appear as a single interface. Roles apply to all of them together; single '
		.. 'ports and VLANs per port cannot be set here. On such a switch a VLAN spans '
		.. 'the whole switch, so the same VLAN ID could not have different roles on '
		.. 'different ports.', table.concat(names, ', ')))
end

-- Was die Hardware kann, fuer die Ports, die jetzt im LAN-Mesh sind
local mesh_ports = portroles.mesh_other_ports(uci)
local facts = {}
for _, port in ipairs(mesh_ports) do
	local info = portroles.port_info(port)
	if not info.on_switch then
		table.insert(facts, translatef('%s: own network interface, isolation works', port))
	elseif info.hw_isolation then
		table.insert(facts, translatef('%s: switch (%s), isolation works in hardware', port, info.driver or '?'))
	else
		table.insert(facts, translatef('%s: switch (%s), no isolation in hardware', port, info.driver or '?'))
	end
end

local description = translate(
	'How LAN ports with the "Mesh" role are joined. "Isolated" keeps them from '
	.. 'forwarding to each other; on switches that cannot do this in hardware, '
	.. '"separate bridges" gives the same result with one mesh interface per port.')
if #mesh_ports > 1 then
	local auto = portroles.effective_mode('auto', mesh_ports)
	description = description .. ' ' .. table.concat(facts, '; ') .. '. '
		.. translatef('"Automatic" currently means: %s.',
			auto == 'isolate' and translate('isolated') or translate('separate bridges'))
elseif #mesh_ports == 1 then
	description = description .. ' ' .. translate('Only one LAN port has the "Mesh" role; the mode does not matter.')
end

local m = f:section(Section, translate('Wired mesh between LAN ports'), description)
local mode = m:option(ListValue, 'mesh_mode', translate('Mode'))
mode:value('isolate', translate('Isolated (one bridge, Gluon default)'))
mode:value('auto', translate('Automatic'))
mode:value('separate', translate('Isolated (separate bridges)'))
mode:value('bridge', translate('Bridged, not isolated'))
mode.default = portroles.get_mode(uci)
function mode:write(data)
	if data ~= mode.default then
		new_mode = data
	end
end

function f:write()
	local c = require('simple-uci').cursor()
	for port, vids in pairs(vlan_lists) do
		portroles.set_vlans(c, port, vids)
	end
	for section, roles in pairs(group_roles) do
		if c:get('gluon', section) then
			if #roles > 0 then
				c:set_list('gluon', section, 'role', roles)
			else
				c:delete('gluon', section, 'role')
			end
		end
	end
	portroles.apply(c, desired)
	if new_mode then
		if not c:get('gluon', 'port_roles') then
			c:section('gluon', 'port_roles', 'port_roles', {})
		end
		c:set('gluon', 'port_roles', 'mesh_mode', new_mode)
	end
	c:commit('gluon')
end

return f
