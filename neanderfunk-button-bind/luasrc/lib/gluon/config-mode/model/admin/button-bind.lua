local uci = require("simple-uci").cursor()

local pkg_i18n = i18n 'neanderfunk-button-bind'

local f = Form(pkg_i18n.translate('Button'))
local s = f:section(Section, nil, pkg_i18n.translate(
	'If the router has a wifi button, it can be given different functions.'))


-- Sollen mehrere Taster konfiguriert werden, dann einfach folgendes Schemata vervielfaeltigen:

-- Without a configured function the page shows "no function" (1). The
-- section is created in this cursor only and written by f:write() - merely
-- showing the page must not write the flash (on the one-page setup of
-- neanderfunk-setup-mode every form is loaded on every visit).
local fct = uci:get('button-bind', 'wifi', 'function')
if not fct then
	fct='1'
	uci:set('button-bind', 'wifi', 'button')
	uci:set('button-bind', 'wifi', 'function', fct)
end

-- Auf einem Knoten ohne WLAN sind "Wifi an/aus" und "Wifi-Reset" wirkungslos,
-- also gar nicht erst anbieten. Steht dort aus der Vergangenheit noch einer der
-- beiden Werte, faellt die Anzeige auf "Funktionslos" zurueck, damit die
-- Auswahl nicht auf einen Wert zeigt, den es in der Liste nicht gibt.
-- Sackgasse 2021.1: gluon.wireless.device_uses_wlan gibt es dort noch nicht
local has_wlan = false
uci:foreach('wireless', 'wifi-device', function()
	has_wlan = true
	return false
end)
if not has_wlan and (fct == '0' or fct == '2') then
	fct = '1'
end

local o = s:option(ListValue, "wifi", pkg_i18n.translate('Wifi button'))
o.default = fct
if has_wlan then
	o:value('0', pkg_i18n.translate('Wifi on/off'))
end
o:value('1', pkg_i18n.translate('No function (default)'))
if has_wlan then
	o:value('2', pkg_i18n.translate('Wifi reset'))
end
o:value('3', pkg_i18n.translate('Night mode - LEDs off, lit only while the button is pressed'))

function o:write(data)
	uci:set('button-bind', 'wifi', 'function', data)
end

function f:write()
	uci:commit('button-bind')
end

return f
