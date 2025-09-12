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

        echo "Adding disk to fstab..."
        echo "$DATA_DISK $MOUNT_DIR ext4 discard,defaults,nofail 0 2" >> /etc/fstab

        echo "Mounting disk..."
        mount -a

        echo "Creating required directories..."
        mkdir -p $MOUNT_DIR/caddy/data
        mkdir -p $MOUNT_DIR/caddy/config
        mkdir -p $MOUNT_DIR/actual-data

        echo "Setting permissions..."
        chown -R root:root $MOUNT_DIR
        chmod -R 755 $MOUNT_DIR
        EOT1
    },
    {
      path        = "/var/lib/cloud/scripts/per-instance/setup-caddy.sh"
      permissions = "0544"
      owner       = "root"
      content     = <<-EOT2
        #!/bin/bash
        set -e
        
        echo "Updating Caddyfile configuration..."
        cat > "/mnt/disks/data/caddy/Caddyfile" << ENDCADDY
{
    acme_dns cloudflare ${var.cloudflare_api_token}
}
${var.actual_subdomain} {
    encode gzip zstd
    reverse_proxy actual_server:5006
    tls {
        dns cloudflare ${var.cloudflare_api_token}
    }
}
ENDCADDY
        chmod 644 "/mnt/disks/data/caddy/Caddyfile"
        echo "Caddyfile updated successfully"
        EOT2
    },
    {
      path        = "/etc/systemd/system/caddy.service"
      permissions = "0644"
      owner       = "root"
      content     = <<-EOT3
        [Unit]
        Description=Start Caddy
        After=network-online.target docker.service
        Requires=docker.service
        RequiresMountsFor=/mnt/disks/data

        [Service]
        Environment=CLOUDFLARE_API_TOKEN=${var.cloudflare_api_token}
        ExecStartPre=/bin/sh -c 'until [ -f /mnt/disks/data/caddy/Caddyfile ]; do sleep 1; done'
        ExecStart=/usr/bin/docker run --rm \
          --network custom-bridge \
          -p 80:80 -p 443:443 -p 443:443/udp \
          --mount 'type=bind,source=/mnt/disks/data/caddy/Caddyfile,target=/etc/caddy/Caddyfile,readonly' \
          --mount 'type=bind,source=/mnt/disks/data/caddy/data,target=/data' \
          --mount 'type=bind,source=/mnt/disks/data/caddy/config,target=/config' \
          --name=caddy \
          caddybuilds/caddy-cloudflare:alpine
        ExecStop=/usr/bin/docker stop caddy
        ExecStopPost=/usr/bin/docker rm caddy
        Restart=unless-stopped
        TimeoutStartSec=0
        TimeoutStopSec=5

        [Install]
        WantedBy=multi-user.target
        EOT3
    },
    {
      path        = "/etc/systemd/system/actual.service"
      permissions = "0644"
      owner       = "root"
      content     = <<-EOT4
        [Unit]
        Description=Start Actual Server
        After=network-online.target docker.service caddy.service
        Requires=docker.service caddy.service
        RequiresMountsFor=/mnt/disks/data

        [Service]
        ExecStart=/usr/bin/docker run --rm \
          --network custom-bridge \
          --mount 'type=bind,source=/mnt/disks/data/actual-data,target=/data' \
          --name=actual_server \
          actualbudget/actual-server:${var.actual_server_image_version_tag}
        ExecStop=/usr/bin/docker stop actual_server
        ExecStopPost=/usr/bin/docker rm actual_server
        Restart=unless-stopped
        TimeoutStartSec=0
        TimeoutStopSec=5

        [Install]
        WantedBy=multi-user.target
        EOT4
    },
    {
      path        = "/etc/systemd/system/actualtasks.service"
      permissions = "0644"
      owner       = "root"
      content     = <<-EOT5
        [Unit]
        Description=Start Actual Tasks
        After=network-online.target docker.service actual.service
        Requires=docker.service actual.service
        RequiresMountsFor=/mnt/disks/data

        [Service]    
        ExecStart=/usr/bin/docker run --rm \
          --network custom-bridge \
          --name=actualtasks \
          -e CRON_EXPRESSION="${var.actual_tasks_config.cron_expression}" \
          -e ACTUAL_SERVER_URL="${var.actual_tasks_config.actual.server_url}" \
          -e ACTUAL_SERVER_PASSWORD="${var.actual_tasks_config.actual.server_password}" \
          -e ACTUAL_SYNC_ID="${var.actual_tasks_config.actual.sync_id}" \
          -e ACTUAL_FILE_PASSWORD="${var.actual_tasks_config.actual.file_password}" \
          -e ENABLE_PAYEE_RENAME=${var.actual_tasks_config.features.payee_rename.is_enabled} \
          -e PAYEE_REGEX_MATCH="${var.actual_tasks_config.features.payee_rename.regex_match}" \
          -e ENABLE_INTEREST_CALCULATION=${var.actual_tasks_config.features.interest_calculation.is_enabled} \
          -e ENABLE_GHOSTFOLIO_SYNC=${var.actual_tasks_config.features.ghostfolio.is_enabled} \
          -e ENABLE_HOLD_INCOME_FOR_NEXT_MONTH=${var.actual_tasks_config.features.hold_income_for_next_month.is_enabled} \
          -e ENABLE_BANK_SYNC=${var.actual_tasks_config.features.bank_sync.is_enabled} \
          rodriguestiago0/actualtasks:${var.actual_tasks_image_version_tag}

        ExecStop=/usr/bin/docker stop actualtasks
        ExecStopPost=/usr/bin/docker rm actualtasks
        Restart=unless-stopped
        TimeoutStartSec=0
        TimeoutStopSec=5

        [Install]
        WantedBy=multi-user.target
        EOT5
    }
  ]

  bootcmd = [
    "bash /var/lib/cloud/scripts/per-instance/fs-prepare.sh"
  ]

  runcmd = [
    "while ! mountpoint -q /mnt/disks/data; do sleep 1; done",
    "bash /var/lib/cloud/scripts/per-instance/setup-caddy.sh",
    "docker network create custom-bridge || true",
    "systemctl daemon-reload",
    "systemctl enable caddy.service",
    "systemctl enable actual.service",
    "systemctl enable actualtasks.service",
    "systemctl start caddy.service",
    "systemctl start actual.service",
    "systemctl start actualtasks.service"
  ]
})}
  EOT
}
