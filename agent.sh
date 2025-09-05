#!/usr/bin/env bash
set -euo pipefail

# ===================== CONFIG =====================
IFACE="ens19"                                # <-- on ne touche qu'à ens19
NETWORK="LAN"
API_URL="https://vodgroup.org/SH/IPV6/allocate.php"
TOKEN="VodGroupConfigIpv6TokenTempSettingAllowDBConnect"
PERSIST_FILE="/etc/network/interfaces.d/99-ipv6-ens19.conf"
# ==================================================

# Ne JAMAIS toucher à l'IPv4 ni à ens18
# (aucune commande ne cible ens18 ni l'IPv4)

HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
MAC_ADDR="$(cat /sys/class/net/${IFACE}/address 2>/dev/null || echo "00:00:00:00:00:00")"

echo ">> Interface ciblée : ${IFACE}"
ip link show "${IFACE}" >/dev/null 2>&1 || {
  echo "[ERREUR] L'interface ${IFACE} n'existe pas."
  exit 1
}

# 1) Appel API pour allocation
echo ">> Appel API d'allocation IPv6…"
RESP="$(curl -fsSL --get \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "network=${NETWORK}" \
  --data-urlencode "hostname=${HOSTNAME_FQDN}" \
  --data-urlencode "iface=${IFACE}" \
  --data-urlencode "mac=${MAC_ADDR}" \
  "${API_URL}"
)"

IP6="$(echo "${RESP}" | sed -n 's/^ip=\(.*\)$/\1/p')"
GW6="$(echo "${RESP}" | sed -n 's/^gateway=\(.*\)$/\1/p')"
PLEN="$(echo "${RESP}" | sed -n 's/^prefix_len=\(.*\)$/\1/p')"
OK="$(echo "${RESP}" | sed -n 's/^ok=\(.*\)$/\1/p')"

if [[ -z "${IP6}" || -z "${GW6}" || -z "${PLEN}" || "${OK}" != "1" ]]; then
  echo "[ERREUR] Allocation échouée."
  echo "Réponse brute API :"
  echo "${RESP}"
  exit 2
fi

echo ">> IPv6 allouée: ${IP6}/${PLEN} | GW: ${GW6} | IF: ${IFACE}"

# 2) Stopper d'éventuels clients DHCPv6 sur ens19 (non bloquant)
if command -v dhclient >/dev/null 2>&1; then
  dhclient -6 -r "${IFACE}" >/dev/null 2>&1 || true
  pkill -f "dhclient.*${IFACE}" >/dev/null 2>&1 || true
fi

# 3) Désactiver l'autoconf/RA côté kernel pour ens19 (runtime)
sysctl -w "net.ipv6.conf.${IFACE}.accept_ra=0" >/dev/null
sysctl -w "net.ipv6.conf.${IFACE}.autoconf=0"  >/dev/null

# 4) Nettoyage des anciennes IPv6 GLOBALES sur ens19 (on garde le fe80::/64)
echo ">> Nettoyage des anciennes IPv6 globales sur ${IFACE}…"
while read -r CIDR; do
  ADDR="${CIDR%/*}"
  [[ "${ADDR}" == fe80::* ]] && continue
  echo "   - suppression ${CIDR}"
  ip -6 addr del "${CIDR}" dev "${IFACE}" || true
done < <(ip -6 addr show dev "${IFACE}" | awk '/inet6/ && $3=="global" {print $2}')

# 5) Application IPv6 + route par défaut (liée à ens19 uniquement)
echo ">> Application ${IP6}/${PLEN} sur ${IFACE}"
ip -6 addr add "${IP6}/${PLEN}" dev "${IFACE}"

# Supprimer une éventuelle default v6 sur ENS19 seulement
ip -6 route del default dev "${IFACE}" 2>/dev/null || true
ip -6 route add default via "${GW6}" dev "${IFACE}"

# 6) Persistance (/etc/network/interfaces.d/…)
echo ">> Écriture persistance : ${PERSIST_FILE}"
mkdir -p "$(dirname "${PERSIST_FILE}")"
cat > "${PERSIST_FILE}" <<EOF
# Fichier généré automatiquement - IPv6 statique ENS19 (ne touche pas à IPv4/ENS18)
auto ${IFACE}
iface ${IFACE} inet6 static
    address ${IP6}/${PLEN}
    gateway ${GW6}
    accept_ra 0
    autoconf 0
EOF

# 7) (Optionnel) Remonter l'interface pour appliquer proprement
#    Commenté pour éviter une coupure ; décommente si besoin.
# ifdown ${IFACE} 2>/dev/null || true
# ifup ${IFACE}

# 8) Test de connectivité
echo ">> Test ping vers 2001:4860:4860::8888"
if ping -6 -c2 -W2 2001:4860:4860::8888 >/dev/null 2>&1; then
  echo "[OK] IPv6 opérationnelle"
else
  echo "[ATTENTION] IPv6 KO (vérifie route/DNS/pare-feu/opnsense)"
fi

echo ">> Terminé. (ENS18/IPv4 inchangés)"
