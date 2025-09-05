#!/usr/bin/env bash
set -euo pipefail

# ===================== CONFIG =====================
WAN_IFACE="ens19"                              # Interface WAN pour IPv6 publique
LAN_IFACE="ens18"                              # Interface LAN -> garder IPv4 uniquement
NETWORK="LAN"
API_URL="https://vodgroup.org/SH/IPV6/allocate.php"
TOKEN="VodGroupConfigIpv6TokenTempSettingAllowDBConnect"
PERSIST_FILE="/etc/network/interfaces.d/99-ipv6-${WAN_IFACE}.conf"
SYSCTL_FILE="/etc/sysctl.d/99-no-ipv6-${LAN_IFACE}.conf"
# ==================================================

HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
WAN_MAC="$(cat /sys/class/net/${WAN_IFACE}/address 2>/dev/null || echo "00:00:00:00:00:00")"

echo "==> Désactivation de l’IPv6 auto sur ${LAN_IFACE} (on garde l’IPv4 DHCP)"
sysctl -w "net.ipv6.conf.${LAN_IFACE}.accept_ra=0" >/dev/null || true
sysctl -w "net.ipv6.conf.${LAN_IFACE}.autoconf=0"  >/dev/null || true
# persistance kernel
mkdir -p /etc/sysctl.d
cat > "${SYSCTL_FILE}" <<EOF
net.ipv6.conf.${LAN_IFACE}.accept_ra = 0
net.ipv6.conf.${LAN_IFACE}.autoconf  = 0
EOF
sysctl --system >/dev/null || true

# purge toutes les IPv6 globales qui auraient été ajoutées automatiquement sur le LAN
for a in $(ip -6 addr show dev "${LAN_IFACE}" | awk '/global/ {print $2}'); do
  echo "   - suppression IPv6 ${a} sur ${LAN_IFACE}"
  ip -6 addr del "${a}" dev "${LAN_IFACE}" || true
done

echo "==> Appel API pour l’allocation IPv6 publique…"
RESP="$(curl -fsSL --get \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "network=${NETWORK}" \
  --data-urlencode "hostname=${HOSTNAME_FQDN}" \
  --data-urlencode "iface=${WAN_IFACE}" \
  --data-urlencode "mac=${WAN_MAC}" \
  "${API_URL}"
)"

IP6="$(echo "${RESP}" | sed -n 's/^ip=\(.*\)$/\1/p')"
GW6="$(echo "${RESP}" | sed -n 's/^gateway=\(.*\)$/\1/p')"
PLEN="$(echo "${RESP}" | sed -n 's/^prefix_len=\(.*\)$/\1/p')"
OK="$(echo "${RESP}" | sed -n 's/^ok=\(.*\)$/\1/p')"

if [[ -z "${IP6}" || -z "${GW6}" || -z "${PLEN}" || "${OK}" != "1" ]]; then
  echo "[ERREUR] Allocation échouée"
  echo "Réponse brute API :"
  echo "${RESP}"
  exit 2
fi

echo "==> IPv6 allouée: ${IP6}/${PLEN} | GW: ${GW6} | IF: ${WAN_IFACE}"

echo "==> Purge des anciennes IPv6 globales sur ${WAN_IFACE}"
for a in $(ip -6 addr show dev "${WAN_IFACE}" | awk '/global/ {print $2}'); do
  echo "   - suppression ${a}"
  ip -6 addr del "${a}" dev "${WAN_IFACE}" || true
done

echo "==> Application de l’IPv6 sur ${WAN_IFACE}"
ip link set "${WAN_IFACE}" up || true
ip -6 addr add "${IP6}/${PLEN}" dev "${WAN_IFACE}"
ip -6 route flush dev "${WAN_IFACE}" || true
ip -6 route del default 2>/dev/null || true
ip -6 route add default via "${GW6}" dev "${WAN_IFACE}"

echo "==> Persistance ifupdown"
mkdir -p "$(dirname "${PERSIST_FILE}")"
cat > "${PERSIST_FILE}" <<EOF
# IPv6 statique automatique - généré (ne touche pas à l'IPv4)
auto ${WAN_IFACE}
iface ${WAN_IFACE} inet6 static
    address ${IP6}/${PLEN}
    gateway ${GW6}
    accept_ra 0
    autoconf 0

# LAN - pas d’IPv6 (IPv4 DHCP conservée)
iface ${LAN_IFACE} inet6 manual
    accept_ra 0
    autoconf 0
EOF

# === Redémarrage contrôlé de l’interface WAN ===
echo "==> Redémarrage de ${WAN_IFACE} pour appliquer proprement la conf"
if command -v ifdown >/dev/null 2>&1 && command -v ifup >/dev/null 2>&1; then
  # on n’utilise pas --force pour éviter les surprises si l’interface n’était pas « connue »
  ifdown "${WAN_IFACE}" 2>/dev/null || true
  ifup   "${WAN_IFACE}" || true
else
  # fallback « ip » si ifupdown n’est pas dispo
  ip link set "${WAN_IFACE}" down || true
  sleep 1
  ip link set "${WAN_IFACE}" up   || true
fi

echo "==> Test de connectivité IPv6"
if ping -6 -c2 -W2 2001:4860:4860::8888 >/dev/null 2>&1; then
  echo "[OK] IPv6 fonctionnelle"
else
  echo "[ATTENTION] IPv6 KO (vérifie route/pare-feu/opnsense)"
fi

echo "==> Fini."
