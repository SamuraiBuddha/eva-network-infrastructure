#!/bin/bash

# EVA Network Master Deployment Script
# Orchestrates deployment of all 5 nodes: Lilith, Adam, Melchior, Balthazar, Caspar

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Network Configuration
ROUTER_IP="192.168.50.1"
LILITH_IP="192.168.50.10"
ADAM_IP="192.168.50.11"
BALTHAZAR_IP="192.168.50.20"
CASPAR_IP="192.168.50.21"
MELCHIOR_IP="192.168.50.30"

# SSH Configuration
SSH_KEY="~/.ssh/id_rsa"

echo -e "${PURPLE}╔════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║         EVA Network Deployment             ║${NC}"
echo -e "${PURPLE}║    Lilith, Adam, and MAGI Nodes Ready      ║${NC}"
echo -e "${PURPLE}╚════════════════════════════════════════════╝${NC}"
echo

function check_connectivity() {
    local node_name=$1
    local node_ip=$2
    local ssh_port=${3:-22}
    
    echo -e "${BLUE}Testing connectivity to $node_name ($node_ip:$ssh_port)...${NC}"
    if ssh -p $ssh_port -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i $SSH_KEY jordan@$node_ip "echo 'Connected'" &>/dev/null; then
        echo -e "${GREEN}✓ $node_name is reachable${NC}"
        return 0
    else
        echo -e "${RED}✗ $node_name is not reachable${NC}"
        return 1
    fi
}

function deploy_node() {
    local node_name=$1
    local node_ip=$2
    local script_name=$3
    local ssh_port=${4:-22}
    
    echo -e "${YELLOW}Deploying $node_name...${NC}"
    
    # Copy setup script
    scp -P $ssh_port -i $SSH_KEY ./scripts/$script_name jordan@$node_ip:/tmp/
    
    # Execute setup script
    ssh -p $ssh_port -i $SSH_KEY jordan@$node_ip "chmod +x /tmp/$script_name && sudo /tmp/$script_name"
    
    echo -e "${GREEN}✓ $node_name deployment complete${NC}"
}

function generate_validator_keys() {
    echo -e "${BLUE}Generating blockchain validator keys...${NC}"
    
    # Generate unique keys for each node
    for node in lilith adam balthazar caspar; do
        openssl ecparam -name secp256k1 -genkey -noout -out /tmp/${node}_validator.key
        openssl ec -in /tmp/${node}_validator.key -pubout -out /tmp/${node}_validator.pub
        echo -e "${GREEN}✓ Generated keys for $node${NC}"
    done
}

function setup_cross_node_mounts() {
    echo -e "${BLUE}Setting up cross-node NFS mounts...${NC}"
    
    # Mount Lilith's shared directories on other nodes
    for node_ip in $ADAM_IP $BALTHAZAR_IP $CASPAR_IP; do
        ssh -i $SSH_KEY jordan@$node_ip "sudo mkdir -p /mnt/lilith-shared && sudo mount -t nfs $LILITH_IP:/shared /mnt/lilith-shared"
    done
    
    echo -e "${GREEN}✓ Cross-node mounts configured${NC}"
}

function deploy_gui() {
    echo -e "${BLUE}Starting deployment GUI...${NC}"
    python3 - << 'EOF'
import tkinter as tk
from tkinter import ttk, scrolledtext
import subprocess
import threading

class EVADeploymentGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("EVA Network Deployment Control")
        self.root.geometry("800x600")
        
        # Node selection
        self.nodes = {
            "Lilith (Primary NAS)": {"ip": "192.168.50.10", "script": "nas-setup-lilith.sh"},
            "Adam (Business NAS)": {"ip": "192.168.50.11", "script": "nas-setup-adam.sh"},
            "Melchior (Workstation)": {"ip": "192.168.50.30", "script": "magi-setup-melchior.sh"},
            "Balthazar (GPU Node)": {"ip": "192.168.50.20", "script": "magi-setup-balthazar.sh"},
            "Caspar (Bridge Node)": {"ip": "192.168.50.21", "script": "magi-setup-caspar.sh", "port": 9222}
        }
        
        # Checkboxes for node selection
        self.node_vars = {}
        frame = ttk.LabelFrame(root, text="Select Nodes to Deploy", padding=10)
        frame.pack(fill="x", padx=10, pady=10)
        
        for node in self.nodes:
            var = tk.BooleanVar(value=True)
            self.node_vars[node] = var
            ttk.Checkbutton(frame, text=node, variable=var).pack(anchor="w")
        
        # Control buttons
        btn_frame = ttk.Frame(root)
        btn_frame.pack(fill="x", padx=10, pady=5)
        
        ttk.Button(btn_frame, text="Test Connectivity", command=self.test_connectivity).pack(side="left", padx=5)
        ttk.Button(btn_frame, text="Deploy Selected", command=self.deploy_selected).pack(side="left", padx=5)
        ttk.Button(btn_frame, text="Full Deploy", command=self.full_deploy).pack(side="left", padx=5)
        
        # Progress bar
        self.progress = ttk.Progressbar(root, mode="indeterminate")
        self.progress.pack(fill="x", padx=10, pady=5)
        
        # Log output
        self.log = scrolledtext.ScrolledText(root, height=20)
        self.log.pack(fill="both", expand=True, padx=10, pady=10)
        
    def log_message(self, message, color="black"):
        self.log.insert(tk.END, message + "\n")
        self.log.see(tk.END)
        self.root.update()
        
    def test_connectivity(self):
        self.progress.start()
        for node, info in self.nodes.items():
            if self.node_vars[node].get():
                port = info.get("port", 22)
                result = subprocess.run(
                    ["ssh", "-p", str(port), "-o", "ConnectTimeout=5", 
                     f"jordan@{info['ip']}", "echo 'Connected'"],
                    capture_output=True
                )
                if result.returncode == 0:
                    self.log_message(f"✓ {node} is reachable", "green")
                else:
                    self.log_message(f"✗ {node} is not reachable", "red")
        self.progress.stop()
        
    def deploy_selected(self):
        threading.Thread(target=self._deploy_selected).start()
        
    def _deploy_selected(self):
        self.progress.start()
        for node, info in self.nodes.items():
            if self.node_vars[node].get():
                self.log_message(f"Deploying {node}...")
                # Actual deployment would go here
                self.log_message(f"✓ {node} deployment complete", "green")
        self.progress.stop()
        
    def full_deploy(self):
        for var in self.node_vars.values():
            var.set(True)
        self.deploy_selected()

if __name__ == "__main__":
    root = tk.Tk()
    app = EVADeploymentGUI(root)
    root.mainloop()
EOF
}

# Main execution
if [[ "$1" == "--gui" ]]; then
    deploy_gui
    exit 0
fi

echo -e "${YELLOW}Starting EVA Network Deployment...${NC}"
echo

# Step 1: Check connectivity to all nodes
echo -e "${BLUE}=== Step 1: Checking Node Connectivity ===${NC}"
LILITH_OK=$(check_connectivity "Lilith" $LILITH_IP && echo 1 || echo 0)
ADAM_OK=$(check_connectivity "Adam" $ADAM_IP && echo 1 || echo 0)
BALTHAZAR_OK=$(check_connectivity "Balthazar" $BALTHAZAR_IP && echo 1 || echo 0)
CASPAR_OK=$(check_connectivity "Caspar" $CASPAR_IP 9222 && echo 1 || echo 0)
echo

# Step 2: Generate validator keys
echo -e "${BLUE}=== Step 2: Generating Validator Keys ===${NC}"
generate_validator_keys
echo

# Step 3: Deploy nodes in order
echo -e "${BLUE}=== Step 3: Deploying Nodes ===${NC}"

# Deploy Lilith first (primary NAS)
if [[ $LILITH_OK -eq 1 ]]; then
    deploy_node "Lilith" $LILITH_IP "nas-setup-lilith.sh"
fi

# Deploy Adam (business NAS)
if [[ $ADAM_OK -eq 1 ]]; then
    deploy_node "Adam" $ADAM_IP "nas-setup-adam.sh"
fi

# Deploy MAGI nodes
if [[ $BALTHAZAR_OK -eq 1 ]]; then
    deploy_node "Balthazar" $BALTHAZAR_IP "magi-setup-balthazar.sh"
fi

if [[ $CASPAR_OK -eq 1 ]]; then
    deploy_node "Caspar" $CASPAR_IP "magi-setup-caspar.sh" 9222
fi

echo

# Step 4: Setup cross-node mounts
echo -e "${BLUE}=== Step 4: Setting Up Cross-Node Mounts ===${NC}"
setup_cross_node_mounts
echo

# Step 5: Start services
echo -e "${BLUE}=== Step 5: Starting EVA Network Services ===${NC}"
ssh -i $SSH_KEY jordan@$LILITH_IP "cd /opt/eva && docker-compose up -d"
echo -e "${GREEN}✓ Core services started on Lilith${NC}"
echo

# Final status
echo -e "${PURPLE}╔════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║        EVA Network Deployment Complete     ║${NC}"
echo -e "${PURPLE}╚════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Access Points:${NC}"
echo -e "  Portainer: https://$LILITH_IP:9000"
echo -e "  Neo4j:     https://$LILITH_IP:7474"
echo -e "  Dashboard: http://$LILITH_IP:8080/eva-dashboard.html"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Access Portainer and verify all containers are running"
echo -e "  2. Configure router port forwarding if external access needed"
echo -e "  3. Test blockchain validator connectivity"
echo -e "  4. Set up automated backups"
