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
- **Static IP**: Reserved public IP (persists across instance recreates)

## Current MTProxy Configuration

- **IP**: 138.2.146.96 (reserved/static)
- **Port**: 443
- **Fake-TLS Domain**: www.microsoft.com (helps bypass Russian DPI)
- **Docker Image**: nineseconds/mtg:2
- **Secret Format**: `ee` + 16-byte-hex-secret + hex-encoded-domain

### Telegram Proxy Link
```
https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a7777772e6d6963726f736f66742e636f6d
```

### Why Fake-TLS?
Russian ISPs use DPI (Deep Packet Inspection) to detect and throttle MTProxy traffic. Fake-TLS disguises the traffic as regular HTTPS to a legitimate domain (www.microsoft.com), making it harder to detect.

## Bastion Script Usage

Use the bastion script instead of direct kubectl commands:

```bash
# Setup bastion pod
./scripts/bastion-setup.sh setup

# Check status
./scripts/bastion-setup.sh status

# Execute command on OCI instance
./scripts/bastion-setup.sh exec "sudo docker ps"
./scripts/bastion-setup.sh exec "sudo docker logs mtproxy"

# Interactive SSH
./scripts/bastion-setup.sh ssh

# Cleanup
./scripts/bastion-setup.sh cleanup
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

## Manually Change Fake-TLS Domain

To change the domain without recreating the instance:

```bash
# Stop current container
./scripts/bastion-setup.sh exec "sudo docker stop mtproxy && sudo docker rm mtproxy"

# Calculate new secret (example for www.microsoft.com)
./scripts/bastion-setup.sh exec 'DOMAIN="www.microsoft.com"; DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d "\n"); echo "eefe9270abb78607fb38eb6e15bd048d6a$DOMAIN_HEX"'

# Start with new secret
./scripts/bastion-setup.sh exec 'sudo docker run -d --name mtproxy --restart always -p 443:3128 nineseconds/mtg:2 simple-run -d -t 30s 0.0.0.0:3128 "eefe9270abb78607fb38eb6e15bd048d6a7777772e6d6963726f736f66742e636f6d"'
```

## Verify MTProxy is Running

```bash
# Check container status
./scripts/bastion-setup.sh exec "sudo docker ps"

# Check logs
./scripts/bastion-setup.sh exec "sudo docker logs --tail 50 mtproxy"

# Check cloud-init status
./scripts/bastion-setup.sh exec "cloud-init status"
```

## Instance Capacity Analysis

### Current Resource Usage

| Component | CPU | RAM |
|-----------|-----|-----|
| Ubuntu 22.04 Minimal | - | ~180 MB |
| Docker daemon | <1% | ~80 MB |
| MTProxy (mtg) | <1% | ~30 MB |
| **Total** | ~1-2% | **~290 MB** |

### Available Capacity

- **RAM**: ~700 MB free (of 1024 MB)
- **CPU**: ~95% idle
- **Network**: ~480 Mbps
- **Outbound Data**: 10 TB/month (free tier limit)

### Can Support Additional Services

| Service | CPU Impact | RAM Impact | Feasible? |
|---------|------------|------------|-----------|
| WireGuard VPN | +2-3% | +10 MB | Yes |
| YouTube 1080p proxy | +2-3% | +50 MB buffers | Yes |
| YouTube 4K proxy | +5% | +100 MB buffers | Yes |
| Multiple video streams | +10% | +150 MB | Yes |

### Data Usage Estimates

| Activity | Data/hour | Monthly (3 hrs/day) |
|----------|-----------|---------------------|
| Telegram text | ~10 MB | ~1 GB |
| Telegram video call | ~500 MB | ~45 GB |
| YouTube 720p | ~2.5 GB | ~225 GB |
| YouTube 1080p | ~3.5 GB | ~315 GB |
| YouTube 4K | ~11 GB | ~1 TB |

**10 TB/month limit is sufficient for personal use.**

## MTProxy Limitations

MTProxy only supports Telegram text/media messages. It does NOT support:
- Telegram voice calls (requires UDP)
- Telegram video calls (requires UDP)
- Other applications

### Options for Call Support

| Solution | Telegram Texts | Calls | Other Apps | Battery Impact |
|----------|---------------|-------|------------|----------------|
| MTProxy (current) | Yes | No | No | Minimal |
| WireGuard | Yes | Yes | Yes | Low-Medium |
| Shadowsocks | Yes | Yes* | Yes | Medium |

*Shadowsocks UDP relay can be unreliable for calls.

**Recommendation**: Add WireGuard for call support (can run alongside MTProxy on different port).

## Memory Usage Comparison

| OS | RAM at Idle | With Docker + MTProxy |
|----|-------------|----------------------|
| Oracle Linux 8 | ~400MB | ~500MB+ |
| Ubuntu 22.04 Minimal | ~180MB | ~290MB |

## File Structure

```
terraform/
├── backend.conf          # S3 backend configuration
├── cloud-init.yaml       # Instance initialization (Docker + MTProxy)
├── compute.tf            # Instance and image configuration
├── network.tf            # VCN, subnet, security list
├── outputs.tf            # Terraform outputs (fake-TLS secret calculation)
├── providers.tf          # Provider configuration
├── variables.tf          # Variable definitions
└── terraform.tfvars      # Variable values (not in git)

scripts/
└── bastion-setup.sh      # Helper script for SSH via K8s bastion
```

## Troubleshooting

### Cloud-init not completing
```bash
./scripts/bastion-setup.sh exec "sudo cat /var/log/cloud-init-output.log"
```

### Docker not starting
```bash
./scripts/bastion-setup.sh exec "sudo systemctl status docker"
```

### MTProxy container issues
```bash
# Check container logs
./scripts/bastion-setup.sh exec "sudo docker logs mtproxy"

# Restart container
./scripts/bastion-setup.sh exec "sudo docker restart mtproxy"
```

### Host key changed after instance recreate
```bash
# Clear known_hosts on bastion pod
kubectl --context $K8S_CONTEXT exec bastion-pod -- rm -f /root/.ssh/known_hosts
```

### Slow speeds from Russia
1. Try different fake-TLS domains: `www.microsoft.com`, `www.google.com`, `storage.googleapis.com`
2. Check if ISP is throttling specific domains
3. Consider switching to WireGuard or Shadowsocks if DPI blocking persists
