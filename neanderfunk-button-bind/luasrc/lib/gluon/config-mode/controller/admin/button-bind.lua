local util = require 'gluon.util'

-- Only offer the page where there is actually a button to bind.
--
-- The usable hardware signal is the device tree: a target with buttons declares
-- them there (the COVR-X1860 has /sys/firmware/devicetree/base/keys holding
-- reset and wps; the x86 VM has no device tree at all).
--
-- Two signals that look plausible but are not:
--   * /dev/input gets it exactly backwards. gpio-button-hotplug emits hotplug
--     events instead of creating input devices, so the COVR has no /dev/input
--     entry at all, while the x86 VM reports a "Power Button" and an AT
--     keyboard - neither of which is a bindable wifi button.
--   * /etc/hotplug.d/button/ is installed by packages (gluon-setup-mode puts
--     its handler there) and is byte-identical on both nodes.
local function has_buttons()
	for _, pattern in ipairs({
		'/sys/firmware/devicetree/base/*keys*',
		'/sys/firmware/devicetree/base/*button*',
		'/sys/firmware/devicetree/base/*/*keys*',
		'/sys/firmware/devicetree/base/*/*button*',
	}) do
		if #util.glob(pattern) > 0 then
			return true
		end
	end
	return false
end

if has_buttons() then
	entry({"admin", "button-bind"}, model("admin/button-bind"), "Taster", 85)
end
