<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# QSO Graph packages

Install QSO Graph's programs on Linux with `apt` or `dnf`, and keep them up to date with the rest of
your system. Every package and every repository index is signed with QSO Graph's release key, so your
package manager checks that what it installs is what QSO Graph released.

| Package | What it is |
|---|---|
| `qso-graph-desktop` | QSO Graph Desktop, the application |
| `qso-graph-trust` | `qg-trust`: sign and upload your logs to ARRL's Logbook of The World, with your key in your computer's credential store |

## Debian, Ubuntu

```sh
sudo curl -fsSL -o /usr/share/keyrings/qso-graph.gpg https://packages.qso-graph.net/qso-graph.gpg
echo "deb [signed-by=/usr/share/keyrings/qso-graph.gpg] https://packages.qso-graph.net/apt stable main" | sudo tee /etc/apt/sources.list.d/qso-graph.list
sudo apt update
sudo apt install qso-graph-trust        # or qso-graph-desktop
```

## Fedora, RHEL, Rocky

```sh
sudo curl -fsSL -o /etc/yum.repos.d/qso-graph.repo https://packages.qso-graph.net/qso-graph.repo
sudo dnf install qso-graph-trust        # or qso-graph-desktop
```

dnf asks you to accept the key the first time. Its fingerprint is
`E4EC 9751 F1AA 66AB 2BA5  08EF 0410 96B9 A6EB D256`.

Already set up for QSO Graph Desktop? You have this repository: `apt install qso-graph-trust` or
`dnf install qso-graph-trust` works as it is.

## How it is built

[`.github/workflows/packages.yml`](.github/workflows/packages.yml) builds the repositories from each
product's published releases ([`products.tsv`](products.tsv)), checks every file against its release's
`SHA256SUMS.txt`, signs and indexes them ([`scripts/linux-repos.sh`](scripts/linux-repos.sh)), uploads
them and checks each one as served. Nothing is edited by hand.

GPL-3.0-or-later.
