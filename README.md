# Internet Computer Subnet Analysis Toolkit

A comprehensive suite of tools for analyzing IC network topology, validating subnet configurations, and simulating subnet modifications with constraint checking.

---

## **🎯 Overview**

This toolkit provides two main analysis workflows:

1. **Node-Level Analysis**: Analyze specific nodes with detailed operator, datacenter, and reward information
2. **Subnet-Level Analysis**: Analyze entire subnets, simulate modifications, and validate topology constraints

---

## **✨ Key Features**

- **🔄 Real-Time Data**: Fetches latest network state directly from IC, no dependency on static files
- **🛡️ Constraint Validation**: Automatically checks IC topology policies and decentralization requirements
- **📊 Comprehensive Analysis**: Node operators, datacenters, geographic distribution, and reward validation
- **🎯 Governance Support**: Designed for IC governance proposal analysis and voting decisions
- **⚡ Rate-Limited API**: Built-in delays to avoid overwhelming IC endpoints
- **🔍 Detailed Reporting**: CSV outputs with complete metadata and change tracking

---

## **📁 Available Scripts**

| Script | Purpose | Input | Output |
|--------|---------|-------|--------|
| `subnet_analyze.sh` | Extract basic subnet membership | Subnet ID | `subnet_analysis.csv` |
| `checknodes.sh` | Detailed node analysis with reward validation | Node list or CSV | `nodes_full_audit.csv` |
| `subnet_whatif.sh` | Simulate subnet changes with constraint checking | Subnet ID + add/remove nodes | `subnet_whatif.csv`, `subnet_full_audit.csv` |

---

## **🚀 Quick Start**

### **Workflow 1: Node-Level Analysis**

```bash
# Option A: Analyze specific nodes directly
./checknodes.sh node1 node2 node3

# Option B: First get subnet nodes, then analyze them
./subnet_analyze.sh subnet
./checknodes.sh  # Automatically reads from subnet_analysis.csv
```

### **Workflow 2: Subnet Modification Analysis**

```bash
# Step 1: Analyze current subnet
./subnet_analyze.sh c4isl-65rwf-emhk5-5ta5m-ngl73-rgrl3-tcc56-2hkja-4erqd-iivmy-7ae

# Step 2: Get detailed current topology
./checknodes.sh

# Step 3: Simulate subnet modifications
./subnet_whatif.sh c4isl-65rwf-emhk5-5ta5m-ngl73-rgrl3-tcc56-2hkja-4erqd-iivmy-7ae \
  --add-nodes c6vcy-6g4me-zzd7n-kaylz-ujxmo-b27zq-us5th-w3t7x-ysolf-3mgpe-7ae u7xea-i2nf7-uyfwo-r756v-dazwi-g3no5-aaylx-6dwmb-6jtm7-ezg75-3ae \
  --remove-nodes iqnlc-oy677-m524v-tisrn-3v44n-2eylu-bclq3-fqjtg-4ab7z-ycrie-mqe mwrqx-e25kz-tchcz-quxpv-jhwdn-rwxeg-au4ci-xv5ko-s44pv-dmu6g-kqe \
---

## **📋 Detailed Tutorial**

### **1. Node-Level Analysis with Reward Validation**

**Purpose**: Analyze specific nodes to verify operator information, datacenter details, and reward type correctness.

#### **Step 1: Direct Node Analysis**
```bash
# Analyze specific nodes
./checknodes.sh \
  wnuri-kqarn-qyjem-ae34x-dhkub-ocuug-3xjnj-xydiu-pmpkx-56lnn-3ae \
  fi2eu-lgaic-n73rv-dsfr6-52z3t-7eto7-pmdg7-r7o7n-agotm-zw6o5-tae
```

#### **What This Does:**
- Pulls detailed node records from IC registry
- Extracts node operator and datacenter information
- Cross-references reward types with regional reward tables
- Validates reward type correctness based on node location
- Generates comprehensive CSV with all metadata

#### **Output Analysis:**
```bash
# View the results
head -3 nodes_full_audit.csv

# Check for reward validation issues
grep "reward_region_not_found" nodes_full_audit.csv
```

**Key Fields in Output:**
- `node_provider_id`: Node provider principal ID
- `node_operator_dc`: Datacenter ID where node is hosted
- `dc_region`: Geographic region (format: "Continent,Country,City")
- `dc_owner`: Datacenter owner/company
- `reward_region`: Matched reward region from reward table
- `reward_table_issue`: Flags any reward type mismatches
- `node_operator_principal_id_mismatch`: Flags when operator record key differs from stored principal ID (CORRECT/MISMATCH)

### **2. Subnet-Level Analysis and Constraint Validation**

**Purpose**: Analyze entire subnets, simulate modifications, and ensure compliance with IC topology policies.

#### **Step 1: Current Subnet Analysis**
```bash
# Extract subnet membership
./subnet_analyze.sh subnet
```

**Output**: `subnet_analysis.csv` with node_id, operator_id, dc_id

**What You Get:**
- Node count and distribution summary  
- Datacenter distribution across the subnet
- Node operator distribution
- Geographic diversity metrics

#### **Step 2: Detailed Subnet Audit**
```bash
# Get comprehensive node details
./checknodes.sh  # Reads from subnet_analysis.csv automatically
```

**Output**: `nodes_full_audit.csv` with complete node metadata

#### **Step 3: Subnet Modification Simulation**
```bash
# Simulate adding/removing nodes
./subnet_whatif.sh subnet \
  --add-nodes proposed_node_1 \
  --remove-nodes current_node_1
```

**Outputs**: 
- `subnet_whatif.csv`: Analysis of only the add/remove nodes
- `subnet_full_audit.csv`: Combined analysis with change tracking and constraint validation

#### **Constraint Validation Results:**

The script automatically checks for IC topology policy violations:

**✅ Valid Topology Flags:**
- `NO_VIOLATIONS`: Node passes all constraints
- `REMOVED_NODE`: Node being removed (excluded from constraint checks)

**🚨 Violation Flags:**
- `DUPLICATE_PROVIDER`: Multiple nodes from same provider
- `DUPLICATE_DC`: Multiple nodes from same datacenter  
- `DUPLICATE_OWNER`: Multiple nodes from same datacenter owner
- `DUPLICATE_COUNTRY`: Too many nodes from same country (varies by subnet type)

**📍 Country Constraint Rules:**
- **3 Countries Allowed**: NNS, SNS, Fiduciary, Internet Identity subnets
- **2 Countries Allowed**: Bitcoin, European, and all other application subnets
- The system automatically detects subnet type and applies appropriate limits

**🔧 Special Constraint Exceptions:**
- **Dfinity Provider Exception**: The Dfinity node provider (`bvcsg-3od6r-jnydw-eysln-aql7w-td5zn-ay5m6-sibd2-jzojt-anwag-mqe`) is allowed up to 3 nodes in the NNS subnet (`tdb26-jop6k-aogll-7ltgs-eruif-6kk7m-qpktf-gdiqx-mxtrf-vb5e6-eqe`), permitting `DUPLICATE_PROVIDER`, `DUPLICATE_DC`, and `DUPLICATE_OWNER` violations for this specific case

**Combined violations** are comma-separated: `DUPLICATE_PROVIDER,DUPLICATE_DC`

### **3. Change Tracking and Analysis**

#### **Understanding Change Types:**
```bash
# View change distribution
python3 -c "
import csv
from collections import Counter
with open('subnet_full_audit.csv') as f:
    reader = csv.reader(f)
    header = next(reader)
    change_idx = header.index('change_type')
    changes = [row[change_idx] for row in reader]
    for change, count in Counter(changes).items():
        print(f'{count:3d} {change}')
"
```

**Change Type Meanings:**
- `UNCHANGED`: Current subnet nodes that remain in the proposed topology
- `REMOVED`: Nodes being removed from the subnet
- `ADDED`: New nodes being added to the subnet

#### **Violation Analysis:**
```bash
# Check constraint violations
python3 -c "
import csv
from collections import Counter
with open('subnet_full_audit.csv') as f:
    reader = csv.reader(f)
    header = next(reader)
    violation_idx = header.index('constraint_violation')
    violations = [row[violation_idx] for row in reader if row[violation_idx] not in ['NO_VIOLATIONS', 'REMOVED_NODE']]
    if violations:
        for violation, count in Counter(violations).items():
            print(f'⚠️  {count} nodes: {violation}')
    else:
        print('✅ No topology constraint violations detected')
"
```

---

## **🔍 Advanced Use Cases**

### **1. Proposal Validation**

Compare your analysis with IC governance proposals:

```bash
# Analyze current subnet
./subnet_analyze.sh subnet
./checknodes.sh

# Simulate proposed changes (example from proposal 135700)
./subnet_whatif.sh subnet \
  --add-nodes proposed-node-1 proposed-node-2 \
  --remove-nodes current-node-1 current-node-2

# Check if proposal maintains topology compliance
grep -v "NO_VIOLATIONS\|REMOVED_NODE" subnet_full_audit.csv
```

### **2. Geographic Distribution Analysis**

```bash
# Analyze regional distribution
cut -d',' -f14 subnet_full_audit.csv | tail -n +2 | sort | uniq -c | sort -nr
```

### **3. Datacenter Consolidation Check**

```bash
# Find potential datacenter conflicts
python3 -c "
import csv
from collections import defaultdict
dc_nodes = defaultdict(list)
with open('subnet_full_audit.csv') as f:
    reader = csv.reader(f)
    header = next(reader)
    dc_idx = header.index('node_operator_dc')
    node_idx = header.index('node_id')
    change_idx = header.index('change_type')
    for row in reader:
        if row[change_idx] != 'REMOVED':
            dc_nodes[row[dc_idx]].append(row[node_idx][:20] + '...')

for dc, nodes in dc_nodes.items():
    if len(nodes) > 1:
        print(f'⚠️  DC {dc}: {len(nodes)} nodes - {nodes}')
"
```

---

## **📊 Understanding Output Files**

### **subnet_analysis.csv**
Basic subnet membership with essential identifiers:
```csv
node_id,operator_id,dc_id
wnuri-kqarn-qyjem-ae34x...,ri4lg-drli2-d5zpi-ts...,nd1
```

### **nodes_full_audit.csv** 
Complete node metadata with reward validation:
```csv
version,node_id,xnet,http,node_operator_id,chip_id,hostos_version_id,public_ipv4_config,domain,node_reward_type,node_provider_id,node_operator_rewardable_nodes,node_operator_dc,node_allowance,dc_region,dc_owner,reward_region,reward_xdr,reward_coefficient,reward_table_issue,node_operator_principal_id_mismatch,reward_type_mismatch
```

### **subnet_full_audit.csv**
Enhanced audit with change tracking and constraint validation:
```csv
[...all columns from nodes_full_audit.csv...],change_type,constraint_violation
```

---

## **🛠️ Troubleshooting**

### **Common Issues:**

1. **"nodes_full_audit.csv not found"**
   ```bash
   # Run checknodes.sh first
   ./checknodes.sh
   ```

2. **"No arguments provided and subnet_analysis.csv not found"**
   ```bash
   # Run subnet_analyze.sh first
   ./subnet_analyze.sh <subnet_id>
   ```

3. **Empty results or timeout errors**
   ```bash
   # Check network connectivity and IC network status
   ic-admin --nns-urls https://ic0.app get-registry-version
   
   # Test subnet access directly
   ic-admin --nns-url https://ic0.app get-subnet <subnet_id>
   ```

4. **Rate limiting or API errors**
   ```bash
   # The scripts include built-in delays to avoid rate limiting
   # If you encounter issues, wait a moment and retry
   # Check IC network status at https://status.internetcomputer.org/
   ```

### **Validation Steps:**

```bash
# Verify file permissions
ls -la *.sh

# Check if all scripts are executable
chmod +x *.sh

# Test basic ic-admin connectivity and subnet access
ic-admin --nns-urls https://ic0.app get-registry-version
ic-admin --nns-url https://ic0.app get-subnet <subnet_id>
```

### **Finding Node Provider Information:**

Since there's no direct `get-node-provider` command, use these approaches:

```bash
# Find node operators for a specific provider
grep "provider-principal-id" node_operators_status.csv

# Get detailed operator info (includes provider relationship)
ic-admin --json --nns-urls https://ic0.app get-node-operator operator-principal-id

# Find all providers in the network
cut -d',' -f4 node_operators_status.csv | tail -n +2 | sort | uniq
```

### **Understanding Principal ID Mismatches:**

The `node_operator_principal_id_mismatch` flag indicates registry inconsistencies:

```bash
# Find nodes with principal ID mismatches
grep ",MISMATCH$" nodes_full_audit.csv

# Count mismatch distribution
awk -F',' '{print $(NF-1)}' nodes_full_audit.csv | sort | uniq -c
```

**What this means:**
- `CORRECT`: Operator record key matches the stored principal ID (normal)
- `MISMATCH`: Operator record key differs from stored principal ID (registry inconsistency)
- Registry keys may differ from principal IDs due to updates or migrations

### **Reward Type Validation:**

The `reward_type_mismatch` flag validates node reward type consistency:

```bash
# Find nodes with reward type mismatches
python3 -c "
import csv
with open('nodes_full_audit.csv') as f:
    reader = csv.reader(f)
    header = next(reader)
    validation_idx = header.index('reward_type_mismatch')
    for row in reader:
        if row[validation_idx] == 'MISMATCH':
            print(f'❌ {row[1][:20]}... - Reward type mismatch')
"

# Get validation summary
python3 -c "
import csv
from collections import Counter
with open('nodes_full_audit.csv') as f:
    reader = csv.reader(f)
    header = next(reader)
    validation_idx = header.index('reward_type_mismatch')
    results = Counter(row[validation_idx] for row in reader)
    for result, count in results.items():
        status = '✅' if result == 'CORRECT' else '❌'
        print(f'{status} {result}: {count} nodes')
"
```

**Validation meanings:**
- `CORRECT`: Node reward type exists in operator's node_operator_rewardable_nodes (valid)
- `MISMATCH`: Node reward type missing from operator's node_operator_rewardable_nodes (mismatch)
- `UNKNOWN`: Missing data for validation
- `PARSE_ERROR`: Could not parse node_operator_rewardable_nodes data

---

## **🔗 Integration with IC Governance**

This toolkit is designed to support IC governance analysis:

- **Proposal Validation**: Simulate proposed subnet changes before voting
- **Topology Compliance**: Ensure modifications follow IC decentralization policies  
- **Impact Assessment**: Understand geographic and operator distribution effects
- **Risk Analysis**: Identify potential single points of failure

**Example Governance Workflow:**
1. Analyze current subnet state with `subnet_analyze.sh` + `checknodes.sh`
2. Simulate proposed changes with `subnet_whatif.sh`
3. Review constraint violations in `subnet_full_audit.csv`
4. Compare with proposal requirements
5. Make informed voting decisions

---

## **⚡ Quick Reference Commands**

```bash
# Check specific subnet
./subnet_analyze.sh <subnet>

# Audit current subnet nodes  
./checknodes.sh

# Simulate subnet modification
./subnet_whatif.sh <subnet> --add-nodes <nodes> --remove-nodes <nodes>

# Check for violations
grep -E "DUPLICATE_|violation" subnet_full_audit.csv
```







