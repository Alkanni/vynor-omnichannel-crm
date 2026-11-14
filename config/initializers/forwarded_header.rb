# Rails 8.1 reads the client address from the RFC 7239 Forwarded header before X-Forwarded-For, as Rack 3 already did for
# Rack::Request#ip, which the Rack::Attack throttles key on. The proxy in front of the app (Caddy) writes X-Forwarded-For
# but passes a Forwarded header from the client through, so the client could choose its own address: Rails answers a
# mismatch with ActionDispatch::RemoteIp::IpSpoofAttackError (HTTP 500), and Rack::Attack would throttle and safelist by the
# address the client claims. Reading X-Forwarded-For only is the workaround of GHSA-2gff-2mmg-m73p, for both Rails and
# Rack (see docs/rails_upgrades/8_1.md).
Rack::Request.forwarded_priority = [:x_forwarded]
