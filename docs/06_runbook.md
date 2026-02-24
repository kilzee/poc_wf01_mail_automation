# Runbook — POC Gmail Automation

**Version :** 1.0 — 2026-02-24
**Environnement :** n8n v2.2.6 OSS · Claude Sonnet 4.6 · PostgreSQL · Telegram

---

## 1. Vue d'ensemble

Le système traite automatiquement la boîte Gmail, classe les emails par priorité via LLM (Claude), génère des brouillons de réponse, et notifie l'opérateur sur Telegram pour validation humaine avant tout envoi.

```
Gmail INBOX
    ↓ (Cron toutes les heures, lun-ven 9h-18h)
WF_01 — Ingest & Analyze
    ├── Normalisation + déduplication (PostgreSQL)
    ├── Score anti-phishing (0-100)
    ├── LLM Triage → P1 / P2 / P3
    ├── LLM Draft → brouillon réponse (si needs_reply=true)
    ├── Création draft dans Gmail
    └── Notification Telegram (digest + alertes P1)
                ↓ (boutons Telegram)
WF_06 — Telegram Webhook
    ├── Auth opérateur (TELEGRAM_AUTHORIZED_USER_ID)
    ├── Récupération contexte email (PostgreSQL)
    ├── Exécution action Gmail (API modify)
    ├── Mise à jour état PostgreSQL
    └── Confirmation Telegram
```

---

## 2. Workflows

### WF_01 — Daily Ingest & Analyze

| Paramètre | Valeur |
|---|---|
| Trigger | Cron `0 9-18 * * 1-5` (toutes les heures, lun-ven 9h-18h) + Manuel |
| Source | Gmail INBOX, emails non lus des dernières 24h |
| Déduplication | Via `gmail_message_id` en PostgreSQL |
| LLM Triage | Claude (temp 0.1) → JSON strict |
| LLM Draft | Claude (temp 0.3) → brouillon si `needs_reply=true` |
| Sortie | Draft Gmail + notification Telegram |

**Conditions de création d'un draft :**
- `needs_reply = true` (décidé par le LLM)
- `recommended_action = DRAFT_REPLY`
- `block_send = false` (risk_level ≠ HIGH)

### WF_06 — Telegram Webhook

Reçoit les actions de l'opérateur via les boutons Telegram. Chaque bouton encode `ACTION|gmail_message_id` dans le callback.

---

## 3. Système de priorité

### Règles de classification

| Priorité | Critères | SLA cible |
|---|---|---|
| **P1** | Incident prod, panne, alerte critique, client VIP, litige, mise en demeure, fuite données | < 4h |
| **P2** | Demande client standard, devis, facture, réunion, suivi dossier, RH | Journée |
| **P3** | Newsletter, CC informatif, confirmation automatique, demande non urgente | Peut attendre |

### Déclencheurs P1 garantis (override programmatique)

Le workflow force **P1** indépendamment du LLM si le **sujet** contient l'un de ces mots-clés :

```
incident critique · production down · litige · mise en demeure
data breach · budget · contrat urgent
```

Ou si l'expéditeur est dans `VIP_EMAILS` / `VIP_DOMAINS` (variables d'env).

### Déclencheurs draft

| Condition | Draft créé |
|---|---|
| P2 + DRAFT_REPLY + LOW/MED risk | Oui |
| P1 + DRAFT_REPLY + LOW/MED risk | Oui |
| P1 + ESCALATE (incident critique) | **Non** — opérateur décide |
| Tout email avec risk HIGH | **Non** — block_send=true |

---

## 4. Boutons Telegram

Chaque notification Telegram affiche les boutons d'action pour l'email concerné.

| Bouton | Action Gmail | Labels Gmail | INBOX |
|---|---|---|---|
| **APPROVE_SEND** | Envoie le draft | + `Label_poc_sent_approved` | Retiré |
| **SAVE_DRAFT_ONLY** | Conserve le draft | + `Label_poc_processed` | Retiré |
| **APPLY_LABEL** | Label uniquement | + `Label_poc_processed` | Intact |
| **ARCHIVE** | Archive l'email | + `Label_poc_processed` | **Retiré** |
| **MARK_SPAM** | Marque comme spam | + `SPAM` | Retiré |
| **ESCALATE** | Label escalade | + `Label_poc_escalated` | Intact |
| **IGNORE** | Label ignoré | + `Label_poc_ignored` | Intact |

> **APPROVE_SEND** est bloqué si `block_send=true` (email HIGH risk) ou si aucun draft n'existe.

---

## 5. Labels Gmail

Labels utilisés par le workflow (créés manuellement dans Gmail avant premier run en mode réel) :

| Nom affiché Gmail | ID interne Gmail | Rôle |
|---|---|---|
| `Label_poc_processed` | `Label_2157285236271374757` | Email traité (archivé, draft conservé) |
| `Label_poc_ignored` | `Label_4210411953109202836` | Email ignoré volontairement |
| `Label_poc_sent_approved` | `Label_5892932524421666823` | Réponse envoyée et approuvée |
| `Label_poc_escalated` | `Label_7736907950711324232` | Escaladé pour décision humaine |

Labels système Gmail utilisés directement (pas à créer) : `INBOX`, `SPAM`, `SENT`.

---

## 6. Score anti-phishing

Score calculé de 0 à 100 avant le triage LLM.

| Score | Niveau | Comportement |
|---|---|---|
| 0-29 | LOW | Traitement normal |
| 30-69 | MED | Traitement normal, flag visible dans Telegram |
| 70-100 | HIGH | `block_send=true`, pas de draft, alerte Telegram |

**Signaux détectés :**
- Mismatch display name / domaine expéditeur (ex: "PayPal" depuis un domaine inconnu)
- Reply-To différent du domaine expéditeur
- Domaine lookalike (typosquatting)
- Mots d'urgence dans sujet/corps
- Demande de secrets (OTP, mot de passe, bancaire)
- URLs raccourcies ou IP littérale
- TLD suspects (.xyz, .top, .click…)
- Pièces jointes dangereuses (.exe, .msi, macros Office)

---

## 7. Variables d'environnement

| Variable | Obligatoire | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | Oui | Clé API Claude |
| `ANTHROPIC_MODEL` | Non | Modèle triage (défaut: `claude-haiku-4-5-20251001`) |
| `ANTHROPIC_DRAFT_MODEL` | Non | Modèle draft (défaut: `claude-haiku-4-5-20251001`) |
| `TELEGRAM_BOT_TOKEN` | Oui | Token bot Telegram |
| `TELEGRAM_CHAT_ID` | Oui | Chat ID pour les notifications |
| `TELEGRAM_AUTHORIZED_USER_ID` | Oui | User ID Telegram autorisé à valider |
| `DEMO_MODE` | Non | `true` = simulation (défaut: `true`) |
| `MAX_EMAILS_PER_RUN` | Non | Limite emails par run (défaut: 50) |
| `RISK_ALERT_THRESHOLD` | Non | Seuil alerte Telegram (défaut: 70) |
| `VIP_EMAILS` | Non | Emails VIP séparés par virgule |
| `VIP_DOMAINS` | Non | Domaines VIP séparés par virgule |
| `INTERNAL_DOMAINS` | Non | Domaines internes séparés par virgule |

---

## 8. Mode DEMO vs Réel

| Comportement | DEMO_MODE=true | DEMO_MODE=false |
|---|---|---|
| Lecture emails Gmail | Réelle | Réelle |
| Score anti-phishing | Réel | Réel |
| Triage LLM | Réel | Réel |
| Draft LLM | Réel | Réel |
| Création draft Gmail | Simulée (`DEMO_DRAFT_xxx`) | **Réelle** |
| Labels Gmail | Simulés | **Réels** |
| Archivage | Simulé | **Réel** |
| Envoi email | **Jamais** | Réel (si APPROVE_SEND) |
| Confirmations Telegram | `[DEMO]` préfixé | Normal |
| PostgreSQL (état, audit) | Réel | Réel |

---

## 9. Planification Cron

| Fréquence | Expression | Cas d'usage |
|---|---|---|
| 1×/jour 8h (démo simple) | `0 8 * * 1-5` | Digest matinal uniquement |
| 2×/jour | `0 8,14 * * 1-5` | Couverture matin + après-midi |
| **Toutes les heures** *(recommandé)* | `0 9-18 * * 1-5` | SLA journée sur P2, P1 < 1h |
| Toutes les 30 min | `*/30 9-18 * * 1-5` | SLA serré, volume élevé |

> La déduplication PostgreSQL garantit qu'un email ne sera jamais traité deux fois, quelle que soit la fréquence.

---

## 10. Base de données PostgreSQL

### Tables

**`email_processing`** — Un enregistrement par email traité
- États : `NEW` → `ANALYZED` → `DRAFT_READY` → `APPROVE_SEND` / `ARCHIVE` / `ESCALATE` / `IGNORE`
- Contient toute la trace : risk score, priorité, réponse LLM, action opérateur, timestamps

**`audit_log`** — Une ligne par action (system ou opérateur)

**`run_stats`** — Une ligne par exécution de WF_01 (compteurs P1/P2/P3, durée, etc.)

---

## 11. Sécurité & garde-fous

| Garde-fou | Détail |
|---|---|
| No auto-send | Envoi uniquement sur `APPROVE_SEND` humain via Telegram |
| Block HIGH risk | `block_send=true` → pas de draft, pas d'envoi possible |
| Auth Telegram | Chaque action vérifie `user_id == TELEGRAM_AUTHORIZED_USER_ID` |
| Draft guards | LLM interdit de demander secrets, OTP, données bancaires |
| JSON LLM strict | Validation schéma + fallback déterministe si parsing échoue |
| Idempotence | `gmail_message_id` unique en DB, jamais traité deux fois |
| Secrets hors Git | `.env` ignoré, `config/.env.example` comme template |

---

## 12. Déploiement (VPS)

```bash
# Connexion
ssh -i ~/.ssh/dimouxn8n -p 2226 dim@72.60.173.92

# Déployer un workflow mis à jour
scp -P 2226 workflows/WF_06_telegram_webhook.json dim@72.60.173.92:/tmp/
docker cp /tmp/WF_06_telegram_webhook.json root-n8n-1:/tmp/
docker exec root-n8n-1 n8n import:workflow --input=/tmp/WF_06_telegram_webhook.json

# Modifier une variable d'env
# Éditer /root/.env (nécessite sudo ou root)
# Puis : docker compose up -d
```

**n8n :** `https://n8n.dimouxn8n.cloud`
**Container :** `root-n8n-1`
