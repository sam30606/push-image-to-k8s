# Docker Image Distribution Script for Kubernetes

A comprehensive bash script to save, compress, and distribute Docker images to multiple Kubernetes hosts via SCP and load them into containerd using `ctr`.

## Features

- **Efficient Transfer**: Compresses Docker images with gzip (30-70% size reduction)
- **Multi-User Support**: Works with both root and non-root users with sudo authentication
- **Secure Authentication**: Multiple password handling methods (prompt, environment variable, passwordless sudo)
- **Parallel Distribution**: Transfers images to multiple hosts simultaneously
- **Containerd Integration**: Loads images directly into containerd with proper namespace support
- **Enhanced Verification**: Shows actual image names and sizes after loading
- **Clean Output**: Suppresses SSH warnings and sudo prompts for streamlined execution

## Requirements

- Docker installed on local machine
- SSH access to target Kubernetes hosts
- `ctr` (containerd CLI) installed on target hosts
- `gzip` available on all systems

## Installation

1. Clone or download the script:
   ```bash
   git clone <repository-url>
   cd pushImageTok8s
   ```

2. Make the script executable:
   ```bash
   chmod +x push-image-to-k8s.sh
   ```

## Usage

### Basic Syntax

```bash
./push-image-to-k8s.sh -i <image_name> -h <host1,host2,...> [OPTIONS]
```

### Required Parameters

- `-i <image_name>`: Docker image name (e.g., `nginx:latest`, `myapp:1.0.0`)
- `-h <host1,host2,...>`: Comma-separated list of target hosts

### Optional Parameters

- `-u <ssh_user>`: SSH user (default: `root`)
- `-k <ssh_key>`: SSH private key file path
- `-n <namespace>`: Container namespace (default: `k8s.io`)
- `-P`: Prompt for sudo password (secure, not saved in history)

### Usage Examples

#### 1. Root User (No sudo needed)
```bash
./push-image-to-k8s.sh -i nginx:latest -h 10.0.0.12,10.0.0.13,10.0.0.14
```

#### 2. Non-root User with Password Prompt
```bash
./push-image-to-k8s.sh -i myapp:1.0.0 -u ubuntu -h worker1,worker2,worker3 -P
```

#### 3. Non-root User with Environment Variable
```bash
SUDO_PASSWORD=yourpassword ./push-image-to-k8s.sh -i redis:6.2 -u sam -h 192.168.1.10,192.168.1.11
```

#### 4. Using SSH Key Authentication
```bash
./push-image-to-k8s.sh -i postgres:13 -u admin -k ~/.ssh/k8s_key -h node1.example.com,node2.example.com
```

#### 5. Custom Namespace
```bash
./push-image-to-k8s.sh -i myapp:dev -u ubuntu -h 10.0.0.12 -n custom.namespace -P
```

## How It Works

### Step 1: Image Preparation
1. **Save**: Exports Docker image to uncompressed tar file using `docker save`
2. **Compress**: Compresses tar file with gzip for efficient transfer
3. **Statistics**: Shows original vs compressed size and savings percentage

### Step 2: Distribution
1. **Transfer**: Uses SCP to copy compressed image to `/tmp/` on each target host
2. **Parallel Processing**: Handles multiple hosts simultaneously
3. **Error Handling**: Continues with remaining hosts if one fails

### Step 3: Loading
1. **Decompress**: Extracts tar file on remote host using `gunzip`
2. **Import**: Loads image into containerd using `ctr images import`
3. **Cleanup**: Removes temporary files from remote hosts

### Step 4: Verification
1. **List Images**: Runs `ctr images ls` to verify successful import
2. **Display Results**: Shows actual image name and size
3. **Status Report**: Provides clear success/failure indicators

## Authentication Methods

### 1. Passwordless Sudo (Recommended)
Configure `/etc/sudoers` on target hosts:
```bash
username ALL=(ALL) NOPASSWD:ALL
```

### 2. Password Prompt (Secure)
Use `-P` flag for secure password input:
```bash
./push-image-to-k8s.sh -i myapp:1.0 -u ubuntu -h host1,host2 -P
Enter sudo password for ubuntu: [hidden input]
```

### 3. Environment Variable
Set password before running:
```bash
export SUDO_PASSWORD=yourpassword
./push-image-to-k8s.sh -i myapp:1.0 -u ubuntu -h host1,host2
```

## Output Example

```
Starting image distribution process...
Image: clm-backend:0.1.0
Hosts: 10.0.0.12 10.0.0.13 10.0.0.14
SSH User: sam (using sudo with password for ctr commands)
Namespace: k8s.io

Step 1: Saving Docker image to tar file...
Image saved to clm-backend_0.1.0.tar

Step 2: Compressing tar file...
Image compressed to clm-backend_0.1.0.tar.gz
Compression stats:
  Original: 254M
  Compressed: 178M
  Savings: 30.0%

Step 3: Transferring and loading image on each host...
Processing host: 10.0.0.12
  - Copying clm-backend_0.1.0.tar.gz to 10.0.0.12...
  - Transfer successful
  - Decompressing and loading image into containerd on 10.0.0.12...
  - Image loaded successfully on 10.0.0.12
  - Verifying image on 10.0.0.12...
    ✓ Image found on 10.0.0.12:
      docker.io/library/clm-backend:0.1.0
      Size: 253.2 MiB

Step 4: Cleaning up local compressed file...
Image distribution complete!
```

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   - Verify SSH access: `ssh user@host`
   - Check SSH key permissions: `chmod 600 ~/.ssh/private_key`

2. **Sudo Permission Denied**
   - Configure passwordless sudo or use `-P` flag
   - Verify user has sudo privileges

3. **Image Not Found**
   - Ensure Docker image exists locally: `docker images`
   - Check image name spelling and tags

4. **Containerd Import Failed**
   - Verify `ctr` is installed: `which ctr`
   - Check containerd is running: `systemctl status containerd`

### Manual Verification

To manually verify images on target hosts:
```bash
ssh user@host "sudo ctr -n k8s.io images ls | grep your-image"
```

## Security Considerations

- Never pass passwords as command-line arguments (they appear in shell history)
- Use SSH keys when possible for authentication
- Consider passwordless sudo for automation
- The script suppresses password prompts to prevent credential leakage
