<#
.SYNOPSIS
    Connects to a SharePoint Online site, finds a list, and extracts metadata
    about its columns (fields).

.DESCRIPTION
    Uses PnP.PowerShell to connect to a SharePoint Online site, locate the
    specified list, and return information about each of its columns
    (internal name, display name, type, required, hidden, etc.).

    Optionally exports the results to a CSV file.

.PARAMETER SiteUrl
    The full URL of the SharePoint Online site, e.g.
    https://contoso.sharepoint.com/sites/MySite

.PARAMETER ListName
    The display name (Title) of the SharePoint list to inspect.

.PARAMETER IncludeHidden
    If specified, hidden/system columns are included in the output.
    By default they are filtered out.

.PARAMETER ExportCsvPath
    Optional. If provided, the column metadata is also written to this CSV file.

.EXAMPLE
    .\Get-SPListColumns.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/HR" `
                            -ListName "Employees"

.EXAMPLE
    .\Get-SPListColumns.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/HR" `
                            -ListName "Employees" `
                            -IncludeHidden `
                            -ExportCsvPath "C:\Temp\EmployeesColumns.csv"

.NOTES
    Requires the PnP.PowerShell module:
        Install-Module PnP.PowerShell -Scope CurrentUser

    The first time you connect interactively you may need to register the
    PnP Management Shell Entra ID app in your tenant:
        Register-PnPManagementShellAccess
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SiteUrl,

    [Parameter(Mandatory = $true)]
    [string] $ListName,

    [switch] $IncludeHidden,

    [string] $ExportCsvPath
)

# --- Ensure PnP.PowerShell is available --------------------------------------
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Write-Error "PnP.PowerShell module is not installed. Install it with: Install-Module PnP.PowerShell -Scope CurrentUser"
    exit 1
}

Import-Module PnP.PowerShell -ErrorAction Stop

# --- Connect to the SharePoint site -----------------------------------------
try {
    Write-Host "Connecting to $SiteUrl ..." -ForegroundColor Cyan
    Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop
}
catch {
    Write-Error "Failed to connect to $SiteUrl. $_"
    exit 1
}

# --- Locate the list ---------------------------------------------------------
try {
    Write-Host "Looking up list '$ListName' ..." -ForegroundColor Cyan
    $list = Get-PnPList -Identity $ListName -ErrorAction Stop
    if (-not $list) {
        throw "List '$ListName' was not found on $SiteUrl."
    }
}
catch {
    Write-Error $_
    Disconnect-PnPOnline
    exit 1
}

Write-Host "Found list: $($list.Title)  (ItemCount: $($list.ItemCount))" -ForegroundColor Green

# --- Retrieve fields ---------------------------------------------------------
try {
    $fields = Get-PnPField -List $list -ErrorAction Stop
}
catch {
    Write-Error "Failed to retrieve fields for list '$ListName'. $_"
    Disconnect-PnPOnline
    exit 1
}

if (-not $IncludeHidden) {
    $fields = $fields | Where-Object { -not $_.Hidden }
}

# --- Project the data we care about -----------------------------------------
$columnInfo = $fields | ForEach-Object {
    [PSCustomObject]@{
        InternalName  = $_.InternalName
        Title         = $_.Title
        TypeAsString  = $_.TypeAsString
        Required      = $_.Required
        Hidden        = $_.Hidden
        ReadOnly      = $_.ReadOnlyField
        Indexed       = $_.Indexed
        Group         = $_.Group
        Description   = $_.Description
        DefaultValue  = $_.DefaultValue
        Id            = $_.Id
    }
}

# --- Output ------------------------------------------------------------------
$columnInfo | Format-Table InternalName, Title, TypeAsString, Required, Hidden -AutoSize

if ($ExportCsvPath) {
    try {
        $columnInfo | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Exported column metadata to $ExportCsvPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to write CSV to $ExportCsvPath. $_"
    }
}

# Return the objects so the script can be piped/consumed
$columnInfo

# --- Cleanup -----------------------------------------------------------------
Disconnect-PnPOnline
