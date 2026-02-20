#!/usr/bin/env bash
# =============================================================================
# export_workflows.sh — Exporter les workflows n8n via l'API REST
# =============================================================================
# Usage: ./scripts/export_workflows.sh [workflow_id]
#   Sans argument : exporter tous les workflows
#   Avec workflow_id : exporter un workflow spécifique
#
# Prérequis: .env configuré, n8n démarré
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

# Vérifier que n8n est accessible
echo "🔍 Vérification de n8n à $N8N_URL..."
if ! curl -sf -H "$AUTH_HEADER" "$N8N_URL/rest/active-workflows" > /dev/null 2>&1; then
  echo "❌ n8n inaccessible à $N8N_URL"
  echo "   Vérifier que n8n est démarré: docker-compose ps"
  exit 1
fi
echo "✅ n8n accessible"

mkdir -p "$WORKFLOWS_DIR"

if [[ -n "${1:-}" ]]; then
  # Exporter un workflow spécifique
  WF_ID="$1"
  echo "📤 Export workflow ID: $WF_ID..."

  RESPONSE=$(curl -sf -H "$AUTH_HEADER" "$N8N_URL/rest/workflows/$WF_ID")
  WF_NAME=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name','unknown').replace(' ','_').replace('/','_'))" 2>/dev/null || echo "workflow_$WF_ID")
  OUTPUT_FILE="$WORKFLOWS_DIR/${WF_NAME}.json"

  echo "$RESPONSE" | python3 -m json.tool > "$OUTPUT_FILE"
  echo "✅ Exporté: $OUTPUT_FILE"

else
  # Exporter tous les workflows
  echo "📤 Export de tous les workflows..."

  WORKFLOWS=$(curl -sf -H "$AUTH_HEADER" "$N8N_URL/rest/workflows" | python3 -c "
import sys, json
data = json.load(sys.stdin)
wfs = data.get('data', data) if isinstance(data, dict) else data
for wf in wfs:
    print(f\"{wf['id']}|{wf['name']}\")
")

  COUNT=0
  while IFS='|' read -r WF_ID WF_NAME; do
    [[ -z "$WF_ID" ]] && continue

    # Sanitize filename
    SAFE_NAME=$(echo "$WF_NAME" | tr ' /' '__' | tr -d '()[]{}:*?<>|\\')
    OUTPUT_FILE="$WORKFLOWS_DIR/${SAFE_NAME}.json"

    echo "  📄 Export: $WF_NAME (ID: $WF_ID)..."
    curl -sf -H "$AUTH_HEADER" "$N8N_URL/rest/workflows/$WF_ID" \
      | python3 -m json.tool > "$OUTPUT_FILE"

    COUNT=$((COUNT + 1))
  done <<< "$WORKFLOWS"

  echo ""
  echo "✅ $COUNT workflow(s) exporté(s) dans $WORKFLOWS_DIR/"
fi

# Valider les JSON exportés
echo ""
echo "🔍 Validation JSON des fichiers exportés..."
ERRORS=0
for f in "$WORKFLOWS_DIR"/*.json; do
  [[ "$f" == *"init_db.sql" ]] && continue
  if python3 -m json.tool "$f" > /dev/null 2>&1; then
    echo "  ✅ $f"
  else
    echo "  ❌ JSON invalide: $f"
    ERRORS=$((ERRORS + 1))
  fi
done

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "⚠️  $ERRORS fichier(s) avec JSON invalide"
  exit 1
fi

echo ""
echo "✅ Export terminé avec succès"
