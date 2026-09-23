# Require a local media path for console play

[Xbox Remote Play](https://www.xbox.com/en-ca/consoles/remote-play) can reach an account-linked console over the Internet, so account association alone does not establish a LAN media route. XFrame will list those consoles but permit a Local Console Session only when its selected media and controller transport can be verified as local. We chose this boundary because the requested feature is LAN console streaming; accepting an Internet relay would change its latency, privacy, and availability behavior without the user's knowledge.
