#!/usr/bin/env bash
set -euo pipefail

# ===================== CONFIG =====================
IFACE_WAN="ens19"                 # interface PUBLIQUE (WAN)
IFACE_LAN="ens18"                 # interface LAN (jamais modifiée par ce script)
NETWORK="LAN"
API_URL="https://vodgroup.org/SH/IPV6/allocate.php"
TOKEN="VodGroupConfigIpv6TokenTempSettingAllowDBConnect"
PERSIST_FILE="/etc/network/interfaces.d/ipv6-${IFACE_WAN}.conf"  # persistance ifupdown
SYSCTL_FILE="/etc/sysctl.d/99-ipv6-${IFACE_WAN}.conf"
# ===================================================

info()  { echo -e "\e[1;36m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[1;32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[1;33m[ATTN]\e[0m $*"; }
err()   { echo -e "\e[1;31m[ERREUR]\e[0m $*"; }

# 0) Pré-checks
if ! command -v ip >/dev/null 2>&1; then
  err "iproute2 manquant."
  exit 1
fi

if ! ip link show dev "${IFACE_WAN}" >/dev/null 2>&1; then
  err "L’interface ${IFACE_WAN} n’existe pas. Modifie IFACE_WAN en tête de script."
  exit 1
fi

HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
MAC_WAN="$(cat /sys/class/net/${IFACE_WAN}/address 2>/dev/null || echo "00:00:00:00:00:00")"

# 1) Appel API pour allocation
info "Appel API pour allocation IPv6 publique…"
RESP="$(curl -fsSL --get \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "network=${NETWORK}" \
  --data-urlencode "hostname=${HOSTNAME_FQDN}" \
  --data-urlencode "iface=${IFACE_WAN}" \
  --data-urlencode "mac=${MAC_WAN}" \
  "${API_URL}" || true
)"

IP6="$(echo "${RESP}" | sed -n 's/^ip=\(.*\)$/\1/p')"
GW6="$(echo "${RESP}" | sed -n 's/^gateway=\(.*\)$/\1/p')"
PLEN="$(echo "${RESP}" | sed -n 's/^prefix_len=\(.*\)$/\1/p')"
OKF="$(echo "${RESP}" | sed -n 's/^ok=\(.*\)$/\1/p')"

if [[ -z "${IP6}" || -z "${GW6}" || -z "${PLEN}" || "${OKF}" != "1" ]]; then
  err "Allocation échouée. Réponse brute API :"; echo "----"; echo "${RESP}"; echo "----"
  exit 2
fi

ok "IPv6 allouée: ${IP6}/${PLEN} | GW: ${GW6} | IF: ${IFACE_WAN}"

# 2) S’assurer que l’interface WAN est UP
ip link set "${IFACE_WAN}" up || true

# 3) Purge des anciennes IPv6 **uniquement** sur l’interface WAN
info "Nettoyage des anciennes IPv6 GLOBAL sur ${IFACE_WAN}…"
while read -r addr ; do
  [[ -z "${addr}" ]] && continue
  info " - suppression ${addr}"
  ip -6 addr del "${addr}" dev "${IFACE_WAN}" || true
done < <(ip -6 addr show dev "${IFACE_WAN}" | awk '/scope global/ {print $2}')

# 4) Application de la nouvelle IPv6 et de la route
info "Application de l’IPv6 ${IP6}/${PLEN} sur ${IFACE_WAN}…"
ip -6 addr add "${IP6}/${PLEN}" dev "${IFACE_WAN}"

# on remplace la route par défaut v6, et on force onlink (utile quand le voisin ne répond pas encore)
ip -6 route del default dev "${IFACE_WAN}" 2>/dev/null || true
ip -6 route replace default via "${GW6}" dev "${IFACE_WAN}" metric 1 onlink

# 5) Désactiver l’autoconf/SLAAC uniquement sur l’interface WAN (persistant)
info "Désactivation SLAAC/temp-addr sur ${IFACE_WAN} (persistant)…"
mkdir -p /etc/sysctl.d
cat > "${SYSCTL_FILE}" <<EOF
net.ipv6.conf.${IFACE_WAN}.accept_ra = 0
net.ipv6.conf.${IFACE_WAN}.autoconf   = 0
net.ipv6.conf.${IFACE_WAN}.use_tempaddr = 0
EOF
sysctl -p "${SYSCTL_FILE}" >/dev/null || true

# 6) Persistance ifupdown (NE TOUCHE PAS ens18)
info "Écriture de la persistance ifupdown : ${PERSIST_FILE}"
mkdir -p "$(dirname "${PERSIST_FILE}")"
cat > "${PERSIST_FILE}" <<EOF
# Généré automatiquement – IPv6 WAN ONLY
auto ${IFACE_WAN}
iface ${IFACE_WAN} inet6 static
    address ${IP6}/${PLEN}
    gateway ${GW6}
    accept_ra 0
EOF

# 7) Tests de connectivité IPv6
info "Tests IPv6…"
if ping -6 -c2 -W2 "${GW6}" >/dev/null 2>&1; then
  ok "Passerelle joignable (${GW6})"
else
  warn "La passerelle IPv6 ne répond pas au ping (possiblement filtrée)."
fi

if ping -6 -c3 -W2 2001:4860:4860::8888 >/dev/null 2>&1; then
  ok "Résolution/chemin IPv6 vers l’extérieur OK (8.8.8.8 v6)"
else
  warn "Ping 2001:4860:4860::8888 KO. Vérifie route upstream/pare-feu."
fi

ok "Configuration terminée. Aucune modification faite sur ${IFACE_LAN} (LAN/IPv4)."
