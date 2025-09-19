# SOP: Manual Resolution of CSI Volume Attachment Issues

## Overview
This Standard Operating Procedure (SOP) provides step-by-step instructions for manually resolving CSI (Container Storage Interface) volume attachment issues, specifically the "Volume Not Found" and "Multi-Attach" errors commonly encountered during StatefulSet rolling updates.

## Issue Identification

### Symptoms
- Pods stuck in `Init:0/2` or `Pending` state for extended periods (>30 minutes)
- Event messages containing:
  - `FailedAttachVolume: rpc error: code = NotFound desc = [ControllerPublishVolume] Volume <volume-id> not found`
  - `Multi-Attach error for volume <pvc-name>`
  - `Unable to attach or mount volumes: unmounted volumes=[pv]`

### Example Error Pattern
```
FailedAttachVolume: rpc error: code = NotFound desc = [ControllerPublishVolume] Volume c747bd14-7d23-4616-b796-0958a0e16dad not found
```

## Prerequisites
- `kubectl` access to the affected cluster
- Administrative privileges for the namespace
- Understanding of the application's data persistence requirements

## Resolution Procedure

### Step 1: Assess the Situation

1. **Identify affected pods:**
   ```bash
   kubectl get pods -n <namespace> | grep -E "(Init:|Pending|ContainerCreating)"
   ```

2. **Check events for volume errors:**
   ```bash
   kubectl get events -n <namespace> --field-selector reason=FailedAttachVolume
   kubectl get events -n <namespace> --field-selector reason=FailedMount
   ```

3. **Examine PVC status:**
   ```bash
   kubectl get pvc -n <namespace>
   kubectl describe pvc <pvc-name> -n <namespace>
   ```

### Step 2: Determine Volume Mapping

1. **Get PVC details to find the bound PV:**
   ```bash
   kubectl get pvc <pvc-name> -n <namespace> -o yaml | grep volumeName
   ```

2. **Check the PersistentVolume:**
   ```bash
   kubectl describe pv <pv-name>
   ```

3. **Verify CSI volume ID mismatch:**
   - Compare the CSI volume ID in the error message with the PV's `spec.csi.volumeHandle`
   - If they don't match, this indicates a mapping corruption

### Step 3: Safe Pod Termination

1. **Delete the stuck pod (normal termination first):**
   ```bash
   kubectl delete pod <pod-name> -n <namespace>
   ```

2. **Wait for pod recreation:**
   ```bash
   kubectl get pods -n <namespace> -w
   ```

3. **If pod recreates with same issue, proceed to Step 4**

### Step 4: PVC Recreation (Primary Resolution Method)

⚠️ **WARNING: This step will result in data loss. Ensure you have backups or can recreate data.**

1. **Delete the problematic PVC while pod is running (StatefulSet will recreate it):**
   ```bash
   kubectl delete pvc <pvc-name> -n <namespace>
   ```

2. **If PVC gets stuck in Terminating state, force delete the pod:**
   ```bash
   kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0
   ```

3. **Monitor for new PVC creation and pod recovery:**
   ```bash
   kubectl get pods,pvc -n <namespace> -w
   ```

4. **Verify new PVC has different volume ID:**
   ```bash
   kubectl get pvc <pvc-name> -n <namespace> -o yaml | grep volumeName
   ```

### Step 5: Alternative - Scale Down Method (If Direct PVC Deletion Fails)

If the PVC deletion in Step 4 doesn't resolve the issue:

1. **Scale down the StatefulSet:**
   ```bash
   kubectl scale statefulset <statefulset-name> -n <namespace> --replicas=0
   ```

2. **Wait for all pods to terminate:**
   ```bash
   kubectl get pods -n <namespace> -l app=<app-label>
   ```

3. **Delete the problematic PVC:**
   ```bash
   kubectl delete pvc <pvc-name> -n <namespace>
   ```

4. **Scale StatefulSet back up:**
   ```bash
   kubectl scale statefulset <statefulset-name> -n <namespace> --replicas=<original-replica-count>
   ```

### Step 6: Data Preservation Method (Advanced - Not Tested)

⚠️ **EXPERIMENTAL**: This method is theoretical and has not been validated in testing:

1. **Get current PV name:**
   ```bash
   PV_NAME=$(kubectl get pvc <pvc-name> -n <namespace> -o jsonpath='{.spec.volumeName}')
   ```

2. **Patch PV to remove claim reference:**
   ```bash
   kubectl patch pv $PV_NAME -p '{"spec":{"claimRef":null}}'
   ```

3. **Delete and recreate PVC with same name:**
   ```bash
   kubectl delete pvc <pvc-name> -n <namespace>
   # Wait for deletion
   kubectl apply -f <pvc-manifest-file>
   ```

4. **Manually bind PVC to PV:**
   ```bash
   kubectl patch pvc <pvc-name> -n <namespace> -p '{"spec":{"volumeName":"'$PV_NAME'"}}'
   ```

### Step 7: Verification

1. **Monitor pod startup:**
   ```bash
   kubectl get pods -n <namespace> -w
   ```

2. **Check for successful volume mounting:**
   ```bash
   kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Volumes:"
   ```

3. **Verify application functionality:**
   ```bash
   kubectl logs <pod-name> -n <namespace>
   kubectl exec <pod-name> -n <namespace> -- df -h
   ```

## Prevention Strategies

### 1. Implement PreStop Hooks
Add preStop hooks to StatefulSet containers to ensure graceful volume cleanup:

```yaml
lifecycle:
  preStop:
    exec:
      command:
      - /bin/sh
      - -c
      - |
        # Application-specific graceful shutdown
        # Wait for CSI volume cleanup
        sleep 30
```

### 2. Use OrderedReady Pod Management
Configure StatefulSets with sequential pod management:

```yaml
spec:
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
```

### 3. Increase Termination Grace Period
Allow more time for volume cleanup:

```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 300
```

### 4. Prevent Multi-Attach Errors with Node Scheduling Controls
Multi-Attach errors occur when pods with ReadWriteOnce (RWO) volumes attempt to schedule on multiple nodes simultaneously. Use these strategies to prevent scheduling conflicts:

#### Pod Anti-Affinity (Recommended)
Configure StatefulSets to prevent multiple pods from scheduling on the same node:

```yaml
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - <your-app-name>
            topologyKey: kubernetes.io/hostname
```

#### Node Selector Constraints
For critical workloads, use node selectors to control placement:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        node-role: dedicated-storage
```

#### Topology Spread Constraints
Distribute pods across failure domains while avoiding conflicts:

```yaml
spec:
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: <your-app-name>
```

#### Benefits of Node Scheduling Controls
- **Prevents Multi-Attach**: Ensures RWO volumes only attach to one node at a time
- **Improves Reliability**: Reduces CSI volume attachment conflicts during rolling updates
- **Enhances Availability**: Distributes workload across cluster nodes for better fault tolerance
- **Reduces Manual Intervention**: Fewer stuck pods requiring manual PVC cleanup

## Post-Resolution Actions

1. **Document the incident:**
   - Record which volumes were affected
   - Note any data loss or service interruption
   - Update monitoring alerts if needed

2. **Review application logs:**
   - Check for any data corruption
   - Verify application-specific recovery procedures

3. **Consider implementing prevention strategies** if not already in place

## Emergency Contacts

- **Platform Engineering**: [Contact information]
- **OPS Team**: [Contact information]
- **Application Team**: [Contact information]

## Real-World Testing Example (2025-09-19)

**Environment**: stork-qa01-dp-npe-iad0-nc1
**Namespace**: drm
**Issue**: Pod stuck in `Init:0/2` for 2d10h

### Actual Commands Used (Validated)
```bash
# 1. Identified the issue
kubectl get pods -n drm
# NAME                 READY   STATUS     RESTARTS       AGE
# drm-data-service-1   0/2     Init:0/2   0              2d10h

# 2. Examined the problem
kubectl describe pod drm-data-service-1 -n drm
# Events showed: FailedAttachVolume: rpc error: code = NotFound desc = [ControllerPublishVolume] Volume 9d3fa055-1b22-448a-a505-900827069e3f not found

# 3. Tried simple pod deletion first (didn't work)
kubectl delete pod drm-data-service-1 -n drm
# Pod recreated with same issue

# 4. PVC deletion (successful resolution)
kubectl delete pvc pv-drm-data-service-1 -n drm
# PVC stuck in Terminating state

# 5. Force delete pod to break dependency
kubectl delete pod drm-data-service-1 -n drm --force --grace-period=0

# 6. Verified resolution
kubectl get pods,pvc -n drm
# Pod: 2/2 Running with new PVC volume ID
```

**Result**: Issue resolved in ~3 minutes after 2d10h of being stuck.
**Key Finding**: PVC deletion is the primary effective resolution method.

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-09-19 | Claude Code | Initial SOP creation |
| 1.1 | 2025-09-19 | Claude Code | Updated based on real-world testing validation |

---

**Note**: This SOP should be tested in non-production environments before applying to production systems. Always ensure proper backups are available before performing destructive operations.