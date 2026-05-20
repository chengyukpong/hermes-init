# Hermes Init

Run [Hermes Agent](https://github.com/NousResearch/hermes-agent) in containers using Podman on WSL.

## Features

- Preconfigured with DeepSeek V4 Flash as main model
- Xiaomi MiMo v2.5 for vision auxiliary tasks
- lark-cli preinstalled
- Dashboard enabled by default
- Multiple instance support via profiles
- Configurable resource limits (CPU, memory)
- Per-profile environment variables

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

# 4. Build the custom image
./run-hermes.sh build

# 5. Setup an instance
./run-hermes.sh setup hermes-1

# 6. Start the instance
./run-hermes.sh start hermes-1

# 7. Check status
./run-hermes.sh list
```

## Commands

| Command | Description |
|---------|-------------|
| `build` | Build custom image with lark-cli |
| `setup <name>` | First-time interactive setup |
| `start <name>` | Start gateway + dashboard |
| `stop <name>` | Stop a running container |
| `chat <name>` | Open interactive CLI |
| `logs <name>` | Tail container logs |
| `update <name>` | Pull latest image + recreate |
| `list` | Show all profiles and status |

## Configuration

### hermes.env

Shared environment variables (API keys):

```
DEEPSEEK_API_KEY=your-deepseek-key
XIAOMI_API_KEY=your-xiaomi-key
```

### hermes-profiles.yaml

Instance definitions:

```yaml
defaults:
  cpu: "1"
  memory: "1g"
  disk: "5g"

profiles:
  hermes-1:
    gateway_port: 8642
    dashboard_port: 9119
    env:
      LARK_APP_ID: your-lark-app-id
      LARK_APP_SECRET: your-lark-app-secret
```

- Data directories default to `~/dockered-hermes/.<profile-name>`
- Profile env vars override shared hermes.env

## Accessing Services

- **Gateway API:** `http://localhost:<gateway_port>`
- **Dashboard:** `http://localhost:<dashboard_port>`

## License

MIT
