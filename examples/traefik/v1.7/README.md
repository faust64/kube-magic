# Deploy Traefik v1.7

```
# ROUTERS_DOMAIN=router.example.com
# openssl genrsa -des3 -out myCA.key 2048
# openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem
# cat <<EOF >router.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $ROUTERS_DOMAIN
DNS.2 = *.$ROUTERS_DOMAIN
EOF
# openssl genrsa -out $ROUTERS_DOMAIN.key 4096
# openssl x509 -req -in $ROUTERS_DOMAIN.csr -CA myCA.pem -CAkey myCA.key -CAcreateserial -out $ROUTERS_DOMAIN.crt -days 102400 -sha256 -extfile router.ext 
# cat $ROUTERS_DOMAIN.crt myCA.pem >$ROUTERS_DOMAIN-server-chain.crt
# kubectl create -f rbac.yaml
# kubectl create secret -n traefik generic traefik-tls --from-file=tls.crt=$ROUTERS_DOMAIN-server-chain.crt --from-file=tls.key=$ROUTERS_DOMAIN.key
# kubectl create -f config.yaml
# kubectl create -f deployment.yaml
```
