# Changelog
All notable changes to the SQL Database BACPAC Migration Script will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.6.2] - 2024-12-19

### Removed
- Azure AD token authentication support and Get-AzureSqlToken function
- Dependency on Az PowerShell module
- Token-based authentication logic with /AccessToken parameter

### Changed
- Reverted to simpler authentication approach using only Active Directory Interactive for Azure SQL
- Simplified export and import code paths by removing token detection logic
- Cleaner code structure without conditional authentication paths

### Rationale
- Reduced complexity and external dependencies
- Active Directory Interactive authentication handles credential caching automatically
- Fewer potential points of failure

## [1.6.1] - 2024-12-19

### Changed
- FilePath parameter now defaults to "C:\Temp" directly in the parameter definition
- FilePath parameter now expects a directory path rather than a full file path
- Simplified path handling logic - the script always builds the full BACPAC path as [FilePath]\[DestinationDatabase].bacpac
- Updated example in documentation to show FilePath as directory (e.g., "D:\Backups" instead of "D:\Backups\TestDB.bacpac")

### Improved
- Cleaner code structure with simpler path handling
- More consistent behavior - FilePath always represents a directory

## [1.6.0] - 2024-12-19

### Added
- Automatic Azure AD token authentication support using Az PowerShell module
- Function `Get-AzureSqlToken` to retrieve cached Azure AD tokens when available
- Fallback mechanism: uses token if available, otherwise uses interactive authentication
- Support for `/AccessToken` parameter in SqlPackage when token is available

### Changed
- Export and import processes now check for Azure AD tokens before defaulting to interactive auth
- Improved authentication flow for Azure SQL Database connections
- Better logging to indicate which authentication method is being used

### Notes
- Requires Az.Accounts PowerShell module for token functionality (optional)
- If Az module is not installed or user is not logged in, falls back to interactive authentication
- Run `Connect-AzAccount` before the script to enable token-based authentication
- Tokens are automatically refreshed by Azure PowerShell, reducing authentication prompts

## [1.5.1] - 2024-12-19

### Changed
- Reverted database sizing features from v1.5.0 back to v1.4.1 functionality
- Updated version number to 1.5.1

### Retained
- Copyright notice for Michael Smith (michael@mikesmith.xyz)
- Version information in script header

### Removed
- Automatic source database size detection
- Target database size calculation with buffer
- Database sizing functions (Get-SourceDatabaseSize, Get-TargetDatabaseSize)
- DatabaseMaxSize property setting during import

## [1.5.0] - 2024-12-19 [REVERTED]

### Added
- Automatic source database size detection for intelligent target database sizing
- Target database size calculation with 15% buffer for growth
- Automatic rounding to nearest valid Azure SQL Database size for P11 tier
- Minimum database size enforcement of 1 GiB
- Valid P11 size selection from Azure's supported sizes (1 GB to 4096 GB)
- Version number (1.5.0) embedded in script header
- Copyright notice for Michael Smith (michael@mikesmith.xyz)
- New functions:
  - `Get-SourceDatabaseSize`: Queries source database size
  - `Get-TargetDatabaseSize`: Calculates optimal target size with buffer

### Changed
- Import process now sets DatabaseMaxSize property based on source database size
- Enhanced logging to show source size and calculated target size

## [1.4.1] - 2024-12-19

### Fixed
- Corrected service objective parameter syntax for SqlPackage
  - Changed from `/DatabaseServiceObjective:P11` to `/Properties:DatabaseServiceObjective="P11"`
  - This uses the proper Properties collection syntax required by SqlPackage

## [1.4.0] - 2024-12-19

### Fixed
- Corrected Azure SQL connection strings to include BOTH "tcp:" protocol AND port 1433
  - Changed from `Server=servername,1433` to `Server=tcp:servername,1433`
  - Applied to all Azure SQL connections (export, import, and database checks)

### Changed
- Renamed script references from `Migrate-Database.ps1` to `Migrate-SqlDatabase.ps1` in all examples
- Updated all documentation to use consistent script naming

## [1.3.0] - 2024-12-19

### Fixed
- Corrected Azure SQL connection string format by removing "tcp:" prefix and adding port 1433
  - Changed from `Server=tcp:servername` to `Server=servername,1433`
- Removed unsupported `/TargetDatabaseEdition:Premium` parameter from SqlPackage import arguments
- Renamed `/TargetServiceObjectiveName` parameter to `/DatabaseServiceObjective` for SqlPackage compatibility

### Changed
- Updated all Azure SQL connection strings to use proper format with explicit port specification
- Improved SqlPackage parameter compatibility for current versions

## [1.2.0] - 2024-12-19

### Changed
- Migrated from individual authentication parameters to connection strings for better compatibility
- Export and Import now use `/SourceConnectionString` and `/TargetConnectionString` parameters
- Connection strings now embed authentication methods directly

### Added
- Verbose logging option for connection strings (hidden by default for security)
- Better connection string construction based on SQL type

## [1.1.0] - 2024-12-19

### Added
- New optional parameters `SourceSQLType` and `DestinationSQLType` with options for "AzureSQL" or "MicrosoftSQL"
- Both SQL type parameters default to "AzureSQL"
- Active Directory Interactive authentication support for Azure SQL connections
- Windows authentication support for Microsoft SQL Server connections
- Conditional Premium P11 service tier setting only for Azure SQL destinations

### Changed
- Authentication method now determined by SQL type parameter
- Updated logging to show SQL type for source and destination
- Connection handling now adapts based on server type

## [1.0.0] - 2024-12-19

### Initial Release

#### Features
- **Required Parameters:**
  - Source SQL Server
  - Source Database
  - Destination SQL Server
  - Destination Database

- **Optional Parameters:**
  - FilePath for BACPAC storage (defaults to C:\Temp)
  - AllowClobber with four modes: None (default), Source, Destination, Both

- **Core Functionality:**
  - Exports source database to BACPAC format
  - Imports BACPAC to destination server
  - Supports Azure SQL Database with Premium P11 service tier
  - Smart file handling with reuse based on clobber settings
  - Comprehensive error handling and logging
  - Detailed timing measurements for each operation
  - Color-coded console output for better readability
  - Automatic SqlPackage.exe detection from multiple common locations
  - Temporary file cleanup on success
  - File retention on failure for retry attempts

- **Safety Features:**
  - Clean error messages with detailed information
  - Database existence checking before operations
  - Proper cleanup procedures
  - Verbose logging options

- **Platform Support:**
  - Azure SQL Database with .database.windows.net detection
  - On-premises SQL Server
  - Windows Authentication by default
  - Placeholder for Azure AD authentication