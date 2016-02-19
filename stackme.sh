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

cat <<EOF > /tmp/devstack/localrc
enable_plugin barbican https://review.openstack.org/openstack/barbican $BARBICAN_PATCH
enable_plugin neutron-lbaas https://review.openstack.org/openstack/neutron-lbaas $NEUTRON_LBAAS_PATCH
enable_plugin octavia https://review.openstack.org/openstack/octavia $OCTAVIA_PATCH
EOF
wget -O - https://github.com/rm-you/devstack_deploy/blob/master/localrc >> /tmp/devstack/localrc

# Create the stack user
/tmp/devstack/tools/create-stack-user.sh

# Move everything into place
mv /tmp/devstack /opt/stack/
chown -R stack:stack /opt/stack/devstack/

# Fix permissions on current tty so screens can attach
echo 'sudo chmod go+rw `tty`' >> /opt/stack/.profile

# Let's rock
su - stack -c /opt/stack/devstack/stack.sh

# Add environment variables for auth/endpoints
echo 'source /opt/stack/devstack/openrc admin admin' >> /opt/stack/.profile
echo 'export BARBICAN_ENDPOINT="http://localhost:9311"' >> /opt/stack/.profile

# Install tox globally
pip install tox

# Set up an example Certificate Container
CERT=$(su - stack -c "barbican secret store -p '-----BEGIN CERTIFICATE-----
MIIC+zCCAeOgAwIBAgIJAL3vlrrJiFHIMA0GCSqGSIb3DQEBBQUAMBQxEjAQBgNV
BAMMCWxvY2FsaG9zdDAeFw0xNjAxMTIxOTM4MjJaFw0yNjAxMDkxOTM4MjJaMBQx
EjAQBgNVBAMMCWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
ggEBAK5Tr+2Mj0jpBBdvzPBAXVVhlNYVq1oY83ANgReEhvK/SpKEm9fpTTMAq055
FdzDdvvMmLzlXg3X/0oHa698SBeLslG0vkZpEuAa1odYBw9uGE+JHI4Zc7skypPf
SK1bTKD85+5L6obCwBvLu1yLkn3j9i7iMKtvLPlS6mnGCEDLz69lDYZTO8SeV1Bb
vK1T9CcuKcMnHc4yN3aq/emlOm0CYvZMHkPqL1XNc2Wjd+adTvKwGhIlZb+dNW+z
Rc2B7I9tnIFokENRSYwQPYv8fdiuxNe8AeA/EdLYsL2pDb06ty+gBN3VagUZZA8U
j5DsbFi5q+SO6yAzzbWo2QTDmpUCAwEAAaNQME4wHQYDVR0OBBYEFKcHdBLjpZy+
xd+sxBXSpHdYxTPOMB8GA1UdIwQYMBaAFKcHdBLjpZy+xd+sxBXSpHdYxTPOMAwG
A1UdEwQFMAMBAf8wDQYJKoZIhvcNAQEFBQADggEBAJBQEnC/Ox0Txe8c6+ss9slM
iByYDXxAf66LYt0KCq31Dttwz4rQY1vJa3SGpxfKzZ+KUObMjoaV/11Y5MxG860T
g7yniE6ZAHu/uEAoQSfd/ZEh8nvKMQWSVEeLfHQiWcbG7XgmxyWwsaecdSaLgIus
ypXtJT9WnZTYGN9CyaFrng63v1cnQ6lWVcFjNucvZBXJ2Oqzx9CFutHRgcEhb2bS
P2EmTWw00G+Bt6VkZ+GQkm04lIuWC0cGQ2aEf7gnqsesLVmj/1yIganmBn1XbJDi
D3Ur1mrVfY3GFdQRkX41fHT/AJDN2j7XUInOMav4ie8MpQHF3weJpVqAymxT6kM=
-----END CERTIFICATE-----'" | awk ' / Secret href / {print $5}')

KEY=$(su - stack -c "barbican secret store -p '-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEArlOv7YyPSOkEF2/M8EBdVWGU1hWrWhjzcA2BF4SG8r9KkoSb
1+lNMwCrTnkV3MN2+8yYvOVeDdf/Sgdrr3xIF4uyUbS+RmkS4BrWh1gHD24YT4kc
jhlzuyTKk99IrVtMoPzn7kvqhsLAG8u7XIuSfeP2LuIwq28s+VLqacYIQMvPr2UN
hlM7xJ5XUFu8rVP0Jy4pwycdzjI3dqr96aU6bQJi9kweQ+ovVc1zZaN35p1O8rAa
EiVlv501b7NFzYHsj22cgWiQQ1FJjBA9i/x92K7E17wB4D8R0tiwvakNvTq3L6AE
3dVqBRlkDxSPkOxsWLmr5I7rIDPNtajZBMOalQIDAQABAoIBAAg41Dxc+8kRjGra
kAzozD4hqxZp0TofoSOwz1zfmEnMseS1MnB9hXGZX3sFBP3zjiIUJUQLgWMfw9+m
9/I/51qM8S0fXDYP8J73RRT/Ft4ocCcYLWuaUbYK5y8QQepDOxsAsqOvmvEeMFdf
RYf44UDkxpCxhGAhjzp3Ka0xdOQxZLpOCP6BZeIfozqQxTHtDEnO+rGHad+BY2AY
D4rZq3ERdfwc7xmreNMKyy4u2IOl0IGzJionzD+2YOkf26mLTe7kMXMs/Ps7LO08
tGhmIIre6A40ITOsKjU5/mf55vlJoz5yzIjST5hWJECR0ufpuGD3d72tfn9ZCimM
X76vcmUCgYEA2z4aEqoj+CiK0r2AMs594MiY1HyxUuC7Sy+YUQcsAsE96ac94NdN
tvr3akgJCmMofZzGLcA0V1ETP6B6eAfaitRY34RFskri6FlMtPpvB6Wm5XyE/xlM
DkgkLCfySE8Ln10Lew1Q/S/WAo1um8vDUO8p6dlCh3RCjghk7bAxmiMCgYEAy43N
kGPlWwE9j9IM1kG0WYfjjrYC4vPR9AXbTFKYf+mklVZu9RJJ8HxT0onZJf9+vlO0
w2GZER9kjmg2K9LTPMa/keQrt0ZaUus8pbaHgOIpAcz+6EpwVQFe/n/9QZBBb3Cu
oN7Ge1sfuBQR1CeAC4lgqDEgz5nClAXW5wTMN+cCgYEAvMpDRWNBSgYPVN1dsWJi
vte90uv0/jsKzPmVHeEhItYobDVZcW21PCXsO5cAQfOVAGWpuefSqoXkH1wfWZDZ
vcaRKRgLtDYMIqwTA5zLUzhv+Rk6pTixZ3Lzwxo65c07YuWKZ1HWNc+lZ9lGL95M
uDraSsaNJXsVfJz53Dtm2yUCgYBeradmuMBOkwYiZi4oXklXt3glwg0XqRcH7M1y
85wRKwitmZVkkkwn+nw2mn2RSgSW3HJgyn2a1EI+ZsSDn703MK6cWkfnKGcM2HPO
FFd0oD04pDQQsccMEuYvdDLFEycMgZoII3aom9rmERe12WWaeByoPqmnRjqWBR1P
OREQEwKBgQChDAG4iuUGV2ucO815qg8Scq4wolpBoYOV1IYW4CQ9gQoiSZEfr7FH
o4msNVGmQw5aYraFfeY+a9U6sRCVue8YFA9Tx7/lOGltGGRkoSLb0zvBUkoa9C5o
bAr1Kb5osO6Km+kGNBAZo94CqKJio+NzSsAru6xgsFmvwGHZTz8YQw==
-----END RSA PRIVATE KEY-----'" | awk ' / Secret href / {print $5}')

CONTAINER=$(su - stack -c "barbican secret container create --type certificate -s 'certificate=$CERT' -s 'private_key=$KEY'" | awk ' / Container href / {print $5}')
NETWORK=$(su - stack -c "neutron subnet-list" | awk '/ private-subnet / {print $2}')
PROJECT_ID=$(su - stack -c "openstack token issue" | awk '/ project_id / {print $4}')

cat <<EOF >> /opt/stack/.profile
export DEFAULT_TLS_CONTAINER='$CONTAINER'
export DEFAULT_NETWORK='$NETWORK'
export PROJECT_ID="${PROJECT_ID:0:8}-${PROJECT_ID:8:4}-${PROJECT_ID:12:4}-${PROJECT_ID:16:4}-${PROJECT_ID:20}"
EOF
wget -O - https://github.com/rm-you/devstack_deploy/blob/master/profile >> /opt/stack/.profile

# Drop into a shell
su - stack
