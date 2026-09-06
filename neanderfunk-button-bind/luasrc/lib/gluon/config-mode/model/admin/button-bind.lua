local uci = require("simple-uci").cursor()
local wireless = require 'gluon.wireless'

local f = Form('Taster')
local s = f:section(Section, nil, "Hat der Router eine Wifi-Taste, so können dieser Taste unterschiedliche Funktionalitäten zugeordnet werden.")


-- Sollen mehrere Taster konfiguriert werden, dann einfach folgendes Schemata vervielfaeltigen:

local fct = uci:get('button-bind', 'wifi', 'function')
if not fct then
	fct='1'
	uci:set('button-bind', 'wifi', 'button')
	uci:set('button-bind', 'wifi', 'function', fct)
	uci:commit('button-bind')
end

-- Auf einem Knoten ohne WLAN sind "Wifi an/aus" und "Wifi-Reset" wirkungslos,
-- also gar nicht erst anbieten. Steht dort aus der Vergangenheit noch einer der
-- beiden Werte, faellt die Anzeige auf "Funktionslos" zurueck, damit die
-- Auswahl nicht auf einen Wert zeigt, den es in der Liste nicht gibt.
local has_wlan = wireless.device_uses_wlan(uci)
if not has_wlan and (fct == '0' or fct == '2') then
	fct = '1'
end

local o = s:option(ListValue, "wifi", "Wifi ON/OFF Taster")
o.default = fct
if has_wlan then
	o:value('0', "Wifi an/aus")
end
o:value('1', "Funktionslos (default)")
if has_wlan then
	o:value('2', "Wifi-Reset")
end
o:value('3', "Nachtmodus - LEDs aus, aber während Taster-Betätigung an")

function o:write(data)
	uci:set('button-bind', 'wifi', 'function', data)
end

function f:write()
	uci:commit('button-bind')
end

return f
