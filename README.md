# Hermes Init

Run [Hermes Agent](https://github.com/NousResearch/hermes-agent) in containers using Podman on WSL.

## Features

- Preconfigured with DeepSeek V4 Flash as main model
- Xiaomi MiMo v2.5 for vision auxiliary tasks
- Feishu/Lark gateway support
- lark-cli preinstalled
- Dashboard enabled by default
- Multiple instance support via profiles
- Configurable resource limits (CPU, memory)
- Per-profile environment variables
- Per-profile SOUL.md initialization
- All config via environment variables (no config.yaml needed)

## Requirements

- [Podman](https://podman.io/) installed
- [yq](https://github.com/mikefarah/yq) installed

## Quick Start

```bash
# 1. Copy example files
cp hermes.env.example hermes.env
cp hermes-profiles.yaml.example hermes-profiles.yaml

# 2. Edit hermes.env with your API keys
vim hermes.env

# 3. Edit hermes-profiles.yaml with your instance configs
vim hermes-profiles.yaml

# 4. Create SOUL.md files (optional)
vim souls/default.md

# 5. Build the custom image
./run-hermes.sh build

# 6. Setup an instance
./run-hermes.sh setup hermes-1

# 7. Start the instance
./run-hermes.sh start hermes-1

# 8. Check status
./run-hermes.sh list
```

## Commands

| Command | Description |
|---------|-------------|
| `build` | Build custom image with lark-cli |
| `setup <name>` | First-time interactive setup (copies SOUL.md if specified) |
| `start <name>` | Start gateway + dashboard |
| `stop <name>` | Stop a running container |
| `chat <name>` | Open interactive CLI |
| `logs <name>` | Tail container logs |
| `update <name>` | Pull latest image + recreate |
| `list` | Show all profiles and status |

## Configuration

All configuration is via environment variables in `hermes.env`. No `config.yaml` needed.

### hermes.env

```bash
# Main model - DeepSeek V4 Flash
HERMES_INFERENCE_PROVIDER=deepseek
HERMES_INFERENCE_MODEL=deepseek-v4-flash
DEEPSEEK_API_KEY=your-deepseek-key

# Auxiliary vision model - Xiaomi MiMo v2.5
AUXILIARY_VISION_PROVIDER=xiaomi
AUXILIARY_VISION_MODEL=mimo-v2.5
AUXILIARY_VISION_BASE_URL=https://token-plan-sgp.xiaomimimo.com/v1
AUXILIARY_VISION_API_KEY=your-xiaomi-key

# Feishu/Lark gateway
FEISHU_APP_ID=your-feishu-app-id
FEISHU_APP_SECRET=your-feishu-app-secret
FEISHU_DOMAIN=lark
FEISHU_CONNECTION_MODE=websocket

# Terminal backend
TERMINAL_ENV=local
```

### hermes-profiles.yaml

Instance definitions with per-profile env vars and SOUL:

```yaml
defaults:
  cpu: "1"
  memory: "1g"
  disk: "5g"

profiles:
  hermes-1:
    gateway_port: 8642
    dashboard_port: 9119
    soul: ./souls/default.md
    env:
      FEISHU_APP_ID: your-feishu-app-id
      FEISHU_APP_SECRET: your-feishu-app-secret
  hermes-2:
    gateway_port: 8643
    dashboard_port: 9120
    soul: ./souls/default.md
    env:
      FEISHU_APP_ID: your-feishu-app-id
      FEISHU_APP_SECRET: your-feishu-app-secret
```

- Data directories default to `~/dockered-hermes/.<profile-name>`
- Profile env vars override shared `hermes.env`
- `gateway_port` and `dashboard_port` are host port mappings (container internal ports are always 8642 and 9119)
- `soul` is optional — if specified, the file is copied to `SOUL.md` in the data directory during setup

### SOUL.md

The `soul` field in `hermes-profiles.yaml` points to a file that becomes the agent's identity (`/opt/data/SOUL.md` inside the container). This is written once during `setup`, not on every `start`.

Example `souls/default.md`:

```markdown
You are a helpful AI assistant.

Be concise and professional in your responses.
```

## Environment Variables Reference

### Main Model

| Variable | Description |
|----------|-------------|
| `HERMES_INFERENCE_PROVIDER` | Provider name (e.g., `deepseek`) |
| `HERMES_INFERENCE_MODEL` | Model name (e.g., `deepseek-v4-flash`) |
| `DEEPSEEK_API_KEY` | DeepSeek API key |
| `DEEPSEEK_BASE_URL` | Override DeepSeek base URL (optional) |

### Auxiliary Vision Model

| Variable | Description |
|----------|-------------|
| `AUXILIARY_VISION_PROVIDER` | Provider name (e.g., `xiaomi`) |
| `AUXILIARY_VISION_MODEL` | Model name (e.g., `mimo-v2.5`) |
| `AUXILIARY_VISION_BASE_URL` | Custom endpoint URL |
| `AUXILIARY_VISION_API_KEY` | API key for the endpoint |

### Feishu/Lark Gateway

| Variable | Description |
|----------|-------------|
| `FEISHU_APP_ID` | Feishu/Lark bot App ID |
| `FEISHU_APP_SECRET` | Feishu/Lark bot App Secret |
| `FEISHU_DOMAIN` | `feishu` (China) or `lark` (international) |
| `FEISHU_CONNECTION_MODE` | `websocket` (recommended) or `webhook` |

### Terminal

| Variable | Description |
|----------|-------------|
| `TERMINAL_ENV` | Backend: `local`, `docker`, `ssh`, etc. |

## Accessing Services

- **Gateway API:** `http://localhost:<gateway_port>`
- **Dashboard:** `http://localhost:<dashboard_port>`

## License

MIT
