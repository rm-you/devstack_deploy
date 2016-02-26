#!/bin/bash

# TODO: Remove these default patchsets after L7 merges
# Set up for L7 testing temporarily
NEUTRON_LBAAS_PATCH="refs/changes/32/148232/48"
NEUTRON_CLIENT_PATCH="refs/changes/76/217276/13"

# Quick sanity check (should be run on Ubuntu 14.04 and MUST be run as root directly)
if [ `lsb_release -rs` != "14.04" ]
then
  echo -n "Warning: This script is only tested against Ubuntu 14.04. Press <enter> to continue at your own risk... "
  read
fi
if [ `whoami` != "root" -o -n "$SUDO_COMMAND" ]
then
  echo "This script must be run as root, and not using 'sudo'!"
  exit 1
fi

# Set up the packages we need
apt-get update
apt-get install git vim -y

# Clone the devstack repo
git clone https://github.com/openstack-dev/devstack.git /tmp/devstack

wget -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/postgres-neutron-lbaas/localrc > /tmp/devstack/localrc

# Create the stack user
/tmp/devstack/tools/create-stack-user.sh

# Move everything into place
mv /tmp/devstack /opt/stack/
chown -R stack:stack /opt/stack/devstack/

cat >>/opt/stack/.profile <<EOF
# Prepare patches for localrc
export NEUTRON_LBAAS_PATCH="$NEUTRON_LBAAS_PATCH"
EOF

# Use the openstack mirrors for pip
NODEPOOL_REGION=iad
NODEPOOL_CLOUD=rax
NODEPOOL_MIRROR_HOST=mirror.$NODEPOOL_REGION.$NODEPOOL_CLOUD.openstack.org
NODEPOOL_MIRROR_HOST=$(echo $NODEPOOL_MIRROR_HOST|tr '[:upper:]' '[:lower:]')
NODEPOOL_PYPI_MIRROR=http://$NODEPOOL_MIRROR_HOST/pypi/simple
NODEPOOL_WHEEL_MIRROR=http://$NODEPOOL_MIRROR_HOST/wheel/ubuntu-14.04-x86_64/

cat >/etc/pip.conf <<EOF
[global]
timeout = 60
index-url = $NODEPOOL_PYPI_MIRROR
trusted-host = $NODEPOOL_MIRROR_HOST
extra-index-url = $NODEPOOL_WHEEL_MIRROR
EOF

cat >/opt/stack/.pydistutils.cfg <<EOF
[easy_install]
index_url = $NODEPOOL_PYPI_MIRROR
allow_hosts = *.openstack.org
EOF

# Let's rock
su - stack -c /opt/stack/devstack/stack.sh

# Update neutron client if necessary
if [ -n "$NEUTRON_CLIENT_PATCH" ]
then
    su - stack -c "cd python-neutronclient && git fetch https://review.openstack.org/openstack/python-neutronclient $NEUTRON_CLIENT_PATCH && git checkout FETCH_HEAD && sudo python setup.py install"
fi

# Install tox globally
pip install tox

# Grab utility scripts from github and add them to stack's .profile
wget -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/postgres-neutron-lbaas/profile >> /opt/stack/.profile

# Drop into a shell
su - stack
