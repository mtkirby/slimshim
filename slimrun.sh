#!/bin/bash
# 20151025 Kirby

. /root/slimlib


/root/slimshim.sh prep

slimguess
    
/root/slimshim.sh $ip $mac $routerip $routermac

# Assume that we are on a /24 network
# If you have problems connecting to other IPs in a nearby subnet, try tuning the cidr
ipnetwork="${ip%.*}.0/24"
route add -net $ipnetwork dev br-lan >/dev/null 2>&1
ripnetwork="${routerip%.*}.0/24"
route add -net $ripnetwork dev br-lan >/dev/null 2>&1
route add default gw $routerip >/dev/null 2>&1

# set
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
/etc/init.d/dnsmasq stop >/dev/null 2>&1
sniff=$(tcpdump -c1 -nni br-lan "not ip6 and udp and port 53" 2>/dev/null)
# 04:40:30.876500 IP 192.168.1.19.59369 > 192.168.1.1.53: 13937+ A? cnn.com. (25)
dns=$(echo $sniff |awk '{print $5}' |cut -d'.' -f1-4)
grep -q $dns /etc/resolv.conf
if [ $? != 0 ]; then
    echo "nameserver $dns" > /etc/resolv.conf
fi
grep -q 8.8.8.8 /etc/resolv.conf
if [ $? != 0 ]; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

