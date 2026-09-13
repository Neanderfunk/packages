neanderfunk-setup-wifi
======================

Setup-Mode per WLAN: Im Setup-Mode spannt der Knoten ein eigenes WLAN
`setup.gluon_<letzte 4 Hexziffern der primären MAC>` auf. Wer sich verbindet,
bekommt per DHCP eine Adresse aus 198.51.100.0/24, jeder DNS-Name zeigt auf den
Knoten, und die Portal-Erkennung des Handys (`/generate_204` und Co.) öffnet
die Setup-Seite – wie bei den Einrichtungs-APs von Tasmota, ESPHome oder WLED.

Früher ein fest verdrahteter Firmware-Patch (`setup-mode-wifi`), jetzt ein
Paket, einstellbar per site.conf.

site.conf
---------

```lua
setup_mode = {
  wifi = {
    start = 'boot',         -- 'off' | 'boot' (sofort) | 'button' (kurzer Tastendruck)
    security = 'wpa2',      -- 'open' | 'wpa2'
    key = 'freifunk_',      -- WPA2: key .. erstes Byte der primären MAC (2 Hexziffern, klein)
    timeout = 1200,         -- Sekunden bis zum Abschalten (60 bis 86400)
  },
},
```

**Ohne den Block** wie der frühere Patch: sofort beim Boot, WPA2 mit
`freifunk_<erstes MAC-Byte>`, nach 1200 s aus. `check_site.lua` prüft:

- `security = 'open'` nur zusammen mit `start = 'button'` – ein offenes
  Setup-WLAN nur mit physischem Zugriff.
- WPA2 braucht 8 bis 63 Zeichen, angehängt werden 2 Hexziffern: `key` also 6
  bis 61 Zeichen.

Das Passwort hält nur versehentliches Verbinden ab; die MAC steht als BSSID in
jedem Beacon (bewusst so). SSID und Adresse sind fest.

Verhalten
---------

| `start` | Boot in den Setup-Mode | kurzer Tastendruck |
|---|---|---|
| `off` | kein Setup-WLAN, kein hostapd | nichts |
| `boot` | AP sofort an, Timeout läuft | AP (wieder) an bzw. Timeout von vorn |
| `button` | kein AP | AP an, Timeout läuft; erneuter Druck startet den Timeout neu |

- **Nur im Setup-Mode.** Im Normalbetrieb tut der Kurzdruck nichts.
- **Kurzdruck:** Loslassen nach weniger als 3 s (`$SEEN` von procd) auf
  `reset`, `wps` oder `phone` – dieselben Tasten wie Gluons Langdruck. Den
  Langdruck (3 s → `gluon-enter-setup-mode`) behandelt weiter Gluons
  `50-gluon-setup-mode`, unverändert. Beim Genexis Pulse EX400 zählt die
  kapazitive `wps`-Taste für den Kurzdruck mit (Gluon nimmt sie dort nur vom
  Langdruck aus); der Reset-Knopf ebenso.
- **Nach dem Timeout:** `wifi down`, Logzeile, der Zugang per Kabel bleibt.
  Kein Neustart – ein unkonfigurierter Knoten käme wieder in den Setup-Mode,
  am Kabel flöge man aus der Eingabe.
- **Status-LED:** Setup-Mode wie bei Gluon 1000/300 ms, solange das
  Setup-WLAN läuft fünfmal so schnell (200/60, bis 14.09.2026 333/100).

Aufbau
------

| Datei | Aufgabe |
|---|---|
| `/lib/gluon/setup-mode/rc.d/S19neanderfunk-setup-wifi-wpad` | hostapd im Setup-Mode (bindet `/etc/init.d/wpad` ein), nicht bei `off` |
| `/lib/gluon/setup-mode/rc.d/S21neanderfunk-setup-wifi` | nach S20network: AP und Bridge `br-setupwifi` (198.51.100.1/24) in `/var/gluon/setup-mode/config`, `ubus call network reload`, `wifi up`; procd-Instanzen für den zweiten dnsmasq und den Timeout |
| `/lib/gluon/setup-mode/rc.d/S97neanderfunk-setup-wifi-led` | nach Gluons S96led wieder schnell blinken, wenn der AP schon läuft |
| `/etc/hotplug.d/button/60-neanderfunk-setup-wifi` | Kurzdruck → `ctl button` |
| `/lib/gluon/neanderfunk-setup-wifi/ctl` | `up`, `button`, `down`, `timeout`, `status` |
| `/lib/gluon/neanderfunk-setup-wifi/lib.sh` | Konfiguration, Namen, LED, uci |

Der AP kommt auf das erste 2,4-GHz-Radio (jedes Handy hat eins, kein
DFS-Warten), sonst auf das erste Radio; die übrigen Radios bleiben aus. Ohne
Radio (x86, ERX) gibt es kein Setup-WLAN.

**198.51.100.1 (TEST-NET-2) statt einer privaten Adresse:** Android öffnet
sein Anmeldefenster nur, wenn der Probe-Host nicht auf RFC 1918 auflöst (am S24
Ultra mit 192.168.2.1 nur „kein Internet“). Deshalb nicht einstellbar. Im
Setup-WLAN lädt die OSM-Karte nicht (auch deren Name zeigt auf den Knoten),
Koordinaten also von Hand.

Voraussetzungen in der Firmware
-------------------------------

Zwei Stellen in Gluons eigenen Dateien bleiben ein Firmware-Patch (zwei
Pakete können dieselbe Datei nicht besitzen):

- `S60dnsmasq` (gluon-setup-mode): die erste Instanz fest an `br-setup`
  (`--interface=br-setup --bind-dynamic`), damit die zweite an `br-setupwifi`
  laufen kann.
- `cgi-bin/portal` (gluon-config-mode-core): Rückleitung auf `SERVER_ADDR`,
  also 198.51.100.1 im WLAN und 192.168.1.1 am LAN.

Trägt die Firmware noch den früheren Patch (erkennbar an `SETUP_WIFI_ADDR` in
`S20network`), hält sich das Paket ganz heraus: kein zweiter AP, kein zweiter
dnsmasq, kein zweiter hostapd.

Geprüft
-------

Am 13.09.2026 auf einem Archer C25 v1 (ath79, 64 MB), Image 26091223bro mit
dem Paket und Gluons ungepatchtem S20network, `S60dnsmasq` nur mit der
Bindung, ohne `S19wpad`:

- Ohne site.conf-Block: nach dem Boot in den Setup-Mode AP
  `setup.gluon_4830` auf dem 2,4-GHz-Radio (psk2, `freifunk_50`),
  `br-setupwifi` 198.51.100.1, zwei dnsmasq, hostapd mit ubus-Objekt, LED
  333/100; jeder Name → 198.51.100.1; `/generate_204` über 198.51.100.1 führt
  auf die Setup-Seite, am LAN 302 auf 192.168.1.1.
- `button`/`open`/90 s: nach dem Boot kein AP, LED 1000/300, hostapd läuft;
  Loslassen mit `SEEN=4` ohne Wirkung; Kurzdruck → offener AP, LED schnell;
  zweiter Druck 30 s später startet den Timeout neu; aus 91 s nach dem
  zweiten Druck, LED zurück, Logzeile.
- `off`: Kurzdruck ohne Wirkung, kein hostapd.

Tasten ohne Finger:
`ACTION=released BUTTON=reset SEEN=1 /sbin/hotplug-call button`.
