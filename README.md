# etcd CSI Mount Testing

This directory contains Kubernetes manifests for testing CSI mount issues with a real-world application (etcd).

## Purpose

Test CSI Multi-Attach errors and volume cleanup timing using etcd StatefulSet instead of synthetic workloads.

## Components

### 1. etcd StatefulSet (`etcd-statefulset.yaml`)
- **3-node etcd cluster** with persistent volumes
- **Data generation sidecar** that continuously writes data to stress CSI volumes
- **PreStop hooks** for graceful volume cleanup
- **Parallel pod management** to trigger Multi-Attach scenarios
- **Extended termination grace period** (900 seconds) for CSI cleanup

### 2. Test Client (`etcd-test-client.yaml`)
- **Monitoring pod** that provides cluster health checks
- **API access** for manual testing and verification
- **Built-in commands** for triggering rolling updates

## Data Generation Strategy

The etcd StatefulSet includes a data generator sidecar that:

1. **Bulk Data**: Writes 10x 1KB entries per cycle
2. **Frequent Updates**: 50 small timestamp entries per cycle  
3. **Large Entries**: 3x 10KB entries per cycle
4. **Continuous Operation**: 1-second intervals with status reports every 100 cycles

This generates realistic I/O patterns that will stress the CSI volume during termination.

## Deployment

```bash
# Deploy to test cluster
kubectl apply -f etcd-statefulset.yaml
kubectl apply -f etcd-test-client.yaml

# Monitor deployment
kubectl get pods -n csi-mount-test -w

# Check etcd cluster health
kubectl logs -n csi-mount-test deployment/etcd-test-client

# Trigger rolling update to test Multi-Attach
kubectl rollout restart statefulset etcd-cluster -n csi-mount-test
```

## Testing Multi-Attach Issues

1. **Wait for cluster to be healthy** (all 3 etcd pods running)
2. **Verify data generation** is creating volume activity
3. **Trigger rolling update**: `kubectl rollout restart statefulset etcd-cluster -n csi-mount-test`
4. **Monitor pod termination timing** and look for Multi-Attach errors
5. **Compare cleanup duration** with previous synthetic tests

## Expected Behavior

- **Without preStop hooks**: Multi-Attach errors during rolling updates
- **With preStop hooks**: Extended termination time but no Multi-Attach errors
- **Data persistence**: etcd data should survive rolling updates

## Volume Usage

Each etcd pod gets an 8GB PVC that will gradually fill with generated data, creating realistic production-like conditions for testing CSI cleanup behavior.

## Monitoring Commands

```bash
# Watch pod status during rolling update
kubectl get pods -n csi-mount-test -w

# Check volume usage
kubectl exec -n csi-mount-test etcd-cluster-0 -- df -h /var/lib/etcd

# View etcd data generation logs
kubectl logs -n csi-mount-test etcd-cluster-0 -c data-generator

# Check for Multi-Attach events
kubectl get events -n csi-mount-test --field-selector reason=FailedAttachVolume
```

---

*Created for CSI Multi-Attach issue testing - OPS-234241*