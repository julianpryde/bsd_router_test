# Purpose
The purpose of this project is to test features for the bsd_router_complex environment.   That project contains configuration files for a FreeBSD router running on a micro form factor Dell OptiPlex.

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