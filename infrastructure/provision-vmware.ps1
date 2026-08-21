# infrastructure/provision-vmware.ps1 - VMware VM Provisioning & Lifecycle Automation
param (
    [string]$Action = "All"  # All | Deploy | Start | Stop | Snapshot | Status
)

$ErrorActionPreference = "Stop"

$ovfTool = "C:\Program Files (x86)\VMware\VMware Workstation\OVFTool\ovftool.exe"
$vmrun   = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
$ovaPath = "C:\Users\ADMIN\Downloads\jammy-server-cloudimg-amd64.ova"
$baseDir = "E:\Virtual Machines"
$pubKeyFile = "$env:USERPROFILE\.ssh\id_ed25519_capstone_mdungtc.pub" # Thay thế pubkey của bạn

$vm1Path = "$baseDir\Ubuntu-VM1-Service\Ubuntu-VM1-Service.vmx"
$vm2Path = "$baseDir\Ubuntu-VM2-Backup\Ubuntu-VM2-Backup.vmx"

function Deploy-VMs {
    if (-not (Test-Path $ovaPath)) {
        Write-Error "Khong tim thay file OVA tai $ovaPath"
        return
    }

    $pubKey = (Get-Content $pubKeyFile -Raw).Trim()

    if (-not (Test-Path $vm1Path)) {
        Write-Host "Dang import VM1 capstone-srv01..." -ForegroundColor Yellow
        $args1 = @(
            "--name=Ubuntu-VM1-Service",
            "--prop:hostname=capstone-srv01",
            "--prop:password=capstone@123",
            "--prop:public-keys=$pubKey",
            $ovaPath,
            "$baseDir\Ubuntu-VM1-Service.vmx"
        )
        & $ovfTool $args1
        (Get-Content $vm1Path) -replace 'ethernet0.connectionType = "bridged"', 'ethernet0.connectionType = "nat"' | Set-Content $vm1Path
    } else {
        Write-Host "VM1 da ton tai tai $vm1Path" -ForegroundColor Green
    }

    if (-not (Test-Path $vm2Path)) {
        Write-Host "Dang import VM2 capstone-backup02..." -ForegroundColor Yellow
        $args2 = @(
            "--name=Ubuntu-VM2-Backup",
            "--prop:hostname=capstone-backup02",
            "--prop:password=capstone@123",
            "--prop:public-keys=$pubKey",
            $ovaPath,
            "$baseDir\Ubuntu-VM2-Backup.vmx"
        )
        & $ovfTool $args2
        (Get-Content $vm2Path) -replace 'ethernet0.connectionType = "bridged"', 'ethernet0.connectionType = "nat"' | Set-Content $vm2Path
    } else {
        Write-Host "VM2 da ton tai tai $vm2Path" -ForegroundColor Green
    }
}

function Start-VMs {
    Write-Host "Dang khoi dong 2 may ao tren VMware Workstation..." -ForegroundColor Yellow
    & $vmrun -T ws start $vm1Path nogui
    & $vmrun -T ws start $vm2Path nogui
}

function Stop-VMs {
    Write-Host "Dang tat 2 may ao..." -ForegroundColor Yellow
    & $vmrun -T ws stop $vm1Path soft
    & $vmrun -T ws stop $vm2Path soft
}

function Snapshot-VMs {
    Write-Host "Dang tao Snapshot ban dau 01-Clean-Baseline..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    & $vmrun -T ws snapshot $vm1Path "01-Clean-Baseline"
    & $vmrun -T ws snapshot $vm2Path "01-Clean-Baseline"
}

function Get-Status {
    Write-Host "=== TRANG THAI MAY AO VMWARE ===" -ForegroundColor Cyan
    & $vmrun -T ws list
}

switch ($Action.ToLower()) {
    "deploy"   { Deploy-VMs }
    "start"    { Start-VMs }
    "stop"     { Stop-VMs }
    "snapshot" { Snapshot-VMs }
    "status"   { Get-Status }
    "all" {
        Deploy-VMs
        Start-VMs
        Snapshot-VMs
        Get-Status
    }
    default {
        Write-Host "Usage: .\provision-vmware.ps1 [-Action All|Deploy|Start|Stop|Snapshot|Status]"
    }
}
