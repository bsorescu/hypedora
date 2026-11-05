#!/bin/bash
# L1 (hypedora): pipeline-ul L4-VM pe linia Omedora 4 — gărzi pe fix-urile upstream (port v4, sudo,
# helpers, boot id) + levierele din PR #4 (grafică/video, geometry-skip, SETUP_FROM_REPO, profile.d).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
VM="$ROOT/omedora/test/fedora/vm"

for f in run-vm-test.sh in-vm/assert-install.sh in-vm/run-suite-in-session.sh; do
  bash -n "$VM/$f" && pass "bash -n $f" || fail "bash -n $f"
done

src=$(cat "$VM/run-vm-test.sh")
assert_output_contains "install stage rulează omedora/install-4.sh" "$src" "omedora/install-4.sh"
assert_output_lacks   "install stage nu mai rulează install.sh de la rădăcină" "$src" 'omarchy/install.sh 2>&1'
assert_output_contains "install stage trece OMEDORA_PLAN_AUTOCONFIRM=1" "$src" "OMEDORA_PLAN_AUTOCONFIRM=1"
# sudo -v sub PTY: upstream îl dezamorsează cu un drop-in sudoers !authenticate (beta.5),
# în locul variantei noastre fără PTY — păzim soluția lor.
assert_output_contains "install stage: sudo nu cere parolă (drop-in !authenticate)" "$src" '!authenticate'
assert_output_contains "grafica e parametrizabilă (OMEDORA_VM_GRAPHICS)" "$src" 'OMEDORA_VM_GRAPHICS'
assert_output_contains "video e parametrizabil (OMEDORA_VM_VIDEO)" "$src" 'OMEDORA_VM_VIDEO'
assert_output_contains "geometry-skip e transmis în VM" "$src" 'OMEDORA_VM_GEOMETRY_SKIP'
assert_output_contains "seam-ul SETUP_FROM_REPO e transmis în VM" "$src" 'OMEDORA_SETUP_FROM_REPO'

asrt=$(cat "$VM/in-vm/assert-install.sh")
assert_output_lacks   "assert-install nu mai cere hyprland-omedora ca keystone" "$asrt" 'rpm -q hyprland-omedora'
assert_output_contains "assert-install cere omedora-settings" "$asrt" 'omedora-settings'
assert_output_contains "assert-install acceptă sourcing-ul v4 (profile.d)" "$asrt" '/etc/profile.d/omarchy.sh'

assert_output_contains "reboot-ul de sesiune e detectat prin boot id" "$src" 'boot_id'

suite=$(cat "$VM/in-vm/run-suite-in-session.sh")
assert_output_contains "SCREENSHOT_GEOMETRY_SKIP e configurabil" "$suite" 'SCREENSHOT_GEOMETRY_SKIP="${SCREENSHOT_GEOMETRY_SKIP:-1}"'
assert_output_contains "suita primește TAP helpers (upstream, beta.5)" "$src" 'test/helpers.sh'

grep -qxF 'omedora/test/fedora/vm/run-vm-test.sh' "$ROOT/hypedora/upstream-patches.txt" \
  && pass "run-vm-test.sh e în upstream-patches.txt" || fail "run-vm-test.sh e în upstream-patches.txt"
