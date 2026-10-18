neanderfunk-default-hostname
============================

Neue Knoten heißen beim ersten Start **`<hostname_prefix><Modell>-<letzte 4 der
node_id>`**, also etwa `dias-WDR3600-1b8c` statt `dias-6466b3ce1b8c`. So, wie
die Testgeräte schon von Hand benannt sind. Geschrieben für **Gluon 2025.1**.

Wie es eingehängt ist
---------------------

Gluon bildet den Vorgabe-Namen an genau einer Stelle,
`gluon.util.default_hostname()`. Der Patch `hostname/default-hostname` in
gluon-patches-packages lässt diese Funktion zuerst dieses Paket fragen und
fällt auf Gluons Form zurück, wenn das Paket fehlt oder das Image unbekannt
ist. Damit gilt die Regel überall, wo Gluon den Vorgabe-Namen nimmt:

- `upgrade/030-system`: Hostname beim allerersten Start (danach nie wieder,
  bestehende Knoten behalten ihren Namen, auch beim Update),
- Wizard `0100-hostname`: Platzhalter, Vorbelegung und "auf Vorgabe zurück",
- `routername` aus neanderfunk-banner (Zurücksetzen auf die Vorgabe).

Kurzname des Modells
--------------------

Aus dem Gluon-Image-Namen (`platform_info.get_image_name()`), nicht aus
`/tmp/sysinfo/model`: der Image-Name ist einheitlich klein geschrieben und mit
Bindestrichen getrennt.

1. Hersteller vorne weg (`tp-link-`, `d-link-`, `mercusys-` ...).
2. Hardware-Revision hinten weg (`-v1`, `-v2.1`, bei D-Link `-a1`/`-b1`),
   ebenso Füllwörter: Region (`-eu-ru`), Flashgröße (`-16m`, `-256mb`),
   Varianten ohne Bedeutung für Menschen (`-xw`, `-dallas`, `-with-...`).
3. Vorsilben der Produktlinie weg oder kürzer: `tl-`, `ws-`, `gl-`,
   `aquila-pro-ai-`; `fritz-box-` wird `FB`, `mi-router-` wird `Mi`,
   `fritz-(wlan-)repeater-` wird `Repeater`. `archer-` bleibt (ArcherC7).
4. Teile mit Ziffern und Teile bis zwei Zeichen groß, sonst großer
   Anfangsbuchstabe; ein `i` direkt hinter einer Ziffer am Ende bleibt klein
   (`ArcherC20i`, `AP3825i`: so steht es auf dem Gerät, und I, l und 1 sehen je
   nach Schrift gleich aus): `nwa50ax-pro` wird `NWA50AXPro`, `unifi-ac-mesh` wird
   `UnifiACMesh`.
5. Eine kleine Tabelle für Namen, bei denen die Regel nichts Brauchbares
   ergibt (`x86-64` wird `x86`, `librerouter-v1` wird `LibreRouter` ...).

Beispiele: `WDR3600`, `WR1043ND`, `MR90X`, `M60`, `CovrX1860`, `WR3000S`,
`FB4040`, `Mi4AGiga`, `NWA50AXPro`, `AP3825i`, `ArcherC7`, `Unifi6LR`. Über
alle 325 Images des Laufs 26100423bro ist der längste Kurzname 17 Zeichen lang.
Revisionen desselben Geräts ergeben denselben Namen, gewollt.

Die letzten vier Stellen der node_id machen den Namen nicht eindeutig (zwei
gleiche Modelle mit gleichen letzten vier Stellen: 1 zu 65536). Eindeutig ist
weiter nur die node_id; der Hostname war das bei Gluon nie.

Prüfen am Knoten:

    lua -e 'print(require("gluon.util").default_hostname())'

Präfix je Domain (Multi-Domain)
-------------------------------

Auftrag adorfer 18.10.2026 über Buildsystem. Knotenaufsteller übernehmen meist
den Vorschlag und schreiben nur in die Mitte etwas dazu (etwa die Straße); das
Ortskürzel vorn soll zur gewählten Domain passen. Gluons `hostname_prefix` ist
site-weit, der Name entsteht beim ersten Start mit der `default_domain`, und im
Wizard steht das Namensfeld über der Domain-Auswahl.

- **Präfix der Domain:** Schlüssel `neanderfunk_hostname_prefix` in der
  Domain-Konfiguration, etwa `neanderfunk_hostname_prefix = 'WLF-',`. Fehlt er,
  gilt das site-weite `hostname_prefix`. Geprüft per `check_site.lua`
  (`in_domain`, optional, String).
- **Vorgabe-Hostname:** nimmt das Präfix der aktuellen Domain.
- **Wizard, nur Ersteinrichtung** (`gluon-setup-mode` `configured` nicht `1`):
  - *im Browser:* Das Template `neanderfunk/hostname-prefix` tauscht das
    Präfix im Namensfeld, sobald die Domain-Auswahl wechselt.
  - *beim Senden:* `wizard/0210-neanderfunk-hostname-prefix` tauscht nach den
    `write()` von `0100-hostname` und `0200-domain-select`, für Browser ohne
    JavaScript. gluon-web arbeitet die Abschnitte der Reihe nach ab, erst
    danach setzt das Formular `configured`.
- **Regel** (`swap_prefix`, dieselbe als JavaScript im Template): Beginnt der
  Name mit dem Präfix einer Domain im Image (längster Treffer, leere Präfixe
  zählen nicht), wird es durch das Präfix der gewählten Domain ersetzt; Mitte
  und Kennung bleiben. Sonst bleibt der Name unverändert.
- Bestehende und migrierte Knoten behalten ihren Namen, ein späterer Umzug in
  eine andere Domain ändert das Präfix nicht.

Getestet 18.10.2026: Regel in Lua und JavaScript (je 8 Fälle), Tausch im
Browser mit einer Nachbildung des Formulars und dem Skript aus dem Template
(Headless-Chromium: Mitte bearbeitet, dann Domain gewechselt), Modul und
serverseitiger Schritt auf 26101300bro in QEMU mit nachgestellten
Domain-Dateien (Präfix je Domain, Rückfall auf das site-weite Präfix,
Alias-Code, `configured=1` lässt den Namen in Ruhe). Nicht getestet: der
echte Wizard mit `gluon-config-mode-domain-select` in einem
Multi-Domain-Image.

Nicht in den Bauten, adorfer evaluiert separat.
