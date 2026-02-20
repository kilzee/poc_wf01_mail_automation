#!/usr/bin/env bash
# =============================================================================
# import_workflows.sh — Importer les workflows n8n depuis les fichiers JSON
# =============================================================================
# Usage: ./scripts/import_workflows.sh [fichier.json]
#   Sans argument : importer tous les fichiers dans workflows/
#   Avec fichier : importer un fichier spécifique
#
# Ordre d'import recommandé:
#   1. WF_07_gmail_actions.json
#   2. WF_06_telegram_webhook.json
#   3. WF_01_daily_ingest.json
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$PROJECT_ROOT/workflows"

# Charger .env si présent
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

N8N_URL="${N8N_PROTOCOL:-http}://${N8N_HOST:-localhost}:${N8N_PORT:-5678}"
N8N_USER="${N8N_BASIC_AUTH_USER:-admin}"
N8N_PASS="${N8N_BASIC_AUTH_PASSWORD:-}"

if [[ -z "$N8N_PASS" ]]; then
  echo "❌ Erreur: N8N_BASIC_AUTH_PASSWORD non défini dans .env"
  exit 1
fi

AUTH_HEADER="Authorization: Basic $(echo -n "${N8N_USER}:${N8N_PASS}" | base64)"
CONTENT_TYPE="Content-Type: application/json"

# Vérifier n8n
echo "🔍 Vérification de n8n à $N8N_URL..."
if ! curl -sf -H "$AUTH_HEADER" "$N8N_URL/rest/active-workflows" > /dev/null 2>&1; then
  echo "❌ n8n inaccessible. Vérifier: docker-compose ps"
  exit 1
fi
echo "✅ n8n accessible"

import_workflow() {
  local FILE="$1"
  local WF_NAME

  # Vérifier que c'est un fichier JSON valide
  if ! python3 -m json.tool "$FILE" > /dev/null 2>&1; then
    echo "  ❌ JSON invalide: $FILE (ignoré)"
    return 1
  fi

  WF_NAME=$(python3 -c "import sys,json; f=open('$FILE'); d=json.load(f); print(d.get('name','Unknown'))" 2>/dev/null || echo "Unknown")
  echo "  📥 Import: $WF_NAME..."

  # Récupérer l'ID si présent dans le fichier
  WF_ID=$(python3 -c "import sys,json; f=open('$FILE'); d=json.load(f); print(d.get('id',''))" 2>/dev/null || echo "")

  # Préparer le payload (supprimer les champs non nécessaires à l'import)
  PAYLOAD=$(python3 -c "
import json, sys
with open('$FILE') as f:
    d = json.load(f)
# Garder seulement les champs nécessaires
keep = ['name', 'nodes', 'connections', 'settings', 'staticData', 'pinData', 'meta']
payload = {k: v for k, v in d.items() if k in keep}
print(json.dumps(payload))
")

  # Vérifier si le workflow existe déjà (par nom)
  EXISTING_IDS=$(curl -sf -H "$AUTH_HEADER" "$N8N_URL/rest/workflows" | python3 -c "
import sys, json
data = json.load(sys.stdin)
wfs = data.get('data', data) if isinstance(data, dict) else data
name = '$WF_NAME'
ids = [str(wf['id']) for wf in wfs if wf.get('name') == name]
print('\n'.join(ids))
" 2>/dev/null || echo "")

  if [[ -n "$EXISTING_IDS" ]]; then
    EXISTING_ID=$(echo "$EXISTING_IDS" | head -1)
    echo "    ⚠️  Workflow '$WF_NAME' existe déjà (ID: $EXISTING_ID)"
    read -rp "    Écraser ? [y/N] " CONFIRM
    if [[ "$CONFIRM" =~ ^[yY]$ ]]; then
      RESPONSE=$(curl -sf -X PUT \
        -H "$AUTH_HEADER" \
        -H "$CONTENT_TYPE" \
        -d "$PAYLOAD" \
        "$N8N_URL/rest/workflows/$EXISTING_ID")
      echo "    ✅ Mis à jour (ID: $EXISTING_ID)"
    else
      echo "    ⏭️  Ignoré"
      return 0
    fi
  else
    RESPONSE=$(curl -sf -X POST \
      -H "$AUTH_HEADER" \
      -H "$CONTENT_TYPE" \
      -d "$PAYLOAD" \
      "$N8N_URL/rest/workflows")
    NEW_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','?'))" 2>/dev/null || echo "?")
    echo "    ✅ Créé (ID: $NEW_ID)"
  fi
}

# Ordre d'import
IMPORT_ORDER=(
  "WF_07_gmail_actions.json"
  "WF_06_telegram_webhook.json"
  "WF_01_daily_ingest.json"
)

if [[ -n "${1:-}" ]]; then
  # Importer un fichier spécifique
  echo "📥 Import: $1"
  import_workflow "$1"
else
  # Importer dans l'ordre recommandé
  echo "📥 Import des workflows dans l'ordre recommandé..."
  echo ""

  IMPORTED=0
  for WF_FILE in "${IMPORT_ORDER[@]}"; do
    FULL_PATH="$WORKFLOWS_DIR/$WF_FILE"
    if [[ -f "$FULL_PATH" ]]; then
      import_workflow "$FULL_PATH"
      IMPORTED=$((IMPORTED + 1))
    else
      echo "  ⚠️  Fichier non trouvé: $FULL_PATH"
    fi
  done

  # Importer les autres fichiers non dans la liste ordonnée
  for f in "$WORKFLOWS_DIR"/*.json; do
    BASENAME=$(basename "$f")
    if [[ "$BASENAME" == "init_db.sql" ]]; then
      continue
    fi
    if [[ ! " ${IMPORT_ORDER[*]} " =~ " ${BASENAME} " ]]; then
      echo "  📄 Import additionnel: $BASENAME"
      import_workflow "$f"
      IMPORTED=$((IMPORTED + 1))
    fi
  done

  echo ""
  echo "✅ $IMPORTED workflow(s) importé(s)"
  echo ""
  echo "⚠️  N'oubliez pas de :"
  echo "   1. Lier les credentials (Gmail, Postgres, Anthropic) dans chaque workflow"
  echo "   2. Activer WF_06 (Telegram Webhook) en premier"
  echo "   3. Tester WF_01 en mode manuel avant d'activer le cron"
fi
