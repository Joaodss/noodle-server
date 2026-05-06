locals {
  cloud_config = <<-EOT
#cloud-config
write_files:      
  - path: /var/lib/cloud/scripts/per-boot/fs-prepare.sh
    permissions: "0544"
    owner: root
    content: |
      #!/bin/bash
      DATA_DISK="/dev/disk/by-id/google-container_host_data_disk_0"
      MOUNT_DIR="/mnt/disks/data"
      PARENT_DIR="/mnt/disks"

      mkdir -p $MOUNT_DIR || true

      echo "Waiting for disk to appear..."
      for i in {1..30}; do
        if [ -b "$DATA_DISK" ]; then
          echo "Disk found!"
          break
        fi
        sleep 1
      done

      if ! blkid $DATA_DISK; then
        mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard $DATA_DISK
      fi

      if ! mountpoint -q $MOUNT_DIR; then
        mount -o discard,defaults $DATA_DISK $MOUNT_DIR || echo "Mount failed"
      fi

      if mountpoint -q $MOUNT_DIR; then
        chmod 555 $PARENT_DIR  
        mkdir -p "$MOUNT_DIR/dockge" "$MOUNT_DIR/stacks"
        chown -R root:root $MOUNT_DIR
      else  
        chmod 555 $PARENT_DIR
        exit 1
      fi

  - path: /etc/systemd/system/docker.service.d/override.conf
    permissions: "0644"
    owner: root
    content: |
      [Unit]
      Requires=mnt-disks-data.mount
      After=mnt-disks-data.mount

  - path: /etc/systemd/system/dockge.service
    permissions: "0644"
    owner: root
    content: |
      [Unit]
      Description=Dockge
      After=network-online.target docker.service local-fs.target
      Requires=docker.service
      RequiresMountsFor=/mnt/disks/data

      [Service]
      Type=simple
      ExecStartPre=/usr/bin/docker pull louislam/dockge:latest
      ExecStart=/usr/bin/docker run --rm --name dockge \
        --network custom-bridge \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /mnt/disks/data/dockge:/app/data \
        -v /mnt/disks/data/stacks:/opt/stacks \
        -p 127.0.0.1:5001:5001 \
        -e DOCKGE_STACKS_DIR=/opt/stacks \
        louislam/dockge:latest
      ExecStop=/usr/bin/docker stop dockge
      Restart=always
      RestartSec=5

      [Install]
      WantedBy=multi-user.target

runcmd:
  - docker network create custom-bridge || true
  - bash /var/lib/cloud/scripts/per-boot/fs-prepare.sh
  - systemctl daemon-reload
  - systemctl restart docker
  - systemctl enable dockge.service
  - systemctl start dockge.service
EOT
}
