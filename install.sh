#!/bin/bash

# WireGuard Client Setup for Iran Server
# کلیدها اول ساخته و نمایش داده می‌شن

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[1;31mبا sudo اجرا کن!\033[0m"
    exit 1
fi

# نصب اگر لازم باشه
apt update -qq && apt install -y wireguard qrencode 2>/dev/null || true

echo -e "\n\033[1;36m=== راه‌اندازی WireGuard روی سرور ایران (کلاینت) ===\033[0m"

INTERFACE="wg0"
PORT_DEFAULT=51820
WG_DIR="/etc/wireguard"

mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

# اول کلیدهای کلاینت رو بساز و نمایش بده
echo -e "\n\033[1;33mساخت کلیدها برای سرور ایران ...\033[0m"

CLIENT_PRIVKEY=$(wg genkey)
CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | wg pubkey)

echo "$CLIENT_PRIVKEY" > "$WG_DIR/client_private.key"
echo "$CLIENT_PUBKEY" > "$WG_DIR/client_public.key"
chmod 600 "$WG_DIR/client_private.key"

echo -e "\n\033[1;41m=================== خیلی مهم ===================\033[0m"
echo -e "\033[1;33mکلید خصوصی کلاینت (Private Key) - فقط روی این سرور بمونه:\033[0m"
echo -e "\033[1;37m$CLIENT_PRIVKEY\033[0m"
echo ""
echo -e "\033[1;32mکلید عمومی کلاینت (Public Key) - اینو کپی کن و بده به سرور خارج:\033[0m"
echo -e "\033[1;37;4m$CLIENT_PUBKEY\033[0m"
echo -e "\033[1;41m==================================================\033[0m"
echo -e "\033[1;33mاین کلید عمومی رو حتماً جایی امن کپی کن و به سرور خارج بفرست تا Peer اضافه کنه.\033[0m"
echo ""

# حالا ورودی‌های لازم رو بگیر
read -p "IP عمومی سرور خارج: " SERVER_PUB_IP

while true; do
    read -p "پورت WireGuard روی سرور خارج (معمولاً $PORT_DEFAULT): " PORT
    PORT=${PORT:-$PORT_DEFAULT}
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        break
    else
        echo -e "\033[1;31mپورت باید عدد بین 1 تا 65535 باشه!\033[0m"
    fi
done

read -p "کلید عمومی سرور خارج (Public Key): " SERVER_PUBKEY

# ساخت کانفیگ کلاینت
cat > "$WG_DIR/$INTERFACE.conf" << EOF
[Interface]
Address = 10.66.66.2/24
PrivateKey = $CLIENT_PRIVKEY
DNS = 8.8.8.8, 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = $SERVER_PUBKEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $SERVER_PUB_IP:$PORT
PersistentKeepalive = 25
EOF

# فعال‌سازی IP forwarding (برای روتینگ بهتر)
echo 'net.ipv4.ip_forward=1' | tee -a /etc/sysctl.conf
sysctl -p >/dev/null

# بالا آوردن تونل
wg-quick up $INTERFACE || true
systemctl enable wg-quick@$INTERFACE 2>/dev/null || true

echo -e "\n\033[1;32mتونل راه‌اندازی شد!\033[0m"
echo "تست‌های زیر رو انجام بده:"
echo "  wg show                  # وضعیت تونل و handshake"
echo "  ping 10.66.66.1          # به سرور خارج"
echo "  curl ifconfig.me         # باید IP سرور خارج رو نشون بده"
echo "  ping 8.8.8.8             # اینترنت آزاد"

echo -e "\n\033[1;33mلاگ چک کن:\033[0m journalctl -u wg-quick@wg0 -f"
echo "خاموش کردن: wg-quick down wg0"
echo ""
echo -e "\033[1;33mیادت باشه:\033[0m کلید عمومی کلاینت رو حتماً به سرور خارج بده تا تونل کامل بشه (Peer اضافه کنه)."
