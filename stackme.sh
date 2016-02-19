#!/bin/bash

BARBICAN_PATCH=""
NEUTRON_LBAAS_PATCH=""
OCTAVIA_PATCH="refs/changes/30/278830/6"

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

wget -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/master/localrc > /tmp/devstack/localrc

# Create the stack user
/tmp/devstack/tools/create-stack-user.sh

# Move everything into place
mv /tmp/devstack /opt/stack/
chown -R stack:stack /opt/stack/devstack/

cat <<EOF >> /opt/stack/.profile
# Fix permissions on current tty so screens can attach
sudo chmod go+rw `tty`

# Prepare patches for localrc
export BARBICAN_PATCH="$BARBICAN_PATCH"
export NEUTRON_LBAAS_PATCH="$NEUTRON_LBAAS_PATCH"
export OCTAVIA_PATCH="$OCTAVIA_PATCH"
EOF

# Let's rock
su - stack -c /opt/stack/devstack/stack.sh

# Install tox globally
pip install tox

# Grab utility scripts from github and add them to stack's .profile
wget -O - https://raw.githubusercontent.com/rm-you/devstack_deploy/master/profile >> /opt/stack/.profile

# Set some utility variables
NETWORK=$(su - stack -c "neutron subnet-list" | awk '/ private-subnet / {print $2}')
PROJECT_ID=$(su - stack -c "openstack token issue" | awk '/ project_id / {print $4}')
cat <<EOF >> /opt/stack/.profile
export PROJECT_ID="${PROJECT_ID:0:8}-${PROJECT_ID:8:4}-${PROJECT_ID:12:4}-${PROJECT_ID:16:4}-${PROJECT_ID:20}"
export DEFAULT_NETWORK='$NETWORK'
EOF

# Set up barbican container
bash <(curl -sL https://raw.githubusercontent.com/rm-you/devstack_deploy/master/make_container.sh)

# Drop into a shell
su - stack
