-- setup_mode.wifi (alles optional; ohne den Block: boot, wpa2, 'freifunk_', 1200)
local start = need_one_of(in_site({'setup_mode', 'wifi', 'start'}), {'off', 'boot', 'button'}, false) or 'boot'
local security = need_one_of(in_site({'setup_mode', 'wifi', 'security'}), {'open', 'wpa2'}, false) or 'wpa2'
need_number_range(in_site({'setup_mode', 'wifi', 'timeout'}), 60, 86400, false)

-- WPA2 will 8 bis 63 Zeichen; angehaengt werden 2 Hexziffern (erstes Byte der
-- primaeren MAC), der Rest kommt aus key.
if security == 'wpa2' then
	need(in_site({'setup_mode', 'wifi', 'key'}), function(v)
		return type(v) == 'string' and #v >= 6 and #v <= 61 and not v:find('\n')
	end, false, 'be a string of 6 to 61 characters (2 hex digits of the MAC are appended, WPA2 needs 8 to 63)')
end

-- Ein offenes Setup-WLAN nur mit Tastendruck, also mit physischem Zugriff.
if security == 'open' and start ~= 'button' then
	need(in_site({'setup_mode', 'wifi', 'security'}), function() return false end, true,
		"be 'wpa2' unless setup_mode.wifi.start is 'button' (an open setup WLAN needs physical access)")
end
