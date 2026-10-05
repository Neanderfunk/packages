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
   Anfangsbuchstabe: `nwa50ax-pro` wird `NWA50AXPro`, `unifi-ac-mesh` wird
   `UnifiACMesh`.
5. Eine kleine Tabelle für Namen, bei denen die Regel nichts Brauchbares
   ergibt (`x86-64` wird `x86`, `librerouter-v1` wird `LibreRouter` ...).

Beispiele: `WDR3600`, `WR1043ND`, `MR90X`, `M60`, `CovrX1860`, `WR3000S`,
`FB4040`, `Mi4AGiga`, `NWA50AXPro`, `AP3825I`, `ArcherC7`, `Unifi6LR`. Über
alle 325 Images des Laufs 26100423bro ist der längste Kurzname 17 Zeichen lang.
Revisionen desselben Geräts ergeben denselben Namen, gewollt.

Die letzten vier Stellen der node_id machen den Namen nicht eindeutig (zwei
gleiche Modelle mit gleichen letzten vier Stellen: 1 zu 65536). Eindeutig ist
weiter nur die node_id; der Hostname war das bei Gluon nie.

Prüfen am Knoten:

    lua -e 'print(require("gluon.util").default_hostname())'
