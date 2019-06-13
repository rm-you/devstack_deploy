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
export PRIVATE_SUBNET=$(openstack subnet list | awk '/ private-subnet / {print $2}')
export PRIVATE_SUBNET_IPV6=$(openstack subnet list | awk '/ ipv6-private-subnet / {print $2}')
export PUBLIC_SUBNET=$(openstack subnet list | awk '/ public-subnet / {print $2}')
export PUBLIC_SUBNET_IPV6=$(openstack subnet list | awk '/ ipv6-public-subnet / {print $2}')

# Make pretty-printing json easy
alias json="python -mjson.tool"

# Make sshing to amps easy
alias ossh="ssh -i /etc/octavia/.ssh/octavia_ssh_key -l ubuntu"

# Other aliases for quality of life
alias oslb='openstack loadbalancer'
alias oss='openstack server'
alias gs='git status'
alias gd='git diff'
alias gp='git pull'
alias gl='git log --stat'

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
  openstack server create --image cirros-0.4.0-x86_64-disk --flavor m1.tiny --nic net-id=$PRIVATE_NETWORK member1 --security-group member --key-name default
  openstack server create --image cirros-0.4.0-x86_64-disk --flavor m1.tiny --nic net-id=$PRIVATE_NETWORK member2 --security-group member --key-name default --wait
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

# Wait for LB to go ACTIVE
function wait_for_status() {
  STATUS=${1:-"ACTIVE"}
  echo -n "Waiting for lb1 to go ACTIVE..."
  LB1=$(openstack loadbalancer show lb1 -f json | jq -r .provisioning_status)
  while [ "$LB1" != "$STATUS" ]; do
    if [ "$LB1" == "ERROR" ]; then
      echo " ERROR!"
      return 1
    fi
    echo -n "."
    sleep 1
    LB1=$(openstack loadbalancer show lb1 -f json | jq -r .provisioning_status)
  done
  echo
}

# Create a LB with Octavia
function create_lb() {
  openstack loadbalancer create --name lb1 --vip-subnet $PUBLIC_SUBNET
  wait_for_status
  openstack loadbalancer show lb1
}

function create_lb_ipv6() {
  openstack loadbalancer create --name lb1 --vip-subnet $PUBLIC_SUBNET_IPV6
  wait_for_status
  openstack loadbalancer show lb1
}

function create_lb_addvip() {
  TOKEN=$(openstack token issue -f value -c id)
  OCTAVIA_BASE_URL=$(openstack endpoint list --service octavia --interface public -c URL -f value)
  curl -s -X POST -H "Content-Type: application/json" -H "X-Auth-Token: $TOKEN" -d "{\"loadbalancer\": {\"vip_subnet_id\": \"${PUBLIC_SUBNET}\", \"name\": \"lb1\", \"additional_vips\": [{\"subnet_id\": \"${PUBLIC_SUBNET_IPV6}\"}]}}" ${OCTAVIA_BASE_URL}/v2.0/lbaas/loadbalancers | jq
  wait_for_status
}

# Create a Listener with Octavia
function create_listener() {
  openstack loadbalancer listener create --protocol TERMINATED_HTTPS --protocol-port 443 --name listener1 --default-tls-container-ref $DEFAULT_TLS_CONTAINER lb1
  wait_for_status
}

# Create a Pool with Octavia
function create_pool() {
  openstack loadbalancer pool create --protocol HTTP --lb-algorithm ROUND_ROBIN --name pool1 --listener listener1
  wait_for_status
}

# Create a Health Monitor with Octavia
function create_hm() {
  openstack loadbalancer healthmonitor create --delay 5 --timeout 5 --max-retries 3 --type HTTP --name hm1 pool1
  wait_for_status
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
  wait_for_status
  openstack loadbalancer member create --address  $MEMBER2_IP --protocol-port 80 --subnet-id $(openstack subnet list | awk '/ private-subnet / {print $2}') --name member2 pool1
  wait_for_status
}

# Do everything
function create_full() {
  echo "Generating backend member nodes:"
  gen_backend
  echo "Creating lb1:"
  create_lb
  echo "Creating listener1:"
  create_listener
  echo "Creating pool1:"
  create_pool
  echo "Creating hm1:"
  create_hm
  echo "Creating member1 and member2:"
  create_members
  echo "Done!"
}

source ~/.bashrc
