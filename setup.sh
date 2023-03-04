#!/bin/bash

# This is just a little script that can be downloaded from the internet to
# setup WireGuard qube as a ProxyVM. It just tested in Debian.

set -eu pipefail

# shellcheck source=/dev/null
. /var/run/qubes/qubes-ns
# shellcheck source=/dev/null
. wireguard.conf

WG_PRIVATE_KEY=${WG_PRIVATE_KEY:-}
WG_ADDRESS=${WG_ADDRESS:-}              # 10.10.10.2/32
WG_DNS=${WG_DNS:-1.1.1.1}               # 1.1.1.1
WG_PUBLIC_KEY=${WG_PUBLIC_KEY:-}
WG_PRESHARED_KEY=${WG_PRESHARED_KEY:-}
WG_ENDPOINT=${WG_ENDPOINT:-}            # 12.34.56.78:51820 or example.com:51820

WG_CONFIG_DIR=${WG_CONFIG_DIR:-/etc/wireguard}
WG_CONFIG=/rw/bind-dirs/etc/wireguard/wg0.conf
NS1=${NS1:-10.139.1.1}
NS2=${NS2:-10.139.1.2}

install -d "/rw/bind-dirs/${WG_CONFIG_DIR}"
cat << EOT >> ${WG_CONFIG}
[Interface]
PrivateKey = ${WG_PRIVATE_KEY}
Address = ${WG_ADDRESS}
DNS = ${WG_DNS}

[Peer]
PublicKey = ${WG_PUBLIC_KEY}
Endpoint = ${WG_ENDPOINT}
AllowedIPs = 0.0.0.0/0, ::/0
EOT
if [ -n "${WG_PRESHARED_KEY}" ]; then
    echo "PresharedKey = ${WG_PRESHARED_KEY}" >> ${WG_CONFIG}
fi

# Persistently preserve the `/etc/wireguard/` directory.
install -d /rw/config/qubes-bind-dirs.d
cat << EOT >> /rw/config/qubes-bind-dirs.d/50_wireguard.conf
binds+=( '/etc/wireguard/' )
EOT

# Add an `rc.local` script to support below.
# 1. enabling traffic forwarding
# 2. specifying a DNS resolver address
# 3. starting the WireGuard service
cat << EOT >> /rw/config/rc.local
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.route_localnet=1
echo 'nameserver ${WG_DNS}' > /etc/resolv.conf
systemctl start wg-quick@wg0
EOT

# If the NetVM of sys-wireguard is modified or changed, it could cause IP changes and also reset
# the `/etc/resolv.conf` file. To restore it to nameserver `${WG_DNS}`, a hook script is required.
HOOK_IP=/rw/config/qubes-ip-change-hook
cat << EOT >> ${HOOK_IP}
#!/bin/sh

echo 'nameserver ${WG_DNS}' > /etc/resolv.conf
EOT
chmod +x ${HOOK_IP}

# Create a firewall rule to forward local DNS requests to the server `${WG_DNS}`.
FW_WG=/rw/config/qubes-firewall.d/wireguard
install -d /rw/config/qubes-firewall.d
cat << EOT >> ${FW_WG}
#!/bin/sh

# Allow redirects to localhost
iptables -I INPUT -i vif+ -p tcp --dport 53 -d ${WG_DNS} -j ACCEPT
iptables -I INPUT -i vif+ -p udp --dport 53 -d ${WG_DNS} -j ACCEPT

# Redirect dns-requests to localhost
iptables -t nat -F PR-QBS
iptables -t nat -A PR-QBS -d ${NS1}/32 -p udp -m udp --dport 53 -j DNAT --to-destination ${WG_DNS}
iptables -t nat -A PR-QBS -d ${NS1}/32 -p tcp -m tcp --dport 53 -j DNAT --to-destination ${WG_DNS}
iptables -t nat -A PR-QBS -d ${NS2}/32 -p udp -m udp --dport 53 -j DNAT --to-destination ${WG_DNS}
iptables -t nat -A PR-QBS -d ${NS2}/32 -p tcp -m tcp --dport 53 -j DNAT --to-destination ${WG_DNS}
EOT
chmod +x ${FW_WG}

# Create firewall rules.
FW_RF=/rw/config/qubes-firewall.d/restrict-firewall
cat << EOT >> ${FW_RF}
#!/bin/sh

##################################################################
##
##  proxy-restrict-firewall
##  Configure Qubes firewall for use with a proxy such as OpenVPN.
##
##  Note: For customization, add rules to a filename in firewall.d
##  other than '90_proxy-restrict'.
##
##################################################################

# Export Qubes DNS nameserver NS1 and NS2
. /var/run/qubes/qubes-ns

# Stop all leaks between downstream (vif+) and upstream (Internet eth0):
iptables -F OUTPUT
iptables -P FORWARD DROP
iptables -I FORWARD -o eth0 -j DROP
iptables -I FORWARD -i eth0 -j DROP

# Ensure only traffic destined for the wg+ interface is forwarded
iptables -F QBS-FORWARD
iptables -A QBS-FORWARD -o wg+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -A QBS-FORWARD -i vif+ -o wg+ -j ACCEPT
iptables -A QBS-FORWARD -j DROP

# Block INPUT from proxy(s):
#iptables -P INPUT DROP
#iptables -I INPUT -i wg+ -j DROP

# Restrict connections to wg+ interface only
iptables -D INPUT -j DROP
iptables -A INPUT -i wg+ -j ACCEPT
iptables -A INPUT -j DROP

# Allow established traffic:
#iptables -A INPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT

# Allow DNS lookups from local via wg+ interface
if [ -n "\${NS1}" ]; then
  iptables -I INPUT -i wg+ -p udp -s "\${NS1}" --sport 53 -m state --state ESTABLISHED -j ACCEPT
  iptables -I INPUT -i wg+ -p tcp -s "\${NS1}" --sport 53 -m state --state ESTABLISHED -j ACCEPT
fi
if [ -n "\${NS2}" ]; then
  iptables -I INPUT -i wg+ -p udp -s "\${NS2}" --sport 53 -m state --state ESTABLISHED -j ACCEPT
  iptables -I INPUT -i wg+ -p tcp -s "\${NS2}" --sport 53 -m state --state ESTABLISHED -j ACCEPT
fi

# Disable icmp packets
if iptables -C INPUT -i vif+ -p icmp -j ACCEPT; then
  iptables -D INPUT -i vif+ -p icmp -j ACCEPT
fi
if iptables -C INPUT -i vif+ -j REJECT --reject-with icmp-host-prohibited; then
  iptables -D INPUT -i vif+ -j REJECT --reject-with icmp-host-prohibited
fi
iptables -I INPUT -p icmp -j DROP

## Drop invalid connections
iptables -I INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
iptables -I INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,PSH,ACK,URG -j DROP
iptables -I INPUT -f -j DROP
iptables -I INPUT -p tcp -m tcp --tcp-flags SYN,RST SYN,RST -j DROP
iptables -I INPUT -p tcp -m tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
iptables -I INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,ACK -j DROP
iptables -I INPUT -m state --state INVALID -j DROP
iptables -I INPUT -m conntrack --ctstate INVALID -j DROP

# Restrict connections via interfaces
#iptables -A OUTPUT -j LOG --log-prefix "[iptables OUTPUT chain] " # debugging purposes: tail -f /var/log/kern.log
iptables -A OUTPUT -m conntrack --ctstate INVALID -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -m state --state INVALID -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,ACK -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -p tcp -m tcp --tcp-flags FIN,SYN FIN,SYN -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -p tcp -m tcp --tcp-flags SYN,RST SYN,RST -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -f -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,PSH,ACK,URG -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -o wg0 -j ACCEPT
iptables -A OUTPUT -p udp -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
EOT
chmod +x ${FW_RF}

echo -e "WireGuard qube setup has been completed.\nPlease restart and enjoy :)"
