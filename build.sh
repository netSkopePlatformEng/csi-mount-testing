#!/bin/bash

# Build script for custom etcd image
set -e

# Configuration
ARTIFACTORY_ENDPOINT=${ARTIFACTORY_ENDPOINT:-artifactory.netskope.io}
IMAGE_NAME="etcd-csi-test"

# Default to v0.0.1 if no TAG is provided
TAG=${TAG:-v0.0.1}
FULL_IMAGE="${ARTIFACTORY_ENDPOINT}/pe-docker/${IMAGE_NAME}:${TAG}"

# Also tag as latest for convenience
LATEST_IMAGE="${ARTIFACTORY_ENDPOINT}/pe-docker/${IMAGE_NAME}:latest"

echo "Building etcd image for CSI testing..."
echo "Image: ${FULL_IMAGE}"

# Build the image
docker build \
    --build-arg artifactory_endpoint=${ARTIFACTORY_ENDPOINT} \
    -t ${FULL_IMAGE} \
    -t ${LATEST_IMAGE} \
    .

echo "Build complete: ${FULL_IMAGE}"
echo "Also tagged as: ${LATEST_IMAGE}"
echo ""
echo "To push to artifactory:"
echo "  docker push ${FULL_IMAGE}"
echo "  docker push ${LATEST_IMAGE}"
echo ""
echo "To test locally:"
echo "  docker run --rm -it ${FULL_IMAGE} --help"