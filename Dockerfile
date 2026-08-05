# syntax=docker/dockerfile:1

# UniFi Video 3.5.2 is a 2016 build packaged for Ubuntu 12.04. Its dependencies are
# "java7-runtime-headless", "mongodb-server (>= 2.0.4)" and "libc6 (>= 2.15)", none of
# which exist in a current Debian release, so the runtime stays on jessie. What has been
# modernised here is the *build*: it works with current Docker/BuildKit, pulls its apt
# packages from the Debian archive (jessie left the mirrors in 2020), verifies the
# vendor artifact by checksum, and can build fully offline from ./cache.
#
# When UniFi Video is upgraded to 3.10.13 this base should be revisited — later 3.10.x
# releases run on Java 8 and can move to a newer Debian.

ARG BASE_IMAGE=debian:jessie

ARG UNIFI_VIDEO_VERSION=3.5.2
ARG UNIFI_VIDEO_DEB=unifi-video_3.5.2~Ubuntu12.04_amd64.deb
ARG UNIFI_VIDEO_SHA256=2bd95a03f16ae87bbb4a804b607a37132b84cb75ef98132ad411ae007d114ede


# --- fetch stage -------------------------------------------------------------------
# Downloading on a modern base keeps the TLS stack and CA bundle out of the jessie
# layer, which can no longer negotiate with much of the current web.
FROM debian:bookworm-slim AS fetch

ARG UNIFI_VIDEO_VERSION
ARG UNIFI_VIDEO_DEB
ARG UNIFI_VIDEO_SHA256
ARG UNIFI_VIDEO_URL=https://dl.ubnt.com/firmwares/unifi-video/${UNIFI_VIDEO_VERSION}/${UNIFI_VIDEO_DEB}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*

# Ubiquiti has discontinued UniFi Video, so the download may disappear without notice.
# Drop a copy of the .deb in ./cache to build without reaching the vendor at all.
COPY cache/ /cache/

RUN set -eux; \
    if [ -f "/cache/${UNIFI_VIDEO_DEB}" ]; then \
        echo "using cached ${UNIFI_VIDEO_DEB}"; \
        cp "/cache/${UNIFI_VIDEO_DEB}" /unifi-video.deb; \
    else \
        echo "downloading ${UNIFI_VIDEO_URL}"; \
        curl -fL --retry 3 --retry-delay 5 -o /unifi-video.deb "${UNIFI_VIDEO_URL}"; \
    fi; \
    echo "${UNIFI_VIDEO_SHA256}  /unifi-video.deb" | sha256sum -c -


# --- runtime stage -----------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG UNIFI_VIDEO_VERSION

LABEL org.opencontainers.image.title="unifi-video" \
      org.opencontainers.image.description="UniFi Video controller" \
      org.opencontainers.image.authors="Ilias Kiourktsidis <ekiourk@gmail.com>" \
      org.opencontainers.image.source="https://github.com/ekiourk/docker-unifi-video" \
      org.opencontainers.image.version="${UNIFI_VIDEO_VERSION}"

# Build-time only, so it does not leak into the running container's environment.
ARG DEBIAN_FRONTEND=noninteractive

# jessie is off the mirrors and its Release files are long expired; point apt at the
# archive over plain HTTP and stop it rejecting the stale signatures.
RUN set -eux; \
    { \
      echo 'deb [trusted=yes] http://archive.debian.org/debian jessie main'; \
      echo 'deb [trusted=yes] http://archive.debian.org/debian-security jessie/updates main'; \
    } > /etc/apt/sources.list; \
    { \
      echo 'Acquire::Check-Valid-Until "false";'; \
      echo 'Acquire::AllowInsecureRepositories "true";'; \
    } > /etc/apt/apt.conf.d/99archive

COPY --from=fetch /unifi-video.deb /tmp/unifi-video.deb

# Dependencies come straight from the .deb's own Depends field. procps is the one
# addition — the entrypoint needs pgrep to wait for a clean shutdown.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        adduser \
        jsvc \
        lsb-release \
        mongodb-server \
        openjdk-7-jre-headless \
        procps \
        psmisc \
        sudo; \
    dpkg -i /tmp/unifi-video.deb; \
    rm -f /tmp/unifi-video.deb; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 7080 web UI, 7443 HTTPS UI, 7445-7447 streaming, 6666 camera stream, 10001/udp
# discovery. Documentation only — the controller is deployed with host networking.
EXPOSE 7080 7443 7445 7446 7447 6666 10001/udp

VOLUME ["/var/lib/unifi-video", "/var/log/unifi-video"]

# Generous start period: on a large recordings database the controller takes minutes
# to come up before it will accept connections.
HEALTHCHECK --interval=60s --timeout=10s --start-period=300s --retries=3 \
    CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/7080' || exit 1

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
