#!/bin/bash

SUBNET_ID="$1"
TOPOLOGY_FILE="topology.json"
OUT_CSV="subnet_analysis.csv"

if [ -z "$SUBNET_ID" ]; then
  echo "Usage: $0 <subnet_id>"
  echo "Example: $0 cv73p-6v7zi-u67oy-7jc3h-qspsz-g5lrj-4fn7k-xrax3-thek2-sl46v-jae"
  exit 1
fi

if [ ! -f "$TOPOLOGY_FILE" ]; then
  echo "Missing topology.json. Run:"
  echo "  ic-admin --nns-url https://ic0.app get-topology > topology.json"
  exit 2
fi

echo "🔍 Analyzing subnet: $SUBNET_ID"

# Create simplified CSV with essential information
echo "node_id,node_operator_id,dc_id" > "$OUT_CSV"

NODE_IDS=$(jq -r --arg sid "$SUBNET_ID" '.subnets[$sid].membership[]' "$TOPOLOGY_FILE")

if [ -z "$NODE_IDS" ]; then
  echo "❌ Error: Subnet $SUBNET_ID not found or has no nodes"
  exit 3
fi

NODE_COUNT=$(echo "$NODE_IDS" | wc -l | xargs)
echo "📊 Found $NODE_COUNT nodes in subnet"

for NODE_ID in $NODE_IDS; do
  # Extract essential node information
  OP_ID=$(jq -r --arg sid "$SUBNET_ID" --arg nid "$NODE_ID" '.subnets[$sid].nodes[$nid].node_operator_id // "unknown"' "$TOPOLOGY_FILE")
  DC_ID=$(jq -r --arg sid "$SUBNET_ID" --arg nid "$NODE_ID" '.subnets[$sid].nodes[$nid].dc_id // "unknown"' "$TOPOLOGY_FILE")

  echo "$NODE_ID,$OP_ID,$DC_ID" >> "$OUT_CSV"
done

echo "✅ Current subnet analysis written to $OUT_CSV"

# Generate summary statistics
echo ""
echo "📈 SUBNET SUMMARY:"
echo "Total nodes: $NODE_COUNT"

echo ""
echo " DATACENTER DISTRIBUTION:"
cut -d',' -f3 "$OUT_CSV" | tail -n +2 | sort | uniq -c | sort -nr | while read count dc; do
  echo "  $dc: $count nodes"
done

echo ""
echo "👥 NODE OPERATOR DISTRIBUTION:"
cut -d',' -f2 "$OUT_CSV" | tail -n +2 | sort | uniq -c | sort -nr | head -10 | while read count op; do
  echo "  $op: $count nodes"
done

echo ""
echo "🔗 Next steps:"
echo "  1. Review $OUT_CSV for current topology"
echo "  2. Use subnet_whatif.sh to simulate changes"
echo "  3. Compare with target proposal: https://dashboard.internetcomputer.org/proposal/132136"
