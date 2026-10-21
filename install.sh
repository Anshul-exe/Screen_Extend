#!/bin/sh
# ============================================================================
# Rebuild the screen-extend setup from this repo onto a fresh pair of machines.
#   ./install.sh          show exactly what would happen (dry run)
#   ./install.sh --apply  do it
#
# Run this FROM the main machine. It deploys main's files locally and the
# laptop's over ssh, then generates TLS certs and exchanges fingerprints.
#
# Read README section 18 first. This script automates the mechanical parts; it
# does NOT make the judgement calls (tool choice, hostnames, screen layout)
# that sections 1-10 explain.
# ============================================================================
set -u
cd "$(dirname "$0")" || exit 1
REPO=$(pwd)
MANIFEST="$REPO/config/MANIFEST"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

LAPTOP=$(sed -n 's/^LAPTOP="\(.*\)"$/\1/p' config/main/local-bin/screenextend | head -1)
[ -n "$LAPTOP" ] || { echo "could not read LAPTOP= from config/main/local-bin/screenextend"; exit 1; }
LAPTOP_USER=${LAPTOP%@*}

run()  { if [ $APPLY -eq 1 ]; then eval "$1"; else echo "    would run: $1"; fi; }
rrun() { if [ $APPLY -eq 1 ]; then ssh -n -o BatchMode=yes "$LAPTOP" "$1"; \
         else echo "    would run (laptop): $1"; fi; }

[ $APPLY -eq 0 ] && echo "*** DRY RUN - nothing will change. Use --apply to execute. ***"
echo "main:   $(cat /etc/hostname 2>/dev/null)"
echo "laptop: $LAPTOP"

# ---------------------------------------------------------------------------
echo
echo "=== 1. Packages (checked, never installed for you) ==="
# README section 4: a careless -Sy on main risks a partial upgrade. You decide.
missing_main=""
for p in deskflow libei xdotool; do
    pacman -Q "$p" >/dev/null 2>&1 || missing_main="$missing_main $p"
done
if [ -n "$missing_main" ]; then
    echo "    main is missing:$missing_main"
    echo "    ->  sudo pacman -S --needed$missing_main"
else
    echo "    main:   all present ($(pacman -Q deskflow))"
fi
if missing_laptop=$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$LAPTOP" \
      'm=""; for p in deskflow libei libportal iw xorg-xset sshfs xorg-xinput python-xlib; do \
         pacman -Q $p >/dev/null 2>&1 || m="$m $p"; done; echo "$m"' 2>/dev/null); then
    if [ -n "$missing_laptop" ]; then
        echo "    laptop is missing:$missing_laptop"
        echo "    ->  ssh $LAPTOP 'sudo pacman -S --needed$missing_laptop'"
    else
        echo "    laptop: all present"
    fi
else
    echo "    laptop: unreachable -- fix ssh first, nothing below will work"
fi

# ---------------------------------------------------------------------------
echo
echo "=== 2. Config files, from config/MANIFEST ==="
while read -r machine repo_path install_path flags <&3; do
    case "$machine" in ''|\#*) continue ;; esac

    case ",$flags," in *,dotfiles,*)
        echo "    SKIP $install_path on $machine"
        echo "         (tracked in your dotfiles repo and stow-symlinked; edit it there,"
        echo "          or stow will fight you. Reference copy: $repo_path)"
        continue ;;
    esac

    if [ "$machine" = main ]; then
        target=$(eval echo "$install_path")
        case ",$flags," in
          *,link,*)
            echo "    LINK $target -> $REPO/$repo_path"
            run "mkdir -p '$(dirname "$target")'"
            run "ln -sfn '$REPO/$repo_path' '$target'"
            ;;
          *)
            echo "    COPY $repo_path -> $target"
            run "mkdir -p '$(dirname "$target")'"
            run "cp '$REPO/$repo_path' '$target'"
            case ",$flags," in *,exec,*) run "chmod +x '$target'" ;; esac
            ;;
        esac
    else
        echo "    COPY $repo_path -> laptop:$install_path"
        case ",$flags," in
          *,sudo,*)
            run "ssh -o BatchMode=yes '$LAPTOP' 'sudo tee $install_path >/dev/null' < '$REPO/$repo_path'"
            ;;
          *)
            rrun "mkdir -p \$(dirname $install_path)"
            run "scp -q '$REPO/$repo_path' '$LAPTOP:$install_path'"
            case ",$flags," in *,exec,*) rrun "chmod +x $install_path" ;; esac
            ;;
        esac
    fi
done 3< "$MANIFEST"

# ---------------------------------------------------------------------------
echo
echo "=== 3. TLS: self-signed cert on each machine, fingerprints exchanged ==="
# README section 7. Deskflow is trust-on-first-use and normally wants the Qt GUI
# to accept a fingerprint; writing the trust files directly avoids ever opening it.
GEN='mkdir -p ~/.config/Deskflow/tls && [ -f ~/.config/Deskflow/tls/deskflow.pem ] || { openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ~/.config/Deskflow/tls/deskflow.pem -out ~/.config/Deskflow/tls/deskflow.pem -subj "/CN=Deskflow" 2>/dev/null && chmod 600 ~/.config/Deskflow/tls/deskflow.pem; }'
FPR='openssl x509 -in ~/.config/Deskflow/tls/deskflow.pem -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ":" | tr "A-Z" "a-z"'
echo "    generate (only if absent) on both"
run  "$GEN"
rrun "$GEN"
echo "    main trusts the laptop  -> ~/.config/Deskflow/tls/trusted-clients"
echo "    laptop trusts main      -> ~/.config/Deskflow/tls/trusted-servers"
if [ $APPLY -eq 1 ]; then
    main_fp=$(eval "$FPR")
    lap_fp=$(ssh -o BatchMode=yes "$LAPTOP" "$FPR")
    printf 'v2:sha256:%s\n' "$lap_fp"  >  "$HOME/.config/Deskflow/tls/trusted-clients"
    ssh -o BatchMode=yes "$LAPTOP" \
        "printf 'v2:sha256:%s\n' '$main_fp' > ~/.config/Deskflow/tls/trusted-servers"
    echo "      main fingerprint:   ${main_fp%"${main_fp#????????}"}..."
    echo "      laptop fingerprint: ${lap_fp%"${lap_fp#????????}"}..."
else
    echo "    would read each fingerprint with: $FPR"
    echo "    and write it to the other machine as v2:sha256:<hex>"
fi

# ---------------------------------------------------------------------------
echo
echo "=== 4. Laptop: kill wifi powersave, never blank the panel ==="
# README section 3: this was the single biggest win -- p99 latency 46ms -> 4ms.
rrun 'iw dev $(iw dev | awk "/Interface/{print \$2; exit}") set power_save off 2>/dev/null || sudo iw dev $(iw dev | awk "/Interface/{print \$2; exit}") set power_save off'
echo "    (the persistent NetworkManager drop-in was installed in step 2)"
echo "    xset s off -dpms is in the laptop's xprofile, applied at next login"

# ---------------------------------------------------------------------------
echo
echo "=== 5. Start it ==="
run "pkill -x deskflow-core; true"
rrun "pkill -x deskflow-core; true"
echo "    then: screenextend start && screenextend status"
echo "    you want 'link: CONNECTED'"

echo
echo "--- not automated, on purpose ---"
echo "  * hostnames. Screen names MUST equal each machine's hostname, and they"
echo "    appear in config/*/Deskflow/*.conf. Change those if yours differ."
echo "  * the laptop's SDDM password at each boot (autologin was left off)."
echo "  * ssh keys both ways. The laptop->main direction is the escape hatch"
echo "    for when input capture wedges main (README section 12)."
echo "  * IP addresses. These are DHCP and have drifted three times; see the"
echo "    drift playbook at the end of the README. Static leases end it."
echo
[ $APPLY -eq 1 ] && echo "*** INSTALL APPLIED ***" || echo "*** DRY RUN COMPLETE ***"
