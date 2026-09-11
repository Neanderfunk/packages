local uci = require("simple-uci").cursor()
local site = require 'gluon.site'
local wireless = require 'gluon.wireless'

package 'neanderfunk-ap-timer'

-- Ob die Seite in den Erweiterten Einstellungen erscheint, entscheidet die
-- site.conf: ap_timer.web (Vorgabe true, wie mit ff-web-ap-timer). Auf einem
-- Knoten, auf dem der Timer schon laeuft, bleibt sie trotzdem sichtbar -
-- sonst liesse er sich dort ueber die Oberflaeche nicht mehr abschalten.
local visible = site.ap_timer.web(true) or uci:get_bool('ap-timer', 'settings', 'enabled')

if wireless.device_uses_wlan(uci) and visible then
	entry({"admin", "ap-timer"}, model("admin/ap-timer"), _("AP Timer"), 30)
end
