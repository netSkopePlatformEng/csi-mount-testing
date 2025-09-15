#!/bin/bash

# Build script for custom etcd image
set -e

# Configuration
ARTIFACTORY_ENDPOINT=${ARTIFACTORY_ENDPOINT:-artifactory.netskope.io}
IMAGE_NAME="etcd-csi-test"
TAG=${TAG:-latest}
FULL_IMAGE="${ARTIFACTORY_ENDPOINT}/pe-docker/${IMAGE_NAME}:${TAG}"

echo "Building etcd image for CSI testing..."
echo "Image: ${FULL_IMAGE}"

# Build the image
docker build \
    --build-arg artifactory_endpoint=${ARTIFACTORY_ENDPOINT} \
    -t ${FULL_IMAGE} \
    .

echo "Build complete: ${FULL_IMAGE}"
echo ""
echo "To push to artifactory:"
echo "  docker push ${FULL_IMAGE}"
echo ""
echo "To test locally:"
echo "  docker run --rm -it ${FULL_IMAGE} --help"