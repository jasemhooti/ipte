#!/bin/bash

# WireGuard Tunnel Setup - ایران و خارج (یک اسکریپت مشترک)
# کلیدها اول ساخته و نمایش داده می‌شن

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[1;31mاین اسکریپت باید با sudo اجرا شود!\033[0m"
    exit 1
fi

# نصب پکیج‌های لازم
apt update -qq && apt install -y wireguard qrencode 2>/dev/null || true

echo -e "\n\033[1;36m=== راه‌اندازی تونل WireGuard (ایران ↔ خارج) ===\033[0m"
echo ""
echo "روی کدوم سرور هستی؟"
echo "1) سرور خارج (سرور WireGuard - اینترنت آزاد)"
echo "2) سرور ایران (کلاینت - اینترنت محدود)"
read -p "انتخاب کن (1 یا 2): " choice

INTERFACE="wg0"
PORT_DEFAULT=51820
WG_DIR="/etc/wireguard"

mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

if [ "$choice" = "1" ]; then
    # ──────────────────────────────
    #        سرور خارج (سرور)
    # ──────────────────────────────

    echo -e "\n\033[1;42m سرور خارج انتخاب شد (سرور WireGuard) \033[0m"

    read -p "IP عمومی این سرور (خارج): " SERVER_PUB_IP

    # ساخت کلیدها
    echo -e "\n\033[1;33mساخت کلیدها ...\033[0m"
    SERVER_PRIVKEY=$(wg genkey)
    SERVER_PUBKEY=$(echo "$SERVER_PRIVKEY" | wg pubkey)

    echo "$SERVER_PRIVKEY" > "$WG_DIR/server_private.key"
    echo "$SERVER_PUBKEY" > "$WG_DIR/server_public.key"
    chmod 600 "$WG_DIR/server_private.key"

    # نمایش کلیدها با تأکید زیاد
    echo -e "\n\033[1;41m=================== خیلی مهم ===================\033[0m"
    echo -e "\033[1;33mکلید خصوصی سرور (فقط روی این سرور بماند):\033[0m"
    echo -e "\033[1;37m$SERVER_PRIVKEY\033[0m\n"
    
    echo -e "\033[1;42mکلید عمومی سرور (این را کپی کن و بده به سرور ایران):\033[0m"
    echo -e "\033[1;37;4m$SERVER_PUBKEY\033[0m"
    echo -e "\033[1;41m==================================================\033[0m\n"

    # ساخت کانفیگ سرور
    cat > "$WG_DIR/$INTERFACE.conf" << EOF
[Interface]
Address = 10.66.66.1/24
PrivateKey = $SERVER_PRIVKEY
ListenPort = $PORT_DEFAULT
PostUp   = iptables -A FORWARD -i $INTERFACE -j ACCEPT; iptables -A FORWARD -o $INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i $INTERFACE -j ACCEPT; iptables -D FORWARD -o $INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

    # فعال کردن فورواردینگ
    echo 'net.ipv4.ip_forward=1' | tee -a /etc/sysctl.conf >/dev/null
    sysctl -p >/dev/null

    wg-quick up $INTERFACE || true
    systemctl enable wg-quick@$INTERFACE 2>/dev/null || true

    echo -e "\033[1;32mسرور خارج آماده است.\033[0m"
    echo "حالا:"
    echo "  1. کلید عمومی بالا رو کپی کن"
    echo "  2. برو روی سرور ایران این اسکریپت رو اجرا کن و کلید عمومی رو بهش بده"
    echo ""
    echo "بعد از گرفتن کلید عمومی ایران، این دستورها رو اینجا بزن:"
    echo "echo '[Peer]' >> /etc/wireguard/wg0.conf"
    echo "echo 'PublicKey = <کلید عمومی ایران>' >> /etc/wireguard/wg0.conf"
    echo "echo 'AllowedIPs = 10.66.66.2/32' >> /etc/wireguard/wg0.conf"
    echo "wg-quick down wg0 && wg-quick up wg0"

elif [ "$choice" = "2" ]; then
    # ──────────────────────────────
    #        سرور ایران (کلاینت)
    # ──────────────────────────────

    echo -e "\n\033[1;42m سرور ایران انتخاب شد (کلاینت) \033[0m"

    # اول کلیدهای کلاینت رو بساز و نشون بده
    echo -e "\n\033[1;33mساخت کلیدها برای سرور ایران ...\033[0m"
    CLIENT_PRIVKEY=$(wg genkey)
    CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | wg pubkey)

    echo "$CLIENT_PRIVKEY" > "$WG_DIR/client_private.key"
    echo "$CLIENT_PUBKEY" > "$WG_DIR/client_public.key"
    chmod 600 "$WG_DIR/client_private.key"

    echo -e "\n\033[1;41m=================== خیلی مهم ===================\033[0m"
    echo -e "\033[1;33mکلید خصوصی کلاینت (فقط روی این سرور بماند):\033[0m"
    echo -e "\033[1;37m$CLIENT_PRIVKEY\033[0m\n"

    echo -e "\033[1;42mکلید عمومی کلاینت (این را کپی کن و بده به سرور خارج):\033[0m"
    echo -e "\033[1;37;4m$CLIENT_PUBKEY\033[0m"
    echo -e "\033[1;41m==================================================\033[0m\n"

    # حالا ورودی‌های لازم
    read -p "IP عمومی سرور خارج: " SERVER_PUB_IP

    while true; do
        read -p "پورت WireGuard روی سرور خارج (پیش‌فرض $PORT_DEFAULT): " PORT
        PORT=${PORT:-$PORT_DEFAULT}
        if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
            break
        fi
        echo -e "\033[1;31mپورت باید عدد معتبر باشد!\033[0m"
    done

    read -p "کلید عمومی سرور خارج: " SERVER_PUBKEY

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

    # فعال کردن فورواردینگ (اختیاری ولی مفید)
    echo 'net.ipv4.ip_forward=1' | tee -a /etc/sysctl.conf >/dev/null
    sysctl -p >/dev/null

    wg-quick up $INTERFACE || true
    systemctl enable wg-quick@$INTERFACE 2>/dev/null || true

    echo -e "\n\033[1;32mتونل روی سرور ایران راه افتاد.\033[0m"
    echo "تست کن:"
    echo "  wg show"
    echo "  ping 10.66.66.1"
    echo "  curl ifconfig.me          # باید IP خارج رو نشون بده"
    echo ""
    echo -e "\033[1;33mیادت باشه:\033[0m کلید عمومی کلاینت رو حتماً به سرور خارج بده."

else
    echo -e "\033[1;31mفقط 1 یا 2 انتخاب کن!\033[0m"
    exit 1
fi

echo -e "\n\033[1;36mدستورهای مفید:\033[0m"
echo "  wg show                  → وضعیت تونل"
echo "  journalctl -u wg-quick@wg0 -f   → لاگ"
echo "  wg-quick down wg0        → خاموش کردن"
