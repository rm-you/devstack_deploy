# Fix permissions on current tty so screens can attach
sudo chmod go+rw `tty`

# Make sure we have git configured for cherry-picks
git config --global user.email "you@example.com"
git config --global user.name "Your Name"

# Add environment variables for auth/endpoints
source /opt/stack/devstack/openrc admin admin >/dev/null
export BARBICAN_ENDPOINT="http://localhost:9311"

# Set some utility variables
PROJECT_ID=$(openstack token issue | awk '/ project_id / {print $4}')
export PROJECT_ID="${PROJECT_ID:0:8}-${PROJECT_ID:8:4}-${PROJECT_ID:12:4}-${PROJECT_ID:16:4}-${PROJECT_ID:20}"
export DEFAULT_NETWORK=$(openstack subnet list | awk '/ private-subnet / {print $2}')
export DEFAULT_NETWORK_IPV6=$(openstack subnet list | awk '/ ipv6-private-subnet / {print $2}')

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
  openstack server create --image cirros-0.3.5-x86_64-disk --flavor 2 --nic net-id=$PRIVATE_NETWORK member1 --security-group member --key-name default
  openstack server create --image cirros-0.3.5-x86_64-disk --flavor 2 --nic net-id=$PRIVATE_NETWORK member2 --security-group member --key-name default --wait
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

# Create a LB with Octavia
function create_lb() {
  openstack loadbalancer create --name lb1 --vip-subnet $DEFAULT_NETWORK
  watch openstack loadbalancer show lb1
}

function create_lb_ipv6() {
  openstack loadbalancer create --name lb1 --vip-subnet $DEFAULT_NETWORK_IPV6
  watch openstack loadbalancer show lb1
}

# Create a Listener with Octavia
function create_listener() {
  openstack loadbalancer listener create --protocol TERMINATED_HTTPS --protocol-port 443 --name listener1 --default-tls-container-ref $DEFAULT_TLS_CONTAINER lb1
  watch openstack loadbalancer show lb1
}

# Create a Pool with Octavia
function create_pool() {
  openstack loadbalancer pool create --protocol HTTP --lb-algorithm ROUND_ROBIN --name pool1 --listener listener1
  watch openstack loadbalancer show lb1
}

# Create Members with Octavia
function create_members() {
  # Get member ips again because we might be in a different shell
  if [ -z "$MEMBER1_IP" ]; then
    export MEMBER1_IP=$(openstack server show member1 | awk '/ addresses / {a = substr($4, 9, length($4)-9); if (a ~ "\\.") print a; else print $5}')
  fi
  openstack loadbalancer member create --address  $MEMBER1_IP --protocol-port 80 --subnet-id $(openstack subnet list | awk '/ private-subnet / {print $2}') --name member1 pool1
  if [ -z "$MEMBER2_IP" ]; then
    # Get the second memberIP while we're waiting anyway
    export MEMBER2_IP=$(openstack server show member2 | awk '/ addresses / {a = substr($4, 9, length($4)-9); if (a ~ ":") print a; else print $5}')
  fi
  watch openstack loadbalancer show lb1 # TODO: Make a proper wait, right now just assumes you will ctrl-c when ready
  openstack loadbalancer member create --address  $MEMBER2_IP --protocol-port 80 --subnet-id $(openstack subnet list | awk '/ private-subnet / {print $2}') --name member2 pool1
}

