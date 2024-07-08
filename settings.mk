#######################################################################################
# Client Servers Configuration
#######################################################################################

SERVER_1_IP := 
SERVER_1_USER_LOGIN := 
SERVER_1_USER_PASSWORD := 

SERVER_2_IP := 
SERVER_2_USER_LOGIN := 
SERVER_2_USER_PASSWORD := 

SERVER_3_IP := 
SERVER_3_USER_LOGIN := 
SERVER_3_USER_PASSWORD := 

#######################################################################################
# Docker Products
#######################################################################################

SERVER_1_PRODUCTS := dozzle #portainer adminer backend autoheal
SERVER_2_PRODUCTS := dozzle #portainer_agent
SERVER_3_PRODUCTS := dozzle #portainer_agent

#######################################################################################
# Swarm Products
#######################################################################################

# if client servers are more than 2
SWARM_PRODUCTS := portainer #backend adminer

#######################################################################################
# Deployment Settings
#######################################################################################

WORK_FOLDER := /opt/project
DATA_FOLDER := data
DB_FOLDER := db

# if client servers are more than 2
GLUSTER_FOLDER := ${WORK_FOLDER}
KEEPALIVED_IP := 

#######################################################################################
# Local Docker Registry Credentials
#######################################################################################

REGISTRY_HOST_IP := 
REGISTRY_HOST := docker.registry.local
REGISTRY_PORT := 5000
REGISTRY_USER := docker
REGISTRY_PASSWORD := docker
TAG := latest