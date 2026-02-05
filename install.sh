#!/bin/bash

# WireGuard Tunnel Script - Iran + Foreign Server
# اجرا با sudo

if [ "$(id -u)" -ne 0 ]; then
    echo "با sudo اجرا کن"
    exit 1
fi

apt update -qq && apt install -y wireguard qrencode

echo "روی کدوم سرور هستی؟"
echo "1 = سرور ایران (کلاینت)"
echo "2 = سرور خارج (سرور WireGuard)"
read -p "انتخاب (1 یا 2): " choice

INTERFACE="wg0"
PORT=51820   # می‌تونی عوض کنی به 443 یا 53 یا هر چی که بازه

if [ "$choice" = "2" ]; then
    # سرور خارج (سرور WG)
    echo "سرور خارج انتخاب شد."

    read -p "IP عمومی این سرور (خارج): " SERVER_PUB_IP
    wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key

    cat << EOF > /etc/wireguard/$INTERFACE.conf
[Interface]
Address = 10.66.66.1/24
PrivateKey = $(cat /etc/wireguard/private.key)
ListenPort = $PORT
PostUp = iptables -A FORWARD -i $INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i $INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# بعداً کلاینت ایران رو اینجا اضافه می‌کنی
EOF

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
