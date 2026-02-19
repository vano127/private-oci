#!/bin/bash
# Bastion pod setup script for SSH access to OCI instances

set -e

K8S_CONTEXT="arn:aws:eks:eu-west-1:747626100725:cluster/az-img-dev-kfv2-eks"
POD_NAME="bastion-pod"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  setup     Create and configure bastion pod"
    echo "  ssh       SSH to OCI instance (requires INSTANCE_IP env var or terraform)"
    echo "  exec      Execute command on OCI instance"
    echo "  cleanup   Delete bastion pod"
    echo "  status    Check bastion pod status"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 ssh"
    echo "  $0 exec 'sudo docker ps'"
    echo "  $0 cleanup"
}

get_instance_ip() {
    if [ -n "$INSTANCE_IP" ]; then
        echo "$INSTANCE_IP"
    elif [ -f "terraform/terraform.tfstate" ] || [ -f "terraform.tfstate" ]; then
        cd "$(dirname "$0")/../terraform" 2>/dev/null || cd "$(dirname "$0")/.." 2>/dev/null || true
        terraform output -raw instance_public_ip 2>/dev/null
    else
        echo "Error: INSTANCE_IP not set and terraform state not found" >&2
        exit 1
    fi
}

setup() {
    echo "Creating bastion pod..."
    kubectl --context "$K8S_CONTEXT" run "$POD_NAME" --image=alpine:latest --restart=Never -- sleep infinity 2>/dev/null || true

    echo "Waiting for pod to be ready..."
    kubectl --context "$K8S_CONTEXT" wait --for=condition=Ready "pod/$POD_NAME" --timeout=60s

    echo "Installing SSH client..."
    kubectl --context "$K8S_CONTEXT" exec "$POD_NAME" -- apk add --no-cache openssh-client

    echo "Copying SSH key..."
    kubectl --context "$K8S_CONTEXT" exec "$POD_NAME" -- mkdir -p /root/.ssh
    kubectl --context "$K8S_CONTEXT" cp "$SSH_KEY" "$POD_NAME:/root/.ssh/id_ed25519"
    kubectl --context "$K8S_CONTEXT" exec "$POD_NAME" -- chmod 600 /root/.ssh/id_ed25519

    echo "Bastion pod ready!"
}

ssh_to_instance() {
    IP=$(get_instance_ip)
    echo "Connecting to ubuntu@$IP..."
    kubectl --context "$K8S_CONTEXT" exec -it "$POD_NAME" -- ssh -o StrictHostKeyChecking=no "ubuntu@$IP"
}

exec_on_instance() {
    IP=$(get_instance_ip)
    kubectl --context "$K8S_CONTEXT" exec "$POD_NAME" -- ssh -o StrictHostKeyChecking=no "ubuntu@$IP" "$@"
}

cleanup() {
    echo "Deleting bastion pod..."
    kubectl --context "$K8S_CONTEXT" delete pod "$POD_NAME" --ignore-not-found
    echo "Done."
}

status() {
    kubectl --context "$K8S_CONTEXT" get pod "$POD_NAME" 2>/dev/null || echo "Bastion pod not found"
}

case "${1:-}" in
    setup)
        setup
        ;;
    ssh)
        ssh_to_instance
        ;;
    exec)
        shift
        exec_on_instance "$@"
        ;;
    cleanup)
        cleanup
        ;;
    status)
        status
        ;;
    *)
        usage
        exit 1
        ;;
esac
