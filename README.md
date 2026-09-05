# docker-unifi-video

Docker image for the UniFi Video controller.

> **UniFi Video is discontinued.** Ubiquiti ended the product; 3.10.13 was the final
> release and all cloud operations have been shut down. This image exists to keep an
> existing installation running on maintained infrastructure, not as a long-term
> platform. Pinned to **3.5.2** until camera firmware compatibility with 3.10.13 has
> been verified.

## Why the base image is still Debian jessie

The 3.5.2 package declares `java7-runtime-headless`, `mongodb-server (>= 2.0.4)` and
`libc6 (>= 2.15)`. No current Debian release ships Java 7 or a `mongodb-server` package,
so the runtime stays on jessie. The *build* is what has been modernised:

- builds with current Docker / BuildKit
- apt is pointed at `archive.debian.org`, since jessie left the mirrors in 2020 and its
  `Release` files are expired
- the vendor `.deb` is downloaded on a modern base in a separate stage, so no TLS or CA
  work happens on jessie, and it is verified against a pinned SHA256
- the build works offline from `./cache`
- graceful shutdown, so the bundled mongod is never hard-killed
- the bundled JNI libraries are patched so they load on a current kernel, and the
  `unifi-video` uid is pinned so it does not drift between builds

When moving to 3.10.13, revisit the base — later 3.10.x releases run on Java 8 and can
sit on a newer Debian.

## Two things the build has to patch

Both of these are invisible until the container meets a current kernel or an existing
installation, and both fail in ways that do not obviously point at their cause.

**The JNI libraries demand an executable stack.** `libubnt_webrtc_jni.so`,
`libubnt_avutils_jni.so` and `libubnt_mp4parser_jni.so` were linked without a
`.note.GNU-stack` section, so the linker marked `PT_GNU_STACK` as `RWE`. When the JVM
`dlopen()`s them, glibc tries to `mprotect` the thread stack executable and current
kernels refuse:

```
libubnt_webrtc_jni.so: cannot enable executable stack as shared object requires:
Permission denied
```

The web UI then fails to load. Kernel 4.4 tolerated this; later ones do not. The
libraries do not execute from the stack — the flag is a build artifact — so
`clear-execstack.py` clears it, one byte per file, in a separate `bookworm-slim` stage.
The build fails if any `RWE` flag survives. It is a separate stage because the fix needs
python3 and jessie should stay minimal; `execstack` is no longer packaged in Debian and
bookworm's `patchelf` (0.14) predates `--clear-execstack`.

**The `unifi-video` uid drifts between builds.** The vendor postinst creates the account
with plain `adduser --system`, so it gets whatever id Debian has free at build time —
which changes whenever the package list does. That silently breaks an existing
installation: the recordings on disk carry the old numeric owner, and the postinst only
repairs ownership to `-maxdepth 3`, so anything deeper in
`videos/<camera>/<year>/<month>/<day>/` keeps the old uid and the controller cannot write
there. `UNIFI_VIDEO_UID` and `UNIFI_VIDEO_GID` pin it to **106:109**, which is what the
2020 build allocated. Pre-creating the account makes the postinst's `create_user()` skip
its own `adduser`. Override the build args if you are migrating data that carries
different ids — check with `stat -c '%u:%g' /var/lib/unifi-video/db`.

## Build

```shell
docker build -t ekiourk/unifi-video:3.5.2 .
```

Ubiquiti may remove the download at any time. To build without touching the vendor, put
the package in `./cache` first:

```shell
curl -fL -o cache/unifi-video_3.5.2~Ubuntu12.04_amd64.deb \
  https://dl.ubnt.com/firmwares/unifi-video/3.5.2/unifi-video_3.5.2~Ubuntu12.04_amd64.deb
```

`cache/*.deb` is gitignored. If you deliberately change versions, update
`UNIFI_VIDEO_VERSION`, `UNIFI_VIDEO_DEB` and `UNIFI_VIDEO_SHA256` in the Dockerfile
together — the checksum is a pin, and a mismatch is meant to fail the build.

## Run

```shell
docker compose up -d
```

or, without compose:

```shell
./run.sh
```

Both use host networking and bind-mount `/var/lib/unifi-video` (recordings **and** the
MongoDB database) and `/var/log/unifi-video` from the host.

## Running under Podman (Quadlet)

`quadlet/` holds a [Podman Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
unit, which is the systemd-native equivalent of the compose file above. Quadlet reads
`.container` files at boot and generates real systemd services from them.

**Requirements**

- **podman >= 4.4** — Quadlet was introduced in 4.4. Note Debian 12 ships 4.3 and is
  therefore too old; Fedora 38+, RHEL/CentOS 9.3+, Ubuntu 24.04, openSUSE MicroOS 6.x
  and Arch are all fine.
- systemd, and the image built locally (see **Build** above)

**Install**

```shell
sudo ./quadlet/install-quadlet.sh
DRY_RUN=1 ./quadlet/install-quadlet.sh          # preview the generated unit, change nothing
```

The paths are parameters, defaulting to the layout this is deployed on:

| Variable | Default | What it is |
|---|---|---|
| `DATA_DIR` | `/var/lib/unifi-nvr/data` | configuration, keystore, and the bundled MongoDB — small, worth putting on a checksumming filesystem |
| `VIDEO_DIR` | `/var/mnt/storage/unifi-nvr/videos` | the recordings — give this its own filesystem |
| `LOG_DIR` | `/var/log/unifi-nvr` | controller logs |
| `IMAGE` | `localhost/ekiourk/unifi-video:3.5.2` | the locally built image |
| `UNIT_DIR` | `/etc/containers/systemd` | where Quadlet looks for unit files |

```shell
sudo DATA_DIR=/srv/nvr/data VIDEO_DIR=/mnt/bulk/videos ./quadlet/install-quadlet.sh
```

`/var/mnt` in the default is an openSUSE MicroOS convention — `/mnt` is part of the
read-only root there. On other distributions `/mnt/...` or `/srv/...` is more natural.

**Why the recordings are a separate volume**

`VIDEO_DIR` is bind-mounted *inside* `DATA_DIR`, at `/var/lib/unifi-video/videos`. Podman
orders bind mounts by path depth, so the deeper one wins and the controller still sees a
single tree at `/var/lib/unifi-video` — while 24/7 video goes to its own filesystem. That
lets the recordings sit on XFS (no copy-on-write, no snapshot growth) with the database
on something checksummed, without the controller knowing anything about it.

**Why there is an installer rather than a file to copy**

The unit needs `Requires=`/`After=` on the systemd mount unit for the recordings
filesystem, and systemd derives that name from the path — `/var/mnt/storage` becomes
`var-mnt-storage.mount`. Get it wrong and nothing complains: the ordering silently does
not apply, and the controller can start before the filesystem is mounted and write video
into the empty mount point on the root filesystem. The installer works the name out with
`systemd-escape -p --suffix=mount`, and omits the dependency entirely when the recordings
are on the root filesystem.

**Ports**

The container uses host networking, so the ports below have to be open on the host
firewall. The installer prints the `firewall-cmd` invocation.

**Note on the image reference**

`IMAGE` defaults to `localhost/...` deliberately. The `ekiourk/unifi-video:3.5.2` tag on
Docker Hub was pushed in 2017 and predates the fixes in this repository, so a container
started from it dies on a current runtime. The `localhost/` prefix also means podman
cannot silently pull it.

## Shutting down

Always stop it with `docker compose down` or `docker stop` — never `docker kill`. The
controller runs its own mongod over the recordings database and needs time to flush and
release its lock. The compose file allows 120s (`--stop-timeout=120` in `run.sh`); the
entrypoint traps the signal, stops the service and waits for the processes to exit.

## Ports

| Port | Purpose |
|---|---|
| 7080 | web UI |
| 7443 | HTTPS web UI |
| 7445–7447 | streaming |
| 6666 | camera stream |
| 10001/udp | camera discovery |
