#!/bin/sh
# Aufruf auf einer Test-VM (nie im Feld): SKRIPT=<Pfad zum Upgrade-Skript> sh testfaelle.sh
# Legt /lib/gluon/domains und *_gluon-old an und raeumt danach auf.
# Test neanderfunk-domain-from-legacy auf echtem Gluon (nur Test-VM)
DOM=/lib/gluon/domains
mkdir -p $DOM; rm -f $DOM/*.json
dom() { # code mesh ip4 [legacy-json]
	printf '{"domain_names":{"%s":"x"},"wifi24":{"mesh":{"id":"%s"}},"wifi5":{"mesh":{"id":"%s"}},"next_node":{"ip4":"%s"}%s}\n' "$1" "$2" "$2" "$3" "${4:+,\"neanderfunk_legacy\":$4}" > $DOM/$1.json
}
dom 10_wlf wlf-mesh 10.40.144.1 '{"mesh_id":["ffnef-wlf-mesh"]}'
dom 32_lvrnw lvrnw-mesh 10.51.240.1 '{"mesh_id":["lvrmw-mesh"]}'
dom 34_lvrmw lvrmw-mesh 10.52.16.1 '{"mesh_id":["lvrso-mesh"]}'
dom 35_lvrso lvrso-mesh 10.52.32.1
dom 17_wip wip-mesh 10.31.0.1
dom 31_lvrno lvrno-mesh 10.51.224.1
ln -sf 10_wlf.json $DOM/wlf_alias.json
old() { # ip4 mesh1 [mesh2]
	rm -f /etc/config/network_gluon-old /etc/config/wireless_gluon-old
	[ -n "$1" ] && printf "config interface 'local_node'\n\toption ipaddr '%s/20'\n" "$1" > /etc/config/network_gluon-old
	if [ -n "$2" ]; then
		printf "config wifi-iface 'mesh_radio0'\n\toption mode 'mesh'\n\toption mesh_id '%s'\n\toption disabled '1'\nconfig wifi-iface 'client_radio0'\n\toption mode 'ap'\n" "$2" > /etc/config/wireless_gluon-old
		[ -n "$3" ] && printf "config wifi-iface 'mesh_radio1'\n\toption mode 'mesh'\n\toption mesh_id '%s'\n" "$3" >> /etc/config/wireless_gluon-old
	fi
	return 0
}
run() { # name erwartet
	uci -q revert gluon; uci -q delete gluon.core.domain; uci commit gluon
	lua "${SKRIPT:-/tmp/s.lua}" 2>/tmp/err; got=$(uci -q get gluon.core.domain); echo "$1 | erwartet ${2:--} | bekommen ${got:--} | $(cat /tmp/err | tr '\n' ' ')"
}
old 10.40.144.1 wlf-mesh;              run "1 Mesh eindeutig" 10_wlf
old 10.40.144.1 ffnef-wlf-mesh;        run "2 alte Mesh-ID (legacy)" 10_wlf
old 10.51.240.1 lvrmw-mesh;            run "3 alter 32er, lvrmw-mesh mehrdeutig -> IPv4" 32_lvrnw
old 10.52.16.1 lvrmw-mesh;             run "4 heutiger 34er, lvrmw-mesh mehrdeutig -> IPv4" 34_lvrmw
old 10.34.0.1 lvrso-mesh;              run "5 34er vor 2023, mehrdeutig, IPv4 unbekannt -> default" ""
old 10.31.0.1 lvrno-mesh;              run "6 31er vor 2023, IPv4 heute 17 -> Mesh gewinnt" 31_lvrno
old 10.40.144.1 "";                    run "7 ohne WLAN -> IPv4" 10_wlf
old 10.99.0.1 gibtsnicht-mesh;         run "8 nichts passt -> default" ""
old 10.40.144.1 wlf-mesh lvrno-mesh;   run "9 zwei Mesh-IDs, zwei Domains -> IPv4" 10_wlf
old "" "";                             run "10 Neuinstallation -> still" ""
old 10.40.144.1 wlf-mesh; uci set gluon.core.domain=17_wip; uci commit gluon; lua "${SKRIPT:-/tmp/s.lua}" 2>/tmp/err; echo "11 Domain schon gesetzt | erwartet 17_wip | bekommen $(uci -q get gluon.core.domain) | $(cat /tmp/err)"
rm -rf $DOM /etc/config/network_gluon-old /etc/config/wireless_gluon-old; uci -q delete gluon.core.domain; uci commit gluon
old 10.40.144.1 wlf-mesh; lua "${SKRIPT:-/tmp/s.lua}" 2>/tmp/err; echo "12 kein domains-Verzeichnis | erwartet - | bekommen $(uci -q get gluon.core.domain || echo -) | $(cat /tmp/err)"
rm -f /etc/config/network_gluon-old /etc/config/wireless_gluon-old
logread | grep neanderfunk-domain | tail -3
echo TESTENDE
