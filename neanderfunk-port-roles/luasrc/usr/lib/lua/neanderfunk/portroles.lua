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

M.MODES = { 'auto', 'bridge', 'isolate', 'separate' }

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

--- Sektionsname fuer einen Port bzw. ein VLAN auf einem Port.
function M.port_section(port)
	return 'iface_port_' .. sanitize(port)
end

function M.vlan_section(port, vid)
	return 'iface_port_' .. sanitize(port) .. '_' .. vid
end

--- Einzeln verwendbare Ports, die eine eigene Sektion haben - die, auf denen
--- VLANs angelegt werden koennen.
function M.physical_ports(uci)
	local ret, seen = {}, {}
	uci:foreach('gluon', 'interface', function(s)
		local ports = M.resolve(s.name)
		if #ports == 1 and not seen[ports[1]] and M.splittable(ports[1]) then
			seen[ports[1]] = true
			table.insert(ret, ports[1])
		end
	end)
	table.sort(ret)
	return ret
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

--- Eingestellter Mesh-Modus, "auto" wenn nichts oder Unbekanntes gesetzt ist.
function M.get_mode(uci)
	local mode = uci:get('gluon', 'port_roles', 'mesh_mode')
	for _, m in ipairs(M.MODES) do
		if m == mode then
			return mode
		end
	end
	return 'auto'
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
		local roles = s.role or {}
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
