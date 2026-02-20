#!/usr/bin/env bash
# =============================================================================
# validate_json.sh — Valider tous les fichiers JSON du projet
# =============================================================================
# Usage: ./scripts/validate_json.sh
# Vérifie:
#   - Syntaxe JSON valide
#   - Structure minimale des workflows n8n
#   - Schéma analysis.json
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ERRORS=0
WARNINGS=0
CHECKED=0

echo "🔍 Validation JSON — POC Gmail Automation"
echo "=========================================="
echo ""

# --- Fonction de validation JSON syntaxique ---
validate_json_syntax() {
  local FILE="$1"
  if python3 -m json.tool "$FILE" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# --- Fonction de validation structure workflow n8n ---
validate_n8n_workflow() {
  local FILE="$1"
  python3 - "$FILE" << 'PYEOF'
import sys, json

filepath = sys.argv[1]
with open(filepath) as f:
    try:
        d = json.load(f)
    except json.JSONDecodeError as e:
        print(f"  ❌ JSON invalide: {e}")
        sys.exit(1)

errors = []
warnings = []

# Champs obligatoires
for field in ['name', 'nodes', 'connections']:
    if field not in d:
        errors.append(f"Champ obligatoire manquant: '{field}'")

# Vérifier les nodes
nodes = d.get('nodes', [])
if not isinstance(nodes, list) or len(nodes) == 0:
    warnings.append("Aucun nœud dans le workflow")
else:
    for i, node in enumerate(nodes):
        for nf in ['id', 'name', 'type', 'position']:
            if nf not in node:
                warnings.append(f"Nœud [{i}] '{node.get('name','?')}': champ '{nf}' manquant")

# Vérifier connections
connections = d.get('connections', {})
if not isinstance(connections, dict):
    errors.append("'connections' doit être un objet")

# Warnings utiles
if not d.get('settings'):
    warnings.append("Pas de 'settings' défini (executionOrder)")

name = d.get('name', '')
if len(name) < 3:
    warnings.append(f"Nom court: '{name}'")

# Rapport
for e in errors:
    print(f"  ❌ {e}")
for w in warnings:
    print(f"  ⚠️  {w}")

if errors:
    sys.exit(1)
PYEOF
}

# --- Valider les workflows ---
echo "📋 Workflows n8n:"
for f in "$PROJECT_ROOT/workflows/"*.json; do
  [[ -f "$f" ]] || continue
  BASENAME=$(basename "$f")
  echo -n "  $BASENAME ... "
  CHECKED=$((CHECKED + 1))

  if ! validate_json_syntax "$f"; then
    echo "❌ JSON invalide"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  if validate_n8n_workflow "$f" 2>&1; then
    echo "✅"
  else
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# --- Valider les configs ---
echo "⚙️  Configs:"
for f in "$PROJECT_ROOT/config/"*.json; do
  [[ -f "$f" ]] || continue
  BASENAME=$(basename "$f")
  echo -n "  $BASENAME ... "
  CHECKED=$((CHECKED + 1))

  if validate_json_syntax "$f"; then
    echo "✅"
  else
    echo "❌ JSON invalide"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# --- Valider les schémas de prompts ---
echo "📝 Schémas prompts:"
for f in "$PROJECT_ROOT/prompts/"*.json; do
  [[ -f "$f" ]] || continue
  BASENAME=$(basename "$f")
  echo -n "  $BASENAME ... "
  CHECKED=$((CHECKED + 1))

  if validate_json_syntax "$f"; then
    echo "✅"
  else
    echo "❌ JSON invalide"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# --- Rapport final ---
echo "=========================================="
echo "📊 Résultat: $CHECKED fichiers vérifiés"
echo "   ✅ Succès: $((CHECKED - ERRORS))"
echo "   ❌ Erreurs: $ERRORS"
[[ $WARNINGS -gt 0 ]] && echo "   ⚠️  Warnings: $WARNINGS"

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "❌ Validation échouée — corriger les erreurs avant de committer"
  exit 1
else
  echo ""
  echo "✅ Tous les fichiers JSON sont valides"
fi
