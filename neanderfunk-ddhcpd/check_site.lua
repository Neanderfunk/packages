-- Alles je Domain (in_domain): eine Domain schaltet ddhcpd ein, die anderen
-- bleiben aus.
local ipv4 = '^%d+%.%d+%.%d+%.%d+$'
local cidr4 = '^%d+%.%d+%.%d+%.%d+/%d+$'

need_string_match(in_domain({'next_node', 'ip4'}), ipv4)

need_boolean(in_domain({'ddhcpd', 'enabled'}), false)
-- Bereich, den ddhcpd in Bloecken vergibt
need_string_match(in_domain({'ddhcpd', 'range'}), cidr4, false)
-- Client-Netz der Domain; daraus die Netzmaske (Option 1) fuer die Clients.
-- Nicht aus prefix4 (bei uns site-weit /8) und nicht aus range.
need_string_match(in_domain({'ddhcpd', 'client_prefix4'}), cidr4, false)
-- Option 3 und 6
need_string_match(in_domain({'ddhcpd', 'router'}), ipv4, false)
need_string_array_match(in_domain({'ddhcpd', 'dns'}), ipv4, false)

-- Zweierpotenz der Blockgroesse; der Daemon speichert die Groesse in 8 Bit
need_number_range(in_domain({'ddhcpd', 'block_size'}), 0, 7, false)
need_number(in_domain({'ddhcpd', 'block_timeout'}), false)
need_number(in_domain({'ddhcpd', 'learning_time'}), false)
need_number(in_domain({'ddhcpd', 'dhcp_lease_time'}), false)
need_number_range(in_domain({'ddhcpd', 'spare_leases'}), 0, 255, false)
need_number_range(in_domain({'ddhcpd', 'tentative_timeout'}), 3, 3600, false)
