# Makefile for managing Local Docker Registry, images, deploying docker compose and docker stack, and other functions
# Author: Yevhen Pavliuchek

######################################################################
# Requirements for use:
######################################################################

########################################
# For the Local Docker Registry Server:
########################################

# Any Debian/Ubuntu or CentOS/RHEL OS

# Install Docker, OpenSSH

# Install the required packages:

# For CentOS/RHEL:
# sudo yum makecache && sudo yum install -y make expect

# For Debian/Ubuntu:
# sudo apt-get update && sudo apt-get install -y make expect

########################################
# For Client Servers:
########################################

# Tested on AlmaLinux OS 9
# https://almalinux.org/

# Install the latest Docker Engine, containerd, and Docker Compose:
# https://docs.docker.com/engine/install/centos/

# Add user to the docker and wheel groups

# Check the time synchronization on all servers

######################################################################
# Usage:
######################################################################

# Usage: make [target]

# Targets:
#   help             Display help message

######################################################################
# Extra :
######################################################################

include settings.mk
include images.mk

DOCKER_COMMAND := docker compose
DOCKER_FOLDER := docker
SWARM_FOLDER := swarm
LOCAL_REGISTRY_FOLDER := local-registry
SSH_KEY_NAME := id_ed25519
SCP_OPTIONS := -i ${HOME}/.ssh/${SSH_KEY_NAME} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR
SSH_OPTIONS := -i $(HOME)/.ssh/$(SSH_KEY_NAME) -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no
HIDDEN_EXPECT := >/dev/null 2>&1 && printf "\nSucceeded\n"

######################################################################

# List of targets that are not files
.PHONY: help install-all install-registry list docker-check-all docker-update-all docker-check-local update-local images-all images-extra ssh-prepare-all ssh-all configure-all docker-copy-all docker-up-all docker-down-all docker-reconfig-all docker-rm-all docker-stop-all docker-start-all docker-ps-all remove-registry remove-images remove-extra ps pwd db-backup11 db-backup1

# Default target
.DEFAULT_GOAL := help

######################################################################
# Installation all-in-one:

## Deploy local docker registry with all images, configure servers and deploy products
install-all: install-registry ssh-all configure-all gluster-install-all docker-copy-all docker-up-all docker-ps swarm-install-all

######################################################################
# Installation in parts:

## Deploy local docker registry with all images
install-registry: registry-install images-all registry-list registry-final-ms

######################################################################

## Generate ssh key for servers
install-ssh: ssh-keygen

######################################################################

## Configure servers
install-servers: ssh-prepare-all configure-all gluster-install-all

######################################################################

## Deploy products
install-products: docker-copy-all docker-up-all docker-ps swarm-install-all

######################################################################

## List of images in local docker registry
list: registry-start registry-list


######################################################################
#################### images
######################################################################


define process_image
	if [ -n "$$(echo $(1) | grep ':')" ]; then \
		im_name=$$(echo $(1) | cut -d ':' -f 1); \
		im_tag=$$(echo $(1) | cut -d ':' -f 2); \
	else \
		im_name=$$(echo $(1)); \
		im_tag=latest; \
	fi; \
	printf "\n"; \
	echo "======================================================================================"; \
	echo "Image: $$im_name:$$im_tag"; \
	echo "======================================================================================"; \
	printf "\n"; \
	TARGET_REGISTRY=""; \
	docker pull $$TARGET_REGISTRY$$im_name:$$im_tag 2>/dev/null || { \
		docker pull $$TARGET_REGISTRY_COMMON$$im_name:$$im_tag 2>/dev/null && TARGET_REGISTRY="$$TARGET_REGISTRY_COMMON" || { \
			echo "======================================================================================"; \
			echo "Failed to pull image. Check name and tag $$im_name:$$im_tag"; \
			echo "======================================================================================"; \
			printf "\n"; exit 1; };	}; \
	docker tag $$TARGET_REGISTRY$$im_name:$$im_tag $(REGISTRY_HOST):${REGISTRY_PORT}/$$im_name:$$im_tag >/dev/null 2>&1; \
	docker tag $$TARGET_REGISTRY$$im_name:$$im_tag $(REGISTRY_HOST):${REGISTRY_PORT}/$$im_name:$(TAG) >/dev/null 2>&1; \
	docker push $(REGISTRY_HOST):${REGISTRY_PORT}/$$im_name:$$im_tag || { printf "\n\nFailed to push $(REGISTRY_HOST):${REGISTRY_PORT}/$$im_name:$$im_tag\n\n\n"; exit 1; }; \
	docker push $(REGISTRY_HOST):${REGISTRY_PORT}/$$im_name:$(TAG) || { printf "\n\nFailed to push $(REGISTRY_HOST):${REGISTRY_PORT}/$$im_name:$(TAG)\n\n\n"; exit 1; }
endef

images-all: images-extra ## Pull, retag and push all images from remote registry to local registry
	$(eval VALUES := $(foreach var,$(filter IMAGES_MAIN-%,$(.VARIABLES)),$($(var))))
	@for image in $(VALUES); do \
		$(call process_image,$$image,extra) || exit 1; \
	done

images: images-all

images-extra: ## Pull, retag and push extra images from remote registry to local registry
	$(eval VALUES := $(foreach var,$(filter IMAGES-%,$(.VARIABLES)),$($(var))))
	@for image in $(VALUES); do \
		$(call process_image,$$image,extra) || exit 1; \
	done

images-main: # Pull, retag and push images of main products from remote registry to local registry
	$(eval VALUES := $(foreach var,$(filter IMAGES_MAIN-%,$(.VARIABLES)),$($(var))))
	@for image in $(VALUES); do \
		$(call process_image,$$image,extra) || exit 1; \
	done

images-%: ## Pull, retag and push selected % group of main images from remote registry to local registry
	$(eval VALUES := $(foreach var,$(filter IMAGES_MAIN-$*-%,$(.VARIABLES)),$($(var))))
	@for image in $(VALUES); do \
		$(call process_image,$$image,extra) || exit 1; \
	done


######################################################################
#################### ssh
######################################################################


define ssh_prepare
	ssh-copy-id $(SSH_OPTIONS) $1@$2
endef

define ssh_prepare_expect
	expect -c 'spawn ssh-copy-id $(SSH_OPTIONS) $1@$2; \
		expect "*password*"; \
		send "$3\r"; \
		expect "*password*" { exit 1 } timeout; \
		' $(HIDDEN_EXPECT) || exit 1
endef

ssh-keygen: # Generate ssh key for servers
	@echo ""; \
	echo "======================================================================================"; \
	echo "Generating ssh key $(HOME)/.ssh/$(SSH_KEY_NAME)"; \
	echo "======================================================================================"; \
	make --no-print-directory check_command-ssh-keygen || exit 1; \
	ssh-keygen -t ed25519 -f $(HOME)/.ssh/$(SSH_KEY_NAME) -C "makefile" || true

ssh-prepare-all: ## Prepare ssh connections for all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory ssh-prepare-$(val) || exit 1;)

ssh-prepare-%: # Prepare ssh connection for selected server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "SSH on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	if [ -n "$(SERVER_$*_USER_PASSWORD)" ] && [ -n "$$(command -v expect)" ]; then \
		$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD)) \
		$(call ssh_prepare_expect,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__USER_PASSWORD)); \
	else \
		$(call ssh_prepare,$(SERVER__USER_LOGIN),$(SERVER__IP)); \
	fi

ssh-prepare: ssh-prepare-all
	@echo ""

ssh-all: ssh-keygen ssh-prepare-all # Prepare ssh connections for all servers with ssh-keygen
	@echo ""

######################################################################

define ssh_connect
	@ssh -t -q $(SSH_OPTIONS) $1@$2 "cd ${3}/${DOCKER_FOLDER}-${4}/; bash"
endef

ssh-%: ## Run ssh connection to selected server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__FOLDER := $(value WORK_FOLDER))
	$(eval SERVER := $*)
	$(call ssh_connect,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),$(SERVER))

ssh: ssh-1


######################################################################
#################### configure access to docker registry
######################################################################

define configure_server
	cat ./$(LOCAL_REGISTRY_FOLDER)/certs/${REGISTRY_HOST}.crt | ssh -q $(SSH_OPTIONS) $1@$2 "cat > /tmp/${REGISTRY_HOST}.crt"; \
	if [ -n "$$(command -v expect)" ] && [ -n "$4" ]; then \
		expect -c 'spawn ssh -q $(SSH_OPTIONS) $1@$2 "\
			sudo -S mkdir -p $3; \
			sudo -S chown $1:$1 $3; \
			sudo -S chmod 755 $3; \
			sudo -S mkdir -p /etc/docker/certs.d/$(REGISTRY_HOST):${REGISTRY_PORT} || true; \
			if grep -qF ${REGISTRY_HOST} /etc/hosts; then \
				sudo -S sed -i '\''s/.*${REGISTRY_HOST}.*/${REGISTRY_HOST_IP} ${REGISTRY_HOST}/'\'' /etc/hosts; \
			else \
				sudo -S sed -i '\''$$ a\\${REGISTRY_HOST_IP} ${REGISTRY_HOST}'\'' /etc/hosts; \
			fi; \
			if test -f /tmp/${REGISTRY_HOST}.crt ; then \
				sudo -S mv /tmp/${REGISTRY_HOST}.crt /etc/docker/certs.d/$(REGISTRY_HOST):${REGISTRY_PORT}/ca.crt; \
				sudo -S systemctl restart docker; \
			fi"; \
			expect "password"; \
			send "$4\r"; \
			expect "*password*" { exit 1 } timeout; \
			' $(HIDDEN_EXPECT) || exit 1; \
	else \
		ssh -q $(SSH_OPTIONS) $1@$2 "\
			sudo -S mkdir -p $3; \
			sudo -S chown $1:$1 $3; \
			sudo -S chmod 755 $3; \
			sudo -S mkdir -p /etc/docker/certs.d/$(REGISTRY_HOST):${REGISTRY_PORT} || true; \
			if grep -qF ${REGISTRY_HOST} /etc/hosts; then \
				sudo -S sed -i 's/.*${REGISTRY_HOST}.*/${REGISTRY_HOST_IP} ${REGISTRY_HOST}/' /etc/hosts; \
			else \
				sudo -S sed -i '$$ a\\${REGISTRY_HOST_IP} ${REGISTRY_HOST}' /etc/hosts; \
			fi; \
			if [ -f /tmp/${REGISTRY_HOST}.crt ]; then \
				sudo -S mv /tmp/${REGISTRY_HOST}.crt /etc/docker/certs.d/$(REGISTRY_HOST):${REGISTRY_PORT}/ca.crt; \
				sudo -S systemctl restart docker; \
			fi"; \
	fi; \
	sleep 1s; \
	login_result=$$(ssh -q $(SSH_OPTIONS) $1@$2 "echo -e "${REGISTRY_PASSWORD}" | docker login https://$(REGISTRY_HOST):${REGISTRY_PORT} --username "${REGISTRY_USER}" --password-stdin;" 2>&1); \
	echo ""; \
	echo "======================================================================================"; \
	if echo "$$login_result" | grep -q "Login Succeeded"; then \
		echo "Succeeded Docker Login to ${REGISTRY_HOST}:${REGISTRY_PORT} on server $1@$2"; \
	else \
		echo "Failed Docker Login to ${REGISTRY_HOST}:${REGISTRY_PORT} on server $1@$2 $$login_result"; \
		exit 1; \
	fi; \
	echo "======================================================================================"; \
	echo ""
endef

configure-all: ## Configure all servers for work with local docker registry
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory configure-$(val) || exit 1;)

configure-%: ## Configure selected server % for work with local docker registry
	@if [ -n "$(SERVER_$*_USER_LOGIN)" -a \
			-n "$(WORK_FOLDER)" -a \
			-n "$(SERVER_$*_IP)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		$(eval SERVER__FOLDER := $(value WORK_FOLDER)) \
		$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD)) \
		echo ""; \
		echo "======================================================================================"; \
		echo "Configuring access to local docker registry on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		echo  ; \
		echo  "Waiting..."; \
		$(call configure_server,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),$(SERVER__USER_PASSWORD)) || exit 1; \
	    make --no-print-directory configure-folders-$* || exit 1; \
	else \
		echo ""; \
		echo "Error command \"make configure-$*\": One or more required variables are not defined. Skipping..."; \
		echo ""; \
	fi

configure: configure-all

######################################################################

configure-folders-%:
	@if [ -n "$(SERVER_$*_USER_LOGIN)" -a \
			-n "$(WORK_FOLDER)" -a \
			-n "$(DATA_FOLDER)" -a \
			-n "$(SERVER_$*_IP)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		$(eval SERVER__FOLDER := $(value WORK_FOLDER)) \
		$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD)) \
		echo "======================================================================================"; \
		echo "Configuring folders on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		ssh -q $(SSH_OPTIONS) ${SERVER__USER_LOGIN}@${SERVER__IP} "\
			mkdir -p ${SERVER__FOLDER}/${DATA_FOLDER} && \
			chown :docker ${SERVER__FOLDER}/${DATA_FOLDER} 2>/dev/null && \
			chmod 775 ${SERVER__FOLDER}/${DATA_FOLDER} 2>/dev/null && printf '\nFolders configured.\n' || printf '\nNot changed.\n'; \
			"; \
	fi


######################################################################
#################### Watchtower
######################################################################


## Watchtower Check all groups images in local registry, compare with running containers and show result without updating
docker-check-all: registry-start images-all check_remote-all
	@echo "Done."

docker-check: docker-check-all

## Watchtower Check selected % group of main images in local registry, compare with running containers and show result without updating
docker-check-%: registry-start
	$(eval VALUES := $(foreach var,$(filter IMAGES_MAIN-$*-%,$(.VARIABLES)),$($(var))))
	@#echo "$*: $(VALUES)"
	@for image in $(VALUES); do \
		$(call process_image,$$image,extra) || exit 1; \
	done
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory check_remote_selected-$(val)-$*;)

check_remote_selected-%:
	$(eval SPLIT_VALUES := $(subst -, , $*))
	$(eval FIRST_PART := $(firstword $(SPLIT_VALUES)))
	$(eval SECOND_PART := $(word 2, $(SPLIT_VALUES)))
	@if [ -n "$(SERVER_$(FIRST_PART)_USER_LOGIN)" -a \
			-n "$(SERVER_$(FIRST_PART)_IP)" -a \
			-n "$(SERVER_$(FIRST_PART)_PRODUCTS)" -a \
			"$(filter $(SECOND_PART),$(SERVER_$(FIRST_PART)_PRODUCTS))" != "" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$(FIRST_PART)_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$(FIRST_PART)_IP)) \
		$(eval SERVER__PRODUCTS := $(value SERVER_$(FIRST_PART)_PRODUCTS)) \
		echo ""; \
		echo "======================================================================================"; \
		echo "Checking new versions of $(SECOND_PART) on server $(FIRST_PART) ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call check_remote,$(SERVER__USER_LOGIN),$(SERVER__IP)) || exit 1; \
	fi


######################################################################


## Watchtower Update all groups of images in local registry, compare with running containers and run updating
docker-update-all: registry-start images-all update_remote-all
	@echo "Done."

docker-update: docker-update-all

## Watchtower Update selected group of main images in local registry, compare with running containers and run updating
docker-update-%: registry-start
	$(eval VALUES := $(foreach var,$(filter IMAGES_MAIN-$*-%,$(.VARIABLES)),$($(var))))
	@#echo "$*: $(VALUES)"
	@for image in $(VALUES); do \
		$(call process_image,$$image,extra) || exit 1; \
	done
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory update_remote_selected-$(val)-$* || exit 1;)

update_remote_selected-%:
	$(eval SPLIT_VALUES := $(subst -, , $*))
	$(eval FIRST_PART := $(firstword $(SPLIT_VALUES)))
	$(eval SECOND_PART := $(word 2, $(SPLIT_VALUES)))
	@if [ -n "$(SERVER_$(FIRST_PART)_USER_LOGIN)" -a \
			-n "$(SERVER_$(FIRST_PART)_IP)" -a \
			-n "$(SERVER_$(FIRST_PART)_PRODUCTS)" -a \
			"$(filter $(SECOND_PART),$(SERVER_$(FIRST_PART)_PRODUCTS))" != "" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$(FIRST_PART)_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$(FIRST_PART)_IP)) \
		$(eval SERVER__PRODUCTS := $(value SERVER_$(FIRST_PART)_PRODUCTS)) \
		echo ""; \
		echo "======================================================================================"; \
		echo "Updating new versions of $(SECOND_PART) on server $(FIRST_PART) ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call update_remote,$(SERVER__USER_LOGIN),$(SERVER__IP)); \
	fi


######################################################################


define check_remote
	ssh -q $(SSH_OPTIONS) $1@$2 '\
	docker run --rm \
	--name watchtower \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v $$HOME/.docker/config.json:/config.json \
	-v /etc/localtime:/etc/localtime:ro \
	${REGISTRY_HOST}:${REGISTRY_PORT}/containrrr/watchtower:$(TAG) \
	--run-once \
	--label-enable \
	--monitor-only'
endef

check_remote-all: # Watchtower check all servers without pulling images
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory check_remote-$(val) || exit 1;)

check_remote-%: # Watchtower check selected server % without pulling images
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Checking new versions on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================";
	@$(call check_remote,$(SERVER__USER_LOGIN),$(SERVER__IP))

check_remote: check_remote-all


######################################################################


define update_remote
	ssh -q $(SSH_OPTIONS) $1@$2 '\
	docker run --rm \
	--name watchtower \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v $$HOME/.docker/config.json:/config.json \
	-v /etc/localtime:/etc/localtime:ro \
	${REGISTRY_HOST}:${REGISTRY_PORT}/containrrr/watchtower:$(TAG) \
	--run-once \
	--label-enable \
	--rolling-restart'
endef

update_remote-all: # Watchtower update all servers without pulling images
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory update_remote-$(val) || exit 1;)

update_remote-%: # Watchtower update selected server % without pulling images
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Updating new versions on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================";
	@$(call update_remote,$(SERVER__USER_LOGIN),$(SERVER__IP))

update_remote: update_remote-all


######################################################################


check_local: # Watchtower monitor local
	@docker run --rm \
	--name watchtower \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v $$HOME/.docker/config.json:/config.json \
	-v /etc/localtime:/etc/localtime:ro \
	${REGISTRY_HOST}:${REGISTRY_PORT}/containrrr/watchtower:$(TAG) \
	--run-once \
	--label-enable \
	--monitor-only


update_local: # Watchtower update local
	@docker run --rm \
	--name watchtower \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v $$HOME/.docker/config.json:/config.json \
	-v /etc/localtime:/etc/localtime:ro \
	${REGISTRY_HOST}:${REGISTRY_PORT}/containrrr/watchtower:$(TAG) \
	--run-once \
	--label-enable \
	--rolling-restart


######################################################################
#################### copy to server
######################################################################


define copy_to_server
	cd docker; \
	sed -i "s|^LOCAL_REGISTRY=.*|LOCAL_REGISTRY=${REGISTRY_HOST}:${REGISTRY_PORT}/|g" .env; \
	host_name=$$(ssh -q $(SSH_OPTIONS) $1@$2 "\
		docker network create test >/dev/null 2>&1 || true; \
		mkdir -p $3/${DOCKER_FOLDER}-$5 || true; \
		hostname"); \
	sed -i "s|^HOSTNAME=.*|HOSTNAME=$$host_name|g" .env; \
	idd=$$(ssh -q $(SSH_OPTIONS) $1@$2 "\
		id -u $1") ; \
	sed -i "s|^user_rights=.*|user_rights=$$idd:$$idd|g" .env; \
	for folder in $4; do \
		sed -i "s|^$$folder=.*|$$folder=$2|g" .env; \
		cp .env $$folder/.env; \
	done; \
	echo ""; \
	echo "Products: $4"; \
	echo ""; \
	echo "Copying to $1@$2:${3}/${DOCKER_FOLDER}-$5"; \
	echo ""; \
	scp $(SCP_OPTIONS) -r $4 $1@$2:${3}/${DOCKER_FOLDER}-$5; \
	for folder in $4; do \
		rm -f $$folder/.env ; \
	done; \
	echo ""
endef

docker-copy-all: ## Copy folders and files to all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory docker-copy-$(val) || exit 1;)

docker-copy-%: ## Copy folders and files to selected server %
	@if [ -n "$(SERVER_$*_PRODUCTS)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		$(eval SERVER__FOLDER := $(value WORK_FOLDER)) \
		$(eval SERVER__PRODUCTS := $(value SERVER_$*_PRODUCTS)) \
		$(eval SERVER := $*) \
		echo ""; \
		echo "======================================================================================"; \
		echo "Copying files to server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call copy_to_server,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),${SERVER__PRODUCTS},${SERVER}); \
	fi

docker-copy: docker-copy-all


######################################################################
#################### docker
######################################################################


define docker_up
	ssh -q $(SSH_OPTIONS) $1@$2 'cd ${3}/${DOCKER_FOLDER}-${5}/ && \
		for dir in $4; do \
			if [ -d "$$dir" ]; then \
				cd "$$dir" && $(DOCKER_COMMAND) pull && $(DOCKER_COMMAND) up -d || exit 1; \
				cd ..; \
			fi; \
		done;'
endef

docker-up-all: ## Docker compose up on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory docker-up-$(val) || exit 1;)

docker-up-%: ## Docker compose up on selected server %
	@if [ -n "$(SERVER_$*_PRODUCTS)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		$(eval SERVER__FOLDER := $(value WORK_FOLDER)) \
		$(eval SERVER__PRODUCTS := $(value SERVER_$*_PRODUCTS)) \
		$(eval SERVER := $*) \
		echo ""; \
		echo "======================================================================================"; \
		echo "docker compose pull && docker compose up -d on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call docker_up,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),${SERVER__PRODUCTS},${SERVER}); \
	fi

docker-up: docker-up-all


######################################################################


define docker_down
	ssh -q $(SSH_OPTIONS) $1@$2 'cd ${3}/${DOCKER_FOLDER}-${5}/ && \
		for dir in $4; do \
			if [ -d "$$dir" ]; then \
				cd "$$dir" && $(DOCKER_COMMAND) down -v && cd ..; \
			fi; \
		done;'
endef

docker-down-all: ## Docker compose down -v on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	$(eval REVERSED_VALUES := $(shell echo $(VALUES) | tr ' ' '\n' | tac))
	@$(foreach val,$(REVERSED_VALUES),make --no-print-directory docker-down-$(val) || exit 1;)

docker-down-%: ## Docker compose down -v on selected server %
	@if [ -n "$(SERVER_$*_PRODUCTS)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		$(eval SERVER__FOLDER := $(value WORK_FOLDER)) \
		$(eval SERVER__PRODUCTS := $(value SERVER_$*_PRODUCTS)) \
		$(eval SERVER := $*) \
		$(eval REVERSED_SERVER__PRODUCTS := $(shell echo $(SERVER__PRODUCTS) | tr ' ' '\n' | tac)) \
		echo ""; \
		echo "======================================================================================"; \
		echo "docker compose down -v on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call docker_down,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),${REVERSED_SERVER__PRODUCTS},${SERVER}); \
	fi

docker-down: docker-down-all


######################################################################


define docker_reconfig
	ssh -q $(SSH_OPTIONS) $1@$2 'cd ${3}/${DOCKER_FOLDER}-${5}/ && \
		for dir in *; do \
			if [ -d "$$dir" ]; then \
				found=false; \
				for included_dir in $4; do \
					if [ "$$dir" = "$$included_dir" ]; then \
						found=true; \
						break; \
					fi; \
				done; \
				if [ "$$found" = false ] && [ -e "./$$dir/docker-compose.yml" ]; then \
					cd "$$dir" && $(DOCKER_COMMAND) down -v && cd ..; \
					rm -rf "$$dir"; \
				fi; \
			fi; \
		done; \
		'
endef

docker-reconfig-all: ## Docker-reconfig on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory docker-reconfig-$(val) || exit 1;)

docker-reconfig-%: ## Docker-reconfig on selected server %
	@if [ -n "$(SERVER_$*_PRODUCTS)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		$(eval SERVER__FOLDER := $(value WORK_FOLDER)) \
		$(eval SERVER__PRODUCTS := $(value SERVER_$*_PRODUCTS)) \
		$(eval SERVER := $*) \
		echo ""; \
		echo "======================================================================================"; \
		echo "docker-reconfig on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call docker_reconfig,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),${SERVER__PRODUCTS},${SERVER}); \
		make --no-print-directory docker-copy-$*; \
		make --no-print-directory docker-up-$*; \
	fi

docker-reconfig: docker-reconfig-all


######################################################################


define docker_rm
	ssh -q $(SSH_OPTIONS) $1@$2 '\
		cd ${3}/${DOCKER_FOLDER}-${4}/; \
		for dir in *; do \
			if [ -d "$$dir" ]; then \
				if [ -e "./$$dir/docker-compose.yml" ]; then \
					cd "$$dir" && $(DOCKER_COMMAND) down -v && cd ..; \
				fi; \
			fi; \
			rm -rf "$$dir" || sudo -S rm -rf "$$dir"; \
		done; \
		cd ..; \
		'
		# if [ -n "$$(docker images -q)" ]; then \
		# 	docker rmi -f $$(docker images -q); \
		# fi; 
endef

docker-rm-all: ## Clean all servers with docker compose down -v, rm -rf ./DATA_FOLDER/DOCKER_FOLDER-%/*, rm -rf ../DATA_FOLDER/*
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	$(eval REVERSED_VALUES := $(shell echo $(VALUES) | tr ' ' '\n' | tac))
	@$(foreach val,$(REVERSED_VALUES),make --no-print-directory docker-rm-$(val) || exit 1;)
	@$(foreach val,$(REVERSED_VALUES),make --no-print-directory docker-rm-data-$(val) || exit 1;)
	@make --no-print-directory docker-rm-db;

docker-rm-%: ## Clean selected server % with docker compose down -v, rm -rf ./DATA_FOLDER/DOCKER_FOLDER-%/*, rm -rf ../DATA_FOLDER/*
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__FOLDER := $(value WORK_FOLDER))
	$(eval SERVER := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "rm -rf ${WORK_FOLDER}/${DOCKER_FOLDER}-${SERVER}/* on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================";
	@$(call docker_rm,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),${SERVER})


######################################################################


docker-rm-data-%: ## Delete data on selected server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "rm -rf ${WORK_FOLDER}/${DATA_FOLDER}/* on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	read -p "Are you sure you want to delete ${DATA_FOLDER}/* ? (y/n): " answer; \
	if [ "$$answer" = "y" ] && [ -n ${WORK_FOLDER} ] && [ -n ${DATA_FOLDER} ]; then \
		ssh -q $(SSH_OPTIONS) ${SERVER__USER_LOGIN}@${SERVER__IP} '\
			rm -rf ${WORK_FOLDER}/${DATA_FOLDER}/* || sudo -S rm -rf ${WORK_FOLDER}/${DATA_FOLDER}/* && echo "${WORK_FOLDER}/${DATA_FOLDER}/* deleted."; \
			'; \
	else \
		echo "Operation canceled."; \
	fi

docker-rm-data: docker-rm-data-1


######################################################################


docker-rm-db: ## Delete db on server 1
	$(eval SERVER__USER_LOGIN := $(value SERVER_1_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_1_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "rm -rf ${WORK_FOLDER}/${DB_FOLDER}/* on server 1 ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	read -p "Are you sure you want to delete ${DB_FOLDER}/* ? (y/n): " answer; \
	if [ "$$answer" = "y" ] && [ -n ${WORK_FOLDER} ] && [ -n ${DB_FOLDER} ]; then \
		ssh -q $(SSH_OPTIONS) ${SERVER__USER_LOGIN}@${SERVER__IP} '\
			rm -rf ${WORK_FOLDER}/${DB_FOLDER}/* >/dev/null 2>&1 || sudo -S rm -rf ${WORK_FOLDER}/${DB_FOLDER}/* && echo "${WORK_FOLDER}/${DB_FOLDER}/* deleted."; \
			mkdir -p ${WORK_FOLDER}/${DB_FOLDER} ; \
			chown ${SERVER__USER_LOGIN}:docker ${WORK_FOLDER}/${DB_FOLDER} >/dev/null 2>&1 && chmod 775 ${WORK_FOLDER}/${DB_FOLDER} >/dev/null 2>&1 || sudo -S chown ${SERVER__USER_LOGIN}:docker ${WORK_FOLDER}/${DB_FOLDER} && sudo -S chmod 775 ${WORK_FOLDER}/${DB_FOLDER} && echo "chown ${WORK_FOLDER}/${DB_FOLDER}/ modified."; \
			'; \
	else \
		echo "Operation canceled."; \
	fi


######################################################################


define docker_stop
	ssh -q $(SSH_OPTIONS) $1@$2 'cd ${3}/${DOCKER_FOLDER}-${5}/ && \
		for dir in $4; do \
			if [ -d "$$dir" ] && [ "$$dir" != "dozzle" ] && [ "$$dir" != "portainer" ]; then \
				cd "$$dir" && $(DOCKER_COMMAND) stop && cd ..; \
			fi; \
		done; \
		'
endef

docker-stop-all: ## Docker compose stop on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	$(eval REVERSED_VALUES := $(shell echo $(VALUES) | tr ' ' '\n' | tac))
	@$(foreach val,$(REVERSED_VALUES),make --no-print-directory docker-stop-$(val) || exit 1;)

docker-stop-%: ## Docker compose stop on selected server %
	@if [ -n "$(SERVER_$*_PRODUCTS)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		$(eval SERVER__FOLDER := $(value WORK_FOLDER)) \
		$(eval SERVER__PRODUCTS := $(value SERVER_$*_PRODUCTS)) \
		$(eval REVERSED_SERVER__PRODUCTS := $(shell echo $(SERVER__PRODUCTS) | tr ' ' '\n' | tac)) \
		$(eval SERVER := $*) \
		echo ""; \
		echo "======================================================================================"; \
		echo "docker compose stop on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call docker_stop,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),${REVERSED_SERVER__PRODUCTS},${SERVER}); \
	fi

docker-stop: docker-stop-all


######################################################################


define docker_start
	ssh -q $(SSH_OPTIONS) $1@$2 'cd ${3}/${DOCKER_FOLDER}-${5}/ && \
		for dir in $4; do \
			if [ -d "$$dir" ]; then \
				cd "$$dir" && $(DOCKER_COMMAND) start && cd ..; \
			fi; \
		done;'
endef

docker-start-all: ## Docker compose start on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory docker-start-$(val) || exit 1;)

docker-start-%: ## Docker compose start on selected server %
	@if [ -n "$(SERVER_$*_PRODUCTS)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		$(eval SERVER__FOLDER := $(value WORK_FOLDER)) \
		$(eval SERVER__PRODUCTS := $(value SERVER_$*_PRODUCTS)) \
		$(eval SERVER := $*) \
		echo ""; \
		echo "======================================================================================"; \
		echo "docker compose start on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call docker_start,$(SERVER__USER_LOGIN),$(SERVER__IP),$(SERVER__FOLDER),${SERVER__PRODUCTS},${SERVER}); \
	fi

docker-start: docker-start-all


######################################################################


define docker_ps
	ssh -q $(SSH_OPTIONS) $1@$2 ' \
		docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Size}}\t{{.CreatedAt}}" | sort'
endef

docker-ps-all: ## Docker ps on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory docker-ps-$(val) || exit 1;)

docker-ps-%: ## Docker ps on selected server %
	@if [ -n "$(SERVER_$*_PRODUCTS)" ]; then \
		$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN)) \
		$(eval SERVER__IP := $(value SERVER_$*_IP)) \
		echo ""; \
		echo "======================================================================================"; \
		echo "docker ps on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
		echo "======================================================================================"; \
		$(call docker_ps,$(SERVER__USER_LOGIN),$(SERVER__IP)); \
	fi

docker-ps: docker-ps-all


######################################################################
#################### local docker registry
######################################################################


registry-password: # Create password for user and save it to auth folder.
	@echo ""; \
	echo "======================================================================================"; \
	echo "Starting ..."; \
	echo "======================================================================================"; \
	echo ""; \
	mkdir -p $(LOCAL_REGISTRY_FOLDER)/auth || true; \
	docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$(REGISTRY_USER)" "$(REGISTRY_PASSWORD)" > $(LOCAL_REGISTRY_FOLDER)/auth/htpasswd; \
	echo "Created password file for local registry."

registry-cert: # Generate self-signed certificate, configure /etc/hosts and systemctl restart docker
	@mkdir -p $(LOCAL_REGISTRY_FOLDER)/certs  >/dev/null 2>&1 || true
	@openssl req -new -newkey rsa:4096 -days 3650 -subj "/CN=${REGISTRY_HOST}" -addext "subjectAltName = IP:${REGISTRY_HOST_IP}, DNS:${REGISTRY_HOST}" -nodes -x509 -keyout $(LOCAL_REGISTRY_FOLDER)/certs/${REGISTRY_HOST}.key -out $(LOCAL_REGISTRY_FOLDER)/certs/${REGISTRY_HOST}.crt  >/dev/null 2>&1
	@sudo mkdir -p /etc/docker/certs.d/${REGISTRY_HOST}:${REGISTRY_PORT} || true
	@sudo cp $(LOCAL_REGISTRY_FOLDER)/certs/${REGISTRY_HOST}.crt /etc/docker/certs.d/${REGISTRY_HOST}:${REGISTRY_PORT}/ca.crt
	@sudo systemctl restart docker
	@if ! grep -qF "${REGISTRY_HOST}" /etc/hosts; then \
		echo "127.0.0.1 ${REGISTRY_HOST}" | sudo tee -a /etc/hosts; \
	fi
	@echo "Created and placed self-signed certificate, added "127.0.0.1 ${REGISTRY_HOST}" to /etc/hosts."

registry-run: # Start container with docker registry
	@mkdir -p $(LOCAL_REGISTRY_FOLDER)/data || true
	@docker run -d --restart unless-stopped --name ${REGISTRY_HOST} \
	-v ./$(LOCAL_REGISTRY_FOLDER)/data:/data \
	-v ./$(LOCAL_REGISTRY_FOLDER)/certs:/certs \
	-v ./$(LOCAL_REGISTRY_FOLDER)/auth:/auth \
	-v /etc/localtime:/etc/localtime:ro \
	-e "REGISTRY_AUTH=htpasswd" \
	-e "REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data" \
	-e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
	-e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
	-e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
	-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${REGISTRY_HOST}.crt \
	-e REGISTRY_HTTP_TLS_KEY=/certs/${REGISTRY_HOST}.key \
	-p :${REGISTRY_PORT}:443 registry:2.8.3
	@sleep 1
	@echo "Started local registry."

# Deploy a local Docker registry with self-signed certificate without pulling images
registry-install: registry-rm registry-password registry-cert registry-run
	@login_result=$$(echo -e "${REGISTRY_PASSWORD}" | docker login https://$(REGISTRY_HOST):${REGISTRY_PORT} --username "${REGISTRY_USER}" --password-stdin 2>&1); \
	echo ""; \
	echo "======================================================================================"; \
	if echo "$$login_result" | grep -q "Login Succeeded"; then \
		echo "Succeeded Docker Login to ${REGISTRY_HOST}:${REGISTRY_PORT} on localhost"; \
	else \
		echo "Failed Docker Login to ${REGISTRY_HOST}:${REGISTRY_PORT} $$login_result"; \
		exit 1; \
	fi; \
	echo "======================================================================================"; \
	echo ""

registry-final-ms:
	@echo ""; \
	echo "Deployed local docker registry with all images."; \
	echo ""; \
	echo "======================================================================================"; \
	echo ""; \
	echo "Local docker registry ${REGISTRY_HOST}:${REGISTRY_PORT} is ready for use"; \
	echo ""; \
	echo "======================================================================================"; \
	echo ""


######################################################################


registry-list:
	@echo ""; \
	echo "======================================================================================"; \
	echo "Images in local registry:"; \
	echo "======================================================================================"; \
	printf "\n"; \
	curl -k -s --user "$(REGISTRY_USER):$(REGISTRY_PASSWORD)" https://$(REGISTRY_HOST):$(REGISTRY_PORT)/v2/_catalog | \
	sed -n 's/.*\["\(.*\)"].*/\1/p' | tr -d '"' | \
	tr ',' '\n' | \
	while read repo; do \
		curl -k -s --user "$(REGISTRY_USER):$(REGISTRY_PASSWORD)" "https://$(REGISTRY_HOST):$(REGISTRY_PORT)/v2/$$repo/tags/list" | \
		sed -n 's/.*"name":"\(.*\)","tags":\[\(.*\)\].*/\1:\2/p' | tr -d '"'; \
		printf "\n"; \
	done; \
	echo "======================================================================================"; \


######################################################################


registry-start: # Start local docker registry container
	@docker start ${REGISTRY_HOST}

registry-stop: # Stop local docker registry container
	@docker stop ${REGISTRY_HOST}

start: registry-start ## Start local docker registry container

stop: registry-stop ## Stop local docker registry container


######################################################################


registry-rm: # Stop and remove container with registry
	@docker stop ${REGISTRY_HOST} >/dev/null 2>&1 || true
	@docker rm ${REGISTRY_HOST} >/dev/null 2>&1 || true

registry-host-clean: # Clear /etc/hosts from local registry dns
	@if grep -qF "${REGISTRY_HOST}" /etc/hosts; then \
		sudo sed -i "/${REGISTRY_HOST}/d" /etc/hosts; \
	fi

registry-rm-data: registry-rm # Stop, remove container with registry and remove data folder with images of local registry server
	sudo rm -rf $(LOCAL_REGISTRY_FOLDER)/data

remove-registry: registry-rm registry-host-clean registry-rm-data ## Clean and remove local docker registry
	@rm -rf $(LOCAL_REGISTRY_FOLDER)
	@echo "Cleaned."

remove-images: ## Remove all docker images
	docker rmi -f $$(docker images -q)

remove-extra: remove-images # Clean all local docker images and run docker system prune
	@echo "Cleaning Docker resources..."
	docker system prune -af


######################################################################
#################### other
######################################################################


ps: # Local docker ps
	@docker ps

pwd: # Local pwd
	@echo "$(shell pwd)"


######################################################################


define check_command
	@if [ -z "$$(command -v $(1))" ]; then \
		echo ""; \
		echo "======================================================================================"; \
		echo "Error $(1) is not installed."; \
		echo "======================================================================================"; \
		echo ""; \
		exit 1; \
	fi
endef

check_command-%: # Check command -v %
	$(call check_command,$(subst check_command-,,$@))


######################################################################


help: # Display help message
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk '/^[a-zA-Z0-9_%-]+:/ { \
		nb = sub( /^## /, "", helpMsg ); \
		if(nb == 0) { \
			helpMsg = $$0; \
			nb = sub( /^[^:]*:.* ## /, "", helpMsg ); \
		} \
		if (nb) { \
			gsub(/:/, "", $$1); \
			printf "  %-25s %s\n", $$1, helpMsg; \
		} \
	} \
	{ helpMsg = $$0 }' \
	$(MAKEFILE_LIST)
	@echo ""


######################################################################
#################### GlusterFS
######################################################################


GLUSTER_FOLDER_BRICK := /opt/gluster-brick

gluster-install-all: ## GlusterFS install on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@if [ $$(echo $(VALUES) | wc -w) -gt 2 ] && [ -n "${GLUSTER_FOLDER}" ]; then \
		echo ""; \
		printf "\033[44mDo you want to install GlusterFS ? (y/n):\033[0m "; \
		read answer; \
		if [ "$$answer" = "y" ]; then \
			$(foreach val,$(VALUES),make --no-print-directory gluster-install-$(val) || exit 1;) \
			make --no-print-directory gluster-config-1 || exit 1; \
			$(foreach val,$(VALUES),make --no-print-directory gluster-mount-$(val) || exit 1;) \
			make --no-print-directory configure-folders-1; \
		else \
			echo "Gluster canceled."; \
		fi; \
	fi

gluster-install: gluster-install-all

gluster-install-%: ## GlusterFS install on selected server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	@echo ""; \
	echo "======================================================================================"; \
	echo "gluster install on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	echo  "Waiting..."; \
	expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		sudo -S yum install centos-release-gluster -y && \
		sudo -S yum install glusterfs-server -y && \
		sudo -S firewall-cmd --add-service=glusterfs --permanent && \
		sudo -S firewall-cmd --reload; \
		sudo -S systemctl enable glusterd && \
		sudo -S systemctl start glusterd; \
		sudo -S mkdir -p ${GLUSTER_FOLDER_BRICK} && \
		sudo -S chown $(SERVER__USER_LOGIN):docker ${GLUSTER_FOLDER_BRICK} && \
		sudo -S chmod 775 ${GLUSTER_FOLDER_BRICK}; \
		"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		expect "*password*" { exit 1 } timeout; \
		' $(HIDDEN_EXPECT) || exit 1; \

gluster-config: gluster-config-1

gluster-config-%: ## GlusterFS config on selected server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	$(eval VALUES := $(sort $(foreach var,$(filter SERVER_%_IP,$(.VARIABLES)),$($(var)))))
	$(eval values_count := $(words $(VALUES)))
	$(eval probe_commands := $(foreach ipp,$(VALUES),sudo -S gluster peer probe $(ipp);))
	$(eval NODES := $(foreach ipp,$(VALUES),sudo -S gluster volume add-brick project replica ${values_count} $(ipp):${GLUSTER_FOLDER_BRICK} force;))
	$(eval gluster := $(addsuffix :${GLUSTER_FOLDER_BRICK} , $(VALUES))) 
	$(eval SERVER := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "gluster config on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		eval $(probe_commands) \
		sleep 1s; \
		echo \"\"; \
		sudo -S gluster pool list; \
		sudo -S gluster peer status; \
		if ! sudo -S gluster volume info project; then \
			sudo -S gluster volume create project replica ${values_count} ${gluster} force && \
			sudo -S gluster volume set project auth.allow 127.0.0.1 && \
			sudo -S gluster volume set project cluster.self-heal-daemon enable && \
			sudo -S gluster volume start project; \
		else \
			eval $(NODES) \
			sleep 1s; \
		fi; \
		echo \"\"; \
		sudo -S gluster volume status; \
		sudo -S gluster volume info; \
		"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		interact'


######################################################################


gluster-mount-all: ## GlusterFS mount on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	$(eval REVERSED_VALUES := $(shell echo $(VALUES) | tr ' ' '\n' | tac))
	@$(foreach val,$(REVERSED_VALUES),make --no-print-directory gluster-mount-$(val) || exit 1;)

gluster-mount: gluster-mount-all

gluster-mount-%: ## GlusterFS mount on selected server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	@echo ""; \
	echo "======================================================================================"; \
	echo "mount -t glusterfs localhost:/project on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	if [ -n "$$(command -v expect)" ] && [ -n "$(SERVER__USER_PASSWORD)" ]; then \
		expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
			sudo -S mount.glusterfs localhost:/project ${GLUSTER_FOLDER} && echo \"Mounted\"; \
			grep -q \"localhost:/project\" /etc/fstab || echo \"localhost:/project ${GLUSTER_FOLDER} glusterfs defaults,_netdev,noauto,x-systemd.automount,x-systemd.device-timeout=30,x-systemd.requires=glusterd.service 0 0\" | sudo -S tee -a /etc/fstab; \
			cat /etc/fstab; \
			"; \
			expect "password"; \
			send "$(SERVER__USER_PASSWORD)\r"; \
			expect "*password*" { exit 1 } timeout; \
			' $(HIDDEN_EXPECT) || exit 1; \
		echo ""; \
	else \
		ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
			sudo -S mount.glusterfs localhost:/project ${GLUSTER_FOLDER} && echo \"Mounted\"; \
			grep -q "localhost:/project" /etc/fstab || echo "localhost:/project ${GLUSTER_FOLDER} glusterfs defaults,_netdev,noauto,x-systemd.automount,x-systemd.device-timeout=30,x-systemd.requires=glusterd.service 0 0" | sudo -S tee -a /etc/fstab; \
			cat /etc/fstab; \
			mount | grep \"localhost:/project\" || echo \"Error\"; \
			"; \
		echo ""; \
	fi


######################################################################


gluster-ps-%: ## GlusterFS status on selected server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	@echo ""; \
	echo "======================================================================================"; \
	echo "gluster status on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		sudo -S gluster pool list && \
		echo \"\" && \
		sudo -S gluster peer status && \
		echo \"\" && \
		sudo -S gluster volume status && \
		sudo -S gluster volume info && \
		echo \"\" && \
		sudo -S sudo gluster volume status project detail && \
		echo \"\" && \
		sudo -S gluster volume heal project info split-brain && \
		echo \"\"; \
		"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		interact'

gluster-ps: gluster-ps-1


######################################################################


gluster-umount-all: ## GlusterFS umount on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	$(eval REVERSED_VALUES := $(shell echo $(VALUES) | tr ' ' '\n' | tac))
	$(foreach val,$(REVERSED_VALUES),make --no-print-directory gluster-umount-$(val);)

gluster-umount: gluster-umount-all

gluster-umount-%: ## GlusterFS umount on selected server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	@echo ""; \
	echo "======================================================================================"; \
	echo "umount ${GLUSTER_FOLDER} on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	if [ -n "$$(command -v expect)" ] && [ -n "$(SERVER__USER_PASSWORD)" ]; then \
		expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
			sudo -S umount ${GLUSTER_FOLDER} && echo \"Umounted\"  || echo \"Already umounted\"; \
			sudo -S sed -i \"/project/d\" /etc/fstab; \
			sudo -S mount -a; \
			cat /etc/fstab; \
			"; \
			expect "password"; \
			send "$(SERVER__USER_PASSWORD)\r"; \
			interact'; \
		echo ""; \
	else \
		ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
			sudo -S umount ${GLUSTER_FOLDER} && echo \"Umounted\"  || echo \"Already umounted\"; \
			sudo -S sed -i '#localhost:/project#d' /etc/fstab; \
			sudo -S mount -a; \
			cat /etc/fstab; \
			"; \
		echo ""; \
	fi


######################################################################


gluster-uninstall-all: ## GlusterFS uninstall on all servers and remove gluster bricks !!!
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	$(eval REVERSED_VALUES := $(shell echo $(VALUES) | tr ' ' '\n' | tac))
	@if [ -n "${GLUSTER_FOLDER}" ]; then \
		$(foreach val,$(REVERSED_VALUES),make --no-print-directory gluster-umount-$(val) || exit 1;) \
		expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER_1_USER_LOGIN)@$(SERVER_1_IP) "\
			sudo -S gluster volume stop project; \
			sudo -S gluster volume delete project; \
			"; \
			expect "password"; \
			send "$(SERVER_1_USER_PASSWORD)\r"; \
			expect "Stopping"; \
			send "y\r"; \
			expect "password"; \
			send "$(SERVER_1_USER_PASSWORD)\r"; \
			expect "Deleting"; \
			send "y\r"; \
			interact'; \
		$(foreach val,$(REVERSED_VALUES),make --no-print-directory gluster-uninstall-$(val) || exit 1;) \
	fi

gluster-uninstall: gluster-uninstall-all

gluster-uninstall-%: ## GlusterFS uninstall on selected server % and remove gluster brick !!!
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	$(eval VALUES := $(foreach var,$(filter SERVER_%_IP,$(.VARIABLES)),$($(var))))
	$(eval values_count := $(words $(VALUES)))
	$(eval probe_commands := $(foreach ipp,$(VALUES),sudo -S gluster peer probe $(ipp);))
	$(eval gluster := $(addsuffix :${GLUSTER_FOLDER_BRICK} , $(VALUES))) 
	$(eval SERVER := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "gluster uninstall on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		sudo -S systemctl stop glusterd; \
		sudo -S yum remove glusterfs-server -y; \
		sudo -S systemctl daemon-reload; \
		sudo -S systemctl status glusterd; \
		sudo -S rm -rf /var/lib/glusterd; \
		sudo -S rm -rf /var/log/glusterfs; \
		sudo -S rm -rf /etc/glusterfs; \
		"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		interact'
	@echo ""; \
	echo "======================================================================================"; \
	echo "rm -rf ${GLUSTER_FOLDER_BRICK} on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	read -p "Are you sure you want to delete ${GLUSTER_FOLDER_BRICK}/* ? (y/n): " answer; \
	if [ "$$answer" = "y" ] && [ -n ${GLUSTER_FOLDER_BRICK} ]; then \
		expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
			sudo -S rm -rf ${GLUSTER_FOLDER_BRICK} && \
			echo \"${GLUSTER_FOLDER_BRICK} deleted.\"; \
			"; \
			expect "password"; \
			send "$(SERVER__USER_PASSWORD)\r"; \
			interact'; \
	else \
		echo "Operation canceled."; \
	fi


######################################################################
#################### gluster remove/detach peer/brick
######################################################################


# sudo gluster volume remove-brick project replica <NUMBER-WORKING-PEERS> <IP-PEER>:/opt/gluster-brick force
# sudo gluster peer detach <IP-PEER> force

# sudo gluster peer probe <IP-PEER>
# sudo gluster volume add-brick project replica <NUMBER-WORKING-PEERS> <IP-PEER>:/opt/gluster-brick force


######################################################################
#################### Docker Swarm
######################################################################


swarm-install-all: ## Install Docker Swarm 
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@if [ $$(echo $(VALUES) | wc -w) -gt 2 ] && [ -n "${SWARM_PRODUCTS}" ] && [ -n "${GLUSTER_FOLDER}" ]; then \
		echo ""; \
		printf "\033[44mDo you want to install Docker Swarm? (y/n):\033[0m "; \
		read answer; \
		if [ "$$answer" = "y" ]; then \
			$(foreach val,$(VALUES),make --no-print-directory swarm-install-$(val) || exit 1;) \
			make --no-print-directory swarm-folders-all || exit 1; \
			make --no-print-directory swarm-copy || exit 1; \
			make --no-print-directory keepalived-install-all || exit 1; \
			make --no-print-directory swarm-up-all || exit 1; \
		else \
			echo "Docker Swarm canceled."; \
		fi; \
	fi

swarm-install: swarm-install-all

swarm-install-%: ## Install Docker Swarm on selected % server
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	$(eval SERVER := $*)
	$(eval SERVER_SWARM_USER_LOGIN := $(value SERVER_1_USER_LOGIN))
	$(eval SERVER_SWARM_IP := $(value SERVER_1_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Docker Swarm on server $(SERVER) ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	if [ $(SERVER) -ne 1 ]; then \
		read -p "Do you want role Manager or Worker of Docker Swarm on server $(SERVER) ${SERVER__IP} ? (m/w): " answer; \
		if [ "$$answer" = "m" ]; then \
			SWARM_CHOSEN_TOKEN=$$(ssh -q $(SSH_OPTIONS) $(SERVER_SWARM_USER_LOGIN)@$(SERVER_SWARM_IP) "docker swarm join-token manager --quiet"); \
		elif [ "$$answer" = "w" ]; then \
			SWARM_CHOSEN_TOKEN=$$(ssh -q $(SSH_OPTIONS) $(SERVER_SWARM_USER_LOGIN)@$(SERVER_SWARM_IP) "docker swarm join-token worker --quiet"); \
		else \
			echo "Canceled."; \
			exit 1; \
		fi; \
		echo "SWARM_CHOSEN_TOKEN: $${SWARM_CHOSEN_TOKEN}"; \
	fi; \
	expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		sudo -S firewall-cmd --add-port=2376/tcp --permanent && \
		sudo -S firewall-cmd --add-port=2377/tcp --permanent && \
		sudo -S firewall-cmd --add-port=7946/tcp --permanent && \
		sudo -S firewall-cmd --add-port=7946/udp --permanent && \
		sudo -S firewall-cmd --add-port=4789/udp --permanent && \
		sudo -S firewall-cmd --add-port=9789/udp --permanent && \
		sudo -S firewall-cmd --reload ; \
		if test ${SERVER} -eq 1 ; then \
			docker swarm init --data-path-port=9789 --advertise-addr ${SERVER__IP}; \
			docker network create -d overlay --attachable test_swarm; \
			docker swarm update --task-history-limit 3; \
		else \
			docker swarm join --token '"$${SWARM_CHOSEN_TOKEN}"' ${SERVER_SWARM_IP}:2377; \
		fi; \
		"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		interact'; \
	ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		NODE_ID=\$$(docker info --format '{{json .Swarm.NodeID}}' | tr -d '\"'); \
		docker node update --label-add node=$(SERVER) \$${NODE_ID}; \
		docker node update --label-add node$(SERVER)=$(SERVER) \$${NODE_ID}; \
		if test ${SERVER} -eq 1 ; then \
			docker node update --label-add monitoring=true \$${NODE_ID}; \
		fi; \
		" >/dev/null 2>&1

swarm-join-%: # Join to Docker Swarm on selected % server
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	$(eval SERVER := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "Join to Docker Swarm on server $(SERVER) ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	if [ $(SERVER) -eq 1 ]; then \
		SERVER_SWARM_USER_LOGIN=$(SERVER_2_USER_LOGIN); \
		SERVER_SWARM_IP=$(SERVER_2_IP); \
		read -p "Do you want role Manager or Worker of Docker Swarm on server $(SERVER) ${SERVER__IP} ? (m/w): " answer; \
		if [ "$$answer" = "m" ]; then \
			SWARM_CHOSEN_TOKEN=$$(ssh -q $(SSH_OPTIONS) $${SERVER_SWARM_USER_LOGIN}@$${SERVER_SWARM_IP} "docker swarm join-token manager --quiet"); \
		elif [ "$$answer" = "w" ]; then \
			SWARM_CHOSEN_TOKEN=$$(ssh -q $(SSH_OPTIONS) $${SERVER_SWARM_USER_LOGIN}@$${SERVER_SWARM_IP} "docker swarm join-token worker --quiet"); \
		else \
			echo "Canceled."; \
			exit 1; \
		fi; \
		echo "SERVER_SWARM_USER_LOGIN: $${SERVER_SWARM_USER_LOGIN}"; \
		echo "SERVER_SWARM_IP: $${SERVER_SWARM_IP}"; \
		echo "SWARM_CHOSEN_TOKEN: $${SWARM_CHOSEN_TOKEN}"; \
	fi; \
	if [ $(SERVER) -ne 1 ]; then \
		SERVER_SWARM_USER_LOGIN=$(SERVER_1_USER_LOGIN); \
		SERVER_SWARM_IP=$(SERVER_1_IP); \
		read -p "Do you want role Manager or Worker of Docker Swarm on server $(SERVER) ${SERVER__IP} ? (m/w): " answer; \
		if [ "$$answer" = "m" ]; then \
			SWARM_CHOSEN_TOKEN=$$(ssh -q $(SSH_OPTIONS) $${SERVER_SWARM_USER_LOGIN}@$${SERVER_SWARM_IP} "docker swarm join-token manager --quiet"); \
		elif [ "$$answer" = "w" ]; then \
			SWARM_CHOSEN_TOKEN=$$(ssh -q $(SSH_OPTIONS) $${SERVER_SWARM_USER_LOGIN}@$${SERVER_SWARM_IP} "docker swarm join-token worker --quiet"); \
		else \
			echo "Canceled."; \
			exit 1; \
		fi; \
		echo "SERVER_SWARM_USER_LOGIN: $${SERVER_SWARM_USER_LOGIN}"; \
		echo "SERVER_SWARM_IP: $${SERVER_SWARM_IP}"; \
		echo "SWARM_CHOSEN_TOKEN: $${SWARM_CHOSEN_TOKEN}"; \
	fi; \
	expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		sudo -S firewall-cmd --add-port=2376/tcp --permanent && \
		sudo -S firewall-cmd --add-port=2377/tcp --permanent && \
		sudo -S firewall-cmd --add-port=7946/tcp --permanent && \
		sudo -S firewall-cmd --add-port=7946/udp --permanent && \
		sudo -S firewall-cmd --add-port=4789/udp --permanent && \
		sudo -S firewall-cmd --add-port=9789/udp --permanent && \
		sudo -S firewall-cmd --reload ; \
		docker swarm join --token '"$${SWARM_CHOSEN_TOKEN}"' '"$${SERVER_SWARM_IP}"':2377; \
		"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		interact'; \
	ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		NODE_ID=\$$(docker info --format '{{json .Swarm.NodeID}}' | tr -d '\"'); \
		docker node update --label-add node$(SERVER)=$(SERVER) \$${NODE_ID}; \
		" >/dev/null 2>&1

######################################################################

swarm-uninstall-all: ## Uninstall Docker Swarm and all stacks
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	$(eval REVERSED_VALUES := $(shell echo $(VALUES) | tr ' ' '\n' | tac))
	@if [ -n "${SWARM_PRODUCTS}" ]; then \
		make --no-print-directory swarm-down-all; \
		sleep 10s; \
		make --no-print-directory keepalived-uninstall-all; \
		make --no-print-directory swarm-ps; \
		$(foreach val,$(REVERSED_VALUES),make --no-print-directory swarm-uninstall-$(val) || exit 1;) \
	fi

swarm-uninstall: swarm-uninstall-all

swarm-uninstall-%: ## Uninstall Docker Swarm on selected % server
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Uninstall Docker Swarm on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		docker swarm leave --force || echo \"Node is not part of Docker Swarmg\" ; \
		"

######################################################################

swarm-ps: swarm-ps-1

swarm-ps-%: ## Docker Swarm ls resources
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "Docker Swarm ls resources server $(SERVER) ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) 'cd ${WORK_FOLDER}/${SWARM_FOLDER}/ && \
		echo "docker node ls" | tr '[:lower:]' '[:upper:]'; \
		docker node ls; \
		echo ""; \
		echo "docker stack ls" | tr '[:lower:]' '[:upper:]'; \
		docker stack ls; \
		echo ""; \
		echo "docker service ls" | tr '[:lower:]' '[:upper:]'; \
		docker service ls; \
		echo ""; \
		for dir in ${SWARM_PRODUCTS}; do \
			if [ -d "$$dir" ]; then \
				echo ""; \
				echo "======================================================================================"; \
				echo "docker stack ps $$dir"; \
				echo "======================================================================================"; \
				echo ""; \
				docker stack ps $$dir; \
				echo ""; \
			fi; \
		done; \
		'

######################################################################

swarm-folders-%:
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	$(eval SERVER := $*) 
	@echo "======================================================================================"; \
	echo "Configuring folders on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
 		mkdir -p ${WORK_FOLDER}/${DATA_FOLDER}/fs/logs && \
 		mkdir -p ${WORK_FOLDER}/${DATA_FOLDER}/call_storage && \
		sudo -S chown -R :docker ${WORK_FOLDER}/${DATA_FOLDER}/fs && \
		sudo -S chown -R :docker ${WORK_FOLDER}/${DATA_FOLDER}/call_storage && \
		mkdir -p ${WORK_FOLDER}/${DB_FOLDER}/ && \
		sudo -S chown -R :docker ${WORK_FOLDER}/${DB_FOLDER}/ && \
		sudo -S chmod -R u=rwX,g=rwX,o=rX ${WORK_FOLDER}/${DB_FOLDER}/ ; \
		"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		expect "password"; \
		send "$(SERVER__USER_PASSWORD)\r"; \
		expect "*password*" { exit 1 } timeout; \
		' $(HIDDEN_EXPECT) || exit 1; \
	echo ""

swarm-folders-all: ## Copy files stacks and create folders for Docker Swarm to servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory swarm-folders-$(val) || exit 1;)

######################################################################

swarm-copy: ## Copy files stacks for Docker Swarm to servers
	$(eval SERVER__USER_LOGIN := $(value SERVER_1_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_1_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_1_USER_PASSWORD))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Copying files stacks Docker Swarm to server 1 ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	cp ./images.mk ./swarm/.images && \
	sed -i 's/ := /=/g' ./swarm/.images && \
	for i in {1..10}; do sed -i 's/\(^[^=]*\)-/\1_/g' ./swarm/.images; done; \
	echo ""; \
	echo "Products: ${SWARM_PRODUCTS}"; \
	echo ""; \
	echo "Copying to ${WORK_FOLDER}/${SWARM_FOLDER}"; \
	echo ""; \
	cd ${SWARM_FOLDER}; \
	scp $(SCP_OPTIONS) -r ${SWARM_PRODUCTS} .env .images deploy.sh ${SERVER__USER_LOGIN}@${SERVER__IP}:${WORK_FOLDER}/${SWARM_FOLDER}; \
	echo ""

swarm-copy-%: ## Copy files % stack for Docker Swarm to servers
	$(eval SERVER__USER_LOGIN := $(value SERVER_1_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_1_IP))
	$(eval STACK := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "Copying files ${STACK} stack Docker Swarm to server 1 ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	cp ./images.mk ./swarm/.images && \
	sed -i 's/ := /=/g' ./swarm/.images && \
	for i in {1..10}; do sed -i 's/\(^[^=]*\)-/\1_/g' ./swarm/.images; done; \
	echo ""; \
	cd ${SWARM_FOLDER}; \
	scp $(SCP_OPTIONS) -r ${STACK} ${SERVER__USER_LOGIN}@${SERVER__IP}:${WORK_FOLDER}/${SWARM_FOLDER}; \
	echo ""

######################################################################

swarm-up-all: ## Deploy products in Docker Swarm
	@if [ -n "$(SERVER_1_USER_LOGIN)" -a \
			-n "$(SERVER_1_IP)" -a \
			-n "$(SWARM_PRODUCTS)" ]; then \
		for product in ${SWARM_PRODUCTS}; do \
			make --no-print-directory swarm-up-$$product; \
		done; \
		make --no-print-directory swarm-ps; \
	fi

swarm-up: swarm-up-all

######################################################################

swarm-down-all: ## Remove products from Docker Swarm
	@if [ -n "$(SERVER_1_USER_LOGIN)" -a \
			-n "$(SERVER_1_IP)" -a \
			-n "$(SWARM_PRODUCTS)" ]; then \
		$(eval REVERSED_SWARM_PRODUCTS := $(shell echo $(SWARM_PRODUCTS) | tr ' ' '\n' | tac)) \
		for product in ${REVERSED_SWARM_PRODUCTS}; do \
			make --no-print-directory swarm-down-$$product; \
		done; \
		make --no-print-directory swarm-ps; \
	fi

swarm-down: swarm-down-all

######################################################################

swarm-up-%: ## Deploy selected % product in Docker Swarm
	@if [ -n "$(SERVER_1_USER_LOGIN)" -a \
			-n "$(SERVER_1_IP)" -a \
			-n "$(SWARM_PRODUCTS)" ]; then \
		$(eval STACK := $*) \
		ssh -q $(SSH_OPTIONS) ${SERVER_1_USER_LOGIN}@${SERVER_1_IP} 'cd ${WORK_FOLDER}/${SWARM_FOLDER}/ && \
			if [ -d "${STACK}" ]; then \
				echo ""; \
				echo "======================================================================================"; \
				echo -e "Deploy stack \033[44m ${STACK} \033[0m in Docker Swarm"; \
				echo "======================================================================================"; \
				echo ""; \
				cd "${STACK}" && \
				if [ -f ../.env ] && [ -f ../.images ]; then \
					echo "set -a && source ../.env && source ../.images && set +a && docker stack deploy -c docker-compose.yml --with-registry-auth --prune --detach=true ${STACK}"; \
					echo ""; \
					set -a && source ../.env && source ../.images && set +a && docker stack deploy -c docker-compose.yml --with-registry-auth --prune --detach=true ${STACK};  \
				else \
					echo "docker stack deploy -c docker-compose.yml --with-registry-auth --prune --detach=true ${STACK}"; \
					echo ""; \
					docker stack deploy -c docker-compose.yml --with-registry-auth --prune --detach=true ${STACK}; \
				fi && \
				cd ..; \
				if [ "${STACK}" = "portainer" ]; then \
					echo "" && \
					echo "" && \
					echo -e "\033[32;5mLogin Portainer\033[0m https://$(KEEPALIVED_IP):9443  (or https://$(KEEPALIVED_IP)/portainer with traefik)" && \
					echo ""; \
				fi; \
				echo ""; \
				echo "======================================================================================"; \
				echo "docker stack ps ${STACK}"; \
				echo "======================================================================================"; \
				echo ""; \
				docker stack ps ${STACK}; \
				echo ""; \
			else \
				echo ""; \
				echo "Error. There is no such folder as ${STACK}. Skipping..."; \
				echo ""; \
			fi; \
		'; \
	fi

######################################################################

swarm-down-%: ## Remove selected % products from Docker Swarm
	@if [ -n "$(SERVER_1_USER_LOGIN)" -a \
			-n "$(SERVER_1_IP)" -a \
			-n "$(SWARM_PRODUCTS)" ]; then \
		$(eval STACK := $*) \
		ssh -q $(SSH_OPTIONS) ${SERVER_1_USER_LOGIN}@${SERVER_1_IP} 'cd ${WORK_FOLDER}/${SWARM_FOLDER}/ && \
			echo ""; \
			echo "======================================================================================"; \
			echo -e "Remove stack \033[44m ${STACK} \033[0m from Docker Swarm"; \
			echo "======================================================================================"; \
			echo ""; \
			docker stack rm ${STACK}; \
			echo ""; \
			echo "======================================================================================"; \
			echo "docker stack ps ${STACK}"; \
			echo "======================================================================================"; \
			echo ""; \
			docker stack ps ${STACK}; \
			echo ""; \
		'; \
	fi

######################################################################

swarm-update-all: ## Update versions of all images in Docker Swarm
	@make --no-print-directory images-all
	$(eval SERVER__USER_LOGIN := $(value SERVER_1_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_1_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Updating versions of all images in Docker Swarm"; \
	echo "======================================================================================"; \
	echo ""; \
	cp ./images.mk ./swarm/.images && \
	sed -i 's/ := /=/g' ./swarm/.images && \
	for i in {1..10}; do sed -i 's/\(^[^=]*\)-/\1_/g' ./swarm/.images; done; \
	scp $(SCP_OPTIONS) ./swarm/.images ${SERVER__USER_LOGIN}@${SERVER__IP}:${WORK_FOLDER}/${SWARM_FOLDER}; \
	make --no-print-directory swarm-up

swarm-update: swarm-update-all

swarm-update-%: ## Update versions of images of selected product in Docker Swarm
	@make --no-print-directory images-$*
	$(eval SERVER__USER_LOGIN := $(value SERVER_1_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_1_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Updating versions of images of $* in Docker Swarm"; \
	echo "======================================================================================"; \
	echo ""; \
	cp ./images.mk ./swarm/.images && \
	sed -i 's/ := /=/g' ./swarm/.images && \
	for i in {1..10}; do sed -i 's/\(^[^=]*\)-/\1_/g' ./swarm/.images; done; \
	scp $(SCP_OPTIONS) ./swarm/.images ${SERVER__USER_LOGIN}@${SERVER__IP}:${WORK_FOLDER}/${SWARM_FOLDER}; \
	make --no-print-directory swarm-up-$*


######################################################################


swarm-rm-data-%:
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	$(eval SERVER := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "rm -rf ${WORK_FOLDER}/${DATA_FOLDER}/* on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	read -p "Are you sure you want to delete ${DATA_FOLDER}/* ? (y/n): " answer; \
	if [ "$$answer" = "y" ] && [ -n ${WORK_FOLDER} ] && [ -n ${DATA_FOLDER} ]; then \
		expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
			rm -rf ${WORK_FOLDER}/${DATA_FOLDER}/* || sudo -S rm -rf ${WORK_FOLDER}/${DATA_FOLDER}/* && echo \"${WORK_FOLDER}/${DATA_FOLDER}/* deleted.\"; \
			"; \
			expect "password"; \
			send "$(SERVER__USER_PASSWORD)\r"; \
			expect "*password*" { exit 1 } timeout; \
			' $(HIDDEN_EXPECT) || exit 1; \
	else \
		echo "Operation canceled."; \
	fi; \
	echo ""

## Delete data on servers
swarm-rm-data: swarm-rm-data-1


######################################################################


swarm-rm-db-all: ## Delete db on all servers
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@$(foreach val,$(VALUES),make --no-print-directory swarm-rm-db-$(val) || exit 1;)

swarm-rm-db: swarm-rm-db-all

swarm-rm-db-%: ## Delete db on server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER__USER_PASSWORD := $(value SERVER_$*_USER_PASSWORD))
	@echo ""; \
	echo "======================================================================================"; \
	echo "rm -rf ${WORK_FOLDER}/${DB_FOLDER}/* on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	read -p "Are you sure you want to delete ${DB_FOLDER}/* ? (y/n): " answer; \
	if [ "$$answer" = "y" ] && [ -n ${WORK_FOLDER} ] && [ -n ${DB_FOLDER} ]; then \
		expect -c 'spawn ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
			rm -rf ${WORK_FOLDER}/${DB_FOLDER}/* >/dev/null 2>&1 || sudo -S rm -rf ${WORK_FOLDER}/${DB_FOLDER}/* && echo \"${WORK_FOLDER}/${DB_FOLDER}/* deleted.\"; \
			mkdir -p ${WORK_FOLDER}/${DB_FOLDER} ; \
			chown ${SERVER__USER_LOGIN}:docker ${WORK_FOLDER}/${DB_FOLDER} >/dev/null 2>&1 && chmod 775 ${WORK_FOLDER}/${DB_FOLDER} >/dev/null 2>&1 || sudo -S chown ${SERVER__USER_LOGIN}:docker ${WORK_FOLDER}/${DB_FOLDER} && sudo -S chmod 775 ${WORK_FOLDER}/${DB_FOLDER} && echo \"chown ${WORK_FOLDER}/${DB_FOLDER}/ modified.\"; \
			"; \
			expect "password"; \
			send "$(SERVER__USER_PASSWORD)\r"; \
			expect "*password*" { exit 1 } timeout; \
			' $(HIDDEN_EXPECT) || exit 1; \
		echo ""; \
	else \
		echo "Operation canceled."; \
	fi


######################################################################
#################### Keepalived
######################################################################


keepalived-install-all: ## Deploy Keepalived
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@if [ $$(echo $(VALUES) | wc -w) -gt 1 ] && [ -n "${KEEPALIVED_IP}" ]; then \
		echo ""; \
		printf "\033[44mDo you want to deploy Keepalived ? (y/n):\033[0m "; \
		read answer; \
		if [ "$$answer" = "y" ]; then \
			$(foreach val,$(VALUES),make --no-print-directory keepalived-install-$(val) || exit 1;) \
		else \
			echo "Keepalived canceled."; \
		fi; \
	fi

keepalived-install: keepalived-install-all

keepalived-install-%: ## Deploy Keepalived on selected % server
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval VALUES := $(foreach var,$(filter SERVER_%_IP,$(.VARIABLES)),$($(var))))
	$(eval ips := $(foreach ipp,$(VALUES),'$(ipp)',))
	$(eval SERVER := $*)
	@trimmed_string=$$(echo "$(ips)" | sed 's/.$$//'); \
	if [ ${SERVER} -eq 1 ]; then \
		priority="200"; \
	else \
		priority=$$(echo "15$(SERVER)"); \
	fi; \
	echo ""; \
	echo "======================================================================================"; \
	echo "Deploy Keepalived on server $(SERVER) ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	KEEPALIVED_INTERFACE=$$(ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "cat /proc/net/route | awk '\$$2 == \"00000000\" {print \$$1}' | head -n 1"); \
	if [ -z "$$KEEPALIVED_INTERFACE" ]; then \
		echo "KEEPALIVED_INTERFACE error."; \
		exit 1; \
	fi; \
	ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		lsmod | grep -P '^ip_vs\s' >/dev/null 2>&1 || (echo "modprobe ip_vs" >> /etc/modules && modprobe ip_vs); \
		docker run -d --name keepalived --restart=always \
		--cap-add=NET_ADMIN --cap-add=NET_BROADCAST --cap-add=NET_RAW --net=host \
		-e KEEPALIVED_UNICAST_PEERS=\"#PYTHON2BASH:[$$trimmed_string]\" \
		-e KEEPALIVED_VIRTUAL_IPS=${KEEPALIVED_IP} \
		-e KEEPALIVED_INTERFACE=$$KEEPALIVED_INTERFACE \
		-e KEEPALIVED_PASSWORD=password \
		-e KEEPALIVED_PRIORITY=$$priority \
		osixia/keepalived:2.0.20 >/dev/null 2>&1 && \
		echo \"Keepalived started\" || echo \"Keepalived already running\" ; \
		"

######################################################################

keepalived-uninstall-all: ## Remove Keepalived
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@if [ -n "${KEEPALIVED_IP}" ]; then \
		$(foreach val,$(VALUES),make --no-print-directory keepalived-uninstall-$(val) || exit 1;) \
	fi

keepalived-uninstall: keepalived-uninstall-all

keepalived-uninstall-%: ## Remove Keepalived on selected % server
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	$(eval SERVER := $*)
	@echo ""; \
	echo "======================================================================================"; \
	echo "Remove Keepalived on server $(SERVER) ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo ""; \
	ssh -q $(SSH_OPTIONS) $(SERVER__USER_LOGIN)@$(SERVER__IP) "\
		docker stop keepalived && docker rm keepalived && \
		echo \"Keepalived removed\" || echo \"Keepalived not running\" ; \
		"


######################################################################
#################### install everything on server
######################################################################


install-server-%: ## install everything on server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Install everything on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo "";
	@make --no-print-directory ssh-prepare-$* || exit 1;
	@make --no-print-directory configure-$* || exit 1;
	$(eval VALUES := $(sort $(foreach var,$(.VARIABLES),$(if $(filter SERVER_%,$(var)),$(firstword $(subst _, ,$(subst SERVER_,,$(filter SERVER_%,$(var)))))))))
	@if [ $$(echo $(VALUES) | wc -w) -gt 2 ] && [ -n "${GLUSTER_FOLDER}" ]; then \
		echo ""; \
		printf "\033[44mDo you have GlusterFS and want to add this server to it? (y/n):\033[0m "; \
		read answer; \
		if [ "$$answer" = "y" ]; then \
			make --no-print-directory gluster-install-$* || exit 1; \
			make --no-print-directory gluster-config-1 || exit 1; \
			make --no-print-directory gluster-mount-$* || exit 1; \
		else \
			echo "Gluster canceled."; \
		fi; \
	fi;
	@if [ $$(echo $(VALUES) | wc -w) -gt 2 ] && [ -n "${SWARM_PRODUCTS}" ] && [ -n "${GLUSTER_FOLDER}" ]; then \
		echo ""; \
		printf "\033[44mDo you have Docker Swarm and want to add this server to it? (y/n):\033[0m "; \
		read answer; \
		if [ "$$answer" = "y" ]; then \
			make --no-print-directory swarm-join-$* || exit 1; \
			make --no-print-directory keepalived-install-$*; \
		else \
			echo "Docker Swarm canceled."; \
		fi; \
	fi;
	@make --no-print-directory docker-copy-$* || exit 1;
	@make --no-print-directory docker-up-$* || exit 1;
	@make --no-print-directory docker-ps-$* || exit 1;


######################################################################
#################### uninstall everything installed on server
######################################################################


uninstall-server-%: ## uninstall everything installed on server %
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Uninstall everything installed on server $* ${SERVER__USER_LOGIN}@${SERVER__IP}"; \
	echo "======================================================================================"; \
	echo "";
	@make --no-print-directory swarm-uninstall-$* || exit 1;
	@make --no-print-directory docker-rm-$* || exit 1;
	@make --no-print-directory gluster-uninstall-$* || exit 1;
	@make --no-print-directory docker-rm-$* || exit 1;


uninstall-servers: ## uninstall everything installed on servers
	$(eval SERVER__USER_LOGIN := $(value SERVER_$*_USER_LOGIN))
	$(eval SERVER__IP := $(value SERVER_$*_IP))
	@echo ""; \
	echo "======================================================================================"; \
	echo "Uninstall everything installed on all servers"; \
	echo "======================================================================================"; \
	echo "";
	@make --no-print-directory swarm-uninstall-all || exit 1;
	@make --no-print-directory gluster-uninstall-all || exit 1;
	@make --no-print-directory docker-rm-all || exit 1;