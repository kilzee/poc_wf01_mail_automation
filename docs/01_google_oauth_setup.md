# Guide — Configuration Google Cloud OAuth2 pour Gmail API

## Prérequis

- Compte Google avec la boîte Gmail à automatiser
- Accès à [Google Cloud Console](https://console.cloud.google.com/)

---

## Étape 1 — Créer un projet Google Cloud

1. Ouvrir [console.cloud.google.com](https://console.cloud.google.com/)
2. Cliquer **"Nouveau projet"** (ou sélectionner un projet existant)
3. Nom : `poc-gmail-automation` (ou au choix)
4. Cliquer **"Créer"**
5. Sélectionner le projet créé dans le menu déroulant en haut

---

## Étape 2 — Activer l'API Gmail

1. Dans le menu gauche : **"API et services" → "Bibliothèque"**
2. Rechercher **"Gmail API"**
3. Cliquer sur **Gmail API**
4. Cliquer **"Activer"**

---

## Étape 3 — Configurer l'écran de consentement OAuth

1. **"API et services" → "Écran d'autorisation OAuth"**
2. Type d'utilisateur : **"Externe"** (pour un compte Gmail personnel)
   - Si G Workspace entreprise : choisir "Interne"
3. Remplir les informations obligatoires :
   - Nom de l'application : `POC Gmail Automation`
   - Email de support utilisateur : votre email
   - Email du développeur : votre email
4. Cliquer **"Enregistrer et continuer"**
5. **Champs d'application** → Cliquer **"Ajouter ou supprimer des champs d'application"**
6. Ajouter ces scopes **minimaux** :
   ```
   https://www.googleapis.com/auth/gmail.readonly
   https://www.googleapis.com/auth/gmail.modify
   https://www.googleapis.com/auth/gmail.compose
   https://www.googleapis.com/auth/gmail.send
   ```
   > **Note sécurité** : `gmail.modify` est nécessaire pour les labels et l'archivage.
   > `gmail.send` uniquement si `DEMO_MODE=false`.
7. Cliquer **"Mettre à jour"** puis **"Enregistrer et continuer"**
8. **Utilisateurs test** → Cliquer **"+ Add users"**
   - Ajouter votre adresse Gmail (celle à surveiller)
9. Cliquer **"Enregistrer et continuer"** → **"Retour au tableau de bord"**

---

## Étape 4 — Créer les identifiants OAuth2

1. **"API et services" → "Identifiants"**
2. Cliquer **"+ Créer des identifiants" → "ID client OAuth"**
3. Type d'application : **"Application Web"**
4. Nom : `n8n POC`
5. **URI de redirection autorisés** — ajouter :
   ```
   http://localhost:5678/rest/oauth2-credential/callback
   ```
   > Si n8n est sur un serveur distant, remplacer `localhost:5678` par votre domaine.
6. Cliquer **"Créer"**
7. **Copier et noter** :
   - `Client ID` → `GMAIL_OAUTH_CLIENT_ID` dans `.env`
   - `Client Secret` → `GMAIL_OAUTH_CLIENT_SECRET` dans `.env`

> **SÉCURITÉ** : Ces valeurs sont des secrets. Ne les commitez jamais dans Git.
> Elles sont stockées **chiffrées** dans n8n via l'interface Credentials.

---

## Étape 5 — Configurer le credential Gmail dans n8n

1. Ouvrir n8n : `http://localhost:5678`
2. Menu gauche → **"Credentials"** → **"+ Add Credential"**
3. Chercher **"Gmail OAuth2 API"**
4. Remplir :
   - **Client ID** : valeur copiée à l'étape 4
   - **Client Secret** : valeur copiée à l'étape 4
5. Cliquer **"Sign in with Google"**
6. Sélectionner votre compte Gmail
7. Accepter les autorisations demandées
8. Nommer le credential : `Gmail POC`
9. **Sauvegarder**

> n8n stocke le refresh token chiffré avec `N8N_ENCRYPTION_KEY`.

---

## Étape 6 — Créer les labels Gmail personnalisés

Les labels doivent être créés dans Gmail avant d'être utilisés dans les workflows.

### Via Gmail Web (manuel)

1. Ouvrir [mail.google.com](https://mail.google.com/)
2. Colonne gauche → Scroll bas → **"Nouveau libellé"**
3. Créer les labels suivants :
   - `POC/Traité`
   - `POC/P1-Urgent`
   - `POC/P2-Normal`
   - `POC/P3-Faible`
   - `POC/HighRisk`
   - `POC/Draft-Prêt`
   - `POC/Envoyé-Approuvé`
   - `POC/Escaladé`
   - `POC/Ignoré`

### Récupérer les IDs des labels

Après création, récupérer les IDs via l'API Gmail (dans le workflow ou via curl) :

```bash
# Obtenir un token d'accès (depuis n8n ou Google OAuth Playground)
TOKEN="votre_access_token"

curl -H "Authorization: Bearer $TOKEN" \
  "https://gmail.googleapis.com/gmail/v1/users/me/labels" \
  | python3 -m json.tool
```

Copier les IDs dans `config/gmail_labels.json` (champs `id` de chaque label).

---

## Vérification

Tester l'accès depuis n8n :
1. Ouvrir un workflow
2. Ajouter un nœud **Gmail**
3. Sélectionner le credential `Gmail POC`
4. Operation : **Get Many Messages**
5. Exécuter — vérifier que des emails sont retournés

---

## Rotation & sécurité

- Le refresh token n'expire pas sauf si révoqué manuellement
- Si révoqué : refaire l'étape 5 (re-auth Google)
- Pour révoquer : [myaccount.google.com/permissions](https://myaccount.google.com/permissions)
- Surveiller les **quotas API** : [console.cloud.google.com/apis/dashboard](https://console.cloud.google.com/apis/dashboard)
  - Gmail API : 1 milliard d'unités/jour (très largement suffisant pour ce POC)
