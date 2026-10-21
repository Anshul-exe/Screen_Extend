# Screen-extend: one keyboard and mouse across two Arch machines

Built 2026-09-04. Every measurement, log line and behaviour claimed in this
document was verified on the actual machines, not assumed.

---

## 1. The goal, and what was actually built

**The want:** monitors are expensive. A second laptop was acquired and the idea
was to use it as an extended display sitting to the right of the main screen —
not mirrored — with the mouse crossing between screens.

**What was built instead:** a _software KVM_. One keyboard and mouse drive both
machines; the cursor crosses the screen edge; the clipboard is shared. The
laptop keeps running its own i3 and its own applications.

This is deliberately **not** an extended display, and the difference matters:

|                      | Software KVM (built)          | Extended display (rejected) |
| -------------------- | ----------------------------- | --------------------------- |
| Video latency        | **Zero** — nothing is encoded | 10–25 ms best case          |
| Text sharpness       | Native panel                  | Softened by H.264 4:2:0     |
| CPU / GPU load       | ~0.2%                         | Constant encode + decode    |
| Drag a window across | **No**                        | Yes                         |
| Runs its own apps    | **Yes**                       | No, it is a dumb monitor    |

### The two machines

|         | `Lenuks` (main)               | `ARCH` (laptop)            |
| ------- | ----------------------------- | -------------------------- |
| CPU     | AMD Ryzen 7 6800H             | Intel i3-1215U             |
| RAM     | ~8 GB (see §19)               | 7.5 GB                     |
| GPU     | RTX 3050 Mobile + Radeon 680M | Intel UHD (Alder Lake)     |
| Display | eDP-1, 1920×1080              | eDP-1, 1920×1080           |
| Desktop | i3 4.25.1 on **X11**, SDDM    | i3 4.25.1 on **X11**, SDDM |
| User    | `mir`                         | `mirr`                     |
| IP      | 192.168.0.109 (DHCP, drifts)  | 192.168.0.114 (DHCP)       |

Both being **X11** is the single most important fact in this whole setup — it
determined which tools were even possible.

---

## 2. Why Deskflow, and why the other two options are dead

Three candidates exist. Two were eliminated on hard evidence before any
installation happened.

### lan-mouse — impossible here

Its own platform matrix lists X11 input **capture** as `WIP`, and states:

> "X11 currently only has support for input emulation, i.e. can only be used on
> the receiving end."

The main machine is X11 and _must_ be the capturing side. lan-mouse physically
cannot do the job. Clipboard sharing is also still unimplemented on its roadmap.

### input-leap — abandoned

The repository **was archived on 26 July 2026** and is read-only. Arch still
ships 3.0.3 and it would probably work, but it is dead upstream.

### Deskflow — chosen

- Ships in the **official Arch repo** (`extra/deskflow 1.26.0-2`) — no AUR, no
  DKMS, no out-of-tree kernel modules, signed and packaged by an Arch dev.
- Actively maintained; network-compatible with input-leap.
- Descends from Synergy (2001) via Barrier.

The alarming X11 bug reports were checked. The worst (#9542, "all app-level
keyboard input locks up on the client") is a **Wayland-server → X11-client**
case with custom keyboard tweaks. This setup is X11 → X11, the oldest and most
mature path in the codebase.

**Known long-term risk:** Deskflow intends to drop X11 eventually. Not near
term, but it is the direction of travel.

---

## 3. The network fix — the single biggest win

Before touching any software, the link was profiled. Input events are small and
frequent, which is the worst case for a sleeping radio.

```
main → laptop:  min 1.3   avg 60.0   max 155.6 ms    ← terrible
laptop → main:  min 1.3   avg  4.5   max   8.2 ms    ← fine
```

That asymmetry is the tell. Packets _arriving_ at the laptop waited; packets
_leaving_ it did not. The laptop's `iwlwifi` radio was sleeping between DTIM
beacons. NetworkManager reported powersave as "default", which for this driver
means **on**.

### The fix

```bash
# immediate, does NOT drop the link
sudo iw dev wlp0s20f3 set power_save off

# persistent across reboots
sudo tee /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF
```

### Measured result

|        | p50 | p90 | **p99**  | max     |
| ------ | --- | --- | -------- | ------- |
| Before | 2.2 | 3.6 | **46.4** | 98.4 ms |
| After  | 1.6 | 2.4 | **4.2**  | 7.3 ms  |

The p99 mattered far more than the average: roughly 1 in 100 mouse packets was
stalling for ~100 ms, which reads as a cursor that glides then randomly jumps.
**p99 improved 11×.**

### Still available: a direct Ethernet cable

Both machines have unused ports (`enp3s0` on main, `enp2s0` on laptop). A single
Cat6 cable between them gives gigabit, sub-millisecond, zero-jitter transport
and removes video/input traffic from wifi entirely. ~₹200. Not needed after the
powersave fix, but it is the ceiling if wifi ever misbehaves.

---

## 4. Installation

Dependencies were checked first so that a full `pacman -Syu` could be avoided on
the main machine — a system upgrade could have pulled a kernel and forced a
reboot mid-work.

```bash
# main needed only 2 packages
sudo pacman -Sw --noconfirm libei deskflow   # download only, non-destructive test
sudo pacman -S  --noconfirm libei deskflow   # installed from cache, NO -Sy

# laptop
sudo pacman -S --noconfirm libei libportal iw xorg-xset sshfs deskflow
# added later for diagnostics
sudo pacman -S --noconfirm xorg-xinput python-xlib
```

Because the mirror still held the exact versions in the local DB, `-Sy` was
never needed — **zero partial-upgrade risk on the main machine.**

### Final versions

| Package       | Version  | Where  | Purpose                    |
| ------------- | -------- | ------ | -------------------------- |
| `deskflow`    | 1.27.0-1 | main   | the KVM itself (see §19)    |
| `deskflow`    | 1.26.0-2 | laptop | still on 1.26; compatible   |
| `libei`       | 1.6.0-2  | main   | dependency                 |
| `libei`       | 1.6.0-1  | laptop | dependency                 |
| `libportal`   | 0.10.0-1 | laptop | dependency                 |
| `iw`          | 6.17-1   | laptop | wifi powersave control     |
| `xorg-xset`   | 1.2.6-1  | laptop | disable screen blanking    |
| `sshfs`       | 3.7.6-1  | laptop | mount main's home          |
| `xorg-xinput` | 1.6.4-2  | laptop | key-state diagnostics      |
| `python-xlib` | 0.33-7   | laptop | modifier-state diagnostics |

---

## 5. The Deskflow 1.26 CLI — not what the docs say

The Debian manpages describe `deskflow-server` / `deskflow-client` binaries with
flags like `--address`, `--name`, `--enable-crypto`, `-f`. **Arch 1.26 ships
none of that.** It ships two binaries:

```
/usr/bin/deskflow        # Qt GUI
/usr/bin/deskflow-core   # the actual engine
```

and `deskflow-core --help` offers only:

```
deskflow-core coremode [options]
  -h --help  -v --version  --new-instance  -s --settings <configFile>
  coremode: server | client
```

There is no positional server-IP argument. Passing one gives
`FATAL: No runtime error occurred: No server addresses configured`.

Everything is driven by two _different_ files:

1. **Screen layout** (server only): `~/.config/Deskflow/deskflow-server.conf` —
   the classic Synergy/Barrier text format, found by running the binary and
   reading the error it printed.
2. **App settings** (both): a QSettings INI at `~/.config/Deskflow/Deskflow.conf`.

The INI keys are not documented anywhere useful. They were recovered by dumping
the binary's Qt UTF-16 strings:

```bash
strings -el /usr/bin/deskflow-core | grep -iE "server|client|tls|screen"
```

which yielded `client/remoteHost`, `core/screenName`, `security/tlsEnabled`,
`server/externalConfig`, and the TLS paths `%1/tls`, `%1/trusted-clients`,
`%1/trusted-servers`.

---

## 6. Configuration

### Server layout — `~/.config/Deskflow/deskflow-server.conf` (main)

Screen names **must** match each machine's hostname.

> **The authoritative copy is `config/main/Deskflow/deskflow-server.conf`.** The
> listing below is the 2026-09-04 original and has since changed three times
> (§19, §20). Read the file, not this block.

> **Superseded on 2026-10-21 by Deskflow 1.27 — see §19.** The `section: screens`
> block below is no longer parsed; computers are declared in `Deskflow.conf`
> instead. Everything else in this section is still accurate.

```
section: screens
	Lenuks:
	ARCH:
end

section: links
	Lenuks:
		right = ARCH
	ARCH:
		left = Lenuks
end

section: options
	switchDelay = 250
	clipboardSharing = true
	clipboardSharingSize = 16384
	relativeMouseMoves = false
	heartbeat = 5000
	keystroke(control+alt+h) = switchInDirection(left)
	keystroke(control+alt+l) = switchInDirection(right)
	keystroke(control+alt+shift+p) = lockCursorToScreen(toggle)   # was +l, see §20
end
```

Why each option:

| Option                         | Reason                                                                                                                         |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `switchDelay = 250`            | Cursor must rest at the edge 250 ms before crossing. Without it a quick flick past the edge steals your keyboard mid-sentence. |
| `clipboardSharing = true`      | Text, HTML and images sync between machines.                                                                                   |
| `clipboardSharingSize = 16384` | **KB**, so 16 MB. Originally 1024; see §9 — a 1920×1080 BMP is ~8100 KB and was being silently dropped.                        |
| `relativeMouseMoves = false`   | Absolute positioning; only needed for games/VMs.                                                                               |
| `heartbeat = 5000`             | Liveness ping; disconnect after 3× no response.                                                                                |
| `switchInDirection`            | Keyboard-only switching. Verified present in the binary: `syntax for action: switchInDirection(<left\|right\|up\|down>)`.      |
| `lockCursorToScreen`           | Pins the cursor when heads-down. On `control+alt+shift+p` since 2026-10-22 (§20).                                                                                               |

**`screenSaverSync` does not exist in 1.26.** It is listed in the official docs
but was removed; including it makes the server refuse to start with
`unknown argument "screenSaverSync"`. This was caught by validating the config
before trusting it.

**Hotkey conflict check:** all 98 `bindsym` entries in the i3 config were
enumerated. `$mod` is `Mod1` (Alt), and `Mod4` (Super) is also used, but
**`Control+Alt` is completely unused** — so Deskflow's global `XGrabKey` on
those combos shadows nothing. Both machines share the same i3 config, so this
holds on the laptop too.

### Client settings — `~/.config/Deskflow/Deskflow.conf` (laptop)

```ini
[core]
screenName=ARCH

[client]
remoteHost=192.168.0.103

[security]
tlsEnabled=true
```

---

## 7. TLS without ever opening the GUI

Deskflow encrypts by default (TLS 1.3) using a **Trust-On-First-Use** model, and
normally prompts you to accept a fingerprint **in the Qt GUI**. A headless
`deskflow-core client` just fails:

```
ERROR: secure socket error: tls certificate doesn't exist:
       ~/.config/Deskflow/tls/deskflow.pem
ERROR: could not load client certificates
```

This was the one predicted blocker, and it was solved entirely from the shell.

### Step 1 — generate a self-signed cert on **each** machine

```bash
mkdir -p ~/.config/Deskflow/tls
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout ~/.config/Deskflow/tls/deskflow.pem \
  -out    ~/.config/Deskflow/tls/deskflow.pem \
  -subj "/CN=Deskflow"
chmod 600 ~/.config/Deskflow/tls/deskflow.pem
```

Key and cert go into the _same_ PEM — the Barrier/Synergy convention.

### Step 2 — exchange SHA-256 fingerprints

```bash
openssl x509 -in ~/.config/Deskflow/tls/deskflow.pem \
  -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-Z' 'a-z'
```

Write each side's fingerprint into the other's trust file, format
`v2:sha256:<lowercase hex>`:

| File                                     | Machine | Contains                     |
| ---------------------------------------- | ------- | ---------------------------- |
| `~/.config/Deskflow/tls/trusted-clients` | main    | the **laptop's** fingerprint |
| `~/.config/Deskflow/tls/trusted-servers` | laptop  | the **main's** fingerprint   |

### Result

```
IPC: peer fingerprint: C28CEC45...566E94
INFO: connected to secure socket
INFO: network encryption protocol: TLSv1.3
IPC: client "ARCH" has connected
```

Mutual verification, TLS 1.3, no GUI ever launched.

---

## 8. Autostart — why `~/.xprofile` and not systemd

Autostart lives in `~/.xprofile` on **each** machine. SDDM sources it — verified
in the actual script at `/usr/share/sddm/scripts/Xsession:44`:

```sh
[ -f $HOME/.xprofile ] && . $HOME/.xprofile
```

**Why not a systemd user unit?** Because the laptop's `XAUTHORITY` path is
**randomised at every login** (`/tmp/xauth_WbNxnV` today, something else
tomorrow). A systemd unit would need that value baked in or imported. `.xprofile`
runs inside the session and inherits `DISPLAY` and `XAUTHORITY` naturally.

**Why not the i3 config?** Because `~/.config/i3/config` is **tracked in the
dotfiles repo** and symlinked into it on the laptop. Editing it would dirty the
repo and risk a `git pull` or `stow --restow` clobbering the autostart at the
worst moment. `~/.xprofile` is untracked on both machines.

### main — `~/.xprofile`

```sh
#!/bin/sh
if command -v deskflow-core >/dev/null 2>&1; then
    ( sleep 5; exec deskflow-core server ) >/dev/null 2>&1 &
fi
```

### laptop — `~/.xprofile`

```sh
#!/bin/sh
xset s off -dpms                       # never blank: this panel is a monitor
( sleep 20; xset s off -dpms ) &       # re-assert after gnome-settings-daemon
if command -v deskflow-core >/dev/null 2>&1; then
    ( sleep 5; exec deskflow-core client ) >/dev/null 2>&1 &
fi
```

Both are **guarded and backgrounded** so a Deskflow failure can never block the
i3 login.

### Screen blanking

The laptop had a 10-minute blank + DPMS-off timer, and `xss-lock` running from
i3 would then lock it — meaning it would go dark and demand a password while
being used as a second screen. Rather than kill `xss-lock` (which lives in the
tracked i3 config), `xset s off -dpms` stops the X screensaver from ever firing,
so `xss-lock` is simply never triggered. Same result, zero tracked-file edits.

**Autologin was NOT enabled.** It was blocked by a permission guard, and it does
weaken security on that box. Consequence: the laptop needs its password typed at
SDDM once per boot before the link comes up. To enable it anyway:

```bash
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/20-screenextend-autologin.conf <<'EOF'
[Autologin]
User=mirr
Session=i3-with-shmlog
EOF
```

---

## 9. Clipboard images — two independent bugs

Screenshots pasted across machines arrived as garbage. There were **two** causes
and both had to be fixed; fixing either alone changes nothing.

### Cause A — format mismatch

Deskflow's clipboard understands exactly these types (extracted from the binary):

```
text/plain   text/plain;charset=utf-8   text/html   image/bmp
```

The screenshot script published `xclip -selection clipboard -t image/png`.
Deskflow found no format it recognised, and the raw PNG bytes surfaced on the
other machine as text — literally `\x89PNG ... IHDR ... IDAT` pasted as
characters. That garbage string was the diagnostic proof.

### Cause B — size limit

Even with the correct format it would have been dropped:

```
clipboardSharingSize = 1024        # KB
1920x1080 32-bit BMP  = 8100 KB    # 8x over
```

Deskflow logs `not updating clipboard because it's over the size limit` and
silently discards it. Raised to `16384`.

### The fix — `~/.local/bin/clipimg`

`xclip` can advertise only **one** target. GTK advertises every
GdkPixbuf-writable type at once. Verified:

```
image/bmp advertised? YES
image/png advertised? YES
```

So local applications still receive `image/png` exactly as before, while
Deskflow picks up `image/bmp`.

```python
#!/usr/bin/env python3
import signal, sys, gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")        # REQUIRED - without it Gdk 4.0 loads
gi.require_version("GdkPixbuf", "2.0")  # and the import dies
from gi.repository import Gdk, GdkPixbuf, Gtk

pixbuf = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
clipboard.set_image(pixbuf)
clipboard.store()
for sig in (signal.SIGINT, signal.SIGTERM):
    signal.signal(sig, lambda *_: Gtk.main_quit())
Gtk.main()   # MUST stay alive: X11 requires the selection owner to persist
```

Two non-obvious requirements, both learned the hard way:

- **`gi.require_version("Gdk", "3.0")` is mandatory.** Without it, Gdk 4.0 gets
  loaded first and the import fails with
  `Requiring namespace 'Gdk' version '3.0', but '4.0' is already loaded`.
- **The process must not exit.** X11 requires the clipboard owner to stay
  running to serve the data on request — this is exactly what `xclip` does
  internally.

### Wiring it in — `~/.scripts/ssCustomName.sh`

```sh
if [ -x "$HOME/.local/bin/clipimg" ]; then
  pkill -f "$HOME/.local/bin/clipimg" 2>/dev/null
  setsid "$HOME/.local/bin/clipimg" "$screenshot_dir/$default_name" >/dev/null 2>&1 &
  sleep 0.5   # let it load the file before the script may delete it
else
  xclip -selection clipboard -t image/png -i "$screenshot_dir/$default_name"
fi
```

The `else` branch keeps the script safe on any machine without `clipimg`.

### Verified end to end

| Direction     | Bytes sent | Bytes received | Received as                   |
| ------------- | ---------- | -------------- | ----------------------------- |
| main → laptop | 2,880,054  | 2,880,054      | `PC bitmap, 1200 x 800 x 24`  |
| laptop → main | 2,100,054  | 2,100,054      | `PC bitmap, 1000 x 700 x 24`  |
| full-screen   | 8,294,522  | 8,294,454      | `PC bitmap, 1920 x 1080 x 32` |

### Known limitation

When an image crosses, Deskflow hands the **receiving** side only `image/bmp` —
not the full target list. GIMP, Firefox and most GTK apps accept BMP. Chromium
and Electron apps (Discord, Slack, VS Code) often look for `image/png` only and
may refuse the paste even though the data is intact. If that bites, the fix is a
watcher on the receiving side that re-publishes an incoming BMP through
`clipimg` so all formats are offered again.

---

## 10. The laptop screenshot bug — not Deskflow at all

Symptom: pressing `Print` on the laptop errored with "screenshot aborted".

**Root cause: the flameshot 14 xdg-desktop-portal regression.** flameshot v14
probes `xdg-desktop-portal` for a Screenshot backend. If none provides it, it
hangs ~30 s and then reports "Unable to capture screen / Screenshot aborted".

|                                     | main                                                    | laptop     |
| ----------------------------------- | ------------------------------------------------------- | ---------- |
| flameshot                           | 14.0.0-1                                                | 14.0.0-1   |
| `~/.config/flameshot/flameshot.ini` | present, `useX11LegacyScreenshot=true` (set 2026-06-20) | **absent** |
| portal declaring `Screenshot`       | `gnome.portal`                                          | **none**   |

The fix had been applied on main back in June — but `flameshot.ini` **is not
tracked in the dotfiles repo**, so the laptop never received it.

```bash
mkdir -p ~/.config/flameshot
cat > ~/.config/flameshot/flameshot.ini <<'EOF'
[General]
contrastOpacity=188
useX11LegacyScreenshot=true
EOF
```

Result: 30-second hang → **0 seconds**, valid 1920×1080 PNG.

---

## 11. Control script — `~/.local/bin/screenextend`

```
screenextend start | stop | status | unstick | log
```

> The full script is tracked at **`config/main/local-bin/screenextend`**, and
> `~/.local/bin/screenextend` is a **symlink** to it — so the command you run and
> the copy in this repo can never drift apart. See §21.

The one interesting piece is that it **rediscovers the laptop's randomised
`XAUTHORITY` on every invocation**, by reading it out of the running i3
process's environment:

```sh
remote_x_env() {
    ssh -o BatchMode=yes "$LAPTOP" \
      'p=$(pgrep -u mirr -f "i3-with-shmlog|^i3$" | head -1); \
       xa=$(tr "\0" "\n" < /proc/$p/environ | grep ^XAUTHORITY | cut -d= -f2); \
       echo "DISPLAY=:0 XAUTHORITY=$xa"'
}
```

Without this, anything scripted against the laptop's display breaks on the next
login.

`unstick` releases every modifier (Ctrl, Alt, Shift, Super, Meta, AltGr,
CapsLock) on **both** machines — the remedy for a screen that starts behaving as
if Ctrl is held. Stuck modifiers are a known failure mode of X11 keyboard
sharing when a modifier is held across a screen switch. Note: this was hit once
in practice and **could not be reproduced afterwards**, including by simulating
realistic hold-across-switch timing. The cause is therefore unconfirmed and
`unstick` treats the symptom, not the cause.

---

## 12. Extras

### SSH, both directions

Deskflow shares clipboard but **not files**. Passwordless keys were installed
both ways:

- main → laptop: for administration.
- laptop → main: an **escape hatch**. If input capture ever wedges the main
  machine, SSH in from the laptop and run `screenextend unstick` or
  `pkill -x deskflow-core`.

### sshfs — `~/.local/bin/mount-main` (on laptop)

```sh
sshfs mir@192.168.0.103:/home/mir "$HOME/mnt/Lenuks" \
  -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,idmap=user
```

On-demand only, no fstab entry, so nothing can break at boot.

### The tmux trick — the best part of this setup

Both machines run tmux 3.7c. From the laptop:

```bash
ssh mir@192.168.0.103 -t 'tmux new-session -t "Main Bi-"'
```

This attaches to the **same tmux server** sharing the same windows, but with an
**independent current window**. The result is a genuine second terminal
workspace at native crispness and zero latency — most of what an extended
display would have given, without any streaming compromise.

---

## 13. Daily use

| Action                           | How                                                         |
| -------------------------------- | ----------------------------------------------------------- |
| Move to laptop                   | Mouse off the right edge, or `Ctrl+Alt+L`                   |
| Move back to main                | Mouse off the left edge, or `Ctrl+Alt+H`                    |
| Pin cursor to current screen     | `Ctrl+Alt+Shift+P` (toggle) — was `+L`, see §20            |
| Check link                       | `screenextend status`                                       |
| Keys acting stuck (phantom Ctrl) | `screenextend unstick`                                      |
| Watch the log                    | `screenextend log`                                          |
| Mount main's home on laptop      | `mount-main` / `mount-main -u`                              |
| Shared terminal workspace        | `ssh mir@192.168.0.103 -t 'tmux new-session -t "Main Bi-"'` |

---

## 14. Power cycling — it is automatic

| You shut down | To get back                                                              |
| ------------- | ------------------------------------------------------------------------ |
| Laptop only   | Power on, log in. Client autostarts, reconnects in ~1 s. Main untouched. |
| Main only     | Power on, log in. Server autostarts. Laptop reconnects on its own.       |
| Both          | Power on both, log in to each. **Order does not matter.**                |

The only manual step is the laptop's SDDM password.

**Why order does not matter (measured):** with the server stopped, the client
retried once per second at **0.2% CPU** indefinitely, then reconnected **1
second** after the server returned.

### Using one machine only

**Main alone** — leave the laptop off. Tested: with the client down, shoving the
cursor at the right edge parks it at `x:1919`. It **cannot get lost off-screen**,
because Deskflow will not switch to a disconnected screen. To stop the server
anyway: `screenextend stop`.

**Laptop alone** — an ordinary Arch box, fully standalone. Its client keeps
retrying to reach main at ~0.2% CPU, which is harmless. Silence it with
`pkill -x deskflow-core`.

### Verified safe, not assumed

- Shutting down main while the cursor is on the laptop: main regains its own
  pointer immediately, no stuck modifiers.
- Killing the server mid-session: input returns to main at once.

---

## 15. Do / Don't

**Do**

- Run `screenextend status` first when something seems off.
- Close the laptop lid to deliberately end a session — it suspends, which is the
  intended disconnect gesture.
- Trust the reconnect; it self-heals.
- Kill with `pkill -x deskflow-core` (exact match).

**Don't**

- **Never `pkill -f deskflow`** — `-f` matches your own shell's command line and
  kills your terminal. This happened twice during setup (exit code 144). The
  same trap applies to `pkill -f clipimg`. Use `-x`, or the bracket trick
  `pkill -f "clip[i]mg"`, and keep the literal name out of the same command.
- **Don't hardcode the laptop's `XAUTHORITY`.** It is randomised per login.
- **Don't expect the link before login** — the client starts with the i3
  session, not at the SDDM greeter.
- **Don't count on the laptop staying awake with the lid shut.**

---

## 16. Gotchas worth remembering

1. **`zsh` does not word-split unquoted variables.** `for d in $DEPS` iterates
   once over the whole string, so a dependency check reported _every_ package
   missing, including `glibc`. Use an array.
2. **`pkill -f` matches your own command line.** Twice fatal here.
3. **Each machine has its own clone of the dotfiles repo.** Editing a tracked
   script on one does **not** propagate. This caused the laptop to keep running
   the old screenshot script long after main was fixed.
4. **Copy helper scripts _after_ they work,** not before. A broken `clipimg` was
   copied to the laptop and then only fixed on main, so the laptop silently
   failed for another round of debugging.
5. **Validate config before trusting docs.** `screenSaverSync` is documented but
   removed in 1.26.
6. **File mtime is not session start time.** Sorting sessions by mtime produced
   a completely wrong conclusion about a rollout date.
7. **On the laptop, `~/.local/bin` is itself a stow symlink into the repo.**
   Files placed there are untracked but sit inside the repo tree and show as
   `??` in `git status`.

---

## 17. Files this setup owns

| Path                                                    | Machine | Tracked in dotfiles?                    |
| ------------------------------------------------------- | ------- | --------------------------------------- |
| `~/.xprofile`                                           | both    | no                                      |
| `~/.config/Deskflow/deskflow-server.conf`               | main    | no                                      |
| `~/.config/Deskflow/Deskflow.conf`                      | both    | no (holds the computer list since 1.27) |
| `~/.config/Deskflow/tls/{deskflow.pem,trusted-*}`       | both    | no                                      |
| `~/.local/bin/screenextend`                             | main    | no                                      |
| `~/.local/bin/clipimg`                                  | both    | no (inside the repo tree on ARCH)       |
| `~/.local/bin/mount-main`                               | laptop  | no (inside the repo tree on ARCH)       |
| `~/.config/flameshot/flameshot.ini`                     | laptop  | no                                      |
| `/etc/NetworkManager/conf.d/99-wifi-powersave-off.conf` | laptop  | no (root)                               |
| `~/.ssh/authorized_keys`                                | both    | no                                      |
| `~/.scripts/ssCustomName.sh`                            | both    | **YES — the only tracked file changed** |

Every one of these is now tracked in this repo under `config/`, with its
install path recorded in **`config/MANIFEST`** — except the four files listed as
deliberately untracked in §21. `./sync.sh` proves the tracked copies still match
what is running.

Revert that one file alone:

```bash
git -C ~/dotfiles checkout -- scripts/.scripts/ssCustomName.sh
```

Revert everything: `./REVERT.sh` (dry run), then `./REVERT.sh --apply`.

---

## 18. Replicating this from scratch

1. Confirm **both** machines run X11 (`echo $XDG_SESSION_TYPE`). On Wayland the
   tool choice changes entirely.
2. Profile the link with `ping -c 60 -i 0.05 -s 32 <other>` and look at **p99**,
   not the average. Kill wifi powersave if the two directions are asymmetric.
3. `pacman -S deskflow` on both. Note the hostnames — they become the screen
   names.
4. Write the server layout config; **validate it** by running
   `deskflow-core server` and reading the error.
5. Generate a self-signed PEM on each machine, exchange SHA-256 fingerprints
   into `trusted-clients` / `trusted-servers` as `v2:sha256:<hex>`.
6. Write the client's `Deskflow.conf` with `client/remoteHost` and
   `core/screenName`.
7. Start both, confirm `client "<name>" has connected` and `TLSv1.3` in the log.
8. Add autostart to `~/.xprofile` on each — **not** to a tracked WM config.
9. On the client, `xset s off -dpms` so it never blanks.
10. For image clipboard, publish with something that advertises multiple targets
    and raise `clipboardSharingSize` well above your screen's uncompressed BMP
    size.

Fixed. Here's your drift playbook.

When the link dies, check this first

ip -4 addr show wlan0 | grep inet # main's current IP
screenextend status

If main's IP is no longer what the laptop expects, that's the whole problem

Three files hold an IP — two on the laptop, one on main

┌──────────────────────────────────┬─────────┬─────────────┬───────────────
│ File │ Machine │ Holds │ Line │
├──────────────────────────────────┼─────────┼─────────────┼─────────────────┤
│ ~/.config/Deskflow/Deskflow.conf │ laptop │ main's IP │ remoteHost= │
├──────────────────────────────────┼─────────┼─────────────┼─────────────────┤
│ ~/.local/bin/mount-main │ laptop │ main's IP │ sshfs mir@… │
├──────────────────────────────────┼─────────┼─────────────┼─────────────────┤
│ ~/.local/bin/screenextend │ main │ laptop's IP │ LAPTOP="mirr@…" │
└──────────────────────────────────┴─────────┴─────────────┴─────────────────┘

Only the first one breaks the cursor. The other two break sshfs and the control script respectively.
If main's IP changed (run from main, substituting the new IP):

ssh mirr@192.168.0.111 "sed -i 's/192\.168\.0\.107/NEW_IP/' \
 ~/.config/Deskflow/Deskflow.conf ~/.local/bin/mount-main"
screenextend stop && screenextend start

If the laptop's IP changed — edit LAPTOP= on line 4 of ~/.local/bin/screenextend, then restart. (REVERT.sh in this folder also has it on line 8, but that only matters the day you tear the setup down.)
Confirm with screenextend status — you want client "ARCH" has connected.

Both currently: main 192.168.0.109, laptop 192.168.0.114 (as of 2026-10-21).

Since it's three files rather than one, the sed one-liner above is the practical middle ground — it covers both laptop files in a single command. If you'd rather not think about it at all, ping me on /short and we'll make it self-discovering.

---

## 19. 2026-10-21 — the Deskflow 1.27 config break

**Symptom reported:** main's memory hit 98%, everything stalled, programs were
closed to recover — and afterwards the screen extension was gone and could not
be reached.

**What was actually wrong:** two separate things, and only one of them had
anything to do with the memory squeeze.

### The fatal one — `pacman -Syu` upgraded Deskflow on main only

```
/var/log/pacman.log:
[2026-10-21T17:04:01+0530] [ALPM] upgraded deskflow (1.26.0-2 -> 1.27.0-1)
```

The machine had booted at 16:29, so the 1.26 server was already running when
the upgrade landed. A running process keeps its old binary inode, so it carried
on serving — it was still listening on 24800 with an ESTABLISHED connection from
the laptop when this was investigated at 19:55. **The breakage only surfaces the
moment the server is restarted**, which is exactly what §13 tells you to do when
something seems off:

```
WARNING: Your server config has a screen section. Screens have moved to the
         general config this section will not be parsed.
ERROR:   cannot read configuration ".../deskflow-server.conf":
         read error: line 11: unknown computer name "Lenuks"
FATAL:   failed to load config
ERROR:   core stopped with error code: 4
```

Line 11 is `Lenuks:` in `section: links`. 1.27 ignores `section: screens`, so by
the time it reaches the links section neither computer name exists. **This would
also have failed silently at the next reboot** via `~/.xprofile`, regardless of
anything the memory incident did.

### The migration — screens move to the general config

Verified against `/usr/share/doc/deskflow/Configuration.md`, which 1.27 ships
(1.26 shipped no docs at all — that is why §5 had to recover keys with
`strings`).

**1. `~/.config/Deskflow/deskflow-server.conf` — delete the whole
`section: screens … end` block.** Keep `links` and `options` exactly as they
were.

**2. `~/.config/Deskflow/Deskflow.conf` — declare one group per computer:**

```ini
[computer_Lenuks]
name=Lenuks

[computer_ARCH]
name=ARCH
```

The group name is the computer name (`[computer_<name>]`). The text config is
parsed top to bottom and a name cannot be used in `links` before it is declared
here.

**What did _not_ change — tested, not assumed.** Every option in the text
`options` section still parses under 1.27: `switchDelay`, `clipboardSharing`,
`clipboardSharingSize`, `relativeMouseMoves`, `heartbeat`, and all three
`keystroke(...)` bindings. 1.27 also offers `[server]` equivalents in
`Deskflow.conf` (`switchDelay`, `enableClipboard`, `clipboardSize` — note that
one is in **MB**, not KB), but there is no need to move anything, so nothing was
moved.

### Version skew across the link is fine

Main is on 1.27.0-1, the laptop still on 1.26.0-2. Both report `protocol v1.8`
and the link negotiated TLS 1.3 and worked. The client has no screens config at
all, so upgrading the laptop later changes nothing on its side.

### Verified end to end, not assumed

```
server: INFO: accepted secure socket / saying hello as Barrier, protocol v1.8
client: INFO: network encryption protocol: TLSv1.3
client: IPC:  connected to server
server: INFO: switch from "Lenuks" to "ARCH" at 528,354
server: INFO: computer "Lenuks" updated clipboard 0 / 1
server: INFO: switch from "ARCH" to "Lenuks" at 1543,840
```

Round-tripped with `Ctrl+Alt+L` then `Ctrl+Alt+H`; the pointer came back to the
exact pixel it started on, and clipboard sync fired on the way across.

### The unconfirmed one — what wedged it before the restart

The still-running 1.26 server was alive and TCP-connected but reportedly not
passing input. The cause cannot be established, **because the autostarted server
wrote its output to `/dev/null`** — there was no log for the entire session. The
memory squeeze is the obvious suspect and a restart cleared it, but that is
inference, not evidence.

So the hole was closed:

| File                        | Was                     | Now                                 |
| --------------------------- | ----------------------- | ----------------------------------- |
| `~/.xprofile` (main)        | `>/dev/null 2>&1`       | `>"$HOME/.cache/deskflow-server.log"` |
| `~/.xprofile` (laptop)      | `>/dev/null 2>&1`       | `>"$HOME/deskflow-client.log"`      |

Now `screenextend log` and `screenextend status` have something to read after a
plain login, not only after a manual `screenextend start`. The `status` grep also
learned `accepted client connection`, because 1.27 headless no longer prints
`client "ARCH" has connected` — that was a GUI-IPC line.

### IP drift, again

Both addresses had moved and `LAPTOP=` was two addresses stale:

| File                        | Held                  | Fixed to        |
| --------------------------- | --------------------- | --------------- |
| `~/.local/bin/screenextend` | `mirr@192.168.0.105`  | `.114`          |
| `REVERT.sh` (line 8)        | `mirr@192.168.0.105`  | `.114`          |

The laptop's two files (`Deskflow.conf`, `mount-main`) were already correct at
`192.168.0.109`. The drift playbook above still stands, and this is now the
third time it has been needed — static DHCP leases on the router would end it
for good.

### Unrelated, but it is why the memory ran out

`RAM: 14 GB` in §1 is no longer true of main:

```
/proc/meminfo:  MemTotal:  7354616 kB
kernel:         Memory: 7054212K/7615304K available
amdgpu:         VRAM: 512M            <- iGPU is NOT eating it
/proc/cmdline:  no mem= limit
```

Main is running on roughly **half** the RAM this document was written against,
and the 512 MB iGPU carve-out does not account for it. That is why a normal
workload hit 98%.

**Resolved 2026-10-22:** not a fault — one DIMM was deliberately removed to deal
with a separate issue, and is going back in shortly. Until it does, this machine
swaps hard, which has knock-on effects on the link (see §20). Put `heartbeat`
back to `5000` once the RAM is in.

---

## 20. 2026-10-22 — locked out, then a link that only looked alive

**Symptom reported:** the laptop could not be reached again.

This time there was a log to read, because §19 pointed the autostart at one.
Everything below came out of it in about two minutes. It was **two unrelated
faults stacked on top of each other.**

### Fault 1 — the cursor was pinned, for 3½ hours

```
[2026-10-21T21:50:43] INFO: cursor locked to current computer
[2026-10-22T01:18:45] INFO: cursor unlocked from current computer   <- 3h28m later
[2026-10-22T01:24:57] INFO: cursor locked to current computer       <- and again
```

Between those, ~500 repetitions of:

```
INFO: cursor is locked to computer, check scroll lock key
```

That is the cursor being shoved at the edge and refused, once per attempt. A
pinned cursor is **indistinguishable from a broken link** from the user's side:
no dialog, no OSD, nothing on screen — the cursor just stops.

**Why it kept happening.** The two bindings were one keypress apart:

| Was                    | Does                      |
| ---------------------- | ------------------------- |
| `Ctrl+Alt+L`           | switch right, to the laptop |
| `Ctrl+Alt+**Shift**+L` | pin the cursor, silently    |

One stray Shift — the hand is already on Shift constantly — turns "go to the
laptop" into "lock myself out of the laptop". Rebound to **`Ctrl+Alt+Shift+P`**
(`p` for pin), which is nowhere near the switch keys. Verified: the old
`Ctrl+Alt+Shift+L` is now inert, and `Ctrl+Alt+Shift+P` locks and unlocks.

**Scroll Lock was tested and is innocent.** 1.27's `[server]` docs say
`disableLockToComputer` defaults to false, i.e. Scroll Lock toggles the pin — but
pressing it did nothing here, because the text config *does* define a
`lockCursorToScreen` action, and that suppresses the Scroll Lock behaviour. So
the log's own advice ("check scroll lock key") is misleading on this setup. The
only way in was the hotkey.

### Fault 2 — a link that was ESTABLISHED but had no session

```
client: [01:22:50.834] NOTE:    server is dead
client: [01:22:50.836] WARNING: failed to connect to server: server is not responding
client: [01:22:51.847] IPC:     connecting to '192.168.0.109':24800
                                 ... and then nothing, ever
```

Meanwhile the server logged `can't leave computer` 25 times, once per second,
then gave up with `jump from "ARCH" to "Lenuks" at 960,540`.

The giveaway: **the whole server log contained exactly one
`accepted client connection`** — the one from the restart hours earlier. The
client's reconnect was never accepted at the application level, yet:

```
ESTAB  192.168.0.109:24800  192.168.0.114:47694  users:(("deskflow-core",pid=969942,fd=20))
```

TCP established, both processes alive, server still responsive to hotkeys (it
processed a lock/unlock while in this state) — but no Deskflow session. A switch
request against a screen the server does not consider connected is **refused
silently, with nothing written to the log at all.** That is the hardest shape of
this failure to diagnose: every surface check passes.

**What stalled it.** With one DIMM out (§19) this machine swaps hard:

```
/proc/vmstat:  pswpin 7541935   pswpout 10062754     (~29 GB in, ~38 GB out)
```

`heartbeat = 5000` means the client declares the server dead after 3×5s. A
swap-thrashing server stalls past 15 s easily, so the client drops a link that
was never actually broken — and the reconnect is what wedged. Raised to
**`heartbeat = 15000`** (45 s). **Put it back to 5000 once the RAM is in.**

### `screenextend status` was lying

It reported `RUNNING / RUNNING` throughout, because it only checked that two
processes existed. It now asks the client what its last connection event was:

```
server (Lenuks): RUNNING
client (ARCH):   RUNNING
link:            CONNECTED
```

and on a wedge: `link: NOT CONNECTED (client: connecting to) -- run: screenextend stop && screenextend start`.
The detection was checked against the real tail of tonight's wedged log, not a
guess at one.

### Verified after the fix

| Mechanism                  | Result                                              |
| -------------------------- | --------------------------------------------------- |
| Mouse at the right edge    | crossed; `switch from "Lenuks" to "ARCH" at 0,500`  |
| `Ctrl+Alt+L`               | 8/8 from five different pointer positions           |
| `Ctrl+Alt+H`               | returned to the exact starting pixel                |
| Clipboard on crossing      | `updated clipboard 0 / 1`                           |
| `Ctrl+Alt+Shift+P`         | locks and unlocks; old `+L` inert                   |

### Unconfirmed, and left unconfirmed

For about two minutes (01:30:30–01:31:40) `Ctrl+Alt+L` did nothing, twice, with
**no log line whatsoever** — while `Ctrl+Alt+H` and edge crossing both worked.
The obvious suspect was the pin toggle leaving `switchInDirection` wedged; that
was tested directly (lock, unlock, switch) **three times and passed every time**,
and the hotkey has since worked 11/11. So the cause is unknown. Recorded here
rather than explained away — same as the stuck-modifier incident in §11.

### Changes

| File                                      | Change                                              |
| ----------------------------------------- | --------------------------------------------------- |
| `~/.config/Deskflow/deskflow-server.conf` | pin hotkey `+l` → `+p`; `heartbeat` 5000 → 15000    |
| `~/.local/bin/screenextend`               | `status` now verifies the session, not the processes |
| `README.md` §6, §13                       | hotkey change reflected in both places it is documented |

Backups of everything touched sit beside the originals as `*.bak-2026-10-22`,
and the wedged log is kept at
`~/.cache/deskflow-server.log.wedged-2026-10-22.bak`.

---

## 21. What this repo tracks, and what it deliberately does not

Up to §20 this repo was documentation only: every config file it described lived
on one of the two machines and nowhere else. Two consequences showed up
immediately — the `screenextend` script existed in exactly one place with no
backup, and §6's config listing had quietly drifted three versions behind the
file it claimed to document.

So the repo now holds the **what** as well as the **why**.

### Layout

```
config/
  MANIFEST                  every file, its install path, and its flags
  main/
    xprofile                -> ~/.xprofile
    Deskflow/               -> ~/.config/Deskflow/
    local-bin/screenextend  -> ~/.local/bin/screenextend   (SYMLINK, see below)
    local-bin/clipimg       -> ~/.local/bin/clipimg
    scripts/                reference copy; the live one is in the dotfiles repo
  laptop/
    xprofile, Deskflow/, local-bin/, flameshot/, NetworkManager/
install.sh                  repo -> machines   (dry run by default)
sync.sh                     machines -> repo   (dry run by default)
```

Both scripts default to a dry run and need `--apply`, same convention as
`REVERT.sh`.

### `screenextend` is a symlink, not a copy

```
~/.local/bin/screenextend -> <repo>/config/main/local-bin/screenextend
```

A copy would need remembering to re-copy after every edit, and would be stale
exactly when it mattered. With a symlink there is one file, tracked, and editing
it *is* editing the live command. `~/.local/bin` is on `PATH`, which is the only
reason `screenextend` works as a command from anywhere — nothing was installed.

The trade: **if this repo is moved or deleted, the command breaks** (dangling
symlink). `./install.sh --apply` recreates it. This is the same arrangement the
laptop already uses, where `~/.local/bin` is a stow symlink into the dotfiles
repo (§16, gotcha 7).

### Deliberately untracked

| Path | Why |
| --- | --- |
| `~/.config/Deskflow/tls/deskflow.pem` | **Private key.** Cert and key are in the same PEM (§7). Never commit this. |
| `~/.config/Deskflow/tls/trusted-clients` | Per-install fingerprint; `install.sh` regenerates it. |
| `~/.config/Deskflow/tls/trusted-servers` | Same, other direction. |
| `~/.ssh/authorized_keys` | Identity. |

`.gitignore` blocks `*.pem`, `*.key`, `authorized_keys*`, `id_rsa*`,
`id_ed25519*`, `known_hosts*`, plus `*.log`, `logs/`, `resume` and `*.bak*`.

An `authorized_keys.backup` holding one public key **was** committed and pushed
to a public repo on 2026-10-21, and was purged from history on 2026-10-22. A
public key is not a credential and nothing needed rotating, but it had no
business being here. It now sits at `~/.ssh/authorized_keys.backup-2026-09-04`,
outside the repo.

**What the tracked files still contain:** LAN IPs (`192.168.0.109`,
`192.168.0.114`), usernames (`mir`, `mirr`) and hostnames (`Lenuks`, `ARCH`).
None is secret, all of it is already throughout this README, and RFC1918
addresses mean nothing outside this LAN. Scrub it if you would rather — but the
screen names **must** equal the hostnames, so those two cannot simply be
renamed without editing both Deskflow configs to match.

### Keeping it honest

```bash
./sync.sh            # does the repo still match both machines?
./sync.sh --apply    # pull live changes in, then: git diff
```

`sync.sh` reads the laptop's address out of `screenextend`'s `LAPTOP=` line
rather than keeping its own copy, so the drift playbook's count of three files
holding an IP stays three.

One bug worth recording, because it is easy to reintroduce: the manifest loop
reads on **fd 3**, not stdin. `ssh` consumes stdin, and with `done < MANIFEST`
it silently swallowed the remaining five laptop entries — the script reported
success having checked barely half the files. `while read ... <&3; done 3< file`
is the fix. This is the same family of mistake as gotcha 1 in §16.

### Rebuilding from scratch

```bash
git clone <this repo> && cd screenExtend
./install.sh                     # read it
./install.sh --apply             # packages checked, configs deployed, TLS set up
screenextend status              # want: link: CONNECTED
```

§18 is still the conceptual order to follow; `install.sh` just does the
mechanical parts of it. What it cannot do for you: hostnames (they are the screen
names), the laptop's SDDM password at boot, ssh keys both ways, and DHCP
addresses — see the drift playbook.
