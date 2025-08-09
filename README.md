# Internet Computer Network Review Toolkit

A comprehensive suite of tools for analyzing IC network topology, validating subnet configurations, and simulating subnet modifications with constraint checking. Designed to support IC governance decisions with detailed analysis of node operators, datacenters, geographic distribution, and topology compliance.

## 🎯 Purpose

The Internet Computer network operates under strict topology constraints to ensure decentralization, fault tolerance, and geographic distribution. This toolkit helps:

- **Governance Participants**: Analyze proposals involving subnet modifications
- **Node Operators**: Understand network topology and placement requirements  
- **Researchers**: Study IC network structure and decentralization metrics
- **Developers**: Validate subnet configurations before deployment

## 🏗️ Scripts Overview

### `checknodes.sh` - Node Analysis
Deep analysis of individual nodes with complete metadata extraction, reward validation, and configuration verification.

### `subnet_analyze.sh` - Subnet Composition
Extracts current subnet membership and provides basic composition overview from live IC network data.

### `subnet_whatif.sh` - Subnet Modification Simulator
Simulates subnet changes, validates topology constraints, checks for violations, and generates interactive maps with geographic summaries.

### `review.sh` - Unified Interface
Single entry point combining all toolkit functionality with parallel processing, bulk operations, and streamlined workflows.

## 🔄 Workflows

### 1. Node Analysis
Analyze specific nodes for compliance and metadata validation using `checknodes.sh` or `review.sh nodes`.

### 2. Subnet Analysis  
Understand current subnet composition using `subnet_analyze.sh` or `review.sh subnet`.

### 3. Governance Proposal Analysis
1. Analyze current subnet state
2. Simulate proposed changes with `subnet_whatif.sh`
3. Review constraint violations and geographic impact
4. Generate visualizations and compare with proposal details

### 4. Configuration-Driven Analysis
Use `node_list.md` and `subnet_whatif.txt` configuration files with `review.sh` for automated workflows.

## 🛡️ Topology Constraints

The toolkit validates IC topology policies automatically:

### Provider/Datacenter Constraints
- **Standard**: 1 node per provider/datacenter per subnet
- **Exception**: Dfinity Foundation can have up to 3 nodes in NNS subnet

### Geographic Constraints
- **NNS/SNS/Fiduciary/Internet Identity**: Up to 3 nodes per country
- **Bitcoin/European/Application Subnets**: Up to 2 nodes per country
- **Swiss and US Subnets**: Up to 13 nodes per country

### Violation Flags
- `NO_VIOLATIONS`: Passes all constraints
- `DUPLICATE_PROVIDER`: Multiple nodes from same provider
- `DUPLICATE_DC`: Multiple nodes from same datacenter  
- `DUPLICATE_OWNER`: Multiple nodes from same datacenter owner
- `DUPLICATE_COUNTRY`: Exceeds country node limits
- `REMOVED_NODE`: Node being removed (excluded from checks)

## 📊 Output Files

- **nodes_full_audit.csv**: Comprehensive node metadata with validation flags
- **subnet_full_audit.csv**: Subnet analysis with change tracking and constraint violations
- **subnet_analysis.csv**: Basic subnet membership overview
- **subnet_map.html**: Interactive geographic visualization

## 🎯 Governance Integration

Directly supports IC governance with:
- **Proposal Validation**: Verify changes comply with topology policies
- **Impact Assessment**: Understand geographic and operator distribution effects  
- **Risk Analysis**: Identify potential single points of failure
- **Evidence-Based Decisions**: Provide concrete data for voting

**Reference**: [Proposal 137147](https://dashboard.internetcomputer.org/proposal/137147) for target topology analysis.

## 🚀 Getting Started

1. **Prerequisites**: Install and configure `ic-admin` tool
2. **Basic Analysis**: `review.sh subnet <subnet-id>` 
3. **Whatif Analysis**: `review.sh whatif <subnet-id> --add-nodes <node> --remove-nodes <node> --map`
4. **Advanced Usage**: Create configuration files for complex scenarios
