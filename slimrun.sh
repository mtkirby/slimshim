#!/bin/bash
# 20160710 Kirby

which screen >/dev/null 2>&1
if [ $? != 0 ]; then
    echo "FATAL ERROR: you are missing the program: screen"              
    exit 1  
fi                                                                                                                                                                       


/root/slimshim autoshim

# add my wifi network so I can route through the SlimShim
/root/slimshim addLan --lan=192.0.0.0/24 --envfile=/root/slimshim.env 

# redirect inbound 2501 to ssh on SlimShim
/root/slimshim redirectIngressPort --proto=tcp --rdrport=2501 --dstport=22 --envfile=/root/slimshim.env 

# redirect outbound to 1.1.1.1 to SlimShim
/root/slimshim redirectEgressIP --origdip=1.1.1.1 --envfile=/root/slimshim.env 

# redirect outbound to bing.com for http to google.com
/root/slimshim redirectEgressPort --envfile=/root/slimshim.env --origdip=204.79.197.200 --newdip=172.217.4.110 --proto=tcp --dstport=80

# Watch for DNS requests and update resolv.conf
screen -dmS getdns /root/slimshim getdns

# Watch for arps and add to arp/route table
# THIS IS REQUIRED for SlimShim to connect to other devices on the LAN
screen -dmS arpwatch /root/slimshim arpwatch

