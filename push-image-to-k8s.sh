#!/bin/bash

set -e

IMAGE_NAME=""
HOSTS=()
SSH_USER="root"
SSH_KEY=""
NAMESPACE="k8s.io"
SUDO_PASSWORD=""
PROMPT_PASSWORD=false

usage() {
    echo "Usage: $0 -i <image_name> -h <host1,host2,...> [-u <ssh_user>] [-k <ssh_key>] [-n <namespace>] [-P]"
    echo "  -i: Docker image name (required)"
    echo "  -h: Comma-separated list of hosts (required)"
    echo "  -u: SSH user (default: root)"
    echo "  -k: SSH private key file path"
    echo "  -n: Container namespace (default: k8s.io)"
    echo "  -P: Prompt for sudo password (secure, not saved in history)"
    echo "Example: $0 -i nginx:latest -h node1,node2,node3 -u ubuntu -k ~/.ssh/id_rsa -P"
    echo "Alternative: Set SUDO_PASSWORD environment variable"
    echo "Note: For passwordless sudo, configure /etc/sudoers with: username ALL=(ALL) NOPASSWD:ALL"
    exit 1
}

while getopts "i:h:u:k:n:P" opt; do
    case $opt in
        i) IMAGE_NAME="$OPTARG";;
        h) IFS=',' read -ra HOSTS <<< "$OPTARG";;
        u) SSH_USER="$OPTARG";;
        k) SSH_KEY="$OPTARG";;
        n) NAMESPACE="$OPTARG";;
        P) PROMPT_PASSWORD=true;;
        *) usage;;
    esac
done

if [[ -z "$IMAGE_NAME" || ${#HOSTS[@]} -eq 0 ]]; then
    usage
fi

# Handle sudo password for non-root users
if [[ "$SSH_USER" != "root" ]]; then
    if [[ "$PROMPT_PASSWORD" == true ]]; then
        echo -n "Enter sudo password for $SSH_USER: "
        read -s SUDO_PASSWORD
        echo
    fi
    # SUDO_PASSWORD might be set via environment variable - keep it as is
fi

SAFE_IMAGE_NAME=$(echo "$IMAGE_NAME" | sed 's/[^a-zA-Z0-9._-]/_/g')
TAR_FILE="${SAFE_IMAGE_NAME}.tar"
COMPRESSED_FILE="${SAFE_IMAGE_NAME}.tar.gz"

echo "Starting image distribution process..."
echo "Image: $IMAGE_NAME"
echo "Hosts: ${HOSTS[*]}"
if [[ "$SSH_USER" == "root" ]]; then
    SUDO_CMD=""
    echo "SSH User: $SSH_USER (no sudo needed)"
else
    if [[ -n "$SUDO_PASSWORD" ]]; then
        SUDO_CMD="echo '$SUDO_PASSWORD' | sudo -S "
        echo "SSH User: $SSH_USER (using sudo with password for ctr commands)"
    else
        SUDO_CMD="sudo "
        echo "SSH User: $SSH_USER (using passwordless sudo for ctr commands)"
    fi
fi

# Store password status for verification
if [[ -n "$SUDO_PASSWORD" ]]; then
    SUDO_WITH_PASSWORD=true
    STORED_PASSWORD="$SUDO_PASSWORD"
    unset SUDO_PASSWORD
else
    SUDO_WITH_PASSWORD=false
    STORED_PASSWORD=""
fi
echo "Namespace: $NAMESPACE"

echo "Step 1: Saving Docker image to tar file..."
docker save -o "$TAR_FILE" "$IMAGE_NAME"
echo "Image saved to $TAR_FILE"

echo "Step 2: Compressing tar file..."
gzip "$TAR_FILE"
echo "Image compressed to $COMPRESSED_FILE"

echo "Compression stats:"
if [[ -f "$COMPRESSED_FILE" ]]; then
    ORIGINAL_SIZE=$(docker save "$IMAGE_NAME" | wc -c)
    COMPRESSED_SIZE=$(stat -c%s "$COMPRESSED_FILE")
    SAVINGS=$(echo "scale=1; (1 - $COMPRESSED_SIZE/$ORIGINAL_SIZE) * 100" | bc -l 2>/dev/null || echo "N/A")
    echo "  Original: $(numfmt --to=iec $ORIGINAL_SIZE)"
    echo "  Compressed: $(numfmt --to=iec $COMPRESSED_SIZE)"
    echo "  Savings: ${SAVINGS}%"
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

echo "Step 3: Transferring and loading image on each host..."
for host in "${HOSTS[@]}"; do
    echo "Processing host: $host"
    
    echo "  - Copying $COMPRESSED_FILE to $host..."
    if scp $SSH_OPTS "$COMPRESSED_FILE" "$SSH_USER@$host:/tmp/"; then
        echo "  - Transfer successful"
    else
        echo "  - Transfer failed for $host, skipping..."
        continue
    fi
    
    echo "  - Decompressing and loading image into containerd on $host..."
    if [[ "$SSH_USER" != "root" && "$SUDO_WITH_PASSWORD" == "true" ]]; then
        if ssh $SSH_OPTS "$SSH_USER@$host" "gunzip /tmp/$COMPRESSED_FILE && echo '$STORED_PASSWORD' | sudo -S ctr -n $NAMESPACE images import /tmp/${TAR_FILE} 2>/dev/null && rm /tmp/${TAR_FILE}"; then
            echo "  - Image loaded successfully on $host"
        else
            echo "  - Failed to load image on $host"
        fi
    else
        if ssh $SSH_OPTS "$SSH_USER@$host" "gunzip /tmp/$COMPRESSED_FILE && ${SUDO_CMD}ctr -n $NAMESPACE images import /tmp/${TAR_FILE} 2>/dev/null && rm /tmp/${TAR_FILE}"; then
            echo "  - Image loaded successfully on $host"
        else
            echo "  - Failed to load image on $host"
        fi
    fi
    
    echo "  - Verifying image on $host..."
    if [[ "$SSH_USER" != "root" && "$SUDO_WITH_PASSWORD" == "true" ]]; then
        VERIFICATION_RESULT=$(ssh $SSH_OPTS "$SSH_USER@$host" "echo '$STORED_PASSWORD' | sudo -S ctr -n $NAMESPACE images ls 2>/dev/null | grep '$IMAGE_NAME'" || echo "")
    else
        VERIFICATION_RESULT=$(ssh $SSH_OPTS "$SSH_USER@$host" "${SUDO_CMD}ctr -n $NAMESPACE images ls 2>/dev/null | grep '$IMAGE_NAME'" || echo "")
    fi
    
    if [[ -n "$VERIFICATION_RESULT" ]]; then
        echo "    ✓ Image found on $host:"
        echo "      $(echo "$VERIFICATION_RESULT" | head -1 | awk '{print $1}')"
        echo "      Size: $(echo "$VERIFICATION_RESULT" | head -1 | awk '{print $4" "$5}')"
    else
        echo "    ✗ Image verification failed on $host"
    fi
done

echo "Step 4: Cleaning up local compressed file..."
rm -f "$COMPRESSED_FILE"

echo "Image distribution complete!"
echo "To verify images on all hosts, run:"
echo "  ${SUDO_CMD}ctr -n $NAMESPACE images ls | grep $IMAGE_NAME"