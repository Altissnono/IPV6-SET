#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ICI (modifie si besoin) ===
IFACE="ens18"
NETWORK="LAN"
API_URL="https://vodgroup.org/SH/IPV6/allocate.php"
TOKEN="VodGroupConfigIpv6TokenTempSettingAllowDBConnect"
PERSIST_FILE="/etc/network/interfaces.d/ipv6.conf"
# ======================================

HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
MAC_ADDR="$(cat /sys/class/net/${IFACE}/address 2>/dev/null || echo "00:00:00:00:00:00")"

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
  echo "Allocation échouée. Réponse brute:"
  echo "${RESP}"
  exit 2
fi

echo ">> IPv6 allouée: ${IP6}/${PLEN} | GW: ${GW6} | IF: ${IFACE}"

# Nettoyage
for a in $(ip -6 addr show dev "${IFACE}" | awk '/global/ {print $2}'); do
  case "${a%/*}" in
    2a03:75c0:1e:8::*) echo "Retrait ancienne IPv6 ${a}"; ip -6 addr del "${a}" dev "${IFACE}" || true;;
  esac
done

# Applique
ip -6 addr add "${IP6}/${PLEN}" dev "${IFACE}"
ip -6 route del default 2>/dev/null || true
ip -6 route add default via "${GW6}" dev "${IFACE}"

# Persistance
mkdir -p "$(dirname "${PERSIST_FILE}")"
cat > "${PERSIST_FILE}" <<EOF
# Généré par agent.sh
auto ${IFACE}
iface ${IFACE} inet6 static
    address ${IP6}/${PLEN}
    gateway ${GW6}
    accept_ra 0
EOF

ping -6 -c2 -W2 2001:4860:4860::8888 >/dev/null 2>&1 && echo "[OK] IPv6 opérationnelle" || echo "[ATTENTION] IPv6 KO"
