# Entscheidungs-Log

Laufendes Protokoll der Ueberlegungen und Entscheidungen. Neueste Eintraege
unten anhaengen, bestehende nicht umschreiben (nur Status aendern).
Status: **offen** / **entschieden** / **verworfen**.

## D-001 Projektname

* Status: **entschieden** (adorfer, 2026-09-04)
* Name: **nodeplacer**. Paket `neanderfunk-nodeplacer` (Community-Praefix,
  siehe D-029), UCI-Config
  `/etc/config/nodeplacer`, site.conf-Block `nodeplacer`, Manifest
  `nodeplacer.manifest`, C-Helfer `nodeplacer-fetch`, Hauptprogramm
  `/usr/sbin/nodeplacer`. Projektordner umbenannt nach
  `~/projekte/freifunk/packages/neanderfunk-nodeplacer`.
* Historie: Arbeitstitel war "domainswitch"; verworfen wegen Kollision mit
  `gluon-scheduled-domain-switch` und `gluon-switch-domain`. Anforderung
  war: keine negativen, z. B. xenophoben Konnotationen wie "forced
  migration". "nodeplacer" (der Knoten wird platziert) erfuellt das.
* Fuer ein Upstreaming in community-packages waere ein Community-Praefix
  (`nef-nodeplacer`, `eulenfunk-nodeplacer`) ueblich; entscheiden wir dann.

## D-002 Primaere Zielversion

* Status: **entschieden** (adorfer, 2026-09-04)
* Gluon **v2023.2.x** zuerst. Perspektive v2025.1. Backport v2021.1.x
  (es gibt kein Gluon 2021.2; gemeint ist die Reihe v2021.1.x, die die
  Firmware frueher benutzt hat).

## D-003 Steuerkanal ueber signiertes Manifest im Autoupdater-Stil

* Status: **entschieden** (Vorgabe adorfer, bestaetigt durch Recherche)
* Gleiches Rahmenformat wie das Autoupdater-Manifest (Kopf, Nutzdaten,
  `---`, Signaturen), damit `contrib/sign.sh`, `ecdsasign` und die
  vorhandenen Schluessel unveraendert funktionieren.
* Mindestsignaturen und Mirrors kommen aus site.conf, nicht aus dem
  Manifest.

## D-004 Signaturpruefung mit libecdsautil

* Status: **entschieden** (adorfer: "libecdsautil ist perfekt", 2026-09-04)
* Begruendung: liegt wegen des Autoupdaters auf jedem Knoten; gleiche
  Krypto, gleiche Schluesselformate, gleiche Semantik (n-of-m, legacy).
* Umsetzungsform noch **offen**:
  * (a) Paket `ecdsautils` als Abhaengigkeit, Aufruf von `ecdsaverify -s ... -p ... -n N <datei>`
    aus Lua. Vorher muss Lua die Datei an `---` teilen und den oberen Teil
    in eine Temp-Datei schreiben. Kein eigener C-Code, aber ein zusaetzliches
    Feed-Paket im Image.
  * (b) Kleiner C-Helper im Package (`src/verify.c`, CMake wie
    `autoupdater/src`), der die Manifest-Semantik des Autoupdaters
    (`manifest.c`: hashen bis `---`, Signaturen danach) 1:1 uebernimmt und
    nur "gueltig ja/nein plus Anzahl" zurueckgibt. Code ist BSD-2-Clause und
    kann uebernommen werden.
  * Tendenz: (b), weil es ohne Temp-Dateien auskommt, keine Feed-Abhaengigkeit
    einfuehrt und exakt das Verhalten des Autoupdaters hat. Nachteil:
    Build-Komplexitaet und Backport-Test auf OpenWrt 19.07.

## D-005 Multidomain-Wechsel ueber `gluon-switch-domain`

* Status: **entschieden** (aus Recherche)
* Statt `uci set gluon.core.domain` + `gluon-reconfigure` + `reboot` (Sketch)
  wird das Core-Kommando `gluon-switch-domain <domain>` benutzt. Es setzt
  `switch_domain`, committet und rebootet; gluon-core wendet den Wechsel
  beim Boot an. Identisch in v2021.1, v2023.2, v2025.1.

## D-006 Single-Domain-Wechsel ueber Autoupdater-Kommandozeile

* Status: **entschieden** (aus Recherche)
* `autoupdater -f --force-version -b <branch> <mirror...>`. Mirrors per
  Kommandozeile statt UCI-Umschreiben; Pubkeys aus der lokalen
  Branch-Section. UCI-Delta ohne Commit nur im Sonderfall "Branch lokal
  unbekannt".
* `--force-version` ist Pflicht (gleiche Versionsnummer in Zieldomain).
* Beide Optionen sind auch in v2021.1.x vorhanden (diff gegen packages-Feed
  v2021.1.x).

## D-007 Node-Identitaet

* Status: **entschieden** (aus Recherche)
* `gluon.util.node_id()` (Primary-MAC ohne Doppelpunkte). Entspricht
  nodeinfo `node_id` und ist protokollunabhaengig. `network.bat0.macaddr`
  aus dem Sketch ist in Gluon dieselbe Adresse, aber nicht bei Layer-3-Mesh.

## D-008 Implementierungssprache

* Status: **entschieden** (adorfer, 2026-09-04)
* Moeglichst viel in **Lua**, nicht in Shell. Begruendung: Gluon-Konvention
  (luasrc, Minify), bessere Testbarkeit auf dem Host, `simple-uci`,
  `posix`, `jsonc` verfuegbar. Shell nur, wo unvermeidbar. C nur fuer
  Signaturpruefung (D-004) und respondd-Provider.

## D-009 Schalter zum Abschalten

* Status: **entschieden** (Vorgabe adorfer)
* `nodeplacer.disable` mit Default `0` (bewusst doppelte Verneinung,
  analog zu Schaltern wie `vpn-disable`).
* Hinweis aus der Recherche: Gluon-Core-Pakete verwenden `enabled`
  (`autoupdater.settings.enabled`, `mesh_vpn.enabled`). Falls das Package
  in community-packages upstream gehen soll, koennte ein Reviewer
  `enabled` verlangen. Kein Blocker, nur festgehalten.

## D-010 Dateiname und Aufteilung des Manifests

* Status: **entschieden**, revidiert 2026-09-04
* Erster Vorschlag war eine Datei pro Quell-Domain
  (`<site_code>.manifest`). Verworfen, weil die Manifeste **von Hand
  gepflegt und von Hand signiert** werden (adorfer): eine Datei pro Domain
  hiesse mehrere Dateien editieren und mehrfach signieren.
* Jetzt: genau **eine Datei `nodeplacer.manifest`** pro Mirror
  (`<mirror>/nodeplacer.manifest`). Alle Knoten der Community laden
  dieselbe Datei; sie ist bei manueller Pflege klein (Handvoll Zeilen).
* Bestaetigt 2026-09-04 (adorfer): **eine zentrale Datei fuer alle 40+
  Domains** von Neanderfunk, damit der Maintenance-Aufwand der Admins klein
  bleibt. Folge: `nodeplacer.mirrors` in allen Site-Templates zeigt auf
  denselben zentralen Pfad (z. B. `http://firmware.ffnef.de/nodeplacer`),
  nicht auf die domainspezifischen Firmware-Verzeichnisse.
* Aufteilung pro Domain bleibt als spaetere Optimierung moeglich (Knoten
  probiert erst `<site_code>.manifest`, dann `nodeplacer.manifest`),
  wird in FORMAT=1 aber nicht umgesetzt.

## D-011 hoodselector

* Status: **entschieden** (adorfer, 2026-09-04: out of scope)
* Kompatibilitaet mit `gluon-hoodselector` ist nicht gefordert; er wird
  nicht eingesetzt. Im Makefile trotzdem `CONFLICTS:=+gluon-hoodselector`
  eintragen, damit ein versehentliches Zusammenbauen beim Build scheitert
  statt im Betrieb (hoodselector wuerde jeden Wechsel binnen 2 Minuten
  zurueckdrehen). Kein Override, keine weitere Beruecksichtigung.

## D-012 Alles im RAM, Versuchslimit als rollendes Fenster

* Status: **entschieden** (adorfer, 2026-09-04)
* Der Knoten schreibt fuer einen Wechselversuch **nichts ins Flash**:
  * UCI-Aenderungen fuer den Autoupdater-Lauf (Branch-Section, Mirrors,
    Pubkeys) nur per `uci set`/`uci:save` ins Delta unter `/tmp/.uci`,
    **kein `uci commit`**. libuci wendet das Delta beim Laden an, der
    Autoupdater sieht die Werte. Nach Reboot ist alles weg.
  * Wo die Kommandozeile reicht (`-b`, Mirrors als Argumente), ist auch
    das Delta unnoetig (D-006). Beides ist RAM-only.
  * Versuchszaehler und "zuletzt angewandtes DATE" liegen in `/tmp`
    (uptime-basiert), nicht in UCI.
  * Einzige Ausnahme: `gluon-switch-domain` committet `gluon` selbst; das
    ist Core-Verhalten und noetig, damit der Wechsel den Reboot ueberlebt.
* Versuchslimit: **3 Versuche in 7 Tagen**, als rollendes Fenster, also
  nicht endgueltig aufgeben: nach Ablauf des Fensters wieder 3 Versuche,
  ggf. "ewig". Der Betreiber beendet das durch Entfernen der Zeile oder
  ueber `EXPIRES`.
* Folge: ein Reboot (Stromausfall) setzt den Zaehler zurueck. Akzeptiert,
  weil der Zaehler nur Flapping und Dauerlast auf dem Mirror begrenzen
  soll, nicht Sicherheit herstellt. Sicherheit kommt aus Signatur und
  `EXPIRES`.
* Ersetzt die UCI-Section `state` aus dem ersten Entwurf.

## D-013 respondd-Provider

* Status: **entschieden** (Vorschlag Claude, offen fuer Einspruch)
* Kleiner Provider fuer `nodeinfo.software.nodeplacer`, damit auf der
  Karte sichtbar ist, welche Knoten adressiert wurden und haengen.

## D-014 Projektort und Repository

* Status: **entschieden**
* Entwicklung in `~/projekte/freifunk/packages/neanderfunk-nodeplacer` (eigenes
  Git-Repo). Auslieferung spaeter ueber den eulenfunk-Feed
  (https://github.com/eulenfunk/packages, Branch v2023.2.x) oder
  community-packages.

## D-015 Kern aus der Autoupdater-Codebasis ableiten

* Status: **entschieden** (adorfer, 2026-09-04: "faktisch die gleiche
  Codebasis wie der Gluon-Autoupdater")
* Der Autoupdater (`packages`-Feed, `admin/autoupdater/src`, BSD-2-Clause)
  enthaelt bereits alles, was der Steuerkanal braucht:
  * `uclient.c`: HTTP-Download ueber libuclient (IPv6, Redirects,
    Timeouts, Groessenlimit)
  * `manifest.c`: zeilenweises Hashen bis `---`, Signaturen danach
  * `autoupdater.c`: Signaturpruefung n-of-m mit libecdsautil, Mirror-
    Zufallsauswahl, Lockfile, Ausgabe/Fehlerbehandlung
  * `settings.c`: UCI-Listen (mirror, pubkey, good_signatures) laden
  * `hexutil.c`, `util.c`: Hex-Parsing, safe_malloc, run_dir
* Daraus wird ein C-Programm `nodeplacer-fetch` (Arbeitsname): laedt das
  Nodeplacer-Manifest von den konfigurierten Mirrors, prueft Signaturen
  und Kopf, gibt bei Erfolg die Nutzdatenzeile(n) fuer die eigene Node-ID
  (oder den ganzen verifizierten Nutzdatenteil) auf stdout aus; Exit-Code
  unterscheidet "nicht adressiert", "kein Manifest", "Signatur ungueltig",
  "Fehler".
* Die **Policy** (Plausibilitaet, Zustand/Versuchslimit, Auswahl und Aufruf
  von `gluon-switch-domain` bzw. `autoupdater`) bleibt in **Lua**
  (`/usr/sbin/nodeplacer`), passend zu D-008. Damit ist der C-Teil ein
  duenner, gut abgegrenzter Fork ohne Geschaeftslogik, und der Lua-Teil ist
  auf dem Host testbar.
* Ersetzt die Umsetzungsfrage in D-004: (b) mit erweitertem Umfang
  (Download + Verify statt nur Verify). Kein `uclient-fetch` aus Lua noetig
  (schliesst offene Frage 7 in DESIGN.md).
* Lizenz: BSD-2-Clause beibehalten, SPDX-Header mit Herkunftshinweis.

## D-016 Manifest-Format: zeilenbasiert wie das Autoupdater-Manifest

* Status: **entschieden** (Formatwahl an Claude delegiert, 2026-09-04)
* Kein JSON, kein CSV. Gruende:
  * Die Signatur deckt den Text vor `---` byteweise ab. JSON muesste
    kanonisiert werden; jede Neuformatierung durch einen Editor braeche die
    Signatur. Zeilen mit Whitespace-Trennung sind robust gegen Editoren.
  * `contrib/sign.sh` und `ecdsasign` funktionieren unveraendert, weil sie
    nur die `---`-Zeile kennen muessen.
  * Menschen editieren die Datei von Hand; Kopf `KEY=VALUE`, eine Zeile
    pro Knoten, `#`-Kommentare. Sieht aus wie das bekannte
    Firmware-Manifest.
  * Der C-Helfer (D-015) kann den Parser des Autoupdaters fast unveraendert
    benutzen; Lua parst die Nutzdaten mit `string.match`.
  * CSV haette keine Vorteile gegenueber Whitespace-Trennung, aber
    Quoting-Fragen bei URLs.
* Details in MANIFEST-FORMAT.md.

## D-017 Serverseite

* Status: **entschieden** (adorfer, 2026-09-04)
* Keine Automatisierung, keine Server-Skripte im Projekt. Die Datei
  `nodeplacer.manifest` wird manuell editiert und manuell signiert, mit
  denselben Werkzeugen und Schluesseln wie die Firmware-Manifeste.
* Folge fuer das Format: Eintraege muessen ohne Werkzeug tippbar und
  pruefbar sein (Node-ID, Methode, Ziel); `EXPIRES` ist Pflicht, damit
  vergessene Eintraege nicht ewig wirken.

## D-018 Listen in einer Manifestzeile: wiederholbare `key=wert`-Token

* Status: **entschieden** (Frage adorfer, Entscheidung Claude, 2026-09-04)
* Nutzdatenzeile: `<node_id> <methode> key=wert [key=wert ...]`.
  Mirror-Listen als `mirror=URL mirror=URL ...`, Reihenfolge der Token
  beliebig, Wiederholung bildet die Liste.
* Verworfen: Positionsfelder (brechen bei optionalem `branch` vor der
  Liste) und Kommalisten (Komma ist in URLs zulaessig, Zeile wird
  unleserlich).
* Strenge Validierung: unbekannter Key oder fehlender Pflicht-Key macht die
  Zeile ungueltig (Log, keine Aktion). Bei Handpflege soll ein Tippfehler
  zu "nichts" fuehren.
* Zeilenlimit im C-Helfer von 512 auf 2048 Zeichen anheben (vier
  Neanderfunk-Mirrors sind etwa 450 Zeichen).

## D-019 Keine Knotenregistrierung bei Neanderfunk, aber Doku-Pflicht

* Status: **entschieden** (adorfer, 2026-09-04)
* Neanderfunk hat keine fastd-Schluessel- oder sonstige Knotenregistrierung;
  fuer die eigene Community ist das kein Thema.
* In der Doku muss stehen: Hat die **Zieldomain** solche Mechanismen
  (Peer-Registrierung, Whitelist, Zertifikate), muss der Knoten dort vor
  dem Umzug bekannt gemacht werden, sonst kommt er ohne VPN an. Das
  betrifft vor allem Umzuege in Domains fremder Communities.

## D-020 Umzug in Fremd-Domains: abgestimmtes Verfahren, sonst off limits

* Status: **entschieden** (adorfer, 2026-09-04)
* Begriff (adorfer): "Fremd-Domain" = Domain einer anderen Community in
  einer anderen Region. Andere Domains der eigenen Community sind keine
  Fremd-Domains, sondern der Normalfall.
* Technisch: Sysupgrade behaelt die UCI-Konfiguration. Nach dem Flash einer
  fremden Firmware bleiben Keys aus der alten site.conf (Hostname-Praefix,
  Branch-Namen, Zusatzpakete, Preserved-Settings) bestehen. Die
  **Zielfirmware** muss damit umgehen koennen; in vielen Faellen wird die
  Ziel-Community eine eigene Migrations-Firmware bauen muessen (Vorbild:
  Migrationspakete wie `ffac-change-autoupdater`,
  `eulenfunk-migrate-updatebranch`).
* Organisatorisch: Ein Umzug in eine fremde Domain verlangt ein zwischen
  den Communities abgestimmtes Verfahren (Schluessel, Firmware, Zeitpunkt,
  Ansprechpartner). Knoten "kalt" in eine fremde Domain zu schieben soll
  nicht nur technisch scheitern, sondern ist **off limits**.
* nodeplacer selbst bleibt auf "gleiche Community" ausgelegt (Minimum-
  Feature). Es verhindert Fremd-Umzuege nicht aktiv (die Signaturen der
  eigenen Maintainer entscheiden), aber die Doku macht die Grenze klar.

## D-021 C-Helfer gibt den ganzen Nutzdatenteil aus; Groessenannahmen

* Status: **entschieden** (adorfer, 2026-09-04)
* `nodeplacer-fetch` gibt den kompletten verifizierten Teil vor `---` aus,
  Lua filtert die eigene Node-ID heraus. Der C-Teil bleibt frei von
  Node-ID-Logik; Gruppenadressierung ist spaeter moeglich.
* Inhalt der Datei sind nur die **Ausnahmefaelle**: Knoten, die
  umplatziert werden sollen. Nach dem Umzug entfernen die Admins die Zeile
  von Hand wieder.
* Groessenannahme fuer die Implementierung: **nie mehr als 100 Knoten,
  in der Regel unter 10.** Bei 500 Bytes pro Zeile sind das maximal etwa
  50 KB. Die Datei wird komplett im RAM gehalten (C-Puffer und Lua-String),
  kein Streaming, keine Obergrenzen-Optimierung. Als Schutz gegen
  fehlerhafte Server begrenzt der Helfer den Download hart (Vorschlag
  256 KB) und bricht darueber ab.

## D-022 Repo-Layout: Projekt-Repo ist der Feed

* Status: **entschieden** (Claude, 2026-09-04)
* Das Paket liegt unter `neanderfunk-nodeplacer/` im Projekt-Repo. OpenWrt-Feeds
  suchen rekursiv nach `Makefile`s, das Repo kann also direkt als
  `GLUON_SITE_FEEDS`-Feed eingebunden werden. Docs, Skizzen und Tests
  bleiben ausserhalb des Paketverzeichnisses.
* Alternative (Paket in eulenfunk/packages einpflegen) bleibt fuer die
  Auslieferung offen; fuer die Entwicklung ist ein eigenes Repo einfacher.

## D-023 Aufruf des C-Helfers per os.execute mit Ausgabedatei

* Status: **entschieden** (Claude, 2026-09-04)
* `gluon.util.subprocess.popen` gibt es erst ab Gluon 2023.x, nicht in
  v2021.1.x. Fuer den Backport ruft das Lua-Hauptprogramm den Helfer
  deshalb per `os.execute('nodeplacer-fetch > /tmp/nodeplacer.body')` auf
  und dekodiert den Wait-Status (Lua 5.1 liefert `exit << 8`).
* stderr des Helfers geht durch (micrond-Log), stdout nur in die Datei.

## D-024 Abbruch bei laufendem Autoupdater

* Status: **entschieden** (adorfer, 2026-09-04; ersetzt den ersten Vorschlag
  "keine Pruefung")
* Der Autoupdater lockt per `flock(2)` und haelt den Lock ueber den exec
  von sysupgrade hinweg. luaposix kann flock-Locks nicht testen (nur
  fcntl-Locks, die davon unabhaengig sind).
* Umsetzung: das Lua-Hauptprogramm liest `/proc/[0-9]*/comm` und bricht
  still ab, wenn ein Prozess `autoupdater` oder `sysupgrade` heisst.
  Damit sind beide Phasen abgedeckt (Download/Pruefung und das eigentliche
  Flashen).
* Zusaetzlich stoppt `gluon-autoupdater` micrond in `download.d`, sodass
  nodeplacer waehrend eines Updates ohnehin nicht mehr gestartet wird.

## D-025 Autoupdater-Quellen aus dem zu Gluon passenden Feed-Stand

* Status: **entschieden** (Claude, 2026-09-04, nach Build-Fehler)
* Die zuerst uebernommene `uclient.c` aus dem `main`-Branch des
  packages-Feeds benutzt `uclient_new_ssl_context()` (HTTPS-Support),
  das in libuclient von OpenWrt 23.05 (2023-04-13) nicht existiert:
  Linker-Fehler beim Bau fuer Gluon 2023.2.x.
* Uebernommen wird deshalb der Stand des Feeds, den Gluon v2023.2.x pinnt
  (`PACKAGES_GLUON_COMMIT` d75722c, `admin/autoupdater/src`). Die Dateien
  `uclient.c`/`uclient.h` sind dort ohne SSL; `hexutil.c`, `manifest.c`,
  `util.c` sind zwischen 2023.2 und main identisch.
* Fuer v2025.1 (neuere libuclient, HTTPS-Mirrors) kann spaeter wieder die
  SSL-faehige Variante verwendet werden; nodeplacer-Mirrors sind bis dahin
  `http://` (check_site erzwingt das).

## D-026 Multidomain deutlich zurueckgestellt

* Status: **entschieden** (adorfer, 2026-09-04)
* Bis zum ersten finalen Release wird nur mit Single-Domain-Firmware
  gearbeitet und getestet (Methode `firmware`). Multidomain-Firmware und
  damit die Methode `domain` kommen erst danach; dafuer sind mehrere
  externe Dinge zu klaeren, unter anderem "nodeplacer funktioniert in der
  Praxis".
* Der `domain`-Codepfad bleibt im Paket (klein, an `gluon-switch-domain`
  delegiert), gilt aber als **ungetestet** und wird im README so
  gekennzeichnet. Kein Multidomain-Testimage, kein qemu-Test dafuer.

## D-027 Release wartet auf Aenderungen im Buildsystem

* Status: **entschieden** (adorfer, 2026-09-04)
* Kein Release, keine Feed-Einbindung und keine Aenderung an den
  Site-Templates, bevor die noetigen Aenderungen im Buildsystem
  (`~/projekte/freifunk/firmware`) gemacht sind. Die Release-Schritte aus
  DESIGN/TESTING bleiben als Liste stehen, werden aber nicht angegangen,
  bis adorfer das Signal gibt.

## D-028 Entwicklungs-Repo bei Adorfer, Teilmenge im Community-Feed

* Status: **entschieden** (adorfer, 2026-09-04)
* Das **gesamte** Projekt liegt in `Adorfer/neanderfunk-nodeplacer-dev` (privat).
* In den Community-Feed `Neanderfunk/packages`, Branch `v2023.2.x`, wandert
  nur die veroeffentlichte Teilmenge, eingebettet als Verzeichnis
  `neanderfunk-nodeplacer/`, weil OpenWrt-Feeds ein Paket je Verzeichnis
  erwarten:
  * `neanderfunk-nodeplacer/` (das Paket) nach `neanderfunk-nodeplacer/`
  * `docs/` nach `neanderfunk-nodeplacer/docs/`
  * die Projekt-`README.md` nach `neanderfunk-nodeplacer/docs/PROJEKT.md`, damit sie
    weder die Feed-`README.md` noch die Paket-`README.md` verdraengt.
* Synchronisation mit `scripts/sync-to-feed.sh`: ein Commit je Lauf, nur
  das Paketverzeichnis wird angefasst, die Historie des Feeds wird
  nicht umgeschrieben. Kein Force-Push, kein `filter-branch` auf dem Feed.
* Verworfen: ein eigenes abgeleitetes GitHub-Repo
  (`Adorfer/neanderfunk-nodeplacer`) mit gefilterter Historie. Es war ein
  Zwischenschritt und wird nicht weiter gepflegt.
* Wichtig: Dateien im Feed zu haben ist noch **kein** Release. Solange
  keine Site ihren `modules`-Commit hochzieht und `nodeplacer` in
  `image-customization.lua` listet, aendert sich an keinem Build etwas
  (siehe D-027).

## D-029 Community-Praefix im Paketnamen

* Status: **entschieden** (adorfer, 2026-09-04)
* Das Paket heisst `neanderfunk-nodeplacer`, das Entwicklungs-Repo
  `Adorfer/neanderfunk-nodeplacer-dev`, das Projektverzeichnis
  `~/projekte/freifunk/packages/neanderfunk-nodeplacer`.
* Grund: die Herkunft soll am Namen ablesbar sein. Die uebrigen Pakete des
  Feeds (`eulenfunk-*`, `gluon-*`) werden demnaechst ebenfalls umbenannt,
  das aber spaeter und nicht im Rahmen dieses Projekts.
* **Unveraendert bleiben die Laufzeitnamen**, weil sie das Ding benennen
  und nicht das Distributionspaket, und weil sie bereits auf Knoten
  getestet sind: `/usr/sbin/nodeplacer`, `/usr/sbin/nodeplacer-fetch`,
  `/etc/config/nodeplacer`, der site.conf-Block `nodeplacer`,
  `/usr/lib/lua/nodeplacer/`, `/usr/lib/micron.d/nodeplacer`,
  `/tmp/nodeplacer.state` und der Dateiname `nodeplacer.manifest`.
  Einzige Ausnahme: der respondd-Provider heisst
  `/usr/lib/respondd/neanderfunk-nodeplacer.so`, weil `gluon.mk` ihn nach
  `PKG_NAME` benennt; das Feld in nodeinfo bleibt
  `software.nodeplacer`. Dasselbe Muster benutzen andere
  Community-Pakete (z. B. `ffac-ssid-changer` mit kurzen Laufzeitpfaden).

## D-030 Zielschluessel und Zielschwelle im Manifest, Vertrauensanker

* Status: **entschieden** (adorfer, 2026-09-04)
* Drei Eigenschaften der Zieldomain sind **unabhaengig** voneinander und
  werden im Manifest einzeln angegeben, wenn sie abweichen:
  Branchname (`branch=`), Signaturschluessel (`pubkey=`) und Mindestzahl
  gueltiger Signaturen (`good_signatures=`). Default ist jeweils der Wert
  des Knotens; innerhalb der eigenen Community steht deshalb nur `mirror=`
  in der Zeile.
* Anlass: eine fremde Community kann ihre Firmware mit anderen Schluesseln
  und einer anderen Schwelle freigeben. Neanderfunk verlangt drei
  Signaturen, andere verlangen zwei; mit der lokalen Schwelle wuerde das
  fremde `stable.manifest` grundlos abgelehnt.
* Behobener Fehler: bisher wurden mitgelieferte Schluessel nur benutzt,
  wenn die Branch-Section lokal fehlte. Bei gleichem Branchnamen, dem
  Normalfall, wurden sie stillschweigend ignoriert.
* Alles bleibt RAM-only (D-012): `uci set` ohne `commit`, Wirkung fuer
  genau einen Autoupdater-Lauf, nach dem Reboot weg.
* Schutz vor Unsinn: Schwelle muss eine positive Zahl sein und darf die
  Zahl der wirksamen Schluessel nicht ueberschreiten. Fehlt die Schwelle
  bei einer neu angelegten Branch-Section, gilt die Zahl der uebergebenen
  Schluessel.
* **Vertrauensanker:** Bei diesem Eingriff sind es zu 100 Prozent die
  Signaturen unter `nodeplacer.manifest` (adorfer), weil damit fast
  beliebige Dinge gemacht werden koennen. Die eingebackenen
  Firmware-Schluessel wirken hier nicht mehr als zweiter Anker. Wer
  `nodeplacer.good_signatures` in der site.conf setzt, bestimmt damit das
  gesamte Sicherheitsniveau des Verfahrens.

## D-031 Vertrauensanker ist der aktive Autoupdater-Branch

* Status: **entschieden** (adorfer, 2026-09-04)
* Die Steuerdatei wird mit den Schluesseln **und** der Mindestzahl
  Signaturen des Branches geprueft, auf dem der Knoten laut Flash steht
  (`autoupdater.settings.branch`, dann `autoupdater.<branch>.pubkey` und
  `.good_signatures`).
* Begruendung: wer eine Firmware fuer diesen Knoten freigeben darf, darf
  ihn auch verschieben. Ein Knoten auf `stable` mit drei geforderten
  Signaturen verlangt drei auch fuer die Steuerdatei; einer auf `broken`
  mit einer verlangt eine.
* `nodeplacer.good_signatures` und `nodeplacer.pubkeys` in site.conf sind
  damit **optionale Overrides** und laut adorfer "eher nicht sinnvoll".
  Der Override gewinnt, wenn er gesetzt ist; das ist getestet.
* Vorher war `nodeplacer.good_signatures` Pflicht in site.conf, waehrend
  die Schluessel schon auf den Branch zurueckfielen. Das war unsymmetrisch
  und haette bei einem Knoten im `broken`-Branch eine unpassende Schwelle
  erzwungen.
* Fail closed: fehlt der aktive Branch in der Autoupdater-Konfiguration
  und steht auch nichts in site.conf, bricht `nodeplacer-fetch` mit
  Konfigurationsfehler ab, statt eine Schwelle zu raten.
* Klarstellung (adorfer, 2026-09-04): das `branch=` in einer
  Firmware-Zeile der Steuerdatei hat **keinen** Einfluss auf diese
  Schwelle. `nodeplacer-fetch` verifiziert die Steuerdatei komplett,
  bevor er auch nur eine Zeile daraus parst; er kennt zu diesem Zeitpunkt
  keine Eintraege, nur den Kopf. Massgeblich ist ausschliesslich der
  Branch, auf dem der Knoten laut Flash gerade laeuft
  (`autoupdater.settings.branch`). `branch=` im Eintrag sagt dem
  spaeter aufgerufenen Autoupdater nur, unter welchem Namen er die
  Firmware am **neuen** Mirror sucht (`<mirror>/<branch>.manifest`);
  das ist ein voellig getrennter Vorgang mit eigener Signaturpruefung
  durch den Autoupdater selbst (siehe Abschnitt 3.2 in DESIGN.md).
* Geprueft und bestaetigt (adorfer): im Auftrag stand als Beispiel, ein
  Knoten im `broken`-Branch solle "dann 3" verlangen; das war ein
  Tippfehler. Es gilt der Wert des **aktiven** Branches, im Beispiel also
  zwei. Ein Maximum ueber alle konfigurierten Branches ist ausdruecklich
  nicht gemeint.

## D-032 Zielschwelle folgt dem eigenen Vertrauensniveau, nicht dem Zielbranch-Namen

* Status: **entschieden** (adorfer, 2026-09-04, echter Bug auf dem
  Testknoten gefunden und behoben)
* Fehler: Ohne `good_signatures=` im Eintrag fiel die Schwelle fuer die
  Zielfirmware bisher auf `autoupdater.<zielbranch>.good_signatures`
  zurueck, sofern der Branch-Name lokal bereits existierte. Auf dem
  Testknoten (aktiver Branch `broken`, dort Schwelle 1,
  `nodeplacer.good_signatures=2` als Override) fuehrte das dazu, dass ein
  Umzug mit Zielbranch `stable` die dort schon konfigurierte, aber fuer
  diesen Vorgang voellig unbeteiligte Schwelle 3 verlangte, statt der 2,
  mit der die Steuerdatei selbst gerade erfolgreich geprueft worden war.
* Korrektur: Standardwert der Zielschwelle ist jetzt das eigene aktuelle
  Vertrauensniveau des Knotens, exakt derselbe Wert, der schon zur
  Pruefung von `nodeplacer.manifest` diente (`nodeplacer.good_signatures`
  als Override, sonst die Schwelle des **aktiven** Autoupdater-Branches,
  D-031). Wer eine Steuerdatei mit N Signaturen unterschreiben kann, darf
  den Knoten auch auf eine mit N Signaturen versehene Firmware schicken -
  unabhaengig vom Namen des Zielbranches. `good_signatures=` im Eintrag
  bleibt ein explizites Override obendrauf.
* Klargestellt (adorfer): `branch=` im Eintrag beeinflusst **nur**, unter
  welchem Namen der spaeter aufgerufene Autoupdater die Firmware am neuen
  Mirror sucht (`<mirror>/<branch>.manifest`); es hat nichts mit dieser
  Schwelle zu tun (siehe Klarstellung in D-031).
* Auf dem Testknoten nachgewiesen: mit dem Fix wurde das echte, nur mit
  zwei Signaturen versehene `stable.manifest` von `02_met.key` akzeptiert
  (Log: "2 signatures required", nicht mehr 3).

## D-033 Kein UCI-Rueckstand nach einem nicht-flashenden Lauf

* Status: **entschieden** (adorfer, 2026-09-04)
* Zusaetzlich zum Fehler in D-032 fiel auf: weder ein `-n`-Trockenlauf noch
  ein fehlgeschlagener echter Lauf setzten das UCI-Delta der
  Autoupdater-Branch-Section zurueck. Eine ueberschriebene (zu niedrige
  oder fremde) Schwelle oder Schluesselliste blieb bis zum naechsten
  Reboot aktiv - und haette in der Zwischenzeit auch den regulaeren, per
  Cron laufenden Autoupdater beeinflusst, obwohl gar keine Firmware
  installiert wurde.
* Korrektur: der Autoupdater laeuft jetzt in beiden Faellen (`-n` und
  echt) als Kindprozess (`os.execute`, also fork+exec+wait) statt per
  `exec()`. Bei einem echten, erfolgreichen Lauf rebootet die Maschine
  ohnehin, bevor irgendein Lua-Code danach liefe - das Delta wird beim
  naechsten Boot ganz normal frisch aus dem Flash gelesen. In jedem
  anderen Fall (Fehlschlag, oder `-n`, das definitionsgemaess nie
  flasht) kehrt die Kontrolle zurueck, und `uci:revert('autoupdater',
  <branch>)` verwirft genau das Delta dieser einen Section, ohne
  zusaetzliche Eintraege in `uci changes` zu hinterlassen.
* Verworfen: alte Werte manuell merken und per `uci:set()` zurueckschreiben
  (erster Vorschlag adorfer). Funktional gleichwertig, aber `uci:revert()`
  ist einfacher, weniger fehleranfaellig und hinterlaesst kein Journal.
* Auf dem Testknoten nachgewiesen: nach einem erzwungenen Fehlschlag
  (unerreichbarer Zielmirror) stand `autoupdater.stable.good_signatures`
  wieder auf dem Flash-Wert, `uci changes autoupdater` zeigte keine
  `stable.*`-Eintraege mehr.

## D-034 Config-Mode-Web-UI als eigenes, optionales Paket

* Status: **entschieden** (adorfer, 2026-09-04: "Kannst Du fuer den
  Configmode ein luci-modul dazufuegen ... damit im Web-UI des
  Configmodes das disable gesetzt werden kann")
* Neues Paket `neanderfunk-web-nodeplacer`, analog zu
  `ff-ap-timer`/`ff-web-ap-timer`: der Kern (`neanderfunk-nodeplacer`)
  bleibt ohne `gluon-web-admin`-Abhaengigkeit installierbar, das Web-Modul
  ist optional und haengt zusaetzlich von `+gluon-web-admin
  +neanderfunk-nodeplacer` ab.
* Platzierung (adorfer: "Keine Ahnung, mach wie es einfacher ist"): ein
  eigener Tab "Nodeplacer" auf der bestehenden "Advanced settings"-Seite
  (`admin`-Menu von `gluon-web-admin`), Gewicht 85, direkt nach
  "Automatic updates" (80). Kein neues Untermenue, keine Aenderung an
  einem fremden Paket noetig - jedes Feature dort registriert nur seinen
  eigenen `entry({"admin", "<name>"}, ...)`.
* UI zeigt eine positive Checkbox "Enabled" (nicht "Disable"), invertiert
  beim Schreiben auf `nodeplacer.settings.disable` - konsistent mit jedem
  anderen Tab auf dieser Seite (`gluon-web-autoupdater` macht es fuer
  `enabled` identisch, nur ohne Inversion noetig, weil deren UCI-Key
  schon positiv heisst).
* Vorbild fuer die Form/Section/Flag-API: `gluon-web-autoupdater`s Modell
  (Apache-2.0), strukturell nachgebaut, kein Text uebernommen.
* **Nicht getestet:** die eigentliche Rendering-/Interaktions-Pipeline.
  Gluons Config-Mode laeuft in einem eigenen Boot-Modus mit eigenem
  uhttpd (`/lib/gluon/setup-mode/rc.d/S50uhttpd`), der nur erreichbar
  ist, wenn der Knoten explizit in diesen Modus (neu-)startet
  (Taster/`gluon-enter-setup-mode`). Das haette einen zusaetzlichen,
  eigenstaendigen Reboot des Testknotens in einen Sondermodus verlangt -
  ungefragt nicht gemacht. Stattdessen: Host-Test mit einem
  Form/Section/Flag/uci-Stub (`tests/test_web_nodeplacer.lua`) fuer die
  Default-/Schreiblogik, echter `opkg install` auf dem Testknoten fuer
  Dateiablage und Abhaengigkeitsaufloesung, `loadfile()` auf dem
  Ziel-Lua-Interpreter fuer die Syntax, luacheck fehlerfrei.
* `scripts/sync-to-feed.sh` synct jetzt beide Paketverzeichnisse
  (`neanderfunk-nodeplacer`, `neanderfunk-web-nodeplacer`).
