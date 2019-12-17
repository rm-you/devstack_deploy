#!/bin/bash

OCTAVIA_PATCH="refs/changes/62/693762/22"
OCTAVIA_CLIENT_PATCH="refs/changes/11/694711/2"
BARBICAN_PATCH=""

# Centos has an ANCIENT version of git, grab a new version from some random repo
#yum -y install http://opensource.wandisco.com/centos/6/git/x86_64/wandisco-git-release-6-1.noarch.rpm
#yum -y update git
yum install vim

# Install python37 and link it in because we need it for stacking
yum-config-manager --add-repo https://edge.artifactory.yahoo.com:4443/artifactory/python_rpms/python_rpms.repo
yum-config-manager --enable python_rpms-beta
yum -y install oath_python37
ln -s /opt/python/bin/python3* /usr/local/bin
ln -s /opt/python/bin/pip3* /usr/local/bin

# Also enable the epel repo that devstack needs later
yum-config-manager --enable epel

# Clone the devstack repo
git clone https://github.com/openstack-dev/devstack.git /tmp/devstack

# Set up our localrc for devstack
wget -O /tmp/devstack/local.conf https://raw.githubusercontent.com/rm-you/devstack_deploy/centos_oath/local.conf

# Create the stack user
/tmp/devstack/tools/create-stack-user.sh
# Fix permissions?
chmod 755 /opt/stack

# Move everything into place
mv /tmp/devstack /opt/stack/
chown -R stack:stack /opt/stack/devstack/

cat >>/opt/stack/.profile <<EOF
# Prepare patches for local.conf
export BARBICAN_PATCH="$BARBICAN_PATCH"
export OCTAVIA_PATCH="$OCTAVIA_PATCH"
export OCTAVIACLIENT_BRANCH="$OCTAVIA_CLIENT_PATCH"
EOF

# Precreate .cache so it won't have the wrong perms
#su - stack -c 'mkdir /opt/stack/.cache'

# Let's rock
su - stack -c /opt/stack/devstack/stack.sh

# Install tox globally
pip install tox &> /dev/null

# Grab utility scripts from github and add them to stack's .profile
wget -q -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/centos_oath/profile | sudo -u stack tee -a /opt/stack/.bash_profile > /dev/null

# Set up barbican container
sudo -u stack wget -q https://raw.githubusercontent.com/rm-you/devstack_deploy/centos_oath/make_container.sh -O /opt/stack/make_container.sh
chmod +x /opt/stack/make_container.sh
sudo su - stack -c /opt/stack/make_container.sh

# Fix missing route
ROUTER_IP=$(su - stack -c "openstack router show router1 | awk -F '|' ' / external_gateway_info / {print \$3} ' | jq -r '.external_fixed_ips[0].ip_address'")
route add -net 10.0.0.0 netmask 255.255.255.0 gw $ROUTER_IP dev br-ex

# Drop into a shell
su - stack
