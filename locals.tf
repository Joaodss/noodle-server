locals {
  cloud_config = <<-EOT
#cloud-config

write_files:
  - path: /etc/systemd/system/format-data-disk.service
    permissions: "0644"
    owner: root
    content: |
      [Unit]
      Description=Format persistent data disk only if it has no filesystem
      Requires=dev-disk-by\x2did-google\x2dcontainer_host_data_disk_0.device
      After=dev-disk-by\x2did-google\x2dcontainer_host_data_disk_0.device
      Before=mnt-disks-data.mount

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      # blkid -p exits 2 only when the device has no recognisable signature;
      # any other result (filesystem found, read error) leaves the disk alone.
      ExecStart=/bin/sh -c 'd=/dev/disk/by-id/google-container_host_data_disk_0; blkid -p "$d" >/dev/null 2>&1; rc=$?; if [ "$rc" -eq 2 ]; then mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "$d"; fi'

  - path: /etc/systemd/system/mnt-disks-data.mount
    permissions: "0644"
    owner: root
    content: |
      [Unit]
      Description=Persistent data disk
      Requires=format-data-disk.service
      After=format-data-disk.service

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
      ExecStart=/bin/sh -c 'f=/mnt/disks/data/swapfile; [ -f "$f" ] || { fallocate -l 1G "$f" && chmod 600 "$f" && mkswap "$f"; }; swapon "$f"'
      ExecStop=/bin/sh -c 'swapoff /mnt/disks/data/swapfile'

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl stop docker.socket docker.service
  - systemctl daemon-reload
  - mkdir -p /mnt/disks/data
  - systemctl enable mnt-disks-data.mount
  - systemctl start mnt-disks-data.mount
  - systemctl enable --now swapfile.service
  - sysctl -w vm.swappiness=10
  - systemctl start docker.service
  # Docker on COS runs with live-restore, so containers started before the
  # data disk was mounted keep the empty placeholder dir. Restart them all.
  - sh -c 'docker ps -q | xargs -r docker restart'
  - systemctl enable dockge.service
  - systemctl start dockge.service
EOT
}
