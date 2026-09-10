-- SPDX-License-Identifier: BSD-3-Clause
-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
--
-- Seite "Ports": eine Rolle je Port und der Mesh-Modus fuer die LAN-Mesh-Ports.
-- Die Rollen sind dieselben gluon.iface_*-Sektionen, die auch Gluons Seite
-- "Netzwerk" zeigt; 025-neanderfunk-port-roles legt sie je Port an. Gespeichert
-- wird wie dort nur per commit - wirksam wird es mit dem gluon-reconfigure beim
-- "Speichern & Neustarten" im Wizard.

local uci = require('simple-uci').cursor()
local portroles = require 'neanderfunk.portroles'

local pkg_i18n = i18n 'neanderfunk-port-roles'
local translate = pkg_i18n.translate
local translatef = pkg_i18n.translatef

local f = Form(translate('Ports'), translate(
	'Assign a role to each network port. A port without a role is not used. '
	.. 'These are the same settings as the interface roles on the "Network" page.'))

local s = f:section(Section, translate('Roles'))

uci:foreach('gluon', 'interface', function(config)
	local ports = portroles.resolve(config.name)
	if #ports == 0 then
		-- Gruppen-Sektion, deren Ports in eigene Sektionen gewandert sind
		return
	end
	local section_name = config['.name']
	local o = s:option(MultiListValue, section_name, table.concat(ports, ' '))
	o.orientation = 'horizontal'
	o:value('uplink', 'Uplink')
	o:value('mesh', 'Mesh')
	o:value('client', 'Client')
	o:exclusive('uplink', 'client')
	o:exclusive('mesh', 'client')
	o.default = config.role
	function o:write(data)
		uci:set_list('gluon', section_name, 'role', data)
	end
end)

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
mode:value('auto', translate('Automatic'))
mode:value('isolate', translate('Isolated (one bridge)'))
mode:value('separate', translate('Isolated (separate bridges)'))
mode:value('bridge', translate('Bridged, not isolated'))
mode.default = portroles.get_mode(uci)
function mode:write(data)
	if not uci:get('gluon', 'port_roles') then
		uci:section('gluon', 'port_roles', 'port_roles', {})
	end
	uci:set('gluon', 'port_roles', 'mesh_mode', data)
end

function f:write()
	uci:commit('gluon')
end

return f
