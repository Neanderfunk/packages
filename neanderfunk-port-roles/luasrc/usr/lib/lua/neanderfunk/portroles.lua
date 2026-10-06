-- SPDX-License-Identifier: BSD-3-Clause
-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
--
-- Gemeinsame Helfer fuer neanderfunk-port-roles: die beiden Upgrade-Skripte
-- und die Seite "Ports" im Config-Mode. Siehe README des Pakets.

local bit = require 'bit32'
local hash = require 'hash'
local sysconfig = require 'gluon.sysconfig'
local unistd = require 'posix.unistd'
local util = require 'gluon.util'

local M = {}

M.MODES = { 'isolate', 'auto', 'bridge', 'separate' }

--- Portnamen aus gluon.iface_*.name. "/lan", "/wan", "/single" verweisen wie
--- in Gluons get_role_interfaces auf die Board-Ports in sysconfig.
function M.resolve(name)
	local ret = {}
	if type(name) ~= 'string' then
		return ret
	end
	if name:sub(1, 1) == '/' then
		name = sysconfig[name:sub(2) .. '_ifname'] or ''
	end
	for port in name:gmatch('%S+') do
		table.insert(ret, port)
	end
	return ret
end

--- VLAN-Unterinterface wie "lan3.5" (auf einem DSA-Port oder einer Karte)
--- oder "eth0.1" (hinter swconfig).
function M.is_vlan(port)
	return port:find('.', 1, true) ~= nil
end

--- Ein Port, der sich einzeln verwenden laesst: eigenes Netdev und kein VLAN.
--- Hinter swconfig haengen alle LAN-Ports an einem "eth0.1"; die bleiben, wie
--- sie sind.
function M.splittable(port)
	return not M.is_vlan(port) and unistd.access('/sys/class/net/' .. port) == 0
end

local function sanitize(s)
	return (s:gsub('[^%w]', '_'))
end

local BOARD_GROUPS = { 'lan', 'wan', 'single' }

--- Sektionsname fuer einen Port oder ein VLAN ("lan3.5"), wie ihn auch der
--- Befehl portrole (neanderfunk-banner) vergibt: gluon.iface_<port>, "." wird
--- "_". Waere der Name schon anders belegt (eine Board-Gruppe iface_lan/_wan/
--- _single, oder eine Sektion mit anderen Ports), dann iface_port_<port>.
function M.port_section(uci, port)
	local name = 'iface_' .. sanitize(port)
	local taken = false
	for _, g in ipairs(BOARD_GROUPS) do
		if name == 'iface_' .. g then
			taken = true
		end
	end
	if not taken and uci:get('gluon', name) then
		local ports = M.resolve(uci:get('gluon', name, 'name'))
		taken = not (#ports == 1 and ports[1] == port)
	end
	if taken then
		name = 'iface_port_' .. sanitize(port)
	end
	return name
end

--- Ist das eine Sektion, die nur fuer diesen einen Port angelegt wurde (von
--- dieser Seite oder von portrole)? Nur solche loest die Seite wieder auf, wenn
--- der Port zur Rolle seiner Gruppe zurueckkehrt; Gluons Gruppen und
--- iface_extra_* (neanderfunk-legacy-migrate) bleiben stehen.
function M.own_section(name, port)
	return name == 'iface_' .. sanitize(port) or name == 'iface_port_' .. sanitize(port)
end

--- Board-Ports einer Gruppe ("lan", "wan", "single") aus sysconfig.
local function board_ports(group)
	return M.resolve('/' .. group)
end

--- Zu welcher Board-Gruppe ein Port gehoert ("iface_lan" ...), sonst nil.
function M.home_group(port)
	for _, g in ipairs(BOARD_GROUPS) do
		if util.contains(board_ports(g), port) then
			return 'iface_' .. g
		end
	end
	return nil
end

--- Zeilen der Seite "Ports": je einzeln verwendbarem Port eine Zeile, auch
--- wenn er (wie ab Werk) in einer Gruppe steckt; Sektionen, deren Ports sich
--- nicht einzeln verwenden lassen (swconfig "eth0.1"), als eine Zeile.
--- Eintraege: { port = <name>, section = <Sektion oder nil> } bzw.
--- { section = <Sektion>, ports = { ... } }.
function M.rows(uci)
	local rows, seen = {}, {}
	uci:foreach('gluon', 'interface', function(s)
		local ports = M.resolve(s.name)
		if #ports == 0 then
			return
		end
		local single = #ports == 1
		if not single then
			single = true
			for _, port in ipairs(ports) do
				if not M.splittable(port) then
					single = false
				end
			end
		end
		if single then
			for _, port in ipairs(ports) do
				if not seen[port] then
					seen[port] = true
					table.insert(rows, { port = port, section = s['.name'] })
				end
			end
		else
			table.insert(rows, { section = s['.name'], ports = ports })
			for _, port in ipairs(ports) do
				seen[port] = true
			end
		end
	end)
	-- Board-Ports, die in keiner Sektion stehen (von Hand aus einer Liste
	-- genommen): ohne Rolle anzeigen, damit man sie zurueckholen kann
	for _, g in ipairs(BOARD_GROUPS) do
		for _, port in ipairs(board_ports(g)) do
			if not seen[port] and M.splittable(port) then
				seen[port] = true
				table.insert(rows, { port = port })
			end
		end
	end
	return rows
end

local function sorted(list)
	local ret = {}
	for _, v in ipairs(list or {}) do
		table.insert(ret, v)
	end
	table.sort(ret)
	return ret
end

local function same(a, b)
	a, b = sorted(a), sorted(b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end
M.same_roles = same

local function set_roles(uci, section, roles)
	if roles and #roles > 0 then
		uci:set_list('gluon', section, 'role', roles)
	else
		uci:delete('gluon', section, 'role')
	end
end

--- Gruppen-Name aus einer Portliste: die volle Board-Liste wieder als "/lan".
local function group_name(section, ports)
	local g = section:match('^iface_(.*)$')
	local full = g and util.contains(BOARD_GROUPS, g) and board_ports(g) or nil
	if full and #full > 0 and same(full, ports) then
		return '/' .. g
	end
	return table.concat(sorted(ports), ' ')
end

--- Gewuenschte Rollen je Port umsetzen, desired[port] = { 'mesh', ... }.
---
--- Eingegriffen wird nur, wo sich etwas aendert (wie portrole):
--- * Ein Port einer Gruppe mit der Rolle der Gruppe bleibt in der Gruppe.
--- * Ein Port mit anderer Rolle wird herausgeloest: die Gruppe behaelt die
---   uebrigen Ports, der Port bekommt gluon.iface_<port>.
--- * Wollen alle Ports einer Gruppe dieselbe neue Rolle, bekommt die Gruppe
---   diese Rolle, statt zerlegt zu werden.
--- * Kehrt ein herausgeloester Port zur Rolle seiner Board-Gruppe zurueck,
---   wandert er wieder hinein, und seine eigene Sektion entfaellt. Ist die
---   Gruppe wieder vollstaendig, steht dort wieder "/lan".
function M.apply(uci, desired)
	local groups = {}   -- Sektion -> { ports = {...}, role = {...}, hp = ... }
	local splits = {}   -- { port, role, hp }
	local singles = {}  -- { section, port }

	uci:foreach('gluon', 'interface', function(s)
		local ports = M.resolve(s.name)
		if #ports == 0 then
			return
		end
		local relevant = false
		for _, port in ipairs(ports) do
			if desired[port] then
				relevant = true
			end
		end
		if not relevant then
			return
		end
		if #ports == 1 then
			table.insert(singles, { section = s['.name'], port = ports[1] })
			return
		end
		-- get_list statt s.role: eine von Hand per "uci set" gesetzte Rolle ist ein
		-- String, keine Liste
		local cur = uci:get_list('gluon', s['.name'], 'role')
		local role = nil
		for _, port in ipairs(ports) do
			if desired[port] and same(desired[port], cur) then
				role = cur
			end
		end
		if not role then
			role = desired[ports[1]] or cur
		end
		local keep = {}
		for _, port in ipairs(ports) do
			if desired[port] and not same(desired[port], role) then
				table.insert(splits, { port = port, role = desired[port], hp = s.batadv_hop_penalty })
			else
				table.insert(keep, port)
			end
		end
		groups[s['.name']] = { ports = keep, role = role, changed = #keep ~= #ports or not same(role, cur) }
	end)

	local function group_of(section)
		if not groups[section] and uci:get('gluon', section) then
			groups[section] = {
				ports = M.resolve(uci:get('gluon', section, 'name')),
				role = uci:get_list('gluon', section, 'role'),
				changed = false,
			}
		end
		return groups[section]
	end

	local joined = {}
	local function rejoin(port, section)
		local home = M.home_group(port)
		if not home or home == section then
			return false
		end
		local g = group_of(home)
		if not g or #g.ports == 0 or not same(g.role, desired[port]) then
			return false
		end
		if not util.contains(g.ports, port) then
			table.insert(g.ports, port)
		end
		g.changed = true
		joined[port] = true
		return true
	end

	for _, s in ipairs(singles) do
		if M.own_section(s.section, s.port) and rejoin(s.port, s.section) then
			uci:delete('gluon', s.section)
		elseif not groups[s.section] then
			if not same(uci:get_list('gluon', s.section, 'role'), desired[s.port]) then
				set_roles(uci, s.section, desired[s.port])
			end
		else
			-- eine Gruppe, die nur noch diesen Port hat
			groups[s.section].role = desired[s.port]
			groups[s.section].changed = true
		end
	end

	-- Board-Ports ohne Sektion
	local assigned = {}
	uci:foreach('gluon', 'interface', function(s)
		for _, port in ipairs(M.resolve(s.name)) do
			assigned[port] = true
		end
	end)
	-- (nur Board-Ports: ein VLAN, das in derselben Speicherung entfernt wurde,
	-- hat noch einen Wunsch, aber keine Sektion mehr und soll weg bleiben)
	for port, roles in pairs(desired) do
		if not assigned[port] and not joined[port] and M.home_group(port) and not rejoin(port, nil) then
			table.insert(splits, { port = port, role = roles })
		end
	end

	for section, g in pairs(groups) do
		if g.changed then
			uci:set('gluon', section, 'name', group_name(section, g.ports))
			set_roles(uci, section, g.role)
		end
	end
	for _, sp in ipairs(splits) do
		local section = M.port_section(uci, sp.port)
		uci:section('gluon', 'interface', section, {
			name = sp.port,
			batadv_hop_penalty = sp.hp,
		})
		set_roles(uci, section, sp.role)
	end
end

--- VLANs eines Ports auf die Liste vids bringen: fehlende als eigene Sektion
--- (gluon.iface_<port>_<vid>, name='<port>.<vid>', ohne Rolle) anlegen,
--- ueberzaehlige loeschen. Ein neues VLAN bekommt seine Rolle danach in einer
--- eigenen Zeile der Seite.
function M.set_vlans(uci, port, vids)
	local want = {}
	for _, vid in ipairs(vids or {}) do
		local n = tonumber(vid)
		if n then
			want[tostring(n)] = true
		end
	end
	local have = {}
	for _, vid in ipairs(M.vlans_of(uci, port)) do
		have[vid] = true
	end
	for vid in pairs(want) do
		if not have[vid] then
			uci:section('gluon', 'interface', M.port_section(uci, port .. '.' .. vid), {
				name = port .. '.' .. vid,
			})
		end
	end
	local pattern = '^' .. port:gsub('%p', '%%%0') .. '%.(%d+)$'
	local remove = {}
	uci:foreach('gluon', 'interface', function(sec)
		local vid = type(sec.name) == 'string' and sec.name:match(pattern)
		if vid and not want[vid] then
			table.insert(remove, sec['.name'])
		end
	end)
	for _, name in ipairs(remove) do
		uci:delete('gluon', name)
	end
end

--- VLAN-IDs, die auf einem Port als eigene Sektion ("<port>.<vid>") stehen.
function M.vlans_of(uci, port)
	local ret = {}
	uci:foreach('gluon', 'interface', function(s)
		local ports = M.resolve(s.name)
		local vid = #ports == 1 and ports[1]:match('^' .. port:gsub('%p', '%%%0') .. '%.(%d+)$')
		if vid then
			table.insert(ret, vid)
		end
	end)
	table.sort(ret, function(x, y) return tonumber(x) < tonumber(y) end)
	return ret
end

--- Gluons Board-Sektionen, deren Ports sich nicht einzeln verwenden lassen:
--- ein Verweis wie "/lan", der auf ein VLAN-Unterinterface zeigt - so sehen
--- LAN-Ports hinter swconfig aus ("eth0.1"). Von Hand angelegte VLAN-Sektionen
--- (explizite Namen) zaehlen nicht dazu.
function M.group_only_sections(uci)
	local ret = {}
	uci:foreach('gluon', 'interface', function(s)
		if type(s.name) ~= 'string' or s.name:sub(1, 1) ~= '/' then
			return
		end
		local ports = M.resolve(s.name)
		for _, port in ipairs(ports) do
			if M.is_vlan(port) then
				table.insert(ret, { section = s['.name'], ports = ports })
				return
			end
		end
	end)
	return ret
end

local function kernel_at_least(major, minor)
	local ma, mi = (util.readfile('/proc/sys/kernel/osrelease') or ''):match('^(%d+)%.(%d+)')
	ma, mi = tonumber(ma), tonumber(mi)
	if not ma then
		return false
	end
	return ma > major or (ma == major and mi >= minor)
end

--- Was ueber einen Port bekannt ist, der Mesh machen soll.
---
--- on_switch: der Port gehoert zu einem Switch mit Hardware-Bridging
---   (switchdev/DSA, erkennbar an phys_switch_id). Ports ohne das - etwa
---   eigene Netzwerkkarten auf x86 - bridged der Kernel in Software, dort
---   wirkt "isolate" immer.
--- hw_isolation: "isolate" wirkt auf diesem Port. Auf einem Switch nur, wenn
---   der Treiber BR_ISOLATED in Hardware umsetzt: mt7530/mt7531 und qca8k
---   (auch qca8k-ipq4019) koennen das ab Kernel 6.6 mit OpenWrts Backports aus
---   v6.11 (790-56, 793-03). Kernel 5.15 (Gluon 2023.2) reicht das Flag gar
---   nicht an den Switch weiter.
function M.port_info(port)
	if M.is_vlan(port) then
		-- VLAN-Unterinterfaces bridged der Kernel in Software, auch auf einem
		-- DSA-Port: dort wirkt "isolate" immer. (Beim Reconfigure gibt es sie
		-- ohnehin noch nicht, netifd legt sie erst an.)
		return { on_switch = false, vlan = true, hw_isolation = true }
	end
	local base = '/sys/class/net/' .. port
	local switch_id = util.trim(util.readfile(base .. '/phys_switch_id') or '')
	local link = unistd.readlink(base .. '/device/driver')
	local driver = link and link:match('([^/]+)$') or nil
	local on_switch = switch_id ~= ''
	local capable = driver ~= nil and (driver:match('^mt753') ~= nil or driver:match('^qca8k') ~= nil)
	return {
		on_switch = on_switch,
		driver = driver,
		hw_isolation = (not on_switch) or (capable and kernel_at_least(6, 6)),
	}
end

--- Eingestellter Mesh-Modus. Ohne Einstellung (oder bei Unbekanntem)
--- "isolate", also Gluons eigener Aufbau: ein Knoten, an dem niemand die Seite
--- benutzt, bleibt genau so, wie Gluon ihn baut.
function M.get_mode(uci)
	local mode = uci:get('gluon', 'port_roles', 'mesh_mode')
	for _, m in ipairs(M.MODES) do
		if m == mode then
			return mode
		end
	end
	return 'isolate'
end

--- Was "auto" fuer diese Ports bedeutet: "isolate", wenn es auf allen wirkt,
--- sonst getrennte Bridges.
function M.effective_mode(mode, ports)
	if mode ~= 'auto' then
		return mode
	end
	for _, port in ipairs(ports) do
		if not M.port_info(port).hw_isolation then
			return 'separate'
		end
	end
	return 'isolate'
end

--- Ports, die im kabelgebundenen Mesh ohne Uplink landen - dieselbe Auswahl,
--- die Gluons 210-interface-mesh fuer mesh_other trifft.
function M.mesh_other_ports(uci)
	local mesh, uplink, ret = {}, {}, {}
	uci:foreach('gluon', 'interface', function(s)
		local roles = uci:get_list('gluon', s['.name'], 'role')
		for _, port in ipairs(M.resolve(s.name)) do
			if util.contains(roles, 'mesh') then
				mesh[port] = true
			end
			if util.contains(roles, 'uplink') then
				uplink[port] = true
			end
		end
	end)
	for port in pairs(mesh) do
		if not uplink[port] then
			table.insert(ret, port)
		end
	end
	table.sort(ret)
	return ret
end

--- Stabile, eigene MAC fuer die Mesh-Bridge eines Ports.
---
--- Gluons generate_mac() leitet aus der primaeren MAC nur 8 Adressen ab (die
--- letzten 3 Bit), und die sind vergeben. Alle DSA-Ports teilen sich die MAC des
--- CPU-Ports; ohne VXLAN sitzt batman-adv direkt auf der Bridge, und doppelte
--- Adressen je Knoten vertraegt es nicht. Deshalb ein eigener Hash ueber
--- primaere MAC und Portnamen: lokal verwaltet, kein Multicast, aendert sich
--- nicht zwischen Reboots und Updates.
function M.mac_for(port)
	local h = hash.md5((sysconfig.primary_mac or '') .. '/neanderfunk-port-roles/' .. port)
	local b = {}
	for i = 1, 6 do
		b[i] = tonumber(h:sub(2 * i - 1, 2 * i), 16)
	end
	b[1] = bit.band(bit.bor(b[1], 0x02), 0xFE)
	return string.format('%02x:%02x:%02x:%02x:%02x:%02x', b[1], b[2], b[3], b[4], b[5], b[6])
end

local reserved = { mesh_other = true, mesh_uplink = true, mesh_vpn = true }

--- Name der Mesh-Schnittstelle eines Ports bei getrennten Bridges. Die Bridge
--- heisst "br-<name>", und Netdev-Namen haben hoechstens 15 Zeichen - also
--- hoechstens 12 fuer den Namen. Kollisionen mit Gluons eigenen Namen und zu
--- lange Namen weichen auf mesh_p<n> aus.
function M.mesh_ifname(port, index)
	local name = 'mesh_' .. sanitize(port)
	if #name > 12 or reserved[name] or name:match('^mesh_radio') then
		name = 'mesh_p' .. index
	end
	return name
end

return M
