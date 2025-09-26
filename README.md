# SQL Database BACPAC Migration Script

A powerful PowerShell script for exporting and importing SQL databases using BACPAC files, with support for both Azure SQL Database and on-premises SQL Server.

## Features

- 🔄 **Export & Import** - Seamlessly migrate databases using BACPAC format
- ☁️ **Azure SQL Support** - Full support for Azure SQL Database with P11 tier configuration
- 🖥️ **On-Premises Support** - Works with traditional SQL Server installations
- 🔐 **Multiple Authentication** - Supports Azure AD Interactive and Windows Authentication
- 📊 **Progress Tracking** - Detailed timing and progress reporting
- 🔁 **Smart Retry** - Preserves BACPAC files on failure for retry attempts
- 🎯 **Flexible Clobber Modes** - Control over file and database overwrites

## Requirements

- PowerShell 5.1 or higher
- SqlPackage.exe (installed with SQL Server Data Tools or DAC Framework)
- Appropriate permissions on source and destination SQL servers
- For Azure SQL: Azure AD account with appropriate permissions

## Installation

1. Download the `Migrate-SqlDatabase.ps1` script
2. Ensure SqlPackage.exe is installed (typically comes with SQL Server Management Studio or Visual Studio)
3. Run PowerShell as Administrator (recommended for first-time setup)

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| **SourceSQLServer** | String | Yes | - | Source SQL Server instance name |
| **SourceDatabase** | String | Yes | - | Source database name to export |
| **DestinationSQLServer** | String | Yes | - | Destination SQL Server instance name |
| **DestinationDatabase** | String | Yes | - | Destination database name to create |
| **FilePath** | String | No | `C:\Temp` | Directory path for the BACPAC file |
| **AllowClobber** | String | No | `None` | What to delete/overwrite (see Clobber Modes) |
| **SourceSQLType** | String | No | `AzureSQL` | Type of source SQL Server |
| **DestinationSQLType** | String | No | `AzureSQL` | Type of destination SQL Server |

### SQL Types
- **AzureSQL**: Azure SQL Database (uses Active Directory Interactive authentication)
- **MicrosoftSQL**: On-premises SQL Server (uses Windows authentication)

### Clobber Modes
- **None**: Reuse existing BACPAC file if present, don't delete destination database (default)
- **Source**: Delete and recreate BACPAC file if it exists
- **Destination**: Delete destination database if it exists before import
- **Both**: Delete both BACPAC file and destination database if they exist

## Usage Examples

### Basic Azure SQL to Azure SQL Migration
```powershell
.\Migrate-SqlDatabase.ps1 `
    -SourceSQLServer "sourceserver.database.windows.net" `
    -SourceDatabase "ProductionDB" `
    -DestinationSQLServer "targetserver.database.windows.net" `
    -DestinationDatabase "TestDB"
```

### On-Premises to Azure SQL
```powershell
.\Migrate-SqlDatabase.ps1 `
    -SourceSQLServer "SQLSERVER01" `
    -SourceDatabase "LocalDB" `
    -DestinationSQLServer "azureserver.database.windows.net" `
    -DestinationDatabase "CloudDB" `
    -SourceSQLType "MicrosoftSQL" `
    -DestinationSQLType "AzureSQL"
```

### On-Premises to On-Premises with Custom Path
```powershell
.\Migrate-SqlDatabase.ps1 `
    -SourceSQLServer "SQLPROD01" `
    -SourceDatabase "ProductionDB" `
    -DestinationSQLServer "SQLTEST01" `
    -DestinationDatabase "TestDB" `
    -SourceSQLType "MicrosoftSQL" `
    -DestinationSQLType "MicrosoftSQL" `
    -FilePath "D:\SQLBackups" `
    -AllowClobber "Both"
```

### Azure SQL with Clobber
```powershell
.\Migrate-SqlDatabase.ps1 `
    -SourceSQLServer "server1.database.windows.net" `
    -SourceDatabase "SourceDB" `
    -DestinationSQLServer "server2.database.windows.net" `
    -DestinationDatabase "TargetDB" `
    -AllowClobber "Destination"
```

## Output

The script provides detailed colored output including:
- ⏱️ Timing for each operation
- ✅ Success messages
- ⚠️ Warnings for important operations
- ❌ Clear error messages with troubleshooting info
- 📊 File size information
- 🔍 Authentication method being used

### Example Output
```
[2024-12-19 10:15:00] === SQL Database Migration Script Started ===
[2024-12-19 10:15:00] Source: server1.database.windows.net\ProdDB (Type: AzureSQL)
[2024-12-19 10:15:00] Destination: server2.database.windows.net\TestDB (Type: AzureSQL)
[2024-12-19 10:15:01] Found SqlPackage.exe at: C:\Program Files\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe
[2024-12-19 10:15:01] Starting database export from AzureSQL...
[2024-12-19 10:18:45] Export completed successfully in 03:44.123
[2024-12-19 10:18:45] BACPAC file size: 1024.50 MB
[2024-12-19 10:18:45] Starting database import to AzureSQL...
[2024-12-19 10:25:30] Import completed successfully in 06:45.789
[2024-12-19 10:25:31] === Migration Completed Successfully ===
```

## Troubleshooting

### Common Issues

1. **SqlPackage.exe not found**
   - Install SQL Server Data Tools or SQL Server Management Studio
   - The script searches common installation paths automatically

2. **Authentication failures with Azure SQL**
   - Ensure you have appropriate Azure AD permissions
   - You may be prompted for interactive authentication
   - Check that your Azure AD account has access to both source and destination servers

3. **BACPAC file errors**
   - Use the `-AllowClobber "Source"` parameter to force recreation
   - Check available disk space in the FilePath directory
   - Verify the source database doesn't have compatibility issues

4. **Import failures**
   - For Azure SQL, ensure the P11 tier is available in your subscription
   - Check that the destination server has sufficient resources
   - Review any database compatibility level mismatches

### Verbose Mode

For detailed troubleshooting, run with the `-Verbose` parameter:
```powershell
.\Migrate-SqlDatabase.ps1 -Verbose `
    -SourceSQLServer "server1" `
    -SourceDatabase "DB1" `
    -DestinationSQLServer "server2" `
    -DestinationDatabase "DB2"
```

## Performance Tips

- **Reuse BACPAC files**: Use the default clobber mode (`None`) to skip re-export if the BACPAC already exists
- **Network location**: Run the script from a machine with good network connectivity to both servers
- **Off-peak hours**: Schedule large database migrations during off-peak hours
- **Disk space**: Ensure adequate disk space (typically 2-3x the database size)

## Contributing

We welcome contributions! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with your improvements

See [LICENSE.md](LICENSE.md) for more details about our community requests.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

While not required, we kindly request that you:
- Link back to this repository if you distribute the script
- Consider contributing improvements back to the community
- Share your enhancements via pull requests

## Author

**Michael Smith**  
Email: michael@mikesmith.xyz  
Repository: https://github.com/UbiSmith/SqlDBMigrate

## Version History

See [CHANGELOG.md](CHANGELOG.md) for a detailed version history.

## Support

For issues, questions, or suggestions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review existing [GitHub Issues](https://github.com/UbiSmith/SqlDBMigrate/issues)
3. Create a new issue with detailed information about your problem

## Acknowledgments

- Microsoft SqlPackage team for the excellent BACPAC tooling
- The PowerShell community for ongoing support and feedback
- All contributors who help improve this script