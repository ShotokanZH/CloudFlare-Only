#!/usr/bin/env bash
chainname="cloudflare";
token="/dev/shm/cloudflare";
nginx_confd="/etc/nginx/conf.d/cloudflare.conf";
ports="80,443";
#
#Don't edit below!
#
if [ $EUID -ne 0 ];
then
        echo "[-] Not root!" >&2;
        exit 1;
fi;

if [ -f "$token" ];
then
        echo "[-] Token found!" >&2;
        exit 2;
else
        touch "$token";
fi;

which iptables >/dev/null;
if [ $? -ne 0 ];
then    
        PATH="$PATH:/sbin";     #cron does not have /sbin/ in $PATH
fi;

which nginx >/dev/null;
if [ $? -ne 0 ];
then
        PATH="$PATH:/usr/sbin";     #cron does not have /usr/sbin/ in $PATH
fi;

echo -n "[+] Requesting IPs.."
list=$(curl -s https://www.cloudflare.com/ips-v4 | grep -ioP "^[0-9.]+\/[0-9]+$");
if [ '$list' = '' ];
then
        echo "[-] Something went wrong.." >&2;
        rm "$token";
        exit 3;
fi;
echo " Done.";

iptables -w -D INPUT -p tcp -m multiport --destination-ports "$ports" -j "$chainname" 2>/dev/null;        #let's avoid potential duplicates or missing redirects (or potential downtimes)

iptables -w -N "$chainname" 2>/dev/null;
if [ $? -ne 0 ];        #it's not the first time
then
        iptables -w -F "$chainname";
fi;

iptables -w -A "$chainname" -j REJECT;
iptables -w -I INPUT -p tcp -m multiport --destination-ports "$ports" -j "$chainname";

echo "[+] Allowing cloudflare nodes.. (and refreshing cloudflare.conf)";
tmpf=$(mktemp);
for ip in ${list};
do
        echo -en "\r\033[K\tAccepting $ip...";
        iptables -w -I "$chainname" -s "$ip" -j ACCEPT;
        echo "set_real_ip_from $ip;" >> $tmpf;
done;
echo "" >> $tmpf;
echo "real_ip_header CF-Connecting-IP;" >> $tmpf;
mv "$tmpf" "$nginx_confd";

echo "";
echo "[+] Reloading nginx..";
nginx -t;
if [ $? -eq 0 ];
then
        service nginx reload;
else
        echo "[-] Something went wrong! nginx not reloaded." >&2;
        rm "$token";
        exit 4;
fi;
echo "[+] Done. (Info: iptables -L \"$chainname\" -n )";

rm "$token";
