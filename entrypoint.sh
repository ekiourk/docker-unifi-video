#!/bin/bash

# in case the /var/lib/unifi-video directory is in a volume
# any files created by the deb package will be lost
# so we run the postinst configure one more time in order to create them again
/var/lib/dpkg/info/unifi-video.postinst configure

service unifi-video start && tail -F /var/log/unifi-video/error.log
