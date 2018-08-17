SHELL := /bin/bash

# Make
RD_MAKE_STATE_DIR := .makestate
RUNDECK_IMAGE_DIR := rundeck

# Docker
CONTAINER_PREFIX := $(shell basename $$(pwd))_
NETWORK_NAME := $(CONTAINER_PREFIX)default
NUM_WEB := 2

# Command to call the Rundeck client from outside of the container
RD := docker run --network $(NETWORK_NAME) --mount type=bind,source="$$(pwd)",target=/root playground-rundeck-cli

# Plugins
PLUGINS_SRC_DIR := rundeck-plugins
LOCAL_LIBEXT_DIR := $(RUNDECK_IMAGE_DIR)/libext
PLUGINS = $(shell for p in $$(ls $(PLUGINS_SRC_DIR)); do echo "$(LOCAL_LIBEXT_DIR)/$${p}.zip"; done)
RD_PLUGIN_STATE = $(shell for p in $$(ls $(PLUGINS_SRC_DIR)); do echo "$(RD_MAKE_STATE_DIR)/$${p}.plugin"; done)

# Rundeck container
RUNDECK_CONTAINER := $(CONTAINER_PREFIX)rundeck_1
RUNDECK_CONTAINER_LIBEXT := /home/rundeck/libext
SSH_AUTHORIZED_KEYS := ssh/authorized_keys

# Makes sure the ssh containers authorize the Rundeck server's public key
$(SSH_AUTHORIZED_KEYS): $(RUNDECK_IMAGE_DIR)/ssh/rundeck-playground.pub
	cp $< $@

# Runs docker-compose to spin up the full environment
compose: $(PLUGINS) $(SSH_AUTHORIZED_KEYS)
	docker-compose up --build

# Installs the plugins into the Rundeck container's plugin directory
plugins: $(RD_PLUGIN_STATE)
$(RD_MAKE_STATE_DIR)/%.plugin: $(LOCAL_LIBEXT_DIR)/%.zip
	docker cp $< $(RUNDECK_CONTAINER):/tmp/
	docker exec $(RUNDECK_CONTAINER) \
		/bin/bash -c 'chown rundeck:rundeck /tmp/$$(basename $<) \
			&& mv /tmp/$$(basename $<) $(RUNDECK_CONTAINER_LIBEXT)/'
	touch $@

# Creates the Rundeck project and sets its config properties
RD_PROJECT := hello-project
RD_PROJECT_CONFIG_DIR := rundeck-project
RD_PROJECT_STATE := $(RD_MAKE_STATE_DIR)/$(RD_PROJECT)
$(RD_PROJECT_STATE): $(RD_PROJECT_CONFIG_DIR)/project.properties
	$(RD) projects create -p $(RD_PROJECT) || true
	$(RD) projects configure update  -p $(RD_PROJECT) --file $<
	touch $@

# Installs the Rundeck job configuration
RD_JOBS_ALL := $(RD_MAKE_STATE_DIR)/all.yaml
RD_JOB_FILES = $(shell find rundeck-project -name '*.yaml')

$(RD_JOBS_ALL): $(RD_JOB_FILES) $(RD_PROJECT_STATE)
	cat $^ > $@
	$(RD) jobs load -f $@ --format yaml -p $(RD_PROJECT)

# Creates or updates the keys into Key Storage
RD_KEYS_DIR := rundeck-project/key-storage
RD_KEYS_STATES = $(shell cd $(RD_KEYS_DIR) && \
					for f in $$(find . -type f); do \
					   echo $(RD_MAKE_STATE_DIR)$${f/./}.key; \
					done)
$(RD_MAKE_STATE_DIR)/%.key: $(RD_KEYS_DIR)/%
	$(RD) keys update -t password -f $< --path $* \
		|| $(RD) keys create -t password -f $< --path $*
	mkdir -p $$(dirname $@) && touch $@

# Installs the secrets into the Rundeck Key Storage
keys: $(RD_KEYS_STATES)

# Installs all the Rundeck config, keys and plugin
rd-config: $(RD_PLUGIN_STATE) $(RD_JOBS_ALL) $(RD_KEYS_STATES)

# Triggers a Rundeck job
JOB ?= Hello Test Job
rd-run-job: rd-config
	$(RD) run -p $(RD_PROJECT) -f --job '$(JOB)'

# Updates the web.py file in the running containers to simulate a deployment
update-web:
	for i in $(shell seq 1 $(NUM_WEB)); do \
		container=$(CONTAINER_PREFIX)web_$${i}_1; \
		docker cp web/web.py $${container}:/usr/share/web.py; \
	done

# Clears all file and docker state created by this project
clean: clean-makestate clean-plugins clean-docker

# Clears the make state files
clean-makestate:
	rm -rf $(RD_MAKE_STATE_DIR)/*

# Clears the zipped plugins
clean-plugins:
	rm -f $(RUNDECK_IMAGE_DIR)/libext/*

# Clears all the docker images, containers, network and volumes
clean-docker:
	docker-compose down --rmi all -v

# Don't confuse these recipes with files
.PHONY: compose plugin rd-config rd-run-job update-web keys clean clean-makestate clean-plugins clean-docker

# Some make hackery to create a general rule for compiling plugin zips in PLUGINS_SRC_DIR
.SECONDEXPANSION:
$(LOCAL_LIBEXT_DIR)/%-plugin.zip: $$(shell find $(PLUGINS_SRC_DIR)/%-plugin/ -type f)
	cd $(PLUGINS_SRC_DIR) && zip -r ../$@ $*-plugin
