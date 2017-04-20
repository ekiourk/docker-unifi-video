FROM debian:jessie

MAINTAINER Ilias Kiourktsidis "ekiourk@gmail.com"

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y \
    adduser \
    apt-utils \
    sudo \
    dpkg \
    apt \
    lsb-release \
    mongodb-server \
    openjdk-7-jre-headless \
    jsvc \
    libc6 \
    psmisc \
    curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

RUN curl -L -O https://dl.ubnt.com/firmwares/unifi-video/3.5.2/unifi-video_3.5.2~Ubuntu12.04_amd64.deb \
  && dpkg -i unifi-video_3.5.2~Ubuntu12.04_amd64.deb \
  && rm unifi-video_3.5.2~Ubuntu12.04_amd64.deb

EXPOSE 7080

COPY ./entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
