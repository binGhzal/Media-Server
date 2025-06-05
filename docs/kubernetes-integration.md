# Kubernetes Integration

The Proxmox Template Creator provides comprehensive Kubernetes integration, enabling you to create VM templates with pre-configured Kubernetes environments and workloads.

## Overview

Kubernetes integration includes:

- **Kubernetes Installation**: Automatic K8s cluster setup with kubeadm
- **Container Runtime**: Containerd or Docker runtime configuration
- **Network CNI**: Calico, Flannel, or Weave network configuration
- **Workload Templates**: Pre-built Kubernetes applications and services
- **Monitoring**: Prometheus, Grafana, and metrics-server integration
- **Ingress**: NGINX or Traefik ingress controller setup

## Kubernetes Templates

### Available Templates

| Template           | Description              | Components                                        |
| ------------------ | ------------------------ | ------------------------------------------------- |
| `control-plane`    | Kubernetes master node   | API server, etcd, scheduler, controller-manager   |
| `worker-node`      | Kubernetes worker node   | kubelet, kube-proxy, container runtime            |
| `monitoring-stack` | Cluster monitoring       | Prometheus, Grafana, AlertManager, metrics-server |
| `ingress-nginx`    | NGINX ingress controller | NGINX ingress, cert-manager, external-dns         |
| `logging-stack`    | Centralized logging      | ELK stack (Elasticsearch, Logstash, Kibana)       |
| `storage-cluster`  | Distributed storage      | Rook-Ceph, Longhorn, or GlusterFS                 |
| `ci-cd-pipeline`   | CI/CD for Kubernetes     | ArgoCD, Tekton, Harbor registry                   |
| `service-mesh`     | Service mesh             | Istio or Linkerd                                  |

### Using Kubernetes Templates

#### Interactive Mode

1. Run the script: `./create-template.sh`
2. Select "Kubernetes Template Integration"
3. Choose cluster role (control-plane or worker)
4. Select additional workloads
5. Configure networking and storage

#### CLI Mode

```bash
# Create control plane template
./create-template.sh --k8s-template control-plane --template-name k8s-master

# Create worker node template
./create-template.sh --k8s-template worker-node --template-name k8s-worker

# Create monitoring stack
./create-template.sh --k8s-template monitoring-stack --template-name k8s-monitoring
```

## Cluster Architecture

### Control Plane Components

```yaml
# Kubernetes control plane configuration
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.0
controlPlaneEndpoint: "k8s-api.example.com:6443"
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "10.244.0.0/16"
etcd:
  local:
    dataDir: "/var/lib/etcd"
dns:
  type: CoreDNS
```

### Worker Node Configuration

```yaml
# Kubernetes worker node configuration
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: "abcdef.0123456789abcdef"
    apiServerEndpoint: "k8s-api.example.com:6443"
nodeRegistration:
  kubeletExtraArgs:
    node-labels: "node-role.kubernetes.io/worker=worker"
```

## Network Configuration

### CNI Plugins

#### Calico (Default)

```yaml
# Calico network configuration
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
        cidr: 10.244.0.0/16
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
```

#### Flannel (Alternative)

```yaml
# Flannel network configuration
net-conf.json: |
  {
    "Network": "10.244.0.0/16",
    "Backend": {
      "Type": "vxlan"
    }
  }
```

### Network Policies

Automatic network policy configuration:

```yaml
# Default network policies
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

## Storage Configuration

### Storage Classes

```yaml
# Local storage class
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

### Persistent Volumes

```yaml
# Local persistent volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: local-storage
  local:
    path: /mnt/disks/ssd1
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - worker-node-1
```

## Workload Templates

### Monitoring Stack

```yaml
# Prometheus configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'kubernetes-apiservers'
      kubernetes_sd_configs:
      - role: endpoints
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
```

### Ingress Controller

```yaml
# NGINX Ingress Controller
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-ingress-controller
  namespace: ingress-nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-ingress-controller
  template:
    metadata:
      labels:
        app: nginx-ingress-controller
    spec:
      containers:
        - name: nginx-ingress-controller
          image: k8s.gcr.io/ingress-nginx/controller:v1.8.1
          args:
            - /nginx-ingress-controller
            - --configmap=$(POD_NAMESPACE)/nginx-configuration
```

## Security Configuration

### RBAC Policies

```yaml
# Service account and RBAC
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k8s-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: k8s-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: k8s-admin
    namespace: kube-system
```

### Pod Security Standards

```yaml
# Pod security standards
apiVersion: v1
kind: Namespace
metadata:
  name: secure-namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Network Security

```yaml
# Network policy for secure communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: secure-namespace
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: secure-namespace
```

## High Availability

### Control Plane HA

```yaml
# HA control plane configuration
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
controlPlaneEndpoint: "k8s-api-lb.example.com:6443"
etcd:
  external:
    endpoints:
      - "https://etcd1.example.com:2379"
      - "https://etcd2.example.com:2379"
      - "https://etcd3.example.com:2379"
```

### Load Balancer Configuration

```yaml
# HAProxy configuration for K8s API
global
daemon
defaults
mode http
timeout connect 5000ms
timeout client 50000ms
timeout server 50000ms
frontend k8s-api
bind *:6443
mode tcp
default_backend k8s-masters
backend k8s-masters
mode tcp
balance roundrobin
server master1 192.168.1.10:6443 check
server master2 192.168.1.11:6443 check
server master3 192.168.1.12:6443 check
```

## Monitoring and Observability

### Prometheus Monitoring

```yaml
# Prometheus ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kubernetes-cluster-monitoring
spec:
  selector:
    matchLabels:
      app: kubernetes
  endpoints:
    - port: https
      scheme: https
      tlsConfig:
        caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        serverName: kubernetes
      bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
```

### Grafana Dashboards

Pre-configured Grafana dashboards for:

- Cluster overview
- Node metrics
- Pod metrics
- Network monitoring
- Storage monitoring
- Application performance

### Logging

```yaml
# Fluent Bit log collection
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: logging
spec:
  selector:
    matchLabels:
      name: fluent-bit
  template:
    metadata:
      labels:
        name: fluent-bit
    spec:
      containers:
        - name: fluent-bit
          image: fluent/fluent-bit:latest
          volumeMounts:
            - name: varlog
              mountPath: /var/log
            - name: varlibdockercontainers
              mountPath: /var/lib/docker/containers
              readOnly: true
```

## Cluster Management

### kubectl Configuration

```bash
# kubectl configuration
export KUBECONFIG=/etc/kubernetes/admin.conf

# Verify cluster status
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces
```

### Helm Package Manager

```bash
# Install Helm
curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar -xz
mv linux-amd64/helm /usr/local/bin/

# Add Helm repositories
helm repo add stable https://charts.helm.sh/stable
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Cluster Upgrades

```bash
# Upgrade Kubernetes cluster
kubeadm upgrade plan
kubeadm upgrade apply v1.28.1

# Upgrade worker nodes
kubectl drain worker-node-1 --ignore-daemonsets
kubeadm upgrade node
kubectl uncordon worker-node-1
```

## Troubleshooting

### Common Issues

#### Cluster Communication Problems

```bash
# Check cluster status
kubectl get cs
kubectl get nodes

# Check pod networking
kubectl run test-pod --image=busybox --command -- sleep 3600
kubectl exec -it test-pod -- nslookup kubernetes.default
```

#### CNI Issues

```bash
# Check CNI pods
kubectl get pods -n kube-system | grep -E 'calico|flannel|weave'

# Restart CNI pods
kubectl delete pods -n kube-system -l k8s-app=calico-node
```

#### Storage Issues

```bash
# Check storage classes
kubectl get storageclass

# Check persistent volumes
kubectl get pv
kubectl get pvc --all-namespaces
```

For more detailed troubleshooting, see [K8s Templates](k8s-templates.md) and [Troubleshooting Guide](troubleshooting.md).
