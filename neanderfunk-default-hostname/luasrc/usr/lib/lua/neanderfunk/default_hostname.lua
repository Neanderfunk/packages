-- SPDX-License-Identifier: BSD-3-Clause
-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
--
-- Vorgabe-Hostname fuer neue Knoten: <hostname_prefix><Kurzname>-<letzte 4 der node_id>,
-- etwa "dias-WDR3600-1b8c" statt "dias-6466b3ce1b8c". Aufgerufen von
-- gluon.util.default_hostname() (Patch hostname/default-hostname in
-- gluon-patches-packages); Gluon setzt den Namen damit beim ersten Start
-- (upgrade/030-system), der Wizard nimmt ihn als Vorschlag.
--
-- Der Kurzname kommt aus dem Gluon-Image-Namen (platform_info), nicht aus
-- /tmp/sysinfo/model: der ist einheitlich klein und mit Bindestrichen
-- getrennt. Regel: Hersteller vorne weg, Hardware-Revision und Fuellwoerter
-- hinten weg, Vorsilben der Produktlinie weg oder kuerzer; Teile mit Ziffern
-- und kurze Teile gross, sonst mit grossem Anfangsbuchstaben.

local M = {}

local vendors = {
	'extreme-networks', 'hewlett-packard', 'alfa-network', 'plasma-cloud', 'tp-link', 'd-link', 'gl.inet',
	'joy-it', '8devices', 'aerohive', 'arcadyan', 'comfast', 'genexis', 'teltonika', 'netgear', 'ubiquiti',
	'cudy', 'openmesh', 'avm', 'xiaomi', 'asus', 'zyxel', 'sophos', 'linksys', 'devolo', 'aruba', 'nexx',
	'buffalo', 'ocedo', 'enterasys', 'zbtlink', 'wavlink', 'mikrotik', 'mercusys', 'zte', 'totolink',
	'siemens', 'ravpower', 'onion', 'o2', 'meraki',
}

-- ganze Image-Namen, bei denen die Regel nichts Brauchbares ergibt
local exact = {
	['x86-64'] = 'x86',
	['x86-generic'] = 'x86',
	['x86-legacy'] = 'x86',
	['librerouter-v1'] = 'LibreRouter',
	['openwrt-one'] = 'OpenWrtOne',
	['vocore2'] = 'VoCore2',
	['gl.inet-6416'] = 'GL6416',
	['buffalo-wzr-hp-g450h-wzr-450hp'] = 'WZR450HP',
	['ubiquiti-unifi-swiss-army-knife-ultra'] = 'UnifiSAKUltra',
}

-- Vorsilben der Produktlinie: ersetzt (leer = weg)
local series = {
	{'aquila-pro-ai-', ''},
	{'mi-router-', 'mi'},
	{'redmi-router-', 'redmi-'},
	{'fritz-box-', 'fb'},
	{'fritz-wlan-repeater-', 'repeater-'},
	{'fritz-repeater-', 'repeater-'},
	{'nighthawk-x4s-', ''},
	{'routerboard-', ''},
	{'tl-', ''},
	{'ws-', ''},
	{'gl-', ''},
	{'zbt-', ''},
	{'wl-', ''},
}

-- Fuellwoerter am Ende: Region, Bauvariante, Generation ohne Bedeutung fuer Menschen
local tail = {
	eu = true, ru = true, jp = true, ca = true, us = true,
	edition = true, international = true, access = true, point = true,
	dallas = true, velop = true, xw = true, xm = true, xc = true, gen1 = true,
	nand = true, hynix = true, micron = true, rtl8366s = true,
	openwrt = true, u = true, boot = true, layout = true,
}

local function word(t)
	if t:find('%d') or #t <= 2 then
		-- "i" direkt hinter einer Ziffer bleibt klein (C20i, AP3825i): steht so
		-- auf dem Geraet, und I, l und 1 sehen je nach Schrift gleich aus
		return (t:upper():gsub('(%d)I$', '%1i'))
	end
	return t:sub(1, 1):upper() .. t:sub(2)
end

-- Kurzname zu einem Gluon-Image-Namen, z.B. 'tp-link-tl-wdr3600-v1' -> 'WDR3600'
function M.short(image)
	if exact[image] then
		return exact[image]
	end

	local s, vendor = image, nil
	for _, v in ipairs(vendors) do
		if s:sub(1, #v + 1) == v .. '-' then
			s, vendor = s:sub(#v + 2), v
			break
		end
	end

	s = s:gsub('%-with%-.*$', ''):gsub('%-rev[%-.].*$', ''):gsub('gigabit', 'giga')

	local toks = {}
	for t in s:gmatch('[^%-]+') do
		toks[#toks + 1] = t
	end
	while #toks > 1 do
		local t = toks[#toks]
		if t:match('^v%d[%d.]*$') or tail[t] or t:match('^%d+mb?$')
				or (vendor == 'd-link' and t:match('^[a-c]%d$')) then
			table.remove(toks)
		else
			break
		end
	end
	s = table.concat(toks, '-')
	s = s:gsub('(%d)v%d$', '%1') -- ea6350v3, ex6150v2

	for _, p in ipairs(series) do
		if s:sub(1, #p[1]) == p[1] then
			s = p[2] .. s:sub(#p[1] + 1)
			break
		end
	end

	local out = {}
	for t in s:gmatch('[^%-]+') do
		out[#out + 1] = word(t)
	end
	local r = table.concat(out):gsub('[^%w]', '')
	if vendor == 'xiaomi' then
		r = r:gsub('^MI', 'Mi')
	end
	if r == '' then
		r = word((vendor or image):gsub('[^%w]', ''))
	end
	return r
end

-- Vorgabe-Hostname; nil, wenn das Image nicht bekannt ist (dann bleibt Gluons Form)
function M.hostname(prefix, node_id)
	local ok, platform_info = pcall(require, 'platform_info')
	if not ok then
		return nil
	end
	local image = platform_info.get_image_name()
	if not image or image == '' then
		return nil
	end
	return prefix .. M.short(image) .. '-' .. node_id:sub(-4)
end

return M
