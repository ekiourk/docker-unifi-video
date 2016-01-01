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
    libc6

RUN apt-get install -y curl
RUN curl -L -O http://dl.ubnt.com/firmwares/unifi-video/3.1.2/unifi-video_3.1.2-Debian7_amd64.deb

RUN dpkg -i unifi-video_3.1.2-Debian7_amd64.deb

EXPOSE 7080

COPY ./entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
