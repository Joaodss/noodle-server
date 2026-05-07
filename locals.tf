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
      After=systemd-udev-settle.service
      Wants=systemd-udev-settle.service

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

runcmd:
  - systemctl daemon-reload
  - mkdir -p /mnt/disks/data
  - systemctl enable mnt-disks-data.mount
  - systemctl start mnt-disks-data.mount
  - systemctl restart docker
  - systemctl enable dockge.service
  - systemctl start dockge.service
EOT
}
