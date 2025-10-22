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
        mkdir -p $MOUNT_DIR/mealie-data

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
${var.mealie_subdomain} {
    encode gzip zstd
    reverse_proxy mealie:9000
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
      path        = "/etc/systemd/system/actual-tasks.service"
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
          --name=actual-tasks \
          --env CRON_EXPRESSION="${var.actual_tasks_config.cron_expression}" \
          --env ACTUAL_SERVER_URL=${var.actual_tasks_config.actual.server_url} \
          --env ACTUAL_SERVER_PASSWORD="${var.actual_tasks_config.actual.server_password}" \
          --env ACTUAL_SYNC_ID="${var.actual_tasks_config.actual.sync_id}" \
          --env ACTUAL_FILE_PASSWORD="${var.actual_tasks_config.actual.file_password}" \
          --env ENABLE_PAYEE_RENAME=${var.actual_tasks_config.features.payee_rename.is_enabled} \
          --env PAYEE_REGEX_MATCH="${var.actual_tasks_config.features.payee_rename.regex_match}" \
          --env ENABLE_INTEREST_CALCULATION=${var.actual_tasks_config.features.interest_calculation.is_enabled} \
          --env ENABLE_GHOSTFOLIO_SYNC=${var.actual_tasks_config.features.ghostfolio.is_enabled} \
          --env ENABLE_HOLD_INCOME_FOR_NEXT_MONTH=${var.actual_tasks_config.features.hold_income_for_next_month.is_enabled} \
          --env ENABLE_BANK_SYNC=${var.actual_tasks_config.features.bank_sync.is_enabled} \
          rodriguestiago0/actualtasks:${var.actual_tasks_image_version_tag}

        ExecStop=/usr/bin/docker stop actual-tasks
        ExecStopPost=/usr/bin/docker rm actual-tasks
        Restart=unless-stopped
        TimeoutStartSec=0
        TimeoutStopSec=5

        [Install]
        WantedBy=multi-user.target
        EOT5
    },
    {
      path        = "/etc/systemd/system/actual-auto-sync.service"
      permissions = "0644"
      owner       = "root"
      content     = <<-EOT6
        [Unit]
        Description=Start Actual Auto Sync
        After=network-online.target docker.service actual.service
        Requires=docker.service actual.service
        RequiresMountsFor=/mnt/disks/data

        [Service]    
        ExecStart=/usr/bin/docker run --rm \
          --network custom-bridge \
          --name=actual-auto-sync \
          --env ACTUAL_SERVER_URL="${var.actual_auto_sync_config.server_url}" \
          --env ACTUAL_SERVER_PASSWORD="${var.actual_auto_sync_config.server_password}" \
          --env ACTUAL_BUDGET_SYNC_IDS="${var.actual_auto_sync_config.sync_ids}" \
          --env ENCRYPTION_PASSWORDS="${var.actual_auto_sync_config.file_passwords}" \
          --env CRON_SCHEDULE="${var.actual_auto_sync_config.cron_schedule}" \
          --env LOG_LEVEL="${var.actual_auto_sync_config.log_level}" \
          --env RUN_ON_START="${var.actual_auto_sync_config.run_on_start}" \
          seriouslag/actual-auto-sync:${var.actual_auto_sync_image_version_tag}

        ExecStop=/usr/bin/docker stop actual-auto-sync
        ExecStopPost=/usr/bin/docker rm actual-auto-sync
        Restart=unless-stopped
        TimeoutStartSec=0
        TimeoutStopSec=5

        [Install]
        WantedBy=multi-user.target
        EOT6
    },
    {
      path        = "/etc/systemd/system/mealie.service"
      permissions = "0644"
      owner       = "root"
      content     = <<-EOT7
        [Unit]
        Description=Start Mealie
        After=network-online.target docker.service caddy.service
        Requires=docker.service caddy.service
        RequiresMountsFor=/mnt/disks/data

        [Service]
        ExecStart=/usr/bin/docker run --rm \
          --network custom-bridge \
          --mount 'type=bind,source=/mnt/disks/data/mealie-data,target=/app/data' \
          --name=mealie \
          -e TZ="${var.mealie_config.timezone}" \
          -e BASE_URL="${var.mealie_config.base_url}" \
          ghcr.io/mealie-recipes/mealie:${var.mealie_image_version_tag}

        ExecStop=/usr/bin/docker stop mealie
        ExecStopPost=/usr/bin/docker rm mealie
        Restart=unless-stopped
        TimeoutStartSec=0
        TimeoutStopSec=5

        [Install]
        WantedBy=multi-user.target
        EOT7
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
    "systemctl enable mealie.service",
    "systemctl enable actual-auto-sync.service",
    "systemctl enable actual-tasks.service",
    "systemctl start caddy.service",
    "systemctl start actual.service",
    "systemctl start mealie.service",
    "systemctl start actual-auto-sync.service",
    "systemctl start actual-tasks.service"
  ]
})}
  EOT
}
