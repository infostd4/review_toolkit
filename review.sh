#!/bin/bash
set -euo pipefail

# IC Network Analysis Toolkit - Unified Command
# Combines node checking, subnet analysis, and whatif functionality

# --- CONFIG ---
IC_ADMIN="ic-admin --json --nns-urls https://ic0.app"
OUTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$OUTDIR/data"
SCRIPT_NAME="$(basename "$0")"

# Output files
NODE_CSV="$DATA_DIR/nodes_status.csv"
OP_CSV="$DATA_DIR/node_operators_status.csv"
DC_CSV="$DATA_DIR/datacenter_status.csv"
REW_CSV="$DATA_DIR/node_reward_types.csv"
FINAL_CSV="$DATA_DIR/nodes_full_audit.csv"
SUBNET_CSV="$DATA_DIR/subnet_analysis.csv"
WHATIF_CSV="$DATA_DIR/subnet_whatif.csv"
FULL_AUDIT_CSV="$DATA_DIR/subnet_full_audit.csv"

# --- HELP FUNCTION ---
show_help() {
  cat << 'EOF'
IC Network Analysis Toolkit - Unified Command

USAGE:
  review.sh <command> [options]

COMMANDS:
  nodes <node1> [node2] [node3] ...     Check specific node records (or reads from node_list.md)
  subnet <subnet_id>                    Analyze subnet composition
  whatif [subnet_id] [options]          Simulate subnet changes (reads from subnet_whatif.txt if no args)

OPTIONS FOR 'whatif':
  --add-nodes <node1> [node2] ...       Add nodes to subnet
  --remove-nodes <node1> [node2] ...    Remove nodes from subnet
  --map                                 Generate interactive map after analysis
  --geo                                 Show geographic summary after analysis

EXAMPLES:
  # Check specific nodes
  review.sh nodes node1-id node2-id node3-id

  # Check all nodes from node_list.md
  review.sh nodes

  # Analyze a subnet
  review.sh subnet cv73p-6v7zi-u67oy-7jc3h-qspsz-g5lrj-4fn7k-xrax3-thek2-sl46v-jae

  # Simulate adding nodes to a subnet
  review.sh whatif cv73p-6v7zi-u67oy-7jc3h-qspsz-g5lrj-4fn7k-xrax3-thek2-sl46v-jae --add-nodes new-node-1 new-node-2

  # Simulate changes from subnet_whatif.txt file
  review.sh whatif

  # Simulate removing and adding nodes with visualization
  review.sh whatif cv73p-6v7zi-u67oy-7jc3h-qspsz-g5lrj-4fn7k-xrax3-thek2-sl46v-jae --remove-nodes old-node-1 --add-nodes new-node-1 --map --geo

OUTPUT FILES:
  data/nodes_full_audit.csv     - Detailed node analysis
  data/subnet_full_audit.csv    - Subnet analysis with changes
  data/subnet_map.html          - Interactive geographic map (with --map)

CONFIGURATION FILES:
  node_list.md                  - List of node IDs for bulk analysis
  subnet_whatif.txt              - Subnet ID and node changes for whatif analysis

EOF
}

# --- UTILITY FUNCTIONS ---
log_info() {
  echo "ℹ️  $1"
}

log_success() {
  echo "✅ $1"
}

log_error() {
  echo "❌ $1" >&2
}

log_progress() {
  echo "🔄 $1"
}

# Function to make parallel API calls for node data
fetch_nodes_parallel() {
  local nodes=("$@")
  local total=${#nodes[@]}
  
  log_progress "Fetching $total node records in parallel..."
  
  # Create temp directory for parallel processing
  local temp_dir=$(mktemp -d)
  
  # Start parallel jobs
  local pids=()
  for i in "${!nodes[@]}"; do
    local node="${nodes[$i]}"
    {
      $IC_ADMIN get-node "$node" 2>/dev/null > "$temp_dir/node_${i}.json" || touch "$temp_dir/node_${i}.failed"
    } &
    pids+=($!)
  done
  
  # Wait for all jobs and show progress
  local completed=0
  for pid in "${pids[@]}"; do
    wait $pid
    ((completed++))
    printf "\r🔄 Progress: $completed/$total nodes fetched"
  done
  printf "\n"
  
  # Process results
  for i in "${!nodes[@]}"; do
    local node="${nodes[$i]}"
    if [ -f "$temp_dir/node_${i}.json" ] && [ ! -f "$temp_dir/node_${i}.failed" ]; then
      python3 <<EOF >> "$NODE_CSV"
import json
import sys

try:
    with open('$temp_dir/node_${i}.json', 'r') as f:
        node_data = json.load(f)
    
    # The node data is in 'value' field, not 'node'
    node = node_data.get('value', {})
    
    version = node_data.get('version', '')
    node_id = '$node'  # Use the node ID from the loop
    xnet = node.get('xnet', '')
    http = node.get('http', '')
    node_operator_id = node.get('node_operator_id', '')
    chip_id = node.get('chip_id', '')
    hostos_version_id = node.get('hostos_version_id', '')
    public_ipv4_config = str(node.get('public_ipv4_config', '')).replace(',', ';').replace('\n', ' ').replace('\r', '').replace('"', '""')
    domain = node.get('domain', '')
    node_reward_type = node.get('node_reward_type', '')
    
    # Properly escape fields for CSV
    fields = [version, node_id, xnet, http, node_operator_id, chip_id, hostos_version_id, public_ipv4_config, domain, node_reward_type]
    csv_fields = []
    for field in fields:
        field_str = str(field) if field is not None else ''
        # Escape double quotes and wrap in quotes if contains comma, newline, or quote
        if ',' in field_str or '\n' in field_str or '"' in field_str:
            field_str = f'"{field_str}"'
        csv_fields.append(field_str)
    
    print(','.join(csv_fields))

except Exception as e:
    print(f"Error processing node $i ($node): {e}", file=sys.stderr)
EOF
    fi
  done
  
  # Cleanup
  rm -rf "$temp_dir"
}

# Function to generate comprehensive node audit
generate_node_audit() {
  local nodes=("$@")
  
  log_progress "Generating comprehensive node audit..."
  
  mkdir -p "$DATA_DIR"
  
  # Initialize CSV files
  echo "version,node_id,xnet,http,node_operator_id,chip_id,hostos_version_id,public_ipv4_config,domain,node_reward_type" > "$NODE_CSV"
  
  # Fetch nodes in parallel
  fetch_nodes_parallel "${nodes[@]}"
  
  # Extract unique node operator IDs
  NODE_OP_IDS=($(tail -n +2 "$NODE_CSV" | cut -d',' -f5 | sort -u | grep -v '^$'))
  
  if [ ${#NODE_OP_IDS[@]} -eq 0 ]; then
    log_error "No valid node operator IDs found"
    return 1
  fi
  
  log_progress "Fetching ${#NODE_OP_IDS[@]} node operator records in parallel..."
  
  # Fetch node operators in parallel
  echo "principal_id,display_name,node_allowance,rewardable_nodes,ipv6,dc_id" > "$OP_CSV"
  local failed_operators=()
  
  # Create temp directory for parallel processing
  local temp_op_dir=$(mktemp -d)
  
  # Start parallel jobs for operators
  local op_pids=()
  for i in "${!NODE_OP_IDS[@]}"; do
    local op_id="${NODE_OP_IDS[$i]}"
    {
      $IC_ADMIN get-node-operator "$op_id" 2>/dev/null > "$temp_op_dir/op_${i}.json" || touch "$temp_op_dir/op_${i}.failed"
    } &
    op_pids+=($!)
  done
  
  # Wait for all operator jobs and show progress
  local op_completed=0
  for pid in "${op_pids[@]}"; do
    wait $pid
    ((op_completed++))
    printf "\r🔄 Progress: $op_completed/${#NODE_OP_IDS[@]} operators fetched"
  done
  printf "\n"
  
  # Process operator results
  for i in "${!NODE_OP_IDS[@]}"; do
    local op_id="${NODE_OP_IDS[$i]}"
    if [ -f "$temp_op_dir/op_${i}.json" ] && [ ! -f "$temp_op_dir/op_${i}.failed" ]; then
      python3 <<EOF >> "$OP_CSV"
import json
import sys

try:
    with open('$temp_op_dir/op_${i}.json', 'r') as f:
        data = json.load(f)
    
    # Operator data is in 'value' field
    operator = data.get('value', {})
    
    principal_id = operator.get('node_operator_principal_id', '')
    display_name = operator.get('node_provider_principal_id', '')
    node_allowance = operator.get('node_allowance', '')
    
    rewardable_nodes = []
    for region_id, count in operator.get('rewardable_nodes', {}).items():
        rewardable_nodes.append(f"{region_id}:{count}")
    rewardable_nodes_str = ';'.join(rewardable_nodes)
    
    ipv6 = operator.get('ipv6', '')
    dc_id = operator.get('dc_id', '')
    
    print(f"{principal_id},{display_name},{node_allowance},{rewardable_nodes_str},{ipv6},{dc_id}")

except Exception as e:
    print(f"Error processing operator $i ({op_id}): {e}", file=sys.stderr)
EOF
    else
      log_error "Failed to fetch operator: $op_id (operator may not exist in registry)"
      failed_operators+=("$op_id")
      # Add a placeholder entry for missing operator
      echo "$op_id,MISSING_OPERATOR,0,,,[MISSING]" >> "$OP_CSV"
    fi
  done
  
  # Cleanup
  rm -rf "$temp_op_dir"
  
  if [ ${#failed_operators[@]} -gt 0 ]; then
    log_error "Found ${#failed_operators[@]} missing/invalid node operators:"
    printf '  - %s\n' "${failed_operators[@]}"
  fi
  
  # Extract unique datacenter IDs
  DC_IDS=($(tail -n +2 "$OP_CSV" | cut -d',' -f6 | sort -u | grep -v '^$'))
  
  if [ ${#DC_IDS[@]} -eq 0 ]; then
    log_error "No valid datacenter IDs found"
    return 1
  fi
  
  log_progress "Fetching ${#DC_IDS[@]} datacenter records in parallel..."
  
  # Fetch datacenters in parallel
  echo "datacenter_id,region,owner,gps_latitude,gps_longitude" > "$DC_CSV"
  
  # Create temp directory for parallel processing
  local temp_dc_dir=$(mktemp -d)
  
  # Start parallel jobs for datacenters
  local dc_pids=()
  for i in "${!DC_IDS[@]}"; do
    local dc_id="${DC_IDS[$i]}"
    {
      $IC_ADMIN get-data-center "$dc_id" 2>/dev/null > "$temp_dc_dir/dc_${i}.json" || touch "$temp_dc_dir/dc_${i}.failed"
    } &
    dc_pids+=($!)
  done
  
  # Wait for all datacenter jobs and show progress
  local dc_completed=0
  for pid in "${dc_pids[@]}"; do
    wait $pid
    ((dc_completed++))
    printf "\r🔄 Progress: $dc_completed/${#DC_IDS[@]} datacenters fetched"
  done
  printf "\n"
  
  # Process datacenter results
  for i in "${!DC_IDS[@]}"; do
    local dc_id="${DC_IDS[$i]}"
    if [ -f "$temp_dc_dir/dc_${i}.json" ] && [ ! -f "$temp_dc_dir/dc_${i}.failed" ]; then
      python3 <<EOF >> "$DC_CSV"
import json
import sys

try:
    with open('$temp_dc_dir/dc_${i}.json', 'r') as f:
        data = json.load(f)
    
    # Datacenter data is in 'value' field
    datacenter = data.get('value', {})
    
    datacenter_id = datacenter.get('id', '')
    region = datacenter.get('region', '')
    owner = datacenter.get('owner', '')
    
    # Extract GPS coordinates
    gps = datacenter.get('gps', {})
    gps_latitude = gps.get('latitude', '') if gps else ''
    gps_longitude = gps.get('longitude', '') if gps else ''
    
    # Properly escape commas in region field for CSV
    region_escaped = f'"{region}"' if ',' in region else region
    
    print(f"{datacenter_id},{region_escaped},{owner},{gps_latitude},{gps_longitude}")

except Exception as e:
    print(f"Error processing datacenter {i} ({dc_id}): {e}", file=sys.stderr)
EOF
    fi
  done
  
  # Cleanup
  rm -rf "$temp_dc_dir"
  
  # Fetch reward types
  log_progress "Fetching node reward types..."
  echo "region,reward_type,xdr_permyriad_per_node_per_month,reward_coefficient_percent" > "$REW_CSV"
  $IC_ADMIN get-node-rewards-table 2>/dev/null > tmp_rewards.json || true
  if [ -f tmp_rewards.json ]; then
    python3 <<EOF >> "$REW_CSV"
import json
import sys

try:
    with open('tmp_rewards.json', 'r') as f:
        data = json.load(f)
    
    # The rewards table is organized by region -> reward_type -> details
    for region, reward_types in data.items():
        for reward_type, details in reward_types.items():
            xdr_amount = details.get('xdr_permyriad_per_node_per_month', '')
            coefficient = details.get('reward_coefficient_percent', '')
            
            # Properly escape region if it contains commas
            region_escaped = f'"{region}"' if ',' in region else region
            
            print(f"{region_escaped},{reward_type},{xdr_amount},{coefficient}")

except Exception as e:
    print(f"Error processing rewards data: {e}", file=sys.stderr)
EOF
  fi

  # Create comprehensive joined audit file
  log_progress "Creating comprehensive audit by joining all data..."
  cd "$DATA_DIR"
  python3 <<'EOF'
import csv
import json
import sys
from collections import defaultdict

# Read all CSV files into memory
nodes = {}
operators = {}
datacenters = {}
rewards = {}

# Read nodes
try:
    with open('nodes_status.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes[row['node_id']] = row
except FileNotFoundError:
    print("Warning: nodes_status.csv not found", file=sys.stderr)

# Read operators
try:
    with open('node_operators_status.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            operators[row['principal_id']] = row
except FileNotFoundError:
    print("Warning: node_operators_status.csv not found", file=sys.stderr)

# Read datacenters
try:
    with open('datacenter_status.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            datacenters[row['datacenter_id']] = row
except FileNotFoundError:
    print("Warning: datacenter_status.csv not found", file=sys.stderr)

# Read rewards (create lookup by region and reward_type)
try:
    with open('node_reward_types.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row['region'].strip('"'), row['reward_type'])
            rewards[key] = row
except FileNotFoundError:
    print("Warning: node_reward_types.csv not found", file=sys.stderr)

# Create comprehensive audit
with open('nodes_full_audit.csv', 'w', newline='') as f:
    fieldnames = [
        'version', 'node_id', 'hostos_version_id', 'node_operator_id', 
        'node_provider_id', 'node_allowance', 'node_reward_type', 
        'node_operator_rewardable_nodes', 'node_operator_dc', 'dc_owner', 
        'dc_region', 'reward_region', 'reward_xdr', 'reward_coefficient',
        'reward_table_issue', 'node_operator_principal_id_mismatch', 
        'reward_type_mismatch', 'gps_latitude', 'gps_longitude'
    ]
    
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    
    for node_id, node in nodes.items():
        row = {}
        
        # Node data
        row['version'] = node.get('version', '')
        row['node_id'] = node_id
        row['hostos_version_id'] = node.get('hostos_version_id', '')
        row['node_operator_id'] = node.get('node_operator_id', '')
        row['node_reward_type'] = node.get('node_reward_type', '')
        
        # Operator data
        operator_id = node.get('node_operator_id', '')
        operator = operators.get(operator_id, {})
        row['node_provider_id'] = operator.get('display_name', '')
        row['node_allowance'] = operator.get('node_allowance', '')
        row['node_operator_rewardable_nodes'] = operator.get('rewardable_nodes', '')
        row['node_operator_dc'] = operator.get('dc_id', '')
        
        # Datacenter data
        dc_id = operator.get('dc_id', '')
        datacenter = datacenters.get(dc_id, {})
        row['dc_owner'] = datacenter.get('owner', '')
        row['dc_region'] = datacenter.get('region', '').strip('"')
        row['gps_latitude'] = datacenter.get('gps_latitude', '')
        row['gps_longitude'] = datacenter.get('gps_longitude', '')
        
        # Reward data - hierarchical lookup: city -> country -> continent
        dc_region = row['dc_region']
        node_reward_type = row['node_reward_type']
        
        reward = {}
        reward_lookup_region = dc_region
        
        if node_reward_type and dc_region:
            # Try different levels of specificity
            region_parts = dc_region.split(',') if ',' in dc_region else [dc_region]
            
            # 1. Try full region first (most specific): "Asia,SG,Singapore"
            reward_key = (dc_region, node_reward_type)
            reward = rewards.get(reward_key, {})
            
            if not reward and len(region_parts) >= 2:
                # 2. Try country level: "Asia,SG"
                country_region = f"{region_parts[0]},{region_parts[1]}"
                reward_key = (country_region, node_reward_type)
                reward = rewards.get(reward_key, {})
                reward_lookup_region = country_region
            
            if not reward and len(region_parts) >= 1:
                # 3. Try continent level: "Asia"
                continent_region = region_parts[0]
                reward_key = (continent_region, node_reward_type)
                reward = rewards.get(reward_key, {})
                reward_lookup_region = continent_region
        
        row['reward_region'] = reward_lookup_region if reward else dc_region
        row['reward_xdr'] = reward.get('xdr_permyriad_per_node_per_month', '')
        row['reward_coefficient'] = reward.get('reward_coefficient_percent', '')
        
        # Validation flags - use CORRECT/MISMATCH format
        row['reward_table_issue'] = 'MISMATCH' if not reward else 'CORRECT'
        row['node_operator_principal_id_mismatch'] = 'MISMATCH' if operator_id != operator.get('principal_id', '') else 'CORRECT'
        row['reward_type_mismatch'] = 'MISMATCH' if node_reward_type and dc_region and not reward else 'CORRECT'
        
        writer.writerow(row)

print(f"✅ Created comprehensive audit with {len(nodes)} nodes")
EOF

  # Return to original directory
  cd "$OUTDIR"

  # Cleanup temporary files
  rm -f tmp_rewards.json

  log_success "Node audit complete! Output: $FINAL_CSV"
}

# Function to parse subnet_whatif.txt
parse_subnet_whatif() {
  local whatif_file="$OUTDIR/subnet_whatif.txt"
  
  if [ ! -f "$whatif_file" ]; then
    log_error "subnet_whatif.txt not found"
    log_error "Please create subnet_whatif.txt with the following format:"
    cat << 'EOF'

{
node_ids_add:[
0:"node-id-1"
1:"node-id-2"
]
node_ids_remove:[
0:"old-node-id-1"
1:"old-node-id-2"
]
subnet_id:"your-subnet-id-here"
}

EOF
    return 1
  fi
  
  log_info "Reading whatif configuration from subnet_whatif.txt..."
  
  # Parse the structured file using Python for better handling
  python3 <<EOF
import re
import sys

try:
    with open('$whatif_file', 'r') as f:
        content = f.read()
    
    # Extract subnet_id
    subnet_match = re.search(r'subnet_id:"([^"]+)"', content)
    if subnet_match:
        subnet_id = subnet_match.group(1)
        print(f"SUBNET_ID={subnet_id}")
    else:
        print("ERROR: No subnet_id found", file=sys.stderr)
        sys.exit(1)
    
    # Extract add nodes
    add_section = re.search(r'node_ids_add:\[(.*?)\]', content, re.DOTALL)
    if add_section:
        add_content = add_section.group(1)
        add_nodes = re.findall(r'\d+:"([^"]+)"', add_content)
        for node in add_nodes:
            print(f"ADD_NODE={node}")
    
    # Extract remove nodes
    remove_section = re.search(r'node_ids_remove:\[(.*?)\]', content, re.DOTALL)
    if remove_section:
        remove_content = remove_section.group(1)
        remove_nodes = re.findall(r'\d+:"([^"]+)"', remove_content)
        for node in remove_nodes:
            print(f"REMOVE_NODE={node}")

except Exception as e:
    print(f"ERROR: Failed to parse subnet_whatif.txt: {e}", file=sys.stderr)
    sys.exit(1)
EOF

  local parse_result=$?
  if [ $parse_result -ne 0 ]; then
    log_error "Failed to parse subnet_whatif.txt"
    return 1
  fi
  
  # Read the parsed values
  local subnet_id=""
  local add_nodes=()
  local remove_nodes=()
  local show_map=true  # Default to true for map
  local show_geo=false # Default to false for geo
  
  while IFS= read -r line; do
    if [[ "$line" =~ ^SUBNET_ID=(.+)$ ]]; then
      subnet_id="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^ADD_NODE=(.+)$ ]]; then
      add_nodes+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ ^REMOVE_NODE=(.+)$ ]]; then
      remove_nodes+=("${BASH_REMATCH[1]}")
    fi
  done < <(python3 <<EOF
import re

try:
    with open('$whatif_file', 'r') as f:
        content = f.read()
    
    # Extract subnet_id
    subnet_match = re.search(r'subnet_id:"([^"]+)"', content)
    if subnet_match:
        subnet_id = subnet_match.group(1)
        print(f"SUBNET_ID={subnet_id}")
    
    # Extract add nodes
    add_section = re.search(r'node_ids_add:\[(.*?)\]', content, re.DOTALL)
    if add_section:
        add_content = add_section.group(1)
        add_nodes = re.findall(r'\d+:"([^"]+)"', add_content)
        for node in add_nodes:
            print(f"ADD_NODE={node}")
    
    # Extract remove nodes
    remove_section = re.search(r'node_ids_remove:\[(.*?)\]', content, re.DOTALL)
    if remove_section:
        remove_content = remove_section.group(1)
        remove_nodes = re.findall(r'\d+:"([^"]+)"', remove_content)
        for node in remove_nodes:
            print(f"REMOVE_NODE={node}")

except Exception as e:
    print(f"ERROR: Failed to parse: {e}")
    exit(1)
EOF
)
  
  # Validate required fields
  if [ -z "$subnet_id" ]; then
    log_error "No subnet ID found in subnet_whatif.txt"
    log_error "Please add a line like: subnet_id:\"your-subnet-id-here\""
    return 1
  fi
  
  # Output parsed values (global variables for caller)
  PARSED_SUBNET_ID="$subnet_id"
  PARSED_ADD_NODES=("${add_nodes[@]}")
  PARSED_REMOVE_NODES=("${remove_nodes[@]}")
  PARSED_SHOW_MAP="$show_map"
  PARSED_SHOW_GEO="$show_geo"
  
  log_info "Parsed configuration:"
  log_info "  Subnet ID: $subnet_id"
  log_info "  Nodes to add: ${#add_nodes[@]} (${add_nodes[*]})"
  log_info "  Nodes to remove: ${#remove_nodes[@]} (${remove_nodes[*]})"
  log_info "  Show map: $show_map"
  log_info "  Show geo: $show_geo"
  
  return 0
}

# Function to analyze subnet
analyze_subnet() {
  local subnet_id="$1"
  
  log_info "Analyzing subnet: $subnet_id"
  log_progress "Fetching latest subnet data from IC network..."
  
  # Get subnet data directly from IC network
  local subnet_data
  if ! subnet_data=$($IC_ADMIN get-subnet "$subnet_id" 2>/dev/null); then
    log_error "Failed to fetch subnet $subnet_id from IC network"
    log_error "Check your internet connection and verify the subnet ID is correct"
    return 1
  fi
  
  if [ -z "$subnet_data" ]; then
    log_error "Subnet $subnet_id not found or has no nodes"
    return 1
  fi
  
  local node_ids
  if ! node_ids=$(echo "$subnet_data" | jq -r '.records[0].value.membership[]' 2>/dev/null); then
    log_error "Failed to parse subnet data"
    return 1
  fi
  
  if [ -z "$node_ids" ]; then
    log_error "Subnet $subnet_id not found or has no nodes"
    return 1
  fi
  
  local nodes_array=()
  while IFS= read -r node_id; do
    if [ -n "$node_id" ]; then
      nodes_array+=("$node_id")
    fi
  done <<< "$node_ids"
  
  log_info "Found ${#nodes_array[@]} nodes in subnet"
  
  # Run full comprehensive audit (this will create all CSVs including nodes_full_audit.csv)
  generate_node_audit "${nodes_array[@]}"
  
  # Create simplified subnet analysis CSV from the comprehensive audit
  log_progress "Creating subnet analysis summary..."
  cd "$DATA_DIR"
  python3 <<'EOF'
import csv

# Create simplified subnet analysis from comprehensive audit
try:
    with open('nodes_full_audit.csv', 'r') as infile, \
         open('subnet_analysis.csv', 'w', newline='') as outfile:
        
        reader = csv.DictReader(infile)
        writer = csv.DictWriter(outfile, fieldnames=['node_id', 'node_operator_id', 'dc_id'])
        writer.writeheader()
        
        for row in reader:
            writer.writerow({
                'node_id': row['node_id'],
                'node_operator_id': row['node_operator_id'],
                'dc_id': row['node_operator_dc']
            })
            
    print("✅ Created subnet analysis summary")

except FileNotFoundError as e:
    print(f"Error: Could not create subnet analysis - {e}", file=sys.stderr)
EOF
  
  # Return to original directory
  cd "$OUTDIR"
  
  log_success "Subnet analysis complete! Output: $SUBNET_CSV"
}

# Function to simulate subnet changes
whatif_subnet() {
  local subnet_id="$1"
  shift
  
  local add_nodes=()
  local remove_nodes=()
  local show_map=false
  local show_geo=false
  
  # Parse whatif options
  while [[ $# -gt 0 ]]; do
    case $1 in
      --add-nodes)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          add_nodes+=("$1")
          shift
        done
        ;;
      --remove-nodes)
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
          remove_nodes+=("$1")
          shift
        done
        ;;
      --map)
        show_map=true
        shift
        ;;
      --geo)
        show_geo=true
        shift
        ;;
      *)
        log_error "Unknown option: $1"
        return 1
        ;;
    esac
  done
  
  log_info "Simulating changes to subnet: $subnet_id"
  if [ ${#add_nodes[@]} -gt 0 ]; then
    log_info "Adding nodes: ${add_nodes[*]}"
  fi
  if [ ${#remove_nodes[@]} -gt 0 ]; then
    log_info "Removing nodes: ${remove_nodes[*]}"
  fi
  
  # First analyze the current subnet
  analyze_subnet "$subnet_id"
  
  # Create whatif CSV with changes
  cd "$DATA_DIR"
  python3 <<EOF
import csv
import sys

# Read current subnet analysis
current_nodes = []
try:
    with open('subnet_analysis.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            current_nodes.append(row['node_id'])
except FileNotFoundError:
    print("Error: subnet_analysis.csv not found", file=sys.stderr)
    sys.exit(1)

# Apply changes
final_nodes = current_nodes.copy()

# Remove nodes
remove_nodes = [$(printf "'%s'," "${remove_nodes[@]}" | sed 's/,$//')]
for node in remove_nodes:
    if node in final_nodes:
        final_nodes.remove(node)
    # else: node not in current subnet - that's fine for whatif analysis

# Add nodes
add_nodes = [$(printf "'%s'," "${add_nodes[@]}" | sed 's/,$//')]
for node in add_nodes:
    if node not in final_nodes:
        final_nodes.append(node)
    # else: node already in subnet - that's fine for whatif analysis

print(f"📊 Final subnet size: {len(final_nodes)} nodes (was {len(current_nodes)})")

# Create whatif CSV
with open('subnet_whatif.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['node_id', 'change_type'])
    
    # Process all nodes from current subnet
    for node in current_nodes:
        if node in remove_nodes:
            writer.writerow([node, 'removed'])
        elif node in add_nodes:
            # Node is both in current subnet AND marked for addition - this is unusual
            # but we'll treat it as if it's being "added" for whatif purposes
            writer.writerow([node, 'added'])
        else:
            writer.writerow([node, 'existing'])
    
    # Process nodes marked for addition that aren't in current subnet
    for node in add_nodes:
        if node not in current_nodes:
            writer.writerow([node, 'added'])
    
    # Process nodes marked for removal that aren't in current subnet
    for node in remove_nodes:
        if node not in current_nodes:
            writer.writerow([node, 'removed'])
EOF
  
  # Return to original directory
  cd "$OUTDIR"
  
  # Identify nodes that need to be fetched (ALL whatif nodes not in current audit)
  local new_nodes=()
  # Check add nodes
  for node in "${add_nodes[@]}"; do
    # Check if node is already in the current audit
    if ! grep -q "^[^,]*,$node," "$DATA_DIR/nodes_full_audit.csv" 2>/dev/null; then
      new_nodes+=("$node")
    fi
  done
  # Check remove nodes
  for node in "${remove_nodes[@]}"; do
    # Check if node is already in the current audit
    if ! grep -q "^[^,]*,$node," "$DATA_DIR/nodes_full_audit.csv" 2>/dev/null; then
      new_nodes+=("$node")
    fi
  done
  
  if [ ${#new_nodes[@]} -gt 0 ]; then
    log_progress "Fetching data for ${#new_nodes[@]} new nodes..."
    # Temporarily save current audit
    cp "$DATA_DIR/nodes_full_audit.csv" "$DATA_DIR/nodes_full_audit_backup.csv"
    
    # Fetch only new nodes
    generate_node_audit "${new_nodes[@]}"
    
    # Merge the audits
    cd "$DATA_DIR"
    python3 <<'EOF'
import csv

# Read existing audit (backup)
existing_nodes = {}
try:
    with open('nodes_full_audit_backup.csv', 'r') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        for row in reader:
            existing_nodes[row['node_id']] = row
except FileNotFoundError:
    fieldnames = None

# Read new nodes audit
new_nodes = {}
try:
    with open('nodes_full_audit.csv', 'r') as f:
        reader = csv.DictReader(f)
        if not fieldnames:
            fieldnames = reader.fieldnames
        for row in reader:
            new_nodes[row['node_id']] = row
except FileNotFoundError:
    pass

# Merge and write combined audit
if fieldnames:
    with open('nodes_full_audit.csv', 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        
        # Write existing nodes
        for node_id, row in existing_nodes.items():
            writer.writerow(row)
        
        # Write new nodes
        for node_id, row in new_nodes.items():
            if node_id not in existing_nodes:
                writer.writerow(row)

# Cleanup
import os
if os.path.exists('nodes_full_audit_backup.csv'):
    os.remove('nodes_full_audit_backup.csv')

print(f"✅ Merged audit: {len(existing_nodes)} existing + {len([n for n in new_nodes if n not in existing_nodes])} new nodes")
EOF
    cd "$OUTDIR"
  else
    log_info "No new nodes to fetch - reusing existing audit data"
  fi
  
  # Create final subnet audit with change tracking
  cd "$DATA_DIR"
  python3 <<'EOF'
import csv

# Read whatif changes
changes = {}
try:
    with open('subnet_whatif.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            changes[row['node_id']] = row['change_type']
except FileNotFoundError:
    print("Warning: subnet_whatif.csv not found")

# Read full audit data
all_nodes = {}
with open('nodes_full_audit.csv', 'r') as infile:
    reader = csv.DictReader(infile)
    fieldnames = reader.fieldnames
    for row in reader:
        all_nodes[row['node_id']] = row

# Create final audit with ALL nodes from whatif analysis
with open('subnet_full_audit.csv', 'w', newline='') as outfile:
    # Add subnet-specific columns
    final_fieldnames = fieldnames + ['change_type', 'constraint_violation']
    writer = csv.DictWriter(outfile, fieldnames=final_fieldnames)
    writer.writeheader()
    
    # Process all nodes mentioned in whatif changes
    for node_id, change_type in changes.items():
        # Convert to proper change type format
        if change_type == 'added':
            final_change_type = 'ADDED'
        elif change_type == 'removed':
            final_change_type = 'REMOVED'
        elif change_type == 'existing':
            final_change_type = 'UNCHANGED'
        else:
            final_change_type = change_type.upper()
        
        if node_id in all_nodes:
            # Node exists in audit data
            row = all_nodes[node_id].copy()
            row['change_type'] = final_change_type
            row['constraint_violation'] = ''  # Will be filled later
            writer.writerow(row)
        else:
            # Node doesn't exist in audit data (for removed nodes not in current subnet)
            # Create a placeholder entry
            placeholder_row = {field: 'NOT_FOUND' for field in fieldnames}
            placeholder_row['node_id'] = node_id
            placeholder_row['change_type'] = final_change_type
            placeholder_row['constraint_violation'] = 'NODE_NOT_FOUND'
            writer.writerow(placeholder_row)

# Now check topology constraints (same logic as subnet_whatif.sh)
print("🔄 Checking topology constraints...")
EOF

# Constraint violation logic
python3 <<EOF
import csv
from collections import defaultdict

def get_allowed_nodes_per_country_per_owner(subnet_id):
    """Return the maximum allowed nodes per country from the same owner."""
    # Subnets that allow 3 nodes per country
    three_nodes_per_country_subnets = {
        "tdb26-jop6k-aogll-7ltgs-eruif-6kk7m-qpktf-gdiqx-mxtrf-vb5e6-eqe",  # NNS
        "x33ed-h457x-bsgyx-oqxqf-6pzwv-wkhzr-rm2j3-npodi-purzm-n66cg-gae",  # SNS
        "pzp6e-ekpqk-3c5x7-2h6so-njoeq-mt45d-h3h6c-q3mxf-vpeq5-fk5o7-yae",  # Fiduciary
        "uzr34-akd3s-xrdag-3ql62-ocgoh-ld2ao-tamcv-54e7j-krwgb-2gm4z-oqe",  # Internet Identity
        # TODO: Add ECDSA Signing and ECDSA Backup subnet IDs when available
    }
    
    # Swiss subnet allows 13 nodes per country
    swiss_subnet = "swiss-subnet-id-here"  # TODO: Replace with actual Swiss subnet ID
    
    # Bitcoin and European subnets allow 2 nodes per country (need IDs)
    # bitcoin_subnet = "bitcoin-subnet-id-here"
    # european_subnet = "european-subnet-id-here"
    
    if subnet_id == swiss_subnet:
        return 13
    elif subnet_id in three_nodes_per_country_subnets:
        return 3
    else:
        return 2  # Default: Bitcoin, European, and Application subnets allow 2 nodes per country

def get_allowed_nodes_per_provider(subnet_id, node_provider_id):
    """Return the maximum allowed nodes per provider for a subnet."""
    # NNS subnet allows Dfinity up to 3 nodes, others only 1
    nns_subnet = "tdb26-jop6k-aogll-7ltgs-eruif-6kk7m-qpktf-gdiqx-mxtrf-vb5e6-eqe"
    dfinity_provider = "bvcsg-3od6r-jnydw-eysln-aql7w-td5zn-ay5m6-sibd2-jzojt-anwag-mqe"
    
    if subnet_id == nns_subnet and node_provider_id == dfinity_provider:
        return 3
    else:
        return 1  # All other cases: 1 node per provider/DC/DC owner

# Use the actual subnet ID from the whatif analysis
subnet_id = "$subnet_id"
max_nodes_per_country = get_allowed_nodes_per_country_per_owner(subnet_id)

print(f"Subnet {subnet_id} allows {max_nodes_per_country} nodes per country")

# Read the audit file
rows = []
with open('subnet_full_audit.csv') as f:
    reader = csv.reader(f)
    header = next(reader)
    rows = list(reader)

# Find column indices
node_id_idx = header.index('node_id')
node_provider_id_idx = header.index('node_provider_id')
node_operator_dc_idx = header.index('node_operator_dc')
dc_region_idx = header.index('dc_region')
dc_owner_idx = header.index('dc_owner')
change_type_idx = header.index('change_type')
constraint_violation_idx = header.index('constraint_violation')

# Track constraints (only for non-removed nodes)
provider_nodes = defaultdict(list)
dc_nodes = defaultdict(list)
owner_nodes = defaultdict(list)
country_nodes = defaultdict(list)  # country -> [nodes]

for i, row in enumerate(rows):
    if row[change_type_idx] == "REMOVED":
        continue  # Skip removed nodes for constraint checking
    
    node_id = row[node_id_idx]
    provider_nodes[row[node_provider_id_idx]].append((i, node_id))
    dc_nodes[row[node_operator_dc_idx]].append((i, node_id))
    owner_nodes[row[dc_owner_idx]].append((i, node_id))
    
    # Extract country from dc_region (format: "Continent,Country,City")
    dc_region = row[dc_region_idx]
    if ',' in dc_region:
        parts = dc_region.split(',')
        if len(parts) >= 2:
            country = parts[1].strip()
        else:
            country = dc_region.strip()
    else:
        country = dc_region.strip()
    
    # Track nodes by country
    country_nodes[country].append((i, node_id))

# Flag violations
for i, row in enumerate(rows):
    violations = []
    
    # Set constraint violation for removed nodes
    if row[change_type_idx] == "REMOVED":
        rows[i][constraint_violation_idx] = "REMOVED_NODE"
        continue
    
    node_id = row[node_id_idx]
    node_provider_id = row[node_provider_id_idx]
    
    # Check for duplicate provider (with special handling for Dfinity in NNS)
    max_allowed_per_provider = get_allowed_nodes_per_provider(subnet_id, node_provider_id)
    if len(provider_nodes[node_provider_id]) > max_allowed_per_provider:
        violations.append("DUPLICATE_PROVIDER")
    
    # Check for duplicate DC (always 1 except Dfinity in NNS)
    max_allowed_per_dc = get_allowed_nodes_per_provider(subnet_id, node_provider_id)
    if len(dc_nodes[row[node_operator_dc_idx]]) > max_allowed_per_dc:
        violations.append("DUPLICATE_DC")
    
    # Check for duplicate owner (always 1 except Dfinity in NNS)
    max_allowed_per_owner = get_allowed_nodes_per_provider(subnet_id, node_provider_id)
    if len(owner_nodes[row[dc_owner_idx]]) > max_allowed_per_owner:
        violations.append("DUPLICATE_OWNER")
    
    # Check for country constraint violations
    dc_region = row[dc_region_idx]
    if ',' in dc_region:
        parts = dc_region.split(',')
        if len(parts) >= 2:
            country = parts[1].strip()
        else:
            country = dc_region.strip()
    else:
        country = dc_region.strip()
    
    if len(country_nodes[country]) > max_nodes_per_country:
        violations.append("DUPLICATE_COUNTRY")
    
    rows[i][constraint_violation_idx] = ",".join(violations) if violations else "NO_VIOLATIONS"

# Write back the updated file
with open('subnet_full_audit.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(header)
    writer.writerows(rows)

print("✅ Generated subnet_full_audit.csv with change tracking and constraint checking")
EOF
  
  # Return to original directory
  cd "$OUTDIR"
  
  log_success "Whatif analysis complete! Output: $FULL_AUDIT_CSV"
  log_info "Compare with target proposal: https://dashboard.internetcomputer.org/proposal/137147"
  
  # Generate visualizations if requested
  if [ "$show_map" = true ]; then
    log_progress "Generating interactive map..."
    if [ -f "$OUTDIR/generate_subnet_map.py" ]; then
      python3 "$OUTDIR/generate_subnet_map.py" --input "$FULL_AUDIT_CSV" --output "$DATA_DIR/subnet_map.html" --subnet-id "$subnet_id"
      log_success "Interactive map generated: data/subnet_map.html"
    else
      log_error "generate_subnet_map.py not found"
    fi
  fi
  
  if [ "$show_geo" = true ]; then
    log_progress "Generating geographic summary..."
    if [ -f "$OUTDIR/generate_geo_summary.py" ]; then
      python3 "$OUTDIR/generate_geo_summary.py" "$FULL_AUDIT_CSV"
    else
      log_error "generate_geo_summary.py not found"
    fi
  fi
}

# --- MAIN COMMAND ROUTING ---
if [ $# -eq 0 ]; then
  show_help
  exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
  nodes)
    if [ $# -eq 0 ]; then
      # Try to read from node_list.md first
      if [ -f "$OUTDIR/node_list.md" ]; then
        log_info "Reading nodes from node_list.md..."
        nodes_from_file=()
        # Read node IDs from markdown file (skip empty lines and comments)
        while IFS= read -r line; do
          # Skip empty lines and lines starting with # (comments)
          if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            # Extract just the node ID (trim whitespace)
            node_id=$(echo "$line" | xargs)
            if [[ -n "$node_id" ]]; then
              nodes_from_file+=("$node_id")
            fi
          fi
        done < "$OUTDIR/node_list.md"
        
        if [ ${#nodes_from_file[@]} -eq 0 ]; then
          log_error "No valid nodes found in node_list.md"
          exit 1
        fi
        
        generate_node_audit "${nodes_from_file[@]}"
      else
        log_error "No nodes specified and node_list.md not found"
        echo "Usage: $SCRIPT_NAME nodes <node1> [node2] [node3] ..."
        echo "   or: Create node_list.md with one node ID per line"
        exit 1
      fi
    else
      generate_node_audit "$@"
    fi
    ;;
  
  subnet)
    if [ $# -eq 0 ]; then
      log_error "No subnet ID specified"
      echo "Usage: $SCRIPT_NAME subnet <subnet_id>"
      exit 1
    fi
    analyze_subnet "$1"
    ;;
  
  whatif)
    if [ $# -eq 0 ]; then
      # Read from subnet_whatif.txt
      if ! parse_subnet_whatif; then
        exit 1
      fi
      
      # Convert parsed values to function arguments
      args=("$PARSED_SUBNET_ID")
      
      if [ ${#PARSED_ADD_NODES[@]} -gt 0 ]; then
        args+=("--add-nodes" "${PARSED_ADD_NODES[@]}")
      fi
      
      if [ ${#PARSED_REMOVE_NODES[@]} -gt 0 ]; then
        args+=("--remove-nodes" "${PARSED_REMOVE_NODES[@]}")
      fi
      
      if [ "$PARSED_SHOW_MAP" = true ]; then
        args+=("--map")
      fi
      
      if [ "$PARSED_SHOW_GEO" = true ]; then
        args+=("--geo")
      fi
      
      whatif_subnet "${args[@]}"
    else
      whatif_subnet "$@"
    fi
    ;;
  
  help|--help|-h)
    show_help
    ;;
  
  *)
    log_error "Unknown command: $COMMAND"
    echo ""
    show_help
    exit 1
    ;;
esac
