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
