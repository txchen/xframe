# Admit LAN candidates before ICE and revoke stale verification

Status: ready-for-agent

Console sessions configure public STUN and admit all local and remote candidates. The selected route is checked after connection. Missing selected-pair statistics preserve prior approval, and disconnect does not consistently hide or republish presentation.

Add same-subnet candidate admission at SDP and trickle boundaries, omit STUN for console sessions, and make route approval revocable with bounded freshness and recovery. Preserve cloud behavior.

## Evidence

- Sources/XFrame/Streaming/CloudVideoConnection.swift
- Sources/XFrame/Streaming/LocalMediaPath.swift
- .audit/lan-console/design.md

Application candidate admission and sampled statistics are not a network firewall. Actual Series X route and playback require live verification.

## Resolution

Implemented, independently reviewed, and exercised with the actual Series X. Video and keyboard input verified.
