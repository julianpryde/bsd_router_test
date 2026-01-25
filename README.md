# Purpose
The purpose of this project is to test features for the bsd_router_complex environment.   That project contains configuration files for a FreeBSD router running on a micro form factor Dell OptiPlex.

# Architecture
For the purposes of testing, these configuration files will be applied to FreeBSD router running in VMWare workstation pro.  There are three interfaces on the router:
1. WAN -> connected to my VMWare NAT VMNet
2. LAN -> serving a stateful DHCPv6 server to clients with dnsmasq.  I chose to use a stateful DHCPv6 server for security.
3. mgmt -> in place for future testing to boot the router from a simulated raspberry pi using PXEboot. My pf rules are very careful to only allow tftp traffic on this interface.

I am running a pf firewall to control the flow of traffic through the router.

As VMWare workstation pro doesn't natively support handing out ipv6 addresses to guests, the WAN interface must only support ipv4 communications, necessitating a NAT64 router.  I am using Tayga for this function.  While I will be able to communicate using ipv6 on the production environment in bsd_router_complex, this will help communicate with ipv4-only websites.