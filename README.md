# IPv6 Auto-Config — agent.sh

Ce script permet de configurer automatiquement une adresse IPv6 publique sur une VM :  

- allocation via API (`allocate.php`)  
- application sur l’interface réseau  
- ajout de la route par défaut  
- persistance de la configuration  
- test de la connectivité  

---

## 🚀 Utilisation rapide

Une seule commande suffit :

```bash
curl -fsSL https://raw.githubusercontent.com/A
```

---

## ⚙️ Fonctionnement

1. Le script appelle ton API pour obtenir une IPv6 disponible (adresse, gateway, prefix).  
2. L’ancienne IPv6 du même `/64` est retirée.  
3. La nouvelle IPv6 est appliquée à l’interface.  
4. La route par défaut est mise à jour.  
5. La configuration est persistée dans `/etc/network/interfaces.d/ipv6.conf`.  
6. Un test de ping est exécuté pour valider la connectivité.  

---

## ✅ Prérequis

### Sur la VM
- Debian/Ubuntu avec `bash`, `curl` et `iproute2`  
- Interface réseau existante (`ens18` par défaut)  
- Paquets à installer si manquants :  

```bash
sudo apt-get update
sudo apt-get install -y iproute2 ifupdown curl ca-certificates
```

### Côté API
- `allocate.php` doit être accessible et connecté à ta base MySQL.  
- La table `ip_pool` doit contenir les IPv6 disponibles avec le champ `taken=0`.  

---

## 🐞 Débogage

- Vérifie l’interface :  
```bash
ip a
```

- Vérifie la route IPv6 :  

```bash
ip -6 route show
```

- Ping la gateway :  

```bash
ping -6 -c3 2a03:75c0:1e:8::5
```

### 🛠️ Route manuelle en cas de bug

Si la VM obtient bien une IPv6 mais que la connectivité est KO, ajoute la route par défaut à la main :

```bash
sudo ip -6 route del default || true
sudo ip -6 route add default via 2a03:75c0:1e:8::5 dev ens18
```
Remplace `ens18` par le nom de ton interface si différent.
