
# AI Assistant

AI-native onboarding and assistance layer for openSUSE.

## Project Status

- **Architecture**: [Architecture v1.0](docs/ARCHITECTURE.md)
- **Mentors**: @rudrakshkarpe @satyampsoni

## Quick Start
```bash
git clone https://github.com/YOUR_USERNAME/ai-assistant.git
cd ai-assistant

uv venv --python 3.13
source .venv/bin/activate

uv pip install -e ".[dev]"

./scripts/download_models.sh
./scripts/build_podman.sh

suse-ai
```

## Contributing

Install pre-commit hooks before committing:
```bash
pre-commit install
```
