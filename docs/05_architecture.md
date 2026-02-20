# Architecture — POC Gmail Automation

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────┐
│                        Gmail INBOX                              │
│  (emails non lus, dernières 24h)                               │
└─────────────────────────┬───────────────────────────────────────┘
                          │ Gmail API (OAuth2)
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│             WF_01 — Daily Ingest & Analyze                      │
│                                                                 │
│  ┌──────────┐  ┌───────────┐  ┌──────────────┐  ┌──────────┐  │
│  │ Trigger  │→ │Normalize  │→ │Security      │→ │LLM       │  │
│  │(Cron/    │  │& Dedup    │  │Analysis      │  │Triage    │  │
│  │ Manual)  │  │           │  │(risk 0-100)  │  │(Claude)  │  │
│  └──────────┘  └───────────┘  └──────────────┘  └────┬─────┘  │
│                                                       │        │
│  ┌──────────────┐  ┌──────────┐  ┌──────────────┐    │        │
│  │Gmail Draft   │← │LLM Draft │← │IF needs_reply│←───┘        │
│  │Create        │  │Generate  │  │& not HIGH    │             │
│  └──────────────┘  └──────────┘  └──────────────┘             │
│         │                                                      │
│         └──→ PostgreSQL (état, audit)                          │
│         └──→ Telegram (digest + alertes P1/HIGH)               │
└─────────────────────────────────────────────────────────────────┘
                          │
                          │ (boutons Telegram)
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│             WF_06 — Telegram Webhook                           │
│                                                                 │
│  Webhook ──→ Auth check ──→ Router                             │
│                             ├── APPROVE_SEND ──→ WF_07         │
│                             ├── EDIT_DRAFT   ──→ Prompt user   │
│                             ├── SAVE_DRAFT   ──→ WF_07         │
│                             ├── APPLY_LABEL  ──→ WF_07         │
│                             ├── ARCHIVE      ──→ WF_07         │
│                             ├── MARK_SPAM    ──→ WF_07         │
│                             ├── ESCALATE     ──→ WF_07         │
│                             └── IGNORE       ──→ Log only      │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│             WF_07 — Gmail Actions                              │
│                                                                 │
│  DEMO_MODE=true  → Log action (no-op)                         │
│  DEMO_MODE=false → Gmail API                                   │
│    ├── Send Draft (uniquement si approved + !block_send)       │
│    ├── Apply/Remove Labels                                     │
│    ├── Mark Read                                               │
│    ├── Archive (modifier INBOX)                                │
│    └── Mark Spam                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## États des emails

```
NEW
 │
 ├─→ [déduplication] ──→ ALREADY_PROCESSED (fin)
 │
 ▼
ANALYZED (normalisation + security scoring)
 │
 ├─→ risk_level=HIGH ──→ RISK_REVIEW (escalade Telegram, pas de draft)
 │
 ▼
NEEDS_REPLY (si needs_reply=true)
 │
 ▼
DRAFT_READY (brouillon créé dans Gmail)
 │
 ▼
AWAITING_APPROVAL (message Telegram envoyé)
 │
 ├─→ APPROVE_SEND ──→ SENT ──→ ARCHIVED
 ├─→ SAVE_DRAFT_ONLY ──→ ARCHIVED
 ├─→ IGNORE ──→ IGNORED
 └─→ ESCALATE ──→ ESCALATED
```

---

## Schéma de base de données (PostgreSQL)

### Table `email_processing`

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | SERIAL PK | ID interne |
| `gmail_message_id` | VARCHAR(255) UNIQUE | ID Gmail (déduplication) |
| `thread_id` | VARCHAR(255) | ID thread Gmail |
| `message_id_header` | VARCHAR(512) | Header Message-ID RFC |
| `from_email` | VARCHAR(512) | Expéditeur |
| `from_name` | VARCHAR(255) | Nom affiché |
| `reply_to` | VARCHAR(512) | Reply-To si différent |
| `subject` | TEXT | Sujet |
| `received_at` | TIMESTAMP | Date réception |
| `state` | VARCHAR(50) | État actuel |
| `risk_level` | VARCHAR(10) | LOW / MED / HIGH |
| `risk_score` | INTEGER | Score 0-100 |
| `risk_reasons` | JSONB | Liste des signaux détectés |
| `priority` | VARCHAR(5) | P1 / P2 / P3 |
| `category` | VARCHAR(50) | Catégorie fonctionnelle |
| `needs_reply` | BOOLEAN | Réponse requise |
| `recommended_action` | VARCHAR(50) | Action LLM recommandée |
| `llm_confidence` | DECIMAL(3,2) | Confiance LLM (0.0-1.0) |
| `draft_id` | VARCHAR(255) | ID draft Gmail |
| `draft_subject` | TEXT | Sujet du brouillon |
| `llm_response` | JSONB | Réponse LLM complète |
| `telegram_message_id` | BIGINT | ID message Telegram envoyé |
| `operator_action` | VARCHAR(50) | Action validée par opérateur |
| `operator_telegram_id` | BIGINT | ID Telegram de l'opérateur |
| `operator_action_at` | TIMESTAMP | Timestamp action opérateur |
| `is_demo` | BOOLEAN | Exécution en mode démo |
| `created_at` | TIMESTAMP | Création enregistrement |
| `updated_at` | TIMESTAMP | Dernière mise à jour |

### Table `audit_log`

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | SERIAL PK | ID log |
| `gmail_message_id` | VARCHAR(255) | Email concerné |
| `action` | VARCHAR(100) | Action effectuée |
| `actor` | VARCHAR(100) | `system` ou `operator:telegram_id` |
| `details` | JSONB | Détails de l'action |
| `is_demo` | BOOLEAN | Mode démo |
| `created_at` | TIMESTAMP | Timestamp |

### Table `run_stats`

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | SERIAL PK | ID run |
| `run_date` | DATE | Date du run |
| `total_processed` | INTEGER | Total emails traités |
| `count_p1` | INTEGER | Emails P1 |
| `count_p2` | INTEGER | Emails P2 |
| `count_p3` | INTEGER | Emails P3 |
| `count_high_risk` | INTEGER | Emails HIGH risk |
| `count_drafts_created` | INTEGER | Brouillons créés |
| `count_sent` | INTEGER | Emails envoyés |
| `duration_seconds` | INTEGER | Durée du run |
| `is_demo` | BOOLEAN | Mode démo |
| `created_at` | TIMESTAMP | Timestamp |

---

## Flux de données détaillé

### 1. Normalisation email

```javascript
// Entrée Gmail API
{
  id: "gmail_message_id",
  threadId: "thread_id",
  payload: {
    headers: [...],
    body: { data: "base64..." },
    parts: [...]
  }
}

// Sortie normalisée
{
  gmail_message_id: "...",
  thread_id: "...",
  message_id_header: "<...@...>",
  from_email: "sender@domain.com",
  from_name: "Sender Name",
  reply_to: "other@domain.com",  // ou null
  subject: "...",
  date: "2026-02-20T08:00:00Z",
  body_text: "...",  // HTML→text converti
  body_html: "...",
  attachments: [{name, type, size}],
  urls: ["https://..."],  // extraits du body
  snippet: "..."
}
```

### 2. Score anti-phishing

```javascript
// Sortie du module sécurité
{
  risk_score: 42,
  risk_level: "MED",
  risk_reasons: [
    "reply_to_different_domain: reply-to pointe vers evil.com",
    "urgency_keywords: 'urgent' détecté dans le sujet"
  ],
  block_send: false,
  requires_manual_review: true,
  attachments_risk: "safe"
}
```

### 3. Réponse LLM (schéma strict)

```json
{
  "summary": "...",
  "priority": "P1",
  "category": "INCIDENT",
  "needs_reply": true,
  "recommended_action": "DRAFT_REPLY",
  "risk_signals": [],
  "draft_reply": {
    "subject": "Re: ...",
    "body": "..."
  },
  "questions_to_confirm": [],
  "confidence": 0.92
}
```

---

## Sécurité & garde-fous

| Garde-fou | Implémentation |
|-----------|----------------|
| No auto-send | Envoi uniquement si `APPROVE_SEND` reçu via Telegram |
| Block HIGH risk | `block_send=true` si `risk_level=HIGH` |
| Validation opérateur | Vérification `telegram_user_id` à chaque action |
| JSON LLM strict | Validation schéma + fallback déterministe |
| Idempotence | Check `gmail_message_id` en DB avant traitement |
| Mode DEMO | Flag global, aucune action Gmail en mode démo |
| Secrets hors Git | `.env` ignoré par `.gitignore` |
| Draft guards | Interdiction de demander secrets/OTP dans les prompts |
| PJ suspectes | Extensions interdites bloquées, alerte opérateur |

---

## Limites du POC

- 1 boîte Gmail (pas multi-compte)
- Quota Gmail API : 250 unités/s (suffisant pour POC)
- Quota Claude API : dépend du plan
- PostgreSQL local (pas HA)
- 1 opérateur Telegram (pas multi-approbateur)
- Pas de retry sophistiqué sur les appels LLM
- Thread context limité (pas de récupération des emails précédents)
