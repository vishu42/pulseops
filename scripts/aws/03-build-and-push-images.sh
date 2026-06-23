#!/usr/bin/env bash
set -euo pipefail

# Builds and pushes service images to ECR.
#
# Prereqs:
#   source scripts/aws/00-env.sh
#   docker info

# Ensure shared AWS/ECR variables were loaded from 00-env.sh.
: "${AWS_PROFILE:?source scripts/aws/00-env.sh first}"
: "${AWS_REGION:?source scripts/aws/00-env.sh first}"
: "${ACCOUNT_ID:?source scripts/aws/00-env.sh first}"

# ECR registry hostname for this AWS account and region.
export ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Default image tag is the current git SHA. Override IMAGE_TAG for release tags.
export IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"

# Authenticate local Docker to ECR. The token is short-lived and scoped by the
# active AWS profile/permissions.
aws ecr get-login-password --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Build one service binary using Dockerfile ARG SERVICE, then push both immutable
# SHA tag and convenient latest tag.
build_and_push() {
  local service="$1"
  local repo="$2"
  local image="${ECR_REGISTRY}/${repo}:${IMAGE_TAG}"
  local latest="${ECR_REGISTRY}/${repo}:latest"

  # Build from the repo root. The Dockerfile compiles ./cmd/${SERVICE}.
  docker build --build-arg "SERVICE=${service}" -t "$image" -t "$latest" .

  # Push the immutable tag first, then latest for quick manual deployments.
  docker push "$image"
  docker push "$latest"

  echo "$service image:"
  echo "  $image"
}

# Publish every PulseOps runtime service.
build_and_push api-server "$API_REPO"
build_and_push scheduler "$SCHEDULER_REPO"
build_and_push status-checker "$CHECKER_REPO"
build_and_push status-writer "$WRITER_REPO"

echo "Pushed images with tag: $IMAGE_TAG"
