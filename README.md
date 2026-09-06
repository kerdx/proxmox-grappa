# Grappa Proxmox Helper-Script

Development version of a Proxmox VE Helper-Script for
[grappa-irc](https://github.com/vjt/grappa-irc). New community scripts are
developed in ProxmoxVED first; this code is not yet submitted or production
tested.

## Development test

The repository contains the Grappa-specific scripts; the shared ProxmoxVED
framework is loaded from its official source. From a disposable Proxmox node,
run the following as `root`:

```sh
var_phx_host=192.168.1.50 \
var_grappa_version=v1.5.1 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kerdx/proxmox-grappa/main/ct/grappa.sh)"
```

Replace the address with the LXC IP or public hostname. To test another branch
of this repository, export `GRAPPA_SCRIPT_URL` before running the command:

```sh
export GRAPPA_SCRIPT_URL="https://raw.githubusercontent.com/kerdx/proxmox-grappa/<branch>"
```

## What it deploys

- An unprivileged Debian 13 LXC with Docker, nesting, keyctl and mknod.
- Grappa `v1.5.1` by default, pinned both for the bootstrap code and the OCI
  image. A different valid release tag can be supplied through
  `var_grappa_version`.
- The application state in the `grappa-data` Docker volume and its production
  environment in `/opt/grappa/grappa.env`.
- Helper-Script state in `/opt/grappa/grappa-helper.env`, including the
  installed release and public Docker bind.

FUSE is disabled by default. arm64 is deliberately blocked until this exact
Docker-in-LXC deployment has been tested on Proxmox VE arm64.

## Network and hostname

The web UI listens on `http://<LXC-IP>:4000`. If **Public Hostname** is left
blank, the installer uses the LXC IPv4 address for `PHX_HOST`, suitable for
LAN-only access.

For an HTTPS reverse proxy, set `var_phx_host` to the exact DNS hostname before
installation. This value is used by Grappa for origin checks and generated
links. After deployment, change `PHX_HOST` in `/opt/grappa/grappa.env` if the
public hostname changes, then run `update` in the LXC to recreate the service.

## First administrator

From the LXC shell, create the first administrator without placing a password
on the command line:

```sh
docker exec -it grappa bin/grappa create-user admin --admin
```

The command prompts for the password.

## Operations

- Logs: `docker logs -f grappa`
- Health: `docker exec grappa curl -fsS http://localhost:4000/healthz`
- Manual application update: run `update` from the LXC shell. It reads the
  latest stable GitHub release, performs the update, and fails if Grappa is not
  healthy afterward.
- Stop temporarily: `docker stop grappa`

## Backup and restore

A standard Proxmox `vzdump` backup of the LXC includes Docker's local volume
and both `/opt/grappa` environment files. Keep a separate protected copy of
`GRAPPA_ENCRYPTION_KEY` from `/opt/grappa/grappa.env`: losing it makes stored
upstream IRC credentials unrecoverable.

For a manual, application-consistent backup, stop Grappa before copying its
volume. Test a restore on a non-production LXC before relying on the backup.
