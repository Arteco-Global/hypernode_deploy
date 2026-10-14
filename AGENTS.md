# Project context

This repository is part of uSS, the server suite.

## Architecture context

- uSS comprises `hypernode-server`, `hypernode_server_gui` (including `/configurator` and `/installer`), and `hypernode_deploy`.
- A uSee client can connect to multiple uSS servers. During synchronization, the client downloads the available server list from `arteco-global.com`.
- uSee is the web client solution (MERN) and comprises `omnia-web-client`, `omnia-web-backend`, and `omnia-web-deploy`. It uses `arteco-global.com` for SSO.
