-- SPDX-License-Identifier: BSD-3-Clause
-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
--
-- Host-Test fuer portroles.rows/apply mit einem uci im Speicher.
-- Aufruf aus dem Paketverzeichnis: lua5.1 tests/apply_test.lua

package.path = 'luasrc/usr/lib/lua/?.lua;' .. package.path

local SYS = {}
local NETDEVS = {}
package.loaded['gluon.sysconfig'] = setmetatable({}, { __index = function(_, k) return SYS[k] end })
package.loaded['gluon.util'] = {
	contains = function(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end,
	trim = function(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end,
	readfile = function() return nil end,
}
package.loaded['posix.unistd'] = {
	access = function(p) return NETDEVS[p:match('[^/]+$')] and 0 or nil end,
	readlink = function() return nil end,
}
package.loaded['bit32'] = {}
package.loaded['hash'] = {}

local function new_uci(sections)
	local data, order = {}, {}
	local u = {}
	for _, s in ipairs(sections) do
		data[s[1]] = s[2]; data[s[1]]['.type'] = 'interface'; table.insert(order, s[1])
	end
	function u:get(_, sec, opt)
		if not data[sec] then return nil end
		if not opt then return data[sec]['.type'] end
		return data[sec][opt]
	end
	function u:get_list(_, sec, opt)
		local v = data[sec] and data[sec][opt]
		if type(v) == 'table' then local c = {} for i, x in ipairs(v) do c[i] = x end return c end
		return v and { v } or {}
	end
	function u:set(_, sec, opt, v) data[sec][opt] = v end
	function u:set_list(_, sec, opt, v) data[sec][opt] = v end
	function u:delete(_, sec, opt)
		if opt then if data[sec] then data[sec][opt] = nil end return end
		data[sec] = nil
		for i, n in ipairs(order) do if n == sec then table.remove(order, i) break end end
	end
	function u:section(_, typ, name, values)
		data[name] = { ['.type'] = typ }
		for k, v in pairs(values or {}) do data[name][k] = v end
		table.insert(order, name)
	end
	function u:foreach(_, typ, fn)
		local snapshot = {}
		for _, n in ipairs(order) do snapshot[#snapshot + 1] = n end
		for _, n in ipairs(snapshot) do
			local s = data[n]
			if s and s['.type'] == typ then
				local c = { ['.name'] = n }
				for k, v in pairs(s) do c[k] = v end
				fn(c)
			end
		end
	end
	u.data, u.order = data, order
	return u
end

local portroles = require 'neanderfunk.portroles'

local fails = 0
local function dump(u)
	local out = {}
	for _, n in ipairs(u.order) do
		local s = u.data[n]
		local r = type(s.role) == 'table' and table.concat(s.role, '+') or (s.role or '-')
		table.insert(out, n .. '=' .. tostring(s.name) .. ':' .. r)
	end
	return table.concat(out, ' ')
end
local function check(title, u, want)
	local got = dump(u)
	if got ~= want then
		fails = fails + 1
		print('FAIL ' .. title .. '\n  got:  ' .. got .. '\n  want: ' .. want)
	else
		print('ok   ' .. title)
	end
end

local function board(lan, wan)
	SYS = { lan_ifname = lan, wan_ifname = wan }
	NETDEVS = {}
	for p in ((lan or '') .. ' ' .. (wan or '')):gmatch('%S+') do NETDEVS[p] = true end
end
local function fresh()
	return new_uci({
		{ 'iface_wan', { name = '/wan', role = { 'uplink' } } },
		{ 'iface_lan', { name = '/lan', role = { 'client' } } },
	})
end

board('lan1 lan2 lan3', 'wan')

-- 1. nichts geaendert: Aufbau bleibt
local u = fresh()
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'client' }, lan2 = { 'client' }, lan3 = { 'client' } })
check('unveraendert', u, 'iface_wan=/wan:uplink iface_lan=/lan:client')

-- 2. lan3 auf mesh: herausloesen
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'client' }, lan2 = { 'client' }, lan3 = { 'mesh' } })
check('lan3 mesh', u, 'iface_wan=/wan:uplink iface_lan=lan1 lan2:client iface_lan3=lan3:mesh')

-- 3. lan3 zurueck auf client: wieder /lan, eigene Sektion weg
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'client' }, lan2 = { 'client' }, lan3 = { 'client' } })
check('lan3 zurueck', u, 'iface_wan=/wan:uplink iface_lan=/lan:client')

-- 4. alle LAN auf mesh: Gruppe bekommt die Rolle, keine Zerlegung
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'mesh' }, lan2 = { 'mesh' }, lan3 = { 'mesh' } })
check('alle mesh', u, 'iface_wan=/wan:uplink iface_lan=/lan:mesh')

-- 5. gemischt ohne die alte Rolle: Gruppe nimmt die Rolle des ersten Ports
portroles.apply(u, { wan = { 'uplink', 'mesh' }, lan1 = { 'client' }, lan2 = {}, lan3 = { 'client' } })
check('gemischt', u, 'iface_wan=/wan:uplink+mesh iface_lan=lan1 lan3:client iface_lan2=lan2:-')

-- 6. lan2 bekommt die Gruppenrolle zurueck
portroles.apply(u, { wan = { 'uplink', 'mesh' }, lan1 = { 'client' }, lan2 = { 'client' }, lan3 = { 'client' } })
check('lan2 zurueck', u, 'iface_wan=/wan:uplink+mesh iface_lan=/lan:client')

-- 7. von portrole angelegte Sektion und iface_extra (legacy-migrate) bleiben Sektionen
board('lan1 lan2', 'wan')
NETDEVS.eth2 = true
u = new_uci({
	{ 'iface_wan', { name = '/wan', role = { 'uplink' } } },
	{ 'iface_lan', { name = 'lan1', role = { 'client' } } },
	{ 'iface_lan2', { name = 'lan2', role = { 'mesh' } } },
	{ 'iface_extra_eth2', { name = 'eth2', role = { 'client' } } },
})
local rows = {}
for _, r in ipairs(portroles.rows(u)) do table.insert(rows, r.port or ('[' .. r.section .. ']')) end
local got = table.concat(rows, ' ')
if got ~= 'wan lan1 lan2 eth2' then fails = fails + 1; print('FAIL rows: ' .. got) else print('ok   rows') end
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'client' }, lan2 = { 'client' }, eth2 = { 'mesh' } })
check('portrole-Sektion zurueck, extra bleibt', u, 'iface_wan=/wan:uplink iface_lan=/lan:client iface_extra_eth2=eth2:mesh')

-- 8. swconfig: eine Zeile je Gruppe, nicht zerlegbar
board('eth0.1', 'eth0.2')
u = fresh()
rows = {}
for _, r in ipairs(portroles.rows(u)) do table.insert(rows, r.port or ('[' .. r.section .. ']')) end
got = table.concat(rows, ' ')
-- eth0.1/eth0.2 sind einzelne Eintraege (je Gruppe ein Port): Zeile je Port
if got ~= 'eth0.2 eth0.1' then fails = fails + 1; print('FAIL rows swconfig: ' .. got) else print('ok   rows swconfig') end

-- 9. Port ohne Sektion (von Hand aus der Liste genommen) wird wieder aufgenommen
board('lan1 lan2', 'wan')
u = new_uci({
	{ 'iface_wan', { name = '/wan', role = { 'uplink' } } },
	{ 'iface_lan', { name = 'lan1', role = { 'client' } } },
})
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'client' }, lan2 = { 'client' } })
check('verwaister Port', u, 'iface_wan=/wan:uplink iface_lan=/lan:client')

-- 10. VLAN: eigene Sektion nach portrole-Schema, Rolle setzen
u = new_uci({
	{ 'iface_wan', { name = '/wan', role = { 'uplink' } } },
	{ 'iface_lan', { name = '/lan', role = { 'client' } } },
	{ 'iface_lan2_5', { name = 'lan2.5' } },
})
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'client' }, lan2 = { 'client' }, ['lan2.5'] = { 'mesh' } })
check('VLAN-Rolle', u, 'iface_wan=/wan:uplink iface_lan=/lan:client iface_lan2_5=lan2.5:mesh')

-- 11. Hop-Penalty der Gruppe wandert mit
u = new_uci({
	{ 'iface_wan', { name = '/wan', role = { 'uplink' } } },
	{ 'iface_lan', { name = '/lan', role = { 'mesh' }, batadv_hop_penalty = '30' } },
})
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'mesh' }, lan2 = { 'client' } })
local hp = u.data.iface_lan2 and u.data.iface_lan2.batadv_hop_penalty
if hp ~= '30' then fails = fails + 1; print('FAIL hop penalty: ' .. tostring(hp)) else print('ok   hop penalty') end

-- 12. Rolle als Option (String) statt Liste, wie nach "uci set ...role=mesh"
board('lan1 lan2', 'wan')
u = new_uci({
	{ 'iface_wan', { name = '/wan', role = 'uplink' } },
	{ 'iface_lan', { name = '/lan', role = 'mesh' } },
})
portroles.apply(u, { wan = { 'uplink' }, lan1 = { 'mesh' }, lan2 = { 'client' } })
check('Rolle als String', u, 'iface_wan=/wan:uplink iface_lan=lan1:mesh iface_lan2=lan2:client')

print(fails == 0 and 'alle Tests gruen' or (fails .. ' Fehler'))
os.exit(fails == 0 and 0 or 1)
