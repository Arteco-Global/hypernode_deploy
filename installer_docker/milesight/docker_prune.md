# Docker Cleanup Commands

Useful Docker pruning commands to remove containers, images, volumes, and other unused resources.

```bash
sudo docker stop $(sudo docker ps -aq)
sudo docker rm -f $(sudo docker ps -aq)
sudo docker rmi -f $(sudo docker images -q)
sudo docker volume rm $(sudo docker volume ls -q)
sudo docker system prune -a --volumes -f
```

> ⚠️ These commands remove all containers, images, and volumes on the host. Run them only when you are sure you no longer need those resources.
