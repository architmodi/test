#!/bin/bash

RELEASE=$(cat /etc/yum.repos.d/latest-installed | awk '{print $1}')

source /home/stack/overcloudrc
if [ -z "`openstack network list | grep private`" ];then
  openstack network create private
  openstack subnet create --gateway 192.168.100.1 --dhcp --network private --subnet-range 192.168.100.0/24 private
  openstack subnet set --dns-nameserver 10.34.32.1 --dns-nameserver 10.34.32.3 private
  echo "****************************************Private network created****************************************************"
fi
SID=$(neutron net-list | grep private | awk '{print $2}' | head -n 1)
if [ -z "`openstack router list | grep testrouter`" ];then
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
  echo "****************************************Router and subnet created*************************************************"
fi
SECID=$(openstack security group list | grep `openstack project list | grep admin | awk '{print $2}'` | head -n 1 | awk '{print $2}')

if [ "$RELEASE" -lt 12 ];then
  nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0 2>/dev/null
  nova secgroup-add-rule default tcp 22 22 0.0.0.0/0 2>/dev/null
else
  openstack security group rule create $SECID --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 2>/dev/null
  openstack security group rule create $SECID --protocol icmp --dst-port -1 --remote-ip 0.0.0.0/0 2>/dev/null
fi

if [ ! -f cirros-0.3.4-x86_64-disk.img ];then wget http://rhos-qe-mirror-tlv.usersys.redhat.com/images/cirros-0.3.4-x86_64-disk.img;fi

if [ -z "`openstack image list | grep cirros`" ];then
  openstack image create cirros --disk-format qcow2 --container-format bare --file cirros-0.3.4-x86_64-disk.img
  echo "****************************************Image uploaded to glance**************************************************"
fi
if [ -z "`openstack flavor list | grep m1.tiny`" ];then
  openstack flavor create --public m1.tiny --id auto --ram 512 --disk 1 --vcpus 1
fi

COUNTVAR=$RANDOM
openstack server create --image cirros --flavor m1.tiny test-$COUNTVAR --nic net-id=$SID --wait

if [ "$RELEASE" -eq 7 ] || [ "$RELEASE" -eq 9 ];then
  IP=$(neutron floatingip-create nova | awk -F '|' '/floating_ip/ { print $3 }')
  nova floating-ip-associate test-$COUNTVAR $IP
elif [ "$RELEASE" -gt 11 ];then
  IP=$(neutron floatingip-create nova | awk -F '|' '/floating_ip/ { print $3 }')
  openstack server add floating ip test-$COUNTVAR $IP
else
  IP=$(neutron floatingip-create public | awk -F '|' '/floating_ip/ { print $3 }')
  nova floating-ip-associate test-$COUNTVAR $IP
fi

openstack server list
