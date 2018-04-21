#!/bin/bash

RELEASE=$(cat /etc/yum.repos.d/latest-installed | awk '{print $1}')

source /home/stack/overcloudrc
while [ -z "$COUNT" ]; do
	if [ "$RELEASE" -lt 12 ];then
	  neutron net-create private
	  neutron subnet-create --name private --gateway 192.168.100.1 --enable-dhcp private 192.168.100.0/24
	  neutron subnet-update private --dns-nameservers list=true 10.34.32.1 10.34.32.4
	else
	  openstack network create private
	  openstack subnet create --gateway 192.168.100.1 --dhcp --network private --subnet-range 192.168.100.0/24 private
	  openstack subnet set --dns-nameserver 10.34.32.1 --dns-nameserver 10.34.32.3 private
	fi

	export SID=$(neutron net-list | grep private | awk '{print $2}')

	if [ "$RELEASE" -eq 7 ] || [ "$RELEASE" -eq 9 ] || [ "$RELEASE" -eq 12 ];then
	  neutron router-create testrouter
	  neutron router-gateway-set testrouter nova
	  neutron router-interface-add testrouter private
	elif [ "$RELEASE" -eq 13 ];then
	  openstack router create testrouter
	  openstack router set --external-gateway nova testrouter
	  openstack router add subnet testrouter private
	else 
	  neutron router-create testrouter
	  neutron router-gateway-set testrouter public
	  neutron router-interface-add testrouter private
	fi

	SECID=$(openstack security group list | grep `openstack project list | grep admin | awk '{print $2}'` | head -n 1 | awk '{print $2}')

	if [ "$RELEASE" -lt 12 ];then
	  nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
	  nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
	else
	  openstack security group rule create $SECID --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0
	  openstack security group rule create $SECID --protocol icmp --dst-port -1 --remote-ip 0.0.0.0/0
	fi

	wget http://rhos-qe-mirror-tlv.usersys.redhat.com/images/cirros-0.3.4-x86_64-disk.img

	if [ "$RELEASE" -lt 10 ];then
	  glance image-create --name cirros --disk-format qcow2 --container-format bare --file cirros-0.3.4-x86_64-disk.img
	else
	  openstack image create cirros --disk-format qcow2 --container-format bare --file cirros-0.3.4-x86_64-disk.img
	fi

	nova flavor-create m1.tiny auto 512 1 1 --is-public True
	export COUNT=1
done

nova boot --poll --image cirros --flavor m1.tiny test-$COUNT --nic net-id=$SID

if [ "$RELEASE" -eq 7 ] || [ "$RELEASE" -eq 9 ];then
  export IP=$(neutron floatingip-create nova | awk -F '|' '/floating_ip/ { print $3 }')
  neutron floatingip-list
  nova floating-ip-associate test-$COUNT $IP
elif [ "$RELEASE" -gt 11 ];then
  export IP=$(neutron floatingip-create nova | awk -F '|' '/floating_ip/ { print $3 }')
  neutron floatingip-list
  openstack server add floating ip test-$COUNT $IP
else
  export IP=$(neutron floatingip-create public | awk -F '|' '/floating_ip/ { print $3 }')
  neutron floatingip-list
  nova floating-ip-associate test-$COUNT $IP
fi

nova console-log test-$COUNT 
openstack server list
COUNT=$(COUNT+1)
