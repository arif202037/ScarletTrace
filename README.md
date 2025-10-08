# 🔴 ScarletTrace — API de logging de connexions (Ruby / Sinatra)

> **ScarletTrace** est une petite API Ruby/Sinatra conçue pour tracer les connexions utilisateurs.
> Elle enregistre chaque tentative de connexion sous forme de JSON dans `logs.jsonl`
> et envoie automatiquement une notification courte vers **Discord** et **Telegram**.
> Léger, élégant et discret — un outil parfait pour surveiller les activités d’une API ou d’un service.

---

## ✨ Fonctionnalités principales

* **Endpoint `POST /login`** :

  * Lit un JSON (username + device info)
  * Redige les champs sensibles (`password`, `token`)
  * Ajoute l’IP cliente et un timestamp ISO8601 (UTC)
  * Enregistre une ligne JSON dans `logs.jsonl`
  * Envoie une notification vers Discord et Telegram
* **Endpoint `GET /`** — test de santé rapide
* **Limitation de requêtes** via `Rack::Throttle::Minute` (par défaut 60/minute)
* **Gestion d’erreurs robuste** et réponses JSON cohérentes
* **Configuration simple** via `.env`

---

## ⚙️ Pile / Versions

* **Langage :** Ruby 3.2+
* **Framework :** Sinatra
* **Gems :** `sinatra`, `json` (standard), `dotenv`, `net/http` (standard), `uri` (standard), `rack-throttle`

---

## 📁 Fichiers importants

* `app.rb` — Application principale Sinatra
* `logs.jsonl` — Fichier de logs (créé à la volée)
* `.env` — Variables d’environnement (configuration du service)

---

## 🚀 Installation rapide

1️⃣ Installer Ruby 3.2+
2️⃣ Installer les gems nécessaires :

```bash
gem install sinatra dotenv rack-throttle
```

3️⃣ Créer un fichier `.env` :

```dotenv
# Notifications Discord
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxx/yyy

# Notifications Telegram
TELEGRAM_BOT_TOKEN=123456:ABCDEF...
TELEGRAM_CHAT_ID=123456789

# Réglages serveur (optionnels)
PORT=4567
BIND=0.0.0.0
THROTTLE_MAX_PER_MIN=60
```

---

## ▶️ Démarrage

```bash
ruby app.rb
```

* Écoute par défaut sur `0.0.0.0:4567`
* Variables `PORT` et `BIND` configurables
* `RACK_ENV` par défaut : `development`

---

## 🔍 Endpoints

### `GET /`

**Réponse :**

```json
{ "ok": true, "service": "scarlet-trace", "time": "2025-10-08T15:00:00Z" }
```

---

### `POST /login`

**Content-Type :** `application/json`
**Exemple de requête :**

```json
{
  "username": "ray",
  "device": {
    "userAgent": "Mozilla/5.0",
    "platform": "MacOS",
    "language": "en-US",
    "screen": {"width": 2560, "height": 1600},
    "timezone": "Europe/London"
  }
}
```

#### ✅ Validation

* `username` : string non vide (obligatoire)
* `device` : objet optionnel
* `screen.width` / `screen.height` : numériques si présents

#### 🔧 Traitement côté serveur

* Redaction automatique des clés `password`, `token` → `[REDACTED]`
* Ajout de `ip` (adresse IP de la requête) et `timestamp` (UTC ISO8601)
* Écriture dans `logs.jsonl` (1 JSON/ligne) avec verrouillage de fichier
* Notification Discord + Telegram (si configurés)

#### 📤 Réponses possibles

| Code | Réponse                                              | Description        |
| ---- | ---------------------------------------------------- | ------------------ |
| 201  | `{ "ok": true }`                                     | Succès             |
| 400  | `{ "error": "Invalid JSON" }`                        | JSON invalide      |
| 422  | `{ "error": "Validation failed", "details": [...] }` | Validation échouée |
| 429  | `{"error":"Rate limit exceeded"}`                    | Trop de requêtes   |
| 500  | `{ "error": "Failed to persist log" }`               | Erreur d’écriture  |

---

## 🧾 Journalisation (JSONL)

Les logs sont stockés dans `logs.jsonl` à la racine du projet.
Chaque ligne correspond à un objet JSON unique.

**Exemple d’entrée :**

```json
{"username":"ray","device":{"platform":"MacOS","language":"en-US","screen":{"width":2560,"height":1600}},"ip":"84.12.33.5","timestamp":"2025-10-08T15:00:00Z"}
```

Lecture rapide :

```bash
tail -f logs.jsonl
```

---

## 🔔 Notifications

* **Discord** : envoi via `DISCORD_WEBHOOK_URL` (champ `content`)
* **Telegram** : envoi via `sendMessage` (`TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID`)
* Les erreurs de notification sont silencieuses (elles n’interrompent pas la requête principale).

---

## 🧱 Limitation de requêtes

* Activée automatiquement via `Rack::Throttle::Minute`
* Plafond configurable avec `THROTTLE_MAX_PER_MIN` (défaut : 60/minute)

---

## 🔒 Sécurité & confidentialité

* Redaction automatique de `password` et `token` avant persistance
* L’adresse IP est obtenue via `request.ip` (ou `X-Forwarded-For`)
* Les IPs sont considérées comme données sensibles — manipuler selon vos politiques de confidentialité
* Aucun mot de passe, token ou info sensible n’est envoyé dans les notifications

---

## 🧪 Test rapide (cURL)

```bash
curl -X POST http://localhost:4567/login \
  -H "Content-Type: application/json" \
  -d '{
    "username":"ray",
    "device":{
      "userAgent":"Mozilla/5.0",
      "platform":"MacOS",
      "language":"en-US",
      "screen": {"width":2560, "height":1600},
      "timezone":"Europe/London"
    }
  }'
```

---

## ⚙️ Déploiement

* Définir `RACK_ENV=production`
* Utiliser un reverse proxy (Nginx, Caddy, etc.) vers `BIND:PORT`
* Prévoir une rotation de logs (`logs.jsonl` peut croître rapidement)
* Sur Windows : exécuter `ruby app.rb` comme service ou tâche planifiée

---

## 🧩 Métadonnées projet

**Nom du projet :** `ScarletTrace`
**Description courte :**

> Un logger d’API léger en Ruby/Sinatra pour tracer les connexions utilisateurs et envoyer des notifications en temps réel vers Discord et Telegram.

**Tags GitHub :**

```
ruby sinatra logger api security telemetry webhook telegram discord jsonl audit monitoring lightweight
```

---

**Auteur :** *Miro-fr* ✨
Déployez, connectez, et laissez **ScarletTrace** surveiller vos logs en silence.



