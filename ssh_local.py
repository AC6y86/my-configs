import subprocess
import sys
import os

# Store the previous username and hostname in /tmp
USERNAME_FILE = "/tmp/local_servers_username"
HOSTNAME_FILE = "/tmp/local_servers_hostname"

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
    """Try to resolve the hostname by appending .joepaley and .joepaley.com"""
    hostnames_to_try = [f"{hostname}.joepaley", f"{hostname}.joepaley.com"]
    for h in hostnames_to_try:
        try:
            subprocess.run(["ping", "-c", "1", h], check=True)
            return h
        except subprocess.CalledProcessError:
            pass
    raise ValueError(f"Unable to resolve hostname {hostname}")

def get_username():
    """Get the username from the previous run or prompt the user"""
    try:
        with open(USERNAME_FILE, "r") as f:
            previous_username = f.read().strip()
    except FileNotFoundError:
        previous_username = None

    if len(sys.argv) == 1 and previous_username:
        print(f"Using previous username: {previous_username}")
        print(f"Using previous hostname: {get_hostname()}")
        return previous_username

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
    try:
        # Attempt to SSH into the server
        subprocess.run(["ssh", "-o", "BatchMode=yes", f"{username}@{resolved_hostname}"], check=True)
    except subprocess.CalledProcessError as e:
        if e.returncode == 255:  # Permission denied
            print(f"Permission denied for {username}@{resolved_hostname}")
            print("Running ssh-copy-id to copy public key...")
            subprocess.run(["ssh-copy-id", f"{username}@{resolved_hostname}"], check=True)
            print("Trying SSH again...")
            subprocess.run(["ssh", "-o", "BatchMode=yes", f"{username}@{resolved_hostname}"], check=True)
        else:
            print(f"Failed to connect to {username}@{resolved_hostname}")

def main():
    try:
        hostname = get_hostname()
        with open(HOSTNAME_FILE, "w") as f:
            f.write(hostname)
        username = get_username()
        with open(USERNAME_FILE, "w") as f:
            f.write(username)
        connect_to_server(username, hostname)
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()