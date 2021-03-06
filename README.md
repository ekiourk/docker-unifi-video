# docker-unifi-video
[![](https://badge.imagelayers.io/ekiourk/unifi-video:latest.svg)](https://imagelayers.io/?images=ekiourk/unifi-video:latest 'Get your own badge on imagelayers.io')

Dockerfile to build a docker image for the unifi video server. One command to run and no additional manual steps.

## Build the image.

```shell
docker build -t unifi-video .
```

## Run the prebuild image from docker hub.
  Note: Change the last line to the name of your image in case you have built your own

```shell
docker run -it -d \
  --name=unifi-video \
  --privileged \
  --net=host \
  -v /var/lib/unifi-video:/var/lib/unifi-video \
  -v /var/log/unifi-video:/var/log/unifi-video \
  ekiourk/unifi-video:latest
```

## Run it by using the run script

```shell
./run.sh
```

