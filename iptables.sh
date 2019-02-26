#!/bin/bash

declare -r INET_IF="eno1"
declare -r INET_TCP_PORTS=(
  8200  # ReadyMedia
  51413 # BitTorrent
)
declare -r INET_UDP_PORTS=(
  1900  # Simple Service Discovery Protocol
)

declare -r VM_IF="br0"
declare -r VM_SUBNET="192.168.13.0/24"
declare -r VM_TCP_PORTS=(
  53    # Domain Name System
  139   # NetBIOS Session
  445   # SMB over TCP
  24800 # Synergy
)
declare -r VM_UDP_PORTS=(
  53    # Domain Name System
  67    # Dynamic Host Configuration Protocol
  137   # NetBIOS Name Service
  138   # NetBIOS Datagram
)
declare -r VM_WHITELIST=(
  192.30.252.0/22    # GitHub
  185.199.108.0/22   # GitHub
  140.82.112.0/20    # GitHub
  50.31.156.0/25     # Beanstalk
  91.189.88.0/21     # Canonical Group Limited
  162.213.32.0/22    # Canonical USA Inc.
  185.125.188.0/22   # Canonical Group Limited
  213.180.204.183    # ru.archive.ubuntu.com
  45.59.69.178       # msys2.org
  54.88.117.136      # frontier.sferalabs.com
  91.199.212.132     # timestamp.comodoca.com
  # Dynamically changing IP addresses (pinned in /etc/dnsmasq.conf)
  151.101.84.133     # raw.githubusercontent.com
  151.101.112.223    # pypi.python.org
  173.194.222.95     # www.googleapis.com, fonts.googleapis.com
  173.194.44.87      # fonts.gstatic.com
  104.19.195.102     # cdnjs.cloudflare.com
  104.122.240.69     # fpdownload.adobe.com
  52.216.84.75       # s3.amazonaws.com
  17.32.213.129      # timestamp.apple.com
  17.253.55.211      # phobos.apple.com
  188.234.145.81     # v2.phobos.apple.com.edgesuite.net
)

check_if_root()
{
  if [[ "$EUID" -ne 0 ]]; then
    echo "Please run me as root"
    exit 1
  fi
}

clear_rules()
{
  echo "Clearing iptables rules..."

  iptables -F
  iptables -X
  iptables -t nat -F
  iptables -t nat -X
  iptables -t mangle -F
  iptables -t mangle -X
  iptables -t raw -F
  iptables -t raw -X
  iptables -t security -F
  iptables -t security -X
}

create_user_chains()
{
  echo "Creating user-defined chains..."

  iptables -N tcp
  iptables -N udp
  iptables -N whitelist
}

set_default_policies()
{
  echo "Setting default policies..."

  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT
}

set_inet_rules()
{
  echo "Setting iptables rules for Internet access..."

  # allow already established incoming connections
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # accept all traffic that comes to the loopback interface
  iptables -A INPUT -i lo -j ACCEPT

  # drop all invalid packets
  iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

  # allow incoming ICMP echo requests (pings)
  iptables -A INPUT -p icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT

  # attach user-defined TCP and UDP chains to the INPUT chain to handle all new incoming connections
  iptables -A INPUT -p tcp --syn -m conntrack --ctstate NEW -j tcp
  iptables -A INPUT -p udp -m conntrack --ctstate NEW -j udp

  # open TCP/UDP ports
  for port in "${INET_TCP_PORTS[@]}"; do
    iptables -A tcp -p tcp --dport "$port" -j ACCEPT
  done
  for port in "${INET_UDP_PORTS[@]}"; do
    iptables -A udp -p udp --dport "$port" -j ACCEPT
  done

  # reject all other TCP/UDP packets with TCP RESET or ICMP port unreachable messages
  iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
  iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable

  # reject all remaining incoming traffic with ICMP protocol unreachable messages
  iptables -A INPUT -j REJECT --reject-with icmp-proto-unreachable
}

set_vm_rules()
{
  echo "Setting iptables rules for virtual machines..."

  # allow already established connections in both directions
  iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # filter all outgoing Internet connections from virtual machines in user-defined whitelist chain
  iptables -A FORWARD -i "$VM_IF" -j whitelist

  # grant access only to whitelisted IP addresses
  for ip in "${VM_WHITELIST[@]}"; do
    iptables -A whitelist -d "$ip" -j ACCEPT
  done

  # open additional TCP/UDP ports but only for connections coming from virtual machines
  for port in "${VM_TCP_PORTS[@]}"; do
    iptables -A tcp -i "$VM_IF" -p tcp --dport "$port" -j ACCEPT
  done
  for port in "${VM_UDP_PORTS[@]}"; do
    iptables -A udp -i "$VM_IF" -p udp --dport "$port" -j ACCEPT
  done

  # reject all remaining forwarded traffic with ICMP host unreachable messages
  iptables -A FORWARD -j REJECT --reject-with icmp-host-unreachable

  # setup NAT for virtual machines
  iptables -t nat -A POSTROUTING -s "$VM_SUBNET" -o "$INET_IF" -j MASQUERADE

  # clamp MSS field in TCP packets to PMTU value (required for PPP connections)
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
}

save_rules()
{
  echo "Saving iptables rules..."

  iptables-save > /etc/iptables/iptables.rules
}

main()
{
  check_if_root
  clear_rules
  create_user_chains
  set_default_policies
  set_inet_rules
  set_vm_rules
  save_rules
}

main "$@"
