#
# Module manifest for module 'srmgen'
#

@{
    RootModule = 'srmgen.psm1'
    ModuleVersion = '1.0.0'
    GUID = '9e0b8e64-f6cf-4482-a9b0-94d76295de32'
    Author = 'Steam ROM Manager Manifest Generator'
    CompanyName = 'Community'
    Copyright = '(c) 2026. All rights reserved.'
    Description = 'PowerShell module to parse Windows shortcuts and generate/manage Steam ROM Manager manifests.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-SrmTargetKey',
        'Get-SrmDefaultManifestFileName',
        'ConvertFrom-LnkShortcut',
        'New-SrmManifestEntry',
        'Import-SrmManifest',
        'Export-SrmManifest',
        'Read-SrmHostPrefilled',
        'Invoke-SrmInteractivePrompt',
        'Invoke-SrmTui'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
