# Guide — Création & Configuration du Bot Telegram

## Étape 1 — Créer le bot via BotFather

1. Ouvrir Telegram → chercher `@BotFather`
2. Envoyer `/newbot`
3. Suivre les instructions :
   - Nom du bot : `POC Gmail Automation Bot` (ou au choix)
   - Username (doit finir par `bot`) : ex. `poc_gmail_auto_bot`
4. **Copier le token** affiché (format : `123456789:ABCdef...`)
5. Placer ce token dans `.env` :
   ```
   TELEGRAM_BOT_TOKEN=123456789:ABCdef...
   ```

### Configurer les commandes du bot (optionnel)

Envoyer à @BotFather :
```
/setcommands
```
Puis sélectionner le bot et coller :
```
status - Statut du système d'automation
digest - Afficher le digest du jour
help - Aide sur les commandes disponibles
demomode - Activer/désactiver le mode démo
```

---

## Étape 2 — Obtenir votre Chat ID

### Méthode 1 : Via @userinfobot
1. Chercher `@userinfobot` dans Telegram
2. Envoyer `/start`
3. Il vous affiche votre user ID

### Méthode 2 : Via l'API
1. Ouvrir votre bot en conversation privée
2. Envoyer n'importe quel message
3. Appeler :
   ```bash
   curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
   ```
4. Dans la réponse JSON, trouver `message.chat.id`

Placer le chat ID dans `.env` :
```
TELEGRAM_CHAT_ID=123456789
TELEGRAM_AUTHORIZED_USER_ID=123456789
```

---

## Étape 3 — Enregistrer le Webhook

> Pour les tests locaux, utiliser ngrok pour exposer n8n publiquement.

### Avec ngrok (développement local)

```bash
# Installer ngrok: https://ngrok.com/download
ngrok http 5678

# ngrok affiche une URL publique comme:
# https://abc123.ngrok.io

# Enregistrer le webhook
TELEGRAM_BOT_TOKEN="votre_token"
NGROK_URL="https://abc123.ngrok.io"

curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"${NGROK_URL}/webhook/telegram-actions\", \"allowed_updates\": [\"callback_query\", \"message\"]}"
```

### En production (serveur avec HTTPS)

```bash
TELEGRAM_BOT_TOKEN="votre_token"
N8N_PUBLIC_URL="https://n8n.votre-domaine.com"

curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"${N8N_PUBLIC_URL}/webhook/telegram-actions\", \"allowed_updates\": [\"callback_query\", \"message\"]}"
```

### Vérifier le webhook

```bash
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

Réponse attendue :
```json
{
  "ok": true,
  "result": {
    "url": "https://votre-serveur/webhook/telegram-actions",
    "has_custom_certificate": false,
    "pending_update_count": 0,
    "last_error_date": ...,
    "max_connections": 40
  }
}
```

---

## Étape 4 — Format des messages Telegram

### Message d'alerte individuel (email P1 ou HIGH risk)

```
🚨 *[P1] Incident Production*
📧 De: client@entreprise.com
📁 Catégorie: INCIDENT
⚠️ Risk: HIGH (score: 78)
🔍 Signaux: reply-to suspect, urgence artificielle

_Résumé: Le client signale une panne totale de son système de facturation depuis 14h._

⬇️ Actions disponibles:
```
Suivi des boutons inline :
- ✅ Approuver & Envoyer
- ✏️ Modifier brouillon
- 💾 Garder brouillon
- 🏷️ Appliquer label
- 📦 Archiver
- 🚫 Marquer spam
- 🔺 Escalader
- ⏭️ Ignorer

### Digest quotidien

```
📊 *Rapport quotidien — 20/02/2026 08:00*

📬 Emails traités: 12
🔴 P1 (urgent): 2
🟡 P2 (normal): 7
🟢 P3 (faible): 3

⚠️ Alertes risque:
• 1 email HIGH risk bloqué
• 2 emails MED risk en attente

📝 Brouillons créés: 6
✅ Déjà envoyés: 0

⏱️ Temps estimé gagné: ~45 min

_Mode: DEMO 🔵_
```

---

## Étape 5 — Tester le bot

### Test manuel

Envoyer `/start` à votre bot → il doit répondre (si WF_06 est actif).

### Test complet

1. Activer `WF_06_telegram_webhook` dans n8n
2. Exécuter `WF_01` en mode manuel
3. Vérifier que vous recevez un message Telegram
4. Cliquer sur un bouton d'action
5. Vérifier dans n8n (Executions) que WF_06 a traité l'action

---

## Sécurité

### Vérification d'identité

Dans `WF_06`, chaque callback_query vérifie :
```javascript
const userId = update.callback_query.from.id;
const authorizedId = parseInt($env['TELEGRAM_AUTHORIZED_USER_ID']);
if (userId !== authorizedId) {
  // Rejeter silencieusement + logger la tentative
}
```

### Recommandations

- Ne partager le bot qu'avec les personnes autorisées
- Utiliser un groupe privé si plusieurs opérateurs
- Pour plusieurs opérateurs : stocker une liste d'IDs autorisés dans `config/`
- Les token Telegram ne doivent jamais apparaître dans les logs n8n
- Revoke le token si compromis : `@BotFather → /mybots → Revoke token`
