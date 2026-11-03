locals {
  cloud_config = <<-EOT
#cloud-config

write_files:
  - path: /etc/systemd/system/mnt-disks-data.mount
    permissions: "0644"
    owner: root
    content: |
      [Unit]
      Description=Persistent data disk

      [Mount]
      What=/dev/disk/by-id/google-container_host_data_disk_0
      Where=/mnt/disks/data
      Type=ext4
      Options=defaults,nofail,x-systemd.device-timeout=120,noatime

      [Install]
      WantedBy=multi-user.target

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
      After=network-online.target docker.service mnt-disks-data.mount
      Requires=docker.service mnt-disks-data.mount

      [Service]
      Type=simple
      ExecStartPre=-/usr/bin/docker network create custom-bridge
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

  - path: /etc/systemd/system/swapfile.service
    permissions: "0644"
    owner: root
    content: |
      [Unit]
      Description=Swapfile on persistent data disk
      Requires=mnt-disks-data.mount
      After=mnt-disks-data.mount
      Before=docker.service

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=/bin/sh /etc/noodle/setup-swap.sh
      ExecStop=/bin/sh -c 'swapoff /mnt/disks/data/swapfile'

      [Install]
      WantedBy=multi-user.target

  - path: /etc/noodle/setup-swap.sh
    permissions: "0755"
    owner: root
    content: |
      #!/bin/sh
      # 1G swap file on the persistent disk. Recreated if it exists without a
      # valid swap signature (e.g. a crash between fallocate and mkswap).
      set -eu
      f=/mnt/disks/data/swapfile
      if ! blkid -p -s TYPE -o value "$f" 2>/dev/null | grep -qx swap; then
        rm -f "$f"
        fallocate -l 1G "$f"
        chmod 600 "$f"
        mkswap "$f"
      fi
      grep -qs "^$f " /proc/swaps || swapon "$f"

  - path: /etc/noodle/prepare-data-disk.sh
    permissions: "0755"
    owner: root
    content: |
      #!/bin/sh
      # Runs from cloud-init on every boot. Docker starts before cloud-init and
      # runs with live-restore, so containers started early bind-mount the empty
      # placeholder /mnt/disks/data and keep it. Stop them, mount the real disk,
      # and start them again only if the real disk is confirmed. Otherwise leave
      # every container stopped.
      set -u
      DATA=/mnt/disks/data
      MARKER="$DATA/THIS_IS_THE_REAL_DISK"
      # Kept on the boot disk so a failed boot does not forget which containers
      # it stopped (docker treats them as manually stopped afterwards).
      STATE=/var/lib/noodle/stopped-containers

      mkdir -p /var/lib/noodle "$DATA"

      docker ps -q >> "$STATE"
      ids=$(sort -u "$STATE" | tr '\n' ' ')
      if [ -n "$(docker ps -q)" ]; then
        echo "prepare-data-disk: stopping containers started before the data disk"
        docker ps -q | xargs -r docker stop
      fi

      systemctl start mnt-disks-data.mount

      if ! grep -qs " $DATA ext4 " /proc/mounts || [ ! -e "$MARKER" ]; then
        echo "prepare-data-disk: $DATA is not the real data disk, containers stay stopped" >&2
        docker ps -q | xargs -r docker stop
        exit 1
      fi

      systemctl start swapfile.service || echo "prepare-data-disk: swap setup failed" >&2
      sysctl -w vm.swappiness=10

      for id in $ids; do
        docker start "$id" || echo "prepare-data-disk: could not start $id" >&2
      done
      rm -f "$STATE"
      systemctl start dockge.service

runcmd:
  - systemctl daemon-reload
  - systemctl enable mnt-disks-data.mount swapfile.service dockge.service
  - sh /etc/noodle/prepare-data-disk.sh
EOT
}
