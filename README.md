# Components for Gershwin [![](https://api.cirrus-ci.com/github/probonopd/gershwin-components.svg)](https://cirrus-ci.com/github/probonopd/gershwin-components)

This repository contains several components such as applications and preference panes designed for FreeBSD systems running the Gershwin desktop environment but potentially also useful elsewhere.

See the `README.md` in each respective directory for detailed information.

https://api.cirrus-ci.com/v1/artifact/github/probonopd/gershwin-components/data/packages/FreeBSD:14:amd64/index.html

## Building

For now, the basic Gershwin libraries are incompatible with their GNUstep counterparts. While the objective is to fix that in the future, for now we need to __MAKE SURE__ that `/usr/local/GNUstep` does __NOT__ exist.

## Installation

Install https://download.ghostbsd.org/releases/amd64/latest/GhostBSD-25.02-R14.3p2-GERSHWIN.iso, then:

```
su

cat > /usr/local/etc/pkg/repos/Gershwin-components.conf <<\EOF
Gershwin-components: {
  url: "https://api.cirrus-ci.com/v1/artifact/github/gershwin-desktop/gershwin-components/data/packages/FreeBSD:14:amd64/",
  mirror_type: "http",
  enabled: yes
}
EOF

sudo pkg install -y gershwin-components
```

Then, add near the top of `/usr/local/bin/gershwin-x11`:

```
export SUDO_ASKPASS=$(which SudoAskPass)
```
