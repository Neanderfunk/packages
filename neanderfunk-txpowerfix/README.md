neanderfunk-txpowerfix
======================

Setzt je Radio eine regulatorische Country, die zu den konfigurierten Kanaelen
passt (DE/JP/TW/US), und den breitesten HT-Modus, den die Hardware anbietet.
**Eine Sendeleistung setzt es nicht mehr, bestehende werden entfernt** - siehe
unten. Der Paketname ist geblieben, damit nebenan in `image-customization.lua`
nichts nachgezogen werden muss.

Herkunft: Mit Chaos Calmer (2016) sendeten viele Geraete spuerbar schwaecher als
unter Barrier Breaker, Mesh-Links kippten beim Update von Gluon 2015.x auf
2016.x "von gruen nach rot". Das Paket war der Workaround dafuer (eulenfunk,
abgeleitet von ffho; Diskussion im Freifunk-Forum, Thread "TX-Powerfix Script",
2016).

Was es tut
----------

Laeuft als `/lib/gluon/upgrade/`-Skript, also bei jedem `gluon-reconfigure`:
bei jedem Firmware-Update, beim Verlassen des Config-Mode und beim
Domainwechsel.

* **Country** je Radio aus den Kanaelen (Logik unveraendert).
* **htmode**: fuer 2,4 GHz der beste 20-MHz-Modus, fuer 5 GHz der breiteste
  80/40-MHz-Modus - bei 5 GHz nur, wenn der Kanal nicht `auto` ist und der
  Outdoor-Modus aus ist. Gelesen ueber das iwinfo-Lua-Binding
  (`iwinfo.nl80211.htmodelist(phy)`) im eigenen Prozess, genauso wie Gluons
  `200-wireless`. Scheitert die Abfrage, bleibt Gluons Wert stehen.
* **txpower**: wird **einmal je Knoten** entfernt, sofern
  `gluon.wireless.preserve_txpower` nicht gesetzt ist; danach nie wieder.
* **`gluon.wireless.preserve_channels`**: steht der Schalter, bleibt htmode
  unangetastet - sonst waere die Breite nach jedem Update wieder die breiteste,
  entgegen Gluons Zusage ("the channel width will not be reset"). Die Country
  wird weiter gesetzt, sie folgt aus den ohnehin erhaltenen Kanaelen. Gesetzt
  wird der Schalter von `neanderfunk-preserve-wifichannel`.

Es schreibt nur Config (`uci:save()`, committet wird von Gluons `998-commit`).
Kein `wifi reconf`, kein `iwinfo` als Kommando, kein `sleep`. Laufzeit auf einem
TL-WDR3600: 150 ms.

Warum keine Sendeleistung mehr
------------------------------

Ohne `txpower` in uci sendet ein Radio bereits mit dem Maximum aus Regdomain,
Kanal und Hardware:

* cfg80211 rechnet beim Anwenden der Regdomain je Kanal
  `max_power = min(Hardware-Limit, Regdomain-Limit)` (`net/wireless/reg.c`).
* mac80211 nimmt diesen Wert und zieht eine Vorgabe nur ueber `min()` heran
  (`__ieee80211_recalc_txpower` in `net/mac80211/iface.c`).

Ein gesetzter Wert kann die Leistung also nur **senken**, nie heben. Und er
bleibt stehen, wenn der Kanal spaeter wechselt (`auto`, DFS-Ausweichen) und dort
mehr erlaubt waere. Die fruehere Fassung las mit `iwinfo txpowerlist` genau
dieses `max_power` aus und fror es ein. Im Config-Mode las sie dabei sogar die
falsche Regdomain: dort gilt die der Site (`S20network` macht `iw reg set` mit
`site.regdom`), die gewaehlte Country steht nur in uci, weil kein hostapd laeuft.

Nachgesehen am 2026-09-10 auf neun Testknoten, 17 Radios (mt7986, mt7981,
mt7915, mt7603, mt76x2, ath9k, ath10k):

* Der Wert aus `iw phy phyN info` war in allen 17 Radios identisch mit dem, was
  `iwinfo txpowerlist` liefert.
* Die beiden Radios ohne `txpower` in uci sendeten exakt mit diesem Wert.
* 7 der 17 Radios waren 3 bis 7 dB **darunter** festgeschrieben.

Einmaliges Aufraeumen
---------------------

Festgeschriebene Werte werden **einmal je Knoten** entfernt, beim ersten Lauf
dieser Fassung. Danach steht in `/lib/gluon/core/sysconfig/` der Vermerk
`neanderfunk_txpowerfix_unpinned`, und `txpower` wird nie wieder angefasst.
Das Skript setzt selbst keine Sendeleistung mehr - jeder spaetere Wert kommt
von jemandem, der ihn bewusst gesetzt hat, und bleibt, auch ueber Updates.

Bei jedem Lauf zu entfernen ginge nicht: seit Gluon 2025.1 loest schon das
Speichern der Erweiterten Einstellungen einen `gluon-reconfigure` aus, ein
Domainwechsel tut es in beiden Staenden. Eine dort gesetzte Sendeleistung waere
sofort wieder weg.

Der Vermerk uebersteht jedes sysupgrade. Bei einer Neuinstallation gibt es
nichts zu entfernen, dann wird nur vermerkt.

Wer vor diesem einmaligen Lauf bewusst eine Sendeleistung gesetzt hat und sie
behalten will:

```
uci set gluon.wireless.preserve_txpower='1'
uci commit gluon
```

Solange der Schalter steht, wird weder aufgeraeumt noch vermerkt; aufgeraeumt
wird im ersten Lauf ohne ihn. Default ist `0`, das Skript legt die Option
sichtbar an, sodass `uci show gluon.wireless` sie neben Gluons
`preserve_channels` zeigt. Gluons
`190-preserve-wireless-channels` schreibt die Sektion bei jedem Lauf neu, laesst
andere Optionen darin aber stehen (am Geraet geprueft).

Warum kein Radio-Betrieb mehr
-----------------------------

Beim "Speichern & Neustarten" im Config-Mode laeuft `gluon-reconfigure` im
CGI-Prozess von uhttpd. uhttpd setzt dafuer einmal `script_timeout` (60 s) und
verlaengert ihn nie. Ist er abgelaufen, wird der CGI abgeschossen, bevor
`wizard.lua` zum Reboot kommt: der Browser zeigt "Bad Gateway", der Knoten
startet nicht neu, erst ein Stromzyklus hilft.

Die fruehere Fassung brauchte allein fuer ihre festen Wartezeiten 85 s - um
jeden `iwinfo`-Aufruf lief ein `sleep 20`, das auch dann ausgesessen wurde, wenn
`iwinfo` nach Millisekunden fertig war, dazu ein `sleep 5` und vier
`wifi reconf`. Am 2026-09-10 auf einem Xiaomi 4A Gigabit genau so nachgestellt,
und mit `uhttpd -t 300` gegengeprueft: dann startete er neu.

Noetig war der Radio-Betrieb dabei nie. Die htmode-Liste ist ein statisches
Merkmal der wiphy, unabhaengig von Country, Kanal und laufenden Interfaces. Und
uebernommen wird die Config ohnehin erst beim naechsten Start der Radios - im
Config-Mode folgt der Reboot direkt, beim ersten Boot nach einem sysupgrade
laufen die Radios noch gar nicht.

Einbindung
----------

```
GLUON_SITE_FEEDS="neanderfunk ..."
PACKAGES_NEANDERFUNK_REPO=https://github.com/Neanderfunk/packages.git
PACKAGES_NEANDERFUNK_BRANCH=v2023.2.x
PACKAGES_NEANDERFUNK_COMMIT=<commit>
```

Danach `neanderfunk-txpowerfix` in `image-customization.lua` bzw. `site.mk`
aufnehmen.

Radio-Erkennung (Stand 2026-09-06)
----------------------------------

Welches Radio 2,4 GHz ist und welches 5 GHz, wurde frueher aus der Kanalnummer
geschlossen: unter 16 heisst 2,4, darueber 5, und ein nicht lesbarer Kanal
wurde zu 999. Das ging an zwei Stellen schief:

* **Ein Knoten mit nur einem Radio bekam ein Phantom-5-GHz-Radio.** Auf einem
  TP-Link WR1043ND v2 gibt es kein `radio1`; `uci get wireless.radio1.channel`
  liefert nichts, daraus wurde 999, und 999 > 15 ergab `interface50 = radio1`.
  Folge: die Landeskennung wurde vom Phantom-Zweig entschieden und ueberschrieb
  die richtige Entscheidung aus dem 2,4-GHz-Zweig (bei Kanal 12 oder 13 also
  falsch), dazu zwei ueberfluessige `wifi reconf` und `iwinfo`-Aufrufe auf ein
  Geraet, das es nicht gibt.
* **Ein 2,4-GHz-Radio auf `channel=auto`** wurde ebenfalls zu 999 und landete im
  5-GHz-Zweig.

Seit OpenWrt 21.02 beantwortet `band` (`2g`/`5g`) die Frage direkt; `hwmode`
bleibt als aeltere Schreibweise als Rueckfall. Ausserdem werden jetzt die
`wifi-device`-Sektionen durchlaufen statt fest `radio0`/`radio1` anzunehmen.
