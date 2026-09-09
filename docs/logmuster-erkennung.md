# Muster im Syslog eines Freifunk-Knotens erkennen

Anleitung für eine auswertende Instanz — zentraler Syslog-Empfänger, Zeitreihen,
Alarmierung. Beschrieben ist der Stand der Neanderfunk-Pakete auf Gluon
v2023.2.x (Firmware-Release `26090803bro` und neuer).

Der Knoten selbst filtert und verdichtet **nicht**. Er schickt Zeilen, die
Intelligenz sitzt hier. Das ist Absicht: verdichtet man auf dem Knoten, muss man
puffern, und dann sind spontane Änderungen genau in dem Moment unsichtbar, in
dem man sie braucht.

## 1. Was ankommt

Rohformat aus `logread`:

```
Wed Sep  9 06:35:02 2026 user.notice neanderfunk-linkcheck: [bsses] lost neighbours 1st: batadv.mesh0
└──────── Zeitstempel ────────┘ └facility.severity┘ └──── Tag ────┘ └check┘ └─── Meldung ───┘
```

Bei aktivierter Weiterleitung (`system.@system[0].log_ip`) rahmt `logread -f -r`
das in RFC3164. Der Tag bleibt erhalten, der Zeitstempel wird auf `Mmm tt
hh:mm:ss` gekürzt.

**Facility:** alles aus unseren Paketen läuft auf `user` (1), meist
`user.notice`. `daemon` (3) ist fremd: hostapd, netifd, dnsmasq, tunneldigger,
micrond. `kern` (0) ist der Kernel.

## 2. Normalisierung

Vor jeder Zählung ersetzen:

| Muster | ersetzen durch | warum |
| --- | --- | --- |
| `(?:[0-9a-f]{2}:){5}[0-9a-f]{2}` | `<MAC>` | MACs |
| `\[[0-9]+\]` im Tag | `[<PID>]` | PIDs wechseln bei jedem Neustart |
| `\b0x[0-9a-fA-F]+\b` | `<HEX>` | Registerwerte |
| `[0-9]+` | `N` | Zähler, Kanäle, Frequenzen, Minuten |

Wirkung, an vier echten 64-KiB-Puffern gemessen (Spannen 0,7 bis 65 Stunden):

| Knoten | Zeilen | verschiedene Muster |
| --- | ---: | ---: |
| Archer C25 (ohne Uplink) | 647 | **14** |
| Xiaomi 4A | 144 | **14** |
| ZyXEL NWA50AX | 257 | **59** |
| COVR-X1860 | 559 | **91** |

Vierzehn bis einundneunzig. Die Kardinalität einer Zeitreihe
`(knoten, muster, anzahl)` ist damit unkritisch, und die Musterdimension ist
flottenweit klein, weil alle Knoten dieselben paar Dutzend Muster teilen.

## 3. Die Tag-Konvention

| Tag | Paket | Zuständig für |
| --- | --- | --- |
| `neanderfunk-healthcheck` | hotfix | Gesundheit *dieses Geräts* |
| `neanderfunk-checkhostapd` | hotfix | hostapd bedient die AP-Interfaces |
| `hotfix-IfNoWificlient` | hotfix | Clients waren da und sind alle weg |
| `neanderfunk-hotfix` | hotfix | gemeinsame Meldungen, Reboots |
| `neanderfunk-linkcheck` | linkcheck | Netz *um das Gerät herum* |
| `neanderfunk-mt7915-backlog` | mt7915-backlog | mt7915-Treiber-Workaround |
| `neanderfunk-ssid-changer` | ssid-changer | Offline-SSID |
| `neanderfunk-wifi-blackout` | wifi-blackout | Radios oben, aber taub |
| `neanderfunk-weeklyreboot` | weeklyreboot | wöchentlicher Neustart |

In eckigen Klammern hinter dem Tag steht der **Check-Name**. Der ist zugleich der
UCI-Schlüssel, mit dem der Check abschaltbar ist
(`uci set hotfix.<check>.disabled='1'` bzw. `linkcheck.<check>.disabled`). Wer
einen Fehlalarm meldet, kann also direkt den Schalter mitliefern.

## 4. Der Meldungskatalog

Vier Klassen. Nur Klasse C und D sind Vorfälle.

### A — Zustand, harmlos, wiederkehrend

Zählen, nicht alarmieren.

| Muster | Bedeutung |
| --- | --- |
| `neanderfunk-linkcheck: batadv\.\S+:N .*` | die Zusammenfassung, eine Zeile mit allen Zählern. Seit Feed-Commit `7d031be` nur noch **bei Zustandsänderung**, sonst stündlich als Lebenszeichen. Bleibt sie länger als 70 min aus, ist der Knoten still oder tot |
| `\[bsses\] \S+ is wifi6/mt7915, not scanning it` | einmal je Interface und Boot. Guter Boot-Marker |
| `mt7915-backlog: \S+: backlog N \(below N\)` | Normalbetrieb |
| `ssid-changer: node is online` / `node is offline` | Zustandswechsel der Offline-SSID |
| `weeklyreboot: scheduled reboot in N seconds` | geplant |

### B — Absichtlich unterlassene Aktion

Der Knoten hat etwas gefunden und **nicht** gehandelt. Das ist Auslegung, kein
Fehler — aber es ist der Vorbote von C.

| Muster | Bedeutung |
| --- | --- |
| `.* - no action taken, uptime below \S+\.settings\.reboot_uptime_min` | jünger als die Karenzzeit (Vorgabe 60 min) |
| `wifi restart skipped, another check is already restarting wifi` | die gemeinsame Sperre `/var/lock/neanderfunk-wifi.lock` hat gegriffen. Sieben Stellen können WLAN neu starten, diese Sperre verhindert, dass sie ineinanderlaufen |
| `wifi restart skipped, last one was Nmin ago \(hotfix\.settings\.hostapd_cooldown_min=N\)` | Abklingzeit |
| `backlog N over N, but wifi was restarted Nmin ago` | dito, mt7915 |
| `safety checks failed .*, exiting with error code 2` | ein Autoupdater-Lauf läuft, alles gehalten |
| `weeklyreboot: .*skipping this week's reboot` | Autoupdater oder Uptime < 1 h |

**Wichtig:** Häuft sich B, ohne dass C folgt, blockiert etwas dauerhaft. Ein
liegengebliebenes `/tmp/hotfix.autoupdater-flashing` etwa entwaffnet das gesamte
Sicherheitsnetz still — sichtbar nur daran, dass `safety checks failed`
unaufhörlich kommt.

### C — Befund mit Eskalationsstufe

Hier steckt die eigentliche Semantik. Die Stufen sind **aufeinanderfolgende
Läufe**, nicht Zeit.

```
neanderfunk-linkcheck: [<check>] lost neighbours 1st: <linkname>.<check>
                                              2nd:
                                              3rd: ..., wifi restart
                                              4th: ..., rebooting!
```

`linkcheck.sh` läuft `*/5`. Also: 1st bis 4th ≈ 20 Minuten, wenn es durchläuft.

Zwei Dinge, die man von außen nicht raten kann:

* Ein Check **schärft sich erst**, wenn er mindestens zwei Nachbarn/Netze/Ports
  gesehen hat (`/tmp/linkcheck.<...>.inhood`). Ein Knoten, der legitim allein
  steht, eskaliert nie. Deshalb ist ein `1st` auf einem frisch aufgestellten
  Knoten unmöglich, und ein `1st` auf einem etablierten Knoten aussagekräftig.
* Die Marker liegen in `/tmp`. Nach einem Reboot ist alles entschärft — eine
  Störung kostet also **höchstens einen Reboot**, danach wartet der Knoten, bis
  er wieder echte Nachbarn gesehen hat.

Weitere Befunde derselben Klasse:

| Muster | Check | Stufen |
| --- | --- | --- |
| `\[hostapd_pids\] hostapd does not serve \S+ \(status: \S+\)` | `hostapd_pids` | 3 Läufe à `*/7` |
| `\[hostapd_pids\] hostapd down and pending on radioN` | `hostapd_pids` | dito |
| `\[hostapd_pids\] channel unknown on \S+` | `hostapd_pids` | dito |
| `\[wifi_firmware\] \S+: firmware register read failed \(strike N of 2\)` | `wifi_firmware` | 2 Läufe à `*/3`, dann Reboot |
| `\[public_prefix\] no public IPv6 prefix on br-client any more` | `public_prefix` | 4 Läufe à `*/8` ≈ 32 min |
| `\[ipv6_anycast\] IPv6 anycast address not reachable` | `ipv6_anycast` | dito |
| `\[bridges\] bridge \S+ gone missing` | `bridges` | über `valuecheck`, 4 Stufen |
| `\[bridge_ports\] \S+ dropped out of bridge \S+` | `bridge_ports` | dito |
| `batman interface \S+ gone missing` | `batinterfaces` | dito |
| `\[wifi_blackout\] no associated station on any radio for N min \(attempt N\)` | `wifi_blackout` | Neustart, dann Reboot |

### D — Aktion ausgeführt

| Muster | Wirkung |
| --- | --- |
| `wifi hard restart` | `wifi down` / `config` / `up`, Clients fliegen ab |
| `\[bsses\] .*3rd: .*, wifi restart` | dito |
| `\[no_wifi_clients\] .*restarting Wifi` | dito |
| `\[dfs_failcheck\] hostapd DFS failcheck, restarting wifi` | dito |
| `mt7915-backlog: .* - restarting wifi` | dito |
| `ssid-changer: reconfiguring wifi to offline ssid` | SSID umgestellt, kein Neustart |
| `rebooting\.\.\. reason: \[(\S+)\] .*` | **Reboot.** Der Grund in Klammern ist der Check-Name |
| `.*4th: .*, rebooting!` | **Reboot** durch linkcheck |
| `\[watchdog\] .*, rebooting via sysrq` | **Reboot**, micrond war 15 min tot. Geht über `/dev/kmsg`, nicht über syslog — im weitergeleiteten Log also evtl. nicht sichtbar |

Die ersten sechs Reboot-Gründe überleben den Neustart in
`/lib/gluon/neanderfunk/reboot.log` — eine Zeile je Reboot, mit Datum und dem
vollen Grund. Dort schreiben inzwischen alle Stellen hinein, die einen Knoten
neu starten: `hotfix` (Checks und Watchdog), `linkcheck` (vierte Stufe und
Gateway) und `wifi-blackout`. Wer per SSH nachsieht: das ist die erste Datei.

Beim Watchdog ist sie sogar die einzige Quelle — dessen Meldung geht über
`/dev/kmsg` und taucht im weitergeleiteten Syslog unter Umständen gar nicht
auf. Steht dort statt der Uhrzeit `uptime=NNNNs`, hat der Knoten beim
Schreiben nicht einmal mehr `date` forken können; das ist für sich schon ein
Befund (Speichermangel).

Ein Firmware-Update wirft die Datei weg, das ist so gewollt: die Frage lautet
immer „warum startet dieses Gerät auf DIESEM Stand neu". Der Deckel ist
`neanderfunk.settings.reboot_log_max` (Vorgabe 6, `0` schaltet das Log ab).

## 5. Was daraus Zeitreihen werden sollten

Pro Knoten und Intervall (5 min reicht):

```
nf_log_lines{node,tag}                    Zeilen je Absender
nf_log_bytes{node,tag}                    Bytes je Absender
nf_finding{node,pkg,check,stage}          Klasse C, stage = 1st|2nd|3rd|4th|single
nf_action{node,pkg,action}                Klasse D, action = wifi_restart|ssid_offline|reboot
nf_withheld{node,pkg,reason}              Klasse B, reason = uptime|lock|cooldown|autoupdater
nf_boot{node}                             Zähler, aus dem Kernel-Bootmuster
```

Die Musterdimension bleibt klein; die Kardinalität steckt in `node`.

## 6. Alarmregeln, die sich lohnen

* **`nf_action{action="reboot"}` > 2 pro Knoten und Tag** — ein Knoten, der sich
  wiederholt neu startet, hat ein Problem, das der Reboot nicht löst.
* **`nf_finding{stage="4th"}` überhaupt** — vier Stufen sind rund 20 Minuten
  Störung.
* **`nf_withheld{reason="autoupdater"}` länger als 6 Stunden** — dann liegt
  vermutlich ein Marker fest und das Sicherheitsnetz ist aus.
* **`nf_finding` gleicher Check über viele Knoten gleichzeitig** — das ist kein
  Knotenproblem, das ist das Netz oder ein Supernode.
* **Die linkcheck-Zusammenfassung bleibt > 70 min aus** — Knoten still.

Nicht alarmieren auf einzelne `1st`/`2nd`: die sind Alltag, und genau dafür gibt
es die Stufen.

## 7. Fallstricke

Aus eigener Erfahrung, jeder davon hat hier schon zu einer falschen Schlussfolgerung
geführt:

**Die Uhr springt.** Die Geräte haben keine RTC. Beim Boot setzt `sysfixtime` die
Uhr auf den Zeitstempel der neuesten Datei im Flash — also auf den letzten
Schreibvorgang, oft Tage alt. Erst NTP zieht sie nach vorn. Ein Logpuffer beginnt
deshalb regelmäßig mit Zeilen, die scheinbar aus der Vergangenheit stammen, und
springt dann. **Alle Zeitstempel vor dem NTP-Sprung sind falsch.** Für Zeitreihen
gilt: die Empfangszeit ist verlässlicher als die Absendezeit, jedenfalls in den
ersten Minuten nach einem Boot.

**Manche Meldungen kommen doppelt.** tunneldigger etwa schreibt jede Zeile
zweimal: einmal per syslog als `td-client:` und einmal über procds
stdout-Mitschnitt als `tunneldigger[<PID>]: td-client: …`. Ursache ist `-f`, das
im Client zusätzlich `LOG_PERROR` setzt. Auf einem Knoten ohne Uplink sind das
zusammen bis zu 90 % des Puffers. Vor dem Zählen deduplizieren, sonst zählt man
alles doppelt.

**Der Ringpuffer ist byte-basiert, nicht zeilenbasiert** (`logd -S 64`, also
64 KiB). Eine lange Zeile verdrängt entsprechend mehr. Wer `logread` pollt statt
sich Zeilen schicken zu lassen, verliert auf lauten Knoten Material: auf einem
Knoten ohne Uplink reicht der Puffer nur rund **40 Minuten** zurück, auf einem
ruhigen mehrere Tage.

**`logread | grep -c` ist keine Rate.** Sobald der Puffer umläuft, altern
Zeilen im selben Takt heraus, in dem neue dazukommen — die Zählung bleibt dann
konstant, egal wie viel passiert. Über Zeitstempel gehen oder den Strom mitlesen.

**Ein leeres Tag-Feld kommt vor.** Manche Meldungen erscheinen als
`user.info : nodeplacer: …` ohne Tag. Der Parser sollte das aushalten.

**Client-MACs stehen selten im Log.** Über vier Knoten und bis zu 65 Stunden
waren es zehn Zeilen, davon sieben hostapd-Assoziationen auf einem einzigen
Gerät. Wer Vendor-Statistiken bauen will, findet sie hier nicht — und wer sich
um Datenschutz sorgt, sollte wissen, dass batman-adv die Client-MACs ohnehin an
**jeden** Knoten im Netz verteilt (`batctl tg`).

## 8. Womit man anfängt

1. Zeilen entgegennehmen, normalisieren, Muster zählen. Ohne jede Regel — nach
   einem Tag weiß man, welche zwanzig Muster 95 % ausmachen.
2. Die Klassen A bis D aus Abschnitt 4 darauf legen.
3. Erst dann alarmieren, und zwar nur auf Abschnitt 6.

Wer Regeln vor der Musterstatistik schreibt, schreibt sie für die Meldungen, die
er sich vorstellt, nicht für die, die tatsächlich kommen.
