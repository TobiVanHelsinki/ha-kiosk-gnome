#!/bin/bash
#logger -t kiosk-display-control "script started"

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f "$SCRIPT_DIR/mqtt.conf" ]; then
    logger -t kiosk-display-control "mqtt.conf not found"
    exit 1
fi
source "$SCRIPT_DIR/mqtt.conf"

#logger -t kiosk-display-control "mqtt.conf loaded, connecting to $BROKER_IP"

mosquitto_sub -h "$BROKER_IP" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$MQTT_TOPIC_CMD" | while read payload; do
    #logger -t kiosk-display-control "received: $payload"
    case "$payload" in
        on)
            gdbus call --session --dest org.gnome.ScreenSaver \
                --object-path /org/gnome/ScreenSaver \
                --method org.gnome.ScreenSaver.SetActive false > /dev/null 2> >(logger -t kiosk-display-control)
            #logger -t kiosk-display-control "display on"
            ;;
        off)
            gdbus call --session --dest org.gnome.ScreenSaver \
                --object-path /org/gnome/ScreenSaver \
                --method org.gnome.ScreenSaver.SetActive true > /dev/null 2> >(logger -t kiosk-display-control)
            #logger -t kiosk-display-control "display off"
            ;;
    esac
done
#logger -t kiosk-display-control "mosquitto_sub exited"
