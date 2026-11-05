#!/bin/bash
# L1 (hypedora, gardă de regresie; fix-ul e upstream de la beta.3/beta.5): system.sh apelează omarchy-apply-system — numele nou
# de după „Move install-time plumbing out of the setup namespace" (536fcd5c);
# vechiul omarchy-setup-system nu mai există nici în RPM, nici în bin/ → exit 127.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
SYS="$ROOT/omedora/install/system.sh"

bash -n "$SYS" && pass "bash -n system.sh" || fail "bash -n system.sh"

src=$(cat "$SYS")
assert_output_contains "system.sh apelează omarchy-apply-system" "$src" 'omarchy-apply-system'
assert_output_lacks   "system.sh nu mai apelează omarchy-setup-system" "$src" 'omarchy-setup-system'

[[ -x "$ROOT/bin/omarchy-apply-system" ]] \
  && pass "bin/omarchy-apply-system există în repo (seam-ul FROM_REPO funcționează)" \
  || fail "bin/omarchy-apply-system există în repo (seam-ul FROM_REPO funcționează)"


# snapper e mapat source="skip" pe Fedora (fedora.toml) dar scriptul nu era gated →
# `snapper: command not found` (127) omora tot apply-ul pe un Workstation stock.
snap=$(cat "$ROOT/install/config/snapper.sh")
assert_output_contains "snapper.sh are gate-ul de Fedora" "$snap" 'omarchy-distro'
bash -n "$ROOT/install/config/snapper.sh" && pass "bash -n snapper.sh" || fail "bash -n snapper.sh"
