#!/bin/bash -x

BARBICAN_PATCH=""
OCTAVIA_PATCH="refs/changes/90/356590/13"
NEUTRON_LBAAS_PATCH=""
NEUTRON_CLIENT_PATCH=""
DIB_PATCH="refs/changes/69/407769/16"

sudo yum -y install python-pip

# Clone the devstack repo
git clone https://github.com/openstack-dev/devstack.git /tmp/devstack

# Centos 7 needs sudo for screen_process sg
sed -i 's/command="sg /command="sudo sg /' /tmp/devstack/functions-common

wget -O /tmp/devstack/localrc https://raw.githubusercontent.com/rm-you/devstack_deploy/master/localrc

# Create the stack user
sudo /tmp/devstack/tools/create-stack-user.sh

# Move everything into place and fix perms
sudo mv /tmp/devstack /opt/stack/
sudo chown -R stack:stack /opt/stack/devstack/
#sudo chmod -R g+rX /opt/stack
#sudo usermod -a -G stack `whoami`

cat <<EOF | sudo -u stack tee -a /opt/stack/.bash_profile > /dev/null
# Prepare patches for localrc
export BARBICAN_PATCH="$BARBICAN_PATCH"
export NEUTRON_LBAAS_PATCH="$NEUTRON_LBAAS_PATCH"
export OCTAVIA_PATCH="$OCTAVIA_PATCH"

# Use Xenial for DIB
export DIB_RELEASE=xenial
EOF

# Fix centos 7 issue with iptables
sudo touch /etc/sysconfig/iptables
sudo sed -i 's/net.ipv6.conf.all.disable_ipv6=1/net.ipv6.conf.all.disable_ipv6=0/' /etc/sysctl.conf
sudo sed -i 's/net.ipv6.conf.default.disable_ipv6=1/net.ipv6.conf.default.disable_ipv6=0/' /etc/sysctl.conf
sudo sed -i 's/net.ipv6.conf.lo.disable_ipv6=1/net.ipv6.conf.lo.disable_ipv6=0/' /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf

# Grab dib and patches
if [ -n "$DIB_PATCH" ]; then
	sudo su - stack -c "git clone https://review.openstack.org/p/openstack/diskimage-builder /opt/stack/diskimage-builder"
	sudo cd /opt/stack/diskimage-builder
	sudo -u stack git fetch https://git.openstack.org/openstack/diskimage-builder $DIB_PATCH && sudo -u stack git checkout FETCH_HEAD
        sudo cd -
fi

# Let's rock
echo "Press enter to ROCK" && read
sudo su - stack -c /opt/stack/devstack/stack.sh
read

# Update neutron client if necessary
if [ -n "$NEUTRON_CLIENT_PATCH" ]
then
    sudo -u stack "cd python-neutronclient && git fetch https://review.openstack.org/openstack/python-neutronclient $NEUTRON_CLIENT_PATCH && git checkout FETCH_HEAD && sudo python setup.py install"
fi

# Install tox globally
sudo pip install tox

# Grab utility scripts from github and add them to stack's .bash_profile
wget -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/centos/profile | sudo -u stack tee -a /opt/stack/.bash_profile

# Set up barbican container
wget https://raw.githubusercontent.com/rm-you/devstack_deploy/centos/make_container.sh
chmod +x make_container.sh
sudo -u stack ./make_container.sh

# Drop into a shell
sudo su - stack
