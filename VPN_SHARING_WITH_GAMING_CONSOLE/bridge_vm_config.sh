#!/bin/bash
set -e

BRIDGED_LAN_IF="ens37"
NAT_IF="ens33"
VPN_IF="wg0"

BRIDGED_LAN_STATIC_IP="192.168.1.201"
CONSOLE_IP="192.168.1.200"
LAN_NETMASK="255.255.255.0"

echo "==> Bringing up interfaces (if not already up)"
for IFACE in "${BRIDGED_LAN_IF}" "${NAT_IF}"; do
    if [ "$(cat /sys/class/net/${IFACE}/operstate 2>/dev/null)" != "up" ]; then
        echo "    Bringing up ${IFACE}"
        ip link set "${IFACE}" up
    else
        echo "    ${IFACE} already up"
    fi
done

echo "==> Writing /etc/network/interfaces"
cat > /etc/network/interfaces <<EOF
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto ${NAT_IF}
iface ${NAT_IF} inet dhcp

# Bridged interface for Console
auto ${BRIDGED_LAN_IF}
iface ${BRIDGED_LAN_IF} inet static
    address ${BRIDGED_LAN_STATIC_IP}
    netmask ${LAN_NETMASK}
EOF


echo "==> Persisting IPv4 forwarding across reboots"
sudo tee /etc/sysctl.d/99-ip-forward.conf > /dev/null << 'EOF'
# Enable IPv4 packet forwarding
net.ipv4.ip_forward = 1
EOF
echo "==> Applying sysctl settings"
sudo sysctl --system


echo "==> Flushing existing rules"
iptables -F
iptables -t nat -F
iptables -X

echo "==> Setting policies"
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP

echo "==> NAT: masquerade outbound on ${VPN_IF}"
iptables -t nat -A POSTROUTING -o "${VPN_IF}" -j MASQUERADE

echo "==> NAT: DMZ - forward all other unsolicited inbound traffic from ${VPN_IF} to CONSOLE (${CONSOLE_IP})"
iptables -t nat -A PREROUTING -i "${VPN_IF}" -j DNAT --to-destination "${CONSOLE_IP}"

echo "==> FORWARD: LAN(console) -> VPN"
iptables -A FORWARD -i "${BRIDGED_LAN_IF}" -o "${VPN_IF}" -j ACCEPT

echo "==> FORWARD: VPN -> LAN, established/related (return traffic)"
iptables -A FORWARD -i "${VPN_IF}" -o "${BRIDGED_LAN_IF}" -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "==> FORWARD: VPN -> CONSOLE, allow new unsolicited connections (DMZ / NAT type 2)"
iptables -A FORWARD -i "${VPN_IF}" -o "${BRIDGED_LAN_IF}" -d "${CONSOLE_IP}" -j ACCEPT

echo "==> Done"
iptables -L -v -n
echo
iptables -t nat -L -v -n

echo
echo "==> ip_forward status:"
sysctl net.ipv4.ip_forward

echo
echo "==> To persist these iptables rules across reboots:"
echo "    apt install iptables-persistent"
echo "    netfilter-persistent save"
