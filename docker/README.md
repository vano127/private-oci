# MTProxy Docker Image

Custom MTProxy container with environment-based configuration.

## Features

- Fake-TLS support (auto-generates secret from base secret + domain)
- Anti-replay protection
- IP blocklist (FireHOL)
- Configurable via environment variables

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MTG_SECRET` | Yes | - | Base secret (16 bytes hex) |
| `MTG_DOMAIN` | Yes | - | Fake-TLS domain |
| `MTG_PORT` | No | 3128 | Container bind port |
| `MTG_ANTI_REPLAY` | No | true | Enable anti-replay |
| `MTG_BLOCKLIST` | No | true | Enable IP blocklist |

## Build Locally

```bash
cd docker
docker build -t mtproxy:local .
```

## Run Locally

```bash
docker run -d --name mtproxy \
  -p 443:3128 \
  -e MTG_SECRET=your_16_byte_hex_secret \
  -e MTG_DOMAIN=cdn.jsdelivr.net \
  mtproxy:local
```

## OCIR Setup

### 1. Get Tenancy Namespace

OCI Console → Tenancy Details → Object Storage Namespace

### 2. Create Auth Token

OCI Console → User Settings → Auth Tokens → Generate Token

### 3. GitHub Secrets

Add these secrets to your GitHub repository:

| Secret | Value |
|--------|-------|
| `OCIR_USERNAME` | `<namespace>/oracleidentitycloudservice/<email>` |
| `OCIR_TOKEN` | Auth token from step 2 |
| `OCIR_NAMESPACE` | Tenancy namespace from step 1 |

### 4. Push to Trigger Build

Any push to `docker/` directory triggers the build workflow.

## Deploy with Docker Compose

```bash
# On the OCI instance
cd /home/ubuntu
cp .env.example .env
# Edit .env with your secrets
docker-compose up -d
```

## Watchtower Auto-Updates

The docker-compose.yml includes Watchtower which:
- Checks for new images every 5 minutes
- Automatically pulls and restarts containers
- Only watches mtproxy containers (not system containers)
