#!/bin/bash
# ============================================================================
# Full revert of the screen-extend (Deskflow) setup - 2026-09-04
# Undoes every change made on BOTH machines. Safe to run more than once.
#   ./REVERT.sh          show what would be removed (dry run)
#   ./REVERT.sh --apply  actually remove it
# ============================================================================
LAPTOP="mirr@192.168.0.114"
APPLY=0; [ "$1" = "--apply" ] && APPLY=1
run() { if [ $APPLY -eq 1 ]; then eval "$1"; else echo "  would run: $1"; fi; }
rrun() { if [ $APPLY -eq 1 ]; then ssh -o BatchMode=yes $LAPTOP "$1"; else echo "  would run (laptop): $1"; fi; }

[ $APPLY -eq 0 ] && echo "*** DRY RUN - nothing will change. Use --apply to execute. ***"

echo; echo "=== 1. Stop the link ==="
run "pkill -x deskflow-core"
rrun "pkill -x deskflow-core"

echo; echo "=== 2. MAIN (Lenuks): autostart + control script + config ==="
run "rm -f ~/.xprofile"
run "rm -f ~/.local/bin/screenextend"
run "rm -rf ~/.config/Deskflow"
run "rm -f ~/.cache/deskflow-server.log"

echo; echo "=== 3. MAIN: remove laptop's SSH key (restores original authorized_keys) ==="
run "sed -i '/mirr@ARCH-screenextend/d' ~/.ssh/authorized_keys"

echo; echo "=== 4. LAPTOP (ARCH): autostart + config ==="
rrun "rm -f ~/.xprofile"
rrun "rm -rf ~/.config/Deskflow"
rrun "rm -f ~/deskflow-client.log"

echo; echo "=== 5. LAPTOP: restore wifi power saving (needs sudo) ==="
rrun "sudo rm -f /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf"
rrun "sudo iw dev wlp0s20f3 set power_save on"

echo; echo "=== 6. LAPTOP: restore screen blanking / DPMS ==="
rrun 'p=$(pgrep -u mirr -f "i3-with-shmlog|^i3$" | head -1); xa=$(tr "\0" "\n" < /proc/$p/environ | grep ^XAUTHORITY | cut -d= -f2); DISPLAY=:0 XAUTHORITY=$xa xset s 600 600 +dpms'

echo; echo "=== 6b. Screenshot / clipboard fixes (added later) ==="
run "rm -f ~/.local/bin/clipimg"
rrun "rm -f ~/.local/bin/clipimg"
rrun "rm -f ~/.config/flameshot/flameshot.ini"
echo "  NOTE: this restores the laptop's flameshot portal bug (30s hang + abort)."
run "git -C ~/dotfiles checkout -- scripts/.scripts/ssCustomName.sh"
echo "  (^ restores the original xclip image/png line in the screenshot script)"

echo; echo "=== 7. OPTIONAL - packages (left installed by default; harmless) ==="
echo "  main:   sudo pacman -Rns deskflow libei"
echo "  laptop: sudo pacman -Rns deskflow libei libportal iw xorg-xset sshfs"
echo "  (main's SSH key on the laptop is left in place - it predates this setup"
echo "   as your normal admin access. Remove with:"
echo "     ssh $LAPTOP \"sed -i '/anshulchauhanworks/d' ~/.ssh/authorized_keys\" )"

echo
[ $APPLY -eq 1 ] && echo "*** REVERT APPLIED ***" || echo "*** DRY RUN COMPLETE ***"
