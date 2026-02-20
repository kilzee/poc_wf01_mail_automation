#!/usr/bin/env bash
# =============================================================================
# scan_secrets.sh — Scanner les fichiers avant commit pour détecter des secrets
# =============================================================================
# Usage:
#   ./scripts/scan_secrets.sh          # Scanner tout le projet
#   ./scripts/scan_secrets.sh [path]   # Scanner un fichier ou répertoire
#
# Peut être utilisé comme pre-commit hook:
#   cp scripts/scan_secrets.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCAN_PATH="${1:-$PROJECT_ROOT}"

FOUND_SECRETS=0
WARNINGS=0

echo "🔍 Scan secrets — POC Gmail Automation"
echo "========================================"
echo "📁 Chemin: $SCAN_PATH"
echo ""

# Fichiers à toujours ignorer
IGNORE_PATTERNS=(
  ".git/"
  "node_modules/"
  ".venv/"
  "*.pyc"
  "*.log"
  ".env.example"
  "scan_secrets.sh"
  "docs/"
)

# Construire les options --exclude pour grep
GREP_EXCLUDES=""
for pat in "${IGNORE_PATTERNS[@]}"; do
  GREP_EXCLUDES="$GREP_EXCLUDES --exclude-dir=${pat%/} --exclude=$pat"
done

# --- Patterns de secrets à détecter ---
declare -A SECRET_PATTERNS

SECRET_PATTERNS["Anthropic API Key"]="sk-ant-[a-zA-Z0-9_-]{20,}"
SECRET_PATTERNS["OpenAI API Key"]="sk-[a-zA-Z0-9]{48}"
SECRET_PATTERNS["Telegram Bot Token"]="[0-9]{8,10}:[a-zA-Z0-9_-]{35}"
SECRET_PATTERNS["Google OAuth Client Secret"]="GOCSPX-[a-zA-Z0-9_-]{28}"
SECRET_PATTERNS["Google Client ID"]="[0-9]+-[a-zA-Z0-9_]+\.apps\.googleusercontent\.com"
SECRET_PATTERNS["AWS Access Key"]="AKIA[0-9A-Z]{16}"
SECRET_PATTERNS["AWS Secret"]="[aA]ws[_-]?[sS]ecret[_-]?[aA]ccess[_-]?[kK]ey.{0,30}[a-zA-Z0-9/+=]{40}"
SECRET_PATTERNS["Private Key Header"]="-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"
SECRET_PATTERNS["Basic Auth (base64)"]="Authorization: Basic [a-zA-Z0-9+/=]{20,}"
SECRET_PATTERNS["Password in URL"]="://[^:@]+:[^@]+@"
SECRET_PATTERNS["Hardcoded password var"]="(password|passwd|pwd|secret|token)\s*=\s*['\"][^'\"]{8,}['\"]"

# Patterns à signaler comme warnings (faux positifs possibles)
declare -A WARNING_PATTERNS
WARNING_PATTERNS["CHANGE_ME placeholder"]="CHANGE_ME"
WARNING_PATTERNS["TODO credential"]="(TODO|FIXME).*(key|token|secret|password|credential)"

check_pattern() {
  local LABEL="$1"
  local PATTERN="$2"
  local IS_WARNING="${3:-false}"

  # Utiliser grep -r avec les exclusions
  MATCHES=$(grep -r --include="*.json" --include="*.yml" --include="*.yaml" \
    --include="*.sh" --include="*.py" --include="*.js" --include="*.ts" \
    --include="*.env" --include="*.txt" \
    -l -E "$PATTERN" \
    --exclude-dir=".git" \
    --exclude-dir="node_modules" \
    --exclude="scan_secrets.sh" \
    "$SCAN_PATH" 2>/dev/null || true)

  if [[ -n "$MATCHES" ]]; then
    if [[ "$IS_WARNING" == "true" ]]; then
      echo "  ⚠️  $LABEL"
      WARNINGS=$((WARNINGS + 1))
    else
      echo "  🚨 $LABEL"
      FOUND_SECRETS=$((FOUND_SECRETS + 1))
    fi

    while IFS= read -r FILE; do
      # Obtenir les lignes correspondantes (masquées)
      LINES=$(grep -n -E "$PATTERN" "$FILE" 2>/dev/null \
        | sed 's/\(.\{50\}\).*/\1.../' \
        | head -3 || true)
      echo "     📄 $FILE"
      while IFS= read -r LINE; do
        echo "        $LINE"
      done <<< "$LINES"
    done <<< "$MATCHES"
    echo ""
  fi
}

# --- Vérifier les fichiers .env commitables ---
echo "📄 Vérification .env files:"
ENV_FILES_COMMITTED=$(git -C "$PROJECT_ROOT" ls-files "*.env" ".env" 2>/dev/null || true)
if [[ -n "$ENV_FILES_COMMITTED" ]]; then
  echo "  🚨 Fichiers .env trackés par Git:"
  while IFS= read -r f; do
    echo "     ❌ $f"
    FOUND_SECRETS=$((FOUND_SECRETS + 1))
  done <<< "$ENV_FILES_COMMITTED"
else
  echo "  ✅ Aucun fichier .env tracké par Git"
fi
echo ""

# --- Scanner les patterns de secrets ---
echo "🔑 Scan des patterns secrets:"
for LABEL in "${!SECRET_PATTERNS[@]}"; do
  check_pattern "$LABEL" "${SECRET_PATTERNS[$LABEL]}" "false"
done

# --- Scanner les patterns de warnings ---
echo "⚠️  Patterns à vérifier (warnings):"
for LABEL in "${!WARNING_PATTERNS[@]}"; do
  check_pattern "$LABEL" "${WARNING_PATTERNS[$LABEL]}" "true"
done

# --- Vérifier .gitignore ---
echo "📋 Vérification .gitignore:"
GITIGNORE="$PROJECT_ROOT/.gitignore"
REQUIRED_IGNORES=(".env" "*.pem" "*.key" "n8n_data/" "postgres_data/" "credentials.json" "token.json")
for PATTERN in "${REQUIRED_IGNORES[@]}"; do
  if grep -qF "$PATTERN" "$GITIGNORE" 2>/dev/null; then
    echo "  ✅ $PATTERN ignoré"
  else
    echo "  ⚠️  $PATTERN non présent dans .gitignore"
    WARNINGS=$((WARNINGS + 1))
  fi
done
echo ""

# --- Rapport final ---
echo "========================================"
if [[ $FOUND_SECRETS -gt 0 ]]; then
  echo "🚨 ATTENTION: $FOUND_SECRETS secret(s) potentiel(s) détecté(s)"
  echo ""
  echo "Actions à effectuer AVANT de committer:"
  echo "  1. Supprimer les secrets des fichiers"
  echo "  2. Utiliser .env.example (sans valeurs réelles)"
  echo "  3. Si déjà commité: git filter-branch ou BFG Repo Cleaner"
  echo "  4. Révoquer immédiatement les clés exposées"
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo "⚠️  $WARNINGS warning(s) — vérification manuelle recommandée"
  echo "✅ Aucun secret détecté automatiquement"
  exit 0
else
  echo "✅ Aucun secret détecté — commit safe"
  exit 0
fi
