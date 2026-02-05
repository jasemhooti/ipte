#!/bin/bash

# WireGuard Tunnel Setup - Iran + Foreign (کلیدها واضح نمایش داده می‌شن)
# نسخه 2 - نمایش فوری کلیدها

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[1;31mاین اسکریپت باید با sudo اجرا بشه!\033[0m"
    exit 1
fi

# نصب WireGuard اگر نباشه
apt update -qq && apt install -y wireguard qrencode jq 2>/dev/null || true

echo -e "\n\033[1;36m=== راه‌اندازی تونل WireGuard (ایران ↔ خارج) ===\033[0m"
echo "روی کدوم سرور هستی؟"
echo "1) سرور خارج (سرور WireGuard - اینترنت آزاد)"
echo "2) سرور ایران (کلاینت - اینترنت محدود)"
read -p "انتخاب کن (1 یا 2): " choice

INTERFACE="wg0"
PORT=51820          # می‌تونی بعداً عوض کنی (مثلاً 443، 53، 1194)
WG_DIR="/etc/wireguard"

mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

if [ "$choice" = "1" ]; then
    # ============== سرور خارج (سرور) ==============
    echo -e "\n\033[1;32mسرور خارج انتخاب شد (سرور WireGuard)\033[0m"

    read -p "IP عمومی این سرور (خارج): " SERVER_PUB_IP

    # ساخت کلیدها
    SERVER_PRIVKEY=$(wg genkey)
    SERVER_PUBKEY=$(echo "$SERVER_PRIVKEY" | wg pubkey)

    echo "$SERVER_PRIVKEY" > "$WG_DIR/server_private.key"
    echo "$SERVER_PUBKEY" > "$WG_DIR/server_public.key"
    chmod 600 "$WG_DIR/server_private.key"

    echo -e "\n\033[1;33m=== کلیدهای سرور خارج ===\033[0m"
    echo -e "\033[1;35mکلید خصوصی سرور (Private Key):\033[0m"
    echo -e "\033[1;37m$SERVER_PRIVKEY\033[0m"
    echo "این کلید رو **هرگز** به کسی نشون نده! فقط روی همین سرور استفاده می‌شه."

    echo -e "\n\033[1;32mکلید عمومی سرور (Public Key):\033[0m"
    echo -e "\033[1;37m$SERVER_PUBKEY\033[0m"
    echo "این کلید رو **کپی کن** و بده به سرور ایران (کلاینت)."

    # تنظیم کانفیگ سرور
    cat > "$WG_DIR/$INTERFACE.conf" << EOF
[Interface]
Address = 10.66.66.1/24
PrivateKey = $SERVER_PRIVKEY
ListenPort = $PORT
PostUp   = iptables -A FORWARD -i $INTERFACE -j ACCEPT; iptables -A FORWARD -o $INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i $INTERFACE -j ACCEPT; iptables -D FORWARD -o $INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# بعداً اینجا Peer کلاینت ایران اضافه می‌شه
EOF

    # فعال‌سازی فورواردینگ
    echo 'net.ipv4.ip_forward=1' | tee -a /etc/sysctl.conf
    sysctl -p

    wg-quick up $INTERFACE || true
    systemctl enable wg-quick@$INTERFACE 2>/dev/null || true

    echo -e "\n\033[1;36mسرور آماده است.\033[0m"
    echo "حالا برو روی سرور ایران اسکریپت رو اجرا کن و این کلید عمومی رو بهش بده."
    echo "بعد از اینکه کلید عمومی ایران رو گرفتی، این دستور رو روی این سرور بزن تا Peer اضافه بشه:"
    echo "echo '[Peer]' >> $WG_DIR/$INTERFACE.conf"
    echo "echo 'PublicKey = <کلید عمومی ایران>' >> $WG_DIR/$INTERFACE.conf"
    echo "echo 'AllowedIPs = 10.66.66.2/32' >> $WG_DIR/$INTERFACE.conf"
    echo "wg-quick down $INTERFACE && wg-quick up $INTERFACE"

elif [ "$choice" = "2" ]; then
    # ============== سرور ایران (کلاینت) ==============
    echo -e "\n\033[1;32mسرور ایران انتخاب شد (کلاینت WireGuard)\033[0m"

    read -p "IP عمومی سرور خارج: " SERVER_PUB_IP
    read -p "پورت WireGuard روی سرور خارج (معمولاً 51820): " PORT
    read -p "کلید عمومی سرور خارج (Public Key): " SERVER_PUBKEY

    # ساخت کلیدهای کلاینت
    CLIENT_PRIVKEY=$(wg genkey)
    CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | wg pubkey)

    echo "$CLIENT_PRIVKEY" > "$WG_DIR/client_private.key"
    echo "$CLIENT_PUBKEY" > "$WG_DIR/client_public.key"
    chmod 600 "$WG_DIR/client_private.key"

    echo -e "\n\033[1;33m=== کلیدهای کلاینت ایران ===\033[0m"
    echo -e "\033[1;35mکلید خصوصی کلاینت (Private Key):\033[0m"
    echo -e "\033[1;37m$CLIENT_PRIVKEY\033[0m"
    echo "این کلید رو **هرگز** به کسی نده! فقط روی همین سرور استفاده می‌شه."

    echo -e "\n\033[1;32mکلید عمومی کلاینت (Public Key):\033[0m"
    echo -e "\033[1;37m$CLIENT_PUBKEY\033[0m"
    echo "این کلید رو **کپی کن** و بده به سرور خارج (تا Peer اضافه کنه)."

    # تنظیم کانفیگ کلاینت
    cat > "$WG_DIR/$INTERFACE.conf" << EOF
[Interface]
Address = 10.66.66.2/24
PrivateKey = $CLIENT_PRIVKEY
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBKEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $SERVER_PUB_IP:$PORT
PersistentKeepalive = 25
EOF

    wg-quick up $INTERFACE || true
    systemctl enable wg-quick@$INTERFACE 2>/dev/null || true

    echo -e "\n\033[1;36mتونل روی ایران راه افتاد.\033[0m"
    echo "تست کن:"
    echo "  ping 10.66.66.1          # به سرور خارج"
    echo "  curl ifconfig.me         # باید IP خارج رو نشون بده"
    echo "  ping 8.8.8.8"

    echo -e "\nکلید عمومی کلاینت رو بده به سرور خارج تا تونل کامل بشه."

else
    echo -e "\033[1;31mفقط 1 یا 2 انتخاب کن!\033[0m"
    exit 1
fi

echo -e "\n\033[1;33mلاگ برای چک کردن:\033[0m journalctl -u wg-quick@wg0 -f"
echo -e "خاموش کردن تونل: wg-quick down wg0"
echo -e "وضعیت: wg show"EOF

    sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

    wg-quick up $INTERFACE
    systemctl enable wg-quick@$INTERFACE

    echo "کلید عمومی سرور: $(cat /etc/wireguard/public.key)"
    echo "این کلید رو برای سرور ایران کپی کن"

elif [ "$choice" = "1" ]; then
    # سرور ایران (کلاینت WG)
    echo "سرور ایران انتخاب شد."

    read -p "IP عمومی سرور خارج: " SERVER_PUB_IP
    read -p "پورت WireGuard روی سرور خارج (معمولاً 51820): " PORT
    read -p "کلید عمومی سرور خارج: " SERVER_PUBKEY

    wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key

    CLIENT_PRIVKEY=$(cat /etc/wireguard/private.key)
    CLIENT_PUBKEY=$(cat /etc/wireguard/public.key)

    cat << EOF > /etc/wireguard/$INTERFACE.conf
[Interface]
Address = 10.66.66.2/24
PrivateKey = $CLIENT_PRIVKEY
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBKEY
AllowedIPs = 0.0.0.0/0
Endpoint = $SERVER_PUB_IP:$PORT
PersistentKeepalive = 25
EOF

    # روی سرور خارج این بخش رو اضافه کن (Peer کلاینت)
    echo ""
    echo "روی سرور خارج این خطوط رو به آخر فایل /etc/wireguard/wg0.conf اضافه کن و wg-quick down wg0 && wg-quick up wg0 بزن:"
    echo "[Peer]"
    echo "PublicKey = $CLIENT_PUBKEY"
    echo "AllowedIPs = 10.66.66.2/32"

    wg-quick up $INTERFACE
    systemctl enable wg-quick@$INTERFACE

    echo "تونل بالا اومد. تست: ping 10.66.66.1"
    echo "تست اینترنت: ping 8.8.8.8 یا curl ifconfig.me"

else
    echo "فقط 1 یا 2"
    exit 1
fi

echo "لاگ: journalctl -u wg-quick@wg0 -f"
echo "خاموش کردن: wg-quick down wg0"
