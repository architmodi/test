#!/bin/bash
# 
# Login as cloud-user once the instance is ACTIVE
# For ssh connection refused error, wait for the 
# system to boot, it takes few minutes.
#

RELEASE=$(cat /etc/yum.repos.d/latest-installed | awk '{print $1}')

source /home/stack/overcloudrc
if [ -z "`openstack network list | grep private`" ];then
  openstack network create private
  openstack subnet create --gateway 192.168.100.1 --dhcp --network private --subnet-range 192.168.100.0/24 private
  openstack subnet set --dns-nameserver 10.34.32.1 --dns-nameserver 10.34.32.3 private
  echo "****************************************Private network created****************************************************"
fi
SID=$(neutron net-list | awk '/private/ {print $2}' | head -n 1)
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
SECID=$(openstack security group list | grep `openstack project show admin -f value -c id` | head -n 1 | awk '{print $2}')

if [ "$RELEASE" -lt 12 ];then
  nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0 2>/dev/null
  nova secgroup-add-rule default tcp 22 22 0.0.0.0/0 2>/dev/null
else
  openstack security group rule create $SECID --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 2>/dev/null
  openstack security group rule create $SECID --protocol icmp --dst-port -1 --remote-ip 0.0.0.0/0 2>/dev/null
fi

if [ ! -f rhel-guest-image-7.5-146.x86_64.qcow2 ];then wget http://download-node-02.eng.bos.redhat.com/released/RHEL-7/7.5/Server/x86_64/images/rhel-guest-image-7.5-146.x86_64.qcow2;fi

if [ -z "`openstack image list | grep rhel`" ];then
  openstack image create rhel --disk-format qcow2 --container-format bare --file rhel-guest-image-7.5-146.x86_64.qcow2
  echo "****************************************Image uploaded to glance**************************************************"
fi
if [ -z "`openstack flavor list | grep m1.custom`" ];then
  openstack flavor create --public m1.custom --id auto --ram 2048 --disk 13 --vcpus 2
fi

if [ -z "`nova keypair-list | grep -o mykey`" ];then
  nova keypair-add --pub-key /home/stack/.ssh/id_rsa.pub mykey
fi

COUNTVAR=$RANDOM
openstack server create --image rhel --flavor m1.custom --key-name mykey test-$COUNTVAR --nic net-id=$SID --wait

if [ "$RELEASE" -eq 7 ] || [ "$RELEASE" -eq 9 ];then
  IP=$(neutron floatingip-create nova -f value -c floating_ip_address) 
  nova floating-ip-associate test-$COUNTVAR $IP
elif [ "$RELEASE" -gt 11 ];then
  IP=$(neutron floatingip-create nova -f value -c floating_ip_address)
  openstack server add floating ip test-$COUNTVAR $IP
else
  IP=$(neutron floatingip-create public -f value -c floating_ip_address)
  nova floating-ip-associate test-$COUNTVAR $IP
fi

openstack server list
