neanderfunk-button-bind
=======================

Mit diesem Paket kann im Config-Mode dem Wifi-Taster des Routers eine eigene
Funktion zugeordnet werden. Das Paket übernimmt dafür `/etc/rc.button/rfkill`
und legt OpenWrts eigenen Handler als `rfkill.owrt` daneben, der im Default-Fall
weiterhin aufgerufen wird.

Verfügbare Funktionen (`uci set button-bind.wifi.function=N; uci commit`):

| N | Funktion |
| --- | --- |
| 0 | Wifi an/aus (OpenWrt-Verhalten) |
| 1 | keine Funktion (Default) |
| 2 | Wifi-Reset |
| 3 | Nachtmodus: LEDs generell aus, nur während der Taster gedrückt ist an (braucht einen Reboot) |

Einstellbar ist das auch im Config-Mode unter „Taster".

Knoten ohne Taster oder ohne WLAN
---------------------------------

Die Seite erscheint im Config-Mode nur, wenn der Knoten überhaupt Taster hat,
und die WLAN-Optionen nur, wenn er WLAN hat:

| Knoten | „Taster"-Seite | angebotene Optionen |
| --- | --- | --- |
| Taster + WLAN (z. B. COVR-X1860) | ja | alle vier |
| Taster, kein WLAN | ja | nur „Funktionslos" und „Nachtmodus" |
| kein Taster (z. B. x86-VM) | nein | – |

Erkannt wird das am **Device Tree**: ein Target mit Tastern deklariert sie dort
(der COVR hat `/sys/firmware/devicetree/base/keys` mit `reset` und `wps`, die
x86-VM hat gar keinen Device Tree). Zwei naheliegende Signale taugen dafür
ausdrücklich *nicht*, beide am echten Gerät gegengeprüft:

* `/dev/input` liefert das Ergebnis **verkehrt herum** — `gpio-button-hotplug`
  erzeugt Hotplug-Events statt Input-Devices, der COVR hat deshalb gar keinen
  `/dev/input`-Eintrag, während die x86-VM „Power Button" und eine AT-Tastatur
  meldet.
* `/etc/hotplug.d/button/` wird von Paketen befüllt (`gluon-setup-mode` legt
  dort seinen Handler ab) und ist auf beiden Knoten identisch.

Ohne Taster passiert auch sonst nichts Schädliches: `rfkill.btnb` wird mangels
Button-Event nie aufgerufen. Der Symlink auf `/etc/rc.button/rfkill` wird
trotzdem gesetzt — genau so hält es Gluon mit seinem eigenen
Setup-Mode-Button-Handler.

Herkunft und Credits
--------------------

Portiert von **`ffffm-button-bind`** aus
<https://github.com/freifunk-ffm/packages/tree/master/ffffm-button-bind>,
© 2019 Freifunk Frankfurt am Main, MIT-Lizenz (siehe `LICENSE`). Die
Weiterentwicklung von rubo77 (Freifunk Nord) liegt unter
<https://github.com/rubo77/ffm-packages>.

Gegenüber dem Original geändert
-------------------------------

Nur das Nötige, damit es hier sauber läuft:

* Paketname auf `neanderfunk-*` gezogen, Upgrade-Skript entsprechend auf
  `888-neanderfunk-button-bind`.
* **Bugfix im Upgrade-Skript.** Das Original machte unbedingt
  `mv rfkill rfkill.owrt`. Das Skript läuft aber bei *jedem*
  `gluon-reconfigure` — also nicht nur beim Firmware-Upgrade, sondern auch beim
  Verlassen des Setup-Modes und beim Domain-Wechsel, ohne Sysupgrade
  dazwischen. Beim zweiten Lauf schiebt es damit den *eigenen Symlink* über das
  gesicherte Original: `rfkill.owrt` zeigt danach auf `rfkill.btnb`, und weil
  dessen Default-Zweig genau `rfkill.owrt` aufruft, führt ein Tastendruck in
  den Endlos-Aufruf. Auf einem Knoten nachgestellt und bestätigt. Gesichert
  wird jetzt genau einmal, und nur wenn `rfkill` wirklich noch die
  Originaldatei ist.
* Die Config-Mode-Seite ist an vorhandene Taster gekoppelt und die
  WLAN-Optionen an vorhandenes WLAN (siehe oben). Das Original zeigte beides
  bedingungslos — auf einer x86-VM ohne Taster und ohne WLAN also eine Seite,
  die „Wifi an/aus" anbietet.
* Der Default-Zweig in `rfkill.btnb` prüft jetzt mit `[ -x ... ]`, ob
  `rfkill.owrt` überhaupt existiert. Auf einem Target, dessen base-files kein
  `rfkill` mitbringen, sichert das Upgrade-Skript keines, und der Aufruf ginge
  ins Leere.
* `uci get` → `uci -q get` in beiden Skripten: fehlt die Config oder die
  Option, schrieb das Original eine Fehlermeldung nach stderr. Am Verhalten
  ändert sich nichts, der Default-Zweig greift so oder so.
* `CONFLICTS:=ffffm-button-bind`, weil beide dieselben Pfade und denselben
  rfkill-Handler beanspruchen.
* Der Aufruf `$(call GluonInstallI18N,$(PKG_NAME),$(1))` ist entfallen. Das
  Paket hat kein `i18n/`-Verzeichnis, und in Gluon v2023.2 nimmt
  `GluonInstallI18N` nur *ein* Argument (das Zielverzeichnis) — mit zwei
  Argumenten hätte es ein Verzeichnis namens `$(PKG_NAME)/lib/gluon/web/i18n`
  angelegt. Stattdessen `BuildPackageGluon`, das `files/`, `luasrc/` und ein
  eventuelles `i18n/` ohnehin selbst erledigt.

Die Oberflächentexte sind bewusst auf Deutsch geblieben, passend zum Rest
unserer Config-Mode-Seiten.
