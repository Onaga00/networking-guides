# VPN Sharing with a Console (via Bridged Virtual Machine)

Consoles do not natively support VPN clients. This guide shows how to route a console's traffic through a VPN by using a virtual machine as a bridge between the console and a WireGuard VPN tunnel.

## Prerequisites

1. A PC with a physical LAN input port (Wi-Fi will **not** work for this) that connects to the same network as the console.
2. The console must be connected to the same network as the PC (either LAN cable or Wi-Fi is fine for the console).
3. VMware Workstation Pro (this guide uses VMware, but feel free to use any hypervisor, e.g. VirtualBox).
4. A Linux distribution image (this guide uses Debian 13.6.0).
5. A VPN provider that supports the WireGuard protocol.

## 1. Create the Virtual Machine

In VMware, create a virtual machine using your Linux distro image, then add **two network interfaces** in its settings:

1. **Primary interface (NAT)** - used to communicate with the host machine.
2. **Bridged interface** - add this *after* the VM's first boot. It provides a direct access point on the physical LAN.

A single processor core and 2 GB of RAM should be more than sufficient. There's no need to install a graphical desktop environment (e.g. GNOME, KDE Plasma, XFCE, MATE, Cinnamon, etc.).

### Improving Performance (Optional)

If the VM feels too slow, try the following:

1. **VMware → Edit → Preferences → Memory** → "Fit all virtual machine memory into reserved host RAM"
2. **VMware → VM → Settings → Options → Advanced** → "Disable side channel mitigations for Hyper-V enabled hosts"
3. **VMware → VM → Settings → Hardware → Processors** → "Virtualize IOMMU" (only if the option is available)

### Verify the Virtual Network Editor

Make sure that under **VMware → Edit → Virtual Network Editor** both the **Bridged** and **NAT** virtual networks exist, with DHCP enabled on the NAT network. Add them if they are missing.

## 2. Install sudo if it's not already present and initialize the Network Interfaces

```bash
apt-get install sudo -y
```

Boot the virtual machine and log in as `root`. Check that both network interfaces are present:

```bash
ip a
```

If needed, bring the interface up manually:

```bash
sudo ip link set <interface_name> up
```


## 3. Install WireGuard

```bash
sudo apt update
sudo apt install wireguard iptables-persistent -y
```

## 4. Generate the WireGuard Keys

Generate and store the keys in `/etc/wireguard/` (skip this step if your VPN provider already gives you a client private key):

```bash
cd /etc/wireguard
umask 077   # restrict permissions to the current user only
wg genkey | tee client_private.key | wg pubkey > client_public.key
```

## 5. Configure the WireGuard Tunnel

The exact procedure for obtaining your WireGuard tunnel configuration varies by VPN provider, but it will generally look similar to the example below.

Edit `/etc/wireguard/wg0.conf`:

```bash
nano /etc/wireguard/wg0.conf
```

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = <CLIENT_IP>
DNS = <e.g. Cloudflare 1.1.1.1, 1.0.0.1>
MTU = <maximum packet size - leave unset if unsure>

[Peer]
PublicKey = <VPN_PUBLIC_KEY>
AllowedIPs = 0.0.0.0/0
Endpoint = <VPN_PUBLIC_IP>:<PORT>
PersistentKeepalive = 25
```

## 6. Install the DNS framework resolvconf and Start WireGuard

```bash
sudo apt install resolvconf
sudo systemctl enable --now wg-quick@wg0
```

## 7. Configure iptables Forwarding

Install the script `bridge_vm_config.sh` and edit its parameters with nano (or any other text editor) to make it match your network's config, save it on the VM, then run it as root:

```bash
apt install curl
sudo curl -O https://raw.githubusercontent.com/Onaga00/networking-guides/refs/heads/main/VPN_SHARING_WITH_GAMING_CONSOLE/bridge_vm_config.sh
sudo bash bridge_vm_config.sh
sudo netfilter-persistent save
```


Open the network interfaces file:

```bash
nano /etc/network/interfaces
```

Make sure it follows this structure:

```
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto <NAT_ADAPTER_NAME>
iface <NAT_ADAPTER_NAME> inet dhcp

# Bridged interface for the console
auto <BRIDGED_ADAPTER_NAME>
iface <BRIDGED_ADAPTER_NAME> inet static
    address <STATIC_IP e.g. 192.168.x.x>
    netmask <e.g. 255.255.255.0>
```

## 8. Verify Everything Works After a Restart

```bash
sudo systemctl restart networking
```

or better

```bash
sudo reboot
```

## Useful Commands

| Command | Description |
|---|---|
| `sudo wg show` | Show the WireGuard interface configuration |
| `sudo systemctl status wg-quick@wg0` | Get the current status of the WireGuard interface |
| `sudo systemctl restart wg-quick@wg0` | Restart the WireGuard interface |
| `sudo wg-quick down wg0` | Turn off the WireGuard interface |
| `sudo wg-quick up wg0` | Turn on the WireGuard interface |
| `cat <filename>` | Read a file |
| `cat > <filename>` | Overwrite or create a file if it doesn't exist |
| `rm <filename>` | Delete a file |
| `sudo ip link set <interface_name> up` | Turn on a network interface |
| `ip a` | Show all network interfaces |
| `curl ifconfig.me` | Display your public IP address |
| `sudo iptables -L` | Inspect routing rules |
| `cat /proc/sys/net/ipv4/ip_forward` | Verify if IP forwarding is active ( 1 = true, 0 = false) |
