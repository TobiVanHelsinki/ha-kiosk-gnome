#!/bin/bash
#logger -t kiosk-display-watch "script started"

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f "$SCRIPT_DIR/mqtt.conf" ]; then
    logger -t kiosk-display-watch "mqtt.conf not found"
    exit 1
fi
source "$SCRIPT_DIR/mqtt.conf"

#logger -t kiosk-display-watch "mqtt.conf loaded, connecting to $BROKER_IP"

gdbus monitor --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver \
| while read line; do
    #logger -t kiosk-display-watch "received: $payload"
    case "$line" in
        *"ActiveChanged (true,"*)
            mosquitto_pub -h "$BROKER_IP" -u "$MQTT_USER" -P "$MQTT_PASS" \
              -t "$MQTT_TOPIC_STATE" -m "off" -r
            #logger -t kiosk-display-watch "state: off"
            ;;
        *"ActiveChanged (false,"*)
            mosquitto_pub -h "$BROKER_IP" -u "$MQTT_USER" -P "$MQTT_PASS" \
              -t "$MQTT_TOPIC_STATE" -m "on" -r
            #logger -t kiosk-display-watch "state: on"
            ;;
    esac
done
#logger -t kiosk-display-watch "mosquitto_sub exited"
