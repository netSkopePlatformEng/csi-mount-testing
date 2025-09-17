# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository contains Kubernetes manifests for testing CSI (Container Storage Interface) mount issues, specifically CSI Multi-Attach errors during StatefulSet rolling updates. The project tests real-world scenarios using etcd StatefulSets with data generation workloads to reproduce and validate fixes for CSI volume cleanup timing issues.

## Key Components and Architecture

### Container Images
- **Custom etcd image**: Built from `Dockerfile` using Ubuntu 20.04 FIPS base with etcd v3.5.9
- **Build script**: `build.sh` builds and tags images for Netskope artifactory (`artifactory.netskope.io/pe-docker/etcd-csi-test`)
- **Public variant**: `Dockerfile.public` for external testing environments

### Core Test Manifests

#### StatefulSet Variants
- **`etcd-statefulset.yaml`**: Original test configuration with parallel pod management and aggressive preStop hooks
- **`fixed-etcd-statefulset.yaml`**: Updated configuration with ordered ready, improved security context, and refined resource limits
- **`etcd-statefulset-local.yaml`**: Local cluster variant with different networking configuration

#### Key Configuration Differences
- **Pod Management Policy**: Original uses `Parallel` (triggers simultaneous termination), fixed uses `OrderedReady`
- **Termination Grace Period**: Original 900s (15 min), fixed 300s (5 min) for faster testing
- **Security Context**: Fixed version adds proper user/group assignments and privilege restrictions
- **PreStop Hook Strategy**: Both include comprehensive volume cleanup with file descriptor closure and CSI wait times

#### Load Testing Components
- **`etcd-load-clients.yaml`**: 5 aggressive client pods that generate large data volumes (1MB, 5MB entries) to stress CSI volumes during testing
- **`etcd-test-client.yaml`**: Simple monitoring pod for cluster health checks and manual testing

### Data Generation Strategy

The etcd StatefulSet includes a sidecar container (`data-generator`) that creates realistic I/O patterns:
- **Bulk Data**: 10x 1KB entries per cycle
- **Frequent Updates**: 50 small timestamp entries per cycle
- **Large Entries**: 3x 10KB entries per cycle
- **Continuous Operation**: 1-second intervals with status reports every 100 cycles

This generates persistent volume stress during pod termination to reproduce CSI timing issues.

## Common Development Tasks

### Building Container Images
```bash
# Build with default tag (v0.0.1)
./build.sh

# Build with specific tag
TAG=v0.0.2 ./build.sh

# Push to artifactory (requires authentication)
docker push artifactory.netskope.io/pe-docker/etcd-csi-test:latest
```

### Deploying Test Environment
```bash
# Deploy etcd cluster for CSI testing
kubectl apply -f etcd-statefulset.yaml  # or fixed-etcd-statefulset.yaml

# Deploy test client for monitoring
kubectl apply -f etcd-test-client.yaml

# Deploy load testing clients (optional, for stress testing)
kubectl apply -f etcd-load-clients.yaml

# Monitor deployment
kubectl get pods -n csi-mount-test -w
```

### Triggering CSI Multi-Attach Tests

**IMPORTANT**: Always trigger updates using template annotations to ensure controlled testing:

```bash
# Method 1: Update annotation to trigger rolling update (RECOMMENDED)
kubectl patch statefulset etcd-cluster -n csi-mount-test -p '{"spec":{"template":{"metadata":{"annotations":{"rolling-restart-trigger":"test-'$(date +%s)'"}}}}}'

# Method 2: Alternative annotation update with descriptive trigger
kubectl patch statefulset etcd-cluster -n csi-mount-test -p '{"spec":{"template":{"metadata":{"annotations":{"rolling-restart-trigger":"csi-test-run-1"}}}}}'

# Monitor for CSI volume issues (Multi-Attach and Volume Not Found errors)
kubectl get events -n csi-mount-test --field-selector reason=FailedAttachVolume
kubectl get events -n csi-mount-test --field-selector reason=FailedMount

# Check pod termination timing and rollout status
kubectl get pods -n csi-mount-test -w
kubectl rollout status statefulset etcd-cluster -n csi-mount-test
```

**Why Use Annotations Instead of `kubectl rollout restart`:**
- Provides controlled, repeatable test triggers
- Allows tracking of specific test runs via annotation values
- Enables comparison between test iterations
- Maintains test traceability in cluster events and logs

### Monitoring and Debugging
```bash
# Check etcd cluster health
kubectl logs -n csi-mount-test deployment/etcd-test-client

# View data generation activity
kubectl logs -n csi-mount-test etcd-cluster-0 -c data-generator

# Check volume usage and stress
kubectl exec -n csi-mount-test etcd-cluster-0 -- df -h /var/lib/etcd

# Monitor preStop hook execution
kubectl logs -n csi-mount-test etcd-cluster-0 -c etcd --previous
```

## Testing Methodology

### CSI Volume Cleanup Testing
The repository tests two main scenarios:
1. **Without preStop hooks**: Expect CSI volume errors during rolling updates
2. **With preStop hooks**: Extended termination time but no CSI volume errors

**Common CSI Error Patterns:**
- **Multi-Attach Error**: Volume already attached to another pod
- **Volume Not Found Error**: `rpc error: code = NotFound desc = [ControllerPublishVolume] Volume ... not found`
- **Failed Mount**: `Unable to attach or mount volumes: unmounted volumes=[...]: timed out waiting for the condition`

These errors often occur together during rolling updates when CSI volume cleanup timing conflicts with new pod scheduling.

### Volume Stress Testing
- etcd data generation creates realistic production-like I/O load
- Each pod gets an 8GB PVC that gradually fills with generated data
- Load clients (if deployed) create additional stress with large data entries

### Expected Behavior Analysis
- **Multi-Attach Prevention**: preStop hooks should prevent volume attachment conflicts
- **Data Persistence**: etcd data should survive rolling updates without corruption
- **Performance Impact**: Document termination timing differences with/without hooks

## Project Context

This repository supports testing for **SYS-24741** (CSI Multi-Attach issue resolution). The testing validates preStop hook solutions that showed 90% effectiveness in preventing CSI conflicts, while identifying CSI driver performance concerns (15-hour cleanup delays in some scenarios).

Key findings from testing are documented in:
- `CSI-Volume-Testing-Report.md`: Comprehensive test results and analysis
- `SESSION-HISTORY.md`: Detailed testing session logs and timeline
- `Proper-Rolling-Update-Testing-Methodology.md`: Testing procedures and methodologies