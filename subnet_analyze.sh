#!/bin/bash

SUBNET_ID="$1"
OUTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$OUTDIR/data"
OUT_CSV="$DATA_DIR/subnet_analysis.csv"

if [ -z "$SUBNET_ID" ]; then
  echo "Usage: $0 <subnet_id>"
  echo "Example: $0 cv73p-6v7zi-u67oy-7jc3h-qspsz-g5lrj-4fn7k-xrax3-thek2-sl46v-jae"
  exit 1
fi

echo "🔍 Analyzing subnet: $SUBNET_ID"
echo "📡 Fetching latest subnet data from IC network..."

# Create data directory
mkdir -p "$DATA_DIR"

# Get subnet data directly from IC network
SUBNET_DATA=$(ic-admin --nns-url https://ic0.app get-subnet "$SUBNET_ID" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$SUBNET_DATA" ]; then
  echo "❌ Error: Failed to fetch subnet $SUBNET_ID from IC network"
  echo "   Check your internet connection and verify the subnet ID is correct"
  exit 2
fi

# Create simplified CSV with essential information
echo "node_id,node_operator_id,dc_id" > "$OUT_CSV"

NODE_IDS=$(echo "$SUBNET_DATA" | jq -r '.records[0].value.membership[]' 2>/dev/null)

if [ -z "$NODE_IDS" ]; then
  echo "❌ Error: Subnet $SUBNET_ID not found or has no nodes"
  exit 3
fi

NODE_COUNT=$(echo "$NODE_IDS" | wc -l | xargs)
echo "📊 Found $NODE_COUNT nodes in subnet"

echo "📡 Fetching detailed node information..."
for NODE_ID in $NODE_IDS; do
  # Get detailed node information directly from IC network
  NODE_DATA=$(ic-admin --json --nns-url https://ic0.app get-node "$NODE_ID" 2>/dev/null)
  
  if [ $? -eq 0 ] && [ -n "$NODE_DATA" ]; then
    # Extract node operator ID
    OP_ID=$(echo "$NODE_DATA" | jq -r '.value.node_operator_id // "unknown"' 2>/dev/null)
    
    # Get datacenter ID from node operator record
    if [ "$OP_ID" != "unknown" ]; then
      # Small delay to avoid rate limiting
      sleep 0.1
      OP_DATA=$(ic-admin --json --nns-url https://ic0.app get-node-operator "$OP_ID" 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$OP_DATA" ]; then
        DC_ID=$(echo "$OP_DATA" | jq -r '.value.dc_id // "unknown"' 2>/dev/null)
        if [ "$DC_ID" = "unknown" ]; then
          echo "⚠️  Warning: Could not extract dc_id for operator $OP_ID"
        fi
      else
        echo "⚠️  Warning: Could not fetch operator data for $OP_ID"
        DC_ID="unknown"
      fi
    else
      echo "⚠️  Warning: Could not extract operator_id for node $NODE_ID"
      DC_ID="unknown"
    fi
  else
    echo "⚠️  Warning: Could not fetch data for node $NODE_ID"
    OP_ID="unknown"
    DC_ID="unknown"
  fi

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
echo "  1. Review data/subnet_analysis.csv for current topology"
echo "  2. Run checknodes.sh to get detailed node analysis"
echo "  3. Use subnet_whatif.sh to simulate changes"
