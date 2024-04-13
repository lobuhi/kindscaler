#!/bin/bash

# Check for required commands
if ! command -v kind &> /dev/null; then
    echo "kind command not found, please install kind to use this script."
    exit 1
fi

# Check input parameters
if [ $# -lt 4 ]; then
    echo "Usage: $0 <cluster-name> --role <role> --count <count>"
    echo "--role must be either 'control-plane' or 'worker'"
    echo "--count must be a positive integer"
    exit 1
fi

# Parse command line arguments
CLUSTER_NAME=$1
shift  # shift the first parameter off the parameters list
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r|--role) ROLE="$2"; shift ;;
        -c|--count) COUNT="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Validate role
if [ "$ROLE" != "control-plane" ] && [ "$ROLE" != "worker" ]; then
    echo "Role must be 'control-plane' or 'worker'"
    exit 1
fi

# Validate count
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -le 0 ]; then
    echo "Count must be a positive integer"
    exit 1
fi

# Get existing nodes and determine the highest node index for the given role
highest_index=0
existing_nodes=$(kind get nodes --name "$CLUSTER_NAME")
for node in $existing_nodes; do
    if [[ $node == "$CLUSTER_NAME-$ROLE"* ]]; then
        suffix=$(echo $node | sed -e "s/^$CLUSTER_NAME-$ROLE//")
        if [[ "$suffix" =~ ^[0-9]+$ ]] && [ "$suffix" -gt "$highest_index" ]; then
            highest_index=$suffix
        fi
    fi
done

# Add nodes based on the highest found index and the count specified
start_index=$(($highest_index + 1))
end_index=$(($highest_index + $COUNT))
for i in $(seq $start_index $end_index); do
    # Determine the name of the container for the specified role
    CONTAINER_NAME=$CLUSTER_NAME-$ROLE

    # Copy the kubeadm file from the container
    docker cp $CONTAINER_NAME:/kind/kubeadm.conf kubeadm-$i.conf > /dev/null 2>&1

    # Replace the container role name with specific node name in the kubeadm file
    sed -i "s/$CONTAINER_NAME$/$CONTAINER_NAME$i/g" "./kubeadm-$i.conf"

    # Update IP addresses
    # Assume the file contains parameters 'advertiseAddress' and 'node-ip' with typical IP values
    # Extract the IP address used, increment it, and replace it in the file
    ORIGINAL_IP=$(grep -oP '(advertiseAddress|node-ip):\s*\K([0-9]{1,3}(\.[0-9]{1,3}){3})' "./kubeadm-$i.conf" | head -1)
    IMAGE=$(docker ps | grep $CLUSTER_NAME | awk '{print $2}' | head -1)
    if [ "$ROLE" == "worker" ]; then
    # Command for worker nodes
    	echo -n "Adding $CLUSTER_NAME-$ROLE$i node to $CLUSTER_NAME cluster... "
        docker run --name $CLUSTER_NAME-$ROLE$i --hostname $CLUSTER_NAME-$ROLE$i \
        --label io.x-k8s.kind.role=$ROLE --privileged \
        --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
        --tmpfs /tmp --tmpfs /run --volume /var \
        --volume /lib/modules:/lib/modules:ro -e KIND_EXPERIMENTAL_CONTAINERD_SNAPSHOTTER \
        --detach --tty --label io.x-k8s.kind.cluster=kind --net kind \
        --restart=on-failure:1 --init=false $IMAGE > /dev/null 2>&1
        NEW_IP=$(docker inspect $CLUSTER_NAME-$ROLE$i | grep IPAddress | tail -1 | cut -d "\"" -f 4)
        sed -i -r "s/$ORIGINAL_IP/$NEW_IP/g" "./kubeadm-$i.conf"
        sleep 5
        docker cp kubeadm-$i.conf $CLUSTER_NAME-$ROLE$i:/kind/kubeadm.conf > /dev/null 2>&1
        docker exec --privileged $CLUSTER_NAME-$ROLE$i kubeadm join --config /kind/kubeadm.conf --skip-phases=preflight --v=6 > /dev/null 2>&1
        rm -f kubeadm-*.conf
        echo "Done!"
    elif [ "$ROLE" == "control-plane" ]; then
    # Generate a random port number between 36000 and 36999 for control-plane nodes
        PORT=$(shuf -i 39000-39999 -n 1)   
    # Command for control-plane nodes
        echo -n "Adding $CLUSTER_NAME-$ROLE$i node to $CLUSTER_NAME cluster... "
        docker run --name $CLUSTER_NAME-$ROLE$i --hostname $CLUSTER_NAME-$ROLE$i \
        --label io.x-k8s.kind.role=$ROLE --privileged \
        --security-opt seccomp=unconfined --publish=127.0.0.1:$PORT:6443/TCP \
        --security-opt apparmor=unconfined --tmpfs /tmp --tmpfs /run --volume /var \
        --volume /lib/modules:/lib/modules:ro -e KIND_EXPERIMENTAL_CONTAINERD_SNAPSHOTTER \
        --detach --tty --label io.x-k8s.kind.cluster=kind --net kind \
        --restart=on-failure:1 --init=false $IMAGE > /dev/null 2>&1
        NEW_IP=$(docker inspect $CLUSTER_NAME-$ROLE$i | grep IPAddress | tail -1 | cut -d "\"" -f 4)
        sed -i -r "s/$ORIGINAL_IP/$NEW_IP/g" "./kubeadm-$i.conf"
        sleep 10
        docker exec --privileged $CLUSTER_NAME-$ROLE$i mkdir /etc/kubernetes/pki/
        docker exec --privileged $CLUSTER_NAME-$ROLE$i mkdir /etc/kubernetes/pki/etcd
        docker cp kubeadm-$i.conf $CLUSTER_NAME-$ROLE$i:/kind/kubeadm.conf > /dev/null 2>&1
        mkdir .kindadd
        docker cp $CLUSTER_NAME-$ROLE:/etc/kubernetes/pki/ca.crt .kindadd/ca.crt
        docker cp .kindadd/ca.crt $CLUSTER_NAME-$ROLE$i:/etc/kubernetes/pki/ca.crt
        
        docker cp $CLUSTER_NAME-$ROLE:/etc/kubernetes/pki/ca.key .kindadd/ca.key
        docker cp .kindadd/ca.key $CLUSTER_NAME-$ROLE$i:/etc/kubernetes/pki/ca.key
        
        docker cp $CLUSTER_NAME-$ROLE:/etc/kubernetes/pki/front-proxy-ca.crt .kindadd/front-proxy-ca.crt
        docker cp .kindadd/front-proxy-ca.crt $CLUSTER_NAME-$ROLE$i:/etc/kubernetes/pki/front-proxy-ca.crt
        
        docker cp $CLUSTER_NAME-$ROLE:/etc/kubernetes/pki/front-proxy-ca.key .kindadd/front-proxy-ca.key
        docker cp .kindadd/front-proxy-ca.key $CLUSTER_NAME-$ROLE$i:/etc/kubernetes/pki/front-proxy-ca.key
        
        docker cp $CLUSTER_NAME-$ROLE:/etc/kubernetes/pki/sa.pub .kindadd/sa.pub
        docker cp .kindadd/sa.pub $CLUSTER_NAME-$ROLE$i:/etc/kubernetes/pki/sa.pub

        docker cp $CLUSTER_NAME-$ROLE:/etc/kubernetes/pki/sa.key .kindadd/sa.key
        docker cp .kindadd/sa.key $CLUSTER_NAME-$ROLE$i:/etc/kubernetes/pki/sa.key
        mkdir .kindadd/etcd
        docker cp $CLUSTER_NAME-$ROLE:/etc/kubernetes/pki/etcd/ca.crt .kindadd/etcd/ca.crt
        docker cp .kindadd/etcd/ca.crt $CLUSTER_NAME-$ROLE$i:/etc/kubernetes/pki/etcd/ca.crt
        
        docker cp $CLUSTER_NAME-$ROLE:/etc/kubernetes/pki/etcd/ca.key .kindadd/etcd/ca.key
        docker cp .kindadd/etcd/ca.key $CLUSTER_NAME-$ROLE$i:/etc/kubernetes/pki/etcd/ca.key
        docker exec --privileged $CLUSTER_NAME-$ROLE$i kubeadm join --config /kind/kubeadm.conf --skip-phases=preflight --v=6 > /dev/null 2>&1
        rm -Rf .kindadd kubeadm-*.conf
        echo "Done!"
else
    echo "Invalid role specified: $ROLE"
    exit 1
fi

done



