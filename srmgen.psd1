#
# Module manifest for module 'srmgen'
#

@{
    RootModule = 'srmgen.psm1'
    ModuleVersion = '1.2.0'
    GUID = '9e0b8e64-f6cf-4482-a9b0-94d76295de32'
    Author = 'Steam ROM Manager Manifest Generator'
    CompanyName = 'Community'
    Copyright = '(c) 2026. All rights reserved.'
    Description = 'PowerShell module to parse Windows shortcuts in parallel, manage SRM manifests with hash caching database and recent settings.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-SrmItemHash',
        'Get-SrmTargetKey',
        'Get-SrmDefaultManifestFileName',
        'Get-SrmDatabase',
        'Save-SrmDatabase',
        'Get-SrmSettings',
        'Save-SrmSettings',
        'Get-SrmTemplate',
        'ConvertFrom-LnkShortcut',
        'New-SrmShortcut',
        'Add-SrmManualShortcut',
        'New-SrmManifestEntry',
        'Invoke-SrmParallelScan',
        'Import-SrmManifest',
        'Export-SrmManifest',
        'Read-SrmHostPrefilled',
        'Invoke-SrmInteractivePrompt',
        'Invoke-SrmTui',
        'Invoke-SrmWizard'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
