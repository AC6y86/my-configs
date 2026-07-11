#!/usr/bin/env python3
import subprocess
import sys
import os
import json

# Store the previous hostname in /tmp, but usernames persistently in home dir
HOSTNAME_FILE = "/tmp/local_servers_hostname"
USERNAME_CACHE_FILE = os.path.expanduser("~/.ssh_local_usernames.json")

# Hostname to IP mappings for direct connections
HOSTNAME_MAP = {
    "devserver": "164.92.107.136",
}

# Default usernames for specific hostnames
DEFAULT_USERNAMES = {
    "devserver": "joepaley",
    "statfink": "joepaley",
}

def get_hostname():
    """Get the hostname from the command line or the previous hostname"""
    if len(sys.argv) > 1:
        return sys.argv[1]
    try:
        with open(HOSTNAME_FILE, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        raise ValueError("No hostname provided and no previous hostname found")

def resolve_hostname(hostname):
    """Try to resolve the hostname by checking direct mappings or appending .joepaley and .joepaley.com"""
    # Check if hostname has a direct IP mapping
    if hostname in HOSTNAME_MAP:
        return HOSTNAME_MAP[hostname]

    hostnames_to_try = [f"{hostname}.joepaley", f"{hostname}.joepaley.com"]
    for h in hostnames_to_try:
        try:
            subprocess.run(["ping", "-c", "1", h], check=True)
            return h
        except subprocess.CalledProcessError:
            pass
    raise ValueError(f"Unable to resolve hostname {hostname}")

def load_username_cache():
    """Load the username cache from disk"""
    try:
        with open(USERNAME_CACHE_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_username_cache(cache):
    """Save the username cache to disk"""
    try:
        with open(USERNAME_CACHE_FILE, "w") as f:
            json.dump(cache, f)
    except Exception as e:
        print(f"Warning: Failed to save username cache: {e}")

def get_username(hostname):
    """Get the username from cache for this hostname or prompt the user"""
    cache = load_username_cache()

    if hostname in cache:
        print(f"Using cached username for {hostname}: {cache[hostname]}")
        return cache[hostname]

    # Check if there's a default username for this hostname
    if hostname in DEFAULT_USERNAMES:
        username = DEFAULT_USERNAMES[hostname]
        print(f"Using default username for {hostname}: {username}")
        return username

    print("Select a username:")
    print("1. root")
    print("2. joepaley")
    choice = input("Enter your choice (1/2): ")
    if choice == "1":
        return "root"
    elif choice == "2":
        return "joepaley"
    else:
        print("Invalid choice. Exiting.")
        sys.exit(1)

def connect_to_server(username, hostname):
    """Connect to the server via SSH"""
    resolved_hostname = resolve_hostname(hostname)

    def add_ssh_config_entry(original, resolved, username):
        ssh_config_path = os.path.expanduser("~/.ssh/config")
        entry = f"Host {original}\n    HostName {resolved}\n    User {username}\n"
        try:
            # Check if entry already exists
            if os.path.exists(ssh_config_path):
                with open(ssh_config_path, 'r') as f:
                    config = f.read()
                    if f"Host {original}" in config:
                        print(f"SSH config already has entry for {original}.")
                        return
            # Append the entry
            with open(ssh_config_path, 'a') as f:
                f.write('\n' + entry)
            print(f"Added SSH config entry for {original} -> {resolved} with user {username}.")
        except Exception as e:
            print(f"Error updating SSH config: {e}")
    
    def cache_username(username, hostname):
        """Cache the username after successful connection for this hostname"""
        cache = load_username_cache()
        cache[hostname] = username
        save_username_cache(cache)

    target = f"{username}@{resolved_hostname}"

    # Probe auth non-interactively so the username can be cached before the
    # interactive session starts — Ctrl-C'ing out of the session must not lose it
    probe = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", target, "true"]
    if subprocess.run(probe).returncode != 0:
        print(f"Key auth failed for {target}")
        print("Running ssh-copy-id to copy public key...")
        subprocess.run(["ssh-copy-id", target], check=True)

    cache_username(username, hostname)
    add_ssh_config_entry(hostname, resolved_hostname, username)
    try:
        subprocess.run(["/home/joepaley/my-configs/sync_ssh_to_windows_symlink.sh"], check=True)
        print("Called sync_ssh_to_windows_symlink.sh after successful SSH and config update.")
    except Exception as e:
        print(f"Failed to call sync_ssh_to_windows_symlink.sh: {e}")

    result = subprocess.run(["ssh", "-o", "BatchMode=yes", target])
    if result.returncode != 0:
        print(f"SSH session exited with code {result.returncode}")

def main():
    try:
        hostname = get_hostname()
        with open(HOSTNAME_FILE, "w") as f:
            f.write(hostname)
        username = get_username(hostname)
        connect_to_server(username, hostname)
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()