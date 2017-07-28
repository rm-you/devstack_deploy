#!/bin/bash

OCTAVIA_PATCH=""
OCTAVIA_CLIENT_PATCH=""
BARBICAN_PATCH=""

# Centos mirrors are broken inside GD, use some upstream mirror
cat << EOF > /etc/yum.repos.d/CentOS-Base.repo
[CentOS-Base]
name=CentOS-Base
baseurl=http://centos-distro.1gservers.com/7/os/x86_64/
enabled=True
gpgcheck=False
EOF

# Centos also has an ANCIENT version of git, grab a new version from some random repo
yum -y install http://opensource.wandisco.com/centos/6/git/x86_64/wandisco-git-release-6-1.noarch.rpm
yum -y update git

# Install python-pip because we need it for stacking
yum -y install python-pip

# Clone the devstack repo
git clone https://github.com/openstack-dev/devstack.git /tmp/devstack

# Centos 7 needs sudo for screen_process sg
sed -i 's/command="sg /command="sudo sg /' /tmp/devstack/functions-common

# Set up our localrc for devstack
wget -O /tmp/devstack/local.conf https://raw.githubusercontent.com/rm-you/devstack_deploy/centos_new/local.conf

# Create the stack user
/tmp/devstack/tools/create-stack-user.sh

# Move everything into place
mv /tmp/devstack /opt/stack/
chown -R stack:stack /opt/stack/devstack/

cat >>/opt/stack/.profile <<EOF
# Prepare patches for local.conf
export BARBICAN_PATCH="$BARBICAN_PATCH"
export OCTAVIA_PATCH="$OCTAVIA_PATCH"
export OCTAVIACLIENT_BRANCH="$OCTAVIA_CLIENT_PATCH"
EOF

# Fix centos 7 issue with iptables
touch /etc/sysconfig/iptables

# Fix ipv6 support
sed -i 's/net.ipv6.conf.all.disable_ipv6=1/net.ipv6.conf.all.disable_ipv6=0/' /etc/sysctl.conf
sed -i 's/net.ipv6.conf.default.disable_ipv6=1/net.ipv6.conf.default.disable_ipv6=0/' /etc/sysctl.conf
sed -i 's/net.ipv6.conf.lo.disable_ipv6=1/net.ipv6.conf.lo.disable_ipv6=0/' /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf

# Precreate .cache so it won't have the wrong perms
su - stack -c 'mkdir /opt/stack/.cache'

# Let's rock
su - stack -c /opt/stack/devstack/stack.sh

# Install tox globally
pip install tox &> /dev/null

# Grab utility scripts from github and add them to stack's .profile
wget -q -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/centos_new/profile | sudo -u stack tee -a /opt/stack/.bash_profile > /dev/null

# Set up barbican container
sudo -u stack wget -q https://raw.githubusercontent.com/rm-you/devstack_deploy/master/make_container.sh -O /opt/stack/make_container.sh
chmod +x /opt/stack/make_container.sh
sudo su - stack -c /opt/stack/make_container.sh

# Fix missing route
ROUTER_IP=$(su - stack -c "openstack router show router1 | awk -F '|' ' / external_gateway_info / {print \$3} ' | jq -r '.external_fixed_ips[0].ip_address'")
route add -net 10.0.0.0 netmask 255.255.255.0 gw $ROUTER_IP dev br-ex

# Drop into a shell
su - stack
