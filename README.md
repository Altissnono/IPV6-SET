IPv6 Auto-Config — agent.sh

Ce script permet de configurer automatiquement une IPv6 publique sur une VM :

allocation via API (allocate.php),

application sur l’interface réseau,

ajout de la route par défaut,

persistance de la configuration,

test de la connectivité.

🚀 Utilisation rapide

Une seule commande suffit :

curl -fsSL https://raw.githubusercontent.com/Altissnono/IPV6-SET/main/agent.sh | sudo bash

📦 Fonctionnement

Le script appelle ton API pour obtenir une IPv6 disponible, la gateway et le prefix length.

L’ancienne IPv6 du même /64 est retirée.

L’IPv6 est appliquée à l’interface.

La route par défaut est mise à jour.

Une configuration persistante est écrite dans /etc/network/interfaces.d/ipv6.conf.

Un test de ping IPv6 est lancé (Google DNS 2001:4860:4860::8888).

✅ Prérequis
Sur la VM

Debian/Ubuntu avec iproute2, ifupdown, curl, ca-certificates.

sudo apt-get install -y iproute2 ifupdown curl ca-certificates


Interface réseau correcte (ens18 par défaut dans le script).

Côté serveur API

Fichier allocate.php corrigé (séparer les SET SQL).

Procédure MySQL allocate_ip_from_pool et table ip_pool bien peuplées.

🧪 Vérifications
Voir l’IPv6 appliquée
ip -6 addr show dev ens18

Vérifier la route
ip -6 route

Tester la connectivité
ping -6 -c3 2001:4860:4860::8888
ping -6 -c3 google.com

🛠️ Dépannage
Erreur curl: (22) … 500

Ton API renvoie une erreur.
Test direct :

curl -v "https://vodgroup.org/SH/IPV6/allocate.php?token=XXXX&network=LAN&hostname=test&iface=ens18&mac=00:11:22:33:44:55"


Si error=SQL syntax → corriger allocate.php.

Vérifie les logs PHP (error_log).

L’IP est appliquée mais Internet IPv6 ne marche pas

Vérifie la gateway :

ping -6 -c3 2a03:75c0:1e:8::5


Si la gateway répond mais pas Internet → problème OPNsense :

Firewall IPv6 (autoriser LAN → any).

Gateway IPv6 configurée dans System > Routing.

Pas de NAT en IPv6.

Test depuis OPNsense :

ping6 -c3 2001:4860:4860::8888

: nom d’option non valable

Le fichier téléchargé contient des fins de lignes Windows (CRLF).
Solution immédiate :

curl -fsSL URL | sed 's/\r$//' | sudo bash


Solution propre : uploader agent.sh en UTF-8 + LF (Unix).

ip: command not found

Installer iproute2 :

sudo apt-get install -y iproute2

Supprimer l’IPv6 et libérer dans la DB

Supprimer sur la VM :

ip -6 addr flush dev ens18
ip -6 route del default || true
rm -f /etc/network/interfaces.d/ipv6.conf
systemctl reload networking || true


Libérer côté DB :

CALL release_ip('LAN','2a03:75c0:1e:8::3e8');

🔧 Personnalisation

Interface : modifier IFACE="ens18" dans le script.

Réseau logique : NETWORK="LAN".

Persistance : /etc/network/interfaces.d/ipv6.conf (modifiable).

Source du script : héberger sur GitHub/GitLab (utiliser le lien Raw).

🔒 Sécurité

Le TOKEN doit rester secret.

Utilise uniquement HTTPS.

Si possible, restreindre l’accès API par IP (firewall ou logique PHP).
