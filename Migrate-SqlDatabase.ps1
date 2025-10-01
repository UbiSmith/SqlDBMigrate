#Requires -Version 5.1
<#
.SYNOPSIS
    Exports a SQL database to BACPAC and imports it to a destination server.

.DESCRIPTION
    This script exports a database from a source SQL Server to a BACPAC file,
    then imports it to a destination SQL Server. Supports Azure SQL Database
    with Premium P11 tier configuration.
    
    Version: 1.8.0
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

.PARAMETER TempDirectory
    Optional temporary directory for SqlPackage to use during export operations.
    If not specified, SqlPackage uses the system default temp directory.
    Useful when exporting large databases and the default temp location has insufficient space.
    Note: This parameter only applies to the export process.

.PARAMETER EnableDiagnostics
    Enables verbose diagnostic output from SqlPackage.
    When enabled, SqlPackage will output detailed diagnostic information including:
    - Detailed progress messages
    - SQL statements being executed
    - Timing information for each operation
    - Detailed error information if failures occur
    This is useful for troubleshooting issues with exports or imports.

.PARAMETER CompressionType
    Specifies the compression type for the BACPAC file.
    Valid options are:
    - Fast: Optimizes for speed over compression ratio (default)
    - Optimal: Balances compression ratio and speed
    - Maximum: Best compression ratio but slower
    - NoCompression: No compression applied
    Default: Fast

.PARAMETER LoggingDatabase
    Connection string for a SQL database to log timing information.
    If provided, migration timings will be recorded in the database.
    The table MigrationTimings will be created if it doesn't exist.
    Example: "Server=LogServer;Database=MigrationLogs;Integrated Security=True"

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

.EXAMPLE
    .\Migrate-SqlDatabase.ps1 -SourceSQLServer "SQLSERVER01" -SourceDatabase "LargeDB" `
        -DestinationSQLServer "azureserver.database.windows.net" -DestinationDatabase "LargeDB" `
        -SourceSQLType "MicrosoftSQL" -DestinationSQLType "AzureSQL" `
        -TempDirectory "E:\SQLTemp" -FilePath "D:\Backups"

.EXAMPLE
    .\Migrate-SqlDatabase.ps1 -SourceSQLServer "SQLSERVER01" -SourceDatabase "ProblemDB" `
        -DestinationSQLServer "SQLSERVER02" -DestinationDatabase "TestDB" `
        -SourceSQLType "MicrosoftSQL" -DestinationSQLType "MicrosoftSQL" `
        -EnableDiagnostics -Verbose

.EXAMPLE
    .\Migrate-SqlDatabase.ps1 -SourceSQLServer "SQLSERVER01" -SourceDatabase "VeryLargeDB" `
        -DestinationSQLServer "azure.database.windows.net" -DestinationDatabase "TestDB" `
        -SourceSQLType "MicrosoftSQL" -DestinationSQLType "AzureSQL" `
        -CompressionType "Maximum" -TempDirectory "E:\SQLTemp"

.EXAMPLE
    .\Migrate-SqlDatabase.ps1 -SourceSQLServer "SQLSERVER01" -SourceDatabase "ProdDB" `
        -DestinationSQLServer "SQLSERVER02" -DestinationDatabase "TestDB" `
        -SourceSQLType "MicrosoftSQL" -DestinationSQLType "MicrosoftSQL" `
        -LoggingDatabase "Server=LogServer;Database=MigrationMetrics;Integrated Security=True"
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
    [string]$DestinationSQLType = "AzureSQL",
    
    [Parameter(Mandatory=$false)]
    [string]$TempDirectory,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableDiagnostics,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Fast", "Optimal", "Maximum", "NoCompression")]
    [string]$CompressionType = "Fast",
    
    [Parameter(Mandatory=$false)]
    [string]$LoggingDatabase
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

# Function to ensure logging database table exists
function Initialize-LoggingDatabase {
    param(
        [string]$ConnectionString
    )
    
    $createTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'MigrationTimings')
BEGIN
    CREATE TABLE MigrationTimings (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        SourceServer NVARCHAR(255) NOT NULL,
        SourceDatabase NVARCHAR(128) NOT NULL,
        DestinationServer NVARCHAR(255) NOT NULL,
        DestinationDatabase NVARCHAR(128) NOT NULL,
        StartTimeUtc DATETIMEOFFSET NOT NULL,
        ExportStartUtc DATETIMEOFFSET NULL,
        ExportEndUtc DATETIMEOFFSET NULL,
        ExportDurationSeconds AS DATEDIFF(SECOND, ExportStartUtc, ExportEndUtc),
        ImportStartUtc DATETIMEOFFSET NULL,
        ImportEndUtc DATETIMEOFFSET NULL,
        ImportDurationSeconds AS DATEDIFF(SECOND, ImportStartUtc, ImportEndUtc),
        EndTimeUtc DATETIMEOFFSET NULL,
        TotalDurationSeconds AS DATEDIFF(SECOND, StartTimeUtc, EndTimeUtc),
        Status NVARCHAR(50) NOT NULL DEFAULT 'Started',
        ErrorMessage NVARCHAR(MAX) NULL,
        CompressionType NVARCHAR(20) NULL,
        BacpacSizeMB DECIMAL(10,2) NULL,
        MachineName NVARCHAR(255) NULL,
        UserName NVARCHAR(255) NULL
    );
    
    CREATE INDEX IX_MigrationTimings_StartTime ON MigrationTimings(StartTimeUtc DESC);
    CREATE INDEX IX_MigrationTimings_Databases ON MigrationTimings(SourceDatabase, DestinationDatabase);
END
"@
    
    try {
        if (Get-Command Invoke-SqlCmd -ErrorAction SilentlyContinue) {
            Invoke-SqlCmd -ConnectionString $ConnectionString -Query $createTableQuery -ErrorAction Stop
            Write-LogMessage "Logging database table initialized" -Type "Info"
        } else {
            Write-LogMessage "Invoke-SqlCmd not available. Database logging disabled." -Type "Warning"
            return $false
        }
        return $true
    }
    catch {
        Write-LogMessage "Could not initialize logging database: $_" -Type "Warning"
        return $false
    }
}

# Function to log migration timing to database
function Write-DatabaseLog {
    param(
        [string]$ConnectionString,
        [hashtable]$LogEntry
    )
    
    try {
        if (Get-Command Invoke-SqlCmd -ErrorAction SilentlyContinue) {
            $query = ""
            
            if ($LogEntry.ContainsKey("Id")) {
                # Update existing record
                $updates = @()
                foreach ($key in $LogEntry.Keys) {
                    if ($key -ne "Id") {
                        $value = if ($null -eq $LogEntry[$key]) { "NULL" } else { "'$($LogEntry[$key])'" }
                        $updates += "$key = $value"
                    }
                }
                $query = "UPDATE MigrationTimings SET $($updates -join ', ') WHERE Id = $($LogEntry.Id)"
            } else {
                # Insert new record
                $columns = $LogEntry.Keys -join ", "
                $values = $LogEntry.Values | ForEach-Object { 
                    if ($null -eq $_) { "NULL" } else { "'$_'" }
                } 
                $values = $values -join ", "
                $query = "INSERT INTO MigrationTimings ($columns) OUTPUT INSERTED.Id VALUES ($values)"
            }
            
            $result = Invoke-SqlCmd -ConnectionString $ConnectionString -Query $query -ErrorAction Stop
            if ($result -and $result.Id) {
                return $result.Id
            }
            return $LogEntry.Id
        }
    }
    catch {
        Write-Verbose "Database log write failed: $_"
    }
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
    
    # Initialize database logging if configured
    $dbLogId = $null
    $dbLoggingEnabled = $false
    if ($LoggingDatabase) {
        $dbLoggingEnabled = Initialize-LoggingDatabase -ConnectionString $LoggingDatabase
        if ($dbLoggingEnabled) {
            $logEntry = @{
                SourceServer = $SourceSQLServer
                SourceDatabase = $SourceDatabase
                DestinationServer = $DestinationSQLServer
                DestinationDatabase = $DestinationDatabase
                StartTimeUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
                Status = 'Started'
                CompressionType = $CompressionType
                MachineName = $env:COMPUTERNAME
                UserName = $env:USERNAME
            }
            $dbLogId = Write-DatabaseLog -ConnectionString $LoggingDatabase -LogEntry $logEntry
            Write-LogMessage "Migration timing will be logged to database (ID: $dbLogId)" -Type "Info"
        }
    }
    
    # Validate and display temp directory if specified
    if ($TempDirectory) {
        if (-not (Test-Path $TempDirectory)) {
            Write-LogMessage "Creating temp directory: $TempDirectory" -Type "Info"
            New-Item -Path $TempDirectory -ItemType Directory -Force | Out-Null
        }
        Write-LogMessage "Using custom temp directory: $TempDirectory" -Type "Info"
    }
    
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
    
    # Define search paths for SqlPackage.exe
    $sqlPackageSearchPaths = @(
        # SQL Server 2022 (160)
        "${env:ProgramFiles}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
        
        # SQL Server 2019 (150)
        "${env:ProgramFiles}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
        
        # SQL Server 2017 (140)
        "${env:ProgramFiles}\Microsoft SQL Server\140\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\140\DAC\bin\SqlPackage.exe",
        
        # SQL Server 2016 (130)
        "${env:ProgramFiles}\Microsoft SQL Server\130\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\130\DAC\bin\SqlPackage.exe",
        
        # Visual Studio 2022
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
        
        # Visual Studio 2019
        "${env:ProgramFiles}\Microsoft Visual Studio\2019\Enterprise\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2019\Professional\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2019\Community\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
        
        # Azure Data Studio
        "${env:LOCALAPPDATA}\Programs\Azure Data Studio\resources\app\extensions\mssql\sqltoolsservice\*\Windows\SqlPackage.exe",
        
        # .NET Tool installation
        "${env:USERPROFILE}\.dotnet\tools\SqlPackage.exe"
    )
    
    # Find all available SqlPackage.exe files with their versions
    $sqlPackageVersions = @()
    
    foreach ($searchPath in $sqlPackageSearchPaths) {
        # Handle wildcards in path
        if ($searchPath -like "*`**") {
            $resolvedPaths = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue
            foreach ($resolvedPath in $resolvedPaths) {
                if (Test-Path $resolvedPath.FullName) {
                    try {
                        $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($resolvedPath.FullName)
                        $sqlPackageVersions += @{
                            Path = $resolvedPath.FullName
                            Version = $version.FileVersion
                            ProductVersion = $version.ProductVersion
                            VersionObject = [Version]::new($version.FileMajorPart, $version.FileMinorPart, $version.FileBuildPart, $version.FilePrivatePart)
                        }
                    }
                    catch {
                        # If we can't get version info, still add it with a low version
                        $sqlPackageVersions += @{
                            Path = $resolvedPath.FullName
                            Version = "0.0.0.0"
                            ProductVersion = "Unknown"
                            VersionObject = [Version]::new(0, 0, 0, 0)
                        }
                    }
                }
            }
        }
        else {
            if (Test-Path $searchPath) {
                try {
                    $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($searchPath)
                    $sqlPackageVersions += @{
                        Path = $searchPath
                        Version = $version.FileVersion
                        ProductVersion = $version.ProductVersion
                        VersionObject = [Version]::new($version.FileMajorPart, $version.FileMinorPart, $version.FileBuildPart, $version.FilePrivatePart)
                    }
                }
                catch {
                    # If we can't get version info, still add it with a low version
                    $sqlPackageVersions += @{
                        Path = $searchPath
                        Version = "0.0.0.0"
                        ProductVersion = "Unknown"
                        VersionObject = [Version]::new(0, 0, 0, 0)
                    }
                }
            }
        }
    }
    
    if ($sqlPackageVersions.Count -eq 0) {
        throw "SqlPackage.exe not found. Please install SQL Server Data Tools, SQL Server Management Studio, or the SqlPackage .NET tool."
    }
    
    # Sort by version and select the highest version
    $highestVersion = $sqlPackageVersions | Sort-Object -Property VersionObject -Descending | Select-Object -First 1
    $sqlPackage = $highestVersion.Path
    
    Write-LogMessage "Found $($sqlPackageVersions.Count) SqlPackage.exe installation(s)" -Type "Info"
    Write-LogMessage "Using highest version: $($highestVersion.Version)" -Type "Success"
    Write-LogMessage "Path: $sqlPackage" -Type "Info"
    
    # Show all found versions in verbose mode
    if ($VerbosePreference -eq 'Continue') {
        Write-Verbose "All SqlPackage.exe versions found:"
        foreach ($pkg in ($sqlPackageVersions | Sort-Object -Property VersionObject -Descending)) {
            Write-Verbose "  Version $($pkg.Version) at $($pkg.Path)"
        }
    }
    
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
        Write-LogMessage "Using compression type: $CompressionType" -Type "Info"
        
        # Log export start to database
        if ($dbLoggingEnabled -and $dbLogId) {
            $logEntry = @{
                Id = $dbLogId
                ExportStartUtc = $exportStartTime.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
                Status = 'Exporting'
            }
            Write-DatabaseLog -ConnectionString $LoggingDatabase -LogEntry $logEntry | Out-Null
        }
        
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
            "/OverwriteFiles:True",
            "/p:CompressionOption=$CompressionType"
        )
        
        # Add temp directory parameter if specified
        if ($TempDirectory) {
            $exportArgs += "/p:TempDirectoryForTableData=`"$TempDirectory`""
        }
        
        # Add diagnostic parameters if enabled
        if ($EnableDiagnostics) {
            Write-LogMessage "Diagnostics enabled - SqlPackage will output verbose information" -Type "Warning"
            $exportArgs += "/DiagnosticsLevel:Verbose"
            $exportArgs += "/Diagnostics:True"
        }
        
        Write-LogMessage "Executing: $sqlPackage Export (authentication details hidden for security)" -Type "Info"
        Write-Verbose "Connection String: $sourceConnectionString"
        Write-Verbose "Compression Type: $CompressionType"
        if ($TempDirectory) {
            Write-Verbose "Temp Directory: $TempDirectory"
        }
        
        if ($EnableDiagnostics) {
            # Run with output visible for diagnostics
            $exportProcess = Start-Process -FilePath $sqlPackage -ArgumentList $exportArgs `
                -NoNewWindow -Wait -PassThru
        } else {
            # Run normally
            $exportProcess = Start-Process -FilePath $sqlPackage -ArgumentList $exportArgs `
                -NoNewWindow -Wait -PassThru
        }
        
        if ($exportProcess.ExitCode -ne 0) {
            throw "Export failed with exit code: $($exportProcess.ExitCode)"
        }
        
        $timings["Export"] = (Get-Date) - $exportStartTime
        Write-LogMessage "Export completed successfully in $(Format-ElapsedTime -StartTime $exportStartTime)" -Type "End"
        
        # Log export completion to database
        if ($dbLoggingEnabled -and $dbLogId) {
            $logEntry = @{
                Id = $dbLogId
                ExportEndUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
                Status = 'Exported'
            }
            Write-DatabaseLog -ConnectionString $LoggingDatabase -LogEntry $logEntry | Out-Null
        }
    } else {
        Write-LogMessage "Skipping export - using existing BACPAC file" -Type "Info"
    }
    
    # Verify BACPAC file exists
    if (-not (Test-Path $bacpacPath)) {
        throw "BACPAC file not found at: $bacpacPath"
    }
    
    $fileInfo = Get-Item $bacpacPath
    $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
    Write-LogMessage "BACPAC file size: $fileSizeMB MB" -Type "Info"
    
    # Log BACPAC size to database
    if ($dbLoggingEnabled -and $dbLogId) {
        $logEntry = @{
            Id = $dbLogId
            BacpacSizeMB = $fileSizeMB
        }
        Write-DatabaseLog -ConnectionString $LoggingDatabase -LogEntry $logEntry | Out-Null
    }
    
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
    
    # Log import start to database
    if ($dbLoggingEnabled -and $dbLogId) {
        $logEntry = @{
            Id = $dbLogId
            ImportStartUtc = $importStartTime.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
            Status = 'Importing'
        }
        Write-DatabaseLog -ConnectionString $LoggingDatabase -LogEntry $logEntry | Out-Null
    }
    
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
    
    # Add diagnostic parameters if enabled
    if ($EnableDiagnostics) {
        Write-LogMessage "Diagnostics enabled - SqlPackage will output verbose information" -Type "Warning"
        $importArgs += "/DiagnosticsLevel:Verbose"
        $importArgs += "/Diagnostics:True"
    }
    
    Write-LogMessage "Executing: $sqlPackage Import (authentication details hidden for security)" -Type "Info"
    Write-Verbose "Connection String: $destinationConnectionString"
    
    if ($EnableDiagnostics) {
        # Run with output visible for diagnostics
        $importProcess = Start-Process -FilePath $sqlPackage -ArgumentList $importArgs `
            -NoNewWindow -Wait -PassThru
    } else {
        # Run normally
        $importProcess = Start-Process -FilePath $sqlPackage -ArgumentList $importArgs `
            -NoNewWindow -Wait -PassThru
    }
    
    if ($importProcess.ExitCode -ne 0) {
        throw "Import failed with exit code: $($importProcess.ExitCode)"
    }
    
    $timings["Import"] = (Get-Date) - $importStartTime
    Write-LogMessage "Import completed successfully in $(Format-ElapsedTime -StartTime $importStartTime)" -Type "End"
    
    # Log import completion to database
    if ($dbLoggingEnabled -and $dbLogId) {
        $logEntry = @{
            Id = $dbLogId
            ImportEndUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
            Status = 'Imported'
        }
        Write-DatabaseLog -ConnectionString $LoggingDatabase -LogEntry $logEntry | Out-Null
    }
    
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
    
    # Log final success to database
    if ($dbLoggingEnabled -and $dbLogId) {
        $logEntry = @{
            Id = $dbLogId
            EndTimeUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
            Status = 'Completed'
        }
        Write-DatabaseLog -ConnectionString $LoggingDatabase -LogEntry $logEntry | Out-Null
    }
    
} catch {
    # Log error to database if enabled
    if ($dbLoggingEnabled -and $dbLogId -and $LoggingDatabase) {
        $logEntry = @{
            Id = $dbLogId
            EndTimeUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
            Status = 'Failed'
            ErrorMessage = $_.Exception.Message
        }
        Write-DatabaseLog -ConnectionString $LoggingDatabase -LogEntry $logEntry | Out-Null
    }
    
    Handle-Error -Operation "Database Migration" -ErrorRecord $_
}