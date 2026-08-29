# VPS as a DMZ Gateway

This guide sets up a Virtual Private Server (VPS) to act as a gateway for a single client, forwarding all inbound traffic to that client and effectively simulating a DMZ (demilitarized zone) host.

## Prerequisites

- A Virtual Private Server (VPS) with a network interface bound to a public IP address.

> Commands below were tested on Debian - they may differ slightly on other distributions.

## 1. Install WireGuard on the VPS

Log in as `root`, then:

```bash
sudo apt update
sudo apt install wireguard iptables-persistent -y
```

## 2. Enable IP Forwarding on the VPS

```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

## 3. Configure the VPS Firewall

**Important:** configure your VPS firewall to allow the ports for the services you need forwarded (if a firewall is present).

## 4. Generate the Server's WireGuard Keys

```bash
cd /etc/wireguard
umask 077   # restrict read/write permissions to the current user only
wg genkey | tee server_private.key | wg pubkey > server_public.key
```

## 5. Configure the Server (`wg0.conf`)

Create the file with `cat > wg0.conf`, add the server's private key, and use the configuration below as a starting point.

**Notes:**

1. All values below are placeholders/examples; replace them with your own.
2. Ports **22** (SSH) and **51820** (WireGuard) are deliberately excluded from the traffic forwarded to the client, so that you don't lock yourself out of your own VPS. **Important:** if your SSH or WireGuard ports differ from the defaults, update the configuration accordingly before activating it.
3. In the example below, `10.0.0.1` is the VPS's address inside the tunnel, with `/24` as the subnet size. `10.0.0.2` is the client's address inside the tunnel, using a `/32` netmask to indicate it's a single host rather than a subnet.

```ini
[Interface]
PrivateKey = <SERVER_PRIVATE_KEY>
Address = <private tunnel IP, e.g. 10.0.0.1/24>
ListenPort = 51820
MTU = <maximum packet size — the optimal value may vary; keep the default if unsure>

# Forward all inbound traffic on eth0 to the client (10.0.0.2), except SSH and WireGuard ports
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 22 -j ACCEPT
PostUp = iptables -t nat -A PREROUTING -i eth0 -p udp --dport 51820 -j ACCEPT
PostUp = iptables -t nat -A PREROUTING -i eth0 -j DNAT --to-destination 10.0.0.2
PostUp = iptables -A FORWARD -d 10.0.0.2 -j ACCEPT

# Clean up rules when the interface shuts down
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D PREROUTING -i eth0 -p tcp --dport 22 -j ACCEPT
PostDown = iptables -t nat -D PREROUTING -i eth0 -p udp --dport 51820 -j ACCEPT
PostDown = iptables -t nat -D PREROUTING -i eth0 -j DNAT --to-destination 10.0.0.2
PostDown = iptables -D FORWARD -d 10.0.0.2 -j ACCEPT

# Client 1 (DMZ host)
[Peer]
PublicKey = <CLIENT_PUBLIC_KEY>
AllowedIPs = 10.0.0.2/32
```

## 6. Start WireGuard on Boot

```bash
sudo systemctl enable --now wg-quick@wg0
```

## 7. Configure the Client

Install WireGuard on the client and configure the tunnel using the example below.

```ini
# Client public key: <CLIENT_PUBLIC_KEY>

[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.0.2/32
DNS = <e.g. Cloudflare 1.1.1.1, 1.0.0.1>
MTU = <maximum packet size — the optimal value may vary; keep the default if unsure>

[Peer]
PublicKey = <VPS_PUBLIC_KEY>
AllowedIPs = 0.0.0.0/0
Endpoint = <VPS_PUBLIC_IP>:<PORT>
PersistentKeepalive = 25
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