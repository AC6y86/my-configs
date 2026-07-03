# my-configs

Personal dotfiles and helper scripts for Meta engineering plus some personal
infra, spanning four environments: **WSL2 (Windows 11), macOS, native Linux
(Fedora), and the Windows/PowerShell side**. Most files target one or two of
these; see `CLAUDE.md` for the full layout and the per-platform split.

## Setup — WSL / native Linux

```bash
# .bashrc (symlink it in)
mv ~/.bashrc ~/.bashrc_bak 2>/dev/null
ln -s ~/my-configs/.bashrc ~/.bashrc

# save git credentials
git config --global credential.helper store
```

Native Linux / GNOME only — DevTerm launcher (ptyxis + tmux): see
`meta/CreateDevTerm-linux.md`.

WSL only — symlink the Windows home so scripts can reach it:

```bash
cd ~/
ln -s /mnt/c/Users/joepaley/ joepaley
```

## Setup — Windows side (PowerShell)

```powershell
# AutoHotkey (Emacs-style global keybindings, autostarts on login)
windows\install-autohotkey.ps1

# Windows Terminal + PowerShell profile (match WSL/bash behavior)
windows\install-windows-configs.ps1
```

## Setup — macOS

- Native `fb-sks-agent` provides the SSH cert; no bridge needed.
- DevTerm launcher (iTerm2 + tmux): see `meta/CreateDevTerm-mac.md`.
- Mount the devserver home over sshfs: `meta/devmount.sh mount`.
