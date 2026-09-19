#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# installer-beginners - install and remove apps with the system package manager.
# Copyright (C) 2026 S00what
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

VERSION="1.0.0"

usage() {
  cat <<EOF
installer-beginners $VERSION - install and remove programs with your package manager.

Usage:
  installer-beginners                  menu
  installer-beginners git vim          install packages
  installer-beginners -r vim htop      remove packages
  installer-beginners --setup          fish + ghostty as defaults
  installer-beginners -h, --help       this help
  installer-beginners -V, --version    version

The sudo password is entered once. Root is not asked for a password.
EOF
}

case "$1" in
  -h|--help)    usage; exit 0 ;;
  -V|--version) echo "installer-beginners $VERSION"; exit 0 ;;
esac

KEEPALIVE_PID=""
APPS=()
ADDED=(); SKIPPED=(); REMOVED=(); ABSENT=(); FAILED=()
FAIL_KIND=install
trap 'cleanup_sudo' EXIT

# --- log (what was added / removed) ---
USER_NAME="${SUDO_USER:-${USER:-$(id -un)}}"
LOG_HOME=$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)
LOG_FILE="${LOG_HOME:-$HOME}/.install_apps.log"

log_action() {  # $1 = + or -, $2 = package
  printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "$2" >> "$LOG_FILE" 2>/dev/null
  if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    chown "$SUDO_USER" "$LOG_FILE" 2>/dev/null
  fi
}

# --- detect package manager ---
PM=""
for pm in apt-get dnf yum pacman zypper apk xbps-install brew; do
  if command -v "$pm" >/dev/null 2>&1; then PM="$pm"; break; fi
done
if [ -z "$PM" ]; then
  echo "Package manager not found."
  exit 1
fi
echo "Package manager: $PM"

# --- curl support (shown in the startup message) ---
CURL_OK=0
command -v curl >/dev/null 2>&1 && CURL_OK=1
if [ "$CURL_OK" -eq 1 ]; then echo "curl: OK"; else echo "CURL NOT SUPPORTED"; fi

# --- is a password needed ---
NEED_SUDO=1
if [ "$EUID" -eq 0 ] || [ "$PM" = "brew" ]; then
  NEED_SUDO=0
elif ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is not installed. Run the script as root."
  exit 1
fi

# --- sudo: the password is entered once, sudo caches it itself ---
init_sudo() {
  sudo -v || { echo "Script cancelled"; exit 1; }
  # keep the sudo cache alive during long operations
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null || exit 0; sleep 50; done ) &
  KEEPALIVE_PID=$!
}

cleanup_sudo() {
  [ -n "$KEEPALIVE_PID" ] || return 0
  kill "$KEEPALIVE_PID" 2>/dev/null
  sudo -k 2>/dev/null
}

# --- run a command as root ---
run_sudo() {
  if [ "$NEED_SUDO" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

confirm() {
  local a
  read -r -p "$1 [y/N] " a
  case "$a" in y|Y|yes|д|Д|да) return 0 ;; *) return 1 ;; esac
}

# --- package manager operations ---
is_installed() {
  case "$PM" in
    apt-get)      dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    dnf|yum|zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    pacman)       pacman -Qq "$1" >/dev/null 2>&1 ;;
    apk)          apk info -e "$1" >/dev/null 2>&1 ;;
    xbps-install) xbps-query "$1" >/dev/null 2>&1 ;;
    brew)         brew list "$1" >/dev/null 2>&1 ;;
  esac
}

pm_update() {
  case "$PM" in
    apt-get)
      run_sudo env DEBIAN_FRONTEND=noninteractive apt-get update -y &&
      run_sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y ;;
    dnf)          run_sudo dnf upgrade -y ;;
    yum)          run_sudo yum update -y ;;
    pacman)       run_sudo pacman -Syu --noconfirm ;;
    zypper)       run_sudo zypper --non-interactive refresh &&
                  run_sudo zypper --non-interactive update ;;
    apk)          run_sudo apk update && run_sudo apk upgrade ;;
    xbps-install) run_sudo xbps-install -Syu ;;
    brew)         brew update && brew upgrade ;;
  esac
}

pm_install() {
  case "$PM" in
    apt-get)      run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$1" ;;
    dnf)          run_sudo dnf install -y "$1" ;;
    yum)          run_sudo yum install -y "$1" ;;
    pacman)       run_sudo pacman -S --needed --noconfirm "$1" ;;
    zypper)       run_sudo zypper --non-interactive install "$1" ;;
    apk)          run_sudo apk add "$1" ;;
    xbps-install) run_sudo xbps-install -y "$1" ;;
    brew)         brew install "$1" ;;
  esac
}

pm_remove() {
  case "$PM" in
    apt-get)      run_sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$1" ;;
    dnf)          run_sudo dnf remove -y "$1" ;;
    yum)          run_sudo yum remove -y "$1" ;;
    pacman)       run_sudo pacman -Rns --noconfirm "$1" ;;
    zypper)       run_sudo zypper --non-interactive remove "$1" ;;
    apk)          run_sudo apk del "$1" ;;
    xbps-install) run_sudo xbps-remove -Ry "$1" ;;
    brew)         brew uninstall "$1" ;;
  esac
}

# --- clean up unused dependencies ---
do_cleanup() {
  local orph
  case "$PM" in
    pacman)
      mapfile -t orph < <(pacman -Qdtq 2>/dev/null)
      if [ "${#orph[@]}" -eq 0 ]; then echo "No unused dependencies."; return; fi
      echo "Unused dependencies: ${orph[*]}"
      confirm "Remove them?" && run_sudo pacman -Rns --noconfirm "${orph[@]}" ;;
    apt-get)
      confirm "Remove unused dependencies (autoremove)?" &&
        run_sudo env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y ;;
    dnf|yum)
      confirm "Remove unused dependencies (autoremove)?" &&
        run_sudo "$PM" autoremove -y ;;
    xbps-install)
      confirm "Remove orphaned packages?" && run_sudo xbps-remove -oy ;;
    brew)
      confirm "Remove unused dependencies?" && brew autoremove ;;
    *) echo "Auto-cleanup is not supported for $PM." ;;
  esac
}

# --- add packages to the list (no duplicates, name validation) ---
add_packages() {
  local words w a dup
  read -r -a words <<< "${1//,/ }"
  for w in "${words[@]}"; do
    if [[ ! "$w" =~ ^[A-Za-z0-9][A-Za-z0-9@._+-]*$ ]]; then
      echo "Skipped (invalid name): $w"
      continue
    fi
    dup=0
    for a in "${APPS[@]}"; do [ "$a" = "$w" ] && dup=1; done
    [ "$dup" -eq 0 ] && APPS+=("$w")
  done
}

# --- interactive package input ---
ask_packages() {
  local line
  echo "Enter package names separated by spaces or commas. You can enter several times."
  echo "Empty line to continue."
  while true; do
    IFS= read -r -p "Packages: " line || break
    [ -z "${line//[[:space:],]/}" ] && break
    add_packages "$line"
    echo "In list: ${APPS[*]}"
  done
}

# --- package descriptions: own (for known ones) or official from the repository ---
own_desc() {
  case "$1" in
    fish)      echo "Smart shell: autosuggestions and highlighting out of the box." ;;
    ghostty)   echo "Fast GPU-accelerated terminal with a native interface." ;;
    git)       echo "Distributed version control system." ;;
    curl)      echo "Tool for transferring data by URL (HTTP, FTP, etc.)." ;;
    wget)      echo "Command-line file downloader." ;;
    vim)       echo "Command-line text editor." ;;
    neovim)    echo "Modern vim fork: Lua plugins, built-in LSP." ;;
    nano)      echo "Simple command-line text editor." ;;
    htop)      echo "Interactive process and resource monitor." ;;
    btop)      echo "Pretty resource monitor: CPU, memory, disks, network." ;;
    tmux)      echo "Terminal multiplexer: sessions, windows, panes." ;;
    unzip)     echo "Extracts ZIP archives." ;;
    zip)       echo "Creates ZIP archives." ;;
    tree)      echo "Shows directory contents as a tree." ;;
    jq)        echo "JSON processor for the command line." ;;
    ripgrep)   echo "Very fast text search in files (rg)." ;;
    fd|fd-find) echo "Fast and friendly find replacement." ;;
    bat)       echo "cat with syntax highlighting and line numbers." ;;
    fastfetch|neofetch) echo "Shows system information in the terminal." ;;
    docker)    echo "Application containerization platform." ;;
    python|python3) echo "Python language interpreter." ;;
    nodejs)    echo "JavaScript runtime." ;;
    ffmpeg)    echo "Audio and video conversion and processing." ;;
    zsh)       echo "Shell with rich customization." ;;
    *)         return 1 ;;
  esac
}

pm_desc() {  # official description from the repository; returns 1 if the package is missing
  local d=""
  case "$PM" in
    apt-get)      d=$(apt-cache show "$1" 2>/dev/null | sed -n 's/^Description[^:]*: //p' | head -1) ;;
    pacman)       d=$(pacman -Si "$1" 2>/dev/null | sed -n 's/^Description *: //p' | head -1)
                  [ -z "$d" ] && d=$(pacman -Qi "$1" 2>/dev/null | sed -n 's/^Description *: //p' | head -1) ;;
    dnf|yum)      d=$("$PM" info "$1" 2>/dev/null | sed -n 's/^Summary *: //p' | head -1) ;;
    zypper)       d=$(zypper --non-interactive info "$1" 2>/dev/null | sed -n 's/^Summary *: //p' | head -1) ;;
    apk)          d=$(apk info -d "$1" 2>/dev/null | sed -n '2p') ;;
    xbps-install) d=$(xbps-query -R -p short_desc "$1" 2>/dev/null | head -1) ;;
    brew)         d=$(brew desc "$1" 2>/dev/null | sed 's/^[^:]*: //' | head -1) ;;
  esac
  [ -n "$d" ] && echo "$d"
}

pkg_desc() { own_desc "$1" || pm_desc "$1"; }

print_group() {  # $1 = title, $2 = icon, the rest = packages
  local title="$1" icon="$2" p d
  shift 2
  [ "$#" -eq 0 ] && return
  echo "$title:"
  for p in "$@"; do
    d=$(pkg_desc "$p")
    echo "  $icon $p${d:+ — $d}"
  done
}

print_failed() {  # packages that failed to install / remove
  local p d why
  [ "$#" -eq 0 ] && return
  echo "Failed:"
  for p in "$@"; do
    d=$(own_desc "$p")
    if [ "$FAIL_KIND" = "remove" ]; then
      why="removal failed, the package may be needed by others"
    elif [ -z "$(pm_desc "$p")" ]; then
      why="not found in $PM repositories"
    else
      why="install failed, see output above"
    fi
    echo "  ✘ $p${d:+ — $d} [$why]"
  done
}

print_report() {
  echo
  echo "===== Report ====="
  print_group "Installed" "✔" "${ADDED[@]}"
  print_group "Already installed" "•" "${SKIPPED[@]}"
  print_group "Removed" "✔" "${REMOVED[@]}"
  print_group "Not installed" "•" "${ABSENT[@]}"
  print_failed "${FAILED[@]}"
  echo "Log: $LOG_FILE"
}

do_install() {
  ADDED=(); SKIPPED=(); FAILED=(); FAIL_KIND=install
  local app
  echo "==> Updating system"
  pm_update || echo "Warning: system update finished with an error"
  for app in "${APPS[@]}"; do
    if is_installed "$app"; then
      SKIPPED+=("$app")
      continue
    fi
    echo "==> Installing: $app"
    if pm_install "$app"; then
      ADDED+=("$app"); log_action + "$app"
    else
      FAILED+=("$app")
    fi
  done
  print_report
}

do_remove() {
  REMOVED=(); ABSENT=(); FAILED=(); FAIL_KIND=remove
  local app present=()
  for app in "${APPS[@]}"; do
    if is_installed "$app"; then present+=("$app"); else ABSENT+=("$app"); fi
  done
  if [ "${#present[@]}" -gt 0 ]; then
    confirm "Remove: ${present[*]}?" || { echo "Cancelled."; return; }
    for app in "${present[@]}"; do
      echo "==> Removing: $app"
      if pm_remove "$app"; then
        REMOVED+=("$app"); log_action - "$app"
      else
        FAILED+=("$app")
      fi
    done
  fi
  print_report
  if [ "${#REMOVED[@]}" -gt 0 ]; then do_cleanup; fi
}

# --- packages added by this script and still installed ---
show_added() {
  local out d p
  if [ ! -s "$LOG_FILE" ]; then echo "Log is empty."; return; fi
  out=$(
    awk -F'\t' '$2=="+"{a[$3]=$1} $2=="-"{delete a[$3]} END{for(p in a) print a[p]"\t"p}' "$LOG_FILE" | sort |
    while IFS=$'\t' read -r d p; do
      is_installed "$p" && echo "  $p  ($d)"
    done
  )
  if [ -z "$out" ]; then
    echo "No packages added by the script."
  else
    echo "Added by the script and still installed:"
    echo "$out"
  fi
}

# --- Claude Code for Linux (the only curl in the script) ---
CLAUDE_CMD='set -o pipefail; curl -fsSL https://claude.ai/install.sh | bash'
CLAUDE_DESC="AI coding assistant from Anthropic that runs in the terminal."

install_claude() {
  local home="${LOG_HOME:-$HOME}"
  if [ "$CURL_OK" -eq 0 ]; then
    echo "CURL NOT SUPPORTED"
    return 1
  fi
  if [ "$EUID" -eq 0 ] && [ -z "$SUDO_USER" ]; then
    echo "Run as a regular user (not root): Claude Code installs to ~/.local/bin."
    return 1
  fi
  if [ -x "$home/.local/bin/claude" ] || command -v claude >/dev/null 2>&1; then
    echo "Claude Code is already installed."
    return 0
  fi
  command -v git >/dev/null 2>&1 || echo "Note: git not found, Claude Code does not work without it (menu item 1 → git)."
  echo "==> Installing Claude Code"
  if [ "$EUID" -eq 0 ]; then
    sudo -u "$SUDO_USER" -H bash -c "$CLAUDE_CMD"
  else
    bash -c "$CLAUDE_CMD"
  fi || {
    echo "  ✘ claude-code — $CLAUDE_DESC [download error: check your network and access to claude.ai]"
    return 1
  }
  echo "  ✔ claude-code — $CLAUDE_DESC"
  echo "Run: claude (if not found, add ~/.local/bin to PATH)."
}

# --- fish + ghostty: install and set as defaults ---
as_user() {  # run a command as the user (needed when launched via sudo)
  if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" -H env "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$SUDO_USER")/bus" "$@"
  else
    "$@"
  fi
}

detect_de() {
  if   pgrep -u "$USER_NAME" -x gnome-shell   >/dev/null 2>&1; then echo gnome
  elif pgrep -u "$USER_NAME" -x plasmashell   >/dev/null 2>&1; then echo kde
  elif pgrep -u "$USER_NAME" -x xfce4-session >/dev/null 2>&1; then echo xfce
  else echo "${XDG_CURRENT_DESKTOP:-unknown}"; fi
}

gs_append_path() {  # $1 = current gsettings list, $2 = path to append
  case "$1" in
    *"'$2'"*)        printf '%s' "$1" ;;
    "@as []"|"[]")   printf "['%s']" "$2" ;;
    *)               printf '%s' "${1%]}, '$2']" ;;
  esac
}

set_default_shell() {
  local fish_bin cur
  fish_bin=$(command -v fish) || { echo "fish not found."; return 1; }
  cur=$(getent passwd "$USER_NAME" | cut -d: -f7)
  if [ "$cur" = "$fish_bin" ]; then echo "fish is already the default shell."; return 0; fi
  # shellcheck disable=SC2016
  grep -qx "$fish_bin" /etc/shells 2>/dev/null ||
    run_sudo sh -c 'printf "%s\n" "$1" >> /etc/shells' _ "$fish_bin" || return 1
  if command -v usermod >/dev/null 2>&1; then
    run_sudo usermod -s "$fish_bin" "$USER_NAME"
  else
    run_sudo chsh -s "$fish_bin" "$USER_NAME"
  fi
}

set_terminal_gnome() {
  local base=org.gnome.settings-daemon.plugins.media-keys
  local path=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty/
  local cur new
  as_user gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty' &&
  as_user gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e' &&
  as_user gsettings set "$base" terminal "[]" &&
  cur=$(as_user gsettings get "$base" custom-keybindings) &&
  new=$(gs_append_path "$cur" "$path") &&
  as_user gsettings set "$base" custom-keybindings "$new" &&
  as_user gsettings set "$base.custom-keybinding:$path" name 'Ghostty' &&
  as_user gsettings set "$base.custom-keybinding:$path" command 'ghostty' &&
  as_user gsettings set "$base.custom-keybinding:$path" binding '<Primary><Alt>t'
}

set_terminal_xfce() {
  as_user xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/override -n -t bool -s true &&
  as_user xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Primary><Alt>t' -n -t string -s ghostty
}

set_terminal_kde() {
  local kw
  kw=$(command -v kwriteconfig6 || command -v kwriteconfig5) || return 1
  as_user "$kw" --file kdeglobals --group General --key TerminalApplication ghostty &&
  as_user "$kw" --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop &&
  echo "KDE: assign Ctrl+Alt+T manually (Settings → Shortcuts → Add command: ghostty)."
}

set_default_terminal() {
  local bin de
  bin=$(command -v ghostty) || { echo "ghostty not found, leaving the terminal unchanged."; return 1; }
  de=$(detect_de)
  case "$de" in
    gnome) set_terminal_gnome ;;
    xfce)  set_terminal_xfce ;;
    kde)   set_terminal_kde ;;
    *)     echo "Desktop environment '$de' is not supported: assign Ctrl+Alt+T to ghostty manually."; return 1 ;;
  esac || { echo "Failed to configure the terminal ($de)."; return 1; }
  # xdg-terminal-exec standard: ghostty first in the list
  # shellcheck disable=SC2016
  as_user bash -c 'f="$HOME/.config/xdg-terminals.list"; mkdir -p "${f%/*}"; grep -qsx "com.mitchellh.ghostty.desktop" "$f" || { touch "$f"; { echo com.mitchellh.ghostty.desktop; cat "$f"; } > "$f.new" && mv "$f.new" "$f"; }'
  # Debian/Ubuntu: x-terminal-emulator
  if [ "$PM" = "apt-get" ] && command -v update-alternatives >/dev/null 2>&1; then
    run_sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$bin" 50 &&
    run_sudo update-alternatives --set x-terminal-emulator "$bin"
  fi
  if [ "$de" = "kde" ]; then
    echo "Default terminal: ghostty (kde; Ctrl+Alt+T manually)."
  else
    echo "Default terminal: ghostty, Ctrl+Alt+T → ghostty ($de)."
  fi
}

setup_fish_ghostty() {
  if [ "$PM" = "brew" ]; then echo "This option is for Linux, not supported on macOS."; return 1; fi
  if [ "$EUID" -eq 0 ] && [ -z "$SUDO_USER" ]; then
    echo "Run as a regular user (or via sudo), not as plain root."
    return 1
  fi
  APPS=(fish ghostty)
  do_install
  if command -v fish >/dev/null 2>&1; then
    echo "==> fish → default shell"
    set_default_shell && echo "Default shell: fish (after you log in again)." ||
      echo "Failed to change the shell."
  fi
  if command -v ghostty >/dev/null 2>&1; then
    echo "==> ghostty → default terminal"
    set_default_terminal
  else
    echo "ghostty is not in $PM repositories. Options: https://ghostty.org/docs/install/binary"
  fi
}

pick_and_run() {
  APPS=()
  ask_packages
  if [ "${#APPS[@]}" -eq 0 ]; then echo "Nothing selected."; else "$1"; fi
}

menu() {
  local c
  while true; do
    echo
    echo "1) Install packages"
    echo "2) Remove packages"
    echo "3) Clean up unused dependencies"
    echo "4) Show packages added by the script"
    echo "5) Install Claude Code"
    echo "6) fish + ghostty (install and make default)"
    echo "0) Exit"
    read -r -p "Choice: " c || break
    case "$c" in
      1) pick_and_run do_install ;;
      2) pick_and_run do_remove ;;
      3) do_cleanup ;;
      4) show_added ;;
      5) install_claude ;;
      6) setup_fish_ghostty ;;
      0|q) break ;;
      *) echo "Invalid choice" ;;
    esac
  done
}

# --- main ---
[ "$NEED_SUDO" -eq 1 ] && init_sudo

if [ "$1" = "-r" ] || [ "$1" = "--remove" ]; then
  shift
  add_packages "$*"
  if [ "${#APPS[@]}" -eq 0 ]; then echo "Nothing selected."; exit 0; fi
  do_remove
elif [ "$1" = "--setup" ]; then
  setup_fish_ghostty
elif [ "$#" -gt 0 ]; then
  add_packages "$*"
  if [ "${#APPS[@]}" -eq 0 ]; then echo "Nothing selected."; exit 0; fi
  do_install
else
  menu
fi

[ "${#FAILED[@]}" -eq 0 ]
