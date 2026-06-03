# Troubleshooting devssh.sh

## How it works

`devssh.sh` uses WSL's native `ssh` with Meta's certificate-based auth. The chain is:

```
WSL ssh -> SSH_AUTH_SOCK (Unix socket) -> socat -> npiperelay.exe -> Windows fb-sks-agent named pipe -> Meta cert
```

The `.bashrc` snippet starts the socat/npiperelay bridge on shell init. The `~/.ssh/config` must include `config-certs` to use the certificate and agent.

## Common errors

### `Permission denied (publickey)`

SSH is using a plain key instead of the Meta certificate. Check:

1. **`~/.ssh/config` missing `Include config-certs`** — Add `Include config-certs` as the first line of `~/.ssh/config`. Without it, SSH doesn't know to use `fb-sks-agent` or the certificate identity.

2. **npiperelay bridge not running** — Run `ssh-add -l`. If it says "communication with agent failed" or "could not open", the bridge is down. Check:
   - `npiperelay.exe` exists at `~/my-configs/bin/npiperelay.exe`
   - `socat` is installed (`sudo apt install socat`)
   - Restart the bridge: `source ~/.bashrc` or open a new terminal

3. **`npiperelay.exe` missing** — Download from https://github.com/jstarks/npiperelay/releases and place in `~/my-configs/bin/`:
   ```powershell
   # From PowerShell
   Invoke-WebRequest -Uri "https://github.com/jstarks/npiperelay/releases/download/v0.1.0/npiperelay_windows_amd64.zip" -OutFile "$env:TEMP\npiperelay.zip"
   Expand-Archive "$env:TEMP\npiperelay.zip" "$env:TEMP\npiperelay" -Force
   Copy-Item "$env:TEMP\npiperelay\npiperelay.exe" "$env:USERPROFILE\my-configs\bin\"
   ```

### `cannot execute binary file: Exec format error`

WSL interop is disabled. WSL can't run Windows `.exe` files (including `npiperelay.exe`).

Fix: restart WSL from PowerShell:
```powershell
wsl --shutdown
```
Then open a new WSL terminal. Interop re-enables on restart.

If it persists, manually re-register:
```bash
sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'
```

Check `/etc/wsl.conf` does not contain `interop=false`.

### `SSH_AUTH_SOCK not set`

The `.bashrc` bridge snippet didn't run. Either:
- Run `source ~/.bashrc`
- Open a new terminal
- Check that `~/.bashrc` contains the socat/npiperelay block (see `CreateDevTerm.md`)

### `Authenticated with partial success` then `Permission denied (keyboard-interactive)`

The certificate worked but the devvm requires two-factor auth (Duo push or TOTP). This is expected — you must run `devssh.sh` interactively so you can respond to the 2FA prompt. It cannot be run from a non-interactive shell.

## Diagnostic commands

```bash
# Check if bridge is running
ps aux | grep socat

# Check if agent socket exists
ls -la ~/.ssh/agent.sock

# Check if agent can list identities
export SSH_AUTH_SOCK=~/.ssh/agent.sock
ssh-add -l

# Verbose SSH to see auth details
ssh -vvv joepaley@devvm7002.scu0.facebook.com

# Check WSL interop
file /mnt/c/Windows/System32/cmd.exe
/mnt/c/Windows/System32/cmd.exe /c "echo works"
```
