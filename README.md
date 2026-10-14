# Morpheus Appliance Deployment with Terraform

## What this does

Morpheus is a cloud management platform that runs as a single server ("appliance"). Setting one up by hand means creating a VM, installing a package, running a configuration step, waiting for the web UI, then clicking through a first-time setup wizard and pasting a licence key. This repo turns all of that into one button.

It uses a Morpheus appliance you already have as the engine. That appliance talks to VMware, creates the new VM, and once the VM boots, runs a script on it that installs and configures a brand-new Morpheus. About 30 minutes later you get a URL and a login for a working, licensed appliance.

Technically it is a Terraform configuration using the `HPE/hpe` provider, packaged as a Morpheus App Blueprint. You pick a version and a name in a form, press Provision, and the existing appliance does the rest.

Secrets (API token, admin password, licence key) are stored in Morpheus Cypher, Morpheus's built-in secret store, and are never written into the blueprint, the task or the logs.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Data sources, Cypher secrets, shell task, workflow, instance, outputs |
| `morpheus-install.sh` | Install script, rendered with `templatefile()`, runs post-provision as root |
| `variables.tf` | Inputs shown in the App form |
| `locals.tf` | Environment settings (cloud, pool, network, plan, datastore, timeouts) |
| `provider.tf` | Provider versions |
| `terraform.tfvars.example` | Template for the tfvar secret |

## Prerequisites

- Terraform >= 1.11 or OpenTofu >= 1.13 (provider 2.x requirement). On the source appliance set Administration > Settings > Provisioning > Terraform Runtime = `auto` and Default Terraform Version = `1.14.5` (or any installed >= 1.11). Leave the blueprint VERSION field empty and do not add `required_version`: any constraint makes Morpheus cap the runtime at 1.5.5.
- API token on the source appliance with rights to create instances, tasks, workflows and Cypher secrets. Set its validity to at least 3600 s (default 1440) so long provisions don't lose auth.
- Source appliance URL with a trusted certificate (TLS verification is always on)
- New VM needs outbound HTTPS to `downloads.morpheusdata.com`, or point `download_base_url` in `locals.tf` at a mirror
- License key is optional; empty `licenseKey` skips activation

## Deploy via App Blueprint

1. Create a Cypher secret of type tfvars (e.g. `tfvars/morpheus_tf_app`):

   ```hcl
   morpheus_url = "https://morpheus.example.com"
   access_token = "..."
   username     = "..."
   password     = "..."
   licenseKey   = "..."
   ```

2. Create a Terraform App Blueprint: Config Type `Git Repository`, this repo, working path `./`, the branch to use, TFVAR SECRET = the secret above.
3. Provision the app. The form shows only `morph_version` and `appliance_name` beyond the secret values.

Outputs on the app's Terraform tab: `appliance_url`, `admin_username`, `instance_name`, `instance_id`. The password is the one from the secret.

Placement and installer settings live in `locals.tf`. For another environment, edit them on a branch and point the blueprint at it.

## Deploy from a workstation

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in
terraform init && terraform apply
terraform output appliance_url
```

## How it works

1. Look up cloud, group, resource pool, network, plan and Ubuntu layout on the source appliance.
2. Store the password and licence key as Cypher secrets. The install script reads them at run time, so they never appear in the task body or history.
3. Create a shell task and a provisioning workflow that runs `morpheus-install.sh` after the VM boots.
4. Provision the instance with that workflow attached. Names use a stable random suffix, so re-applying doesn't recreate everything.

Note: the app's Resources tab stays empty. Morpheus only maps resources from the AWS, Azure, Google, vSphere and OpenStack providers; it has no mapper for its own. The State tab and outputs work as normal.

## Install script

`morpheus-install.sh` is designed to fail loudly and retry safely:

- Exits non-zero on any unrecoverable step, so the task fails and its retries (2, 60 s apart) kick in
- Idempotent: skips package install and `/api/setup` if already done
- Disables `apt-daily` timers, waits for dpkg/apt locks (15 min cap), removes `unattended-upgrades`
- Downloads with `curl` retries/resume and verifies the `.deb` before `dpkg -i`
- Edits `appliance_url` in `morpheus.rb` in place (backup at `morpheus.rb.orig`)
- Polls `GET /api/setup/check` until the UI answers, with a real timeout (`ui_timeout_minutes`, default 25)
- Builds JSON with Python so special characters in passwords are safe; logs HTTP codes on failure
- Never prints the API token; log is `chmod 600`
- Provisioning-settings and user-settings updates are warnings, not failures

## Troubleshooting

Easiest: open the new instance in the source appliance, Monitoring > Logs, search `morph-install`. The script mirrors every step there.

On the new VM:

```bash
sudo tail -f /tmp/morph_install_log.txt
```

If the UI never comes up, the last 50 lines of `/var/log/morpheus/morpheus-ui/current` are appended to that log. The task output in the source appliance (Instance > History) shows the same messages minus secrets.

| Symptom | Likely cause |
|---------|--------------|
| UI timeout | VM under-sized (16 GB RAM minimum) or slow datastore. Raise `ui_timeout_minutes`. |
| Download failed | Wrong `morph_version` (must match `x.y.z-N` exactly) or no internet from the VM |
| Setup failed | Password doesn't meet complexity rules |

Instance `create` timeout is 90 minutes to cover provisioning plus install.

## Disclaimer

Provided as-is, without warranty or official Morpheus support. You own any consequences of using it.
