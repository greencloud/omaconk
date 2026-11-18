# omaconk

A desktop system monitor for the Omarchy bar. omaconk runs as a native
Omarchy shell plugin and uses the shell's theme and Nerd Font.

## Install

You need Omarchy with its Quickshell bar and Python 3. The public IP lookup
uses curl. NVIDIA temperature readings require a working driver and
`nvidia-smi`.

From the repository root, run the following commands in your Omarchy session.

```sh
plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/system-monitor"
install -Dm644 manifest.json "$plugin_dir/manifest.json"
install -Dm644 BarWidget.qml "$plugin_dir/BarWidget.qml"
install -Dm644 metrics.py "$plugin_dir/metrics.py"
install -Dm644 i18n/en.json "$plugin_dir/i18n/en.json"
omarchy-shell shell rescanPlugins
omarchy bar put local.system-monitor --after omarchy.monitor
```

Click the chip icon next to the display controls. The panel shows CPU
utilization and load averages, CPU/GPU/NVMe temperatures, RAM and swap usage,
the three highest CPU and RAM consumers, and configured DNS servers. Local
readings refresh while the panel is open.

Click **Look up via ipify** to display your public IP. The widget contacts
ipify over HTTPS only when you click the button. The returned address reflects
your public egress, including any VPN or proxy you use.

## Development

`BarWidget.qml` is the shell entry point. `metrics.py` collects the Linux
readings, and `i18n/en.json` contains the English UI strings. There are no
bundled visual assets or build dependencies.

Run these checks from the repository root.

```sh
omarchy plugin validate "$PWD"
python3 metrics.py
```

For a live check, install the plugin, open the panel, and verify the process
rankings, sensor readings, DNS list, and on-demand public IP lookup.
