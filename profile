# Fix permissions on current tty so screens can attach
sudo chmod go+rw `tty`

# Add environment variables for auth/endpoints
source /opt/stack/devstack/openrc admin admin >/dev/null
#export BARBICAN_ENDPOINT="http://localhost:9311"

# Set some utility variables
PROJECT_ID=$(openstack token issue | awk '/ project_id / {print $4}')
export PROJECT_ID="${PROJECT_ID:0:8}-${PROJECT_ID:8:4}-${PROJECT_ID:12:4}-${PROJECT_ID:16:4}-${PROJECT_ID:20}"
export DEFAULT_NETWORK=$(openstack subnet list | awk '/ private-subnet / {print $2}')

# Make pretty-printing json easy
alias json="python -mjson.tool"

# Make sshing to amps easy
alias ossh="ssh -i /etc/octavia/.ssh/octavia_ssh_key -l ubuntu"

# Run this to generate nova VMs as a test backend
function gen_backend() {
  ssh-keygen -f /opt/stack/.ssh/id_rsa -t rsa -N '' -q
  openstack keypair create --public-key ~/.ssh/id_rsa.pub default
  openstack security group create member
  openstack security group rule create --protocol icmp member
  openstack security group rule create --protocol tcp --dst-port 22 member
  openstack security group rule create --protocol tcp --dst-port 80 member
  openstack security group rule create --protocol icmpv6 --ethertype IPv6 --remote-ip ::/0 member
  openstack security group rule create --protocol tcp --dst-port 22 --ethertype IPv6 --remote-ip ::/0 member
  openstack security group rule create --protocol tcp --dst-port 80 --ethertype IPv6 --remote-ip ::/0 member
  PRIVATE_NETWORK=$(openstack network list | awk '/ private / {print $2}')
  openstack server create --image cirros-0.3.3-x86_64-disk --flavor 2 --nic net-id=$PRIVATE_NETWORK member1 --security-group member --key-name default
  openstack server create --image cirros-0.3.3-x86_64-disk --flavor 2 --nic net-id=$PRIVATE_NETWORK member2 --security-group member --key-name default --wait
  sleep 15
  if [ -z "$MEMBER1_IP" ]; then
    export MEMBER1_IP=$(openstack server show member1 | awk '/ addresses / {a = substr($4, 9, length($4)-9); if (a ~ "\\.") print a; else print $5}')
  fi
  if [ -z "$MEMBER2_IP" ]; then
    export MEMBER2_IP=$(openstack server show member2 | awk '/ addresses / {a = substr($4, 9, length($4)-9); if (a ~ "\\.") print a; else print $5}')
  fi
  ssh -o StrictHostKeyChecking=no cirros@$MEMBER1_IP "(while true; do echo -e 'HTTP/1.0 200 OK\r\n\r\nIt Works: member1' | sudo nc -l -p 80 ; done)&"
  ssh -o StrictHostKeyChecking=no cirros@$MEMBER2_IP "(while true; do echo -e 'HTTP/1.0 200 OK\r\n\r\nIt Works: member2' | sudo nc -l -p 80 ; done)&"
  sleep 5
  curl $MEMBER1_IP
  curl $MEMBER2_IP
}

# Create a LB with Neutron-LBaaS
function create_lb() {
  neutron lbaas-loadbalancer-create $DEFAULT_NETWORK --name lb1
  watch neutron lbaas-loadbalancer-show lb1
}

# Create a Listener with Neutron-LBaaS
function create_listener() {
  #neutron lbaas-listener-create --loadbalancer lb1 --protocol-port 443 --protocol TERMINATED_HTTPS --name listener1 --default-tls-container=$DEFAULT_TLS_CONTAINER
  neutron lbaas-listener-create --loadbalancer lb1 --protocol-port 80 --protocol HTTP --name listener1
  watch neutron lbaas-loadbalancer-show lb1
}

# Create a Pool with Neutron-LBaaS
function create_pool() {
  neutron lbaas-pool-create --name pool1 --protocol HTTP --listener listener1 --lb-algorithm ROUND_ROBIN
  watch neutron lbaas-loadbalancer-show lb1
}

# Create Members with Neutron-LBaaS
function create_members() {
  # Get member ips again because we might be in a different shell
  if [ -z "$MEMBER1_IP" ]; then
    export MEMBER1_IP=$(openstack server show member1 | awk '/ addresses / {a = substr($4, 9, length($4)-9); if (a ~ "\\.") print a; else print $5}')
  fi
  neutron lbaas-member-create pool1 --address $MEMBER1_IP --protocol-port 80 --subnet $(neutron subnet-list | awk '/ private-subnet / {print $2}') --name member1
  if [ -z "$MEMBER2_IP" ]; then
    # Get the second memberIP while we're waiting anyway
    export MEMBER2_IP=$(openstack server show member2 | awk '/ addresses / {a = substr($4, 9, length($4)-9); if (a ~ "\\.") print a; else print $5}')
  fi
  watch neutron lbaas-loadbalancer-show lb1  # TODO: Make a proper wait, right now just assumes you will ctrl-c when ready
  neutron lbaas-member-create pool1 --address $MEMBER2_IP --protocol-port 80 --subnet $(neutron subnet-list | awk '/ private-subnet / {print $2}') --name member2
}

