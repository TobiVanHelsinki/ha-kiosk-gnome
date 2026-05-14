#!/bin/bash

if [ ! -f "$(dirname "$0")/kiosk.env" ]; then
    echo "kiosk.env not found. Copy kiosk-template.env to kiosk.env and fill in your values."
    exit 1
fi
# get the HA URL
source "$(dirname "$0")/kiosk.env"

# kill existing sessions and wait a second if something has been killed
pkill firefox && sleep 1
# start the session
firefox --kiosk "$HA_URL" &