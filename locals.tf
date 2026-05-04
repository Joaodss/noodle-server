locals {
  cloud_config = <<-EOT
    #cloud-config
    ${yamlencode({
  write_files = [
    {
      path        = "/var/lib/cloud/scripts/per-instance/fs-prepare.sh"
      permissions = "0544"
      owner       = "root"
      content     = <<-EOT1
        #!/bin/bash
        set -e

        DATA_DISK="/dev/disk/by-id/google-container_host_data_disk_0"
        MOUNT_DIR="/mnt/disks/data"

        echo "Checking if disk needs formatting..."
        if ! blkid $DATA_DISK; then
          echo "Formatting disk..."
          mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard $DATA_DISK
        fi

        echo "Creating mount directory..."
        mkdir -p $MOUNT_DIR

        echo "Adding disk to fstab if not already present..."
        if ! grep -q "$DATA_DISK" /etc/fstab; then
          echo "$DATA_DISK $MOUNT_DIR ext4 discard,defaults,nofail 0 2" >> /etc/fstab
        fi

        echo "Mounting disk..."
        mount -a

        echo "Creating required directories..."
        mkdir -p "$MOUNT_DIR/dockge"  # Dockge internal state
        mkdir -p "$MOUNT_DIR/stacks"  # One sub-directory per compose stack

        echo "Setting permissions..."
        chown -R root:root $MOUNT_DIR
        chmod -R 755 $MOUNT_DIR
        EOT1
    },
    {
      path        = "/etc/systemd/system/dockge.service"
      permissions = "0644"
      owner       = "root"
      content     = <<-EOT2
        [Unit]
        Description=Dockge - Docker Compose manager
        After=network-online.target docker.service
        Requires=docker.service
        RequiresMountsFor=/data

        [Service]
        ExecStart=/usr/bin/docker run --rm \
          --name dockge \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v /data/dockge:/app/data \
          -v /data/stacks:/opt/stacks \
          -p 127.0.0.1:5001:5001 \
          -e DOCKGE_STACKS_DIR=/opt/stacks \
          louislam/dockge:latest
        ExecStop=/usr/bin/docker stop dockge
        ExecStopPost=/usr/bin/docker rm dockge
        Restart=unless-stopped
        TimeoutStartSec=0
        TimeoutStopSec=10

        [Install]
        WantedBy=multi-user.target
        EOT2
    }
  ]

  bootcmd = [
    "bash /var/lib/cloud/scripts/per-instance/fs-prepare.sh"
  ]

  runcmd = [
    "while ! mountpoint -q /mnt/disks/data; do sleep 1; done",

    "docker network create custom-bridge || true",

    "systemctl daemon-reload",
    "systemctl enable dockge.service",
    "systemctl start dockge.service"
  ]
})}
  EOT
}
