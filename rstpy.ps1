  # Prompt for root password
$rootPassword = Read-Host -AsSecureString "Enter Lab Default password"
$rootPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootPassword))
  
# Define variables
$sshFolder = "$env:USERPROFILE\.ssh"
$keyName = "id_ecdsa"
$centosHosts = @("centos1", "centos2")
$remoteUser = "root"
$clusters = @("cluster1")  
# Ensure .ssh directory exists
if (-Not (Test-Path -Path $sshFolder)) {
    New-Item -ItemType Directory -Path $sshFolder
}
  
# Generate SSH key
if (-Not (Test-Path -Path $sshFolder\$keyName)){
ssh-keygen -t ecdsa -f "$sshFolder\$keyName" -N '""' -q
}

# Copy public key to authorized_keys
$pubKey = Get-Content "$sshFolder\$keyName.pub"
$authKeysPath = "$sshFolder\authorized_keys"
if (-Not (Test-Path -Path $authKeysPath)) {
    New-Item -ItemType File -Path $authKeysPath
}
Add-Content -Path $authKeysPath -Value $pubKey
  
# Save password to a temporary file
$temp_pw_file = [System.IO.Path]::GetTempFileName()
Set-Content -Path $temp_pw_file -Value $rootPasswordPlain
  
# Copy .ssh folder to CentOS machines and set permissions
foreach ($centosHost in $centosHosts) {
    plink -batch -pwfile $temp_pw_file ${remoteUser}@${centosHost} "mkdir -p ~/.ssh"
    pscp -pwfile $temp_pw_file -r $sshFolder ${remoteUser}@${centosHost}:
    plink -batch -pwfile $temp_pw_file ${remoteUser}@${centosHost} "chmod 700 ~/.ssh; chmod 600 ~/.ssh/id_ecdsa; chmod 600 ~/.ssh/authorized_keys"
}
  
$knownHostsPath = "$env:USERPROFILE\.ssh\known_hosts"
  
foreach ($centosHost in $centosHosts) {
    ssh-keyscan -H $centosHost | Out-File -Append -Encoding ascii $knownHostsPath
}
  
  
# Create Bash script for ONTAP configuration
$bashScript = @'
#!/bin/bash
  
# Define ONTAP clusters and Vserver names
ONTAP_CLUSTERS=("cluster1")
VSERVER_NAMES=("cluster1")
  
# Credentials and key
ONTAP_USER="admin"
ONTAP_PASS=$(<./ontap_admin_password.txt)
KEY_FILE="$HOME/.ssh/id_ecdsa.pub"
  
# Function to copy SSH key to ONTAP using CLI
copy_ssh_key_ontap() {
  
    local user=$1
  
    local pass=$2
  
    local host=$3
  
    local vserver=$4
  
    local key_file=$5
  
    local public_key=$(cat $key_file)
  
    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "security login create -vserver $vserver -user-or-group-name $user -application ssh -authentication-method publickey -role admin ; security login publickey create -vserver $vserver -username $user -publickey \"$public_key\""
  
}
  
  
  
  
# Loop through clusters and apply the key
for i in "${!ONTAP_CLUSTERS[@]}"; do
    copy_ssh_key_ontap "$ONTAP_USER" "$ONTAP_PASS" "${ONTAP_CLUSTERS[$i]}" "${VSERVER_NAMES[$i]}" "$KEY_FILE"
done
  
# Directory containing repo files
REPO_DIR="/etc/yum.repos.d"
  
# Loop through all .repo files
for file in "$REPO_DIR"/*.repo; do
    if grep -q "^failovermethod=" "$file"; then
        echo "Updating $file..."
        # Comment out all lines starting with 'failovermethod='
        sed -i 's/^failovermethod=/# failovermethod=/' "$file"
    fi
done
echo "All applicable 'failovermethod' lines have been commented out."
echo "Checking CentOS version..."
if ! grep -q "CentOS Linux release 8" /etc/redhat-release; then
    echo " This script is intended for CentOS 8.x only."
    exit 1
fi
  
echo "Installing Python 3.9 from AppStream..."
sudo dnf module enable -y python39
sudo dnf install -y python39 python39-devel python39-pip
  
echo "Updating alternatives to make Python 3.9 the default..."
  
# Register python3.9 with alternatives
sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 100
sudo alternatives --set python3 /usr/bin/python3.9
  
# Optional: also set 'python' to point to python3.9
sudo alternatives --install /usr/bin/python python /usr/bin/python3.9 100
sudo alternatives --set python /usr/bin/python3.9
  
echo "Disabling custom Python 3.11 in /usr/local/bin..."
  
# Rename or remove custom Python 3.11 binaries
for bin in /usr/local/bin/python3.11 /usr/local/bin/python3.11-config; do
    if [ -f "$bin" ]; then
        sudo mv "$bin" "${bin}.disabled"
        echo "Disabled $bin"
    fi
done
  
# Remove broken symlink
if [ -L /usr/local/bin/python3 ]; then
  sudo rm -f /usr/local/bin/python3
  echo "Removed broken symlink /usr/local/bin/python3"
fi
  
  
echo "Python version now set to:"
which python3
python3 --version
  
  
  
'@
  
# Save Bash script to a file
$bashScriptPath = "$env:TEMP\setup_ontap.sh"
Set-Content -Path "$bashScriptPath" -Value "$bashScript"
  
# Copy and execute the Bash script on centos1
scp $bashScriptPath ${remoteUser}@centos1:~/setup_ontap.sh
scp $temp_pw_file ${remoteUser}@centos1:~/ontap_admin_password.txt
ssh ${remoteUser}@centos1 "dos2unix ~/setup_ontap.sh"
ssh ${remoteUser}@centos1 "dos2unix ~/ontap_admin_password.txt"
ssh ${remoteUser}@centos1 "chmod +x ~/setup_ontap.sh"
ssh ${remoteUser}@centos1 "~/setup_ontap.sh"
ssh ${remoteUser}@centos1 "rm -f ~/setup_ontap.sh"
ssh ${remoteUser}@centos1 "rm -f ~/ontap_admin_password.txt"
  
$knownHostsPath = "$env:USERPROFILE\.ssh\known_hosts"
  
foreach ($cluster in $clusters) {
    ssh-keyscan -H $cluster | Out-File -Append -Encoding ascii $knownHostsPath
}
  
# Copy .ssh/known_hosts to CentOS machines
foreach ($centosHost in $centosHosts) {
    scp  $sshFolder\known_hosts ${remoteUser}@${centosHost}:~/.ssh/
    
}
  
# Clean up temporary password file
Remove-Item -Path $temp_pw_file
Remove-Item -Path $bashScriptPath

# Define paths
$installerPath = "$env:TEMP\vscode.exe"
$codeCmd = "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd"
  
# Check if VS Code is already installed
if (-Not (Test-Path $codeCmd)) {
    Write-Host "VS Code not found. Downloading and installing..."
  
    # Download VS Code installer
    Invoke-WebRequest -Uri "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user" -OutFile $installerPath
  
    # Install VS Code silently without launching it after installation
    Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /MERGETASKS=!runcode" -Wait
  
    # Wait until the CLI becomes available
    while (-not (Test-Path $codeCmd)) {
        Start-Sleep -Seconds 2
    }
  
    Write-Host "VS Code installed successfully."
} else {
    Write-Host "VS Code is already installed. Skipping download and installation."
}
  
# Download VSIX for Remote SSH extension
$remoteSshVsixPath = "$env:TEMP\remote-ssh.vsix"
Invoke-WebRequest -Uri "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-ssh/latest/vspackage" -OutFile $remoteSshVsixPath
  
# Install the Remote SSH extension
& $codeCmd --install-extension $remoteSshVsixPath
 

