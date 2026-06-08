# EllesmereUI-MoP — Repo- & Release-Setup (Phase 10)

Dieses Dokument beschreibt die Repo-Struktur, das Branch-Modell und den
Release-Workflow (privat **und** öffentlich via CurseForge/WoWInterface/Wago)
über **GitHub Desktop**.

---

## 1. Repo-Struktur (Flat-Layout)

Alle 17 Addon-Ordner liegen direkt im Repo-Root — identisch zum Install-Layout,
ideal zum Entwickeln/Testen:

```
<repo-root>/
  EllesmereUI-MoP/                 (Core)
  EllesmereUIActionBars/
  EllesmereUIAuraBuffReminders/
  … (alle weiteren Modulordner) …
  EllesmereUIUnitFrames/
  .pkgmeta                         <- Packaging-Konfiguration
  .github/workflows/release.yml    <- Auto-Build/Upload bei Tag
  .gitignore
  README.md
  CHANGELOG.md
  REPO-SETUP.md                    (diese Datei)
```

Die mitgelieferte `.pkgmeta` hebt per `move-folders` jeden der 17 Ordner aus dem
Paket-Wrapper auf die Zip-Root-Ebene — das fertige Release-Zip enthält die
Ordner also wieder nebeneinander (so wie sie installiert werden). Du musst hier
nichts umbauen.

> Wenn du später Ordner hinzufügst/umbenennst: den entsprechenden Eintrag in
> `move-folders` mitpflegen.

---

## 2. TOC-Anpassungen für die Distribution (im Snapshot bereits erledigt)

Im gelieferten Repo-Ready-Snapshot ist beides schon gesetzt — hier nur zur
Erklärung:

**a) Version per Keyword** — alle `*.toc` haben statt einer festen Versionszeile:

```
## Version: @project-version@
```

Der Packager stempelt beim Tag automatisch die Tag-Version (z. B. `1.0.0`)
hinein. (Meine Dev-Builds behalten weiter eine feste Version — das ist normal:
die Quelle nutzt das Keyword, das ausgelieferte Zip die echte Version.)

**b) Projekt-IDs** — in der **Core**-TOC `EllesmereUI-MoP/EllesmereUI-MoP.toc`
(der Packager nimmt die IDs aus der `package-as`-TOC):

```
## X-Curse-Project-ID: 1567415
```

WoWInterface/Wago sind (noch) nicht hinterlegt — die Uploads dorthin werden
einfach übersprungen. Sobald du dort Projekte hast, die jeweilige Zeile
(`## X-WoWI-ID:` / `## X-Wago-ID:`) in die Core-TOC ergänzen.

---

## 3. Secrets (einmalig, GitHub-Web)

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Token-Quelle |
|---|---|
| `CF_API_KEY` | https://legacy.curseforge.com/account/api-tokens |
| `WOWI_API_TOKEN` | WoWInterface → Account → API Tokens |
| `WAGO_API_TOKEN` | https://addons.wago.io/account/apikeys |

`GITHUB_TOKEN` wird automatisch bereitgestellt. Zusätzlich einmalig prüfen:
**Settings → Actions → General → Workflow permissions → „Read and write
permissions"** aktivieren (sonst kann die Action kein GitHub-Release anlegen).

Nur die Plattformen, für die ein Secret gesetzt ist, werden beliefert — rein
privates Arbeiten ohne Secrets ist also auch möglich (dann nur GitHub-Release).

---

## 4. Branch-Modell

- **`main`** — veröffentlichter, stabiler Stand. Hier wird getaggt/released.
- **`dev`** — laufende Arbeit/Integration. Hierhin committe ich gelieferte Builds.
- *(optional)* Feature-Branches → in `dev` mergen.

Release = `dev` → `main` mergen, dann auf `main` taggen.

---

## 5. Workflow in GitHub Desktop

**Laufende Arbeit:**
1. Branch `dev` auswählen (Current Branch → dev).
2. Neue/aktualisierte Dateien ins lokale Repo kopieren (z. B. die gelieferten
   Modulordner überschreiben).
3. Unten Commit-Message eingeben → **Commit to dev** → **Push origin**.

**Release ausliefern:**
1. Current Branch → **main**, dann **Branch → Merge into current branch → dev**.
2. **Push origin**.
3. Tag setzen: Reiter **History** → Rechtsklick auf den obersten Commit →
   **Create Tag…** → Name = Version, z. B. `mop.29` (oder `8.0.3-mop.29`).
4. **Push origin** (Desktop fragt, ob der Tag mit gepusht wird → ja).

Sobald der Tag auf GitHub ankommt, läuft die Action: sie baut das Zip
(via `.pkgmeta`), erstellt ein **GitHub-Release** und lädt — falls Secrets
gesetzt — zu CurseForge/WoWInterface/Wago hoch.

> Hinweis: Wird der allererste Workflow zusammen mit dem ersten Tag gepusht,
> triggert er noch nicht. Dann einfach einen zweiten Tag pushen.

Alternativ ganz ohne Desktop-Tagging: auf GitHub **Releases → Draft a new
release → Choose a tag → neuen Tag tippen → Publish** — das erzeugt den Tag und
triggert dieselbe Action.

---

## 6. Versionsschema (SemVer)

Tags folgen **`MAJOR.MINOR.PATCH`**:
- **MAJOR** (`1`.x.x) — Hauptversion: große, ggf. inkompatible Umbauten.
- **MINOR** (x.`1`.x) — Featureversion: neue Features oder große Rewrites.
- **PATCH** (x.x.`1`) — Bugfix-Version.

Erstes Release = **`1.0.0`**. Beispiele: Bugfix → `1.0.1`, neues Feature/Rewrite
→ `1.1.0`, Major → `2.0.0`. `@project-version@` übernimmt exakt den Tag-Namen,
d. h. Tag `1.0.0` ⇒ in der TOC steht `1.0.0`. `CHANGELOG.md` pro Release um
einen Abschnitt ergänzen.

---

## 7. Lokal testen ohne Release (optional)

Zum Entwickeln brauchst du den Packager nicht — du installierst weiter die
gelieferten Dev-Zips. Wer dennoch lokal paketieren will: das Repo nach
`Interface\AddOns\` spiegeln (Symlink/Copy) genügt, da das Repo bereits im
Install-Layout vorliegt. Die `@project-version@`-Zeile zeigt dann roh im
Client — das ist nur kosmetisch und im echten Release korrekt gestempelt.
