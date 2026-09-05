#!/bin/bash
# Plain-docker equivalent of docker-compose.yml, for hosts without compose installed.
set -euo pipefail

CONTAINER="unifi-video"
IMAGE="ekiourk/unifi-video:${UNIFI_VIDEO_VERSION:-3.5.2}"
DATA_DIR="${DATA_DIR:-/var/lib/unifi-video}"
LOG_DIR="${LOG_DIR:-/var/log/unifi-video}"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "$CONTAINER does not exist. Starting a new one."
    exec docker run -d -it \
        --name="$CONTAINER" \
        --privileged \
        --security-opt label=disable \
        --net=host \
        --restart=unless-stopped \
        --stop-timeout=120 \
        -v "$DATA_DIR:/var/lib/unifi-video" \
        -v "$LOG_DIR:/var/log/unifi-video" \
        "$IMAGE"
fi

if [ "$(docker inspect --format='{{.State.Running}}' "$CONTAINER")" = "false" ]; then
    echo "Starting existing $CONTAINER."
    exec docker start "$CONTAINER"
fi

echo "$CONTAINER is already running."
