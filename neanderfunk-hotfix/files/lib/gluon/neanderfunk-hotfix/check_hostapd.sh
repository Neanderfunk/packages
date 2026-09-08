#!/bin/sh
# Prueft, ob hostapd die konfigurierten AP-Interfaces wirklich bedient.
#
# Frueher hiess das "check_hostapd for matching pids": healthcheck.sh reichte
# jeden hostapd-Prozess aus der ps-Ausgabe herein, dieses Skript las aus dessen
# Kommandozeile die Optionen -B (Konfigdatei, daraus der phy) und -P (PID-Datei)
# und verglich den Inhalt der PID-Datei mit der echten PID.
#
# Das lief seit Jahren ins Leere. Seit OpenWrt 21.02 gibt es keinen hostapd je
# phy mehr, sondern genau einen globalen Prozess ohne -B und ohne -P:
#     /usr/sbin/hostapd -s -g /var/run/hostapd/global
# Der Filter in healthcheck.sh war "ps | grep hostapd | grep .pid", und der
# findet daran nichts. Am Knoten gemessen (2023.2.6, 2026-09-08): null Treffer,
# das Skript wurde also nie aufgerufen - und damit liefen auch die beiden
# anderen Pruefungen hier drin nie.
#
# Jetzt zaehlt das Skript die AP-Interfaces selbst aus der wireless-Config auf
# und fragt den globalen hostapd ueber ubus nach jedem einzelnen BSS. Das ist
# zugleich die Vorbereitung auf Gluon 2025.1: dort kann ein phy mehrere Radios
# tragen, "phy0 -> radio0 -> client0" gilt also nicht mehr. Hier wird nichts
# mehr aus Indizes abgeleitet, alle drei Namen (Sektion, ifname, Radio) kommen
# aus der Config.
#
# Der uci-Schluessel heisst weiterhin hotfix.hostapd_pids, obwohl es um PIDs
# nicht mehr geht. Umbenennen wuerde ein hotfix.hostapd_pids.disabled='1', das
# jemand bewusst gesetzt hat, stillschweigend wirkungslos machen.
#
# strike()/unstrike() zaehlen aufeinanderfolgende Fehlschlaege, siehe common.sh.
. /lib/gluon/neanderfunk-hotfix/common.sh

HOTFIX_TAG='neanderfunk-checkhostapd'

RESTART_MARKER='/tmp/hotfix.hostapd.last-restart'

# Rueckgabe 0 nur bei tatsaechlichem Neustart - der Aufrufer raeumt danach
# Strikes weg, und das darf nicht behaupten, es sei etwas geschehen.
restart_wifi() {
	local age cooldown

	# Abklingzeit. Ohne sie wuerde ein dauerhaft fehlendes Radio - eine Sektion
	# in der Config, deren phy nicht hochkommt - alle drei Laeufe einen
	# WLAN-Neustart ausloesen, also rund dreimal pro Stunde, und jedes Mal alle
	# Clients beider Radios abwerfen, ohne dass es etwas repariert. Genau das
	# Muster, das in neanderfunk-mt7915-backlog schon einmal aufgefallen ist.
	#     uci set hotfix.settings.hostapd_cooldown_min='60' ; uci commit hotfix
	cooldown="$(uci -q get hotfix.settings.hostapd_cooldown_min)"
	case "$cooldown" in
		''|*[!0-9]*) cooldown=30 ;;
	esac
	if [ -f "$RESTART_MARKER" ] ; then
		age=$(( ( $(date +%s) - $(date -r "$RESTART_MARKER" +%s) ) / 60 ))
		if [ "$age" -lt "$cooldown" ] ; then
			logger -t "$HOTFIX_TAG" -p 5 "wifi restart skipped, last one was ${age}min ago (hotfix.settings.hostapd_cooldown_min=${cooldown})"
			return 1
		fi
	fi

	# gemeinsame Sperre, siehe common.sh
	if ! wifi_lock ; then
		logger -t "$HOTFIX_TAG" -p 5 "wifi restart skipped, another check is already restarting wifi"
		return 1
	fi
	touch "$RESTART_MARKER"
	logger -t "$HOTFIX_TAG" -p 5 "wifi hard restart"
	wifi down
	killall hostapd 2>/dev/null
	rm -f /tmp/hostapd.*.core 2>/dev/null
	wifi config
	wifi up
	wifi_unlock
	sleep 60
	return 0
}

# einmal holen statt je Interface: "wifi status" liefert den Zustand aller
# Radios in einem JSON-Dokument.
wifistatus="$(wifi status 2>/dev/null)"

# Alle AP-Interfaces aus der Config. mode='ap' trifft die Client-SSIDs und,
# falls konfiguriert, die OWE-Interfaces. Abgeschaltete werden uebersprungen -
# das schliesst die OWE-Interfaces ein, die der ssid-changer waehrend einer
# Offline-Phase deaktiviert (er setzt nur uci save, und ein uci get sieht den
# Delta, also stimmt das auch dann).
for section in $(uci show wireless 2>/dev/null | sed -n "s/^wireless\.\([^.]*\)\.mode='ap'$/\1/p") ; do
	ifname="$(uci -q get wireless."$section".ifname)"
	[ -n "$ifname" ] || continue
	[ "$(uci -q get wireless."$section".disabled)" = "1" ] && continue
	radio="$(uci -q get wireless."$section".device)"

	# --- 1) kennt der globale hostapd dieses BSS, und laeuft es? ------------
	#
	# Der Nachfolger der PID-Pruefung. hostapd legt je BSS ein ubus-Objekt
	# hostapd.<ifname> an; fehlt es, kennt hostapd das Interface gar nicht.
	#
	# Bewusst NICHT ueber /var/run/hostapd/<ifname> geprueft: auf allen drei
	# daraufhin untersuchten Knoten liegt dort nur der Socket des zweiten
	# Radios plus "global", der von client0 fehlt. Der Socket ist als
	# Indikator also unbrauchbar, das ubus-Objekt ist es nicht.
	sema="/tmp/hotfix.hostapdbss"
	raw="$(ubus call hostapd."$ifname" get_status 2>/dev/null)"
	if [ -z "$raw" ] ; then
		state='no-ubus-object'
	else
		state="$(printf '%s' "$raw" | jsonfilter -e '@.status' 2>/dev/null)"
		[ -n "$state" ] || state='no-status'
	fi
	case "$state" in
		ENABLED)
			unstrike "$sema.fail.$ifname"
			;;
		ACS|HT_SCAN|DFS|COUNTRY_UPDATE)
			# Uebergangszustaende: Kanalwahl, DFS-Messung, Laenderwechsel.
			# Weder Strike noch Entwarnung - eine DFS-Messung darf zehn
			# Minuten dauern, und drei Laeufe dieses Checks sind erst 21.
			;;
		*)
			if [ "$(strike "$sema.fail.$ifname")" -ge 3 ] ; then
				logger -t "$HOTFIX_TAG" -p 5 "[hostapd_pids] hostapd does not serve $ifname (status: $state)"
				restart_wifi && unstrike "$sema.fail.$ifname"
			fi
			;;
	esac

	# --- 2) haengt das Radio in "down und pending"? -------------------------
	#
	# Das Radio wird aus wireless.<section>.device gelesen, nicht mehr aus der
	# phy-Nummer abgeleitet. jsonfilter statt grep -A 6: die Zuordnung Radio ->
	# Feld ist damit exakt, und nicht mehr davon abhaengig, wie viele Zeilen
	# netifd je Radio ausgibt.
	if [ -n "$radio" ] ; then
		sema="/tmp/hotfix.wifipending"
		up="$(printf '%s' "$wifistatus" | jsonfilter -e "@[\"$radio\"].up" 2>/dev/null)"
		pending="$(printf '%s' "$wifistatus" | jsonfilter -e "@[\"$radio\"].pending" 2>/dev/null)"
		if [ "$up" = "false" ] && [ "$pending" = "true" ] ; then
			if [ "$(strike "$sema.fail.$radio")" -ge 3 ] ; then
				logger -t "$HOTFIX_TAG" -p 5 "[hostapd_pids] hostapd down and pending on $radio"
				restart_wifi && unstrike "$sema.fail.$radio"
			fi
		elif [ -n "$up" ] ; then
			unstrike "$sema.fail.$radio"
		fi
	fi

	# --- 3) AP ohne Kanal ---------------------------------------------------
	#
	# Ein Interface im Master-Modus, dem iwinfo keinen Kanal nennen kann, ist
	# oben, sendet aber nichts Brauchbares.
	sema="/tmp/hotfix.channelunknown"
	iwstat="$(iwinfo "$ifname" info 2>/dev/null)"
	if printf '%s\n' "$iwstat" | grep -qi "Mode: Master" ; then
		if printf '%s\n' "$iwstat" | grep -qi "Channel: unknown" ; then
			if [ "$(strike "$sema.fail.$ifname")" -ge 3 ] ; then
				logger -t "$HOTFIX_TAG" -p 5 "[hostapd_pids] channel unknown on $ifname"
				restart_wifi && unstrike "$sema.fail.$ifname"
			fi
		else
			unstrike "$sema.fail.$ifname"
		fi
	fi
done

exit 0
