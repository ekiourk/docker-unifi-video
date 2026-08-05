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

When moving to 3.10.13, revisit the base — later 3.10.x releases run on Java 8 and can
sit on a newer Debian.

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
