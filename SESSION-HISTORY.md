# CSI Mount Testing Session History - 2025-09-12

## Overview
This document captures the complete testing session for CSI Multi-Attach issues and preStop hooks solution development.

## Background Context
- **Primary Issue**: CSI Multi-Attach errors during StatefulSet rolling updates
- **Root Cause**: Timing mismatch between pod termination (45s) and CSI volume cleanup (10-15 minutes)
- **Previous Work**: Developed preStop hooks solution that showed 90% effectiveness
- **Critical Finding**: Previous test showed 15-hour cleanup delay, raising production concerns

## Current Test Status

### Test Environment
- **Cluster**: stork-qa01-mp-npe-iad0-nc1
- **Namespace**: csi-mount-test
- **KubeConfig**: /Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml

### Active Test #1: csi-test-app (Synthetic Workload)
**Current Status** (as of 15:00 PDT):
- `csi-test-app-0`: Running (1/1) on knode19 
- `csi-test-app-1`: Terminating for ~3 hours (since 14:54 PDT)

**Test Configuration**:
```yaml
terminationGracePeriodSeconds: 900  # 15 minutes
podManagementPolicy: Parallel
```

**PreStop Hook**: Implemented with file descriptor cleanup and 45-second CSI wait

**Purpose**: Testing if 15-hour cleanup delay is consistent or anomaly

### Previous Test Results
- **Test #1**: 15-hour cleanup delay (csi-test-app-1 remained in Terminating state)
- **Findings**: PreStop hooks prevent Multi-Attach errors but revealed severe CSI driver performance issues
- **Timeline**: Started 2025-09-11 ~18:00 PDT, completed 2025-09-12 ~09:00 PDT

## New Development: etcd Real-World Testing

### Motivation
Need to test with actual application workloads instead of synthetic stress tests to validate preStop hooks solution.

### GitHub Repository
**Repository**: https://github.com/netSkopePlatformEng/csi-mount-testing  
**Organization**: netSkopePlatformEng  
**Access**: Public repository for platform engineering team  

### Files Created in `/Users/jdambly/repos/csi-mount-testing/`

#### 1. Docker Images
- **`Dockerfile`** - Netskope-compliant base image (requires VPN access)
- **`Dockerfile.public`** - Public Ubuntu 20.04 base image (working)
- **`build.sh`** - Automated build script

**Built Image**: `etcd-csi-test:latest` (etcd v3.5.9)

#### 2. Kubernetes Manifests
- **`etcd-statefulset.yaml`** - Production manifest using Netskope artifactory
- **`etcd-statefulset-local.yaml`** - Test manifest using local Docker image
- **`etcd-test-client.yaml`** - Monitoring and test client

#### 3. Documentation
- **`README.md`** - Complete deployment and testing procedures

### etcd Test Configuration

**StatefulSet Specs**:
```yaml
replicas: 3
podManagementPolicy: Parallel  # Triggers Multi-Attach scenarios
terminationGracePeriodSeconds: 900  # 15 minutes for CSI cleanup
```

**Data Generation Strategy**:
- **Bulk Data**: 10x 1KB entries per cycle
- **Frequent Updates**: 50 timestamp entries per cycle  
- **Large Entries**: 3x 10KB entries per cycle
- **Continuous Operation**: 1-second intervals with monitoring

**PreStop Hooks**:
```bash
# Gracefully stop etcd processes
pkill -TERM etcd || true
sleep 5

# Close file handles to data volume
lsof +f -- /var/lib/etcd | awk 'NR>1 {print $2}' | xargs kill -TERM

# Sync filesystem
sync; sync; sync

# Wait for CSI cleanup (30 seconds)
sleep 30
```

**Storage**: 8GB PVC per pod using `csi-cinder-sc-delete`

## Session Commands History

### Initial Setup
```bash
# Navigate to project directory
cd /Users/jdambly/repos/csi-mount-testing

# Build etcd container
./build.sh

# Test built image
docker run --rm etcd-csi-test:latest --version
```

### Current Monitoring Commands
```bash
# Monitor current test
kubectl get pods -n csi-mount-test --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml

# Check terminating pod status
kubectl describe pod csi-test-app-1 -n csi-mount-test --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml

# Monitor events for Multi-Attach errors
kubectl get events -n csi-mount-test --field-selector reason=FailedAttachVolume --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml

# Check VolumeAttachments
kubectl get volumeattachments --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml | grep csi-mount-test
```

### Deployment Commands for etcd Test
```bash
# Deploy etcd cluster
kubectl apply -f etcd-statefulset-local.yaml --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml

# Deploy monitoring client
kubectl apply -f etcd-test-client.yaml --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml

# Monitor etcd deployment
kubectl get pods -n csi-mount-test -w --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml

# Check etcd cluster health
kubectl logs -n csi-mount-test deployment/etcd-test-client --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml

# Trigger rolling update test
kubectl rollout restart statefulset etcd-cluster -n csi-mount-test --kubeconfig=/Users/jdambly/.mcp/stork-qa01-mp-npe-iad0-nc1.yaml
```

## Key Findings & Issues

### Issue 1: 15-Hour CSI Cleanup Delay
**Problem**: Pod remained in Terminating state for 15 hours instead of 15 minutes
**Impact**: Unacceptable for production services requiring fast recovery
**Status**: Testing for consistency with current csi-test-app-1

### Issue 2: Artifactory Connectivity
**Problem**: Cannot access `artifactory.netskope.io` without VPN
**Solution**: Created public Ubuntu base image fallback
**Files**: `Dockerfile.public` and `etcd-statefulset-local.yaml`

### Issue 3: Policy Violations
**Observed**: PolicyViolation events for "Images must be sourced from artifactory"
**Impact**: May block new pod creation during rolling updates
**Mitigation**: Use local images for testing, address for production

## Testing Strategy

### Current Test (In Progress)
**Objective**: Determine if 15-hour cleanup delay is consistent
**Method**: Monitor current terminating pod `csi-test-app-1`
**Started**: 2025-09-12 14:54 PDT
**Current Duration**: ~3 hours

### Planned Test: etcd Comparison
**Objective**: Validate preStop hooks with real application workloads
**Method**: Deploy etcd cluster and trigger rolling updates
**Expected**: Shorter cleanup times with database-appropriate I/O patterns

### Comparison Points
1. **Cleanup Duration**: Synthetic vs real workload
2. **Multi-Attach Prevention**: Effectiveness with different I/O patterns  
3. **Data Integrity**: etcd data survival through rolling updates
4. **Resource Usage**: CSI driver performance under different loads

## Related Documentation

### Previous Analysis Files
- `/Users/jdambly/csi-mount-issue-analysis.md` - Initial investigation
- `/Users/jdambly/csi-mount-issue-complete-analysis.md` - Comprehensive solution document
- `/Users/jdambly/k8s-csi-troubleshooting-guide.md` - Object relationship guide
- `/Users/jdambly/drm-multi-attach-reproduction-sop.md` - Production testing SOP

### Jira Tickets
- **OPS-234241**: DRM Pod Not Healthy (Multi-Attach errors) - Updated with findings
- **SYS-24675**: Cinder CSI plugin not fully dismounting PVCs - Root cause ticket

## Next Steps for Dev Machine

### 1. Transfer Files
Copy entire `/Users/jdambly/repos/csi-mount-testing/` directory to dev machine

### 2. Build Images (if needed)
```bash
# Option A: Build Netskope-compliant image (requires VPN)
./build.sh

# Option B: Build public image
docker build -f Dockerfile.public -t etcd-csi-test:latest .
```

### 3. Deploy Tests
```bash
# Set kubeconfig for test cluster
export KUBECONFIG=/path/to/stork-qa01-mp-npe-iad0-nc1.yaml

# Deploy etcd test
kubectl apply -f etcd-statefulset-local.yaml

# Monitor both tests
kubectl get pods -n csi-mount-test -w
```

### 4. Trigger Rolling Updates
```bash
# Test etcd rolling update
kubectl rollout restart statefulset etcd-cluster -n csi-mount-test

# Monitor for Multi-Attach errors and cleanup timing
kubectl get events -n csi-mount-test --field-selector reason=FailedAttachVolume -w
```

### 5. Data Collection
- Record termination durations for both synthetic and real workloads
- Compare Multi-Attach error frequencies
- Document any differences in CSI driver behavior
- Update OPS-234241 with comparative results

## Expected Outcomes

### Success Criteria
1. **Consistent preStop hook effectiveness** across workload types
2. **Reasonable cleanup timing** (< 1 hour for real workloads)
3. **No data corruption** in etcd during rolling updates
4. **Reproducible results** for production recommendation

### Risk Assessment
- **15-hour delays** make solution unsuitable for critical services
- **CSI driver upgrade** (SYS-24675) may be required before production deployment
- **Alternative solutions** (blue-green deployments, pod anti-affinity) may be needed

## GitHub Repository

**Repository**: https://github.com/netSkopePlatformEng/csi-mount-testing  
**Organization**: netSkopePlatformEng  
**Access**: Public repository for platform engineering team collaboration  

### Clone for Dev Machine
```bash
git clone https://github.com/netSkopePlatformEng/csi-mount-testing.git
cd csi-mount-testing
```

---

*Session Date: 2025-09-12*  
*Status: Active testing in progress - Repository created*  
*Contact: Jeff d'Ambly (jdambly@netskope.com)*