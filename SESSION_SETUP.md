# Session Setup Guide

This document captures all the tools and setup used to deploy MTProxy on OCI.

## Prerequisites

- Terraform installed
- kubectl configured with access to EKS cluster
- OCI CLI configured (for checking available images)
- SSH key pair (`~/.ssh/id_ed25519`)

## Infrastructure Overview

- **Cloud Provider**: Oracle Cloud Infrastructure (OCI) Free Tier
- **Instance Shape**: VM.Standard.E2.1.Micro (1 OCPU, 1GB RAM)
- **OS**: Ubuntu 22.04 Minimal (chosen for low memory footprint ~200MB vs Oracle Linux ~400MB)
- **Region**: eu-frankfurt-1

## K8s Bastion Setup (for SSH access behind corporate firewall)

The K8s bastion pod is used to bypass ZScaler/corporate firewall that blocks SSH ports.

### Create Bastion Pod
```bash
# Context for the EKS cluster
K8S_CONTEXT="arn:aws:eks:eu-west-1:747626100725:cluster/az-img-dev-kfv2-eks"

# Create bastion pod
kubectl --context $K8S_CONTEXT run bastion-pod --image=alpine:latest --restart=Never -- sleep infinity

# Wait for pod to be ready
kubectl --context $K8S_CONTEXT wait --for=condition=Ready pod/bastion-pod --timeout=60s

# Install SSH client
kubectl --context $K8S_CONTEXT exec bastion-pod -- apk add --no-cache openssh-client

# Copy SSH key to bastion pod
kubectl --context $K8S_CONTEXT exec bastion-pod -- mkdir -p /root/.ssh
kubectl --context $K8S_CONTEXT cp ~/.ssh/id_ed25519 bastion-pod:/root/.ssh/id_ed25519
kubectl --context $K8S_CONTEXT exec bastion-pod -- chmod 600 /root/.ssh/id_ed25519
```

### SSH to OCI Instance via Bastion
```bash
# Get instance IP from terraform
INSTANCE_IP=$(terraform output -raw instance_public_ip)

# SSH via bastion pod
kubectl --context $K8S_CONTEXT exec bastion-pod -- ssh -o StrictHostKeyChecking=no ubuntu@$INSTANCE_IP "<command>"
```

### Cleanup Bastion Pod
```bash
kubectl --context $K8S_CONTEXT delete pod bastion-pod
```

## Terraform Commands

### Initialize
```bash
cd terraform
terraform init -backend-config=backend.conf
```

### Deploy Infrastructure
```bash
terraform apply
```

### Recreate Instance (e.g., after cloud-init changes)
```bash
# Recommended: use -replace flag (single command)
terraform apply -replace=oci_core_instance.mtproxy

# Deprecated: taint + apply (two commands, taint is deprecated)
# terraform taint oci_core_instance.mtproxy
# terraform apply
```

### Get Outputs
```bash
# Get all outputs
terraform output

# Get specific outputs
terraform output instance_public_ip
terraform output -raw mtproxy_secret
terraform output -raw telegram_proxy_link
```

### Destroy Infrastructure
```bash
terraform destroy
```

## Verify MTProxy is Running

```bash
# Via K8s bastion
kubectl --context $K8S_CONTEXT exec bastion-pod -- ssh ubuntu@$INSTANCE_IP "sudo docker ps"
kubectl --context $K8S_CONTEXT exec bastion-pod -- ssh ubuntu@$INSTANCE_IP "sudo docker logs mtproxy"
```

## Check Cloud-Init Status

```bash
kubectl --context $K8S_CONTEXT exec bastion-pod -- ssh ubuntu@$INSTANCE_IP "cloud-init status"
```

## Memory Usage Comparison

| OS | RAM at Idle | With Docker + MTProxy |
|----|-------------|----------------------|
| Oracle Linux 8 | ~400MB | ~500MB+ |
| Ubuntu 22.04 Minimal | ~180MB | ~250MB |

## File Structure

```
terraform/
├── backend.conf          # S3 backend configuration
├── cloud-init.yaml       # Instance initialization (Docker + MTProxy)
├── compute.tf            # Instance and image configuration
├── network.tf            # VCN, subnet, security list
├── outputs.tf            # Terraform outputs
├── providers.tf          # Provider configuration
├── variables.tf          # Variable definitions
└── terraform.tfvars      # Variable values (not in git)
```

## Troubleshooting

### Cloud-init not completing
```bash
# Check cloud-init logs
kubectl --context $K8S_CONTEXT exec bastion-pod -- ssh ubuntu@$INSTANCE_IP "sudo cat /var/log/cloud-init-output.log"
```

### Docker not starting
```bash
# Check Docker service status
kubectl --context $K8S_CONTEXT exec bastion-pod -- ssh ubuntu@$INSTANCE_IP "sudo systemctl status docker"
```

### MTProxy container issues
```bash
# Check container logs
kubectl --context $K8S_CONTEXT exec bastion-pod -- ssh ubuntu@$INSTANCE_IP "sudo docker logs mtproxy"

# Restart container
kubectl --context $K8S_CONTEXT exec bastion-pod -- ssh ubuntu@$INSTANCE_IP "sudo docker restart mtproxy"
```
