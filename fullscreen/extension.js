import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const DBUS_INTERFACE_XML = `
<node>
  <interface name="org.gnome.Shell.Extensions.KioskRemax">
    <method name="RemaxFirefox"/>
  </interface>
</node>`;

class KioskDBusService {
    constructor(remaxCallback) {
        this._callback = remaxCallback;

        // Parse XML into typed InterfaceInfo object (required for GNOME 46)
        const nodeInfo = Gio.DBusNodeInfo.new_for_xml(DBUS_INTERFACE_XML);
        const ifaceInfo = nodeInfo.lookup_interface(
            'org.gnome.Shell.Extensions.KioskRemax'
        );

        this._impl = Gio.DBusExportedObject.wrapJSObject(ifaceInfo, this);
        this._impl.export(
            Gio.DBus.session,
            '/org/gnome/Shell/Extensions/KioskRemax'
        );

        console.log('[kiosk-remax] DBus exported successfully');
    }

    RemaxFirefox() {
        this._callback();
    }

    destroy() {
        this._impl.unexport();
        this._impl = null;
    }
}

export default class KioskRemaxExtension extends Extension {
    enable() {
        console.log('[kiosk-remax] enable() called');
        this._dbus = new KioskDBusService(() => this._remaxFirefox());
        this._addPanelButton();
    }

    disable() {
        this._dbus.destroy();
        this._dbus = null;
        this._removePanelButton();
    }

    _remaxFirefox() {
        const tracker = Shell.WindowTracker.get_default();

        for (const actor of global.get_window_actors()) {
            const win = actor.get_meta_window();
            if (!win || win.get_window_type() !== Meta.WindowType.NORMAL)
                continue;

            const app = tracker.get_window_app(win);
            if (!app)
                continue;

            const appId = app.get_id() ?? '';
            if (!appId.toLowerCase().includes('firefox'))
                continue;

            if (win.get_maximized())
                win.unmaximize(Meta.MaximizeFlags.BOTH);

            win.make_fullscreen();
            win.focus(global.get_current_time());
            return;
        }

        console.warn('[kiosk-remax] No Firefox window found');
    }

    _addPanelButton() {
        this._button = new St.Button({
            style_class: 'panel-button kiosk-remax-button',
            can_focus: true,
            track_hover: true,
        });

        const label = new St.Label({
            text: '⛶',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._button.set_child(label);
        this._button.connect('clicked', () => this._remaxFirefox());

        Main.panel._rightBox.insert_child_at_index(this._button, 0);
    }

    _removePanelButton() {
        if (this._button) {
            Main.panel._rightBox.remove_child(this._button);
            this._button.destroy();
            this._button = null;
        }
    }
}
