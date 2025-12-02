#!/bin/bash
#	
#	MIT License
#	
#	Copyright (c) 2024 Daniel-Doggy
#	
#	Permission is hereby granted, free of charge, to any person obtaining a copy
#	of this software and associated documentation files (the "Software"), to deal
#	in the Software without restriction, including without limitation the rights
#	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#	copies of the Software, and to permit persons to whom the Software is
#	furnished to do so, subject to the following conditions:
#	
#	The above copyright notice and this permission notice shall be included in all
#	copies or substantial portions of the Software.
#	
#	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#	SOFTWARE.

keycloak_version="26.4.7"
keycloak_db_username="keycloak_app"
keycloak_admin_username=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; echo)
keycloak_admin_password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; echo)

mysql_root_password=$(tr -dc 'A-Za-z0-9!#%()*+,-.;<=>?^_{|}~' </dev/urandom | head -c 32; echo)
keycloak_db_password=$(tr -dc 'A-Za-z0-9!#%()*+,-.;<=>?^_{|}~' </dev/urandom | head -c 32; echo)
installdir=$(dirname "$(realpath -s "$0")")
serverip=$(hostname -I | awk '{print $1}')
serverhostname=$(dig -x $serverip +short | sed 's/\.[^.]*$//')
export DEBIAN_FRONTEND="noninteractive"

apt-get install -y default-jdk
wget -O "${installdir}/mysql-apt-config.deb" --quiet "https://repo.mysql.com/mysql-apt-config.deb"
apt-get install -y "${installdir}/mysql-apt-config.deb"
apt-get update
apt-get install -y mysql-server

echo "[client]" >> /root/.my.cnf
echo "user=\"root\"" >> /root/.my.cnf
echo "password=\"${mysql_root_password}\"" >> /root/.my.cnf
chmod 600 /root/.my.cnf

mysql -u root -e "ALTER USER \"root\"@\"localhost\" IDENTIFIED WITH caching_sha2_password BY \"${mysql_root_password}\"; FLUSH PRIVILEGES;"
mysql_secure_installation --defaults-extra-file="/root/.my.cnf" --use-default
mysql --defaults-extra-file="/root/.my.cnf" -e "CREATE DATABASE keycloak CHARACTER SET utf8 COLLATE utf8_unicode_ci"
mysql --defaults-extra-file="/root/.my.cnf" -e "CREATE USER \"${keycloak_db_username}\"@\"localhost\" IDENTIFIED BY \"${keycloak_db_password}\""
mysql --defaults-extra-file="/root/.my.cnf" -e "GRANT ALL ON keycloak.* TO \"${keycloak_db_username}\"@\"localhost\";  FLUSH PRIVILEGES;"

wget -O "${installdir}/keycloak.tar.gz" --quiet "https://github.com/keycloak/keycloak/releases/download/${keycloak_version}/keycloak-${keycloak_version}.tar.gz"
tar -xzf "${installdir}/keycloak.tar.gz" -C "${installdir}/"
cp -r "${installdir}/keycloak-${keycloak_version}/" /opt/keycloak/
groupadd keycloak
useradd -r -g keycloak -d /opt/keycloak -s /usr/sbin/nologin keycloak

sed -i "/#db=/c\db=mysql" /opt/keycloak/conf/keycloak.conf
sed -i "/#db-username=/c\db-username=${keycloak_db_username}" /opt/keycloak/conf/keycloak.conf
sed -i "/#db-password=/c\db-password=${keycloak_db_password}" /opt/keycloak/conf/keycloak.conf
sed -i "/#https-certificate-file=/c\https-certificate-file=\$\{kc.home.dir\}\/conf\/server.crt.pem" /opt/keycloak/conf/keycloak.conf
sed -i "/#https-certificate-key-file=/c\https-certificate-key-file=\$\{kc.home.dir\}\/conf\/server.key.pem" /opt/keycloak/conf/keycloak.conf
sed -i "/#hostname=/c\hostname=${serverhostname}" /opt/keycloak/conf/keycloak.conf
sed -i "/#Environment=KC_BOOTSTRAP_ADMIN_USERNAME=/c\Environment=KC_BOOTSTRAP_ADMIN_USERNAME=\"${keycloak_admin_username}\"" "${installdir}/keycloak.service"
sed -i "/#Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=/c\Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=\"${keycloak_admin_password}\"" "${installdir}/keycloak.service"

chown -R keycloak:keycloak /opt/keycloak/
chmod o+rwx /opt/keycloak/bin/
/opt/keycloak/bin/kc.sh build

mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
cp "${installdir}/keycloak-hook.sh" /etc/letsencrypt/renewal-hooks/deploy/
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/keycloak-hook.sh
certbot certonly --staging --non-interactive --agree-tos --standalone --preferred-challenges http -d ${serverhostname} -m "admin@${serverhostname}" --deploy-hook "/etc/letsencrypt/renewal-hooks/deploy/keycloak-hook.sh"

cp "${installdir}/keycloak.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable keycloak
systemctl start keycloak

sed -i "/Environment=KC_BOOTSTRAP_ADMIN_USERNAME=/c\#Environment=KC_BOOTSTRAP_ADMIN_USERNAME=" /etc/systemd/system/keycloak.service
sed -i "/Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=/c\#Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=" /etc/systemd/system/keycloak.service
systemctl daemon-reload

echo "Keycloak admin temp user: ${keycloak_admin_username}" >> /root/install.log
echo "Keycloak admin temp pass: ${keycloak_admin_password}" >> /root/install.log