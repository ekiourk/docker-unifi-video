#!/bin/bash
CONTAINER="unifi-video"
VOLUME_DIR=/var

RUNNING=$(docker inspect --format="{{ .State.Running }}" $CONTAINER 2> /dev/null)

if [ $? -eq 1 ]; then
  echo "$CONTAINER does not exist. Starting a new one."
  docker run -it -d \
    --name=$CONTAINER \
    --privileged \
    --net=host \
    -v $VOLUME_DIR/lib/unifi-video:/var/lib/unifi-video \
    -v $VOLUME_DIR/log/unifi-video:/var/log/unifi-video \
    ekiourk/unifi-video:3.1.2
  exit 0
fi

if [ "$RUNNING" == "false" ]; then
  echo "Starting existing $CONTAINER."
  docker start $CONTAINER
  exit 0
fi

echo "$CONTAINER is already running."
exit 0
