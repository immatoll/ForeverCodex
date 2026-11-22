# Forever Codex – Projektleitfaden für Agents und Mitwirkende

> **Zuerst lesen, zuletzt aktualisieren.** Diese Datei ist das Gedächtnis des Projekts. Lies sie vor jeder
> Änderung. Wenn sich Struktur, Konventionen, Slash-Befehle, Saved-Variables oder Entscheidungen ändern,
> aktualisiere sie im selben Arbeitsschritt (siehe „Pflege dieser Datei“). Der Stand ist nur so gut wie
> der letzte Eintrag.

## Was das ist

Ein persönliches World-of-Warcraft-Addon für WoW Forever (Classic-Reihe, `## Interface: 16001`, Lua 5.1),
gedacht als allumfassende Suite. Es hieß früher *ForeverKillLog* (daher stammen Teile der Historie und
die Übernahme alter Daten). Es zeichnet Kills und Beute pro Quelle auf und bewertet sie. Dazu kommen Sitzungs-HUD, Journal, Kartenfenster,
Account-Fenster (Altoholic-artig), Einstellungsfenster, Tooltips, eigener Auktionshaus-Scan, Routen und
Benachrichtigungen. Optik: „vergoldetes Braun“. Sprachen: Englisch (Quelltext) und Deutsch (Locale).

Der Ordner liegt direkt unter `Interface\AddOns\ForeverCodex\`. Saved Variables: `ForeverCodexDB`
(Datei `WTF\Account\<KONTO>\SavedVariables\ForeverCodex.lua`, also nie im Repo). Der Dateiname dort richtet
sich nach dem Ordnernamen.

## Arbeitsregeln

- **Nichts davon ist im Spiel automatisch getestet.** Es gibt kein WoW-Testumfeld im Terminal. Sag im
  Bericht immer klar, was ungetestet ist. Behaupte nie „funktioniert“, wenn nur die Syntax geprüft wurde.
- Nach jeder Lua-Änderung die Blockprüfung laufen lassen: `python tools/blockcheck.py <Dateien>.lua`
  (Pfade relativ zum Addon-Ordner). Sie findet fehlende/überzählige `end`. Echtes `luacheck` ist
  nicht installiert. Wenn es später dazukommt, ist es besser.
- Der Nutzer schreibt Deutsch oder Englisch; antworte in der Sprache der letzten Nachricht, knapp, mit
  Ergebnis zuerst.
- Neue Anzeigetexte immer auf Englisch in den Code und als Deutsch in `Locale.lua` eintragen (siehe unten).
- Größere Änderungen vorher kurz benennen, bei Unklarheiten nachfragen. Nichts Zerstörerisches ohne
  Rückfrage (z. B. SavedVariables-Migrationen, die Daten verwerfen).

## Dateien und Ladereihenfolge

Die Reihenfolge steht in `ForeverCodex.toc` und ist wichtig. Neue Dateien dort eintragen.

| Datei | Aufgabe |
|---|---|
| `Libs\` | LibStub, CallbackHandler, LibDataBroker, LibDBIcon (Fremdcode, Lizenzen in `Libs\THIRD_PARTY_NOTICES.txt`) |
| `Locale.lua` | `ns.L`: Übersetzungstabelle (Schlüssel = englischer Text) |
| `Value.lua` | Preise: Händler, Auktion (Auctionator oder eigener Scan), `V.Format` für Geld |
| `Core.lua` | Events, Loot-Erfassung, Quellen, Datenbank, Slash-Befehle (`/fc`), Debug |
| `Account.lua` | Datenschicht pro Charakter (`ns.Acc`): Ausrüstung, Taschen, Bank, Post, Berufe, Rezepte, AH |
| `AuctionScan.lua` | Eigener AH-Scan, Preisverlauf (`ns.AH`) |
| `AuctionTab.lua` | Reiter „Codex“ im Auktionshaus: Listen (Alle/Deine Gegenstände/Rezepte/Trends), Filterspalte, Übergänge; `Build` hat fast das Upvalue-Limit |
| `Theme.lua` | Zentrale Layout-Maße je Fenstergruppe (`ns.Theme.Get(gruppe, schlüssel)`, Überschreibungen in `ForeverCodexDB.theme`), Entwicklerfenster `/fctheme`. Bisher nur Gruppe `hud` (Kills & Loot) |
| `BgPicker.lua` | Entwicklerwerkzeug `/fcbg`: Galerie der Blizzard-Hintergründe/Icons mit Testfenster |
| `ItemInfo.lua` | Kleines Fenster zu einem Gegenstand (Rechtsklick-Menü im AH-Reiter): Berufs-Tabs, Rezeptzeilen (UI.NewListView), welche Charaktere das Rezept kennen |
| `AuctionDashboard.lua` | Erste Seite des Reiters: Vermögen, sehenswerte Taschen-Gegenstände, Markt (günstig/steigend), lohnende Rezepte |
| `Data\Recipes.lua`, `Data\Disenchant.lua` | Erzeugt von `toolsuild_recipes.py` / `toolsuild_disenchant.py` (Quellen: wago.tools, DisenchantBuddy) |
| `Tooltip.lua` | Item- und Kreatur-Tooltips, Optionsliste `ns.TIP_OPTIONS` |
| `Widgets.lua` | Gemeinsame UI-Bausteine `ns.W` (Buttons, Platte, Griff zum Skalieren, `TopFrameIs`) |
| `Dropdown.lua` | Hover-Kontextmenü `W.NewDropdown` / `W.NewMenuButton` |
| `Data\MapOverlays.lua` | Kartendaten |
| `MapView.lua` | Kartenansicht, Marker (Teile, Badge), `ns.MapData` |
| `UI.lua`, `SessionHUD.lua` | Hauptfenster-Gerüst, Sitzungs-HUD („Kills & Loot“) |
| `Page*.lua` | Journal-Seiten (Quellen, Beute, Suche, Verlauf, Statistik) |
| `Routes.lua`, `Spots.lua` | Routen und Fundorte |
| `MapMain.lua`, `MapWindow.lua` | Kartenfenster (`/fcmap`), Mini-Karte (`/fcmini`) |
| `AccountWindow.lua` | Account-Fenster (`/fcaccount`, `/fcalts`), sehr groß |
| `SettingsWindow.lua` | Einstellungen (`/fcsettings`) mit Kategorien und Beschreibungen |
| `Minimap.lua` | Minimap-Knopf |
| `Media\` | Logo (`logo.tga` 256 px, `logo64.tga` für die Minimap, `logo.png` fürs README, mit Alpha), Konzeptbilder in `Media\concepts\` (Icons für später). Erzeugt mit `tools\make_addon_logo.py` und `tools\cut_concepts.py` aus den Konzeptblättern; `tools\make_logo.py` ist die erste selbstgezeichnete Idee (`Media\drawn*`) |
| `tools\` | Hilfsskripte außerhalb des Spiels (nicht im `.toc`) |

Alle Dateien teilen `local ADDON, ns = ...`. Es gibt keine globale API außer `ForeverCodexDB` und den
Slash-Befehlen.

## Konventionen (wichtig, sonst bricht das Addon)

- Fensterstil (`settings.frameStyle`): `ornate`, `plain`, `blizzard`. Jedes Fenster hat eine `ApplyFrameStyle`; `blizzard` legt über `W.BlizzSkin(frame, on)` einen Blizzard-Rahmen (ButtonFrameTemplate o. ä.) hinter das Fenster, fehlt das Template, bleibt es bei `plain`. Neue Fenster müssen alle drei Stile behandeln.

- **Lua 5.1**, keine `goto`/Bit-Operatoren der neueren Versionen. Maximal **60 Upvalues pro Funktion**:
  `SessionHUD.Render` liegt bei ca. 54. Dasselbe gilt für `Build` in `AuctionTab.lua` (53; Konstanten stehen deshalb gebündelt in der Tabelle `K`). Ein Überschreiten bricht das Laden der ganzen Datei ab, ohne Chat-Meldung (nur im Fehlerlog). Zählen: alle Datei-Locals, die in einer Funktion samt ihren inneren Funktionen vorkommen. Neue Hilfsfunktionen in eine Tabelle packen statt als weiteres
  `local`.
- **Geheimwerte im Kampf:** Unit-Daten können „secret“ sein. Immer `ns.Readable` / `ns.ReadableNumber`
  verwenden, bevor verglichen oder formatiert wird.
- **API-Varianten** (Auktion, Handwerk, Taschen) per Feature-Erkennung und `pcall` abdecken, nie nur eine
  Variante annehmen.
- **Fenster** teilen ein Rezept: `deco`-Rahmen, `fill`, hängendes `banner`, Schließen- und
  Deckkraft-Knopf, Fensterknopfreihe oben links (Journal, Sitzung, Karte, Account, **Einstellungen immer
  zuletzt**). Neue Fenster daran ausrichten.
- **Hover/Scroll:** Nur das oberste Fenster reagiert (`W.TopFrameIs`). Neue Hover-Logik muss das
  nutzen, denn das Mausrad erreicht sonst verdeckte Fenster.
- **Ziehen/Skalieren (`W.AttachScaleGrip`):** Ziehen = Größe, Strg = Skalierung, Umschalt = Proportionen,
  Rechtsklick beim Ziehen = abbrechen, Rechtsklick auf den Griff = zentrieren, Umschalt+Rechtsklick =
  Standardgröße, Strg+Rechtsklick = Standardskalierung. Der Griff-Tooltip ist eine Tabelle Taste → Aktion.
- **Geld** immer über `ns.Value.Format` ausgeben (Zahlen weiß, nur Münzbuchstaben farbig, Gewinn getönt).
- **Optionen:** Tooltip-Optionen stehen in `ns.TIP_OPTIONS`, Beschreibungen in der `DESC`-Tabelle der
  `SettingsWindow.lua`. Neue Option = Eintrag + Beschreibung + Locale. Einstellungen liegen in
  `ns.db.settings`.
- **Lokalisierung:** `L["English text"]`. Deutsche Texte in `Locale.lua` direkt **vor** der Ankerzeile
  `L["Mini map"] = "Mini-Karte"` einfügen. Fehlt ein Eintrag, erscheint der englische Text. Prüfen, dass
  der Schlüssel noch nicht existiert.
- Eingerückt wird mit 4 Leerzeichen. Kommentare erklären das „Warum“, kurz, auf Englisch. Dem
  Stil der Umgebung folgen.
- Die Lua-Dateien sind (fast alle) CRLF. **Beim Bearbeiten das vorhandene Zeilenende der Datei
  beibehalten** (nicht umwandeln, sonst entsteht ein Riesen-Diff). Vor dem ersten Commit eine
  `.gitattributes` mit `* text=auto` anlegen, damit Git das einheitlich handhabt.

## Daten und Migration

- `ForeverCodexDB` hat `DB_VERSION` (siehe `Core.lua`). `InitDB` übernimmt einmalig die Daten der alten
  Variable `ForeverKillLogDB` (`.toc` listet beide Namen). Diese Übernahme nicht entfernen, solange alte
  Spielstände existieren können. Wer das Format ändert, schreibt eine
  Migration und erhöht die Version. Alte Daten dürfen nie stillschweigend verloren gehen.
- Account-Daten: `ns.db.account.chars[key]` pro Charakter. Leere Werte dürfen vorhandene nicht
  überschreiben (z. B. Geld nie mit 0 beim Abmelden). Siehe `Keep()` in `Account.lua`.
- AH-Verlauf: `ns.db.ahData[realm-faction] = { prices, time, count, hist }`, 14 Tage, höchstens 3000
  Items. Klein halten, die Datei wird bei jedem Login geladen.

## Slash-Befehle

`/fc` (Hilfe, `debug`, `accdebug`, `account`/`alts`, `settings`/`options`), `/codex`, `/fcmap`, `/fcmini`,
`/fcaccount`, `/fcalts`, `/fcsettings`. Die alten Namen (`/fkl`, `/killlog`, `/fcmap`, `/fklmini`, `/fklaccount`,
`/fklalts`, `/fklsettings`) funktionieren weiter als Aliase.

## Debuggen im Spiel

- `/fc debug` schaltet Protokoll im Chat ein: Sammelzauber, Beutefenster, Chat-Beute-Ersatz.
- `/fc accdebug`: Zustand der Account-Daten.
- Nach Änderungen `/reload`. Lua-Fehler zeigt man mit `/console scriptErrors 1` oder einem
  Fehler-Addon (BugSack/BugGrabber).
- Bekannte Eigenheiten: Beim Sammeln (Bergbau, Kräuter) kommt in manchen Clients kein Beutefenster.
  Dann greift der Chat-Beute-Ersatz in `Core.lua` (`ns.OnChatLoot`). Leichen von Gegnern ohne XP
  haben teils leere Beutefenster (0 Slots) und zählen nicht als Kill.

## Offene Punkte / Ideen

- Leere Leichen als Kill des toten Ziels zählen (angeboten, nicht entschieden).
- Karten-Menü auf das gemeinsame `Dropdown`-Widget umstellen.
- Debug-Code zum Sammeln entfernen, sobald das Verhalten gesichert ist.
- Crafting-Spalte „Gewinn“ als Prozent.
- Alles bisher Gebaute ist nur im Spiel prüfbar. Bei Rückmeldungen daraus hier vermerken, was bestätigt ist.

- **Fenster-Design festlegen (offen, Nutzer macht es später):** Mit `/fcbg` (Hintergrund, Icon, Layout, Deckkraft je Fenster) und `/fctheme` (Layout-Maße Kills & Loot) ausprobieren, dann `/fctheme` → „Export“ und den Text in `Theme.lua` (`T.defaults`, `T.skins`, `T.design`) eintragen. `W.SkinOf` liest diese Standards bereits. Panel-Transparenz (`settings.panelAlpha`) steht nicht im Export.
- **Blizzard-Stil, Kopfbereich (bestätigt am Kills-&-Beute-Fenster, `SessionHUD.lua`):** Der Rahmen steht 54 über dem Fenster, die Titelleiste liegt bei y +54 bis +28, der Streifen darunter ab y +24 und rechts vom Ring ab x 56 ist nutzbar (dort: drei kompakte Statuskarten, Pause/Beenden gestapelt rechts). Dasselbe soll für die anderen Fenster (Account, Karte, Einstellungen, Journal) versucht werden; Inhalte entsprechend nach oben ziehen. Das Layout wird beim Laden über `ns.AfterLoad` festgelegt.
- Kills & Beute: Tabs Regionboard und Route sind nicht mehr im Fenster (Code in `SessionHUD.lua` liegt brach). Die Route soll bei Bedarf als eigenes Fenster ausgegliedert werden.
- Vertagt: Live-Bearbeiten-Modus für Layout-Maße (Umbau SessionHUD), Schrift/Farben im Theme, gleiche Tabellenlayouts überall, Journal komplett neu gestalten.

## Arbeitsablauf mit Git/GitHub (Empfehlung)

**Eine Kopie, kein Doppelleben:** Das Repo liegt direkt im Addon-Ordner
(`...\AddOns\ForeverCodex\`, dort `git init`). Der Ordner ist der Arbeitsstand, den das Spiel lädt. Mit
`/reload` testet man sofort, ohne zu kopieren oder zu verlinken. Der Ordnername muss `ForeverCodex`
bleiben (gleich dem `.toc`-Namen, sonst lädt das Spiel das Addon nicht).

- **`main`** ist stabil. Entwickelt wird auf Zweigen (`feature/...`, `fix/...`) oder direkt auf einem
  `dev`-Zweig. Zurück auf `main` wechselt man erst, wenn es im Spiel getestet ist. Ein Zweigwechsel
  ändert die Dateien im Ordner, was das Spiel beim nächsten `/reload` lädt.
- **„Produktiv“ vs. „Testen“:** Wer mit einer stabilen Version spielen und gleichzeitig testen will, legt
  einen zweiten Ordner an: `git worktree add ..\ForeverCodex_dev dev`. Dessen `.toc` müsste dann
  anders heißen, daher ist das nur für Gelegenheiten nötig. Im Normalfall: stabil = Tag, Test = Zweig.
- **Releases:** Version im `.toc` (`## Version:`) erhöhen, Tag `vX.Y.Z` setzen, ZIP bauen, dessen oberster
  Ordner `ForeverCodex/` heißt. GitHubs automatisches „Source code (zip)“ hat den falschen Ordnernamen
  (`ForeverCodex-main`). Dafür eine GitHub Action oder den BigWigs-Packager verwenden, der den
  Ordnernamen korrekt setzt (`.pkgmeta`).
- **Commits** klein und thematisch, Nachrichten auf Englisch oder Deutsch, aber einheitlich.
- `.gitignore` (vor dem ersten Push anlegen): `*.bak`, `*.tmp`, `*.zip`, `.vscode/`, `.claude/`,
  `scratch/`, Editor-Dateien. **Niemals** `WTF\`-Dateien einchecken (Saved Variables enthalten
  Charakternamen, Goldstände, Server).
- Vor dem ersten Push prüfen: Keine Namen/Server/Geld aus Testdaten in Beispielen? Keine Pfade wie `F:\...` im
  Code? `LICENSE` (All Rights Reserved, Christian Remy), `README.md` und Autor im `.toc` sind angelegt. Libs
  behalten ihre eigenen Lizenzen (`Libs\THIRD_PARTY_NOTICES.txt`).
- `CurseForge`/`Wago` später über `.pkgmeta` und die Projekt-IDs im `.toc`. Erst, wenn das Addon
  veröffentlicht werden soll.

## Pflege dieser Datei

Aktualisiere diese Datei im selben Schritt, wenn du

- eine Datei hinzufügst, löschst oder umbenennst (Tabelle oben und `.toc`),
- einen Slash-Befehl, eine Saved-Variable, `DB_VERSION` oder eine Konvention änderst,
- eine Erkenntnis gewinnst, die nicht aus dem Code ersichtlich ist (Client-Eigenheiten, Fallen,
  getroffene Entscheidungen und das Warum),
- etwas aus „Offene Punkte“ erledigst oder neu aufnimmst.

Kurz halten: nur das, was man sonst jedes Mal neu herausfinden müsste. Keine Chronik, dafür gibt es
die Git-Historie.
