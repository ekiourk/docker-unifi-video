#!/bin/bash
set -uo pipefail

# The deb's postinst creates state under /var/lib/unifi-video. At runtime that path is a
# bind mount, which masks whatever the image shipped, so configure has to run on every
# start rather than once at build time.
/var/lib/dpkg/info/unifi-video.postinst configure

# UniFi Video runs its own bundled mongod holding the recordings database. Letting the
# container be SIGKILLed leaves that database dirty, so stop the service properly and
# wait for it to actually go away before exiting.
term_handler() {
    echo "[entrypoint] signal received, stopping unifi-video..."
    service unifi-video stop || true

    for _ in $(seq 1 90); do
        pgrep -f '/usr/lib/unifi-video' >/dev/null 2>&1 || break
        sleep 1
    done

    if pgrep -f '/usr/lib/unifi-video' >/dev/null 2>&1; then
        echo "[entrypoint] WARNING: processes still running after 90s"
    else
        echo "[entrypoint] stopped cleanly"
    fi
    exit 0
}
trap term_handler TERM INT

# /usr/sbin/unifi-video does `ulimit -H -c 200` on startup. Docker used to give containers
# a soft core limit of 0, so lowering the hard limit was fine; current versions start with
# both limits unlimited, and setrlimit rejects a hard limit below the soft one with EINVAL
# — the service then dies with only "ulimit: error setting limit (Invalid argument)".
#
# Drop the soft limit to 0 and leave the hard limit alone, so whatever the init script
# picks is necessarily >= soft. Do not "helpfully" set a matching soft limit here: this is
# bash and that script is dash, and the two count -c in 1024- and 512-byte blocks
# respectively, so equal-looking numbers are not equal and the EINVAL comes straight back.
ulimit -S -c 0 2>/dev/null || true

service unifi-video start

# -F rather than -f so this survives the log being rotated or not existing yet.
tail -F /var/log/unifi-video/error.log &
tail_pid=$!

# wait is interrupted when a trapped signal arrives; loop so that anything the trap does
# not handle does not silently end the container.
while kill -0 "$tail_pid" 2>/dev/null; do
    wait "$tail_pid"
done
