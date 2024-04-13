# KindScaler: Node Management for KinD Clusters

KinD is a solution that allows to quickly create local Kubernetes clusters, ideal for development or testing tasks. However, once these clusters are created, KinD does not have built-in features to modify the cluster configuration by adding or removing nodes, whether they are control-planes or workers, and the entire cluster would need to be regenerated from scratch.

KindScaler comes to facilitate this task. After dissecting how KinD creates and adds different nodes and roles to the cluster, this bash script has been created and allows to add both workers and control planes.

# How-to

```
./kindscaler.sh <clustername> -r <control-plane|worker> -c <count>
```

For example, adding 3 workers to cluster `kind`:

```
$kind create cluster --config cluster.yaml
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.28.0) 🖼
 ✓ Preparing nodes 📦 📦 📦  
 ✓ Writing configuration 📜 
 ✓ Starting control-plane 🕹 
 ✓ Installing CNI 🔌 
 ✓ Installing StorageClass 💾 
 ✓ Joining worker nodes 🚜 
Set kubectl context to "kind-kind"                                                                                                                          
You can now use your cluster with:                                                                                                                          
                                                                                                                                                            
kubectl cluster-info --context kind-kind                                                                                                                    
                                                                                                                                                            
Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/                                                                     
                                                                                                                                                            
$kubectl get nodes                                                                                                   
NAME                 STATUS   ROLES           AGE   VERSION
kind-control-plane   Ready    control-plane   34s   v1.28.0
kind-worker          Ready    <none>          13s   v1.28.0
kind-worker2         Ready    <none>          8s    v1.28.0
                                                                                                                                                            
$./kindscaler.sh kind -r worker -c 3
Adding kind-worker3 node to kind cluster... Done!
Adding kind-worker4 node to kind cluster... Done!
Adding kind-worker5 node to kind cluster... Done!
                                                                                                                                                            
$kubectl get nodes
NAME                 STATUS   ROLES           AGE    VERSION
kind-control-plane   Ready    control-plane   109s   v1.28.0
kind-worker          Ready    <none>          88s    v1.28.0
kind-worker2         Ready    <none>          83s    v1.28.0
kind-worker3         Ready    <none>          49s    v1.28.0
kind-worker4         Ready    <none>          36s    v1.28.0
kind-worker5         Ready    <none>          7s     v1.28.0

```

## Deleting nodes

```
kubectl delete node <nodename>
docker stop <container>
docker container rm <container>
```
