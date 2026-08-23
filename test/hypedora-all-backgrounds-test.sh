#!/bin/bash
# L1 (hypedora): hook-ul theme-set.d/30-all-backgrounds face disponibile
# background-urile TUTUROR temelor în ~/.config/omarchy/backgrounds/<temă>/ —
# prefixate cu tema sursă, idempotent, curățând ce nu mai există, fără să atingă
# fișierele userului. HOME temporar + /usr/share/omarchy/themes fals (OMARCHY_THEMES_DIR).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
. "$ROOT/test/helpers.sh"

assert_ok() { # descriere + comandă care trebuie să reușească
  local description=$1
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}

HOOK="$ROOT/hypedora/overlay/omarchy/hooks/theme-set.d/30-all-backgrounds"
assert_file_exists "hook-ul există în overlay" "$HOOK"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
HOME_T="$TMP/home"; THEMES="$TMP/themes"
mkdir -p "$HOME_T/.local/state/omarchy/current"

# Teme de sistem false: nord (tema curentă), catppuccin, tokyo-night.
# „omarchy.png" există în toate — exact cazul în care numele nu sunt unice.
for t in nord catppuccin tokyo-night; do
  mkdir -p "$THEMES/$t/backgrounds"
  printf '%s wallpaper\n' "$t" > "$THEMES/$t/backgrounds/1-$t.png"
  printf '%s omarchy\n' "$t" > "$THEMES/$t/backgrounds/omarchy.png"
done
printf 'nu sunt imagine\n' > "$THEMES/nord/backgrounds/not-an-image.txt"

# Temă de user (~/.config/omarchy/themes) — trebuie tratată la fel.
mkdir -p "$HOME_T/.config/omarchy/themes/mine/backgrounds"
printf 'mine\n' > "$HOME_T/.config/omarchy/themes/mine/backgrounds/1-mine.jpg"

DEST="$HOME_T/.config/omarchy/backgrounds/nord"
run_hook() { env HOME="$HOME_T" XDG_CONFIG_HOME= OMARCHY_THEMES_DIR="$THEMES" bash "$HOOK" "$@"; }

# 1) background-urile temelor străine, prefixate cu tema sursă
run_hook nord
assert_file_exists "background străin, prefixat cu tema sursă" "$DEST/zz-catppuccin-1-catppuccin.png"
assert_file_exists "„omarchy.png\" din fiecare temă capătă nume distinct" "$DEST/zz-tokyo-night-omarchy.png"
assert_file_exists "și temele de user sunt incluse" "$DEST/zz-mine-1-mine.jpg"
assert_equals "conținutul e cel din tema sursă" \
  "$(cat "$DEST/zz-catppuccin-1-catppuccin.png")" "catppuccin wallpaper"

# 2) fișiere reale, nu symlink-uri: omarchy-theme-bg-set stochează realpath, iar
#    omarchy-theme-bg-next caută acel șir printre căile din director — un symlink
#    ar ieși din ciclu (s-ar rezolva la /usr/share/omarchy/...) și „bg next" ar
#    rămâne blocat pe prima imagine.
assert_ok "intrările sunt fișiere reale" test -f "$DEST/zz-catppuccin-1-catppuccin.png"
assert_ok "intrările nu sunt symlink-uri" test ! -L "$DEST/zz-catppuccin-1-catppuccin.png"

# 3) background-urile temei curente rămân primele în sortarea globală: apar în
#    $DEST cu numele lor real (fără prefix), deci înaintea celor „zz-".
assert_file_exists "background-ul propriu al temei, neprefixat" "$DEST/1-nord.png"
assert_ok "tema curentă nu se auto-prefixează" test ! -e "$DEST/zz-nord-1-nord.png"
first=$(find -L "$DEST" -maxdepth 1 -type f -name '*.png' -print0 | sort -z | tr '\0' '\n' | head -1)
assert_equals "primul în ordine e un background al temei curente" "$(basename "$first")" "1-nord.png"

# 4) doar imagini
assert_ok "fișierele non-imagine nu sunt prefixate în DEST" test ! -e "$DEST/zz-nord-not-an-image.txt"
assert_ok "fișierele non-imagine nu sunt copiate în DEST" test ! -e "$DEST/not-an-image.txt"

# 5) manifest: evidența a ce am pus noi (fără extensie de imagine, deci Omarchy îl ignoră)
assert_file_exists "manifestul există" "$DEST/.hypedora-all-backgrounds"
assert_ok "manifestul listează intrările noastre" \
  grep -qxF "zz-catppuccin-1-catppuccin.png" "$DEST/.hypedora-all-backgrounds"

# 6) idempotent: a doua rulare nu duplică și nu rescrie nimic
before=$(find "$DEST" -mindepth 1 -printf '%P %s %T@\n' | sort)
run_hook nord
after=$(find "$DEST" -mindepth 1 -printf '%P %s %T@\n' | sort)
assert_equals "a doua rulare lasă directorul neschimbat" "$after" "$before"

# 7) o temă dezinstalată → copiile ei dispar, restul rămân
rm -rf "$THEMES/tokyo-night"
run_hook nord
assert_ok "copiile temei dezinstalate sunt șterse" test ! -e "$DEST/zz-tokyo-night-omarchy.png"
assert_file_exists "restul copiilor rămân" "$DEST/zz-catppuccin-omarchy.png"
manifest_lacks_tokyo() { ! grep -q '^zz-tokyo-night-' "$DEST/.hypedora-all-backgrounds"; }
assert_ok "manifestul nu mai listează tema dezinstalată" manifest_lacks_tokyo

# 8) fișierele userului din același director: nici clobber-uite, nici șterse
printf 'al meu\n' > "$DEST/1-nord.png"          # același nume ca un background al temei
printf 'poza mea\n' > "$DEST/zz-ceva-al-meu.png" # nume care seamănă cu al nostru, dar nu e în manifest
run_hook nord
assert_equals "fișierul userului cu nume identic nu e suprascris" "$(cat "$DEST/1-nord.png")" "al meu"
assert_file_exists "fișierul userului cu nume asemănător nu e șters" "$DEST/zz-ceva-al-meu.png"

# 9) numele temei e normalizat ca în omarchy-theme-set; fără argument ia tema curentă
run_hook "Tokyo Night"
assert_file_exists "„Tokyo Night\" → tokyo-night" \
  "$HOME_T/.config/omarchy/backgrounds/tokyo-night/zz-catppuccin-omarchy.png"
printf 'catppuccin\n' > "$HOME_T/.local/state/omarchy/current/theme.name"
run_hook
assert_file_exists "fără argument folosește tema curentă" \
  "$HOME_T/.config/omarchy/backgrounds/catppuccin/zz-nord-omarchy.png"

# 10) fără teme de sistem: nu explodează
assert_exit_code "rulează fără erori și când directorul de teme lipsește" 0 \
  env HOME="$HOME_T" XDG_CONFIG_HOME= OMARCHY_THEMES_DIR="$TMP/inexistent" bash "$HOOK" nord
