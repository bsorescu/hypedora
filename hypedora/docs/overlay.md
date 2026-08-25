# Overlay (`hypedora/overlay/`)

Fișierele de aici sunt copiate de `hypedora/post-install.sh` (cu backup
`.pre-hypedora-<timestamp>` dacă exista deja altceva pe acel drum). Sunt mecanisme
de user ale Omarchy — nimic din payload-ul RPM (`/usr/share/omarchy/**`) și niciun
binar upstream nu e modificat.

**Destinația** se alege după primul segment al căii relative din `overlay/`:

| Cale în `overlay/` | Ajunge în |
|---|---|
| `.local/share/…` | `$XDG_DATA_HOME` (implicit `~/.local/share`) |
| `.local/…` | `~/.local` |
| orice altceva | `$XDG_CONFIG_HOME` (implicit `~/.config`) |

Ultima linie e comportamentul istoric, neschimbat: `omarchy/hooks/…` ajunge tot în
`~/.config/omarchy/hooks/…`.

## `omarchy/hooks/theme-set.d/30-all-backgrounds`

**Ce face:** toate background-urile, pe orice temă. La fiecare schimbare de temă,
`omarchy-theme-set` rulează `omarchy-hook theme-set <temă>`; hook-ul umple
`~/.config/omarchy/backgrounds/<temă>/` cu background-urile **tuturor** temelor
instalate (stock din `/usr/share/omarchy/themes/` + temele tale din
`~/.config/omarchy/themes/`). Directorul ăla e citit oricum de `omarchy-theme-set`,
`omarchy-theme-bg-next` și `omarchy-theme-bg-switcher`, alături de `backgrounds/`
al temei curente — deci `omarchy theme bg next` ciclează prin toate, iar
switcher-ul (Super+Space → Style → Background) le arată pe toate.

Convenții:

- background-urile **altor** teme primesc prefixul `zz-<temă-sursă>-`. Nume unice
  (fiecare temă are un `omarchy.png`) și etichete lizibile în switcher.
- background-urile **temei curente** sunt copiate cu numele lor real. Sortarea din
  `choose_theme_background` (`bin/omarchy-theme-set`) e globală peste ambele
  directoare, iar `~/.config/omarchy/backgrounds/<temă>/` vine înaintea
  directorului temei — fără copiile astea, orice schimbare de temă ar alege un
  background străin. Selectorul de imagini deduplică după numele fișierului, deci
  în UI apar o singură dată.
- `~/.config/omarchy/backgrounds/<temă>/.hypedora-all-backgrounds` e evidența a
  ce a pus hook-ul. Ce nu e în listă e al tău și nu se atinge: un fișier propriu
  cu același nume nu e suprascris, iar unul cu nume asemănător nu e șters. Când o
  temă e dezinstalată (sau un background redenumit), doar intrările noastre dispar.

**Copii, nu symlink-uri.** `omarchy-theme-bg-set` stochează `realpath` al imaginii
în `~/.local/state/omarchy/current/background`, iar `omarchy-theme-bg-next` caută
exact acel șir printre căile date de `find`. Un symlink s-ar rezolva la
`/usr/share/omarchy/...`, care nu e în listă → index `-1` la fiecare apăsare și
`bg next` rămâne blocat pe prima imagine (verificat pe hardware, 2026-08-23). Pe
btrfs — implicit pe Fedora — `cp --reflink=auto` e copiere fără cost de spațiu
(92 de imagini, ~108 MB aparent, în 0,14 s). Pe un fs fără CoW se copiază efectiv,
~100 MB per temă vizitată.

**Comportament cunoscut, neremediat intenționat:** `omarchy-theme-set` alege
background-ul temei noi *înainte* de a rula hook-urile. La prima trecere pe o temă
nouă, alegerea se face deci pe conținutul de dinainte — vezi un background al
temei, ca în Omarchy nemodificat; abia de la a doua schimbare pe acea temă
directorul e complet. Nimic de reparat aici fără a patch-ui upstream.

**Prima rulare** (post-install nu schimbă tema, deci hook-ul nu s-a declanșat încă):

```bash
bash ~/.config/omarchy/hooks/theme-set.d/30-all-backgrounds   # implicit: tema curentă
```

**Dezactivare:**

```bash
rm ~/.config/omarchy/hooks/theme-set.d/30-all-backgrounds
# și, pentru fiecare temă atinsă, copiile puse de hook:
cd ~/.config/omarchy/backgrounds/<temă> && xargs -a .hypedora-all-backgrounds rm -f && rm .hypedora-all-backgrounds
```

`omarchy theme bg next` și switcher-ul revin la comportamentul standard (doar tema
curentă) fără alți pași.

**Test:** `bash test/hypedora-all-backgrounds-test.sh` (L1, TAP, HOME temporar +
teme false prin `OMARCHY_THEMES_DIR`).

## `.local/bin/brave` + `.local/share/applications/com.brave.Browser.desktop`

**Ce fac:** rutează Brave-ul flatpak prin `~/.local/bin/brave` și opresc un core
dump la fiecare lansare de browser.

Două probleme, un singur wrapper:

1. **`omarchy-launch-browser` are nevoie de un executabil unic.** El extrage doar
   primul cuvânt din `Exec=` (`sed -n 's/^Exec=\([^ ]*\).*/\1/p'`), deci
   `Exec=/usr/bin/flatpak run … com.brave.Browser` s-ar reduce la `/usr/bin/flatpak`
   — lansat fără niciun argument. De aici `.desktop`-ul propriu, cu `Exec=brave`.
2. **Sonda `--help` omoară orice Chromium în flatpak.** Ca să detecteze Firefox,
   launcher-ul rulează `$browser_exec --help 2>/dev/null | grep -q MOZ_LOG`. Un
   browser Chromium nu tipărește help: face `execlp("man", "man", "brave", NULL)`.
   În sandbox-ul flatpak `PATH=/app/bin:/usr/bin` și `man` nu există → ENOENT →
   `PLOG(FATAL)` în `chrome/app/chrome_main_delegate.cc` → `base::ImmediateCrash()`
   → `int3` → **SIGTRAP + core dump la fiecare lansare de browser**. Stderr-ul
   sondei e `/dev/null`, deci singurul simptom vizibil e notificarea de crash.

Wrapper-ul răspunde el însuși sondei: ieșire 0, nimic pe stdout. Fără `MOZ_LOG`,
launcher-ul cade pe ramura `--incognito` — exact flag-ul corect pentru Brave, deci
comportamentul rămâne cel dinainte, minus crash-ul. Guard-ul prinde `--help` și
`-h` (ambele forme pe care Chromium le tratează ca help), oriunde în argumente.

**`Exec=brave`, nu o cale absolută.** Overlay-ul e per-user, deci nu poate hardcoda
`/home/<user>`. `~/.local/bin` e în PATH-ul managerului systemd `--user` (verificat:
`systemctl --user show-environment`), iar launcher-ul face `systemd-run … uwsm-app -- brave`
— se rezolvă corect. `basename` rămâne `brave`, deci `omarchy-hyprland-focus-app`
primește același regex ca înainte.

**Ce NU rezolvă:** cauza din amonte. `omarchy-launch-browser` și `omarchy-launch-webapp`
tot nu scanează `/var/lib/flatpak/exports/share/applications` — de aceea `.desktop`-ul
trebuie să existe în `~/.local/share/applications`. Raportat la
[AndrewGaspar/omedora#5](https://github.com/AndrewGaspar/omedora/issues/5).

**Verificare pe hardware** (2026-08-25, `thinky`): înainte, patru dump-uri identice
`SIGTRAP /app/brave/brave` (24–25 aug), toate cu `--help` în linia de comandă. După:
`omarchy-launch-browser` → `RC=0`, Brave pornit, `coredumpctl` neschimbat.

**Test:** `bash test/hypedora-brave-help-guard-test.sh` (L1, TAP, 20 de aserțiuni).
Testul nu pornește niciodată browserul: calea de delegare e verificată static, iar
guard-ul prin `bash -x` (dovedim că `exec` nu e atins).
