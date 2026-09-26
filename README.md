# deSEC Dynamic DNS updater

A small, hardened Dynamic DNS client for Linux using a deSEC DNS API token and
a systemd timer.

It:

- obtains the public IPv4 address from `api.ipify.org`
- reads the current apex `A` record from `ns1.desec.io`
- updates the deSEC apex `A` record only when the address changes
- stores the API token in `/etc/dyndns/credentials` with mode `0600`
- runs as a root-owned systemd service
- logs through the systemd journal
- is safe to re-run for upgrades without overwriting existing credentials
- supports uninstalling without automatically deleting the credentials

## Requirements

Designed for Ubuntu/Debian-like Linux systems with:

- `systemd`
- `bash`
- `curl`
- `dig` from `dnsutils`

The installer uses `apt-get` when required dependencies are missing.

## Installation

Clone the repository and run:

```bash
git clone https://github.com/YOUR-USER/desec-dyndns.git
cd desec-dyndns
sudo ./install.sh
```

The installer asks for:

- DNS domain
- deSEC API token
- check interval

The token is never written to the repository.

## One-line bootstrap installation

A fresh Linux machine can bootstrap it without first cloning it manually:

```bash
curl -fsSL https://raw.githubusercontent.com/TitusMihu/deSEC-dynDNS/refs/heads/main/bootstrap.sh | sudo bash
```

The bootstrapper installs Git if necessary, clones the repository into `/opt/dyndns-desec`, and runs the version-controlled `install.sh`. Existing credentials are preserved by the installer when it is re-run.

For a reproducible installation, use a release tag:

```bash
DYNDNS_REPO=https://github.com/TitusMihu/dyndns-desec.git \
DYNDNS_REF=v1.0.0 \
curl -fsSL https://raw.githubusercontent.com/TitusMihu/deSEC-dynDNS/refs/heads/main/bootstrap.sh | sudo bash
```

## deSEC token

For best security, create a dedicated deSEC token for this updater and restrict
its RRset permissions through deSEC's token-policy API.

The updater itself only needs a token capable of modifying the intended apex
`A` record.

If you use an unrestricted token, the updater still works, but a scoped token
is strongly recommended.

## What gets installed

```text
/usr/local/sbin/update-dns-apex.sh
/etc/dyndns/credentials
/etc/systemd/system/dyndns.service
/etc/systemd/system/dyndns.timer
```

The credentials file is:

```text
root:root 0600
```

The updater and systemd unit are root-owned.

## Timer

The default interval is 5 minutes.

Check the timer:

```bash
systemctl list-timers dyndns.timer
```

Check its status:

```bash
systemctl status dyndns.timer
```

Run the service immediately:

```bash
sudo systemctl start dyndns.service
```

## Logs

Show recent executions:

```bash
journalctl -u dyndns.service -n 50 --no-pager
```

Follow live:

```bash
journalctl -u dyndns.service -f
```

## Configuration

The credentials file contains:

```ini
DNSDOMAIN=mydomain.com
TOKEN=your_desec_token
```

The installer also writes:

```ini
IP_URL=https://api.ipify.org
DNS_SERVER=ns1.desec.io
```

Do not commit this file.

## Updating

Pull the new version and run the installer again:

```bash
git pull
sudo ./install.sh
```

Existing credentials are preserved unless you explicitly choose to replace them.

## Uninstalling

```bash
sudo ./uninstall.sh
```

The uninstaller removes the updater, service and timer.

It asks separately whether `/etc/dyndns/credentials` should be deleted.

## Security notes

Do not commit an API token.

If a real token has ever been exposed publicly, revoke it and create a new
one.

The systemd service uses:

- `NoNewPrivileges=yes`
- `PrivateTmp=yes`
- `ProtectSystem=strict`
- `ProtectHome=yes`
- `ProtectKernelTunables=yes`
- `ProtectKernelModules=yes`
- `ProtectControlGroups=yes`

The updater is installed outside `/home`, allowing `ProtectHome=yes` to remain
enabled.

## License

MIT. See `LICENSE`.
