neanderfunk-setup-mode
======================

Der Config-Mode auf **einer** Seite: oben der Wizard (Knoten, Standort,
Internetverbindung, Außenbereich), darunter jedes Formular der Erweiterten
Einstellungen als eingeklappte Gruppe mit Zustandszeile. Gespeichert wird mit
einem einzigen „Speichern & Neustarten“. Information und Firmware-Upgrade
bleiben eigene Seiten und stehen oben im Menü.

Heute verliert, wer vom Wizard in die Erweiterten Einstellungen wechselt,
seine Eingaben. Auf einer Seite gibt es keinen Wechsel mehr.

Braucht [neanderfunk-config-mode-theme](../neanderfunk-config-mode-theme/README.md)
(also `-gluon-config-mode-theme` in `image-customization.lua`):

```lua
packages {
    '-gluon-config-mode-theme',
    'neanderfunk-setup-mode',
}
```

Ohne das Paket ist der normale Wizard zurück.

Was die Seite tut und was nicht
-------------------------------

Die Formulare bleiben die von Gluon und den Paketen. Das Paket lädt, prüft
und schreibt sie so wie `gluon-web-model`. Es entscheidet nur, welche
Formulare auf die Seite kommen, wie sie aussehen und wann sie geschrieben
werden. Neue Seiten unter „Erweiterte Einstellungen“ (ein neues
`model()`-Paket) erscheinen ohne Zutun als weitere Gruppe.

Regeln beim Speichern (`luasrc/usr/lib/lua/neanderfunk/setup-mode.lua`):

1. **Alles oder nichts.** Geschrieben wird nur, wenn alle Formulare gültig
   sind. Passwort und Bestätigung vergleicht gluon-web-admin erst beim
   Schreiben, deshalb prüft das Paket das vorher. Bei einem Fehler öffnet sich
   der Abschnitt, das Feld ist markiert, die Seite springt hin.
2. **Nur geänderte Formulare.** Verglichen wird, was die Seite angezeigt hat,
   mit dem, was zurückkommt. Ein unverändertes Formular wird nicht geschrieben.
   Das spart Flash-Schreibvorgänge und vermeidet Nebenwirkungen. Das
   Passwortformular würde leer sonst `passwd -l root` ausführen, und
   `authorized_keys` würde neu geschrieben.
3. **Der Wizard zuletzt, und immer.** Sein Schreiben setzt `configured`, ruft
   `gluon-reconfigure` und startet neu.
4. **Commit wird zu Save, Reconfigure wird übersprungen**, solange die
   Erweiterten Formulare schreiben. Der `gluon-reconfigure` des Wizards
   committet alles auf einmal (`001-reset-uci` beginnt mit `uci commit`) und
   lässt alle Upgrade-Skripte laufen. Das ist nötig: Auf einer Seite haben
   alle Formulare ihren uci-Cursor vor dem ersten Schreiben geladen. Ein
   Formular, das ein Paket committet, das es nicht geändert hat, schriebe
   sonst eine veraltete Kopie zurück.

**Außenbereich** fragt Gluon doppelt ab: im Wizard (nur Outdoor-Geräte) und
unter WLAN. Auf der Seite steht es einmal. Die WLAN-Variante bleibt, weil
HT-Modus und der 5-GHz-Mesh-Schalter an ihr hängen. Auf Outdoor-Geräten
rückt sie in den Einrichtungsteil, auf allen anderen bleibt sie unter WLAN.

**Passwort:** Auf der Sammelseite bedeutet ein leeres Passwortfeld
„unverändert“. Zum Löschen gibt es den Schalter „Passwort entfernen“. Er
erscheint nur, solange ein Passwort gesetzt ist, und blendet die beiden
Felder aus. Gespeichert führt gluon-web-admin dann wie gewohnt
`passwd -l root` aus. Ist auch das Feld der SSH-Schlüssel leer, gibt es gar
keinen Fernzugriff mehr.

**Meldungen:** Unter einem Feld mit Fehler steht, was es erwartet, zum
Beispiel „Mindestens 12 Zeichen.“, „Keine gültige IPv4-Adresse.“ oder
„Pflichtfeld, bitte ausfüllen.“. Die Meldung ergibt sich aus dem Datentyp des
Feldes. Passwort und Bestätigung vergleicht die Seite schon im Browser
(„Die Passwörter sind nicht gleich.“) und noch einmal auf dem Knoten.

Die alten Adressen unter `admin/` funktionieren weiter und zeigen die
einzelnen Seiten wie bisher.

**Nur „Speichern & Neustarten“** (Entscheidung adorfer): Einen Knopf
„Speichern“ ohne Neustart gibt es auf der Sammelseite nicht, ohne
Seitenwechsel wäre er sinnlos. Im klassischen Wizard bleibt er. Unten rechts
läuft eine Leiste mit dem Knopf und einem Zähler der Änderungen mit.

**Größe:** etwa 15,5 KB xz für dieses Paket und
neanderfunk-config-mode-theme zusammen.

Interna, auf die sich das Paket verlässt
----------------------------------------

Bei jedem Gluon-Update prüfen, besonders beim Wechsel auf 2025.1:

- **Ladereihenfolge der Controller:** Der Dispatcher lädt
  `controller/*.lua`, dann `controller/*/*.lua`, jeweils nach `posix.glob`
  sortiert. `neanderfunk-setup-mode/` kommt nach `gluon-config-mode/` und
  überschreibt `{"wizard"}`. Ändert sich das, kommt der normale Wizard
  zurück. Kaputt geht dabei nichts.
- **Controller erneut ausgewertet:** Der Dispatcher-Baum hält nur Closures.
  Welche Einträge Formulare sind (`model()`) und zu welchem Paket sie
  gehören, liest das Paket deshalb aus einer zweiten Auswertung der
  Controller-Dateien mit eigener Umgebung.
- **Template je Knoten:** `node.template` und `node.package`. Nur Gluons
  Standard-Templates (`model/form`, `model/section`, `model/valuewrapper`)
  werden ersetzt. Eigene Templates der Pakete bleiben.
- **Wizard-Module:** `wizard.lua` lädt sie mit
  `setfenv(assert(loadfile(file)), getfenv())()(f, uci)`. Für die Zuordnung
  Modul → Gruppe wird `loadfile` für diesen einen Aufruf umhüllt. Lädt
  `wizard.lua` einmal anders, landen die Abschnitte in einer Gruppe ohne
  Titel.
- **Form-IDs** werden eindeutig gemacht (`id.nf-<seite>[-<form>]`), sonst
  hießen die Formulare aller Seiten `id.1`.

Setup-Mode beendet sich selbst
------------------------------

Ein Knoten, der im Setup-Mode vergessen wird, kommt nach einer Frist (Vorgabe
24 h) von allein zurück ins Netz: Nach Ablauf geschieht dasselbe wie bei
„Speichern & Neustarten“ (configured=1, `gluon-reconfigure`, Neustart). Auf
einem nie eingerichteten Knoten bleiben es die Standardwerte. Anlass: ein Cudy
in der Werkstatt, gut 25 h im Setup-Mode vergessen (adorfer, 04.10.2026).

Dateien: `/lib/gluon/setup-mode/rc.d/S98neanderfunk-setup-autoexit` startet
beim Eintritt in den Setup-Mode eine procd-Instanz mit
`/lib/gluon/neanderfunk-setup-mode/autoexit run <sekunden>`. Die Frist misst
`sleep`, also unabhängig von der Uhrzeit (die steht im Setup-Mode ohne NTP).

Einstellung, die erste gesetzte gilt:

| Ort | Schlüssel | Werte |
|---|---|---|
| uci | `gluon-setup-mode.@setup_mode[0].autoexit` | 0/1 (auch true/false, on/off, yes/no) |
| uci | `gluon-setup-mode.@setup_mode[0].autoexit_timeout` | Sekunden |
| site.conf | `setup_mode.autoexit.enabled` | true/false |
| site.conf | `setup_mode.autoexit.timeout` | Sekunden, 600 bis 604800 (check_site) |
| Vorgabe | | an, 86400 s |

    setup_mode = {
      autoexit = {
        enabled = true,      -- ohne Angabe: an
        timeout = 86400,     -- ohne Angabe: 24 h
      },
    },

`/lib/gluon/neanderfunk-setup-mode/autoexit conf` zeigt, was gilt
(`<an> <sekunden>`).

**Kein paralleles Speichern.** Das Skript nimmt dieselbe Sperre wie der
Wizard (`/var/gluon/setup-mode/wizard-save`, gluon-patches-fixes
`wizard-save-lock`): atomar anlegen, PID hinein, nach `gluon-reconfigure`
`wizard-save.done`. Hält das Skript die Sperre, wartet ein Klick auf
„Speichern & Neustarten“ und bekommt danach nur die Neustart-Seite. Hält ein
Klick die Sperre, tritt das Skript zurück und versucht es alle 30 s wieder.
Startet der Knoten danach nicht neu (Formular ungültig, der Wizard gibt die
Sperre frei), läuft es weiter, bis es die Sperre bekommt oder ein `.done`
sieht. Eine verwaiste Sperre (Prozess weg, kein `.done`) übernimmt es wie der
Wizard.

Geprüft am 04.10.2026 in QEMU (x86-64, 26100312bro, frisches Image im
Setup-Mode): Vorgaben und uci-Varianten von `conf`; Ablauf nach 90 s
(gespeichert, Neustart, Normalbetrieb mit configured=1, enabled=0);
fremde Sperre mit lebendem Prozess (Rückzug, alle 30 s neu), danach
verwaiste Sperre übernommen und neu gestartet; umgekehrt Klick per CGI-POST,
während die Sperre gehalten wird (wartet, kein zweites `gluon-reconfigure`,
nach `.done` Neustart-Seite).

Test
----

In QEMU (x86-64, Setup-Mode, eine NIC mit hostfwd auf 192.168.1.1:80).
Templates, CSS, JS und Lua hängen nicht von der Architektur ab. Ins Overlay
kopiert, laufen sie auf jedem Knoten im Setup-Mode.

Lizenz
------

BSD-3-Clause, siehe [LICENSE](LICENSE).
