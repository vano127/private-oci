# Session Setup Guide

This document captures all the tools and setup used to deploy MTProxy and VLESS + Reality on OCI.

**IMPORTANT:** All infrastructure changes must be applied through Terraform for reproducibility. Manual commands via bastion are for testing only.

## Prerequisites

- Terraform installed
- kubectl configured with access to EKS cluster
- OCI CLI configured (for checking available images)
- SSH key pair (`~/.ssh/id_ed25519`)
- Zscaler certificate for HTTPS fetches (corporate network)

### Zscaler Certificate

For HTTPS requests through corporate proxy, use the zscaler certificate:

```bash
# Curl with zscaler cert
curl --cacert /Users/kmvr200/IdeaProjects/personal-oci/zscaler.crt https://example.com

# Or set environment variable
export CURL_CA_BUNDLE=/Users/kmvr200/IdeaProjects/personal-oci/zscaler.crt
export REQUESTS_CA_BUNDLE=/Users/kmvr200/IdeaProjects/personal-oci/zscaler.crt
```

## Infrastructure Overview

- **Cloud Provider**: Oracle Cloud Infrastructure (OCI) Free Tier
- **Instance Shape**: VM.Standard.E2.1.Micro (1 OCPU, 1GB RAM)
- **OS**: Ubuntu 22.04 Minimal (chosen for low memory footprint ~200MB vs Oracle Linux ~400MB)
- **Region**: eu-frankfurt-1 (Frankfurt - Free Tier home region)
- **Static IP**: Reserved public IP (persists across instance recreates)

## Current Configuration

Four containers run on the same instance, all deployed automatically via cloud-init:

| Container | Image | Port | Purpose |
|-----------|-------|------|---------|
| mtproxy | nineseconds/mtg:2 | 443 | Primary Telegram proxy (cdn.jsdelivr.net) |
| mtproxy-secondary | fra.ocir.io/fratzuns8xud/mtproxy:latest | 9443 | Secondary Telegram proxy (wildberries.ru) |
| xray-vless | teddysun/xray | 8443 | VLESS + Reality server (universal VPN) |
| nginx-config | nginx:alpine | 8080 | Client config server (no secrets) |

### Primary Proxy (cdn.jsdelivr.net)
- **Port**: 443
- **Domain**: cdn.jsdelivr.net (well-known CDN)
- **Container**: mtproxy
- **Config**: /home/ubuntu/mtg-config.toml

### Secondary Proxy (wildberries.ru) - For MegaFon
- **Port**: 9443
- **Domain**: wildberries.ru (major Russian e-commerce, less monitored)
- **Container**: mtproxy-secondary
- **Config**: /home/ubuntu/mtg-config-secondary.toml

### VLESS + Reality Server
- **Port**: 8443 (configurable via `vless_port`)
- **Protocol**: VLESS with Reality TLS
- **Container**: xray-vless
- **Config**: /home/ubuntu/xray-config.json
- **Public Key**: /home/ubuntu/vless-public-key.txt
- **SNI Domain**: www.microsoft.com (configurable via `vless_dest_domain`)

### Get Proxy Links

```bash
cd /Users/kmvr200/IdeaProjects/personal-oci/terraform

# Primary proxy link
terraform output -raw telegram_proxy_link

# Secondary proxy link
terraform output -raw telegram_proxy_link_secondary

# All outputs
terraform output
```

### Get VLESS + Reality Link

The VLESS link requires the Reality public key which is generated at instance creation time.

```bash
cd /Users/kmvr200/IdeaProjects/personal-oci/terraform

# Get link template (contains PUBLIC_KEY placeholder)
terraform output -raw vless_link_template

# Get the actual public key from instance
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "cat /home/ubuntu/vless-public-key.txt"

# Replace PUBLIC_KEY in the template with the actual key
```

**Mobile Clients for VLESS + Reality:**
- **Android**: v2rayNG (free, open-source) or Hiddify
- **iOS**: Shadowrocket ($2.99, most reliable) or Streisand (free)

### Client Config Server

A config server runs on port 8080 serving client-side proxy settings (no secrets).

**Public URL (safe to share):**
```
http://92.5.20.109:8080/config.json
```

This config sets up:
- SOCKS5 proxy on `127.0.0.1:10808`
- HTTP proxy on `127.0.0.1:10809`

**User setup flow:**
1. Import client config from URL: `http://92.5.20.109:8080/config.json`
2. Import server config (VLESS URL) - shared privately
3. Both configs combine for proxy mode operation

### Config Server (nginx)
- **Port**: 8080
- **Container**: nginx-config
- **Content**: /home/ubuntu/nginx-config/config.json
- **Purpose**: Serves client-side proxy mode settings (SOCKS5/HTTP inbounds) without exposing server credentials
- **Public URL**: `http://<primary-ip>:8080/config.json`

### Features Enabled (both MTProxy instances)
- **Fake-TLS**: Disguises traffic as HTTPS
- **Anti-replay**: Blocks DPI probe replay attacks (1MB bloom filter cache)
- **IP Blocklist**: FireHOL level1 (~40k IPs)
- **DC Fallback**: Enabled for better connectivity
- **Timeouts**: 30s TCP/HTTP, 5m idle

---

## Terraform Commands

All commands should be run from `/Users/kmvr200/IdeaProjects/personal-oci/terraform`

### Initialize
```bash
cd /Users/kmvr200/IdeaProjects/personal-oci/terraform
terraform init -backend-config=backend.conf
```

### Deploy Infrastructure
```bash
cd /Users/kmvr200/IdeaProjects/personal-oci/terraform
terraform apply
```

### Change Proxy Configuration

To change domains or ports, update `terraform.tfvars`:

```hcl
# Primary proxy
mtproxy_port            = 443
mtproxy_fake_tls_domain = "cdn.jsdelivr.net"

# Secondary proxy
mtproxy_secondary_port   = 9443
mtproxy_secondary_domain = "wildberries.ru"

# VLESS + Reality
vless_port              = 8443
vless_dest_domain       = "www.microsoft.com"
```

Then recreate the instance to apply changes:

```bash
cd /Users/kmvr200/IdeaProjects/personal-oci/terraform
terraform apply -replace=oci_core_instance.mtproxy
```

### Get Outputs
```bash
cd /Users/kmvr200/IdeaProjects/personal-oci/terraform

# Get all outputs
terraform output

# Get specific outputs
terraform output instance_public_ip
terraform output -raw telegram_proxy_link
terraform output -raw telegram_proxy_link_secondary
```

### Destroy Infrastructure
```bash
cd /Users/kmvr200/IdeaProjects/personal-oci/terraform
terraform destroy
```

---

## Bastion Script Usage (Testing Only)

Use the bastion script for testing and debugging. For permanent changes, update Terraform instead.

```bash
# Setup bastion pod
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh setup

# Check status
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh status

# Execute command on OCI instance (testing only)
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker ps"
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker logs mtproxy"

# Interactive SSH
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh ssh

# Cleanup
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh cleanup
```

---

## Monitoring Proxy Statistics

### Check Proxy Status
```bash
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker ps"
```

### Check Active Connections
```bash
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "ss -tn state established '( sport = :443 )' | tail -n +2 | wc -l"
```

### Check Connection Statistics
```bash
# Failed handshakes (blocked probes/scanners)
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec 'sudo docker logs mtproxy 2>&1 | grep -c "handshake is failed"'

# Successful streams
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec 'sudo docker logs mtproxy 2>&1 | grep -c "Stream has been started"'

# Unique client IPs with connection counts
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec 'sudo docker logs mtproxy 2>&1 | grep "client-ip" | grep -oE "client-ip\":\"[0-9.]+" | sort | uniq -c | sort -rn'
```

### What Gets Blocked

| Protection | What It Blocks |
|------------|----------------|
| Anti-replay | DPI probes replaying captured handshakes |
| IP Blocklist | Known scanners/attackers (FireHOL list ~40k IPs) |
| Invalid handshake | Scanners sending non-MTProxy traffic |

---

## Recommended Fake-TLS Domains

### Tier 1: Russian Services (Best for Russia)
Russian ISPs cannot block these without massive collateral damage.

| Domain | Why It's Good |
|--------|---------------|
| `wildberries.ru` | Major Russian e-commerce |
| `ozon.ru` | Russian Amazon-like |
| `vk.com` | Major Russian social network |
| `yandex.ru` | Russian search/services (may be monitored) |

### Tier 2: International CDNs

| Domain | Why It's Good |
|--------|---------------|
| `cdn.jsdelivr.net` | Used by many websites |
| `storage.googleapis.com` | Google Cloud storage |

### Tier 3: Common (May Be Fingerprinted)

| Domain | Risk Level |
|--------|------------|
| `www.microsoft.com` | Medium |
| `www.google.com` | High (common target) |
| `cloudflare.com` | High (very common) |

---

## OCI Free Tier Limits

| Resource | Limit | Current Usage |
|----------|-------|---------------|
| AMD Compute (VM.Standard.E2.1.Micro) | 2 instances | 1 |
| Boot Volume | 200 GB | 47 GB |
| Reserved Public IP | Included | 2 (primary + secondary) |
| Outbound Data | 10 TB/month | ~minimal |

**Free tier has no time limit** - resources remain free indefinitely.

---

## OCI Container Registry (OCIR)

Custom MTProxy image is stored in OCIR for GitOps deployment.

### Registry Details

| Item | Value |
|------|-------|
| Registry | `fra.ocir.io` (NOT eu-frankfurt-1.ocir.io) |
| Namespace | `fratzuns8xud` |
| Image | `fra.ocir.io/fratzuns8xud/mtproxy:latest` |

## Dual-IP Setup

The instance has two public IPs - one for each proxy:

| Proxy | Public IP | Private IP | Port | Domain |
|-------|-----------|------------|------|--------|
| Primary | 92.5.20.109 (reserved) | auto | 443 | cdn.jsdelivr.net |
| Secondary | dynamic (reserved) | 10.0.1.100 | 9443 | wildberries.ru |

**Note:** The secondary private IP must be configured in the OS. Cloud-init handles this automatically using the static IP `10.0.1.100`.

### Get OCIR Credentials

```bash
cd /Users/kmvr200/IdeaProjects/personal-oci/terraform

# Get username
terraform output -raw ocir_username

# Get token (password)
terraform output -raw ocir_token
```

### Build and Push Image Locally

**IMPORTANT:** OCI Free Tier instances use AMD64 architecture. If building on Apple Silicon (M1/M2/M3), you MUST specify `--platform linux/amd64`.

```bash
# Start podman machine
podman machine start

# Copy zscaler cert (gitignored, must copy before build)
cp /Users/kmvr200/IdeaProjects/personal-oci/zscaler.crt /Users/kmvr200/IdeaProjects/personal-oci/docker/

# Build image for AMD64 (required for OCI)
cd /Users/kmvr200/IdeaProjects/personal-oci/docker
podman build --platform linux/amd64 -t mtproxy:latest .

# Login to OCIR
OCIR_TOKEN=$(cd /Users/kmvr200/IdeaProjects/personal-oci/terraform && terraform output -raw ocir_token)
echo "$OCIR_TOKEN" | podman login fra.ocir.io -u "fratzuns8xud/m.bikova2009@gmail.com" --password-stdin

# Tag and push
podman tag localhost/mtproxy:latest fra.ocir.io/fratzuns8xud/mtproxy:latest
podman push fra.ocir.io/fratzuns8xud/mtproxy:latest
```

### Custom Image Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MTG_SECRET` | Yes | - | Base secret (16 bytes hex) |
| `MTG_DOMAIN` | Yes | - | Fake-TLS domain |
| `MTG_PORT` | No | 3128 | Container bind port |
| `MTG_ANTI_REPLAY` | No | true | Enable anti-replay |
| `MTG_BLOCKLIST` | No | true | Enable IP blocklist |

---

## File Structure

```
/Users/kmvr200/IdeaProjects/personal-oci/
├── terraform/
│   ├── backend.conf          # S3 backend configuration
│   ├── cloud-init.yaml       # Instance initialization (Docker + all containers)
│   ├── compute.tf            # Instance, IPs, and VLESS UUID generation
│   ├── network.tf            # VCN, subnet, security list (ports 443, 9443, 8443, 8080)
│   ├── ocir.tf               # OCIR repository and auth token
│   ├── outputs.tf            # Terraform outputs (proxy links, VLESS template)
│   ├── providers.tf          # Provider configuration
│   ├── variables.tf          # Variable definitions (incl. VLESS settings)
│   └── terraform.tfvars      # Variable values (not in git)
├── docker/
│   ├── Dockerfile            # Custom MTProxy image
│   ├── entrypoint.sh         # Config generation from env vars
│   ├── docker-compose.yml    # Deployment with Watchtower
│   ├── .env.example          # Environment template
│   └── zscaler.crt           # Zscaler cert for image build
├── .github/workflows/
│   └── build-image.yml       # CI/CD pipeline for OCIR
├── scripts/
│   └── bastion-setup.sh      # Helper script for SSH via K8s bastion
├── zscaler.crt               # Zscaler certificate for HTTPS fetches
└── SESSION_SETUP.md          # This file
```

### Instance File Layout

```
/home/ubuntu/
├── mtg-config.toml           # Primary MTProxy config (generated by cloud-init)
├── xray-config.json          # VLESS + Reality Xray config (generated by cloud-init)
├── vless-public-key.txt      # Reality public key (for client link generation)
└── nginx-config/
    └── config.json           # Client proxy mode settings (served by nginx, no secrets)
```

---

## Troubleshooting

### Cloud-init not completing
```bash
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo cat /var/log/cloud-init-output.log"
```

### Docker not starting
```bash
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo systemctl status docker"
```

### MTProxy container issues
```bash
# Check container logs
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker logs mtproxy"
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker logs mtproxy-secondary"

# Restart container
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker restart mtproxy"
```

### VLESS + Reality issues
```bash
# Check Xray container
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker logs xray-vless"

# Verify Reality public key
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "cat /home/ubuntu/vless-public-key.txt"

# Test port connectivity from bastion
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "nc -zv -w 5 92.5.20.109 8443"

# Restart Xray
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker restart xray-vless"
```

### Config server issues
```bash
# Check nginx container
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "sudo docker logs nginx-config"

# Test config endpoint
/Users/kmvr200/IdeaProjects/personal-oci/scripts/bastion-setup.sh exec "curl -s http://localhost:8080/config.json"
```

### Host key changed after instance recreate
```bash
# Clear known_hosts on bastion pod
kubectl --context $K8S_CONTEXT exec bastion-pod -- rm -f /root/.ssh/known_hosts
```

### Slow speeds from Russia
1. Change domain in `terraform.tfvars` and recreate instance
2. Try Russian domains (`wildberries.ru`, `ozon.ru`) - less likely to be fingerprinted
3. Use VLESS + Reality (better DPI evasion than MTProxy)
4. If all fails, consider Shadowsocks or WireGuard

### v2rayNG not connecting
1. Verify port is open: test from bastion with `nc -zv -w 5 <ip> 8443`
2. Check OCI security list has the port rule (terraform apply if needed)
3. Check iptables on instance: `sudo iptables -L INPUT -n --line-numbers`
4. Verify all VLESS settings match exactly (UUID, public key, SNI, flow)
5. v2rayNG is not in Russian Play Store - download APK from GitHub: `https://github.com/2dust/v2rayNG/releases`
6. Alternative Android clients: Hiddify, NekoBox

---

## VLESS + Reality Overview

VLESS + Reality is an advanced censorship evasion protocol:

- **VLESS**: Lightweight proxy protocol (lighter than VMess)
- **Reality**: TLS fingerprint masquerading technology

### How Reality Works

Unlike traditional TLS proxies that use fake certificates, Reality:
1. Uses the actual TLS certificate of a legitimate website (e.g., microsoft.com)
2. Performs server-side TLS handshake impersonation
3. DPI sees traffic that looks identical to legitimate HTTPS

### Advantages Over MTProxy

| Feature | MTProxy | VLESS + Reality |
|---------|---------|-----------------|
| Protocol | Telegram-specific | Universal (any TCP/UDP) |
| Detection | Detectable by traffic patterns | Very hard to detect |
| Use cases | Telegram only | Any app/browser |
| Setup | Simpler | More complex |

### Current Configuration

| Setting | Value |
|---------|-------|
| Port | 8443 |
| SNI/Dest | www.microsoft.com |
| Flow | xtls-rprx-vision |
| Short IDs | "", "0123456789abcdef" |

---

## DPI Evasion Notes

### Why Russian DPI Can't Be Blocked by IP

Russian DPI (TSPU - Technical System for Countering Threats) works differently than scanners:

| Traditional Scanner | Russian DPI (TSPU) |
|--------------------|--------------------|
| Connects TO your server | Sits INLINE in network path |
| Has specific IP ranges | Uses ISP's own infrastructure |
| Can be blocked by IP | Cannot be blocked by IP |

The solution is protocol-level evasion (fake-TLS, anti-replay), not IP blocking.

### Current Defenses
- Fake-TLS with Russian/CDN domains (MTProxy)
- Anti-replay protection (MTProxy)
- IP blocklist for known scanners (MTProxy)
- Domain fronting (invalid connections forwarded to real domain)
- VLESS + Reality (universal proxy, near-undetectable TLS masquerading)

---

## Important Notes

### Architecture
- OCI Free Tier instances use **AMD64** architecture
- When building Docker images on Apple Silicon (M1/M2/M3), always use `--platform linux/amd64`

### Port Allocation

| Port | Service | Protocol |
|------|---------|----------|
| 443 | MTProxy primary | MTProto fake-TLS |
| 9443 | MTProxy secondary | MTProto fake-TLS |
| 8443 | VLESS + Reality | VLESS over Reality TLS |
| 8080 | Config server | HTTP (nginx) |

### Security
- VLESS server credentials (UUID, private key) are never exposed via the config server
- The config server only serves client-side proxy mode settings (SOCKS5/HTTP inbounds)
- Share VLESS connection URLs only via private/encrypted channels
- Reality keys are generated at instance creation time and stored on the instance
