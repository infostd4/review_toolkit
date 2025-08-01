#!/bin/bash
set -euo pipefail

# --- CONFIG ---
IC_ADMIN="ic-admin --json --nns-urls https://ic0.app"
OUTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHATIF_CSV="$OUTDIR/subnet_whatif.csv"
FULL_AUDIT_CSV="$OUTDIR/subnet_full_audit.csv"

SUBNET_ID=""
ADD_NODES=()
REMOVE_NODES=()

# Parse command line arguments
if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
  SUBNET_ID="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --subnet)
      SUBNET_ID="$2"
      shift 2
      ;;
    --add-nodes)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        ADD_NODES+=("$1")
        shift
      done
      ;;
    --remove-nodes)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        REMOVE_NODES+=("$1")
        shift
      done
      ;;
    --help|-h)
      echo "Usage: $0 <subnet_id> [--add-nodes node1 node2 ...] [--remove-nodes node1 node2 ...]"
      echo ""
      echo "Enhanced subnet analysis with detailed node information and constraint checking."
      echo ""
      echo "Examples:"
      echo "  $0 cv73p-6v7zi-u67oy-7jc3h-qspsz-g5lrj-4fn7k-xrax3-thek2-sl46v-jae --add-nodes new-node-1"
      echo "  $0 cv73p-6v7zi-u67oy-7jc3h-qspsz-g5lrj-4fn7k-xrax3-thek2-sl46v-jae --remove-nodes old-node-1 --add-nodes new-node-1"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

if [ -z "$SUBNET_ID" ]; then
  echo "❌ Error: Subnet ID is required"
  echo "Use --help for usage information"
  exit 1
fi

if [ ${#ADD_NODES[@]} -eq 0 ] && [ ${#REMOVE_NODES[@]} -eq 0 ]; then
  echo "❌ Error: At least one --add-nodes or --remove-nodes must be specified"
  echo "Use --help for usage information"
  exit 1
fi

echo "🔄 ENHANCED SUBNET MODIFICATION ANALYSIS"
echo "========================================"
echo "Subnet ID: $SUBNET_ID"
echo "Nodes to add: ${ADD_NODES[*]:-none}"
echo "Nodes to remove: ${REMOVE_NODES[*]:-none}"
echo ""

# Check if nodes_full_audit.csv exists
if [ ! -f "$OUTDIR/nodes_full_audit.csv" ]; then
  echo "❌ Error: nodes_full_audit.csv not found"
  echo "Run analyze_subnet.sh and checknodes.sh first to generate current subnet data"
  exit 2
fi

mkdir -p "$OUTDIR"

# --- STEP 1: ANALYZE ADD/REMOVE NODES ---
echo "📊 Step 1: Analyzing add/remove nodes..."
ALL_WHATIF_NODES=()
if [ ${#ADD_NODES[@]} -gt 0 ]; then
  ALL_WHATIF_NODES+=("${ADD_NODES[@]}")
fi
if [ ${#REMOVE_NODES[@]} -gt 0 ]; then
  ALL_WHATIF_NODES+=("${REMOVE_NODES[@]}")
fi

if [ ${#ALL_WHATIF_NODES[@]} -gt 0 ]; then
  # Create whatif CSV with same format as nodes_full_audit + change_type
  echo "version,node_id,hostos_version_id,node_operator_id,node_provider_id,node_allowance,node_reward_type,node_operator_rewardable_nodes,node_operator_dc,dc_owner,dc_region,reward_region,reward_xdr,reward_coefficient,reward_table_issue,node_operator_principal_id_mismatch,reward_type_mismatch,change_type" > "$WHATIF_CSV"

  # Temporary files for processing
  NODE_CSV_TEMP="$OUTDIR/temp_nodes.csv"
  OP_CSV_TEMP="$OUTDIR/temp_operators.csv"
  DC_CSV_TEMP="$OUTDIR/temp_datacenters.csv"
  REW_CSV_TEMP="$OUTDIR/temp_rewards.csv"

  # Pull node records for whatif nodes
  echo "version,node_id,xnet,http,node_operator_id,chip_id,hostos_version_id,public_ipv4_config,domain,node_reward_type" > "$NODE_CSV_TEMP"
  NODE_OP_IDS=()

  for NODE in "${ALL_WHATIF_NODES[@]}"; do
    echo "  Analyzing node: $NODE"
    $IC_ADMIN get-node "$NODE" 2>/dev/null > tmp_node.json || continue
    python3 <<EOF >> "$NODE_CSV_TEMP"
import json
d = json.load(open('tmp_node.json'))
v = d.get('version','None')
val = d.get('value',{})
def norm(x):
    if x is None: return 'None'
    s = str(x).replace('\n',' ').replace('\r','').replace('\t',' ')
    s = s.replace('\"', '\"\"')
    if ',' in s or '"' in s: s = f'"{s}"'
    return s
row = [
    str(v),
    "$NODE",
    norm(val.get('xnet')),
    norm(val.get('http')),
    norm(val.get('node_operator_id')),
    norm(val.get('chip_id')),
    norm(val.get('hostos_version_id')),
    norm(val.get('public_ipv4_config')),
    norm(val.get('domain')),
    norm(val.get('node_reward_type')),
]
print(','.join(row))
EOF

    OPID=$(jq -r '.value.node_operator_id // empty' tmp_node.json)
    [ -n "$OPID" ] && NODE_OP_IDS+=("$OPID")
  done
  rm -f tmp_node.json

  NODE_OP_IDS=($(printf "%s\n" "${NODE_OP_IDS[@]}" | sort -u))

  # Pull node operator records
  echo "version,node_operator_id,node_allowance,node_provider_id,dc_id,node_operator_rewardable_nodes,ipv6,max_rewardable_nodes" > "$OP_CSV_TEMP"
  DC_IDS=()

  for OP in "${NODE_OP_IDS[@]}"; do
    $IC_ADMIN get-node-operator "$OP" 2>/dev/null > tmp_op.json || continue
    python3 <<EOF >> "$OP_CSV_TEMP"
import json
d = json.load(open('tmp_op.json'))
v = d.get('version','None')
val = d.get('value',{})
def norm(x):
    if x is None or (isinstance(x,(str,dict,list)) and not x): return 'None'
    s = str(x).replace('\n',' ').replace('\r','').replace('\t',' ')
    s = s.replace('\"', '\"\"')
    if ',' in s or '"' in s: s = f'"{s}"'
    return s
row = [
    str(v),
    norm(val.get('node_operator_principal_id')),
    norm(val.get('node_allowance')),
    norm(val.get('node_provider_principal_id')),
    norm(val.get('dc_id')),
    norm(val.get('rewardable_nodes')),
    norm(val.get('ipv6')),
    norm(val.get('max_rewardable_nodes')),
]
print(','.join(row))
EOF
    DCID=$(jq -r '.value.dc_id // empty' tmp_op.json)
    [ -n "$DCID" ] && DC_IDS+=("$DCID")
  done
  rm -f tmp_op.json

  DC_IDS=($(printf "%s\n" "${DC_IDS[@]}" | sort -u))

  # Pull datacenter records
  echo "version,dc_id,region,owner,gps_latitude,gps_longitude" > "$DC_CSV_TEMP"
  for DC in "${DC_IDS[@]}"; do
    $IC_ADMIN get-data-center "$DC" 2>/dev/null > tmp_dc.json || continue
    python3 <<EOF >> "$DC_CSV_TEMP"
import json
d = json.load(open('tmp_dc.json'))
v = d.get('version','None')
val = d.get('value',{})
def norm(x):
    if x is None or (isinstance(x,(str,dict,list)) and not x): return 'None'
    s = str(x).replace('\n',' ').replace('\r','').replace('\t',' ')
    s = s.replace('\"', '\"\"')
    if ',' in s or '"' in s: s = f'"{s}"'
    return s
gps = val.get('gps',{}) or {}
row = [
    str(v),
    norm(val.get('id')),
    norm(val.get('region')),
    norm(val.get('owner')),
    norm(gps.get('latitude')),
    norm(gps.get('longitude'))
]
print(','.join(row))
EOF
  done
  rm -f tmp_dc.json

  # Pull node reward types table
  REGVER=$($IC_ADMIN --nns-urls https://ic0.app get-registry-version 2>/dev/null | tail -n 1)
  echo "# Registry version: $REGVER" > "$REW_CSV_TEMP"
  echo "region,reward_type,xdr_permyriad_per_node_per_month,reward_coefficient_percent" >> "$REW_CSV_TEMP"
  $IC_ADMIN get-node-rewards-table 2>/dev/null | jq -r '
    to_entries[] as $region_entry |
    $region_entry.value | to_entries[] as $rtype_entry |
    [
      $region_entry.key,
      $rtype_entry.key,
      ($rtype_entry.value.xdr_permyriad_per_node_per_month // "None"),
      ($rtype_entry.value.reward_coefficient_percent // "None")
    ] | @csv
  ' >> "$REW_CSV_TEMP"

  # Merge data and add change_type flags
  python3 <<EOF
import csv

def clean_region(r):
    return r.lower().replace(' ', '').replace('"','').replace("'", '')

# Load operators
ops = {}
with open("$OP_CSV_TEMP") as f:
    next(f)
    for row in csv.reader(f):
        ops[row[1]] = row

# Load datacenters
dcs = {}
with open("$DC_CSV_TEMP") as f:
    next(f)
    for row in csv.reader(f):
        dcs[row[1]] = row

# Load rewards
rewards = {}
with open("$REW_CSV_TEMP") as f:
    for i, row in enumerate(csv.reader(f)):
        if i < 2: continue
        region, reward_type, xdr, coeff = row
        key = (clean_region(region), reward_type)
        rewards[key] = (region, xdr, coeff)

# Node lists for change type determination
add_nodes = "${ADD_NODES[*]:-}".split() if "${ADD_NODES[*]:-}" else []
remove_nodes = "${REMOVE_NODES[*]:-}".split() if "${REMOVE_NODES[*]:-}" else []

with open("$NODE_CSV_TEMP") as infile, open("$WHATIF_CSV", "w", newline='') as outfile:
    reader = csv.reader(infile)
    header = next(reader)
    # New reordered header matching the desired structure
    out_header = [
        "version","node_id","hostos_version_id","node_operator_id","node_provider_id",
        "node_allowance","node_reward_type","node_operator_rewardable_nodes",
        "node_operator_dc","dc_owner","dc_region","reward_region","reward_xdr",
        "reward_coefficient","reward_table_issue","node_operator_principal_id_mismatch","reward_type_mismatch","change_type"
    ]
    writer = csv.writer(outfile)
    writer.writerow(out_header)
    
    for row in reader:
        node_id = row[1]
        node_operator_id = row[4]
        op = ops.get(node_operator_id, ["None"]*8)
        dc_id = op[4] if len(op) > 4 else "None"
        dc_info = dcs.get(dc_id, ["None"]*6)
        dc_region_full = dc_info[2] if len(dc_info) > 2 else "None"
        node_reward_type = row[9]
        
        # Extract rewardable_nodes from operator record
        rewardable_nodes = "None"
        if len(op) > 5 and op[5] != "None":
            rewardable_nodes = op[5]
        
        # Validate principal ID mismatch
        principal_id_mismatch = "CORRECT"
        if len(op) > 7 and op[7] != "None" and op[7] != node_operator_id:
            principal_id_mismatch = "MISMATCH"
        
        # Validate reward type mismatch
        reward_type_mismatch = "CORRECT"
        if rewardable_nodes != "None":
            try:
                import json
                # Convert Python dict format to JSON format (single quotes to double quotes)
                json_string = rewardable_nodes.replace("'", '"')
                rewardable_dict = json.loads(json_string)
                if node_reward_type not in rewardable_dict:
                    reward_type_mismatch = "MISMATCH"
            except:
                reward_type_mismatch = "PARSE_ERROR"
        else:
            reward_type_mismatch = "UNKNOWN"
        
        # Determine reward info
        reward_region = "None"
        reward_xdr = "None"
        reward_coeff = "None"
        reward_issue = ""
        region_parts = [p.strip() for p in dc_region_full.split(',')]
        region1 = ','.join(region_parts[:2]) if len(region_parts) >= 2 else region_parts[0] if region_parts else ""
        region2 = region_parts[0] if region_parts else ""
        match = None
        if (clean_region(region1), node_reward_type) in rewards:
            match = rewards[(clean_region(region1), node_reward_type)]
        elif (clean_region(region2), node_reward_type) in rewards:
            match = rewards[(clean_region(region2), node_reward_type)]
        if match:
            reward_region, reward_xdr, reward_coeff = match
        else:
            reward_issue = "reward_region_not_found"
        
        # Determine change type
        change_type = "ADDED" if node_id in add_nodes else "REMOVED"
        
        # Create row in the new column order
        # Original row: version,node_id,xnet,http,node_operator_id,chip_id,hostos_version_id,public_ipv4_config,domain,node_reward_type
        # New order: version,node_id,hostos_version_id,node_operator_id,node_provider_id,node_allowance,node_reward_type,node_operator_rewardable_nodes,node_operator_dc,dc_owner,dc_region,reward_region,reward_xdr,reward_coefficient,reward_table_issue,node_operator_principal_id_mismatch,reward_type_mismatch,change_type
        reordered_row = [
            row[0],  # version
            row[1],  # node_id  
            row[6],  # hostos_version_id
            row[4],  # node_operator_id
            op[3],   # node_provider_id
            op[2],   # node_allowance
            row[9],  # node_reward_type
            rewardable_nodes,  # node_operator_rewardable_nodes
            op[4],   # node_operator_dc
            dc_info[3],  # dc_owner
            dc_info[2],  # dc_region
            reward_region,  # reward_region
            reward_xdr,     # reward_xdr
            reward_coeff,   # reward_coefficient
            reward_issue,   # reward_table_issue
            principal_id_mismatch,  # node_operator_principal_id_mismatch
            reward_type_mismatch,   # reward_type_mismatch
            change_type    # change_type
        ]
        writer.writerow(reordered_row)
EOF

  # Clean up temp files
  rm -f "$NODE_CSV_TEMP" "$OP_CSV_TEMP" "$DC_CSV_TEMP" "$REW_CSV_TEMP"
fi

# --- STEP 2: CREATE COMBINED ANALYSIS ---
echo "📊 Step 2: Creating combined analysis..."

# Copy nodes_full_audit.csv and add change tracking columns
python3 <<EOF
import csv

# Read current audit and add change tracking columns
with open("$OUTDIR/nodes_full_audit.csv") as infile, open("$FULL_AUDIT_CSV", "w", newline='') as outfile:
    reader = csv.reader(infile)
    header = next(reader)
    # Add change_type and constraint_violation columns
    out_header = header + ["change_type", "constraint_violation"]
    writer = csv.writer(outfile)
    writer.writerow(out_header)
    
    remove_nodes = "${REMOVE_NODES[*]:-}".split() if "${REMOVE_NODES[*]:-}" else []
    
    for row in reader:
        node_id = row[1]  # node_id is in column 1
        change_type = "REMOVED" if node_id in remove_nodes else "UNCHANGED"
        constraint_violation = ""  # Will be filled in step 4
        writer.writerow(row + [change_type, constraint_violation])

# Append whatif nodes if they exist (but only ADDED nodes, not REMOVED ones)
try:
    with open("$WHATIF_CSV") as whatif_file:
        reader = csv.reader(whatif_file)
        next(reader)  # Skip header
        
        with open("$FULL_AUDIT_CSV", "a", newline='') as outfile:
            writer = csv.writer(outfile)
            for row in reader:
                # Only append ADDED nodes, not REMOVED ones (they're already flagged above)
                if row[-1] == "ADDED":  # change_type is the last column
                    # Add empty constraint_violation column
                    writer.writerow(row + [""])
except FileNotFoundError:
    pass  # No whatif nodes to append
EOF

# --- STEP 3: CHECK CONSTRAINTS AND FLAG VIOLATIONS ---
echo "📊 Step 3: Checking constraints and flagging violations..."

python3 <<EOF
import csv
from collections import defaultdict

# Read the combined audit file
rows = []
with open("$FULL_AUDIT_CSV") as f:
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
region_nodes = defaultdict(list)
owner_nodes = defaultdict(list)

for i, row in enumerate(rows):
    if row[change_type_idx] == "REMOVED":
        continue  # Skip removed nodes for constraint checking
    
    node_id = row[node_id_idx]
    provider_nodes[row[node_provider_id_idx]].append((i, node_id))
    dc_nodes[row[node_operator_dc_idx]].append((i, node_id))
    region_nodes[row[dc_region_idx]].append((i, node_id))
    owner_nodes[row[dc_owner_idx]].append((i, node_id))

# Flag violations
for i, row in enumerate(rows):
    violations = []
    
    # Set constraint violation for removed nodes
    if row[change_type_idx] == "REMOVED":
        rows[i][constraint_violation_idx] = "REMOVED_NODE"
        continue
    
    node_id = row[node_id_idx]
    
    # Check for duplicate provider
    if len(provider_nodes[row[node_provider_id_idx]]) > 1:
        violations.append("DUPLICATE_PROVIDER")
    
    # Check for duplicate DC
    if len(dc_nodes[row[node_operator_dc_idx]]) > 1:
        violations.append("DUPLICATE_DC")
    
    # Check for duplicate region
    if len(region_nodes[row[dc_region_idx]]) > 1:
        violations.append("DUPLICATE_REGION")
    
    # Check for duplicate owner
    if len(owner_nodes[row[dc_owner_idx]]) > 1:
        violations.append("DUPLICATE_OWNER")
    
    rows[i][constraint_violation_idx] = ",".join(violations) if violations else "NO_VIOLATIONS"

# Write back the updated file
with open("$FULL_AUDIT_CSV", "w", newline='') as f:
    writer = csv.writer(f)
    writer.writerow(header)
    writer.writerows(rows)
EOF

# --- STEP 4: GENERATE SUMMARY REPORT ---
echo ""
echo "✅ ANALYSIS COMPLETE!"
echo "===================="

# Count changes
ADD_COUNT=${#ADD_NODES[@]}
REMOVE_COUNT=${#REMOVE_NODES[@]}
echo "📊 Changes Summary:"
echo "  Nodes to add: $ADD_COUNT"
echo "  Nodes to remove: $REMOVE_COUNT"
echo "  Net change: $((ADD_COUNT - REMOVE_COUNT)) nodes"

# Count constraint violations
VIOLATION_COUNT=$(python3 -c "
import csv
count = 0
with open('$FULL_AUDIT_CSV') as f:
    reader = csv.reader(f)
    header = next(reader)
    violation_idx = header.index('constraint_violation')
    for row in reader:
        violation = row[violation_idx].strip()
        if violation and violation not in ['NO_VIOLATIONS', 'REMOVED_NODE']:
            count += 1
print(count)
")

echo ""
echo "🚨 Constraint Violations: $VIOLATION_COUNT"
if [ "$VIOLATION_COUNT" -gt 0 ]; then
  echo "⚠️  WARNING: Constraint violations detected! Review $FULL_AUDIT_CSV"
fi

echo ""
echo "📄 Files Generated:"
echo "  - Whatif analysis: $WHATIF_CSV"
echo "  - Combined audit: $FULL_AUDIT_CSV"
echo ""
echo "🔗 Next Steps:"
echo "  1. Review $FULL_AUDIT_CSV for complete analysis"
echo "  2. Check constraint violations for topology compliance"
echo "  3. Compare with target proposal: https://dashboard.internetcomputer.org/proposal/132136"

# Clean up any remaining temp files
rm -f tmp_*.json
