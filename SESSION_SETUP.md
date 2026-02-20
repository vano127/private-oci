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
- **Base Secret**: `fe9270abb78607fb38eb6e15bd048d6a`

### Telegram Proxy Link
```
https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a7777772e6d6963726f736f66742e636f6d
```

### Why Fake-TLS?
Russian ISPs use DPI (Deep Packet Inspection) to detect and throttle MTProxy traffic. Fake-TLS disguises the traffic as regular HTTPS to a legitimate domain (www.microsoft.com), making it harder to detect.

---

## Future Improvements for DPI Evasion

### 1. Recommended Fake-TLS Domains

All domains below support TLS 1.3 (required for mtg compatibility).

#### Tier 1: Russian Services (Best for Russia)
Russian ISPs cannot block these without massive collateral damage.

| Domain | Why It's Good | Proxy Link |
|--------|---------------|------------|
| `vk.com` | Major Russian social network | `https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a766b2e636f6d` |
| `yandex.ru` | Russian search/services | `https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a79616e6465782e7275` |
| `ok.ru` | Russian social network | `https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a6f6b2e7275` |

#### Tier 2: International CDNs
Less commonly used for proxy fronting.

| Domain | Why It's Good | Proxy Link |
|--------|---------------|------------|
| `cdn.jsdelivr.net` | Used by many websites | `https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a63646e2e6a7364656c6976722e6e6574` |
| `storage.googleapis.com` | Google Cloud storage | `https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a73746f726167652e676f6f676c65617069732e636f6d` |

#### Tier 3: Common (May Be Fingerprinted)

| Domain | Risk Level | Proxy Link |
|--------|------------|------------|
| `www.microsoft.com` | Medium (current) | `https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a7777772e6d6963726f736f66742e636f6d` |
| `www.google.com` | High (common target) | `https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a7777772e676f6f676c652e636f6d` |
| `cloudflare.com` | High (very common) | `https://t.me/proxy?server=138.2.146.96&port=443&secret=eefe9270abb78607fb38eb6e15bd048d6a636c6f7564666c6172652e636f6d` |

#### Domain Selection Criteria
- Must support TLS 1.3
- High traffic volume in Russia (blends in)
- Not commonly used for proxy fronting
- Business-critical (blocking causes collateral damage)

#### How to Switch Domain
```bash
# Stop current container
./scripts/bastion-setup.sh exec "sudo docker stop mtproxy && sudo docker rm mtproxy"

# Start with new domain (example: vk.com)
./scripts/bastion-setup.sh exec 'sudo docker run -d --name mtproxy --restart always -p 443:3128 nineseconds/mtg:2 simple-run -d -t 30s 0.0.0.0:3128 "eefe9270abb78607fb38eb6e15bd048d6a766b2e636f6d"'
```

---

### 2. Anti-Replay Protection

Anti-replay prevents DPI from detecting MTProxy via replay attacks (capturing and replaying handshake data).

#### How It Works
1. MTProxy stores fingerprint of each connection's first bytes in a bloom filter cache
2. If same fingerprint seen again, connection is rejected or forwarded to fronting domain
3. DPI probe sees normal HTTPS response instead of MTProxy behavior

#### Enable Anti-Replay (Requires Config File Mode)

Create config file on instance:
```bash
./scripts/bastion-setup.sh exec 'cat > /home/ubuntu/mtg-config.toml << EOF
debug = true
secret = "eefe9270abb78607fb38eb6e15bd048d6a7777772e6d6963726f736f66742e636f6d"
bind-to = "0.0.0.0:3128"

[defense.anti-replay]
enabled = true
max-size = "1mib"
error-rate = 0.001
EOF'
```

Start mtg with config file:
```bash
./scripts/bastion-setup.sh exec "sudo docker stop mtproxy && sudo docker rm mtproxy"
./scripts/bastion-setup.sh exec 'sudo docker run -d --name mtproxy --restart always -p 443:3128 -v /home/ubuntu/mtg-config.toml:/config.toml:ro nineseconds/mtg:2 run /config.toml'
```

#### Effectiveness
| Attack Type | Protection |
|-------------|------------|
| Replay attacks | High |
| Active probing with captured data | High |
| Fresh probing (new connections) | None |
| Traffic pattern analysis | None |
| TLS fingerprinting | None |

---

### 3. IP Blocklist (Block Known Scanners)

Block connections from known scanner/attacker IPs using FireHOL lists.

#### Enable Blocklist (Config File Mode)

```toml
[defense.blocklist]
enabled = true
download-concurrency = 2
urls = [
    "https://iplists.firehol.org/files/firehol_level1.netset"
]
update-each = "24h"
```

#### Full Config with Anti-Replay + Blocklist

```bash
./scripts/bastion-setup.sh exec 'cat > /home/ubuntu/mtg-config.toml << EOF
debug = true
secret = "eefe9270abb78607fb38eb6e15bd048d6a7777772e6d6963726f736f66742e636f6d"
bind-to = "0.0.0.0:3128"
domain-fronting-port = 443
tolerate-time-skewness = "5s"

[defense.anti-replay]
enabled = true
max-size = "1mib"
error-rate = 0.001

[defense.blocklist]
enabled = true
download-concurrency = 2
urls = [
    "https://iplists.firehol.org/files/firehol_level1.netset"
]
update-each = "24h"

[network.timeout]
tcp = "30s"
http = "30s"
idle = "1m"
EOF'
```

---

### 4. MTProxy Implementations Comparison

| Feature | mtg v2 (current) | Official MTProxy |
|---------|------------------|------------------|
| Fake-TLS (`ee` prefix) | Yes | Yes |
| Random Padding (`dd` prefix) | No | Yes |
| Anti-Replay Cache | Yes | No |
| IP Blocklist | Yes | No |
| Config File | Yes | No |
| Proxy Chaining (SOCKS5) | Yes | No |
| Multiple Secrets | No | Yes |

#### Official MTProxy Random Padding (`dd` prefix)

The official Telegram MTProxy supports random padding with `dd` prefix:
- Format: `dd` + 32-char-hex-secret
- Adds random bytes to packets to obscure packet sizes
- Different from fake-TLS (`ee` prefix)
- **Cannot be combined with fake-TLS** - they are mutually exclusive modes

**Note:** mtg v2 does not support `dd` padding, only fake-TLS (`ee`).

#### How to Use Random Padding (Official MTProxy)

If fake-TLS is being detected, try switching to official MTProxy with `dd` padding:

```bash
# Stop current mtg container
./scripts/bastion-setup.sh exec "sudo docker stop mtproxy && sudo docker rm mtproxy"

# Generate dd-prefixed secret
# dd + base_secret (no domain encoding needed)
# Example: ddfe9270abb78607fb38eb6e15bd048d6a

# Run official MTProxy with dd padding
./scripts/bastion-setup.sh exec 'sudo docker run -d --name mtproxy --restart always \
  -p 443:443 \
  -v /home/ubuntu/proxy-secret:/data/proxy-secret:ro \
  -v /home/ubuntu/proxy-multi.conf:/data/proxy-multi.conf:ro \
  telegrammessenger/proxy:latest'
```

**Setup steps for official MTProxy:**
```bash
# 1. Download proxy secret
./scripts/bastion-setup.sh exec "curl -s https://core.telegram.org/getProxySecret -o /home/ubuntu/proxy-secret"

# 2. Download proxy config (update daily via cron)
./scripts/bastion-setup.sh exec "curl -s https://core.telegram.org/getProxyConfig -o /home/ubuntu/proxy-multi.conf"

# 3. Run official MTProxy
./scripts/bastion-setup.sh exec 'sudo docker run -d --name mtproxy --restart always \
  -p 443:443 \
  -v /home/ubuntu/proxy-secret:/data/proxy-secret:ro \
  -v /home/ubuntu/proxy-multi.conf:/data/proxy-multi.conf:ro \
  -e SECRET=ddfe9270abb78607fb38eb6e15bd048d6a \
  telegrammessenger/proxy:latest'
```

**Telegram proxy link with dd padding:**
```
https://t.me/proxy?server=138.2.146.96&port=443&secret=ddfe9270abb78607fb38eb6e15bd048d6a
```

#### Comparison: `dd` vs `ee` Modes

| Feature | `dd` (Random Padding) | `ee` (Fake-TLS) |
|---------|----------------------|-----------------|
| Implementation | Official MTProxy | mtg v2, others |
| Obfuscation | Packet size randomization | TLS handshake disguise |
| Domain fronting | No | Yes |
| Detection resistance | Medium | Medium-High |
| Use case | When fake-TLS is fingerprinted | Default recommendation |

---

### 5. Alternative Solutions (If MTProxy Fails)

If Russian DPI blocks MTProxy entirely, these alternatives provide better evasion:

| Solution | DPI Evasion | Telegram Native | Battery Impact | Complexity |
|----------|-------------|-----------------|----------------|------------|
| MTProxy + Fake-TLS | Medium | Yes | Minimal | Low |
| Shadowsocks + Cloak | Very High | No (app needed) | Medium | Medium |
| Xray + VLESS + Reality | Very High | No (app needed) | Medium | High |
| WireGuard VPN | Medium | No (VPN) | Low-Medium | Low |

#### WireGuard Setup (For Calls + Full Traffic)
WireGuard can be added to the same instance for Telegram calls and other apps.
- Port: 51820 UDP
- Supports voice/video calls (UDP)
- Higher battery usage than MTProxy

---

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

# Calculate new secret (example for vk.com)
./scripts/bastion-setup.sh exec 'DOMAIN="vk.com"; DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d "\n"); echo "eefe9270abb78607fb38eb6e15bd048d6a$DOMAIN_HEX"'

# Start with new secret
./scripts/bastion-setup.sh exec 'sudo docker run -d --name mtproxy --restart always -p 443:3128 nineseconds/mtg:2 simple-run -d -t 30s 0.0.0.0:3128 "<SECRET_FROM_ABOVE>"'
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

## OCI Free Tier Limits

| Resource | Limit | Current Usage |
|----------|-------|---------------|
| AMD Compute (VM.Standard.E2.1.Micro) | 2 instances | 1 |
| Boot Volume | 200 GB | 47 GB |
| Reserved Public IP | Included | 1 |
| Outbound Data | 10 TB/month | ~minimal |

**Free tier has no time limit** - resources remain free indefinitely.

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
1. Try different fake-TLS domains (see domain recommendations above)
2. Try Russian domains (`vk.com`, `yandex.ru`) - less likely to be fingerprinted
3. Enable anti-replay protection (config file mode)
4. Enable IP blocklist to block scanners
5. If all fails, consider Shadowsocks or WireGuard
