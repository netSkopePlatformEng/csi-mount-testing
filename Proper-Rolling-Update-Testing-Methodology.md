# Proper Rolling Update Testing Methodology for CSI Volume Issues

## Issue with Previous Testing Approach

The previous testing approach had a fundamental flaw:
- **Method Used**: Direct pod deletion (`kubectl delete pod`)
- **Problem**: This bypasses Kubernetes' rolling update mechanism and doesn't represent real-world deployment scenarios
- **Impact**: Results don't reflect how CSI volumes behave during actual application updates

## Correct Testing Methodology

### 1. Rolling Update Configuration Requirements

For proper testing of CSI volume attachment issues during rolling updates, the StatefulSet must be configured with:

```yaml
spec:
  podManagementPolicy: OrderedReady  # Ensures sequential pod updates
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1  # Only one pod updates at a time (StatefulSet doesn't support this field)
      # For StatefulSets, use partition to control update order instead
```

**Note**: StatefulSets don't support `maxUnavailable` in `rollingUpdate`. Instead, use `partition` to control which pods get updated.

### 2. Correct StatefulSet Configuration

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: etcd-cluster
  namespace: csi-mount-test
spec:
  serviceName: etcd-headless
  replicas: 3
  podManagementPolicy: OrderedReady  # Critical: ensures one pod at a time
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0  # Start at 0 to update all pods, or set higher to limit updates
  # ... rest of spec
```

### 3. Rolling Update Testing Process

#### Step 1: Prepare the Environment
1. Ensure StatefulSet is configured with `podManagementPolicy: OrderedReady`
2. Verify all pods are running and healthy
3. Confirm load testing is active (if testing under stress)

#### Step 2: Trigger Rolling Update
**Method A: Environment Variable Change**
```bash
# Update a non-functional environment variable to trigger pod restart
kubectl patch statefulset etcd-cluster -n csi-mount-test -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"etcd","env":[{"name":"ROLLING_UPDATE_TRIGGER","value":"'$(date +%s)'"}]}]}}}}'
```

**Method B: Image Tag Update**
```bash
# Update image tag (if using versioned images)
kubectl patch statefulset etcd-cluster -n csi-mount-test -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"etcd","image":"artifactory.netskope.io/pe-docker/etcd-csi-test:v0.0.2"}]}]}}}}'
```

**Method C: Resource Limit Adjustment**
```bash
# Adjust resource limits slightly
kubectl patch statefulset etcd-cluster -n csi-mount-test -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"etcd","resources":{"limits":{"memory":"513Mi"}}}]}}}}'
```

#### Step 3: Monitor Rolling Update Progression

1. **Watch Pod Status**:
```bash
kubectl get pods -n csi-mount-test -w
```

2. **Monitor StatefulSet Rollout**:
```bash
kubectl rollout status statefulset/etcd-cluster -n csi-mount-test
```

3. **Check Events for CSI Issues**:
```bash
kubectl get events -n csi-mount-test --sort-by='.lastTimestamp'
```

#### Step 4: Control Update Progression (Optional)

To test one pod at a time, use the `partition` field:

```bash
# Update only pods with ordinal >= partition value
# Start with partition=2 (updates only etcd-cluster-2)
kubectl patch statefulset etcd-cluster -n csi-mount-test -p \
  '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'

# After etcd-cluster-2 is updated, move to etcd-cluster-1
kubectl patch statefulset etcd-cluster -n csi-mount-test -p \
  '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":1}}}}'

# Finally update etcd-cluster-0
kubectl patch statefulset etcd-cluster -n csi-mount-test -p \
  '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

### 4. What to Monitor During Testing

#### CSI Volume Attachment Issues
Look for these events during rolling updates:
- `FailedAttachVolume`: Multi-Attach errors
- `VolumeAttachmentTimeout`: Volume attachment timeouts
- `FailedMount`: Mount failures due to attachment conflicts

#### Pod Lifecycle Events
- `FailedPreStopHook`: PreStop hook failures (expected with current config)
- `Killing`: Pod termination events
- `SuccessfulCreate`: New pod creation
- `Scheduled`: Pod scheduling to nodes

#### StatefulSet Update Progress
- Sequential pod updates (with OrderedReady)
- Update strategy effectiveness
- Rollback capabilities if issues occur

### 5. Expected Behavior vs Issues

#### Expected Behavior (Healthy CSI)
1. Pod receives termination signal
2. PreStop hook executes (may timeout, which is acceptable)
3. Pod terminates after grace period
4. Volume detaches from old node
5. New pod gets scheduled (possibly on different node)
6. Volume attaches to new node
7. Pod starts successfully

#### CSI Volume Issues to Watch For
1. **Multi-Attach Errors**: Volume stuck attached to old node when new pod tries to schedule
2. **Extended Termination**: Pods stuck in Terminating state beyond grace period
3. **Mount Failures**: New pods can't mount volumes due to attachment conflicts
4. **Data Inconsistency**: Volume corruption due to improper detachment

### 6. Recovery and Rollback

If CSI issues occur during rolling update:

```bash
# Pause the rollout
kubectl patch statefulset etcd-cluster -n csi-mount-test -p \
  '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":3}}}}'

# Rollback to previous version
kubectl rollout undo statefulset/etcd-cluster -n csi-mount-test

# Monitor rollback progress
kubectl rollout status statefulset/etcd-cluster -n csi-mount-test
```

### 7. Key Differences from Pod Deletion Testing

| Aspect | Pod Deletion (Incorrect) | Rolling Update (Correct) |
|--------|-------------------------|-------------------------|
| **Trigger** | Manual pod deletion | StatefulSet spec change |
| **Control** | No update strategy control | Respects updateStrategy settings |
| **Realism** | Not representative of deployments | Mirrors real deployment scenarios |
| **Observability** | Limited to pod lifecycle | Full rollout monitoring available |
| **Rollback** | Not available | Built-in rollback capabilities |
| **Ordering** | Random pod replacement | Controlled by podManagementPolicy |

## Current Environment Limitations

### Issue: Cannot Change podManagementPolicy
Our current StatefulSet has `podManagementPolicy: Parallel`, which means all pods may update simultaneously. This cannot be changed on an existing StatefulSet.

### Workaround Options
1. **Use partition field**: Control which pods update by setting partition values
2. **Recreate StatefulSet**: Delete and recreate with OrderedReady (requires downtime)
3. **Accept parallel updates**: Test with current configuration but note the limitation

### Recommended Approach for Current Test
Given the limitations, we'll:
1. Use partition-based control to update one pod at a time
2. Document that this is a workaround for the parallel pod management policy
3. Note in results that OrderedReady would provide better control in production

## Implementation Plan

1. **Update StatefulSet with partition control**
2. **Trigger rolling update via environment variable change**
3. **Monitor CSI volume behavior during controlled update**
4. **Document observed behavior and issues**
5. **Compare results with previous pod deletion testing**

This methodology provides a more realistic and controlled way to test CSI volume attachment issues during actual application deployments.