# Changelog

Toutes les modifications notables de ce projet sont documentées ici.
Format : [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/)

## [Unreleased]

## [v0.2-demo] — À venir

### Planifié
- Données de démo pré-chargées (emails fictifs)
- Dashboard KPI dans Telegram
- Support multi-langue (FR/EN)
- Export rapport PDF hebdomadaire

## [v0.1-poc] — 2026-02-20

### Ajouté
- Workflow WF_01 : ingest quotidien Gmail (unread, 24h, pagination)
- Normalisation emails : headers, body HTML→text, métadonnées
- Déduplication par `gmail_message_id` + `message-id` header
- Module anti-phishing : score 0-100, 12 vecteurs de détection
- Module triage LLM (Claude) : JSON strict P1/P2/P3, 8 catégories
- Module draft LLM : brouillons pro avec `{A_CONFIRMER}`
- Création automatique drafts Gmail (sans envoi)
- Workflow WF_06 : webhook Telegram, 8 actions opérateur
- Workflow WF_07 : exécution Gmail (labels, archive, send, spam)
- PostgreSQL : schéma audit, idempotence, TTL
- Mode DEMO/DRY_RUN (no-op sur toutes les actions Gmail)
- Digest Telegram quotidien : top P1/P2, stats, alertes
- Documentation complète : OAuth, n8n, Telegram, démo
- Scripts : export/import workflows, validate JSON, scan secrets
- docker-compose.yml : n8n v2.2.6 + PostgreSQL 15
- Structure Git propre, .gitignore exhaustif

### Sécurité
- No auto-send par défaut
- Blocage draft si `risk_level=HIGH`
- Jamais de secrets en Git
- Validation JSON LLM + fallback règles déterministes
- Garde-fous draft : pas de secrets/OTP, pas de liens suspects
