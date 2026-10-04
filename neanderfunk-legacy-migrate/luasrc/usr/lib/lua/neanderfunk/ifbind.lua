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
			table.insert(ret, { name = name, mac = mac, dev = dev:match('[^/]+$') })
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

return M
