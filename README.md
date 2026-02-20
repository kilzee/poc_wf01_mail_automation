# POC Gmail Automation — n8n v2.2.6 OSS

Automatisation de gestion quotidienne d'une boîte Gmail, pilotée et validée via Telegram.

## Fonctionnalités

- **Ingest quotidien** : lecture INBOX, récupération threads, pagination
- **Anti-phishing** : score 0-100, détection lookalike, urgence, reply-to suspect
- **Tri & priorisation** : LLM (Claude) → JSON strict → P1/P2/P3
- **Brouillons** : génération automatique, `{A_CONFIRMER}` si info manquante
- **Pilotage Telegram** : digest quotidien + boutons d'action par email
- **No auto-send** : envoi uniquement après `APPROVE_SEND` humain
- **Mode DEMO/DRY_RUN** : simulation sans action réelle
- **Audit log** : toutes les décisions tracées en base PostgreSQL

## Architecture

```
INBOX Gmail
    ↓
WF_01 Daily Ingest & Analyze
    ├── Normalisation emails
    ├── Score anti-phishing
    ├── LLM Triage (priorité + catégorie)
    ├── LLM Draft (brouillon réponse)
    ├── Création Draft Gmail
    └── Telegram: Digest + Alertes P1
            ↓
WF_06 Telegram Webhook (actions opérateur)
    ├── APPROVE_SEND → send draft
    ├── SAVE_DRAFT_ONLY → garder brouillon
    ├── APPLY_LABEL → labelliser
    ├── ARCHIVE → archiver
    ├── MARK_SPAM → marquer spam
    ├── ESCALATE → escalader
    └── IGNORE → ignorer
```

## Prérequis

- Docker + Docker Compose
- Compte Google Cloud (OAuth2, Gmail API activée)
- Bot Telegram (via BotFather)
- Clé API Anthropic (Claude)

## Démarrage rapide

```bash
# 1. Cloner le repo
git clone <repo-url>
cd workflow_n8n_automation_mail

# 2. Configurer les secrets
cp config/.env.example .env
# Éditer .env avec vos valeurs

# 3. Démarrer
docker-compose up -d

# 4. Accéder à n8n
open http://localhost:5678
# Login: voir N8N_BASIC_AUTH_USER / N8N_BASIC_AUTH_PASSWORD dans .env

# 5. Importer les workflows
./scripts/import_workflows.sh

# 6. Configurer les credentials n8n (Gmail OAuth2, Telegram, Anthropic)
# Voir docs/02_n8n_setup.md

# 7. Activer WF_06 Telegram Webhook en premier
# Puis activer WF_01 Daily Ingest
```

## Documentation

| Fichier | Description |
|---------|-------------|
| [docs/01_google_oauth_setup.md](docs/01_google_oauth_setup.md) | Configuration Google Cloud & OAuth2 |
| [docs/02_n8n_setup.md](docs/02_n8n_setup.md) | Installation n8n & credentials |
| [docs/03_telegram_bot_setup.md](docs/03_telegram_bot_setup.md) | Création bot Telegram & webhook |
| [docs/04_demo_scenario.md](docs/04_demo_scenario.md) | Scénario de démo client |
| [docs/05_architecture.md](docs/05_architecture.md) | Architecture détaillée |

## Structure du repo

```
├── docker-compose.yml
├── .gitignore
├── README.md
├── CHANGELOG.md
├── workflows/
│   ├── init_db.sql                    # Schéma PostgreSQL
│   ├── WF_01_daily_ingest.json        # Workflow principal
│   ├── WF_06_telegram_webhook.json    # Handler actions Telegram
│   └── WF_07_gmail_actions.json       # Exécution Gmail
├── prompts/
│   ├── system_triage.md               # Prompt triage LLM
│   ├── system_draft.md                # Prompt draft LLM
│   └── schema_analysis.json           # Schéma JSON attendu
├── config/
│   ├── .env.example                   # Template secrets
│   ├── scoring_rules.json             # Règles anti-phishing
│   ├── gmail_labels.json              # Mapping labels Gmail
│   └── vip_list.json                  # Liste VIP/prioritaires
├── docs/
└── scripts/
    ├── export_workflows.sh
    ├── import_workflows.sh
    ├── validate_json.sh
    └── scan_secrets.sh
```

## Mode DEMO

Mettre `DEMO_MODE=true` dans `.env` (défaut).
En mode DEMO : aucun envoi, aucun archivage, aucune modification Gmail réelle.
Toutes les actions sont loggées comme `[DEMO]` dans les logs et Telegram.

## Sécurité

- Secrets jamais en Git (`.env`, tokens, credentials)
- Envoi uniquement après validation humaine via Telegram
- Blocage automatique si `risk_level=HIGH`
- Pas d'action sur PJ non vérifiées
- Scan secrets avant commit : `./scripts/scan_secrets.sh`

## Versioning

| Tag | Description |
|-----|-------------|
| `v0.1-poc` | Version initiale POC fonctionnel |
| `v0.2-demo` | Version démo client avec données test |
