#!/bin/bash
set -euo pipefail

# --- CONFIG ---
IC_ADMIN="ic-admin --json --nns-urls https://ic0.app"
OUTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_CSV="$OUTDIR/nodes_status.csv"
OP_CSV="$OUTDIR/node_operators_status.csv"
DC_CSV="$OUTDIR/datacenter_status.csv"
REW_CSV="$OUTDIR/node_reward_types.csv"
FINAL_CSV="$OUTDIR/nodes_full_audit.csv"

# --- 1. INPUT NODES ---
NODES=()

# Check if arguments are provided via command line
if [ $# -gt 0 ]; then
  echo "📝 Using nodes from command line arguments..."
  NODES=("$@")
else
  # Try to read from subnet_analysis.csv
  if [ -f "$OUTDIR/subnet_analysis.csv" ]; then
    echo "📝 Reading nodes from subnet_analysis.csv..."
    # Read node IDs from CSV (skip header)
    while IFS=',' read -r node_id operator_id dc_id; do
      if [ "$node_id" != "node_id" ]; then  # Skip header
        NODES+=("$node_id")
      fi
    done < "$OUTDIR/subnet_analysis.csv"
  else
    echo "❌ Error: No arguments provided and subnet_analysis.csv not found"
    echo "Usage: $0 [node1 node2 node3 ...]"
    echo "   or: Run subnet_analyze.sh first to populate subnet_analysis.csv"
    exit 1
  fi
fi

echo "🔍 Analyzing ${#NODES[@]} nodes..."

mkdir -p "$OUTDIR"

# --- 2. PULL NODE RECORDS ---
echo "Pulling node records..."
echo "version,node_id,xnet,http,node_operator_id,chip_id,hostos_version_id,public_ipv4_config,domain,node_reward_type" > "$NODE_CSV"
NODE_OP_IDS=()

for NODE in "${NODES[@]}"; do
  $IC_ADMIN get-node "$NODE" 2>/dev/null > tmp_node.json || continue
  python3 <<EOF >> "$NODE_CSV"
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

# --- 3. PULL NODE OPERATOR RECORDS AND COLLECT DC IDs ---
echo "Pulling node operator records..."
echo "version,node_operator_id,node_allowance,node_provider_id,dc_id,node_operator_rewardable_nodes,ipv6,max_rewardable_nodes,node_operator_principal_id_mismatch" > "$OP_CSV"
DC_IDS=()

for OP in "${NODE_OP_IDS[@]}"; do
  $IC_ADMIN get-node-operator "$OP" 2>/dev/null > tmp_op.json || continue
  python3 <<EOF >> "$OP_CSV"
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

# Check for principal ID mismatch
lookup_key = "$OP"
stored_principal = val.get('node_operator_principal_id', '')
principal_mismatch = "MISMATCH" if lookup_key != stored_principal else "CORRECT"

row = [
    str(v),
    "$OP",  # Use the lookup key instead of the principal ID from within the record
    norm(val.get('node_allowance')),
    norm(val.get('node_provider_principal_id')),
    norm(val.get('dc_id')),
    norm(val.get('rewardable_nodes')),
    norm(val.get('ipv6')),
    norm(val.get('max_rewardable_nodes')),
    principal_mismatch,
]
print(','.join(row))
EOF
  DCID=$(jq -r '.value.dc_id // empty' tmp_op.json)
  [ -n "$DCID" ] && DC_IDS+=("$DCID")
done
rm -f tmp_op.json

# Remove duplicates from DC_IDS array if it has elements
if [ ${#DC_IDS[@]} -gt 0 ]; then
  DC_IDS=($(printf "%s\n" "${DC_IDS[@]}" | sort -u))
fi

# --- 4. PULL DATACENTER RECORDS ---
echo "Pulling datacenter records..."
echo "version,dc_id,region,owner,gps_latitude,gps_longitude" > "$DC_CSV"
for DC in "${DC_IDS[@]}"; do
  $IC_ADMIN get-data-center "$DC" 2>/dev/null > tmp_dc.json || continue
  python3 <<EOF >> "$DC_CSV"
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

# --- 5. PULL NODE REWARD TYPES TABLE ---
echo "Pulling node reward type table..."
REGVER=$($IC_ADMIN --nns-urls https://ic0.app get-registry-version 2>/dev/null | tail -n 1)
echo "# Registry version: $REGVER" > "$REW_CSV"
echo "region,reward_type,xdr_permyriad_per_node_per_month,reward_coefficient_percent" >> "$REW_CSV"
$IC_ADMIN get-node-rewards-table 2>/dev/null | jq -r '
  to_entries[] as $region_entry |
  $region_entry.value | to_entries[] as $rtype_entry |
  [
    $region_entry.key,
    $rtype_entry.key,
    ($rtype_entry.value.xdr_permyriad_per_node_per_month // "None"),
    ($rtype_entry.value.reward_coefficient_percent // "None")
  ] | @csv
' >> "$REW_CSV"

# --- 6. FINAL MERGE (Region normalization logic) ---
echo "Merging into $FINAL_CSV ..."
python3 <<EOF
import csv

def clean_region(r):
    return r.lower().replace(' ', '').replace('"','').replace("'", '')

ops = {}
with open("$OP_CSV") as f:
    next(f)
    for row in csv.reader(f):
        ops[row[1]] = row

dcs = {}
with open("$DC_CSV") as f:
    next(f)
    for row in csv.reader(f):
        dcs[row[1]] = row

# Build: region (cleaned) + reward_type -> (region,xdr,coeff)
rewards = {}
with open("$REW_CSV") as f:
    for i, row in enumerate(csv.reader(f)):
        if i < 2: continue
        region, reward_type, xdr, coeff = row
        key = (clean_region(region), reward_type)
        rewards[key] = (region, xdr, coeff)

with open("$NODE_CSV") as infile, open("$FINAL_CSV", "w", newline='') as outfile:
    reader = csv.reader(infile)
    header = next(reader)
    # New reordered header matching the desired structure
    out_header = [
        "version","node_id","hostos_version_id","node_operator_id","node_provider_id",
        "node_allowance","node_reward_type","node_operator_rewardable_nodes",
        "node_operator_dc","dc_owner","dc_region","reward_region","reward_xdr",
        "reward_coefficient","reward_table_issue","node_operator_principal_id_mismatch","reward_type_mismatch",
        "gps_latitude","gps_longitude"
    ]
    writer = csv.writer(outfile)
    writer.writerow(out_header)
    for row in reader:
        node_operator_id = row[4]
        op = ops.get(node_operator_id, ["None"]*9)  # Updated to account for new column
        dc_id = op[4] if len(op) > 4 else "None"
        dc_info = dcs.get(dc_id, ["None"]*6)
        dc_region_full = dc_info[2] if len(dc_info) > 2 else "None"
        principal_mismatch = op[8] if len(op) > 8 else "UNKNOWN"  # Get the mismatch flag
        rewardable_nodes = op[5] if len(op) > 5 else "None"  # Get rewardable_nodes
        node_reward_type = row[9]
        
        # Check for reward type mismatch
        reward_type_valid = "MISMATCH"
        if rewardable_nodes != "None" and node_reward_type != "None":
            # Parse rewardable_nodes (it's a string representation of a dict)
            try:
                import ast
                rewardable_dict = ast.literal_eval(rewardable_nodes) if rewardable_nodes != "None" else {}
                reward_type_valid = "CORRECT" if node_reward_type in rewardable_dict else "MISMATCH"
            except:
                reward_type_valid = "PARSE_ERROR"
        else:
            reward_type_valid = "UNKNOWN"
        
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
        
        # Create row in the new column order
        # Original row: version,node_id,xnet,http,node_operator_id,chip_id,hostos_version_id,public_ipv4_config,domain,node_reward_type
        # New order: version,node_id,hostos_version_id,node_operator_id,node_provider_id,node_allowance,node_reward_type,node_operator_rewardable_nodes,node_operator_dc,dc_owner,dc_region,reward_region,reward_xdr,reward_coefficient,reward_table_issue,node_operator_principal_id_mismatch,reward_type_mismatch,gps_latitude,gps_longitude
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
            principal_mismatch,  # node_operator_principal_id_mismatch
            reward_type_valid,   # reward_type_mismatch
            dc_info[4] if len(dc_info) > 4 else "None",  # gps_latitude
            dc_info[5] if len(dc_info) > 5 else "None"   # gps_longitude
        ]
        writer.writerow(reordered_row)
EOF

echo "Done. Final audit written to $FINAL_CSV"
