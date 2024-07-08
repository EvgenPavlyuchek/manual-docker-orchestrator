#######################################################################################
# Groups of images for products
#######################################################################################

# group test of main images
IMAGES_MAIN-test-mysql := container-registry.oracle.com/mysql/community-server:8.0.37
IMAGES_MAIN-test-router := container-registry.oracle.com/mysql/community-router:8.0.37

#######################################################################################

# group of extra additional images
IMAGES-extra-redis := bitnami/redis:7.2.4
IMAGES-extra-sentinel := bitnami/redis-sentinel:7.2.4
IMAGES-extra-rabbitmq := rabbitmq:3.12.13-management-alpine
IMAGES-extra-traefik := traefik:v2.10
IMAGES-extra-portainer := portainer/portainer-ce:2.20.3-alpine
IMAGES-extra-agent := portainer/agent:2.20.3-alpine
IMAGES-extra-watchtower := containrrr/watchtower:1.7.1
IMAGES-extra-dozzle := amir20/dozzle:v8.0.1
IMAGES-extra-xtrabackup := percona/percona-xtrabackup:8.0
IMAGES-extra-adminer := adminer:4.8.1-standalone
IMAGES-extra-keepalived := osixia/keepalived:2.0.20
IMAGES-extra-autoheal := willfarrell/autoheal:1.2.0