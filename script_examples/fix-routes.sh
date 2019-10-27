#!/bin/sh
#Fix for docker and VPN network conflict.

echo "Adding default route to $route_vpn_gateway with /0 mask..."
ip route add default via $route_vpn_gateway

echo "Removing /1 routes..."
ip route del 0.0.0.0/1 via $route_vpn_gateway
ip route del 128.0.0.0/1 via $route_vpn_gateway

#Add executable bit to the file: fix-routes.sh and change owner of this file to root:
#chown root:root  /etc/openvpn/fix-routes.sh
#Openvpn adds routes that for following networks: 0.0.0.0/1 and 128.0.0.0/1 (these routes cover entire IP range),
#and docker can't find range of IP addresses to create it's own private network.
#You need to add a default route (to route everything through openvpn) and disable these two specific routes.
#fix-routes script does that.
#This script is called after openvpn adds its own routes.
#To execute scripts you'll need to set script-security to 2 which allows execution of bash scripts from openvpn context
