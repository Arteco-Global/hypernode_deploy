# Automation and Integration deployment

Both active native-split workflows (standard and legacy Mongo) include `integration` and `automation` in `all`, as individual service choices, and in the image manifest jobs.

| Service | Image | Dockerfile in hypernode-server |
| --- | --- | --- |
| integration | artecoglobalcompany/usee_integration_manager | docker/integration.Dockerfile |
| automation | artecoglobalcompany/usee_automation_service | docker/automation.Dockerfile |

Full server and Synology compose definitions include both services. Each uses its own `integration-db` or `automation-db` in the configured MongoDB instance and the existing RabbitMQ connection. Additional-instance compose definitions are available in `composes/integration` and `composes/automation`, with process-specific databases.

The shell installer offers options 17/18 to install/update Integration and 19/20 to install/update Automation. Native update scripts accept `--service integration` and `--service automation`; suite updates include both. The GUI installer offers both services and maps their discovered service types to the matching compose definitions.

The backend's `pkg:all` includes Automation as well as Integration. Docker build/push helper scripts, release ledger generation and image tag cleanup defaults also include both images.

Build and publish both images for the chosen tag before installing or updating. These configuration changes do not publish images or update running installations automatically. Archived workflows under `old_workflows` are not changed.
