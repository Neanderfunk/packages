# neanderfunk-ssid-changer

forked from  
https://github.com/freifunk-gluon/community-packages/tree/v2023.2.x/ffac-ssid-changer
https://github.com/freifunk-gluon/community-packages/commit/91e5fa8a253b1c5cf73fca7f5f519520cf6c90c2


This package adds a script to change the SSID when there is no
connection to any gateway. This Offline-SSID can be generated from the
first and last part of the node\'s name or from the MAC address allowing
observers to recognize which node does not have a connection to a
gateway. This script is called once every minute by `micrond`. It will
change the SSID to the Offline-SSID after the node had no
gateway-connectivity for several consecutive checks. As soon as the
gateway-connectivity is back it toggles back to the original SSID.

You can enable/disable it in the config mode.

It checks if a gateway is reachable in an interval. Different algorithms
can be selected to determine whether a gateway is assumed reachable:

-   `tq_limit_enabled=true`: (not working with BATMAN_V) define an upper
    and lower bound to toggle the SSID. As long as the TQ stays
    in-between those bounds the SSID will not be changed.

-   `tq_limit_enabled=false`: there will be only checked, if the gateway
    is reachable with:

        batctl gwl -H

The SSID is always changed back to normal every minute as soon as the
gateway-connectivity is back.

The parameter `switch_timeframe` defines how long it will record the
gateway-connectivity. **Only** if the gateway is not reachable during at
least half the checks within `switch_timeframe` minutes, the SSID will
be changed to \"FF_Offline\_\$node_hostname\" (or \_\$node_mac)

The parameter `first` defines a learning phase after reboot (in minutes)
during which the SSID may be changed to the Offline-SSID **every
minute**.

# site.conf

Adapt and add this block to your `site.conf`:

    ssid_changer = {
      enabled = true,
      switch_timeframe = 30,    -- only once every timeframe (in minutes) the SSID will change to the Offline-SSID
                                -- set to 1440 to change once a day
                                -- set to 1 minute to change every time the router gets offline
      first = 5,                -- the first few minutes directly after reboot within which an Offline-SSID may be
                                -- activated every minute (must be <= switch_timeframe)
      prefix = 'FF_Offline_',   -- use something short to leave space for the nodename (no '~' allowed!)
      suffix = 'nodename',      -- generate the SSID with either 'nodename', 'mac' or to use only the prefix: 'none'

      tq_limit_enabled = false, -- if false, the offline SSID will only be set if there is no gateway reachable
                                -- if true, set upper and lower limit to turn the offline_ssid on and off
                                -- in-between these two values the SSID will never be changed to prevent it from
                                -- toggling every minute:
      tq_limit_max = 45,        -- upper limit, above that the online SSID will be used
      tq_limit_min = 35         -- lower limit, below that the offline SSID will be used
      debug_log_enabled = true, -- optional: enable extra debug logs
    },

# Commandline options

You can configure the ssid-changer on the commandline with `uci`, for
example disable it with:

    uci set ssid-changer.settings.enabled='0'

Or set the timeframe to every three minutes with

    uci set ssid-changer.settings.switch_timeframe='3'
    uci set ssid-changer.settings.first='3'

# Alternative: gluon-ssid-notifier

If you just need the Offline-SSID for administrative purposes, there is
a better solution, that will just add an extra SSID if a node is
offline: <https://github.com/freifunk-kiel/gluon-ssid-notifier/>

# Implement this package in your firmware

Create a file \"modules\" with the following content in your site
directory:

    GLUON_SITE_FEEDS="eulenfunk"
    PACKAGES_SSIDCHANGER_REPO=https://github.com/eulenfunk/packages.git
    PACKAGES_SSIDCHANGER_COMMIT=/FILL-IN/ # <-- set the newest commit ID here
    PACKAGES_SSIDCHANGER_BRANCH=v2023.2.x

With this done you can add the package `neanderfunk-ssid-changer` to your
`site.mk`

# History

*This is a merge of https://github.com/ffac/gluon-ssid-changer and
https://github.com/viisauksena/gluon-ssid-changer and https://github.com/tecff/gluon-packages/tree/main/tecff-ssid-changer
Some SSID changers are in use in:

-   [Freifunk Aachen](https://github.com/ffac/gluon-ssid-changer/)
-   [Freifunk Kiel](https://github.com/freifunk-kiel/gluon-ssid-notifier)
-   Freifunk Kreis Gütersloh
-   [Freifunk Nord](https://github.com/Freifunk-Nord/gluon-ssid-changer)
-   [Eulenfunk](https://github.com/eulenfunk/packages/tree/v2020.1.x/gluon-ssid-changer)
-   Freifunk Vogtland
-   [Freifunk Berlin](https://github.com/freifunk-berlin/falter-packages/tree/master/packages/falter-berlin-ssid-changer)
-   [Freifunk Stuttgart](https://gitlab.freifunk-stuttgart.de/firmware/gluon-packages.git)
-   [Freifunk Altdorf](https://github.com/tecff/gluon-packages/tree/main/tecff-ssid-changer)


Mutually exclusive packages
---------------------------

This package declares `CONFLICTS:=ffac-ssid-changer gluon-ssid-changer`. It is a
fork of `ffac-ssid-changer` and installs the exact same six paths, uses the same
`/tmp` state files and drives the same SSID, so the two can only be installed
together by mistake - the package manager now refuses instead of leaving it to
whoever edits `image-customization.lua`. `gluon-ssid-changer` is the older shell
variant this feed used to carry (removed here, still present upstream).

`ffac-eol-ssid` is *not* a conflict: different purpose, different files, and it
can be used alongside this one.

Stand 2026-09-06: TQ-Schwelle war wirkungslos
---------------------------------------------

`calculate_tq_limit()` las den TQ des gewaehlten Gateways so:

```
batctl gwl -H | grep -e "^\*" | awk -F"[()]" "{print $2}" | tr -d " "
```

Das awk-Programm steht in **doppelten** Anfuehrungszeichen, also expandierte die
Shell das `$2` zu leer, awk bekam `{print }` und gab damit die ganze Zeile aus:

```
*02:ca:ff:ee:21:03(255)02:ca:ff:ee:21:03[mesh-vpn]:1024.0/1024.0MBit
```

`tonumber()` darauf ist `nil`, `calculate_tq_limit()` lief also bei jedem Aufruf
in den Rueckfall und lieferte immer `online`. Die TQ-Schwelle hat damit nie
gegriffen, obwohl `tq_limit_enabled=1` auf den Knoten gesetzt ist - ein Knoten
mit schlechtem, aber vorhandenem Gateway wechselte nie auf die Offline-SSID.
An zwei Geraeten gemessen. Mit einfachen Anfuehrungszeichen kommt der Wert
korrekt heraus (255 bzw. 254).

## Zustandsdateien in /tmp

Alles nur im RAM, bis zum naechsten Boot. Die Namen der drei aelteren Dateien
fuehren in die Irre - sie klingen nach Summen, sind aber keine:

| Datei | Inhalt |
|---|---|
| `ssid-changer-count` | Minuten, die im laufenden Fenster (`switch_timeframe`) als offline galten. An jeder Fenstergrenze auf 0 oder 1 gesetzt, mit Gateway sofort 0 - bei `switch_timeframe = 2` also 0 bis 2. |
| `ssid-changer-gwofflinecount` | Entprellung: Minuten in Folge ohne Gateway, bis `gwofflinemaxcount`; erst danach gilt der Knoten als offline. Nach dem gezaehlten Ausfall `gwofflinemaxcount + 1`, mit Gateway sofort 0. |
| `ssid-changer-offline` | 0/1: galt der Knoten am letzten Fensterwechsel als offline. Nur Diagnose - sagt nicht, ob die Offline-SSID geschaltet hat. |
| `ssid-changer-offline-switches` | **Zaehler seit Boot:** wie oft die Offline-SSID geschaltet wurde. Gezaehlt wird die Entscheidung, einmal je Ausfall, auch wenn `wifi reconf` gerade gesperrt war. |
| `ssid-changer-gateway-losses` | **Zaehler seit Boot:** wie oft das Gateway verloren ging - nach der Entprellung; ein Wackler unter `gwofflinemaxcount` Minuten zaehlt nicht. |

Die beiden Zaehler legt das Skript beim ersten Lauf mit 0 an; die Statusseite
erkennt daran, dass das Paket sie fuehrt. Geschrieben werden sie ueber eine
Nebendatei und `rename`, damit ein Abbruch sie nicht leert.

Die Umschaltentscheidungen sind dadurch unveraendert: auf einem Pruefstand, der
das Skript Minute fuer Minute durch Ausfaelle, einen kurzen Wackler, einen
gesperrten `wifi reconf` und `gwofflinemaxcount = 0` schickt, entscheidet es
Minute fuer Minute wie vorher; hinzu kommen nur die Zaehler.
