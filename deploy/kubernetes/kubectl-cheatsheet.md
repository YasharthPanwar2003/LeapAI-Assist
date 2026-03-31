# kubectl Cheatsheet

> Quick reference for essential kubectl commands on openSUSE Leap 16.

---

## Setup

```bash
sudo zypper install kubernetes-client    # Install kubectl
kubectl version --client                  # Verify version
kubectl cluster-info                      # Test cluster connectivity
kubectl get nodes                         # Verify nodes
```

---

## Cluster

| Command | Description |
|---------|-------------|
| `kubectl cluster-info` | Display cluster endpoints |
| `kubectl version` | Show client and server versions |
| `kubectl api-resources` | List all resource types |
| `kubectl api-versions` | List API versions |
| `kubectl get componentstatuses` | Component health (deprecated) |
| `kubectl get --raw='/readyz?verbose'` | Detailed health check |

---

## Nodes

| Command | Description |
|---------|-------------|
| `kubectl get nodes` | List all nodes |
| `kubectl describe node <name>` | Node details |
| `kubectl cordon <name>` | Mark unschedulable |
| `kubectl uncordon <name>` | Mark schedulable |
| `kubectl drain <name>` | Evict pods + cordon |
| `kubectl taint node <name> key=val:NoSchedule` | Add taint |
| `kubectl top nodes` | Node resource usage |

---

## Namespaces

| Command | Description |
|---------|-------------|
| `kubectl create ns <name>` | Create namespace |
| `kubectl get ns` | List namespaces |
| `kubectl describe ns <name>` | Namespace details |
| `kubectl delete ns <name>` | Delete namespace |
| `kubectl config set-context --current --namespace=<ns>` | Set default ns |
| `kubectl get all -n <ns>` | List all resources in ns |
| `kubectl get all --all-namespaces` | List all resources cluster-wide |

---

## Pods

| Command | Description |
|---------|-------------|
| `kubectl get pods` | List pods (current ns) |
| `kubectl get pods -o wide` | Show node and IP |
| `kubectl get pods -w` | Watch pods |
| `kubectl get pods -A` | All namespaces |
| `kubectl get pods -l app=<label>` | Filter by label |
| `kubectl get pods --sort-by='.status.startTime'` | Sort by start time |
| `kubectl get pods --field-selector=status.phase=Running` | Filter by phase |
| `kubectl describe pod <name>` | Pod details + events |
| `kubectl logs <name>` | View logs |
| `kubectl logs <name> -c <container>` | Specific container logs |
| `kubectl logs <name> --tail=100` | Last 100 lines |
| `kubectl logs <name> --since=1h` | Logs since 1 hour ago |
| `kubectl logs <name> -f` | Follow logs |
| `kubectl logs <name> --previous` | Previous container logs |
| `kubectl logs <name> | jq .` | Pipe logs to jq |
| `kubectl exec -it <name> -- /bin/sh` | Shell into pod |
| `kubectl exec <name> -- <cmd>` | Run command |
| `kubectl port-forward <name> 8080:80` | Port forward |
| `kubectl cp <name>:/path ./local` | Copy from pod |
| `kubectl cp ./local <name>:/path` | Copy to pod |
| `kubectl delete pod <name>` | Delete pod |
| `kubectl delete pod <name> --force --grace-period=0` | Force delete |
| `kubectl top pods` | Pod resource usage |
| `kubectl top pods --containers` | Per-container usage |

---

## Deployments

| Command | Description |
|---------|-------------|
| `kubectl create deploy <name> --image=<img> --replicas=3` | Create deployment |
| `kubectl get deployments` | List deployments |
| `kubectl describe deploy <name>` | Deployment details |
| `kubectl scale deploy <name> --replicas=5` | Scale replicas |
| `kubectl autoscale deploy <name> --min=2 --max=10 --cpu-percent=80` | Auto-scale |
| `kubectl rollout status deploy/<name>` | Rollout status |
| `kubectl rollout history deploy/<name>` | Rollout history |
| `kubectl rollout history deploy/<name> --revision=2` | Specific revision |
| `kubectl rollout undo deploy/<name>` | Rollback |
| `kubectl rollout undo deploy/<name> --to-revision=2` | Rollback to revision |
| `kubectl rollout restart deploy/<name>` | Restart all pods |
| `kubectl rollout pause deploy/<name>` | Pause rollout |
| `kubectl rollout resume deploy/<name>` | Resume rollout |
| `kubectl set image deploy/<name> <c>=<img>:<tag>` | Update image |
| `kubectl set resources deploy/<name> -c <c> --limits=cpu=200m,memory=512Mi` | Set resources |
| `kubectl delete deploy <name>` | Delete deployment |

---

## Services

| Command | Description |
|---------|-------------|
| `kubectl expose deploy <name> --port=80 --target-port=8080` | Create ClusterIP |
| `kubectl expose deploy <name> --port=80 --type=NodePort` | Create NodePort |
| `kubectl expose deploy <name> --port=80 --type=LoadBalancer` | Create LB |
| `kubectl get svc` | List services |
| `kubectl describe svc <name>` | Service details |
| `kubectl get endpoints <name>` | Service endpoints |
| `kubectl delete svc <name>` | Delete service |

---

## ConfigMaps & Secrets

| Command | Description |
|---------|-------------|
| `kubectl create cm <name> --from-literal=key=val` | Create from literal |
| `kubectl create cm <name> --from-file=file.yaml` | Create from file |
| `kubectl create cm <name> --from-env-file=.env` | Create from env file |
| `kubectl get cm` | List ConfigMaps |
| `kubectl describe cm <name>` | ConfigMap details |
| `kubectl get cm <name> -o yaml` | Get ConfigMap YAML |
| `kubectl create secret generic <name> --from-literal=key=val` | Create generic secret |
| `kubectl create secret generic <name> --from-file=key=file` | Create from file |
| `kubectl create secret docker-registry <name> --docker-server=<s> --docker-username=<u> --docker-password=<p>` | Registry secret |
| `kubectl create secret tls <name> --cert=crt --key=key` | TLS secret |
| `kubectl get secrets` | List secrets |
| `kubectl describe secret <name>` | Secret details |
| `kubectl get secret <name> -o jsonpath='{.data.KEY}' \| base64 -d` | Decode secret value |

---

## Ingress

| Command | Description |
|---------|-------------|
| `kubectl get ingress` | List ingresses |
| `kubectl describe ing <name>` | Ingress details |
| `kubectl delete ing <name>` | Delete ingress |

---

## Persistent Volumes

| Command | Description |
|---------|-------------|
| `kubectl get pv` | List PVs |
| `kubectl get pvc` | List PVCs |
| `kubectl describe pvc <name>` | PVC details |
| `kubectl describe pv <name>` | PV details |
| `kubectl delete pvc <name>` | Delete PVC |
| `kubectl patch pv <name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'` | Change reclaim policy |

---

## RBAC

| Command | Description |
|---------|-------------|
| `kubectl get sa` | List ServiceAccounts |
| `kubectl get roles` | List Roles |
| `kubectl get rolebindings` | List RoleBindings |
| `kubectl get clusterroles` | List ClusterRoles |
| `kubectl get clusterrolebindings` | List ClusterRoleBindings |
| `kubectl describe role <name> -n <ns>` | Role details |
| `kubectl describe clusterrole <name>` | ClusterRole details |
| `kubectl auth can-i <verb> <resource> --as=sa:<ns>:<name>` | Check permissions |
| `kubectl auth reconcile -f rbac.yaml` | Reconcile RBAC |

---

## Apply & Manage

| Command | Description |
|---------|-------------|
| `kubectl apply -f file.yaml` | Apply manifest |
| `kubectl apply -f directory/` | Apply all in directory |
| `kubectl apply -f https://url/manifest.yaml` | Apply from URL |
| `kubectl apply -f file.yaml --dry-run=client` | Validate (no apply) |
| `kubectl apply -f file.yaml --dry-run=client -o yaml` | Print rendered YAML |
| `kubectl delete -f file.yaml` | Delete from manifest |
| `kubectl replace -f file.yaml` | Replace resource |
| `kubectl patch deploy <name> -p '{"spec":{"replicas":3}}'` | Patch resource |
| `kubectl diff -f file.yaml` | Show differences |
| `kubectl edit deploy <name>` | Edit in editor |

---

## Labels & Annotations

| Command | Description |
|---------|-------------|
| `kubectl label pod <name> env=prod` | Add label |
| `kubectl label pod <name> env-` | Remove label |
| `kubectl label pod <name> env=staging --overwrite` | Overwrite label |
| `kubectl annotate pod <name> desc="text"` | Add annotation |
| `kubectl annotate pod <name> desc-` | Remove annotation |
| `kubectl get pods -l app=ai` | Filter by label |
| `kubectl get pods -l 'env in (prod,staging)'` | Label set membership |
| `kubectl get pods -l 'tier notin (frontend)'` | Label exclusion |
| `kubectl get all -l app=ai` | All resources by label |

---

## Output Formatting

| Flag | Description |
|------|-------------|
| `-o yaml` | YAML output |
| `-o json` | JSON output |
| `-o wide` | Extended (node, IP) |
| `-o name` | Resource names only |
| `-o jsonpath='{.items[*].metadata.name}'` | JSONPath query |
| `-o custom-columns=NAME:.metadata.name,STATUS:.status.phase` | Custom columns |

---

## Debugging

| Command | Description |
|---------|-------------|
| `kubectl get events --sort-by='.lastTimestamp'` | Recent events |
| `kubectl get events -w` | Watch events |
| `kubectl get pod <name> -o yaml` | Full pod spec |
| `kubectl get pod <name> -o jsonpath='{.status.phase}'` | Pod phase |
| `kubectl get pod <name> -o jsonpath='{.status.containerStatuses[*].ready}'` | Ready status |
| `kubectl describe pod <name>` | Events (check bottom) |
| `kubectl run debug --image=busybox -it --rm --restart=Never` | Debug pod |
| `kubectl debug <pod> -it --image=nicolaka/netshoot` | Debug running pod |

---

## Complete Deployment Workflow

```bash
# 1. Create namespace
kubectl apply -f k8s-namespace.yaml

# 2. Create config and secrets
kubectl apply -f k8s-configmap.yaml
kubectl create secret generic ai-assistant-secret \
  --from-literal=DATABASE_PASSWORD=my-password \
  --from-literal=API_KEY=my-api-key \
  -n ai-assistant

# 3. Create storage
kubectl apply -f k8s-pvc.yaml

# 4. Create RBAC
kubectl apply -f k8s-rbac.yaml

# 5. Deploy application
kubectl apply -f k8s-deployment.yaml

# 6. Create services
kubectl apply -f k8s-service.yaml

# 7. Create ingress
kubectl apply -f k8s-ingress.yaml

# 8. Verify
kubectl get all -n ai-assistant
kubectl logs -f deploy/ai-assistant -n ai-assistant

# 9. Test
kubectl port-forward svc/ai-assistant 8080:80 -n ai-assistant
curl http://localhost:8080/health
curl http://localhost:8080/ready
```

---

## Common Patterns

### Scale up for traffic
```bash
kubectl scale deploy ai-assistant --replicas=10 -n ai-assistant
```

### Quick rollback
```bash
kubectl rollout undo deploy/ai-assistant -n ai-assistant
```

### Restart all pods
```bash
kubectl rollout restart deploy/ai-assistant -n ai-assistant
```

### Copy logs to file
```bash
kubectl logs deploy/ai-assistant -n ai-assistant --since=1h > app-logs.txt
```

### Export current state
```bash
kubectl get deploy ai-assistant -n ai-assistant -o yaml > deployment-backup.yaml
```

### Watch all resources
```bash
kubectl get all,cm,secret,pvc,ingress -n ai-assistant -w
```

### Delete everything in namespace
```bash
kubectl delete all --all -n ai-assistant
```

---

*For SUSE-specific Kubernetes options, see the main README.md.*
