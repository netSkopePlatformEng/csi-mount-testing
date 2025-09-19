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

1. **Force delete the stuck pod:**
   ```bash
   kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0
   ```

2. **Wait for pod recreation:**
   ```bash
   kubectl get pods -n <namespace> -w
   ```

3. **If pod recreates with same issue, proceed to Step 4**

### Step 4: PVC Recreation (Data Loss Risk)

⚠️ **WARNING: This step will result in data loss. Ensure you have backups or can recreate data.**

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

4. **Verify PV cleanup:**
   ```bash
   kubectl get pv | grep <pv-name>
   ```

5. **Scale StatefulSet back up:**
   ```bash
   kubectl scale statefulset <statefulset-name> -n <namespace> --replicas=<original-replica-count>
   ```

### Step 5: Alternative - PVC Patch Method (Preserve Data)

If data preservation is critical, attempt this method first:

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

### Step 6: Verification

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
- **SRE Team**: [Contact information]
- **Application Team**: [Contact information]

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-09-19 | Claude Code | Initial SOP creation |

---

**Note**: This SOP should be tested in non-production environments before applying to production systems. Always ensure proper backups are available before performing destructive operations.