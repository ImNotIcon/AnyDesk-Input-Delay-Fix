# AnyDesk input-delay fix for Linux

A workaround for delayed AnyDesk mouse movement when a laptop lid is closed,
even though keyboard input and clicks remain responsive.

The service detaches the ACPI lid switch during remote sessions and restores it
after disconnect or backend exit. It uses Bash and standard Linux utilities;
Python is not required. See [the investigation report](REPORT.md) for measurements,
implementation details, and limitations of log tracking.

## Install or update

Requirements: systemd, Bash, an AnyDesk X11 backend, and a writable ACPI button
`lid_init_state` parameter. The installer checks required utilities and detects
the desktop account and lid device.

```sh
sudo ./install.sh
```

To select another desktop account:

```sh
sudo ANYDESK_USER=USERNAME ./install.sh
```

Installation enables and restarts the service. Updates preserve existing
configuration in `/etc/default/anydesk-input-delay-fix`:

```text
LID_DEVICE=PNP0C0D:00
ANYDESK_TRACE_FILE="/home/USERNAME/.anydesk/anydesk.trace"
```

Edit those values if detection is unsuitable, then restart the service.

## Check operation

```sh
systemctl status anydesk-input-delay-fix.service
journalctl -u anydesk-input-delay-fix.service -n 30
sudo /usr/local/sbin/anydesk-input-delay-fix status
```

The lid switch should be bound while disconnected, unbound during a remote
session, and bound again within a few seconds after the final disconnect.
Test closing the lid, connecting, opening the lid, and disconnecting; the display
should recover normally. The service checks for new log data once per second.

## Effects and limitations

During remote sessions, lid detection is unavailable to all applications;
lid-triggered actions cannot run. The physical lid state cannot be read through
the detached device. Detection returns after the session.

After rebinding, the helper verifies ACPI against UPower's cached lid state.
It restarts `upower.service` only if those states disagree. This briefly refreshes
battery/power reporting and is recorded in the journal.

The watcher relies on AnyDesk backend trace messages and UTC timestamps. Verify
operation after AnyDesk upgrades. Running the watcher directly bypasses systemd's
shutdown recovery; use the service for normal operation.

## Stop or remove

Stop the service and restore lid detection:

```sh
sudo systemctl stop anydesk-input-delay-fix.service
```

To uninstall:

```sh
sudo systemctl disable --now anydesk-input-delay-fix.service
sudo rm /etc/systemd/system/anydesk-input-delay-fix.service
sudo rm /usr/local/sbin/anydesk-input-delay-fix-watcher
sudo rm /usr/local/sbin/anydesk-input-delay-fix
sudo rm /etc/default/anydesk-input-delay-fix
sudo systemctl daemon-reload
```
