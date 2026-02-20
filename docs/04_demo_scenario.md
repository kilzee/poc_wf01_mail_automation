# Scénario de Démo Client

## Contexte

Démonstration d'un POC d'automatisation Gmail avec pilotage Telegram.
Durée : 20-30 minutes. Mode : `DEMO_MODE=true` (aucune action réelle).

---

## Préparation (avant la démo)

### Checklist technique

- [ ] n8n démarré : `docker-compose up -d`
- [ ] `DEMO_MODE=true` dans `.env`
- [ ] Bot Telegram accessible et webhook configuré
- [ ] Gmail connecté (credential OAuth2 actif)
- [ ] Données test en base (optionnel : `scripts/load_demo_data.sh`)
- [ ] Ngrok actif si démo en local : `ngrok http 5678`
- [ ] Téléphone Telegram à portée de main

### Emails test recommandés (à préparer dans Gmail)

1. **Email P1 — Incident critique** (de client fictif)
   - Sujet : `URGENT : Production down depuis 2h - Impact 500 utilisateurs`
   - Expéditeur : `client@demo-entreprise.com`
   - Corps : "Bonjour, notre plateforme est inaccessible depuis ce matin..."

2. **Email PHISHING — HIGH risk** (expéditeur lookalike)
   - Sujet : `Action requise : Votre compte sera suspendu dans 24h`
   - Expéditeur : `security@paypa1-secure.com` (lookalike paypal)
   - Corps : "Cliquez ici pour vérifier vos informations de paiement..."
   - Lien : http://192.168.1.1/login (IP literal)

3. **Email P2 — Facture fournisseur**
   - Sujet : `Facture F-2026-0234 - Échéance le 28/02`
   - Expéditeur : `comptabilite@fournisseur.fr`
   - Corps : "Veuillez trouver ci-joint notre facture mensuelle..."

4. **Email P3 — Newsletter**
   - Sujet : `[Newsletter] Les dernières actualités tech de février`
   - Expéditeur : `news@techblog.io`
   - Corps : texte long de newsletter

5. **Email VIP — CEO**
   - Sujet : `Budget Q1 — Validation requise avant vendredi`
   - Expéditeur : `pdg@monentreprise.com` (dans vip_list.json)
   - Corps : "Pouvez-vous me confirmer le budget alloué..."

---

## Déroulement de la démo

### Acte 1 — Présentation du problème (3 min)

**Script :**
> "Voici la boîte Gmail du responsable. Ce matin : 47 emails non lus.
> Sans automatisation, il faut 45-60 minutes juste pour trier, prioriser et rédiger les premières réponses.
> Notre POC va faire ça en moins de 2 minutes."

**Action :** Montrer la boîte Gmail avec les emails test.

---

### Acte 2 — Lancer l'analyse (5 min)

**Action :** Dans n8n, ouvrir `WF_01 - Daily Ingest & Analyze`.

**Script :**
> "On lance l'analyse manuellement pour la démo. En production, ça tourne automatiquement à 8h."

**Action :** Cliquer **Execute Workflow** ▶

**Montrer en temps réel :**
- Les nœuds qui s'exécutent (vert = succès)
- Le nœud "Normalize Email" : données structurées
- Le nœud "Security Analysis" : score risk calculé
- Le nœud "LLM Triage" : appel Claude API
- Le nœud "Create Gmail Draft" : brouillon créé

**Script pendant l'exécution :**
> "L'email 1 : incident critique → P1, catégorie INCIDENT, risk LOW.
> Le workflow rédige automatiquement un brouillon professionnel.
>
> L'email 2 : regardez ce score de risque → 82/100 HIGH.
> Lookalike 'paypa1' au lieu de 'paypal', IP literal dans le lien.
> Aucun brouillon généré. Alerte immédiate envoyée."

---

### Acte 3 — Réception Telegram (5 min)

**Montrer le téléphone Telegram :**

> "Pendant que le workflow tourne, voici ce que reçoit l'opérateur."

**Message 1 — Alerte HIGH risk :**
```
🚨 [HIGH RISK] Action requise - Votre compte sera suspendu dans 24h
📧 De: security@paypa1-secure.com
⚠️ Score: 82/100 — Phishing probable
🔍 Détails: Lookalike 'paypa1' (paypal), lien IP, urgence artificielle
❌ Aucun brouillon — Envoi bloqué automatiquement
[🚫 Marquer spam] [🔺 Escalader] [⏭️ Ignorer]
```

**Script :**
> "L'opérateur n'a qu'à cliquer 'Marquer spam'. Fait en 2 secondes."

**Cliquer `🚫 Marquer spam`** → Montrer la confirmation.

**Message 2 — Incident P1 :**
```
🔴 [P1] URGENT: Production down depuis 2h
📧 De: client@demo-entreprise.com
📁 INCIDENT | ⚠️ Risk: LOW (12/100)
_Production inaccessible, 500 utilisateurs impactés..._
📝 Brouillon prêt ✓
[✅ Approuver & Envoyer] [✏️ Modifier] [💾 Garder] [📦 Archiver]
```

**Script :**
> "Email P1 avec brouillon auto-généré. Voyons le brouillon."

---

### Acte 4 — Revue du brouillon (5 min)

**Action :** Ouvrir Gmail → Drafts → Montrer le brouillon.

**Brouillon généré :**
```
Sujet: Re: URGENT : Production down depuis 2h - Impact 500 utilisateurs

Bonjour,

Merci pour votre signalement. Nous prenons en charge cet incident en priorité.

Notre équipe technique est mobilisée. Nous vous confirmons un premier point
de situation dans {A_CONFIRMER: délai — ex: 30 minutes}.

Numéro de ticket associé : {A_CONFIRMER: numéro de ticket incident}

Nous vous tiendrons informé(e) de l'avancement.

Cordialement,
{A_CONFIRMER: votre nom}
{A_CONFIRMER: votre poste}
```

**Script :**
> "Le brouillon est professionnel, concis, avec des `{A_CONFIRMER}` clairs
> pour les informations que l'IA ne peut pas inventer.
> L'opérateur corrige les placeholders en 30 secondes, puis approuve."

**Action :** Cliquer `✅ Approuver & Envoyer` dans Telegram.

> [Mode DEMO] : "En mode démo, l'envoi est simulé. En production, l'email partirait maintenant."

---

### Acte 5 — Digest quotidien (3 min)

**Afficher le digest Telegram reçu :**
```
📊 Rapport — 20/02/2026 08:02

📬 5 emails traités en 1m 47s
🔴 P1: 2 (1 incident, 1 VIP CEO)
🟡 P2: 2 (1 facture, 1 client)
🟢 P3: 1 (newsletter)

⚠️ 1 email HIGH risk bloqué (phishing détecté)
📝 4 brouillons générés
✅ 0 envois (mode DEMO)

⏱️ Temps gagné estimé: ~42 minutes
```

**Script :**
> "En 1m47s, 5 emails triés, priorités claires, brouillons prêts.
> L'opérateur n'intervient que pour valider — le reste est automatique."

---

### Acte 6 — Questions & différenciateurs (5 min)

**Points forts à souligner :**

| Fonctionnalité | Valeur |
|----------------|--------|
| Anti-phishing explicable | Score + raisons lisibles par l'humain |
| No auto-send | Conformité, RGPD, responsabilité |
| Brouillons `{A_CONFIRMER}` | Pas d'hallucinations dangereuses |
| Mode DEMO | Démo sans risque, adoption progressive |
| Open source n8n | Pas de vendor lock-in, déployable on-premise |
| Git + versioning | Auditabilité, maintenance, évolutions |

**Questions anticipées :**

*"Et si le LLM se trompe ?"*
> "Deux garde-fous : (1) validation humaine obligatoire avant envoi,
> (2) fallback déterministe si le JSON LLM est invalide."

*"Les données sortent-elles de notre infra ?"*
> "n8n est on-premise. Seul le contenu de l'email part vers l'API Claude.
> En option : Claude en local avec Ollama (POC Phase 2)."

*"Que se passe-t-il en cas de panne n8n ?"*
> "Les emails restent dans Gmail non lus. Aucune perte.
> Alertes Postgres + Telegram en cas d'échec d'exécution."

---

## Métriques POC attendues

| Métrique | Objectif POC |
|----------|-------------|
| Emails triés / heure | 60-100 (limité par quota API) |
| Précision priorisation | > 85% sur emails test |
| Faux positifs phishing | < 5% |
| Temps moyen traitement / email | < 30 secondes |
| Temps gagné opérateur / jour | 30-90 minutes (estimé) |
