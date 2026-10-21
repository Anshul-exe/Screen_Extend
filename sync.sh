#!/bin/sh
# ============================================================================
# Pull the live config off both machines into this repo, so the tracked copies
# cannot silently drift from what is actually running.
#   ./sync.sh          show what differs (dry run)
#   ./sync.sh --apply  copy the live files into the repo
# Then review with `git diff` and commit.
# ============================================================================
set -u
cd "$(dirname "$0")" || exit 1
REPO=$(pwd)
MANIFEST="$REPO/config/MANIFEST"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

# The laptop address lives in exactly one place -- screenextend -- so there is
# no second copy of it to go stale. (README drift playbook.)
LAPTOP=$(sed -n 's/^LAPTOP="\(.*\)"$/\1/p' config/main/local-bin/screenextend | head -1)
[ -n "$LAPTOP" ] || { echo "could not read LAPTOP= from config/main/local-bin/screenextend"; exit 1; }

[ $APPLY -eq 0 ] && echo "*** DRY RUN - nothing will be written. Use --apply. ***"
echo "laptop: $LAPTOP"
echo

differ=0; same=0; skipped=0; unread=0

while read -r machine repo_path install_path flags <&3; do
    case "$machine" in ''|\#*) continue ;; esac

    # A 'link' target IS the repo file, so there is nothing to pull back.
    case ",$flags," in *,link,*)
        echo "  --  $repo_path  (symlinked; always in sync)"
        skipped=$((skipped+1)); continue ;;
    esac

    tmp=$(mktemp) || exit 1
    if [ "$machine" = main ]; then
        target=$(eval echo "$install_path")
        if [ -r "$target" ]; then cp "$target" "$tmp"; else rm -f "$tmp"; tmp=""; fi
    else
        # install_path may be ~-relative (remote $HOME) or absolute.
        if ! ssh -n -o BatchMode=yes -o ConnectTimeout=6 "$LAPTOP" \
                 "cat ${install_path}" > "$tmp" 2>/dev/null; then
            rm -f "$tmp"; tmp=""
        fi
    fi

    if [ -z "$tmp" ]; then
        echo "  ??  $repo_path  (could not read live file on $machine)"
        unread=$((unread+1)); continue
    fi

    if cmp -s "$tmp" "$repo_path"; then
        same=$((same+1))
    else
        differ=$((differ+1))
        echo "  !!  $repo_path  DIFFERS from live $machine copy"
        if [ $APPLY -eq 1 ]; then
            cp "$tmp" "$repo_path"
            case ",$flags," in *,exec,*) chmod +x "$repo_path" ;; esac
            echo "      updated in repo"
        fi
    fi
    rm -f "$tmp"
done 3< "$MANIFEST"

echo
echo "in sync: $same   differing: $differ   symlinked: $skipped   unreadable: $unread"
if [ $differ -gt 0 ] && [ $APPLY -eq 0 ]; then
    echo "run ./sync.sh --apply to bring the repo up to date, then: git diff"
fi
