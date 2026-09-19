# installer-beginners

Simple package installer for Linux beginners: one interface for `apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`, `xbps` and `brew`.

## Features

- Install and remove several packages at once
- The sudo password is entered once
- Report: what was installed, what was already there, what failed
- Cleanup of unused dependencies
- Log of packages added by the script
- Optional: Claude Code, fish + ghostty as defaults

## Installation

```bash
# Arch / AUR
yay -S installer-beginners

# From source
git clone https://github.com/S00what/installer-beginners
cd installer-beginners
sudo make install
```

## Usage

```bash
installer-beginners                 # menu
installer-beginners git vim         # install
installer-beginners -r vim htop     # remove
installer-beginners --setup         # fish + ghostty as defaults
installer-beginners --help
```

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
