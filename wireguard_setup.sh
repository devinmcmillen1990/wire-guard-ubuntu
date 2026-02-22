#!/bin/bash

PORT=51820
SERVER_IP="187.102.244.102"
SUBNET="10.0.0"

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

CLIENT1_PRIVATE=$(wg genkey)
CLIENT1_PUBLIC=$(echo "$CLIENT1_PRIVATE" | wg pubkey)
CLIENT2_PRIVATE=$(wg genkey)
CLIENT2_PUBLIC=$(echo "$CLIENT2_PRIVATE" | wg pubkey)

# Write server config
{
  echo "[Interface]"
  echo "Address = ${SUBNET}.1/24"
  echo "ListenPort = ${PORT}"
  echo "PrivateKey = ${SERVER_PRIVATE_KEY}"
  echo "PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
  echo "PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
  echo ""
  echo "[Peer]"
  echo "# Client 1"
  echo "PublicKey = ${CLIENT1_PUBLIC}"
  echo "AllowedIPs = ${SUBNET}.2/32"
  echo ""
  echo "[Peer]"
  echo "# Client 2"
  echo "PublicKey = ${CLIENT2_PUBLIC}"
  echo "AllowedIPs = ${SUBNET}.3/32"
} | sudo tee /etc/wireguard/wg0.conf > /dev/null

echo "==============================="
echo "SERVER CONFIG written to /etc/wireguard/wg0.conf"
echo "Server Public Key: ${SERVER_PUBLIC_KEY}"
echo "==============================="
echo ""
echo "==============================="
echo "CLIENT 1 CONFIG (use on client 1):"
echo "==============================="
echo "[Interface]"
echo "Address = ${SUBNET}.2/24"
echo "PrivateKey = ${CLIENT1_PRIVATE}"
echo "DNS = 1.1.1.1"
echo ""
echo "[Peer]"
echo "PublicKey = ${SERVER_PUBLIC_KEY}"
echo "Endpoint = ${SERVER_IP}:${PORT}"
echo "AllowedIPs = 0.0.0.0/0"
echo "PersistentKeepalive = 25"
echo ""
echo "==============================="
echo "CLIENT 2 CONFIG (use on client 2):"
echo "==============================="
echo "[Interface]"
echo "Address = ${SUBNET}.3/24"
echo "PrivateKey = ${CLIENT2_PRIVATE}"
echo "DNS = 1.1.1.1"
echo ""
echo "[Peer]"
echo "PublicKey = ${SERVER_PUBLIC_KEY}"
echo "Endpoint = ${SERVER_IP}:${PORT}"
echo "AllowedIPs = 0.0.0.0/0"
echo "PersistentKeepalive = 25"
echo ""
echo "==============================="
echo "Done! Now run: sudo systemctl restart wg-quick@wg0"
echo "==============================="
