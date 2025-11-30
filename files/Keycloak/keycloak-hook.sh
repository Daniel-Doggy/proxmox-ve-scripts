#!/bin/bash

systemctl stop keycloak

cp $RENEWED_LINEAGE/fullchain.pem /opt/keycloak/conf/server.crt.pem
cp $RENEWED_LINEAGE/privkey.pem /opt/keycloak/conf/server.key.pem
chown keycloak:keycloak /opt/keycloak/conf/server.crt.pem
chown keycloak:keycloak /opt/keycloak/conf/server.key.pem

systemctl start keycloak