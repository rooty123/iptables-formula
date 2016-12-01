# Firewall management module
{%- if salt['pillar.get']('firewall:enabled') %}
  {% set firewall = salt['pillar.get']('firewall', {}) %}
  {% set install = firewall.get('install', False) %}
  {% set strict_mode = firewall.get('strict', False) %}
  {% set global_block_nomatch = firewall.get('block_nomatch', False) %}
  {% set packages = salt['grains.filter_by']({
    'Debian': ['iptables', 'iptables-persistent'],
    'RedHat': ['iptables'],
    'default': 'Debian'}) %}

    {%- if install %}
      # Install required packages for firewalling
      iptables_packages:
        pkg.installed:
          - pkgs:
            {%- for pkg in packages %}
            - {{pkg}}
            {%- endfor %}
    {%- endif %}

    {%- if strict_mode %}
      # If the firewall is set to strict mode, we'll need to allow some
      # that always need access to anything
      iptables_allow_localhost:
        iptables.append:
          - table: filter
          - chain: INPUT
          - jump: ACCEPT
          - source: 127.0.0.1
          - save: True

      # Allow related/established sessions
      iptables_allow_established:
        iptables.append:
          - table: filter
          - chain: INPUT
          - jump: ACCEPT
          - match: conntrack
          - ctstate: 'RELATED,ESTABLISHED'
          - save: True

      # Set the policy to deny everything unless defined
      enable_reject_policy:
        iptables.set_policy:
          - table: filter
          - chain: INPUT
          - policy: DROP
          - require:
            - iptables: iptables_allow_localhost
            - iptables: iptables_allow_established
    {%- endif %}

/sbin/iptables -F FORWARD:
    cmd.run

  # Generate ipsets for all services that we have information about
  {%- for service_name, service_details in firewall.get('services', {}).items() %}
    {% set block_nomatch = service_details.get('block_nomatch', False) %}
    {% set interfaces = service_details.get('interfaces','') %}
    {% set protos = service_details.get('protos',['tcp']) %}
    {% set docker = service_details.get('docker', False) %}
    {%- if docker %}
    {% set chain = 'FORWARD' %}
    {%- else %}
    {% set chain = 'INPUT' %}
    {%- endif %}

    {%- if docker %}
     {%- for ip in service_details.get('ips_allow', []) %}
       {%- for proto in protos %}
        iptables_{{service_name}}_allow_{{ip}}_docker:
            iptables.insert:
              - position: 1
              - table: filter
              - chain: {{ chain }}
              - jump: DOCKER
              - source: {{ ip }}
              - dport: {{ service_name }}
              - proto: {{ proto }}
              - save: True
       {%- endfor %}
     {%- endfor %}
    {%- endif %}

    # Allow rules for ips/subnets
    {%- for ip in service_details.get('ips_allow', []) %}
      {%- if interfaces == '' %}
        {%- for proto in protos %}
      iptables_{{service_name}}_allow_{{ip}}_{{proto}}:
        {%- if docker %}
        iptables.insert:
          - position: 1
        {%- else %}
        iptables.append:
        {%- endif %}
          - table: filter
          - chain: {{ chain }}
          - jump: ACCEPT
          - source: {{ ip }}
          - dport: {{ service_name }}
          - proto: {{ proto }}
          - save: True
        {%- endfor %}
      {%- else %}
        {%- for interface in interfaces %}
          {%- for proto in protos %}
      iptables_{{service_name}}_allow_{{ip}}_{{proto}}_{{interface}}:
        {%- if docker %}
        iptables.insert:
          - position: 1
        {%- else %}
        iptables.append:
        {%- endif %}
          - table: filter
          - chain: {{ chain }}
          - jump: ACCEPT
          - i: {{ interface }}
          - source: {{ ip }}
          - dport: {{ service_name }}
          - proto: {{ proto }}
          - save: True
          {%- endfor %}
        {%- endfor %}
      {%- endif %}
    {%- endfor %}

    {%- if not strict_mode and global_block_nomatch or block_nomatch %}
      # If strict mode is disabled we may want to block anything else
      {%- if interfaces == '' %}
        {%- for proto in protos %}
      iptables_{{service_name}}_deny_other_{{proto}}:
        {%- if docker %}
        iptables.insert:
        {%- else %}
        iptables.append:
        {%- endif %}
          - position: 1
          - table: filter
          - chain: {{ chain }}
          - jump: REJECT
          - dport: {{ service_name }}
          - proto: {{ proto }}
          - save: True
        {%- endfor %}
      {%- else %}
        {%- for interface in interfaces %}
          {%- for proto in protos %}
      iptables_{{service_name}}_deny_other_{{proto}}_{{interface}}:
        {%- if docker %}
        iptables.insert:
        {%- else %}
        iptables.append:
        {%- endif %}
          - position: 1
          - table: filter
          - chain: {{ chain }}
          - jump: REJECT
          - i: {{ interface }}
          - dport: {{ service_name }}
          - proto: {{ proto }}
          - save: True
          {%- endfor %}
        {%- endfor %}
      {%- endif %}

    {%- endif %}

  {%- endfor %}

  # Generate rules for NAT
  {%- for service_name, service_details in firewall.get('nat', {}).items() %}
    {%- for ip_s, ip_ds in service_details.get('rules', {}).items() %}
      {%- for ip_d in ip_ds %}
      iptables_{{service_name}}_allow_{{ip_s}}_{{ip_d}}:
        iptables.append:
          - table: nat
          - chain: POSTROUTING
          - jump: MASQUERADE
          - o: {{ service_name }}
          - source: {{ ip_s }}
          - destination: {{ip_d}}
          - save: True
      {%- endfor %}
    {%- endfor %}
  {%- endfor %}

  # Generate rules for whitelisting IP classes
  {%- for service_name, service_details in firewall.get('whitelist', {}).items() %}
    {%- for ip in service_details.get('ips_allow', []) %}
      iptables_{{service_name}}_allow_{{ip}}:
        iptables.append:
           - table: filter
           - chain: INPUT
           - jump: ACCEPT
           - source: {{ ip }}
           - save: True
    {%- endfor %}
  {%- endfor %}

{%- endif %}
