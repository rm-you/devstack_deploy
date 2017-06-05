#!/bin/bash

OCTAVIA_PATCH=""
OCTAVIA_CLIENT_PATCH=""
BARBICAN_PATCH=""

# Quick sanity check (should be run on Ubuntu 16.04 and MUST be run as root directly)
if [ `lsb_release -rs` != "16.04" ]
then
  echo -n "Warning: This script is only tested against Ubuntu xenial. Press <enter> to continue at your own risk... "
  read
fi
if [ `whoami` != "root" -o -n "$SUDO_COMMAND" ]
then
  echo "This script must be run as root, and not using 'sudo'!"
  exit 1
fi

# Set up the packages we need
apt-get update
apt-get install git vim jq -y

# Clone the devstack repo
git clone https://github.com/openstack-dev/devstack.git /tmp/devstack

wget -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/master/localrc > /tmp/devstack/localrc

# Create the stack user
/tmp/devstack/tools/create-stack-user.sh

# Apparently the group for libvirt changed to libvirtd in parallels?
usermod -a -G libvirtd stack

# Move everything into place
mv /tmp/devstack /opt/stack/
chown -R stack:stack /opt/stack/devstack/

cat >>/opt/stack/.profile <<EOF
# Prepare patches for localrc
export BARBICAN_PATCH="$BARBICAN_PATCH"
export OCTAVIA_PATCH="$OCTAVIA_PATCH"
export OCTAVIACLIENT_BRANCH="$OCTAVIA_CLIENT_PATCH"

export OCTAVIA_USE_MOD_WSGI=False
EOF

# Precreate .cache so it won't have the wrong perms
su - stack -c 'mkdir /opt/stack/.cache'

# Install non-broken ubuntu qemu packages
apt-get install -y seabios=1.8.2-1ubuntu1 qemu-system-sparc=1:2.5+dfsg-5ubuntu10.11 qemu-system-ppc=1:2.5+dfsg-5ubuntu10.11 qemu-system-arm=1:2.5+dfsg-5ubuntu10.11 qemu-kvm=1:2.5+dfsg-5ubuntu10.11 qemu-system-x86=1:2.5+dfsg-5ubuntu10.11 qemu-system-mips=1:2.5+dfsg-5ubuntu10.11 qemu-system-misc=1:2.5+dfsg-5ubuntu10.11
apt-mark hold seabios qemu-system-sparc qemu-system-ppc qemu-system-arm qemu-kvm qemu-system-x86 qemu-system-mips qemu-system-misc

# Let's rock
su - stack -c /opt/stack/devstack/stack.sh

# Immediately delete spurious o-hm default route
route > ~/routes.log
route del default gw 192.168.0.1

# Install tox globally
pip install tox &> /dev/null

# Grab utility scripts from github and add them to stack's .profile
wget -q -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/master/profile | sudo -u stack tee -a /opt/stack/.bash_profile > /dev/null

# Set up barbican container
sudo -u stack wget -q https://raw.githubusercontent.com/rm-you/devstack_deploy/master/make_container.sh -O /opt/stack/make_container.sh
chmod +x /opt/stack/make_container.sh
sudo su - stack -c /opt/stack/make_container.sh

# Fix missing route
ROUTER_IP=$(su - stack -c "openstack router show router1 | awk -F '|' ' / external_gateway_info / {print \$3} ' | jq -r '.external_fixed_ips[0].ip_address'")
route add -net 10.0.0.0 netmask 255.255.255.0 gw $ROUTER_IP dev br-ex

# Drop into a shell
su - stack
