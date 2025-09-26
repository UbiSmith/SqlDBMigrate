#Requires -Version 5.1
<#
.SYNOPSIS
    Exports a SQL database to BACPAC and imports it to a destination server.

.DESCRIPTION
    This script exports a database from a source SQL Server to a BACPAC file,
    then imports it to a destination SQL Server. Supports Azure SQL Database
    with Premium P11 tier configuration.
    
    Version: 1.6.2
    Author: Michael Smith
    Email: michael@mikesmith.xyz
    Copyright: (c) 2024 Michael Smith. All rights reserved.

.NOTES
    This software is licensed under the MIT License.
    
    COMMUNITY REQUEST (not legally binding):
    While not required, we kindly request that:
    - You link back to the original repository
    - You consider contributing improvements back to the community
    - You share your enhancements via pull requests when possible
    
    This helps the community thrive and benefits everyone!
    
    Repository: https://github.com/UbiSmith/SqlDBMigrate

.PARAMETER SourceSQLServer
    The source SQL Server instance name (required).

.PARAMETER SourceDatabase
    The source database name to export (required).

.PARAMETER DestinationSQLServer
    The destination SQL Server instance name (required).

.PARAMETER DestinationDatabase
    The destination database name to create (required).

.PARAMETER FilePath
    Optional directory path for the BACPAC file. Defaults to C:\Temp
    The BACPAC file will be named [DestinationDatabase].bacpac in this directory.

.PARAMETER AllowClobber
    Specifies what to delete/overwrite:
    - None: Reuse existing BACPAC, don't delete destination DB (default)
    - Source: Delete and recreate BACPAC file
    - Destination: Delete destination database if exists
    - Both: Delete both BACPAC and destination database

.PARAMETER SourceSQLType
    Type of source SQL Server:
    - AzureSQL: Azure SQL Database (uses Active Directory Interactive auth)
    - MicrosoftSQL: On-premises SQL Server (uses Windows auth)
    Default: AzureSQL

.PARAMETER DestinationSQLType
    Type of destination SQL Server:
    - AzureSQL: Azure SQL Database (uses Active Directory Interactive auth)
    - MicrosoftSQL: On-premises SQL Server (uses Windows auth)
    Default: AzureSQL

.EXAMPLE
    .\Migrate-SqlDatabase.ps1 -SourceSQLServer "SERVER1" -SourceDatabase "ProdDB" `
        -DestinationSQLServer "SERVER2.database.windows.net" -DestinationDatabase "TestDB"

.EXAMPLE
    .\Migrate-SqlDatabase.ps1 -SourceSQLServer "SERVER1" -SourceDatabase "ProdDB" `
        -DestinationSQLServer "SERVER2" -DestinationDatabase "TestDB" `
        -SourceSQLType "MicrosoftSQL" -DestinationSQLType "MicrosoftSQL" `
        -AllowClobber "Both" -FilePath "D:\Backups"

.EXAMPLE
    .\Migrate-SqlDatabase.ps1 -SourceSQLServer "azure1.database.windows.net" -SourceDatabase "ProdDB" `
        -DestinationSQLServer "azure2.database.windows.net" -DestinationDatabase "TestDB" `
        -SourceSQLType "AzureSQL" -DestinationSQLType "AzureSQL"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceSQLServer,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationSQLServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationDatabase,
    
    [Parameter(Mandatory=$false)]
    [string]$FilePath = "C:\Temp",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("None", "Source", "Destination", "Both")]
    [string]$AllowClobber = "None",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("AzureSQL", "MicrosoftSQL")]
    [string]$SourceSQLType = "AzureSQL",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("AzureSQL", "MicrosoftSQL")]
    [string]$DestinationSQLType = "AzureSQL"
)

# Script configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Initialize timing
$scriptStartTime = Get-Date
$timings = @{}

# Function to format elapsed time
function Format-ElapsedTime {
    param([datetime]$StartTime)
    $elapsed = (Get-Date) - $StartTime
    return "{0:mm}:{0:ss}.{0:fff}" -f $elapsed
}

# Function to log messages with timestamp
function Write-LogMessage {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Type) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        "Start" { "Cyan" }
        "End" { "Cyan" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

# Function to handle errors gracefully
function Handle-Error {
    param(
        [string]$Operation,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    
    Write-LogMessage "ERROR during $Operation" -Type "Error"
    Write-LogMessage "Error Message: $($ErrorRecord.Exception.Message)" -Type "Error"
    
    if ($ErrorRecord.Exception.InnerException) {
        Write-LogMessage "Inner Exception: $($ErrorRecord.Exception.InnerException.Message)" -Type "Error"
    }
    
    Write-LogMessage "Error occurred at line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)" -Type "Error"
    
    # Keep BACPAC file for retry
    if ($bacpacPath -and (Test-Path $bacpacPath)) {
        Write-LogMessage "BACPAC file retained at: $bacpacPath for retry" -Type "Warning"
    }
    
    # Display final timing
    Write-LogMessage "Script failed after: $(Format-ElapsedTime -StartTime $scriptStartTime)" -Type "Error"
    
    exit 1
}

try {
    Write-LogMessage "=== SQL Database Migration Script Started ===" -Type "Start"
    Write-LogMessage "Source: $SourceSQLServer\$SourceDatabase (Type: $SourceSQLType)" -Type "Info"
    Write-LogMessage "Destination: $DestinationSQLServer\$DestinationDatabase (Type: $DestinationSQLType)" -Type "Info"
    Write-LogMessage "Clobber Mode: $AllowClobber" -Type "Info"
    
    # Set BACPAC file path
    # Ensure the directory exists
    if (-not (Test-Path $FilePath)) {
        Write-LogMessage "Creating directory: $FilePath" -Type "Info"
        New-Item -Path $FilePath -ItemType Directory -Force | Out-Null
    }
    
    # Build the full BACPAC file path
    $bacpacPath = Join-Path $FilePath "$DestinationDatabase.bacpac"
    Write-LogMessage "BACPAC file path: $bacpacPath" -Type "Info"
    
    # Check for SqlPackage.exe
    Write-LogMessage "Locating SqlPackage.exe..." -Type "Info"
    
    $sqlPackagePaths = @(
        "${env:ProgramFiles}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe"
    )
    
    $sqlPackage = $null
    foreach ($path in $sqlPackagePaths) {
        if (Test-Path $path) {
            $sqlPackage = $path
            break
        }
    }
    
    if (-not $sqlPackage) {
        throw "SqlPackage.exe not found. Please install SQL Server Data Tools or DAC Framework."
    }
    
    Write-LogMessage "Found SqlPackage.exe at: $sqlPackage" -Type "Success"
    
    # Handle clobber for BACPAC file
    $needsExport = $true
    if (Test-Path $bacpacPath) {
        if ($AllowClobber -eq "Source" -or $AllowClobber -eq "Both") {
            Write-LogMessage "Deleting existing BACPAC file (Clobber mode: $AllowClobber)" -Type "Warning"
            Remove-Item $bacpacPath -Force
        } else {
            Write-LogMessage "Reusing existing BACPAC file: $bacpacPath" -Type "Info"
            $needsExport = $false
        }
    }
    
    # Export database to BACPAC
    if ($needsExport) {
        $exportStartTime = Get-Date
        Write-LogMessage "Starting database export from $SourceSQLType..." -Type "Start"
        
        # Build connection string based on SQL type
        if ($SourceSQLType -eq "AzureSQL") {
            Write-LogMessage "Using Active Directory Interactive authentication for Azure SQL source" -Type "Info"
            $sourceConnectionString = "Server=tcp:$SourceSQLServer,1433;Initial Catalog=$SourceDatabase;Authentication=Active Directory Interactive;Encrypt=True;TrustServerCertificate=False"
        } else {
            Write-LogMessage "Using Windows authentication for Microsoft SQL source" -Type "Info"
            $sourceConnectionString = "Server=$SourceSQLServer;Database=$SourceDatabase;Integrated Security=True;TrustServerCertificate=True"
        }
        
        $exportArgs = @(
            "/Action:Export",
            "/SourceConnectionString:`"$sourceConnectionString`"",
            "/TargetFile:`"$bacpacPath`"",
            "/OverwriteFiles:True"
        )
        
        Write-LogMessage "Executing: $sqlPackage Export (authentication details hidden for security)" -Type "Info"
        Write-Verbose "Connection String: $sourceConnectionString"
        
        $exportProcess = Start-Process -FilePath $sqlPackage -ArgumentList $exportArgs `
            -NoNewWindow -Wait -PassThru
        
        if ($exportProcess.ExitCode -ne 0) {
            throw "Export failed with exit code: $($exportProcess.ExitCode)"
        }
        
        $timings["Export"] = (Get-Date) - $exportStartTime
        Write-LogMessage "Export completed successfully in $(Format-ElapsedTime -StartTime $exportStartTime)" -Type "End"
    } else {
        Write-LogMessage "Skipping export - using existing BACPAC file" -Type "Info"
    }
    
    # Verify BACPAC file exists
    if (-not (Test-Path $bacpacPath)) {
        throw "BACPAC file not found at: $bacpacPath"
    }
    
    $fileInfo = Get-Item $bacpacPath
    Write-LogMessage "BACPAC file size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -Type "Info"
    
    # Handle clobber for destination database
    if ($AllowClobber -eq "Destination" -or $AllowClobber -eq "Both") {
        Write-LogMessage "Checking for existing destination database..." -Type "Info"
        
        try {
            $checkDbScript = @"
IF EXISTS (SELECT name FROM sys.databases WHERE name = '$DestinationDatabase')
BEGIN
    ALTER DATABASE [$DestinationDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$DestinationDatabase];
    SELECT 'Database dropped' AS Result;
END
ELSE
BEGIN
    SELECT 'Database does not exist' AS Result;
END
"@
            
            # Use SqlCmd or Invoke-SqlCmd if available
            if (Get-Command Invoke-SqlCmd -ErrorAction SilentlyContinue) {
                $sqlCmdParams = @{
                    ServerInstance = $DestinationSQLServer
                    Query = $checkDbScript
                    ErrorAction = 'SilentlyContinue'
                }
                
                # Add authentication parameter for Azure SQL
                if ($DestinationSQLType -eq "AzureSQL") {
                    $sqlCmdParams.Add('ConnectionString', "Server=tcp:$DestinationSQLServer,1433;Initial Catalog=master;Authentication=Active Directory Interactive;Encrypt=True;TrustServerCertificate=False")
                }
                
                $result = Invoke-SqlCmd @sqlCmdParams
                Write-LogMessage "Destination database check: $($result.Result)" -Type "Info"
            } else {
                Write-LogMessage "Unable to check destination database. Proceeding with import." -Type "Warning"
            }
        } catch {
            Write-LogMessage "Could not check/drop destination database: $_" -Type "Warning"
        }
    }
    
    # Import BACPAC to destination
    $importStartTime = Get-Date
    Write-LogMessage "Starting database import to $DestinationSQLType..." -Type "Start"
    
    # Build connection string based on SQL type
    if ($DestinationSQLType -eq "AzureSQL") {
        Write-LogMessage "Using Active Directory Interactive authentication for Azure SQL destination" -Type "Info"
        Write-LogMessage "Setting Premium P11 service tier for Azure SQL Database" -Type "Info"
        $destinationConnectionString = "Server=tcp:$DestinationSQLServer,1433;Initial Catalog=$DestinationDatabase;Authentication=Active Directory Interactive;Encrypt=True;TrustServerCertificate=False"
        
        $importArgs = @(
            "/Action:Import",
            "/TargetConnectionString:`"$destinationConnectionString`"",
            "/SourceFile:`"$bacpacPath`"",
            "/Properties:DatabaseServiceObjective=`"P11`""
        )
    } else {
        Write-LogMessage "Using Windows authentication for Microsoft SQL destination" -Type "Info"
        $destinationConnectionString = "Server=$DestinationSQLServer;Database=$DestinationDatabase;Integrated Security=True;TrustServerCertificate=True"
        
        $importArgs = @(
            "/Action:Import",
            "/TargetConnectionString:`"$destinationConnectionString`"",
            "/SourceFile:`"$bacpacPath`""
        )
    }
    
    Write-LogMessage "Executing: $sqlPackage Import (authentication details hidden for security)" -Type "Info"
    Write-Verbose "Connection String: $destinationConnectionString"
    
    $importProcess = Start-Process -FilePath $sqlPackage -ArgumentList $importArgs `
        -NoNewWindow -Wait -PassThru
    
    if ($importProcess.ExitCode -ne 0) {
        throw "Import failed with exit code: $($importProcess.ExitCode)"
    }
    
    $timings["Import"] = (Get-Date) - $importStartTime
    Write-LogMessage "Import completed successfully in $(Format-ElapsedTime -StartTime $importStartTime)" -Type "End"
    
    # Delete temporary BACPAC file on success
    Write-LogMessage "Migration successful - cleaning up temporary files..." -Type "Info"
    if (Test-Path $bacpacPath) {
        Remove-Item $bacpacPath -Force
        Write-LogMessage "Deleted temporary BACPAC file: $bacpacPath" -Type "Success"
    }
    
    # Display summary
    Write-LogMessage "=== Migration Summary ===" -Type "Success"
    Write-LogMessage "Source: $SourceSQLServer\$SourceDatabase (Type: $SourceSQLType)" -Type "Info"
    Write-LogMessage "Destination: $DestinationSQLServer\$DestinationDatabase (Type: $DestinationSQLType)" -Type "Info"
    
    if ($timings.ContainsKey("Export")) {
        Write-LogMessage "Export Time: $(Format-ElapsedTime -StartTime $exportStartTime)" -Type "Info"
    }
    Write-LogMessage "Import Time: $(Format-ElapsedTime -StartTime $importStartTime)" -Type "Info"
    
    $totalTime = (Get-Date) - $scriptStartTime
    Write-LogMessage "Total Execution Time: $(Format-ElapsedTime -StartTime $scriptStartTime)" -Type "Success"
    Write-LogMessage "=== Migration Completed Successfully ===" -Type "Success"
    
} catch {
    Handle-Error -Operation "Database Migration" -ErrorRecord $_
}