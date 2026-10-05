-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
-- SPDX-License-Identifier: BSD-3-Clause
--
-- x86: LAN/WAN dauerhaft an die Netzwerkkarte binden statt an ethN.
--
-- Auf x86 setzt Gluons 020-interfaces bei jedem Reconfigure lan=eth0 und
-- wan=eth1, also nach der Reihenfolge, in der die Treiber laden. Die aendert
-- sich zwischen Kernel-Versionen (Gluon 2025.1 hat dafuer
-- 019-migrate-interface-order); im Feld sind die Ports bei groesseren
-- Spruengen mehrfach zwischen LAN und WAN gesprungen (adorfer).
--
-- Gebunden wird je Rolle (lan, wan) an zwei Merkmale, gespeichert in
-- sysconfig neanderfunk_bind_lan / _wan als "<mac> <pci>":
--   - die Hardware-MAC, nur lesbar, solange sie nicht ueberschrieben ist
--     (addr_assign_type 0; Gluon setzt im Betrieb eigene MACs, etwa fuer
--     mesh_other - beim Reconfigure nach einem Update sind sie noch echt),
--   - den Geraetepfad (PCI-Adresse), immer lesbar und unabhaengig von ethN.
local M = {}

local util = require 'gluon.util'
local unistd = require 'posix.unistd'

local function read(path)
	local v = util.readfile(path)
	return v and util.trim(v)
end

-- Physische Ethernet-Karten: mit device-Link, Typ 1 (Ethernet), kein WLAN.
function M.nics()
	local ret = {}
	for _, p in ipairs(util.glob('/sys/class/net/*')) do
		local name = p:match('[^/]+$')
		local dev = unistd.readlink(p .. '/device')
		if dev and read(p .. '/type') == '1' and not unistd.access(p .. '/phy80211') then
			local mac
			if read(p .. '/addr_assign_type') == '0' then
				mac = (read(p .. '/address') or ''):lower()
			end
			local drv = unistd.readlink(p .. '/device/driver')
			table.insert(ret, { name = name, mac = mac, dev = dev:match('[^/]+$'), driver = drv and drv:match('[^/]+$') })
		end
	end
	return ret
end

function M.find(nics, key)
	if not key then return nil end
	local mac, dev = key:match('^(%S*) (%S*)$')
	for _, n in ipairs(nics) do
		if mac ~= '' and n.mac == mac then return n end
	end
	for _, n in ipairs(nics) do
		if dev ~= '' and n.dev == dev then return n end
	end
end

function M.key(n)
	return (n.mac or '') .. ' ' .. n.dev
end

function M.byname(nics, name)
	for _, n in ipairs(nics) do
		if n.name == name then return n end
	end
end

-- Aufzaehlung von OpenWrt 14.07 bis 19.07 (Gluon 2014.4 bis 2021.1) auf x86:
-- erst fest eingebaute Treiber, dann /etc/modules-boot.d, dann /etc/modules.d,
-- jeweils nach Dateinamen sortiert (kmodloader), innerhalb eines Treibers nach
-- PCI-Adresse. Dateinamen aus package/kernel/linux/modules/netdevices.mk
-- (AutoLoad <prio>-<paket>, AutoProbe <paket>), in allen fuenf Versionen gleich;
-- eingebaut laut target/linux/x86/*/config-*.
local builtin = { virtio_net = true, vmxnet3 = true, vif = true }
local builtin_geode = { ['8139cp'] = true, ['8139too'] = true, natsemi = true, ['via-rhine'] = true }
local boot = { tg3 = '19-tg3' }
local modfile = {
	natsemi = '20-natsemi', e1000 = '35-e1000', igb = '35-igb', ixgbe = '35-ixgbe',
	['3c59x'] = '3c59x', ['8139cp'] = '8139cp', ['8139too'] = '8139too', atl1 = 'atl1',
	atl1c = 'atl1c', atl1e = 'atl1e', bnx2 = 'bnx2', e100 = 'e100', e1000e = 'e1000e',
	forcedeth = 'forcedeth', ['ne2k-pci'] = 'ne2k-pci', pcnet32 = 'pcnet32', r8169 = 'r8169',
	sis900 = 'sis900', skge = 'skge', sky2 = 'sky2', tulip = 'tulip', ['via-rhine'] = 'via-rhine',
	['via-velocity'] = 'via-velocity', via_velocity = 'via-velocity',
}

-- Karten in der Reihenfolge, in der die alte Firmware sie eth0, eth1 ...
-- genannt haette; nil und Grund, wenn ein Treiber unbekannt ist.
function M.old_order(nics, geode)
	local keyed = {}
	for _, n in ipairs(nics) do
		local d = n.driver
		local k
		if d and (builtin[d] or (geode and builtin_geode[d])) then
			k = '0 '
		elseif d and boot[d] then
			k = '1 ' .. boot[d]
		elseif d and modfile[d] then
			k = '2 ' .. modfile[d]
		else
			return nil, 'unknown driver ' .. tostring(d) .. ' on ' .. n.name
		end
		table.insert(keyed, { key = k .. ' ' .. n.dev, nic = n })
	end
	table.sort(keyed, function(a, b) return a.key < b.key end)
	local ret = {}
	for i, e in ipairs(keyed) do
		ret[i] = e.nic
	end
	return ret
end

-- Wofuer die alte Firmware ihre Karten benutzt hat, aus network_gluon-old
-- (001-reset-uci hat sie dorthin verschoben; OpenWrts
-- 11_network-migrate-bridges hat Bridge-Ports nur nach device/ports
-- umgezogen). Ergebnis: { eth0 = { wan = true }, eth1 = { mesh = true },
-- eth2 = { client = true } }; nur einfache ethN, keine VLANs.
local mesh_protos = { batadv = true, gluon_mesh = true, batadv_hardif = true }

function M.old_usage(uci)
	local cfg = 'network_gluon-old'
	local ports = {}
	uci:foreach(cfg, 'device', function(d)
		if d.name then
			ports[d.name] = d.ports or {}
		end
	end)
	local function members(i)
		local ret, seen = {}, {}
		local function add(tok)
			if seen[tok] then return end
			seen[tok] = true
			if ports[tok] then
				-- 2015.1: br-client nennt nach migrate-bridges sich selbst als Port
				for _, p in ipairs(ports[tok]) do add(p) end
			elseif tok:match('^eth%d+$') then
				ret[tok] = true
			end
		end
		local ifn = i.ifname
		if type(ifn) == 'table' then ifn = table.concat(ifn, ' ') end
		for tok in (ifn or ''):gmatch('%S+') do add(tok) end
		if i.device then add(i.device) end
		return ret
	end
	local usage = {}
	local function mark(name, what)
		usage[name] = usage[name] or {}
		usage[name][what] = true
	end
	uci:foreach(cfg, 'interface', function(i)
		local on = i.auto ~= '0' and i.disabled ~= '1'
		local what
		if i['.name'] == 'wan' then
			what = 'wan'
		elseif mesh_protos[i.proto or ''] then
			what = on and 'mesh' or nil
		elseif i['.name'] == 'client' then
			what = 'client'
		end
		if what then
			for name in pairs(members(i)) do mark(name, what) end
		end
	end)
	return usage
end

-- Alte primaere MAC: sysconfig, sonst network.client.macaddr (Gluon bis 2021.1
-- setzt dort bei jedem Upgrade primary_mac ein, etwa 2014.4
-- 310-gluon-mesh-batman-adv-core-mesh).
function M.old_primary_mac(uci, sysconfig)
	local m = sysconfig.neanderfunk_old_primary_mac
	if m and m ~= '' then return m:lower() end
	m = uci:get('network_gluon-old', 'client', 'macaddr')
	if m and m:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$') then return m:lower() end
end

return M
