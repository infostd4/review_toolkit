#!/usr/bin/env python3
"""
Generate a text-based geographic summary of IC subnet nodes.
Useful for quick terminal-based analysis without needing a browser.
"""

import csv
import argparse
from collections import defaultdict, Counter
from pathlib import Path

def read_subnet_data(csv_file):
    """Read subnet analysis data from CSV file."""
    nodes = []
    
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes.append({
                'node_id': row.get('node_id', ''),
                'dc_id': row.get('node_operator_dc', ''),
                'dc_owner': row.get('dc_owner', ''),
                'dc_region': row.get('dc_region', ''),
                'change_type': row.get('change_type', 'UNCHANGED'),
                'constraint_violation': row.get('constraint_violation', ''),
                'reward_region': row.get('reward_region', ''),
            })
    
    return nodes

def analyze_geographic_distribution(nodes):
    """Analyze and display geographic distribution."""
    # Parse regions
    regions = defaultdict(list)
    countries = defaultdict(list)
    continents = defaultdict(list)
    
    for node in nodes:
        dc_region = node['dc_region']
        change_type = node['change_type']
        violations = node['constraint_violation']
        
        if dc_region and ',' in dc_region:
            parts = [p.strip() for p in dc_region.split(',')]
            if len(parts) >= 3:
                continent, country, city = parts[0], parts[1], parts[2]
            elif len(parts) == 2:
                continent, country, city = parts[0], parts[1], ''
            else:
                continent, country, city = parts[0], '', ''
        else:
            continent, country, city = dc_region, '', ''
        
        node_info = {
            'node_id': node['node_id'][:20] + '...',
            'dc_id': node['dc_id'],
            'dc_owner': node['dc_owner'],
            'change_type': change_type,
            'violations': violations,
            'city': city
        }
        
        regions[f"{continent},{country}"].append(node_info)
        countries[country].append(node_info)
        continents[continent].append(node_info)
    
    return regions, countries, continents

def print_geographic_summary(nodes, subnet_id=''):
    """Print a comprehensive geographic summary."""
    regions, countries, continents = analyze_geographic_distribution(nodes)
    
    # Change type colors for terminal
    colors = {
        'ADDED': '🟢',
        'REMOVED': '🔴',
        'UNCHANGED': '🔵',
        'VIOLATION': '🟡'
    }
    
    print("=" * 80)
    print("🌍 GEOGRAPHIC DISTRIBUTION ANALYSIS")
    print("=" * 80)
    if subnet_id:
        print(f"Subnet: {subnet_id}")
    print(f"Total Nodes: {len(nodes)}")
    print()
    
    # Summary by change type
    change_counts = Counter(node['change_type'] for node in nodes)
    violation_count = len([n for n in nodes if n['constraint_violation'] and 
                          n['constraint_violation'] not in ['NO_VIOLATIONS', 'REMOVED_NODE']])
    
    print("📊 CHANGE SUMMARY:")
    for change_type, count in change_counts.items():
        icon = colors.get(change_type, '⚪')
        print(f"  {icon} {change_type}: {count} nodes")
    if violation_count > 0:
        print(f"  🟡 VIOLATIONS: {violation_count} nodes")
    print()
    
    # Country distribution
    print("🌎 COUNTRY DISTRIBUTION:")
    country_summary = []
    for country, country_nodes in countries.items():
        if not country:
            continue
        
        change_breakdown = Counter(node['change_type'] for node in country_nodes)
        violation_nodes = [n for n in country_nodes if n['violations'] and 
                          n['violations'] not in ['NO_VIOLATIONS', 'REMOVED_NODE']]
        
        summary = f"  {country}: {len(country_nodes)} nodes"
        if len(change_breakdown) > 1 or violation_nodes:
            details = []
            for change_type, count in change_breakdown.items():
                if count > 0:
                    icon = colors.get(change_type, '⚪')
                    details.append(f"{icon}{count}")
            if violation_nodes:
                details.append(f"🟡{len(violation_nodes)} violations")
            summary += f" ({', '.join(details)})"
        
        country_summary.append((country, len(country_nodes), summary))
    
    # Sort by node count
    for country, count, summary in sorted(country_summary, key=lambda x: x[1], reverse=True):
        print(summary)
    print()
    
    # Detailed regional breakdown
    print("🏙️  DETAILED REGIONAL BREAKDOWN:")
    for region, region_nodes in sorted(regions.items()):
        if not region or region == ',':
            continue
            
        print(f"\n  📍 {region} ({len(region_nodes)} nodes):")
        
        # Group by datacenter
        dc_groups = defaultdict(list)
        for node in region_nodes:
            dc_groups[f"{node['dc_id']} ({node['dc_owner']})"].append(node)
        
        for dc_info, dc_nodes in sorted(dc_groups.items()):
            print(f"    🏢 {dc_info}:")
            for node in dc_nodes:
                icon = colors.get(node['change_type'], '⚪')
                violation_marker = ' ⚠️ ' if (node['violations'] and 
                                           node['violations'] not in ['NO_VIOLATIONS', 'REMOVED_NODE']) else ''
                city_info = f" ({node['city']})" if node['city'] else ''
                print(f"      {icon} {node['node_id']}{city_info}{violation_marker}")
                if violation_marker:
                    print(f"         └─ Violations: {node['violations']}")
    
    # Constraint analysis
    print("\n" + "=" * 80)
    print("🚨 CONSTRAINT ANALYSIS:")
    print("=" * 80)
    
    # Check datacenters and owners
    datacenters = defaultdict(list)
    owners = defaultdict(list)
    
    for node in nodes:
        if node['change_type'] == 'REMOVED':
            continue
        # Note: We don't have provider info in this simple version
        # This would need to be enhanced to include provider data
        datacenters[node['dc_id']].append(node)
        owners[node['dc_owner']].append(node)
    
    # Check for violations
    dc_violations = [(dc, nodes) for dc, nodes in datacenters.items() if len(nodes) > 1]
    owner_violations = [(owner, nodes) for owner, nodes in owners.items() if len(nodes) > 1]
    
    if dc_violations:
        print("🏢 DATACENTER CONSTRAINT VIOLATIONS:")
        for dc, dc_nodes in dc_violations:
            print(f"  ⚠️  {dc}: {len(dc_nodes)} nodes")
            for node in dc_nodes:
                icon = colors.get(node['change_type'], '⚪')
                print(f"    {icon} {node['node_id']}")
        print()
    
    if owner_violations:
        print("🏭 DATACENTER OWNER CONSTRAINT VIOLATIONS:")
        for owner, owner_nodes in owner_violations:
            print(f"  ⚠️  {owner}: {len(owner_nodes)} nodes")
            for node in owner_nodes:
                icon = colors.get(node['change_type'], '⚪')
                print(f"    {icon} {node['node_id']}")
        print()
    
    if not dc_violations and not owner_violations:
        print("✅ No obvious datacenter or owner constraint violations detected")
        print("   (Note: Provider constraint checking requires full audit data)")
        print()
    
    print("=" * 80)
    print("💡 TIP: For full interactive geographic visualization,")
    print("   open subnet_map.html in your browser")
    print("=" * 80)

def main():
    parser = argparse.ArgumentParser(description='Generate text-based geographic analysis for IC subnet')
    parser.add_argument('--input', '-i', default='subnet_full_audit.csv', 
                       help='Input CSV file (default: subnet_full_audit.csv)')
    parser.add_argument('--subnet-id', '-s', default='',
                       help='Subnet ID for display')
    
    args = parser.parse_args()
    
    if not Path(args.input).exists():
        print(f"Error: Input file {args.input} not found")
        return 1
    
    # Read data
    nodes = read_subnet_data(args.input)
    
    if not nodes:
        print("No nodes found in input file")
        return 1
    
    # Generate summary
    print_geographic_summary(nodes, args.subnet_id)
    
    return 0

if __name__ == '__main__':
    exit(main())
