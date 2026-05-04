locals {
  cloud_config = <<-EOT
    #cloud-config
    write_files:
      - path: /var/lib/cloud/scripts/per-instance/fs-prepare.sh
        permissions: "0544"
        owner: root
        content: |
          #!/bin/bash
          set -e
          DATA_DISK="/dev/disk/by-id/google-container_host_data_disk_0"
          MOUNT_DIR="/mnt/disks/data"
          if ! blkid $DATA_DISK; then
            mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard $DATA_DISK
          fi
          mkdir -p $MOUNT_DIR
          if ! grep -q "$DATA_DISK" /etc/fstab; then
            echo "$DATA_DISK $MOUNT_DIR ext4 discard,defaults,nofail 0 2" >> /etc/fstab
          fi
          mount -a
          mkdir -p "$MOUNT_DIR/dockge" "$MOUNT_DIR/stacks"
          chown -R root:root $MOUNT_DIR

      - path: /etc/systemd/system/dockge.service
        permissions: "0644"
        owner: root
        content: |
          [Unit]
          Description=Dockge
          After=network-online.target docker.service
          Requires=docker.service
          [Service]
          ExecStartPre=/usr/bin/docker pull louislam/dockge:latest
          ExecStart=/usr/bin/docker run --rm --name dockge \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v /mnt/disks/data/dockge:/app/data \
            -v /mnt/disks/data/stacks:/opt/stacks \
            -p 5001:5001 louislam/dockge:latest
          Restart=unless-stopped

    runcmd:
      - bash /var/lib/cloud/scripts/per-instance/fs-prepare.sh
      - systemctl daemon-reload
      - systemctl enable dockge.service
      - systemctl start dockge.service
  EOT
}
