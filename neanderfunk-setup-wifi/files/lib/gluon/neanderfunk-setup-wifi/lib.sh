# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
#
# neanderfunk-setup-wifi: gemeinsame Funktionen der Setup-Mode-Skripte, des
# Tasten-Handlers und von ctl. Wird mit "." eingebunden.
#
# Das Setup-WLAN: ein AP setup.gluon_<letzte 4 Hexziffern der primaeren MAC>
# in eigener Bridge br-setupwifi, 198.51.100.1/24, eigener dnsmasq mit
# DNS-Catch-all und DHCP. Nur im Setup-Mode. Einstellbar per site.conf
# (setup_mode.wifi, siehe README und check_site.lua); ohne den Block wie der
# fruehere Firmware-Patch: sofort beim Boot, WPA2 freifunk_<erstes MAC-Byte>,
# nach 1200 s aus.
#
# 198.51.100.1 (TEST-NET-2, RFC 5737) und keine private Adresse: Android
# oeffnet sein Anmeldefenster nur, wenn der Probe-Host nicht auf RFC 1918
# aufloest (am S24 Ultra mit 192.168.2.1 nur "kein Internet"). Bewusst nicht
# einstellbar.

SW_ADDR=198.51.100.1
SW_NETMASK=255.255.255.0
SW_CONFIG_DIR=/var/gluon/setup-mode/config
# Laeuft das Setup-WLAN gerade (oder soll es laufen)? Enthaelt den Zeitpunkt
# des letzten Starts; ein neuer Zeitpunkt startet den Timeout neu. /var ist
# tmpfs, also weg nach jedem Neustart.
SW_ACTIVE=/var/gluon/setup-mode/setup-wifi.active

sw_log() {
	logger -t neanderfunk-setup-wifi "$*"
}

# Laeuft der Setup-Mode? /var/gluon/setup-mode legt das Preinit-Skript von
# gluon-setup-mode nur im Setup-Mode an (tmpfs).
sw_in_setup_mode() {
	[ -d /var/gluon/setup-mode ]
}

# Enthaelt das Image noch den frueheren Firmware-Patch setup-mode-wifi? Dann
# baut dessen S20network das WLAN selbst, und dieses Paket haelt sich raus -
# zwei APs und zwei dnsmasq auf br-setupwifi gingen nicht gut.
sw_legacy_patch() {
	grep -q 'SETUP_WIFI_ADDR' /lib/gluon/setup-mode/rc.d/S20network 2>/dev/null
}

# Einstellungen aus der site.conf (mit den Vorgaben von oben) als
# Shell-Variablen SW_START, SW_SECURITY, SW_KEY, SW_TIMEOUT.
sw_conf() {
	local out
	# Eine Zeile je Wert, der Schluessel zuletzt (darf alles ausser Zeilenende
	# enthalten) - kein eval.
	out="$(lua -e '
		local w = require("gluon.site").setup_mode.wifi
		print(w.start("boot"))
		print(w.security("wpa2"))
		print(math.floor(tonumber(w.timeout(1200)) or 1200))
		print(w.key("freifunk_"))
	')"
	SW_START="$(echo "$out" | sed -n 1p)"
	SW_SECURITY="$(echo "$out" | sed -n 2p)"
	SW_TIMEOUT="$(echo "$out" | sed -n 3p)"
	SW_KEY="$(echo "$out" | sed -n 4p)"
	[ -n "$SW_START" ] || SW_START=boot
	[ -n "$SW_SECURITY" ] || SW_SECURITY=wpa2
	[ -n "$SW_TIMEOUT" ] || SW_TIMEOUT=1200
}

# SSID und Schluessel aus der primaeren MAC: SW_SSID, SW_PSK.
sw_names() {
	local mac
	mac="$(lua -e 'print(require("gluon.sysconfig").primary_mac)' | tr -d ':' | tr 'A-F' 'a-f')"
	SW_SSID="setup.gluon_$(echo "$mac" | cut -c9-12)"
	SW_PSK="${SW_KEY}$(echo "$mac" | cut -c1-2)"
}

# Status-LED wie gluon-setup-mode S96led: Setup-Mode 1000/300, solange das
# Setup-WLAN laeuft dreimal so schnell.
sw_led() {
	local custom_led
	. /etc/diag.sh
	get_status_led 2>/dev/null
	[ -n "$status_led" ] || status_led="$running"
	[ -n "$status_led" ] || status_led="$boot"
	if [ -z "$status_led" ]; then
		custom_led="$(lua -e 'print(require("gluon.setup-mode").get_status_led() or "")')"
		status_led="$custom_led"
	fi
	[ -n "$status_led" ] || return 0
	case "$1" in
		fast) status_led_set_timer 333 100 ;;
		*) status_led_set_timer 1000 300 ;;
	esac
}

# --- uci-Konfiguration des Setup-Modes -------------------------------------

sw_delete_wifi_iface() {
	uci_remove wireless "$1"
}

sw_disable_other_radio() {
	[ "$1" = "$sw_radio" ] || uci_set wireless "$1" disabled 1
}

sw_find_radio() {
	local band hwmode
	config_get band "$1" band
	config_get hwmode "$1" hwmode
	[ -n "$sw_radio" ] || sw_radio="$1"
	if [ -z "$sw_radio_2g" ] && { [ "$band" = '2g' ] || [ "$hwmode" = '11g' ]; }; then
		sw_radio_2g="$1"
	fi
}

# Legt AP und Bridge in der Konfiguration des Setup-Modes an (netifd laeuft
# dort mit -c $SW_CONFIG_DIR, S20network). Ein AP auf dem ersten
# 2,4-GHz-Radio (jedes Handy hat eins, kein DFS-Warten), sonst dem ersten
# Radio; die uebrigen Radios aus. Rueckgabe 1, wenn es kein Radio gibt.
# Braucht sw_conf und sw_names.
sw_prepare_config() {
(
	export UCI_CONFIG_DIR="$SW_CONFIG_DIR"
	. /lib/functions.sh
	local sw_radio='' sw_radio_2g=''

	[ -s /etc/config/wireless ] || exit 1
	[ -s "$UCI_CONFIG_DIR/network" ] || exit 1

	cp /etc/config/wireless "$UCI_CONFIG_DIR/wireless"
	config_load wireless
	config_foreach sw_delete_wifi_iface wifi-iface
	config_foreach sw_find_radio wifi-device
	sw_radio="${sw_radio_2g:-$sw_radio}"
	if [ -z "$sw_radio" ]; then
		rm -f "$UCI_CONFIG_DIR/wireless"
		exit 1
	fi

	config_foreach sw_disable_other_radio wifi-device
	uci_set wireless "$sw_radio" disabled 0
	uci_add wireless wifi-iface setup_wifi
	uci_set wireless setup_wifi device "$sw_radio"
	uci_set wireless setup_wifi network 'setupwifi'
	uci_set wireless setup_wifi mode 'ap'
	uci_set wireless setup_wifi ssid "$SW_SSID"
	if [ "$SW_SECURITY" = open ]; then
		uci_set wireless setup_wifi encryption 'none'
	else
		uci_set wireless setup_wifi encryption 'psk2'
		uci_set wireless setup_wifi key "$SW_PSK"
	fi
	uci_commit wireless

	config_load network
	uci_remove network setupwifi 2>/dev/null
	uci_add network interface setupwifi
	uci_set network setupwifi type 'bridge'
	uci_set network setupwifi bridge_empty '1'
	uci_set network setupwifi proto 'static'
	uci_set network setupwifi ipaddr "$SW_ADDR"
	uci_set network setupwifi netmask "$SW_NETMASK"
	uci_commit network
)
}
