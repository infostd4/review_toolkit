#!/usr/bin/env python3
"""
Generate an interactive HTML map showing IC subnet nodes with their geographic distribution,
change types (add/remove/unchanged), and constraint violations.
"""

import csv
import json
import argparse
from pathlib import Path

def read_subnet_data(csv_file):
    """Read subnet analysis data from CSV file."""
    nodes = []
    
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Parse GPS coordinates directly from CSV
            try:
                # Extract region info
                dc_region = row.get('dc_region', '')
                if dc_region and ',' in dc_region:
                    region_parts = dc_region.split(',')
                    country = region_parts[1] if len(region_parts) > 1 else ''
                    city = region_parts[2] if len(region_parts) > 2 else ''
                else:
                    country = ''
                    city = ''
                
                # Get GPS coordinates directly from CSV
                lat_str = row.get('gps_latitude', '').strip()
                lon_str = row.get('gps_longitude', '').strip()
                
                latitude = None
                longitude = None
                
                if lat_str and lat_str != 'None':
                    try:
                        latitude = float(lat_str)
                    except ValueError:
                        pass
                        
                if lon_str and lon_str != 'None':
                    try:
                        longitude = float(lon_str)
                    except ValueError:
                        pass
                
                node_data = {
                    'node_id': row.get('node_id', ''),
                    'node_operator_id': row.get('node_operator_id', ''),
                    'node_provider_id': row.get('node_provider_id', ''),
                    'dc_id': row.get('node_operator_dc', ''),
                    'dc_owner': row.get('dc_owner', ''),
                    'dc_region': dc_region,
                    'country': country,
                    'city': city,
                    'change_type': row.get('change_type', 'UNCHANGED'),
                    'constraint_violation': row.get('constraint_violation', ''),
                    'reward_region': row.get('reward_region', ''),
                    'reward_xdr': row.get('reward_xdr', '0'),
                    'latitude': latitude,  # Now populated directly from CSV
                    'longitude': longitude
                }
                nodes.append(node_data)
                
            except Exception as e:
                print(f"Warning: Could not process node {row.get('node_id', 'unknown')}: {e}")
                continue
    
    return nodes

def generate_html_map(nodes, output_file='subnet_map.html', subnet_id=''):
    """Generate an interactive HTML map using Leaflet."""
    
    # Filter nodes with valid coordinates (coordinates are now read directly from CSV)
    valid_nodes = [n for n in nodes if n['latitude'] is not None and n['longitude'] is not None]
    
    # Color scheme for different change types and violations
    color_scheme = {
        'ADDED': '#28a745',      # Green
        'REMOVED': '#dc3545',    # Red  
        'UNCHANGED': '#007bff',  # Blue
        'VIOLATION': '#ffc107'   # Yellow/Orange for violations
    }
    
    html_template = f"""
<!DOCTYPE html>
<html>
<head>
    <title>IC Subnet Analysis Map</title>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <style>
        body {{ margin: 0; padding: 0; font-family: Arial, sans-serif; }}
        #map {{ height: 100vh; width: 100%; }}
        .info-panel {{
            position: absolute;
            top: 10px;
            right: 10px;
            background: white;
            padding: 15px;
            border-radius: 5px;
            box-shadow: 0 0 15px rgba(0,0,0,0.2);
            z-index: 1000;
            max-width: 300px;
        }}
        .legend {{
            position: absolute;
            bottom: 30px;
            right: 10px;
            background: white;
            padding: 10px;
            border-radius: 5px;
            box-shadow: 0 0 15px rgba(0,0,0,0.2);
            z-index: 1000;
        }}
        .legend-item {{
            margin: 5px 0;
            display: flex;
            align-items: center;
        }}
        .legend-color {{
            width: 20px;
            height: 20px;
            margin-right: 10px;
            border-radius: 50%;
        }}
        .popup-content {{
            max-width: 300px;
        }}
        .popup-content h4 {{
            margin: 0 0 10px 0;
            color: #333;
        }}
        .popup-content .field {{
            margin: 5px 0;
        }}
        .popup-content .label {{
            font-weight: bold;
            display: inline-block;
            width: 120px;
        }}
    </style>
</head>
<body>
    <div id="map"></div>
    
    <div class="info-panel">
        <h3>IC Subnet Analysis</h3>
        <p><strong>Subnet ID:</strong><br>{subnet_id[:40]}...</p>
        <p><strong>Total Nodes Analysed:</strong> {len(nodes)}</p>
        <div>
            <strong>Changes:</strong><br>
            Added: {len([n for n in nodes if n['change_type'] == 'ADDED'])}<br>
            Removed: {len([n for n in nodes if n['change_type'] == 'REMOVED'])}<br>
            Unchanged: {len([n for n in nodes if n['change_type'] == 'UNCHANGED'])}
        </div>
        <div style="margin-top: 10px;">
            <strong>Topology Violations:</strong><br>
            {len([n for n in nodes if n['constraint_violation'] and n['constraint_violation'] not in ['NO_VIOLATIONS', 'REMOVED_NODE']])} nodes
        </div>
    </div>
    
    <div class="legend">
        <h4>Legend</h4>
        <div class="legend-item">
            <div class="legend-color" style="background-color: {color_scheme['ADDED']};"></div>
            <span>Added Nodes</span>
        </div>
        <div class="legend-item">
            <div class="legend-color" style="background-color: {color_scheme['REMOVED']};"></div>
            <span>Removed Nodes</span>
        </div>
        <div class="legend-item">
            <div class="legend-color" style="background-color: {color_scheme['UNCHANGED']};"></div>
            <span>Unchanged Nodes</span>
        </div>
        <div class="legend-item">
            <div class="legend-color" style="background-color: {color_scheme['VIOLATION']};"></div>
            <span>Constraint Violations</span>
        </div>
    </div>

    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <script>
        // Initialize map
        var map = L.map('map').setView([20, 0], 2);
        
        // Add tile layer
        L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
            attribution: '© OpenStreetMap contributors'
        }}).addTo(map);
        
        // Node data
        var nodes = {json.dumps(valid_nodes, indent=8)};
        
        // Color function
        function getNodeColor(node) {{
            // Priority: violations > change type
            if (node.constraint_violation && 
                node.constraint_violation !== 'NO_VIOLATIONS' && 
                node.constraint_violation !== 'REMOVED_NODE') {{
                return '{color_scheme['VIOLATION']}';
            }}
            
            switch(node.change_type) {{
                case 'ADDED': return '{color_scheme['ADDED']}';
                case 'REMOVED': return '{color_scheme['REMOVED']}';
                default: return '{color_scheme['UNCHANGED']}';
            }}
        }}
        
        // Add nodes to map
        nodes.forEach(function(node) {{
            var color = getNodeColor(node);
            var radius = node.change_type === 'REMOVED' ? 6 : 8;
            var opacity = node.change_type === 'REMOVED' ? 0.6 : 0.9;
            
            var marker = L.circleMarker([node.latitude, node.longitude], {{
                radius: radius,
                fillColor: color,
                color: '#000',
                weight: 1,
                opacity: opacity,
                fillOpacity: 0.8
            }}).addTo(map);
            
            // Create popup content
            var popupContent = `
                <div class="popup-content">
                    <h4>${{node.node_id.substring(0, 20)}}...</h4>
                    <div class="field">
                        <span class="label">Change Type:</span>
                        <span style="color: ${{color}}; font-weight: bold;">${{node.change_type}}</span>
                    </div>
                    <div class="field">
                        <span class="label">Datacenter:</span>
                        ${{node.dc_id}} (${{node.dc_owner}})
                    </div>
                    <div class="field">
                        <span class="label">Location:</span>
                        ${{node.dc_region}}
                    </div>
                    <div class="field">
                        <span class="label">Reward Region:</span>
                        ${{node.reward_region}}
                    </div>
                    <div class="field">
                        <span class="label">Operator:</span>
                        ${{node.node_operator_id.substring(0, 20)}}...
                    </div>
                    <div class="field">
                        <span class="label">Provider:</span>
                        ${{node.node_provider_id.substring(0, 20)}}...
                    </div>
                    ${{node.constraint_violation && node.constraint_violation !== 'NO_VIOLATIONS' && node.constraint_violation !== 'REMOVED_NODE' ? 
                        `<div class="field" style="color: #dc3545; font-weight: bold;">
                            <span class="label">Violations:</span>
                            ${{node.constraint_violation}}
                        </div>` : ''
                    }}
                </div>
            `;
            
            marker.bindPopup(popupContent);
        }});
        
        // Fit map to show all nodes
        if (nodes.length > 0) {{
            var group = new L.featureGroup();
            nodes.forEach(function(node) {{
                group.addLayer(L.marker([node.latitude, node.longitude]));
            }});
            map.fitBounds(group.getBounds().pad(0.1));
        }}
        
        // Add country borders (optional - requires additional data)
        // You could add GeoJSON country boundaries here for better visualization
        
    </script>
</body>
</html>
"""
    
    with open(output_file, 'w') as f:
        f.write(html_template)
    
    print(f"Interactive map generated: {output_file}")
    print(f"Open in browser to view: file://{Path(output_file).absolute()}")

def main():
    parser = argparse.ArgumentParser(description='Generate interactive map for IC subnet analysis')
    parser.add_argument('--input', '-i', default='subnet_full_audit.csv', 
                       help='Input CSV file (default: subnet_full_audit.csv)')
    parser.add_argument('--output', '-o', default='subnet_map.html',
                       help='Output HTML file (default: subnet_map.html)')
    parser.add_argument('--subnet-id', '-s', default='',
                       help='Subnet ID for display')
    
    args = parser.parse_args()
    
    if not Path(args.input).exists():
        print(f"Error: Input file {args.input} not found")
        return 1
    
    # Read data
    print(f"Reading data from {args.input}...")
    nodes = read_subnet_data(args.input)
    
    if not nodes:
        print("No nodes found in input file")
        return 1
    
    # Generate map
    print(f"Generating map for {len(nodes)} nodes...")
    generate_html_map(nodes, args.output, args.subnet_id)
    
    return 0

if __name__ == '__main__':
    exit(main())
