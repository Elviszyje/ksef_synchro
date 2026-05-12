#!/usr/bin/env bash
# deploy.sh — pobiera najnowszy commit i przebudowuje stos aplikacji
# Użycie: ./deploy.sh [--no-cache]
set -euo pipefail

# ── kolory ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}▶  $*${NC}"; }
ok()   { echo -e "${GREEN}✓  $*${NC}"; }
warn() { echo -e "${YELLOW}⚠  $*${NC}"; }
fail() { echo -e "${RED}✗  $*${NC}"; exit 1; }

# ── katalog roboczy = katalog skryptu ─────────────────────────────────────────
cd "$(dirname "$(realpath "$0")")"

# ── argumenty ─────────────────────────────────────────────────────────────────
NO_CACHE=""
[[ "${1:-}" == "--no-cache" ]] && { NO_CACHE="--no-cache"; warn "Tryb --no-cache — pełna przebudowa"; }

# ── sprawdź dostępność docker compose ─────────────────────────────────────────
if docker compose version &>/dev/null; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    fail "Nie znaleziono 'docker compose' ani 'docker-compose'"
fi

# ── git pull ──────────────────────────────────────────────────────────────────
step "Git pull"
if ! git diff --quiet || ! git diff --cached --quiet; then
    warn "Są niezapisane zmiany lokalne (git stash jeśli chcesz je zachować)"
fi
git pull
COMMIT=$(git rev-parse --short HEAD)
BRANCH=$(git branch --show-current)
ok "Gałąź: ${BRANCH} | Commit: ${COMMIT}"

# ── build tylko kontenerów aplikacji (db i redis bez zmian) ───────────────────
step "Build: web, celery, celery-beat"
$DC build $NO_CACHE web celery celery-beat

# ── restart kontenerów aplikacji z nowym obrazem ─────────────────────────────
step "Restart kontenerów aplikacji"
$DC up -d --no-deps web celery celery-beat

# ── poczekaj chwilę i sprawdź stan ───────────────────────────────────────────
step "Sprawdzanie stanu (czekam 8s na starty)"
sleep 8
$DC ps web celery celery-beat

# ── szybki test odpowiedzi web ────────────────────────────────────────────────
step "Ping web (health check)"
WEB_PORT=$(grep -E '^\s+-\s+"?[0-9]+:8000"?' docker-compose.yml | grep -oE '[0-9]+:8000' | cut -d: -f1 | head -1)
WEB_PORT="${WEB_PORT:-8080}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${WEB_PORT}/accounts/login/" --max-time 10 || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|302)$ ]]; then
    ok "Web odpowiada — HTTP ${HTTP_CODE} (port ${WEB_PORT})"
else
    warn "Web zwrócił HTTP ${HTTP_CODE} — sprawdź logi:"
    echo ""
    $DC logs --tail=30 web
    exit 1
fi

echo ""
ok "Deploy zakończony — commit ${COMMIT}"
