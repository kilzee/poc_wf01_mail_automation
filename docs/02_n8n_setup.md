# Guide — Installation & Configuration n8n v2.2.6 OSS

## Prérequis

- Docker 24+ et Docker Compose v2+
- Ports disponibles : 5678 (n8n), 5432 (PostgreSQL)
- RAM minimum : 2 Go (recommandé : 4 Go)

---

## Étape 1 — Cloner & configurer

```bash
git clone <repo-url>
cd workflow_n8n_automation_mail

# Créer .env depuis le template
cp config/.env.example .env
```

Éditer `.env` et remplir **tous** les champs marqués `CHANGE_ME_*` :

```bash
# Générer les secrets nécessaires
echo "POSTGRES_PASSWORD: $(openssl rand -hex 24)"
echo "N8N_BASIC_AUTH_PASSWORD: $(openssl rand -hex 16)"
echo "N8N_ENCRYPTION_KEY: $(openssl rand -hex 32)"
```

---

## Étape 2 — Démarrer les services

```bash
# Démarrer en arrière-plan
docker-compose up -d

# Vérifier que tout est démarré
docker-compose ps

# Voir les logs
docker-compose logs -f n8n
docker-compose logs -f postgres
```

Attendre que la DB soit healthy et n8n démarré (~30 secondes).

---

## Étape 3 — Accéder à n8n

Ouvrir : `http://localhost:5678`

Login :
- **User** : valeur de `N8N_BASIC_AUTH_USER` dans `.env`
- **Password** : valeur de `N8N_BASIC_AUTH_PASSWORD` dans `.env`

---

## Étape 4 — Configurer les Credentials

### 4.1 Gmail OAuth2

Voir [01_google_oauth_setup.md](01_google_oauth_setup.md).

Après configuration, noter le nom du credential (ex: `Gmail POC`).
Ce nom sera à sélectionner dans les nœuds Gmail des workflows.

### 4.2 Anthropic (Claude API)

1. Menu → **"Credentials"** → **"+ Add Credential"**
2. Chercher **"HTTP Header Auth"** (ou créer un credential générique)
3. Nom : `Anthropic API`
4. Header Name : `x-api-key`
5. Header Value : votre clé `sk-ant-...`
6. Sauvegarder

> Alternative : utiliser le credential **"Anthropic"** si disponible dans votre version.

### 4.3 PostgreSQL

1. Menu → **"Credentials"** → **"+ Add Credential"**
2. Chercher **"Postgres"**
3. Remplir :
   - Host : `postgres` (nom du service Docker)
   - Port : `5432`
   - Database : valeur de `POSTGRES_DB` dans `.env`
   - User : valeur de `POSTGRES_USER`
   - Password : valeur de `POSTGRES_PASSWORD`
4. Nom : `Postgres POC`
5. Tester la connexion → Sauvegarder

### 4.4 Telegram (HTTP Request)

Le bot Telegram est géré via HTTP Request avec le token en header.
Pas de credential n8n spécifique nécessaire — le token est dans `.env`.
Il sera injecté dans les nœuds HTTP Request via la variable d'environnement.

---

## Étape 5 — Importer les workflows

```bash
./scripts/import_workflows.sh
```

Ou manuellement via l'interface :
1. Menu → **"Workflows"**
2. **"Import from File"**
3. Sélectionner chaque fichier dans `workflows/`
4. Importer dans cet ordre :
   1. `WF_07_gmail_actions.json`
   2. `WF_06_telegram_webhook.json`
   3. `WF_01_daily_ingest.json`

---

## Étape 6 — Lier les credentials aux workflows

Pour chaque workflow importé :
1. Ouvrir le workflow
2. Pour chaque nœud **Gmail** : sélectionner `Gmail POC`
3. Pour chaque nœud **Postgres** : sélectionner `Postgres POC`
4. Pour chaque nœud **HTTP Request vers Anthropic** : sélectionner `Anthropic API`
5. Sauvegarder le workflow

---

## Étape 7 — Configurer le webhook Telegram

1. Ouvrir `WF_06_telegram_webhook`
2. Cliquer sur le nœud **"Telegram Webhook"** (type: Webhook)
3. Copier l'**URL du webhook** affichée (format: `http://localhost:5678/webhook/telegram-actions`)
4. **Activer le workflow** (toggle en haut à droite)
5. Enregistrer cette URL comme webhook Telegram :

```bash
TELEGRAM_BOT_TOKEN="votre_token"
WEBHOOK_URL="http://votre-serveur:5678/webhook/telegram-actions"

curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"${WEBHOOK_URL}\"}"
```

> **Important** : Pour la production, n8n doit être accessible publiquement (HTTPS recommandé).
> Pour les tests locaux, utiliser [ngrok](https://ngrok.com/) : `ngrok http 5678`

---

## Étape 8 — Activer & tester WF_01

1. Ouvrir `WF_01 - Daily Ingest & Analyze`
2. Vérifier que tous les credentials sont liés
3. S'assurer que `DEMO_MODE=true` dans `.env` pour les premiers tests
4. Cliquer **"Execute Workflow"** (bouton ▶ en bas)
5. Observer l'exécution dans le panneau d'exécution
6. Vérifier les logs Telegram

---

## Étape 9 — Activer le déclencheur planifié

Quand les tests sont satisfaisants :
1. Ouvrir `WF_01`
2. Toggle **"Active"** en haut à droite
3. Le workflow démarrera automatiquement chaque matin à l'heure configurée

---

## Variables d'environnement dans les Code nodes

Les workflows accèdent aux variables d'environnement via :
```javascript
// Dans un Code node n8n
const demoMode = $env['DEMO_MODE'] === 'true';
const anthropicKey = $env['ANTHROPIC_API_KEY'];
const telegramToken = $env['TELEGRAM_BOT_TOKEN'];
const chatId = $env['TELEGRAM_CHAT_ID'];
```

> n8n v2.2.6 expose les variables d'environnement définies dans le container
> directement via `$env` dans les Code nodes.

---

## Maintenance

### Redémarrer n8n

```bash
docker-compose restart n8n
```

### Mettre à jour n8n

```bash
# Modifier la version dans docker-compose.yml : image: n8nio/n8n:X.Y.Z
docker-compose pull n8n
docker-compose up -d n8n
```

### Voir les exécutions

n8n → Menu → **"Executions"** (historique de toutes les exécutions)

### Nettoyer les données POC (TTL)

```bash
# Se connecter à PostgreSQL
docker-compose exec postgres psql -U n8n -d n8n_mail_poc

-- Supprimer les données > 30 jours
DELETE FROM email_processing WHERE created_at < NOW() - INTERVAL '30 days';
DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL '30 days';
\q
```

### Exporter les workflows modifiés

```bash
./scripts/export_workflows.sh
```
