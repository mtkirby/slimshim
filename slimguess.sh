#!/bin/bash
# 20151025 Kirby

. /root/slimlib
slimguess
    
echo "###########################################"
echo "# Here is a hint on how to run slimshim.sh:"
echo "./slimshim.sh $ip $mac $routerip $routermac"
subnet=$(echo $ip |cut -d'.' -f1-3)
echo "route add -net ${subnet}.0/24 dev br-lan"
echo "route add default gw $routerip"
echo "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
echo "###########################################"
echo "# Here is how you can test connectivity:"
echo "echo 'asdf'|nc cnn.com 80 |head"

