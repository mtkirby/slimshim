#!/bin/bash
# 20151025 Kirby

. /root/slimlib
slimguess
    
/root/slimshim.sh $ip $mac $routerip $routermac
subnet=$(echo $ip |cut -d'.' -f1-3)
route add -net ${subnet}.0/24 dev br-lan
route add default gw $routerip
echo 'nameserver 8.8.8.8' > /etc/resolv.conf

while :; do
    sleep 10
    # openwrt overwrites resolv.conf
    grep 8.8.8.8 /etc/resolv.conf >/dev/null 2>&1 || echo 'nameserver 8.8.8.8' > /etc/resolv.conf
done
