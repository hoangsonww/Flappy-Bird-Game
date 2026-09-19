# Documentation

Everything written down about this project, in the order most people need it.

| Guide | What it covers |
|-------|----------------|
| [Development](DEVELOPMENT.md) | Clone → run → contribute. Start here. |
| [Gameplay](GAMEPLAY.md) | Modes, power-ups, combos, weather, medals, achievements — and the numbers behind them. |
| [Architecture](ARCHITECTURE.md) | How the game, the optional backend and the storage layers fit together. |
| [Backend](BACKEND.md) | Running, configuring and operating the API. |
| [API reference](API.md) | Every endpoint, with request and response examples. |
| [Database](DATABASE.md) | Schema, indexes, migrations and the ranking query. |
| [Docker](DOCKER.md) | Compose profiles, images, volumes and the observability stack. |
| [Testing](TESTING.md) | What is tested, how to run it, and how to add more. |
| [CI/CD](CI-CD.md) | The pipeline, and how automatic releases are cut. |
| [Security model](SECURITY-MODEL.md) | Auth, token handling, fair play and the threat model. |
| [Troubleshooting](TROUBLESHOOTING.md) | Symptoms, causes and fixes. |
| [FAQ](FAQ.md) | Short answers to common questions. |
| [Roadmap](ROADMAP.md) | What is planned and what is deliberately out of scope. |
| [Decision records](adr/) | Why the project is built the way it is. |

## The one thing worth repeating

**The game is completely playable without the backend.** Clone, open in Xcode,
press ⌘R. Everything under `backend/` is opt-in: it adds accounts, leaderboards
and cloud saves, and the game detects it automatically when it is running.

```mermaid
flowchart LR
    A[Clone the repo] --> B[Open in Xcode]
    B --> C[⌘R]
    C --> D{Want leaderboards?}
    D -- No --> E[Play — everything saves locally]
    D -- Yes --> F[make up]
    F --> G[Game auto-detects the server]
    G --> H[Accounts · leaderboards · cloud saves]

    style E fill:#d1fae5,stroke:#059669,color:#065f46
    style H fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
```
