# Feature "net": configures eth0. IPv4 DHCP is done by the kernel before init runs (ip=dhcp is
# placed on the measured command line by mkImage). Parameters on the measured command line:
#   net.ip4=dhcp|static:ADDR/PREFIX,GW|off      default dhcp
#   net.ip6=slaac|static:ADDR/PREFIX,GW|off     default slaac
#   net.dns=ADDR[,ADDR]                         resolvers; override those learned by DHCP
$bb ip link set lo up
$bb ip link set eth0 up
case "${net_ip4:-dhcp}" in
    dhcp) ;;
    static:*) a="${net_ip4#static:}"; $bb ip addr add "${a%,*}" dev eth0; $bb ip route replace default via "${a#*,}" dev eth0 ;;
    off) ;;
esac
case "${net_ip6:-slaac}" in
    slaac) $bb echo 1 > /proc/sys/net/ipv6/conf/eth0/accept_ra ;;
    static:*) a="${net_ip6#static:}"; $bb ip -6 addr add "${a%,*}" dev eth0; $bb ip -6 route replace default via "${a#*,}" dev eth0 ;;
    off) $bb echo 1 > /proc/sys/net/ipv6/conf/eth0/disable_ipv6 ;;
esac
if [ -n "$net_dns" ]; then
    : > /etc/resolv.conf
    for d in $($bb echo "$net_dns" | $bb tr , ' '); do $bb echo "nameserver $d" >> /etc/resolv.conf; done
elif [ -r /proc/net/pnp ]; then
    $bb grep '^nameserver' /proc/net/pnp > /etc/resolv.conf
fi
log "network: $($bb ip -o addr show eth0 | $bb awk '{print $4}' | $bb tr '\n' ' ')"
