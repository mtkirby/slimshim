SlimShim is a script that performs IP and MAC address spoofing of a directly-connected device without interrupting traffic to and from that device. A SlimShim has 2 ethernet ports that is plugged in between the victim device and the switch/router. The SlimShim acts as a switch and injects spoofed packets below the radar (source ports).

UPDATE: After all the work of testing and scripting, it turns out I just re-invented the wheel. The idea was already conceived by Alva Lease ‘Skip’ Duckwall IV and he did a presentation at Defcon 19.  His script is called 8021xbridge.  I like my script better.  It is better at network guessing and supports 802.1q.


QUICK OVERVIEW/TL;DR

    The device you shim will remain up and connected. Nothing on the victim device will change.
    This allows you to get past NAC (as long as you shim a trusted device).
    This allows you to MITM the device connecting through the SlimShim.
    This allows you to spoof as any device connected to the SlimShim.
    If you attack the victim, you will appear as the router.
    If your SlimShim has wifi, you can route through it and appear as the victim.
    Everything is transparent to the network.
    A network scanner cannot detect SlimShim
    Code is available at https://github.com/mtkirby/slimshim
    Only IPv4 is supported at the moment. IPv6 is coming soon.
    802.1q vlans can be shimmed.
    Slimshim mimics the TTL of the victim device.
    You will need expert-level skills of Linux and networking to understand how this works.
    You need to plug the victim into eth1.  The network guess function sniffs for input packets on that interface.



TODO/Upcoming features:

    IPv6 support

SlimShim is a bash script that runs iptables and ebtables commands to mimic the IP and MAC of the victim. It will use an ephemeral port (source ports) range below the range used by Windows and Linux devices. SlimShim will forward a lower range of ephemeral ports to itself, such as ports 27000-32000.

SlimShim can run on any device that has 2 ethernet ports.  I use it on a Raspberry Pi(with a usb ethernet) running Kali and a Nexx WT3020 running OpenWRT.  To shim a PC, simply unplug it's ethernet and plug the cable into the SlimShim and plug the other SlimShim ethernet into the PC.  You may need a cross-over cable if your device can't configure it automatically.  The two interfaces on the SlimShim are bridged, so it acts as a switch.  The victim device does not know it has been shimmed and neither does the router.  
I have wifi AP setup on my SlimShims so that I can connect to victim's network with a laptop and still appear as the victim IP/MAC.  


The hardest part of shimming a victim is to get the IP/MAC of the victim and router. On my SlimShims, I have the slimrun.sh start on bootup via rc.local (/root/slimrun.sh >/tmp/slimrun.log 2>&1). The slimshim script will run 3 tcpdumps to attempt to guess the IP/MAC of the victim and router.  The script should also work if you are shimming a server that is receiving mostly inbound packets, such as a networked security camera (which is a funny story for another time).

The method I use to guess the network is as follows:

1) Start a loop to sniff for packets.  If anything doesn’t look right, start over.

2) Sniff for inbound packets on eth1, where the victim device is plugged in.  This gets the victim IP, MAC, TTL, and 802.1q vlan tag(if used).

3) Get the route MAC by sniffing for packets that are sent to the victim IP, look for non-standard TTLs (because we want packets that were hopped), and ignore any local network packets (assuming we’re on a /24).

4) Now for the hard part, which is getting the router IP.  We have to watch for an arp request for who has the router MAC we got from the previous sniff. This may take a while for the victim to re-query the router IP, so to speed it up I re-plumb eth1 and also use scapy(if installed) to flood the assumed /24 with arp requests.

 
The script will also watch for DNS queries and update /etc/resolv.conf with the nameserver that the victim is using.

The script will also forward all connections to 1.1.1.1 to the SlimShim. This allows the victim PC to connect to the SlimShim, which is useful to me when I’m pentesting. The script will also forward port 2501 to it’s ssh service so I can connect to SlimShim from elsewhere on the network.

The redirectIngressPort and redirectIngressPorts functions can redirect traffic that is destined to the victim. This is useful for opening ports to be used for reverse-bind attacks when I attack the network.

The redirectEgressPort function can redirect traffic from the victim so that I can redirect DNS, or anything, for MITM attacks. I once redirected a victim running Splunk Forwarder to a malicious Splunk server that I setup and deployed an app that opened a reverse shell.
 
The source is available at https://github.com/mtkirby/slimshim
It is GPLv3.

The slimshim.sh script will create an environment log file in /root that you can source and use the variables for your own scripts.

So how can you protect your network against SlimShims?  You'd need your firewalls to log all connections that use a source port range of 27000-32000.

The goals of this project were as follows:

    The victim should not perceive any manipulation to the router IP and MAC and vice versa.
    The victim can connect to the shim box, but only when I allow it.  This is for when I shim my own PC to do pentesting.
    NAC cannot see any changes and should trust the SlimShim just as it trusts the victim.
    The SlimShim can allow any inbound connections to the victim.  (In case any services such as RDP, NAC agents, etc.).
    SlimShim can connect to the network spoofed as the victim's IP and MAC.
    A network scanner cannot detect SlimShim.
    SlimShim can redirect the victim's traffic and perform MITM attacks.







#############################################################################
How to setup SlimShim on a Raspberry Pi running Kali:
First get a usb ethernet adapter because SlimShim requires 2 ethernets.
Setup your /etc/network/interfaces like so:

    auto lo
    iface lo inet loopback

    auto eth0
    iface eth0 inet manual
        up ifconfig $IFACE up

    auto eth1
    iface eth1 inet manual
        up ifconfig $IFACE up

    auto wlan0
    iface wlan0 inet static
        address 192.0.0.1
        netmask 255.255.255.0

Setup wifi.  Add this to /etc/hostapd/hostapd.conf.  Ssid is slimshim and password is Gaddafi'd! (anyone get the reference?)

    interface=wlan0
    driver=nl80211
    ssid=slimshim
    hw_mode=g
    channel=1
    macaddr_acl=0
    auth_algs=1
    ignore_broadcast_ssid=2
    wpa=2
    wpa_passphrase=Gaddafi'd!
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=TKIP
    rsn_pairwise=CCMP
    ieee80211n=1
    require_ht=1

 
Setup dhcp for the wifi interface.  Add this to /etc/dhcp/dhcpd.conf 

    ddns-update-style none;
    option domain-name "shim.lan";
    option domain-name-servers 8.8.8.8;
    subnet 192.0.0.0 netmask 255.255.255.0 {
        range 192.0.0.10 192.0.0.254;
    }
    default-lease-time 600;
    max-lease-time 7200;
    log-facility local7;

The script will create a br-lan bridge and assign it 169.254.0.1/24 with MAC of 00:01:01:01:01:01.  The wifi interface will be 192.0.0.1/24.  You can ssh to it once you are connected to wifi.  Add it as your default route if you want to route through the SlimShim.
Copy the code from Github and put in /root/.  Now run slimrun.sh
I have the slimrun.sh start on bootup via rc.local (/root/slimrun.sh >/tmp/slimrun.log 2>&1). 
If that ran without errors, try to telnet to a website to see if everything is working.  You can sniff the interface to verify your IP/MAC spoofs.  The source port range should be within the range specified in the slimshim script.
That should do it.  Let me know if something doesn't work for you. 


#############################################################################
How to setup SlimShim on a Nexx WT3020.  These things are only $15-$20.  They are powered by usb.  They don't have much storage or ram, so don't expect much beyond shimming a victim and maybe run a small nmap scan.
First install OpenWRT or LEDE.  I have mine modified to use a usb thumbdrive for storage.  The Nexx has very little storage and you won't be able to do much without a thumbdrive extension.  There is documentation on OpenWRT's site on how to use a thumbdrive as an overlay filesystem.  I use a sandisk ultrafit 16gb.  I compiled a custom OpenWRT build, but that was probably overkill.
You should at the very least add these packages: arptables bash ebtables ebtables-utils ip ip-bridge ip-full ip6tables iptables kmod-bridge kmod-ebtables* kmod-ipt-* kmod-nf-conntrack* kmod-nf-ipt* kmod-nf-nat* kmod-nfnetlink kmod-nft-core kmod-nft-nat nftables swconfig

Run these uci commands:

    uci delete wireless.radio0
    uci set wireless.radio0=wifi-device
    uci set wireless.radio0.type='mac80211'
    uci set wireless.radio0.channel='11'
    uci set wireless.radio0.hwmode='11g'
    uci set wireless.radio0.path='10180000.wmac'
    uci set wireless.radio0.htmode='HT20'
    uci set wireless.radio0.txpower='20'
    uci set wireless.radio0.country='00'

    uci delete wireless.@wifi-iface[0]
    uci add wireless wifi-iface
    uci set wireless.@wifi-iface[0]=wifi-iface
    uci set wireless.@wifi-iface[0].device='radio0'
    uci set wireless.@wifi-iface[0].mode='ap'
    uci set wireless.@wifi-iface[0].ssid='slimshim'
    uci set wireless.@wifi-iface[0].hidden='1'
    uci set wireless.@wifi-iface[0].encryption='psk2'
    uci set wireless.@wifi-iface[0].key='Gaddafi'\''d!'
    uci set wireless.@wifi-iface[0].network='wifi'

    uci delete dhcp.lan
    uci delete dhcp.wan
    uci delete dhcp.odhcpd
    uci delete dhcp.wifi
    uci set dhcp.lan=dhcp
    uci set dhcp.lan.interface='lan'
    uci set dhcp.lan.ignore='1'
    uci set dhcp.wan=dhcp
    uci set dhcp.wan.interface='wan'
    uci set dhcp.wan.ignore='1'
    uci set dhcp.odhcpd=odhcpd
    uci set dhcp.odhcpd.maindhcp='0'
    uci set dhcp.odhcpd.leasefile='/tmp/hosts/odhcpd'
    uci set dhcp.odhcpd.leasetrigger='/usr/sbin/odhcpd-update'
    uci set dhcp.wifi=dhcp
    uci set dhcp.wifi.leasetime='12h'
    uci set dhcp.wifi.limit='150'
    uci set dhcp.wifi.interface='wifi'
    uci set dhcp.wifi.start='10'

    uci set dropbear.@dropbear[0].GatewayPorts='on'

    while uci show firewall 2>&1|grep  -q firewall
    do 
        for i in $(uci show firewall|cut -d'=' -f1)
        do 
            uci delete $i >/dev/null 2>&1
        done
    done

    uci add firewall defaults
    uci set firewall.@defaults[0]=defaults
    uci set firewall.@defaults[0].input='ACCEPT'
    uci set firewall.@defaults[0].output='ACCEPT'
    uci set firewall.@defaults[0].forward='ACCEPT'
    uci add firewall zone
    uci set firewall.@zone[0]=zone
    uci set firewall.@zone[0].name='lan'
    uci set firewall.@zone[0].input='ACCEPT'
    uci set firewall.@zone[0].output='ACCEPT'
    uci set firewall.@zone[0].forward='ACCEPT'
    uci set firewall.@zone[0].network=' '
    uci add firewall zone
    uci set firewall.@zone[1]=zone
    uci set firewall.@zone[1].name='wan'
    uci set firewall.@zone[1].output='ACCEPT'
    uci set firewall.@zone[1].network='wan wan6'
    uci set firewall.@zone[1].input='ACCEPT'
    uci set firewall.@zone[1].forward='ACCEPT'
    uci add firewall forwarding
    uci set firewall.@forwarding[0]=forwarding
    uci set firewall.@forwarding[0].src='lan'
    uci set firewall.@forwarding[0].dest='wan'
    uci add firewall include
    uci set firewall.@include[0]=include
    uci set firewall.@include[0].path='/etc/firewall.user'

    uci set network.lan._orig_ifname='eth0.1'
    uci set network.lan._orig_bridge='true'
    uci set network.lan.ifname='eth0.1 eth0.2'
    uci set network.lan.ipaddr='169.254.0.1'
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.force_link='1'
    uci set network.lan.delegate=0
    uci delete network.lan.ip6assign

    uci set network.@switch_vlan[0].ports='0 6t'
    uci set network.@switch_vlan[0].vid='1'
    uci set network.@switch_vlan[1].ports='4 6t'
    uci set network.@switch_vlan[1].vid='2'

    uci set network.wifi=interface
    uci set network.wifi._orig_ifname='wlan0'
    uci set network.wifi._orig_bridge='false'
    uci set network.wifi.proto='static'
    uci set network.wifi.ipaddr='192.0.0.1'
    uci set network.wifi.netmask='255.255.255.0'
    uci set network.wifi.delegate='0'

    uci delete network.wan
    uci delete network.wan6

    uci set system.@system[0].hostname=slimshim

    uci commit    

Copy the code from Github and put in /root/.  Now run slimrun.sh
I have the slimrun.sh start on bootup via rc.local (/root/slimrun.sh >/tmp/slimrun.log 2>&1). 

If that ran without errors, try to telnet to a website to see if everything is working.  You can sniff the interface to verify your IP/MAC spoofs.  The source port range should be within the range specified in the slimshim script.  The slimshim script will blink the power led at a slow pace when it wants you to unplug and replug the vicim ethernet to get the router's MAC. 


Other packages you may want to install:
opkg update 
opkg install aircrack-ng airmon-ng apache arp-scan arptables at autossh bc bind-check bind-client bind-dig bind-dnssec bind-host bind-libs bind-rndc bind-server bind-tools bzip2 ca-bundle ca-certificates certtool coreutils curl ddns-scripts ddns-scripts_cloudflare.com-v4 ddns-scripts_freedns_42_pl ddns-scripts_godaddy.com-v1 ddns-scripts_no-ip_com ddns-scripts_nsupdate ddns-scripts_route53-v1 diffutils dmesg dmidecode ebtables ebtables-utils emailrelay ethtool extract file fstools fstrim git git-http gnupg gnupg-utils haproxy hdparm htop ifstat iftop iodine iodined ip-bridge ip-full ipmitool ipsec-tools iw-full iwcap iwinfo jq less lftp lsof macchanger mariadb-client mariadb-client-extra mii-tool mtr ncat-ssl ndiff netcat nginx nmap-ssl openssh-client openssh-client-utils openssh-keygen openssh-moduli openssh-server openssh-sftp-client openssh-sftp-server openssl-util perl perl-net-http perl-net-telnet pgsql-cli pgsql-cli-extra pppdump python python3 python3-openssl python3-pip python3-setuptools quagga quagga-bgpd quagga-isisd quagga-libospf quagga-libzebra quagga-ospf6d quagga-ospfd quagga-ripd quagga-ripngd quagga-vtysh quagga-watchquagga reaver relayctl relayd rsync rsyncd ruby ruby-openssl samba36-client samba36-hotplug samba36-net samba36-server scapy screen script-utils snmp-mibs snmp-utils socat socksify sshfs sshtunnel sslh ssmtp strace stunnel tcpbridge tcpcapinfo tcpdump tcpdump-mini tcpliveplay tcpprep tcpproxy tcpreplay tcpreplay-all tcpreplay-edit tcprewrite thc-ipv6-address6 thc-ipv6-alive6 thc-ipv6-covert-send6 thc-ipv6-covert-send6d thc-ipv6-denial6 thc-ipv6-detect-new-ip6 thc-ipv6-detect-sniffer6 thc-ipv6-dnsdict6 thc-ipv6-dnsrevenum6 thc-ipv6-dos-new-ip6 thc-ipv6-dump-router6 thc-ipv6-exploit6 thc-ipv6-fake-advertise6 thc-ipv6-fake-dhcps6 thc-ipv6-fake-dns6d thc-ipv6-fake-dnsupdate6 thc-ipv6-fake-mipv6 thc-ipv6-fake-mld26 thc-ipv6-fake-mld6 thc-ipv6-fake-mldrouter6 thc-ipv6-fake-router26 thc-ipv6-fake-router6 thc-ipv6-fake-solicitate6 thc-ipv6-flood-advertise6 thc-ipv6-flood-dhcpc6 thc-ipv6-flood-mld26 thc-ipv6-flood-mld6 thc-ipv6-flood-mldrouter6 thc-ipv6-flood-router26 thc-ipv6-flood-router6 thc-ipv6-flood-solicitate6 thc-ipv6-fragmentation6 thc-ipv6-fuzz-dhcpc6 thc-ipv6-fuzz-dhcps6 thc-ipv6-fuzz-ip6 thc-ipv6-implementation6 thc-ipv6-implementation6d thc-ipv6-inverse-lookup6 thc-ipv6-kill-router6 thc-ipv6-ndpexhaust6 thc-ipv6-node-query6 thc-ipv6-parasite6 thc-ipv6-passive-discovery6 thc-ipv6-randicmp6 thc-ipv6-redir6 thc-ipv6-rsmurf6 thc-ipv6-sendpees6 thc-ipv6-sendpeesmp6 thc-ipv6-smurf6 thc-ipv6-thcping6 thc-ipv6-toobig6 thc-ipv6-trace6 tor tor-gencert tor-geoip tor-resolve trace-cmd trace-cmd-extra tracertools unrar unzip usbutils vnstat wget wireguard wireguard-tools wpa-cli xinetd xz xz-utils
