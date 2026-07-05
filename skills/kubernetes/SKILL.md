---
name: kubernetes
description: >
  End-to-end Kubernetes cluster troubleshooting skill. Diagnoses scheduling failures,
  pod lifecycle issues, networking, storage, node health, RBAC, resource exhaustion,
  control plane problems, and workload rollout issues. Uses kubectl, logs, events,
  and cluster state to identify root causes and suggest fixes.
triggers:
  - kubernetes
  - k8s
  - kubectl
  - pod
  - deployment
  - node
  - cluster
  - scheduling
  - CrashLoopBackOff
  - ImagePullBackOff
  - OOMKilled
  - Pending
  - Evicted
---

# Kubernetes Troubleshooting Skill

You are a Kubernetes troubleshooting expert. When the user describes a cluster issue,
follow the structured diagnostic approach below. Always start by identifying which
failure domain the problem falls into, then run the relevant diagnostic commands.

## Prerequisites Check

Before diving in, confirm the user has access:

```bash
kubectl cluster-info
kubectl version --short 2>/dev/null || kubectl version
kubectl auth can-i '*' '*' --all-namespaces  # check if admin
```

Ask the user for:
- **Namespace** (default: `default`)
- **Resource name** (pod, deployment, service, etc.)
- **Symptom** (what they're seeing)

---

## 1. SCHEDULING FAILURES (Pod stuck in Pending)

The Kubernetes scheduler works in 4 phases:

### Phase 1: Filter (mandatory criteria)
Eliminates nodes that cannot run the pod. Common filter failures:

| Filter | Checks | Diagnostic |
|--------|--------|------------|
| Resource availability | CPU/memory requests vs allocatable | `kubectl describe node <node> \| grep -A5 "Allocated resources"` |
| Taints/Tolerations | Node taints vs pod tolerations | `kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints` |
| Node Affinity | `nodeSelector` / `nodeAffinity` rules | `kubectl get pod <pod> -o jsonpath='{.spec.nodeSelector}'` |
| Volume constraints | PV zone, access mode, node attachment limits | `kubectl get pv -o wide` and `kubectl describe pvc <pvc>` |
| Node readiness | Node condition = Ready | `kubectl get nodes` |
| Pod topology spread | `topologySpreadConstraints` | `kubectl get pod <pod> -o yaml \| grep -A10 topologySpread` |
| Inter-pod affinity | `podAffinity` / `podAntiAffinity` | Check if required pods exist in target topology |

### Phase 2: Score (rank feasible nodes)
Remaining nodes are scored by:
- Resource utilization balance (`LeastRequestedPriority`, `MostRequestedPriority`)
- Topology spread (even distribution across zones/nodes)
- Affinity/anti-affinity preferred rules (soft constraints)
- Image locality (node already has the container image)
- Node preference weights

### Phase 3: Select
Pick the node with the highest composite score.

### Phase 4: Bind
Bind the pod to the selected node (write binding to etcd via API server).

### Diagnostic workflow for Pending pods:

```bash
# Step 1: Check pod events for scheduler messages
kubectl describe pod <pod> -n <ns> | grep -A20 "Events:"

# Step 2: Check if any nodes are available
kubectl get nodes -o wide

# Step 3: Check resource pressure across nodes
kubectl top nodes

# Step 4: Check for resource quotas blocking scheduling
kubectl get resourcequota -n <ns>
kubectl describe resourcequota -n <ns>

# Step 5: Check LimitRange constraints
kubectl get limitrange -n <ns>
kubectl describe limitrange -n <ns>

# Step 6: Check PDB (PodDisruptionBudget) blocking
kubectl get pdb -n <ns>

# Step 7: Check if scheduler is running
kubectl get pods -n kube-system -l component=kube-scheduler

# Step 8: Check scheduler logs
kubectl logs -n kube-system -l component=kube-scheduler --tail=50
```

---

## 2. POD LIFECYCLE FAILURES

### CrashLoopBackOff
The container starts and crashes repeatedly.

```bash
# Check exit code and reason
kubectl describe pod <pod> -n <ns> | grep -A5 "Last State"

# Get current and previous logs
kubectl logs <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous

# Check if it's an OOM kill (exit code 137)
kubectl get pod <pod> -n <ns> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'

# Check resource limits vs actual usage
kubectl top pod <pod> -n <ns>
```

Common causes:
- **Exit code 1**: Application error — read logs
- **Exit code 137**: OOMKilled — increase memory limit or fix memory leak
- **Exit code 139**: Segfault — bad binary or incompatible base image
- **Exit code 126/127**: Command not found — wrong entrypoint/command

### ImagePullBackOff

```bash
# Check the exact error
kubectl describe pod <pod> -n <ns> | grep -A3 "Warning.*Failed"

# Verify image exists
# For Docker Hub:
kubectl run test --image=<image> --dry-run=client -o yaml

# Check imagePullSecrets
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.imagePullSecrets}'
kubectl get secret <secret> -n <ns> -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

Common causes:
- Image tag doesn't exist (typo, not pushed)
- Private registry without `imagePullSecret`
- Registry rate limiting (Docker Hub: 100 pulls/6h for anonymous)
- Node can't reach registry (network/firewall)

### CreateContainerConfigError

```bash
# Usually a missing ConfigMap or Secret reference
kubectl describe pod <pod> -n <ns> | grep -A5 "Warning"
kubectl get configmap -n <ns>
kubectl get secret -n <ns>
```

### Init Container failures

```bash
# Check init container status separately
kubectl get pod <pod> -n <ns> -o jsonpath='{.status.initContainerStatuses}' | jq .
kubectl logs <pod> -n <ns> -c <init-container-name>
```

---

## 3. NODE ISSUES

### Node NotReady

```bash
# Check node conditions
kubectl describe node <node> | grep -A20 "Conditions:"

# Check kubelet logs
journalctl -u kubelet --since "10 minutes ago" --no-pager | tail -50
# or on managed clusters:
kubectl get events --field-selector involvedObject.kind=Node,involvedObject.name=<node>

# Check system resources on the node
kubectl top node <node>
kubectl describe node <node> | grep -A10 "Allocated resources"
```

### Node Pressure (evictions)

| Condition | Trigger | What happens |
|-----------|---------|--------------|
| MemoryPressure | Available memory < threshold | Pods evicted by QoS (BestEffort first) |
| DiskPressure | Available disk < threshold | Image GC, then pod eviction |
| PIDPressure | Available PIDs < threshold | Pod eviction |
| NetworkUnavailable | CNI not configured | Pods can't get IPs |

```bash
# Check for evicted pods
kubectl get pods -n <ns> --field-selector status.phase=Failed | grep Evicted

# Check node conditions
kubectl get nodes -o custom-columns=NAME:.metadata.name,MEMORY_PRESSURE:.status.conditions[?(@.type==\"MemoryPressure\")].status,DISK_PRESSURE:.status.conditions[?(@.type==\"DiskPressure\")].status

# Check if node is cordoned
kubectl get nodes | grep SchedulingDisabled
```

---

## 4. NETWORKING

### Service connectivity

```bash
# Verify service exists and has endpoints
kubectl get svc <service> -n <ns>
kubectl get endpoints <service> -n <ns>

# If endpoints are empty, check label selector match
kubectl get svc <service> -n <ns> -o jsonpath='{.spec.selector}'
kubectl get pods -n <ns> -l <key>=<value>

# Test DNS resolution from inside the cluster
kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never -- nslookup <service>.<ns>.svc.cluster.local

# Test connectivity from a debug pod
kubectl run net-test --rm -it --image=nicolaka/netshoot --restart=Never -- curl -v <service>.<ns>.svc.cluster.local:<port>
```

### DNS issues

```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20

# Check CoreDNS configmap
kubectl get configmap coredns -n kube-system -o yaml
```

### NetworkPolicy blocking traffic

```bash
# List network policies in namespace
kubectl get networkpolicy -n <ns>
kubectl describe networkpolicy -n <ns>

# Check if any policy is denying traffic (default deny present?)
kubectl get networkpolicy -n <ns> -o yaml | grep -A5 "policyTypes"
```

### Ingress issues

```bash
# Check ingress resource
kubectl get ingress -n <ns>
kubectl describe ingress <ingress> -n <ns>

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=30

# Verify backend service exists and has endpoints
kubectl get svc <backend-service> -n <ns>
kubectl get endpoints <backend-service> -n <ns>

# Check TLS certificate
kubectl get secret <tls-secret> -n <ns> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | head -20
```

---

## 5. STORAGE

### PVC stuck in Pending

```bash
# Check PVC events
kubectl describe pvc <pvc> -n <ns>

# Check StorageClass exists and is valid
kubectl get storageclass
kubectl describe storageclass <sc>

# Check if provisioner is running
kubectl get pods -n kube-system | grep -i provisioner

# For static provisioning, check PV availability
kubectl get pv | grep Available

# Check if PV and PVC match (access mode, storage class, capacity, labels)
kubectl get pv -o wide
kubectl get pvc -n <ns> -o wide
```

### Volume mount failures

```bash
# Check pod events for mount errors
kubectl describe pod <pod> -n <ns> | grep -i -A3 "mount\|volume\|attach"

# For multi-attach errors (RWO volume on multiple nodes)
kubectl get volumeattachment | grep <pv-name>

# Check node-level mount status (if you have node access)
# mount | grep <pv-name>
```

---

## 6. RBAC & SECURITY

```bash
# Check if a service account can perform an action
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa> -n <ns>

# List roles/clusterroles bound to a service account
kubectl get rolebinding,clusterrolebinding -A -o json | jq '.items[] | select(.subjects[]? | .name=="<sa>" and .namespace=="<ns>") | {name: .metadata.name, role: .roleRef.name}'

# Check pod's service account
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.serviceAccountName}'

# Check if PSP/PSA is blocking
kubectl get podsecuritypolicy 2>/dev/null  # PSP (deprecated)
kubectl get ns <ns> -o yaml | grep "pod-security"  # PSA labels

# Check SecurityContext issues
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.securityContext}' | jq .
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[0].securityContext}' | jq .
```

---

## 7. RESOURCE EXHAUSTION & QUOTAS

```bash
# Namespace resource quotas
kubectl describe resourcequota -n <ns>

# Namespace limit ranges
kubectl describe limitrange -n <ns>

# Cluster-wide resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -20
kubectl top pods -A --sort-by=cpu | head -20

# Check for pods without resource requests/limits (risky in shared clusters)
kubectl get pods -n <ns> -o json | jq '.items[] | select(.spec.containers[].resources.requests == null) | .metadata.name'

# HPA status (is it scaling?)
kubectl get hpa -n <ns>
kubectl describe hpa <hpa> -n <ns>
```

---

## 8. CONTROL PLANE

```bash
# Check control plane component health
kubectl get componentstatuses 2>/dev/null  # deprecated but sometimes still works
kubectl get pods -n kube-system

# API server health
kubectl get --raw /healthz
kubectl get --raw /livez
kubectl get --raw /readyz

# etcd health (if accessible)
kubectl get pods -n kube-system -l component=etcd
kubectl logs -n kube-system -l component=etcd --tail=20

# Controller manager
kubectl get pods -n kube-system -l component=kube-controller-manager
kubectl logs -n kube-system -l component=kube-controller-manager --tail=20

# Check API server audit events for denied requests
kubectl logs -n kube-system -l component=kube-apiserver --tail=30 | grep -i "forbidden\|denied"
```

---

## 9. WORKLOAD ROLLOUT ISSUES

### Deployment stuck

```bash
# Check rollout status
kubectl rollout status deployment/<deploy> -n <ns> --timeout=10s

# Check deployment conditions
kubectl describe deployment <deploy> -n <ns> | grep -A10 "Conditions:"

# Check ReplicaSet status
kubectl get rs -n <ns> -l app=<app-label>
kubectl describe rs <new-rs> -n <ns>

# Check if it's a quota issue preventing new pods
kubectl describe resourcequota -n <ns>

# Check deployment strategy (is maxUnavailable=0 with maxSurge=0?)
kubectl get deployment <deploy> -n <ns> -o jsonpath='{.spec.strategy}'

# Rollback if needed
kubectl rollout undo deployment/<deploy> -n <ns>
kubectl rollout history deployment/<deploy> -n <ns>
```

### StatefulSet issues

```bash
# StatefulSets roll one pod at a time — check which ordinal is stuck
kubectl get pods -n <ns> -l app=<app-label> --sort-by=.metadata.name

# Check PVC binding for each pod
kubectl get pvc -n <ns> -l app=<app-label>
```

### DaemonSet not scheduling on all nodes

```bash
# Compare desired vs current vs ready
kubectl get daemonset <ds> -n <ns>

# Check which nodes are missing
kubectl get pods -n <ns> -l <ds-label> -o wide
kubectl get nodes -o name | while read node; do
  echo -n "$node: "
  kubectl get pods -n <ns> -l <ds-label> --field-selector spec.nodeName=$(basename $node) -o name 2>/dev/null || echo "MISSING"
done

# Check for taints preventing scheduling
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl get daemonset <ds> -n <ns> -o jsonpath='{.spec.template.spec.tolerations}' | jq .
```

### Job/CronJob failures

```bash
# Check job status
kubectl get jobs -n <ns>
kubectl describe job <job> -n <ns>

# Check CronJob schedule and last run
kubectl get cronjob -n <ns>
kubectl describe cronjob <cj> -n <ns> | grep -A5 "Last Schedule"

# Check for stuck jobs (backoffLimit reached)
kubectl get jobs -n <ns> -o json | jq '.items[] | select(.status.failed != null) | {name: .metadata.name, failed: .status.failed}'
```

---

## 10. OBSERVABILITY & EVENTS

```bash
# All events in namespace (sorted by time)
kubectl get events -n <ns> --sort-by=.lastTimestamp

# Warning events only
kubectl get events -n <ns> --field-selector type=Warning --sort-by=.lastTimestamp

# Events for a specific resource
kubectl get events -n <ns> --field-selector involvedObject.name=<resource-name>

# Cluster-wide warning events
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | head -30

# Check metrics-server is running (needed for `kubectl top`)
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Pod resource usage
kubectl top pods -n <ns> --sort-by=memory
```

---

## Triage Decision Tree

When the user describes a symptom, follow this decision tree:

1. **Pod is Pending** → Section 1 (Scheduling) + Section 7 (Quotas)
2. **Pod is CrashLoopBackOff** → Section 2 (Pod Lifecycle)
3. **Pod is Running but not working** → Section 4 (Networking) + Section 6 (RBAC)
4. **Pod was Evicted** → Section 3 (Node Pressure)
5. **Can't pull image** → Section 2 (ImagePullBackOff)
6. **Can't access service** → Section 4 (Networking)
7. **PVC stuck** → Section 5 (Storage)
8. **Deployment won't update** → Section 9 (Rollout)
9. **Permission denied** → Section 6 (RBAC)
10. **Cluster unresponsive** → Section 8 (Control Plane)
11. **Unknown** → Section 10 (Events) first, then follow the trail

## Response Format

For every troubleshooting session:
1. **Identify the symptom** and map it to a failure domain
2. **Run diagnostic commands** (ask the user to run them or use kubectl directly if available)
3. **Interpret the output** — explain what each result means
4. **Provide the fix** — concrete kubectl commands or YAML patches
5. **Explain the root cause** — so the user learns, not just fixes
6. **Suggest prevention** — resource requests, PDBs, monitoring, alerts
