# docker-unifi-video
Dockerfile to build a docker image for the unifi video server. One command to run and no additional manual steps.


## To run it use the following command:

```shell
docker run -it -d \
  --name=unifi-video \
  --privileged \
  --net=host \
  -v /var/lib/unifi-video:/var/lib/unifi-video \
  -v /var/log/unifi-video:/var/log/unifi-video \
  ekiourk/unifi-video:latest
```
