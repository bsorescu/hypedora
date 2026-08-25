#!/bin/bash
# L1 (hypedora): wrapper-ul `~/.local/bin/brave` din overlay răspunde el însuși
# sondei `--help` a lui omarchy-launch-browser, în loc s-o paseze browserului.
#
# De ce contează: launcher-ul face `$browser_exec --help 2>/dev/null | grep -q MOZ_LOG`
# ca să detecteze Firefox. Un Chromium nu tipărește help — face
# `execlp("man", "man", "brave")`; în sandbox-ul flatpak `man` nu există, deci
# execlp dă ENOENT și Chromium moare în PLOG(FATAL) → SIGTRAP → core dump la
# fiecare lansare de browser.
#
# Testul nu pornește niciodată nimic: calea „fără --help" e verificată static, iar
# calea cu guard e verificată prin xtrace (dovedim că `exec` nu e atins).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
. "$ROOT/test/helpers.sh"

WRAPPER="$ROOT/hypedora/overlay/.local/bin/brave"
DESKTOP="$ROOT/hypedora/overlay/.local/share/applications/com.brave.Browser.desktop"

assert_file_exists "wrapper-ul există în overlay" "$WRAPPER"
assert_file_exists ".desktop-ul există în overlay" "$DESKTOP"

# post-install copiază cu `cp -a`, deci bitul de execuție din repo e cel livrat.
[[ -x $WRAPPER ]] && pass "wrapper-ul e executabil în repo" || fail "wrapper-ul e executabil în repo"

# 1) Guard-ul: ieșire 0, pe toate formele de help acceptate de Chromium (kHelp/kHelpShort),
#    inclusiv când `--help` nu e singurul argument.
assert_exit_code "--help iese cu 0" 0 bash "$WRAPPER" --help
assert_exit_code "-h iese cu 0" 0 bash "$WRAPPER" -h
assert_exit_code "--help alături de alte argumente iese tot cu 0" 0 \
  bash "$WRAPPER" --incognito --help https://example.invalid

# 2) Nimic pe stdout: launcher-ul face grep pe stdout, deci orice zgomot de acolo
#    ar putea (teoretic) să conțină MOZ_LOG și să comute pe --private-window.
out=$(bash "$WRAPPER" --help 2>/dev/null)
assert_equals "guard-ul nu tipărește nimic pe stdout" "$out" ""

# 3) Contractul real cu omarchy-launch-browser: sonda NU se potrivește, deci
#    launcher-ul cade pe ramura --incognito (corectă pentru Brave).
probe_matches_firefox() { bash "$WRAPPER" --help 2>/dev/null | grep -q MOZ_LOG; }
assert_exit_code "sonda MOZ_LOG nu se potrivește → ramura --incognito" 1 probe_matches_firefox

# 4) Dovada că browserul nu e pornit: sub xtrace, linia de `exec` nu e atinsă.
trace=$(bash -x "$WRAPPER" --help 2>&1 >/dev/null || true)
assert_output_lacks "guard-ul iese înainte de exec (nu se pornește flatpak)" "$trace" "flatpak run"

# 5) Calea normală rămâne delegare curată către flatpak, cu argumentele pasate
#    mai departe (verificat static — a rula asta chiar ar deschide browserul).
exec_line=$(grep -n '^exec ' "$WRAPPER" | head -1 | cut -d: -f2-)
assert_output_contains "delegă către flatpak com.brave.Browser" "$exec_line" \
  '/usr/bin/flatpak run --branch=stable --command=brave com.brave.Browser'
assert_output_contains "pasează argumentele mai departe" "$exec_line" '"$@"'

# 6) .desktop-ul: omarchy-launch-browser ia PRIMUL cuvânt din Exec= și îl rulează.
#    Reproducem exact expresia lui (bin/omarchy-launch-browser).
browser_exec=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$DESKTOP" | head -1)
assert_equals "primul cuvânt din Exec= e un executabil unic, nu „flatpak\"" "$browser_exec" "brave"
assert_equals "basename-ul folosit la focus rămâne „brave\"" "$(basename "$browser_exec" -stable)" "brave"

# 7) Overlay-ul e per-user: nicio cale absolută de home nu are ce căuta în repo.
assert_exit_code ".desktop-ul nu hardcodează /home/<user>" 1 grep -q "/home/" "$DESKTOP"
assert_exit_code "wrapper-ul nu hardcodează /home/<user>" 1 grep -q "/home/" "$WRAPPER"

# 8) Toate cele 4 intrări Exec (fereastră, new-window, private, tor) trec prin wrapper.
mapfile -t execs < <(grep '^Exec=' "$DESKTOP")
assert_equals "toate intrările Exec= sunt prezente" "${#execs[@]}" "4"
for e in "${execs[@]}"; do
  assert_output_contains "Exec= trece prin wrapper: $e" "$e" "Exec=brave"
done
