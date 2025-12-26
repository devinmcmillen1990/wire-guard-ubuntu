#!/usr/bin/env bash
set -euo pipefail

# Simple WireGuard server + single client setup
# Tested conceptually for Ubuntu/Debian-like systems.

WG_IFACE="wg0"
WG_PORT="${WG_PORT:-51820}"
WG_NET="10.8.0.0/24"
WG_SERVER_IP="10.8.0.1"
WG_CLIENT_IP="10.8.0.2"
WG_DIR="/etc/wireguard"
SERVER_PRIV_KEY_FILE="${WG_DIR}/server_private.key"
SERVER_PUB_KEY_FILE="${WG_DIR}/server_public.key"
CLIENT_PRIV_KEY_FILE="${WG_DIR}/client_private.key"
CLIENT_PUB_KEY_FILE="${WG_DIR}/client_public.key"
CLIENT_CONF_FILE="${WG_DIR}/client.conf"

# Detect the main outgoing interface (best-effort)
detect_main_iface() {
  local dev
  if dev=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1); exit}'); then
    echo "$dev"
  else
    echo "eth0"
  fi
}

main_iface=$(detect_main_iface)

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

echo "=== Updating packages and installing WireGuard ==="
apt-get update -y
apt-get install -y wireguard iproute2 iptables

mkdir -p "${WG_DIR}"
chmod 700 "${WG_DIR}"

echo "=== Generating server keys ==="
umask 077
wg genkey | tee "${SERVER_PRIV_KEY_FILE}" | wg pubkey > "${SERVER_PUB_KEY_FILE}"

echo "=== Generating client keys ==="
wg genkey | tee "${CLIENT_PRIV_KEY_FILE}" | wg pubkey > "${CLIENT_PUB_KEY_FILE}"

SERVER_PRIV_KEY=$(cat "${SERVER_PRIV_KEY_FILE}")
SERVER_PUB_KEY=$(cat "${SERVER_PUB_KEY_FILE}")
CLIENT_PRIV_KEY=$(cat "${CLIENT_PRIV_KEY_FILE}")
CLIENT_PUB_KEY=$(cat "${CLIENT_PUB_KEY_FILE}")

# Get public IP (basic method)
PUBLIC_IP=$(curl -4s https://ifconfig.co || curl -4s https://ipv4.icanhazip.com || echo "YOUR_SERVER_IP")

echo "=== Enabling IP forwarding ==="
sysctl -w net.ipv4.ip_forward=1 >/dev/null
if ! grep -q "net.ipv4.ip_forward" /etc/sysctl.conf 2>/dev/null; then
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
else
  sed -i 's/^net\.ipv4\.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
fi

echo "=== Writing server config to ${WG_DIR}/${WG_IFACE}.conf ==="
cat > "${WG_DIR}/${WG_IFACE}.conf" <<EOF
[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV_KEY}

# NAT VPN subnet out via main interface
PostUp = iptables -t nat -A POSTROUTING -s ${WG_NET} -o ${main_iface} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s ${WG_NET} -o ${main_iface} -j MASQUERADE

[Peer]
# Client peer
PublicKey = ${CLIENT_PUB_KEY}
AllowedIPs = ${WG_CLIENT_IP}/32
EOF

chmod 600 "${WG_DIR}/${WG_IFACE}.conf"

echo "=== Starting and enabling WireGuard (${WG_IFACE}) ==="
systemctl enable "wg-quick@${WG_IFACE}"
systemctl restart "wg-quick@${WG_IFACE}"

echo "=== Creating client config at ${CLIENT_CONF_FILE} ==="
cat > "${CLIENT_CONF_FILE}" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${WG_CLIENT_IP}/32
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${PUBLIC_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "${CLIENT_CONF_FILE}"

echo
echo "=== DONE ==="
echo "Server interface: ${WG_IFACE}"
echo "Public IP (guessed): ${PUBLIC_IP}"
echo
echo "Client config written to: ${CLIENT_CONF_FILE}"
echo "You can display it with:"
echo "  sudo cat ${CLIENT_CONF_FILE}"
echo
echo "Import this config into your WireGuard client app."
echo
