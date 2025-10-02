# Keystone VM Infrastructure Management Makefile

VM_IMAGES_DIR = ./vm-images
SNAPSHOT_DIR = $(VM_IMAGES_DIR)/snapshots
SCRIPTS_DIR = ./scripts
NETWORK_NAME = keystone-net
VMS = router storage client backup dev off-site

# Disk sizes for each VM
ROUTER_DISK_SIZE = 16G
STORAGE_DISK_SIZE = 32G
CLIENT_DISK_SIZE = 64G
BACKUP_DISK_SIZE = 32G
DEV_DISK_SIZE = 48G
OFFSITE_DISK_SIZE = 8G

.PHONY: help setup-network teardown-network status clean-all clean-network
.PHONY: $(addprefix up-,$(VMS)) $(addprefix down-,$(VMS)) $(addprefix clean-,$(VMS))
.PHONY: up-all down-all deploy-all build-iso snapshot-all

help: ## Show this help message
	@echo "Keystone VM Infrastructure Management"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make setup-network            - Create the keystone-net virtual network"
	@echo "  make build-iso                - Build Keystone installer ISO"
	@echo ""
	@echo "VM Management Commands:"
	@echo "  make up-all                   - Start all VMs"
	@echo "  make up-<vm>                  - Start specific VM (router, storage, client, backup, dev, off-site)"
	@echo "  make down-all                 - Stop all VMs"
	@echo "  make down-<vm>                - Stop specific VM"
	@echo "  make deploy-all               - Deploy configurations to all VMs"
	@echo "  make deploy-<vm> [CONFIG=x]   - Deploy configuration to specific VM"
	@echo ""
	@echo "Maintenance Commands:"
	@echo "  make status                   - Show status of all VMs and network"
	@echo "  make snapshot-all             - Create snapshots of all running VMs"
	@echo "  make clean-<vm>               - Remove specific VM and its disks"
	@echo "  make clean-all                - Remove all VMs and disks"
	@echo "  make clean-network            - Remove the virtual network"
	@echo "  make teardown-network         - Stop network and remove all VMs"
	@echo ""
	@echo "Available VMs: $(VMS)"

setup-network: ## Create the keystone-net virtual network
	@echo "Setting up Keystone virtual network..."
	@if ! virsh net-list --all | grep -q "$(NETWORK_NAME)"; then \
		virsh net-define network/keystone-net.xml; \
		echo "Network $(NETWORK_NAME) defined"; \
	else \
		echo "Network $(NETWORK_NAME) already exists"; \
	fi
	@if ! virsh net-list | grep -q "$(NETWORK_NAME).*active"; then \
		virsh net-start $(NETWORK_NAME); \
		echo "Network $(NETWORK_NAME) started"; \
	else \
		echo "Network $(NETWORK_NAME) already active"; \
	fi
	@virsh net-autostart $(NETWORK_NAME)
	@echo "Network setup complete"

build-iso: ## Build Keystone installer ISO
	@echo "Building Keystone ISO..."
	@$(SCRIPTS_DIR)/build-and-boot.sh router

# VM creation targets
up-router: setup-network ## Start router VM
	@$(call create_vm,router,$(ROUTER_DISK_SIZE))

up-storage: setup-network ## Start storage VM  
	@$(call create_vm_with_data_disks,storage,$(STORAGE_DISK_SIZE))

up-client: setup-network ## Start client VM
	@$(call create_vm,client,$(CLIENT_DISK_SIZE))

up-backup: setup-network ## Start backup VM
	@$(call create_vm_with_backup_disk,backup,$(BACKUP_DISK_SIZE))

up-dev: setup-network ## Start dev VM
	@$(call create_vm,dev,$(DEV_DISK_SIZE))

up-off-site: setup-network ## Start off-site VM
	@$(call create_vm,off-site,$(OFFSITE_DISK_SIZE))

up-all: $(addprefix up-,$(VMS)) ## Start all VMs

# VM shutdown targets
down-router: ## Stop router VM
	@$(call stop_vm,router)

down-storage: ## Stop storage VM
	@$(call stop_vm,storage)

down-client: ## Stop client VM
	@$(call stop_vm,client)

down-backup: ## Stop backup VM
	@$(call stop_vm,backup)

down-dev: ## Stop dev VM
	@$(call stop_vm,dev)

down-off-site: ## Stop off-site VM
	@$(call stop_vm,off-site)

down-all: $(addprefix down-,$(VMS)) ## Stop all VMs

# Deployment targets
deploy-router: ## Deploy router configuration
	@$(SCRIPTS_DIR)/deploy-vm.sh router $(or $(CONFIG),router)

deploy-storage: ## Deploy storage configuration
	@$(SCRIPTS_DIR)/deploy-vm.sh storage $(or $(CONFIG),storage)

deploy-client: ## Deploy client configuration
	@$(SCRIPTS_DIR)/deploy-vm.sh client $(or $(CONFIG),client)

deploy-backup: ## Deploy backup configuration
	@$(SCRIPTS_DIR)/deploy-vm.sh backup $(or $(CONFIG),backup)

deploy-dev: ## Deploy dev configuration
	@$(SCRIPTS_DIR)/deploy-vm.sh dev $(or $(CONFIG),dev)

deploy-off-site: ## Deploy off-site configuration
	@$(SCRIPTS_DIR)/deploy-vm.sh off-site $(or $(CONFIG),off-site)

deploy-all: ## Deploy configurations to all VMs
	@echo "Deploying configurations to all VMs..."
	@for vm in $(VMS); do \
		if virsh list | grep -q "keystone-$$vm.*running"; then \
			echo "Deploying to $$vm..."; \
			$(SCRIPTS_DIR)/deploy-vm.sh $$vm $$vm || echo "Warning: Deployment to $$vm failed"; \
		else \
			echo "Skipping $$vm (not running)"; \
		fi; \
	done

# Status and monitoring
status: ## Show status of all VMs and network
	@echo "=== Keystone VM Infrastructure Status ==="
	@echo ""
	@echo "Network Status:"
	@virsh net-list | grep -E "(Name|$(NETWORK_NAME))" || echo "Network $(NETWORK_NAME) not found"
	@echo ""
	@echo "VM Status:"
	@virsh list --all | grep -E "(Id|keystone-)" || echo "No Keystone VMs found"
	@echo ""
	@echo "DHCP Leases:"
	@virsh net-dhcp-leases $(NETWORK_NAME) 2>/dev/null || echo "No DHCP leases found"

# Snapshot management
snapshot-all: ## Create snapshots of all running VMs
	@echo "Creating snapshots of all running VMs..."
	@mkdir -p $(SNAPSHOT_DIR)
	@for vm in $(VMS); do \
		if virsh list | grep -q "keystone-$$vm.*running"; then \
			echo "Creating snapshot for $$vm..."; \
			$(call create_snapshot,$$vm); \
		else \
			echo "Skipping $$vm (not running)"; \
		fi; \
	done

# Cleanup targets
clean-router: ## Remove router VM and disks
	@$(call cleanup_vm,router)

clean-storage: ## Remove storage VM and disks
	@$(call cleanup_vm_with_data_disks,storage)

clean-client: ## Remove client VM and disks
	@$(call cleanup_vm,client)

clean-backup: ## Remove backup VM and disks
	@$(call cleanup_vm_with_backup_disk,backup)

clean-dev: ## Remove dev VM and disks
	@$(call cleanup_vm,dev)

clean-off-site: ## Remove off-site VM and disks
	@$(call cleanup_vm,off-site)

clean-all: $(addprefix clean-,$(VMS)) ## Remove all VMs and disks
	@echo "Cleaning up VM images directory..."
	@rm -rf $(VM_IMAGES_DIR)

clean-network: ## Remove the virtual network
	@echo "Removing Keystone virtual network..."
	@virsh net-destroy $(NETWORK_NAME) 2>/dev/null || true
	@virsh net-undefine $(NETWORK_NAME) 2>/dev/null || true
	@echo "Network $(NETWORK_NAME) removed"

teardown-network: down-all clean-all clean-network ## Complete teardown

# Helper functions
define create_vm
	@echo "Creating VM: keystone-$(1)"
	@mkdir -p $(VM_IMAGES_DIR)
	@if [ ! -f "/tmp/keystone-$(1).qcow2" ]; then \
		qemu-img create -f qcow2 /tmp/keystone-$(1).qcow2 $(2); \
	fi
	@if ! virsh list --all | grep -q "keystone-$(1)"; then \
		virsh define vms/$(1)/vm.xml; \
	fi
	@if ! virsh list | grep -q "keystone-$(1).*running"; then \
		virsh start keystone-$(1); \
		echo "VM keystone-$(1) started"; \
	else \
		echo "VM keystone-$(1) already running"; \
	fi
endef

define create_vm_with_data_disks
	@echo "Creating storage VM with data disks: keystone-$(1)"
	@mkdir -p $(VM_IMAGES_DIR)
	@if [ ! -f "/tmp/keystone-$(1).qcow2" ]; then \
		qemu-img create -f qcow2 /tmp/keystone-$(1).qcow2 $(2); \
	fi
	@if [ ! -f "/tmp/keystone-$(1)-data1.qcow2" ]; then \
		qemu-img create -f qcow2 /tmp/keystone-$(1)-data1.qcow2 64G; \
	fi
	@if [ ! -f "/tmp/keystone-$(1)-data2.qcow2" ]; then \
		qemu-img create -f qcow2 /tmp/keystone-$(1)-data2.qcow2 64G; \
	fi
	@if ! virsh list --all | grep -q "keystone-$(1)"; then \
		virsh define vms/$(1)/vm.xml; \
	fi
	@if ! virsh list | grep -q "keystone-$(1).*running"; then \
		virsh start keystone-$(1); \
		echo "VM keystone-$(1) started with data disks"; \
	else \
		echo "VM keystone-$(1) already running"; \
	fi
endef

define create_vm_with_backup_disk
	@echo "Creating backup VM with backup disk: keystone-$(1)"
	@mkdir -p $(VM_IMAGES_DIR)
	@if [ ! -f "/tmp/keystone-$(1).qcow2" ]; then \
		qemu-img create -f qcow2 /tmp/keystone-$(1).qcow2 $(2); \
	fi
	@if [ ! -f "/tmp/keystone-$(1)-storage.qcow2" ]; then \
		qemu-img create -f qcow2 /tmp/keystone-$(1)-storage.qcow2 128G; \
	fi
	@if ! virsh list --all | grep -q "keystone-$(1)"; then \
		virsh define vms/$(1)/vm.xml; \
	fi
	@if ! virsh list | grep -q "keystone-$(1).*running"; then \
		virsh start keystone-$(1); \
		echo "VM keystone-$(1) started with backup disk"; \
	else \
		echo "VM keystone-$(1) already running"; \
	fi
endef

define stop_vm
	@echo "Stopping VM: keystone-$(1)"
	@virsh destroy keystone-$(1) 2>/dev/null || true
	@echo "VM keystone-$(1) stopped"
endef

define cleanup_vm
	@echo "Cleaning up VM: keystone-$(1)"
	@virsh destroy keystone-$(1) 2>/dev/null || true
	@virsh undefine keystone-$(1) --nvram 2>/dev/null || true
	@rm -f /tmp/keystone-$(1).qcow2
	@echo "VM keystone-$(1) removed"
endef

define cleanup_vm_with_data_disks
	@echo "Cleaning up storage VM with data disks: keystone-$(1)"
	@virsh destroy keystone-$(1) 2>/dev/null || true
	@virsh undefine keystone-$(1) --nvram 2>/dev/null || true
	@rm -f /tmp/keystone-$(1).qcow2
	@rm -f /tmp/keystone-$(1)-data1.qcow2
	@rm -f /tmp/keystone-$(1)-data2.qcow2
	@echo "VM keystone-$(1) and data disks removed"
endef

define cleanup_vm_with_backup_disk
	@echo "Cleaning up backup VM with backup disk: keystone-$(1)"
	@virsh destroy keystone-$(1) 2>/dev/null || true
	@virsh undefine keystone-$(1) --nvram 2>/dev/null || true
	@rm -f /tmp/keystone-$(1).qcow2
	@rm -f /tmp/keystone-$(1)-storage.qcow2
	@echo "VM keystone-$(1) and backup disk removed"
endef

define create_snapshot
	@SNAPSHOT_NAME="keystone-$(1)_$$(date +%Y%m%d_%H%M%S)" && \
	echo "Creating snapshot: $$SNAPSHOT_NAME" && \
	virsh snapshot-create-as --domain keystone-$(1) "$$SNAPSHOT_NAME" "Snapshot taken on $$(date)" --atomic && \
	echo "Snapshot $$SNAPSHOT_NAME created successfully"
endef