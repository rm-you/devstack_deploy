# Fix permissions on current tty so screens can attach
sudo chmod go+rw `tty`

# Add environment variables for auth/endpoints
source /opt/stack/devstack/openrc admin admin
export BARBICAN_ENDPOINT="http://localhost:9311"

# Set some utility variables
PROJECT_ID=$(openstack token issue | awk '/ project_id / {print $4}')
export PROJECT_ID="${PROJECT_ID:0:8}-${PROJECT_ID:8:4}-${PROJECT_ID:12:4}-${PROJECT_ID:16:4}-${PROJECT_ID:20}"
export DEFAULT_NETWORK=$(neutron subnet-list | awk '/ private-subnet / {print $2}')

# Make pretty-printing json easy
alias json="python -mjson.tool"

# Run this to generate nova VMs as a test backend
function gen_backend() {
  ssh-keygen -f /opt/stack/.ssh/id_rsa -t rsa -N '' -q
  nova keypair-add default --pub-key ~/.ssh/id_rsa.pub 
  neutron security-group-create member
  nova secgroup-add-rule member tcp 22 22 0.0.0.0/0
  nova secgroup-add-rule member tcp 80 80 0.0.0.0/0
  nova secgroup-add-rule member icmp -1 -1 0.0.0.0/0
  PRIVATE_NETWORK=$(neutron net-list | awk '/ private / {print $2}')
  nova boot --image cirros-0.3.0-x86_64-disk --flavor 2 --nic net-id=$PRIVATE_NETWORK member1 --security-groups member --key-name default
  nova boot --image cirros-0.3.0-x86_64-disk --flavor 2 --nic net-id=$PRIVATE_NETWORK member2 --security-groups member --key-name default --poll
  sleep 15
  export MEMBER1_IP=$(nova show member1 | awk '/private network/ {a = substr($5, 0, length($5)-1); if (a ~ "\\.") print a; else print $6}')
  export MEMBER2_IP=$(nova show member2 | awk '/private network/ {a = substr($5, 0, length($5)-1); if (a ~ "\\.") print a; else print $6}')
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
  neutron lbaas-listener-create --loadbalancer lb1 --protocol-port 443 --protocol TERMINATED_HTTPS --name listener1 --default-tls-container=$DEFAULT_TLS_CONTAINER
  watch neutron lbaas-loadbalancer-show lb1
}

# Create a Pool with Neutron-LBaaS
function create_pool() {
  neutron lbaas-pool-create --name pool1 --protocol HTTP --listener listener1 --lb-algorithm ROUND_ROBIN
  watch neutron lbaas-loadbalancer-show lb1
}

# Create Members with Neutron-LBaaS
function create_members() {
  export MEMBER1_IP=$(nova show member1 | awk '/private network/ {a = substr($5, 0, length($5)-1); if (a ~ "\\.") print a; else print $6}')
  neutron lbaas-member-create pool1 --address $MEMBER1_IP --protocol-port 80 --subnet $(neutron subnet-list | awk '/ private-subnet / {print $2}') 
  watch neutron lbaas-loadbalancer-show lb1  # TODO: Make a proper wait, right now just assumes you will ctrl-c when ready
  export MEMBER2_IP=$(nova show member2 | awk '/private network/ {a = substr($5, 0, length($5)-1); if (a ~ "\\.") print a; else print $6}')
  neutron lbaas-member-create pool1 --address $MEMBER2_IP --protocol-port 80 --subnet $(neutron subnet-list | awk '/ private-subnet / {print $2}') 
}

