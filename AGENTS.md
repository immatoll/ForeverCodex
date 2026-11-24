# Forever Companion – Projektleitfaden für Agents und Mitwirkende

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

Der Ordner liegt direkt unter `Interface\AddOns\ForeverCompanion\`. Saved Variables: `ForeverCompanionDB`
(Datei `WTF\Account\<KONTO>\SavedVariables\ForeverCompanion.lua`, also nie im Repo). Der Dateiname dort richtet
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

Die Reihenfolge steht in `ForeverCompanion.toc` und ist wichtig. Neue Dateien dort eintragen.

| Datei | Aufgabe |
|---|---|
| `Libs\` | LibStub, CallbackHandler, LibDataBroker, LibDBIcon (Fremdcode, Lizenzen in `Libs\THIRD_PARTY_NOTICES.txt`) |
| `Locale.lua` | `ns.L`: Übersetzungstabelle (Schlüssel = englischer Text) |
| `Value.lua` | Preise: Händler, Auktion (Auctionator oder eigener Scan), `V.Format` für Geld |
| `Core.lua` | Events, Loot-Erfassung, Quellen, Datenbank, Slash-Befehle (`/fc`), Debug |
| `Account.lua` | Datenschicht pro Charakter (`ns.Acc`): Ausrüstung, Taschen, Bank, Post, Berufe, Rezepte, AH |
| `AuctionScan.lua` | Eigener AH-Scan, Preisverlauf (`ns.AH`) |
| `AuctionTab.lua` | Reiter „Companion“ im Auktionshaus: Listen (Alle/Deine Gegenstände/Rezepte/Trends), Filterspalte, Übergänge; `Build` hat fast das Upvalue-Limit |
| `Theme.lua` | Zentrale Layout-Maße je Fenstergruppe (`ns.Theme.Get(gruppe, schlüssel)`, Überschreibungen in `ForeverCompanionDB.theme`), Entwicklerfenster `/fctheme`. Bisher nur Gruppe `hud` (Kills & Loot) |
| `BgPicker.lua` | Entwicklerwerkzeug `/fcbg`: Galerie der Blizzard-Hintergründe/Icons mit Testfenster |
| `AuctionSell.lua` | Verkaufs-Panel unter einer Zeile der Ansicht „Verkauf“: günstigste 10 Angebote (C_AuctionHouse.SendSearchQuery), Preis (günstigster −1 Kupfer), Menge, Dauer, Einstellen (PostCommodity/PostItem). Nur im Spiel prüfbar, API-Annahmen: Commodity- und Item-Suchergebnisse |
| `AuctionBuy.lua` | Kauf-Panel (Markt/Trends/Übersicht-Listen): günstigste Angebote, Menge, Kosten über die Angebote, Kaufen in zwei Schritten (StartCommoditiesPurchase → Preis → ConfirmCommoditiesPurchase; Einzelgegenstände: PlaceBid mit Sofortkauf). Nur im Spiel prüfbar |
| `AuctionCraft.lua` | Herstellen-Panel (Klick auf ein Rezept in „Herstellen“): Materialien für n Herstellungen, was die gewählten Charaktere haben, was fehlt, Kosten, Kaufen-Knopf je Material (öffnet das Kauf-Panel mit der Fehlmenge). Erster Test |
| `AuctionShop.lua` | Einkaufsliste (Ansicht „shop“ des Auktionshaus-Reiters, eine Seite wie die Übersicht): Gegenstände mit Menge in `ns.db.ahShop`, `ns.AuctionShop.Add/Set/Remove/Clear`; Hinzufügen aus Kauf-Panel, Rezept-Panel und Zeilenmenü; Kaufen öffnet das Kauf-Panel |
| `AuctionOwn.lua` | Seite „Meine Auktionen“ des Auktionshaus-Reiters: im Angebot (alle Charaktere, aus Account.lua) und Verlauf (`ns.db.ahHistory`, von Account.lua beim Verschwinden einer Auktion vermerkt: verkauft/abgelaufen/abgebrochen); `O.Spent` vermerkt Käufe (`ns.db.ahSpent`) für die Übersicht |
| `ItemInfo.lua` | Rezepte-Fenster (`/fcrecipes`, `ns.ItemInfo.Home/Show(itemId)/Toggle`, Schlüssel `recipes`, 940×680, Skalier-Griff, Position in `ns.db.recipeWin`): Startseite = Berufe, Suche über alle Rezepte (Name, Beruf, Material), Berufs-Tabs, Zeilen (UI.NewListView mit `lv:Resize`), Detailfeld unten mit Materialkarten (Vorrat aller Charaktere, Kosten/Wert/Gewinn), Verlauf mit „<“. Stufen Orange/Gelb/Grün/Grau (Grün = Mitte Gelb–Grau); Orange = Lernstufe nur bekannt, wenn ein Rezept-Gegenstand das Rezept lehrt (`r[8]`). Quelle „Lehrer/Rezept“: `r[7]` = lehrender Gegenstand, `ns.db.trainerSpells` wird aus Lehrerfenstern gefüllt |
| `AuctionDashboard.lua` | Erste Seite des Reiters: Vermögen, sehenswerte Taschen-Gegenstände, Markt (günstig/steigend), lohnende Rezepte |
| `Data\Recipes.lua`, `Data\Disenchant.lua` | Erzeugt von `toolsuild_recipes.py` / `toolsuild_disenchant.py` (Quellen: wago.tools, DisenchantBuddy) |
| `Tooltip.lua` | Item- und Kreatur-Tooltips, Optionsliste `ns.TIP_OPTIONS` |
| `Widgets.lua` | Gemeinsame UI-Bausteine `ns.W` (Buttons, Platte, Griff zum Skalieren, `TopFrameIs`) |
| `Dropdown.lua` | Hover-Kontextmenü `W.NewDropdown` / `W.NewMenuButton` |
| `Data\MapOverlays.lua` | Kartendaten |
| `MapView.lua` | Kartenansicht, Marker (Teile, Badge), `ns.MapData` |
| `UI.lua`, `SessionHUD.lua` | Hauptfenster-Gerüst, Sitzungs-HUD („Kills & Loot“) |
| `Page*.lua` | Journal-Seiten (Quellen mit Suche über Namen **und Beute**, Gegenstandssuche, Verlauf, Statistik; die Seite „Beute“ ist entfernt) |
| `Routes.lua`, `Spots.lua` | Routen und Fundorte |
| `MapMain.lua`, `MapWindow.lua` | Kartenfenster (`/fcmap`), Mini-Karte (`/fcmini`) |
| `AccountWindow.lua` | Account-Fenster (`/fcaccount`, `/fcalts`), sehr groß |
| `SettingsWindow.lua` | Einstellungen (`/fcsettings`): Gruppen links (GROUPS) mit Zählbadge, Seiten aus Karten (Heading beginnt Karte), Suche über alle Optionen (virtuelle Seite `search`), `def` an Toggle/Choice = Standardwert für Badge und „Diese Seite zurücksetzen“ |
| `Minimap.lua` | Minimap-Knopf |
| `Media\` | Logo (`logo.tga` 256 px, `logo64.tga` für die Minimap, `logo.png` fürs README, mit Alpha), Konzeptbilder in `Media\concepts\` (Icons für später). Erzeugt mit `tools\make_addon_logo.py` und `tools\cut_concepts.py` aus den Konzeptblättern; `tools\make_logo.py` ist die erste selbstgezeichnete Idee (`Media\drawn*`) |
| `tools\` | Hilfsskripte außerhalb des Spiels (nicht im `.toc`) |

Alle Dateien teilen `local ADDON, ns = ...`. Es gibt keine globale API außer `ForeverCompanionDB` und den
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

- `ForeverCompanionDB` hat `DB_VERSION` (siehe `Core.lua`). `InitDB` übernimmt einmalig die Daten der alten
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
- Beutezug (früher Kills & Beute; englischer Schlüssel bleibt `L["Kills & Loot"]`, deutscher Name „Beutezug“): Tabs Regionboard und Route sind nicht mehr im Fenster (Code in `SessionHUD.lua` liegt brach). Die Route soll bei Bedarf als eigenes Fenster ausgegliedert werden.
- Auktionshaus-Seite (`panel` in AuctionTab.lua) kann im Auktionshaus-Reiter oder im eigenen Fenster (`/fcah`, `ns.AuctionWindow`, Fenster-Menü am runden Icon) liegen; `T.PlacePanel(host)` dockt sie um (Eltern, Ankerpunkte, Frame-Ebenen). Kaufen/Verkaufen/Preise prüfen brauchen das offene Auktionshaus.
- Vertagt: Live-Bearbeiten-Modus für Layout-Maße (Umbau SessionHUD), Schrift/Farben im Theme, gleiche Tabellenlayouts überall, Journal komplett neu gestalten.

## Arbeitsablauf mit Git/GitHub (Empfehlung)

**Eine Kopie, kein Doppelleben:** Das Repo liegt direkt im Addon-Ordner
(`...\AddOns\ForeverCompanion\`, dort `git init`). Der Ordner ist der Arbeitsstand, den das Spiel lädt. Mit
`/reload` testet man sofort, ohne zu kopieren oder zu verlinken. Der Ordnername muss `ForeverCompanion`
bleiben (gleich dem `.toc`-Namen, sonst lädt das Spiel das Addon nicht).

- **`main`** ist stabil. Entwickelt wird auf Zweigen (`feature/...`, `fix/...`) oder direkt auf einem
  `dev`-Zweig. Zurück auf `main` wechselt man erst, wenn es im Spiel getestet ist. Ein Zweigwechsel
  ändert die Dateien im Ordner, was das Spiel beim nächsten `/reload` lädt.
- **„Produktiv“ vs. „Testen“:** Wer mit einer stabilen Version spielen und gleichzeitig testen will, legt
  einen zweiten Ordner an: `git worktree add ..\ForeverCompanion_dev dev`. Dessen `.toc` müsste dann
  anders heißen, daher ist das nur für Gelegenheiten nötig. Im Normalfall: stabil = Tag, Test = Zweig.
- **Releases:** Version im `.toc` (`## Version:`) erhöhen, Tag `vX.Y.Z` setzen, ZIP bauen, dessen oberster
  Ordner `ForeverCompanion/` heißt. GitHubs automatisches „Source code (zip)“ hat den falschen Ordnernamen
  (`ForeverCompanion-main`). Dafür eine GitHub Action oder den BigWigs-Packager verwenden, der den
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

- **Fensterstil:** Es gibt nur noch den Blizzard-Stil (Stand 2026-11-22). Die Zweige `ornate`/`plain` in den `ApplyFrameStyle`-Funktionen sind per `false`/`true` fest verdrahtet und toter Code; die Option „Window style“ ist entfernt.
- **Tooltip-Einstellungen:** eigene Gruppe „Tooltips“ mit Seiten Allgemein/Gegenstände/Kreaturen; oben eine Vorschau (`ns.TipPreview` in Tooltip.lua, erfundene Beispieldaten, nutzt dieselben `ns.TipOn`-Schalter). Neue Tooltip-Zeile = in `ItemLines`/`MobLines` **und** in `SampleItemLines`/`SampleMobLines` eintragen.
- **Vorkommen-Tooltip:** `OnObject`/`NodeLines` in Tooltip.lua (Kräuter/Erz/Objekte, Quelle `ns.db.mobs["herb:Name"]`, nur bereits gesammelte); Optionen `nodeVisited/nodeGathered/nodeDrops`, Vorschau-Art `node`. Hook über `Enum.TooltipDataType.Object` bzw. Fallback `OnShow` — im Spiel noch nicht geprüft.
- **Kopfstreifen (Blizzard-Stil):** Journal (`UI.lua`: Seite ab AREA_TOP -24, **kein Kopfband und kein Minimieren-Knopf mehr**), Karte (`MapMain.lua` BAR_TOP -24/BAR_LEFT 56) und Account (`AccountWindow.lua` BAR_TOP -24) nutzen den Streifen unter der Titelleiste neben dem Ring; Inhalt beginnt direkt darunter.
- **Referenzdaten Auktionshaus:** `Data/AuctionSeed.lua` (erzeugt aus dem Konto des Autors, Realm CAMWOW EU4 Realm 3 PvE-Horde, Stand 2026-11-22, ca. 1,2 MB) wird beim ersten Start als Datenbestand des Spielers geladen (`Seed` in AuctionScan.lua, einmalig über `db.ahSeeded`), `store.seeded = true` bis zum ersten eigenen Scan (`AH.Seeded()`; der Tooltip-Hinweis „Besuche das Auktionshaus“ bleibt solange). Neu erzeugen: Skript im Scratchpad `seed.py` (liest ForeverCompanion.lua aus WTF).
- **Schnellleiste:** `QuickBar.lua` (`/fcbar`, `ns.QuickBar.Toggle`): kleine verschiebbare Knopfleiste für die Fenster; Linksklick auf das Minimap-Symbol öffnet sie, Umschalt+Links = Kills & Loot, Rechts = Einstellungen. Position/Ausrichtung/Sichtbarkeit in `ns.db.quickBar`. Neues Fenster = in `Windows()` eintragen.
- **Umbenennung (2026-11-22):** Aus „Forever Codex“ wurde „Forever Companion“. Neu: Ordner/`.toc` `ForeverCompanion`, SavedVariables `ForeverCompanionDB` (Datei `WTF\Account\<KONTO>\SavedVariables\ForeverCompanion.lua`; die alte `ForeverCodex.lua` ist nur noch eine Sicherung), Framenamen `ForeverCompanion*`, Slash-Namen `FOREVERCOMPANION*`, Chat-Präfix, Reiter im Auktionshaus „Companion“. Slash-Befehle `/fc…` bleiben (passt zu beiden Namen), `/companion` und `/codex` öffnen beide. Die Einstellung `ahOpenCodex` behielt ihren Namen (nur intern). Das Skript `..inish-rename.ps1` (im AddOns-Ordner, einmalig) benennt den Ordner um und wandelt die Daten neu um, sobald das Spiel beendet ist. GitHub: Repo auf github.com umbenennen, dann `git remote set-url origin https://github.com/immatoll/ForeverCompanion.git`.
- **Aufzeichnung pausiert (Dungeons/Gruppe):** In Dungeons/Schlachtzügen (und in Gruppen) liefert der Client Namen/GUIDs als „secret values“, die Beute landet dann bei „Unbekannt“. `RecordingPaused()` in Core.lua (Einstellungen `pauseInstances`/`pauseGroup`, beide standardmäßig an, Seite Kills & Loot) verwirft `RecordLoot`/`RecordMoney` dort und sagt es einmal im Chat. Ein echter Fix (Namen anders ermitteln) ist offen; vermutlich nur im Spiel mit `/fc debug` zu erarbeiten.
- **Dungeon-Befund (2026-11-23, Burg Shadowfang, `/fc probe`):** Name/GUID/Kreaturentyp eines Gegners (target, softenemy) sind SECRET; lesbar sind Stufe, Klassifizierung, tot/lebendig. Spielernamen sind lesbar. **Die Quelle im Beutefenster (`GetLootSourceInfo`) ist lesbar**: `Creature-0-<server>-<karte>-<instanz>-<npcID>-<spawn>` (z. B. npcID 3927, Karte 33). Offen: ob sich der Name über `C_TooltipInfo.GetHyperlink("unit:"..guid)` bzw. `SetHyperlink` an einem eigenen Tooltip lesen lässt (Test: `/fc probe` mit offenem Beutefenster **nach `/reload`**, siehe Zeilen „guid…/hyperlink data/tooltip by guid“). Falls nicht: unter der npcID buchen und den Namen später lernen (npcID→Name aus lesbaren Gegnern draußen), Anzeige „Kreatur <id> · <Zone>". Bis dahin pausiert `RecordingPaused()` in Dungeons/Gruppen.
- **Minimap-Pins (Spots.lua):** Pflanzen/Adern zeigen beim Darüberfahren den Vorkommen-Tooltip (`ns.TipNodeFor` in Tooltip.lua, Dots tragen `key`); Vorkommen in der Nähe funkeln (`DrawFx`: drehender Stern, Ringe, Halo; Einstellungen `mmGlow`, `mmGlowRange`, `mmGlowStyle`, `mmSparkleAll` auf der Seite Karte). Echte Leuchtfeuer in der 3D-Welt sind für Addons nicht möglich; offen: Spiel-Wegpunkt (`C_Map.SetUserWaypoint`/`C_SuperTrack`) und CVars für Funkeln/Umriss — Test über `/fc probe` (Abschnitte „waypoint“ und „settings of the game“).
- **Funkeln in der Welt (Stand 2026-11-23):** Das Minimap-Funkeln der Pins (`DrawFx`, `mmGlow*`) ist standardmäßig AUS und hat keine Einstellung mehr (Nutzer wollte es nicht). Stattdessen `WorldGlow.lua`: setzt die Spiel-CVars der Interaktions-Hervorhebung (SoftTargetInteract*, Icon, Reichweite) und stellt sie beim Ausschalten wieder her (`ns.db.cvarBackup`); Einstellung `worldGlow`/`worldGlowRange` auf der Seite Karte. Ob das das Funkeln wie bei Blackthorn Farmer ist, ist ungeprüft. Der Tooltip des Spiel-Blips auf der Minimap (Text nur, Name SECRET) wird um unsere Zeilen ergänzt, indem der bekannte Spot nächst der Maus gesucht wird (`NearestPinToMouse` in Spots.lua).
- **WorldGlow.lua (neu aufgebaut nach dem Vorbild von OneForAll/Lueur, 2026-11-23):** Funkeln/Lichtstrahl über Kräutern und Erz in der Welt über den „softinteract“-Namensplaketten des Spiels. Art (Kraut/Ader) über das Cursor-Symbol (`SetUnitCursorTexture`), nur mit Kräuter-/Erz-Aufspüren (Zauber 2383/8387, 2580/8388), die Plakette nur eingeschaltet, solange ein Kraut/eine Ader das Ziel ist. Setzt Spiel-CVars (Sicherung in `ns.db.cvarBackup`, Wiederherstellung beim Ausschalten). Einstellungen `worldGlow`, `worldGlowOnlyMine`, `worldGlowStyle`, `worldGlowDrop` (Seite Karte). Nicht zusammen mit dem Knotenfunkeln von OneForAll/Blackthornes Farmer laufen lassen. Im Spiel ungeprüft.
- **Leuchtfeuer entfernt (2026-11-23):** Der Spiel-Wegpunkt mit eigenem Lichtstrahl (Waypoint.lua, Media/beam.tga, Media/flare.tga) und der Strahl am Funkeln wurden wieder ausgebaut: Das Spiel zeichnet keinen Strahl, ein eigener hängt an `C_Navigation.GetFrame()` und springt mit der Spielerhöhe (der Client gibt keine Höhe heraus, `UnitPosition` liefert z = 0). Übrig ist das Funkeln über Kräutern/Erz (WorldGlow.lua), das die Interaktionstaste des Spiels automatisch einschaltet.
- **Kürschnern-Funkeln (WorldGlow.lua):** `SkinnableCorpse(unit)`: tote Kreatur, deren Tooltip (`C_TooltipInfo.GetUnit("softinteract")`) das Wort `UNIT_SKINNABLE_LEATHER` enthält; nur mit Kürschnerei (Zauber 8613/8617/8618/10768/32678, Fertigkeitsliste, Account-Daten); Einstellung `worldGlowSkin`. Wird bei `LOOT_CLOSED` neu ausgewertet. Die Namensplakette für das Interaktionsziel wird dafür auch bei Kadavern eingeschaltet. Im Spiel ungeprüft; Diagnose mit `/fc glow` (Zeile „skinnable corpse“).
- **Talente / Respec (Account):** `ScanTalents` in Account.lua liest die verteilten Punkte (`GetTalentTabInfo`); fallen sie, wird `rec.respecAt` gesetzt (nur durch Ereignisse `PLAYER_TALENT_UPDATE`/`CHARACTER_POINTS_CHANGED`, nicht in den ersten 15 s nach dem Login). Das Spiel nennt den Zeitpunkt eines Resets nicht; Resets vor dem Beobachten sind unbekannt („noch nicht gesehen“). Ansicht „Talente“ in der Account-Übersicht mit Filter auf den letzten Reset (`view.respecFilter`).
- **Talente über C_Traits (Stand 2026-11-23):** WoW Forever hat KEINE klassischen Talentfunktionen (`GetTalentInfo` usw. sind nil), sondern `C_ClassTalents`/`C_Traits` (Konfiguration `GetActiveConfigID`, ein Baum mit ~50 Knoten, Koordinaten `posX/posY` im Raster 600, `visibleEdges`, Eintrag→Definition→`spellID`). `ScanTalents` (Account.lua) speichert pro Charakter `rec.talents = { spent, unspent, tree, nodes = { id, x, y, rank, max, spell, tex, edges } }`; die Account-Seite zeichnet daraus in der Registerkarte „Talente“ den Baum (`DrawTree`: Raster ×0,1 skaliert, Linien zu `edges`, Rang, Tooltip per `SetSpellByID`). Oben/unten wird aus der Lage der Wurzelknoten (nichts führt zu ihnen) geraten, Knopf „Umdrehen“ korrigiert. Die drei Bäume sind drei Bänder nebeneinander (`TreePoints`). Im Spiel ungeprüft.
- **Talentbaum mit den Grafiken des Spiels:** Hintergründe `talents-background-<klasse>-<spezialisierung>` (1612x774, per `W.LayoutBg` im Modus „zoom“ je Baum zugeschnitten; Reihenfolge der Spezialisierungen je Klasse in `SPEC_ART`), Rahmen `talents-node-square-gray|yellow|green` (+ `-greenglow`), Rangplakette `orderhalltalents-rankborder[-yellow|-green]`, Pfeile `talents-arrow-head-yellow|gray`, Kopfring `talents-node-circle-yellow|gray`. Namen und Symbole der drei Bäume stehen in `rec.talents.specs` (aus `C_SpecializationInfo.GetSpecializationInfo(1..3)`, nur für den angemeldeten Charakter lesbar). Im Spiel ungeprüft.
- **Taschen-Verwalter (`Manager.lua`, `/fcbags`, erste Fassung, ungeprüft):** eigenes Fenster (Blizzard-Stil, Schlüssel `bags`) mit Reitern Händler / Post / Bank. Liest Taschen + Reagenzientasche (`C_Container`), je Gegenstand Händlerpreis (`ns.Value.Vendor`) gegen Auktionspreis nach Gebühr (`AuctionPrice` × 0,95); Urteil: Plunder (grau), Händler, Auktionshaus (ab `mgrAhGain` % mehr), oder eine Regel `ns.db.itemRules[id] = { kind = keep|mail|bank, target }`. Regeln per Klick auf eine Zeile (Menü am Mauszeiger), in den Einstellungen (Seite „Taschen“, Liste mit ×, „Alle Regeln entfernen“) änderbar. Aktionen: Verkaufen über `C_Container.UseContainerItem` (Zeitabstand 0,1 s), Plunder automatisch beim Öffnen eines Händlers (`mgrSellJunk`), „Alles ohne AH-Vorteil verkaufen“ (zweimal klicken, bis Qualität `mgrSellLimit`), Post: legt die Stapel (bis `ATTACHMENTS_MAX_SEND`) in einen Brief an den Zielcharakter, Bank: lagert ein. Öffnet sich mit Händler/Briefkasten/Bank (`mgrAutoOpen`). Inspiration: Blackthornes Butler (nur Idee, kein Code übernommen, dort „All Rights Reserved“). Später: echte Reiter an MerchantFrame/MailFrame statt eigenes Fenster.
- **Taschen-Verwalter, Ergänzung:** vierter Reiter „Regeln“ (Arten von Gegenständen + einzelne Regeln, auch für Gegenstände, die nicht in den Taschen sind). Regeln für **Arten** (`ns.db.catRules[id]`, Arten in `M.CATS`: Stoff, Leder, Kräuter, Erz, Edelsteine, Elementare, Verzauberungsmaterial, Teile, grün, blau+; erkannt über `GetItemInfoInstant` Klasse/Unterklasse bzw. Qualität). Die Regel eines einzelnen Gegenstands hat Vorrang (`RuleFor`); gebundene Gegenstände werden nie per Post-Regel einer Art erfasst. **Vorschläge:** `M.Suggest(cat)` nimmt den Charakter mit dem passenden Beruf (höchster Fertigkeitswert, nicht der aktuelle; Namen en/de in `PROF_NAMES`), „→ Name“ in der Zeile bzw. „Alle Vorschläge“. Einstellungen: Arten-Liste mit „Ändern“ (Menü `M.OpenCatMenu`), Einzelregel-Liste mit ×. Knopftexte kurz halten.
- **Rezepte-Daten (`Data/Recipes.lua`, 2026-11-24):** Zeilen `{ spell, item, min, gelb, grau, { Material, Menge ... }, lehrender Gegenstand, Lernstufe }`. `min` ist in der Datenquelle fast überall 1 (nicht verwendbar); der lehrende Gegenstand kommt aus ItemXItemEffect/ItemEffect/Item (Klasse 9), die Lernstufe aus ItemSparse.RequiredSkillRank. Lehrer-Listen gibt es in der Quelle nicht.
- **Taschen-Regeln (Stand 2026-11-24):** Regeln gelten standardmäßig nur für den aktuellen Charakter (`ns.db.charRules[charKey].items/.cats`, mit `char = true`), umstellbar auf „alle Charaktere“ (`ns.db.itemRules`, `catRules`); die Regel des Charakters geht vor. Art „Händler“ (`vendor`) wird mit „Müll verkaufen“ mitverkauft. Reiter „Regeln“ ohne Preise, mit Suche und Filter; „Alle Regeln löschen“ mit Warnung. Im Auktionshaus-Verkauf schaltet „Geplant“ (`ahPlanned`) auf `M.AuctionSet()` (Regel „Auktion“ oder Vorschlag) um, nur mit eigenem Charakter gewählt.
- **Menüs und Fenster (2026-11-24):** Alle `W.NewDropdown` liegen in der Ebene FULLSCREEN_DIALOG; solange ein Menü offen ist, werden fremde Tooltips unterdrückt. Knöpfe holen ihr Fenster per `W.RaiseWindow` nach vorn. Die Skalier-Griffe (`W.AttachScaleGrip`) haben `topInset` (Höhe des Rahmens über dem Fensterrand, Blizzard-Stil 54), damit die sichtbare Ecke stehen bleibt.
- **Gruppen und Dungeon (2026-11-24):** `pauseInstances` Standard an, `pauseGroup` Standard aus; in einer Gruppe zählt Geld als Anteil aus `CHAT_MSG_MONEY` (`ns.OnChatMoney`). Beutezug-Fenster öffnet sich nur mit `autoOpenSession == true`.
- **Weltkarte (2026-11-24, ungeprüft):** `WorldMapMarkers.lua` zeichnet die Beutekarten-Markierungen (`ns.MapData`, gleicher Filter wie Minimap/Beutekarte) auf die Spielkarte und setzt rechts oben eine Knopfspalte (Menü, Deckkraft, Größe). Menü: Weltkarte/Minimap ein-aus, je Gruppe ein Haken plus „Einzelne wählen“ (Quellen der Zone). Neue Filter-Schalter `ns.MapWorldOn/SetWorld`; Markergröße `ns.MapSize()` (50/100/150 %, `settings.markerSize`) gilt für Beutekarte, Weltkarte und Minimap. Der alte Pin-Overlay (`Spots.RefreshMap`, vom Nutzer angeheftete Orte) bleibt daneben.
