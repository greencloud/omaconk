import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

PROC = Path("/proc")
CLOCK_TICKS = os.sysconf("SC_CLK_TCK")
PAGE_KIB = os.sysconf("SC_PAGE_SIZE") // 1024


def command(*args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=2)
    except (OSError, subprocess.SubprocessError):
        return ""


def cpu_snapshot():
    fields = list(map(int, (PROC / "stat").read_text().splitlines()[0].split()[1:9]))
    processes = {}
    for path in PROC.glob("[0-9]*/stat"):
        try:
            raw = path.read_text(errors="replace")
            name, fields_text = raw[raw.index("(") + 1:].rsplit(")", 1)
            stats = fields_text.split()
            key = (path.parent.name, stats[19])
            # Remove control characters and bound each label before it reaches QML.
            name = "".join(char for char in name[:64] if char.isprintable())
            processes[key] = (name, int(stats[11]) + int(stats[12]), max(0, int(stats[21])) * PAGE_KIB)
        except (OSError, ValueError, IndexError):
            continue
    return sum(fields), fields[3] + fields[4], processes


def temperatures():
    readings = {}
    for chip in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        try:
            driver = (chip / "name").read_text().strip()
            if driver in {"k10temp", "coretemp", "zenpower"}:
                label = "CPU"
            elif driver == "nvme":
                label = next((part for part in reversed(chip.resolve().parts) if re.fullmatch(r"nvme\d+", part)), chip.name)
            elif driver in {"amdgpu", "nouveau", "xe", "i915"}:
                label = "GPU"
            else:
                continue
            source = chip / "temp1_input"
            for candidate in sorted(chip.glob("temp*_label")):
                if candidate.read_text().strip() in {"Tdie", "Composite", "edge", "Package id 0"}:
                    source = candidate.with_name(candidate.name.replace("_label", "_input"))
                    break
            readings[label] = round(int(source.read_text()) / 1000, 1)
        except (OSError, ValueError):
            continue
    for index, value in enumerate(command("nvidia-smi", "--query-gpu=temperature.gpu",
                                         "--format=csv,noheader,nounits").splitlines()[:8]):
        if value.strip().isdigit():
            key = "GPU" if index == 0 and "GPU" not in readings else f"NVIDIA GPU {index}"
            readings[key] = int(value)
    return readings


def addresses(words):
    result = []
    for word in words:
        try:
            address = ipaddress.ip_address(word)
        except ValueError:
            continue
        if not address.is_loopback and str(address) not in result:
            result.append(str(address))
    return result[:8]


def dns_servers():
    lines = command("resolvectl", "dns").splitlines()
    servers = addresses(word for line in lines for word in line.partition(":")[2].split())
    if servers:
        return servers
    try:
        configured = re.findall(r"^nameserver\s+(\S+)", Path("/etc/resolv.conf").read_text(), re.MULTILINE)
    except OSError:
        configured = []
    return (addresses(configured)
            or addresses(command("nmcli", "-g", "IP4.DNS,IP6.DNS", "device", "show").split())
            or configured[:8])


def public_ip():
    # Cap the response and accept exactly one globally routable address.
    try:
        response = subprocess.check_output(
            ["curl", "--disable", "--fail", "--silent", "--max-time", "4", "--max-filesize", "128",
             "https://api64.ipify.org"], stderr=subprocess.DEVNULL, timeout=5)
        address = ipaddress.ip_address(response.strip().decode("ascii"))
        return str(address) if address.is_global else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def metrics():
    started = time.monotonic()
    first_total, first_idle, previous = cpu_snapshot()
    time.sleep(0.45)
    elapsed = time.monotonic() - started
    total, idle, current = cpu_snapshot()
    cpu = 100 * (1 - (idle - first_idle) / max(1, total - first_total))
    processes = [
        {"name": name, "cpu": round(100 * max(0, ticks - previous[key][1]) / (elapsed * CLOCK_TICKS), 1)
         if key in previous else 0, "ram": ram}
        for key, (name, ticks, ram) in current.items()
    ]
    mem = {}
    for line in (PROC / "meminfo").read_text().splitlines():
        field, value = line.split(":", 1)
        mem[field] = int(value.split()[0])
    return {
        "cpu": round(max(0, min(cpu, 100)), 1),
        "loads": os.getloadavg(),
        "ram": [mem["MemTotal"] - mem["MemAvailable"], mem["MemTotal"]],
        "swap": [mem["SwapTotal"] - mem["SwapFree"], mem["SwapTotal"]],
        "topCpu": sorted(processes, key=lambda row: row["cpu"], reverse=True)[:3],
        "topRam": sorted(processes, key=lambda row: row["ram"], reverse=True)[:3],
        "temperatures": temperatures(),
        "dns": dns_servers(),
    }


if __name__ == "__main__":
    print(json.dumps(public_ip() if sys.argv[1:] == ["--public-ip"] else metrics()))
