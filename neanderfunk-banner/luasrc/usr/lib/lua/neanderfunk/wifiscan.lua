-- neanderfunk.wifiscan - WLAN-Scan fuer offlinescan und channel.
--
--   local cells = require('neanderfunk.wifiscan').scan('radio0')
--
-- Drei Scans hintereinander ueber iwinfo, je BSSID eine Zelle mit dem
-- staerksten Pegel. Ein einzelner passiver Scan verpasst viel; gemessen am
-- 25.11.2026 (je 5 Scans auf 2.4 GHz, Anteil der Mesh-Punkte je Scan im
-- Mittel/schlechtesten): WR1043ND v2 (ath9k) 64/44 %, M60 (mt7981) 83/67 %,
-- MR80X v2 (ath11k) 98/88 %, Xiaomi 4A (mt76) 100 %; drei Scans
-- hintereinander 96/89 %, 100 %, 100 %, 100 %. Der Domainhelper macht es
-- genauso (DH_SCAN_ROUNDS in lib.sh).
--
-- iwinfo scannt passiv (TRIGGER_SCAN ohne SSID-Liste). Das ist wichtig: ath11k
-- verlaesst bei einem aktiven Scan seinen Kanal nicht, solange auf dem Radio
-- ein AP laeuft, passiv sieht es alle Kanaele (MR80X v2, 25.11.2026). Nicht
-- auf "iw scan" umstellen, ohne "passive" mitzugeben.

local M = {}

M.ROUNDS = 3

function M.scan(radio, rounds)
	local iwinfo = require('iwinfo')
	local cells, idx = {}, {}
	for i = 1, rounds or M.ROUNDS do
		if i > 1 then os.execute('sleep 1') end
		for _, c in ipairs(iwinfo.nl80211.scanlist(radio) or {}) do
			local key = c.bssid and c.bssid:upper()
			if not key then
				table.insert(cells, c)
			elseif not idx[key] then
				table.insert(cells, c)
				idx[key] = #cells
			elseif (c.signal or -100) > (cells[idx[key]].signal or -100) then
				cells[idx[key]] = c
			end
		end
	end
	return cells
end

return M
