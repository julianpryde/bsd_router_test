# Purpose
The purpose of this project is to test features for the bsd_router_complex environment.   That project contains configuration files for a FreeBSD router running on a micro form factor Dell OptiPlex.

# Motivation
My home networking environment consists of iPhones, Windows computers, an XBox, Phillips Hue bulbs, and possibly android phones.  My most sensitive resources are:
1. The personal information stored on my iPhones and Windows computers,
2. The reputation of my ip address
3. The compute resources of the computers on my network.

The router should:
1. Limit the ability for a malicious actor to gain initial access on my network through minimum-access-necessary firewall rules and eventually observability of anomalous traffic,
2. Limit the persistence of any possible attackers on the router itself through frequent re-installs of the base operating system from a raspberry pi, and
3. Limit the ability for an attacker on one network component to learn about the rest of the network through microsegmentatoin of network boundaries and encryption of network traffic to the maximum extent possible.

# Architecture
For the purposes of testing, these configuration files will be applied to FreeBSD router running in VMWare workstation pro.  There are three interfaces on the router:
1. WAN -> interface em0, connected to my VMWare NAT VMNet
2. LAN -> serving a dual-stack network with DHCPv4 for IPv4 addressing and IPv6 SLAAC for stateless IPv6 auto-configuration. Clients receive both IPv4 and IPv6 addresses. Right now, I only have one client connected, a Kali linux VM connected to the same LAN segment as my LAN interface (em1)
3. mgmt (em2) -> interface for PXE booting the router from a Debian VM (Raspberry Pi in production). Static IP: 192.168.100.2. The Debian VM (192.168.100.1) provides DHCP and TFTP for BIOS PXE boot only. Configuration files for the Debian VM are in the `debian-pxe-boot/` folder.

I am running a pf firewall to control the flow of traffic through the router.

The router operates as a traditional dual-stack router:
- IPv4 traffic from LAN clients (192.168.1.0/24) is NATed to the WAN interface
- IPv6 traffic from LAN clients (2001:db8:1::/64) is routed natively without NAT
- Both protocols are treated independently according to their native characteristics

# Update Process
I am not using the configuration files stored here, I am copying them into my testing environment as such:
dnsmasq.conf -> /usr/local/etc/dnsmasq.conf
named -> /usr/local/etc/namedb/named.conf
pf.conf -> /etc/pf.conf
rc.conf -> /etc/rc.conf
tayga.conf -> /usr/local/etc/tayga.conf