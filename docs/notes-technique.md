#  Notes Techniques — Déploiement Sécurisé Nginx + React

Documentation détaillée des étapes suivies pour déployer un projet React 
sur un serveur Ubuntu, avec sécurisation SSH, HTTPS et pare-feu.

---

## Étape 1 — Sécurisation de l'accès SSH

Objectif : n'autoriser la connexion au serveur que par clé publique, 
jamais par mot de passe et n'autoriser que les utilisateur du group remote_groups pour se connecter aux serveur.

### 1.1 Génération de la clé sur la machine hôte (PC local)
```bash
ssh-keygen -t ed25519 -C "mail@exemple.com"
```

### 1.2 Envoi de la clé publique vers le serveur
```bash
ssh-copy-id user@adresse-ip
```

### 1.3 Configuration du serveur SSH
Fichier : `/etc/ssh/sshd_config`

Port 2220
PubkeyAuthentication yes
PasswordAuthentication no
UsePAM no
AllowGroups remote_groups

### 1.4 Redémarrage du service SSH
```bash
sudo systemctl restart sshd
```

###  Vérification
Avant de couper l'ancienne session, ouvrir un **nouveau terminal** et tester :
```bash
ssh -p 2220 user@adresse-ip
```
 Ne jamais fermer la session SSH en cours avant d'avoir confirmé que 
la nouvelle connexion fonctionne — risque de se retrouver bloqué hors 
du serveur.

---

## Étape 2 — Installation et configuration de Nginx

### 2.1 Installation
```bash
sudo apt update && sudo apt install nginx -y
```

### 2.2 Build du projet React (sur la machine locale)
```bash
npm run build
```
→ Génère le dossier `dist/` (projet sous Vite).

### 2.3 Transfert du build vers le serveur
```bash
scp -r dist/* user@adresse-ip:/tmp/mon-app
```

### 2.4 Déploiement dans le dossier Nginx
```bash
sudo rm -rf /var/www/html/*
sudo cp -r /tmp/mon-app/* /var/www/html/
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
```

###  Vérification
Test en HTTP réussi sur `http://adresse-ip/`.

---

## Étape 3 — Mise en place du HTTPS (certificat auto-signé)

Le serveur étant une VM locale (pas de nom de domaine public), Let's 
Encrypt n'est pas utilisable. Un certificat auto-signé permet de 
comprendre le fonctionnement de TLS.

### 3.1 Création du dossier de stockage
```bash
sudo mkdir -p /etc/nginx/ssl/
```

### 3.2 Génération du certificat et de la clé privée
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/selfsigned.key \
  -out /etc/nginx/ssl/selfsigned.crt
```

### 3.3 Configuration Nginx
Voir le fichier [`nginx/default.conf`](../nginx/default.conf) de ce repo 
pour la configuration complète (redirection HTTP → HTTPS + bloc SSL).

### ✅ Vérification
```bash
sudo nginx -t                    # doit renvoyer "syntax is ok"
sudo systemctl restart nginx
```
Puis test sur `https://adresse-ip/` (avertissement navigateur normal 
avec un certificat auto-signé).

---

## Étape 4 — Configuration du pare-feu (UFW)

Principe appliqué : **tout bloquer par défaut, n'autoriser que le 
strict nécessaire**, plutôt que bloquer port par port.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2220/tcp     # SSH (port custom)
sudo ufw allow 80/tcp       # HTTP (nécessaire pour la redirection vers HTTPS)
sudo ufw allow 443/tcp      # HTTPS
sudo ufw enable
```

###  Vérification
```bash
sudo ufw status verbose
```



---

##  Erreurs rencontrées et corrections

| Erreur | Cause | Solution |
|---|---|---|
| Nginx refusait de démarrer | `ssl_certificate` dupliqué au lieu d'utiliser `ssl_certificate_key`, points-virgules manquants | Correction de la syntaxe, validation systématique avec `nginx -t` |
| Page blanche sur les routes React (`/projets`, etc.) | `try_files $uri $uri/ =404;` ne gère pas le routing côté client | Remplacé par `try_files $uri /index.html;` |

---

## 📚 Concepts clés appris

- **Authentification par clé SSH** : plus sécurisée qu'un mot de passe, 
  repose sur une paire clé publique/privée
- **TLS/HTTPS** : chiffrement du trafic via certificat + clé privée
- **Certificat auto-signé vs Let's Encrypt** : Let's Encrypt nécessite 
  une validation de domaine public, impossible sur une VM locale
- **Principe de moindre privilège (firewall)** : tout bloquer par 
  défaut, ouvrir uniquement ce qui est utilisé