# Overlay (`hypedora/overlay/`)

Fișierele de aici sunt copiate în `~/.config/` de `hypedora/post-install.sh`
(cu backup `.pre-hypedora-<timestamp>` dacă exista deja altceva pe acel drum).
Sunt mecanisme de user ale Omarchy — nimic din payload-ul RPM
(`/usr/share/omarchy/**`) și niciun binar upstream nu e modificat.

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
