#Requires -Version 7.0
<#
.SYNOPSIS
    Applies the repository settings that org rulesets and security configurations can't inherit to a GitHub Action repository.
.EXAMPLE
    ./configure-action-repo.ps1 -Repository RageAgainstThePixel/retry-failed-jobs
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[\w.-]+/[\w.-]+$')]
    [string]$Repository,

    # existing action repo whose discord release/star hook is copied, so the url never lives in source control
    [ValidatePattern('^[\w.-]+/[\w.-]+$')]
    [string]$DiscordHookSource = 'RageAgainstThePixel/unity-action'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# action.yml name must be unique across the whole Marketplace
$actionYaml = $null
foreach ($file in 'action.yml', 'action.yaml') {
    try {
        $actionYaml = gh api "repos/$Repository/contents/$file" -H 'Accept: application/vnd.github.raw' 2>$null
        break
    }
    catch { }
}

if (-not $actionYaml) {
    throw "$Repository has no action.yml on its default branch"
}

$nameLine = $actionYaml | Where-Object { $_ -match '^name:\s*(.+)$' } | Select-Object -First 1
$actionName = ($nameLine -replace '^name:\s*', '').Trim().Trim('''"')
$slug = ($actionName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
$listing = Invoke-WebRequest "https://github.com/marketplace/actions/$slug" -SkipHttpErrorCheck

if ($listing.StatusCode -eq 200 -and $listing.Content -notmatch [regex]::Escape("$Repository@")) {
    throw "Marketplace name '$actionName' is already taken: https://github.com/marketplace/actions/$slug"
}

Write-Host "Marketplace name '$actionName' is available"

if ($PSCmdlet.ShouldProcess($Repository, 'apply action repository settings')) {
    $settings = @{
        allow_squash_merge          = $true
        allow_merge_commit          = $false
        allow_rebase_merge          = $false
        squash_merge_commit_title   = 'PR_TITLE'
        squash_merge_commit_message = 'PR_BODY'
        delete_branch_on_merge      = $true
        allow_auto_merge            = $true
        allow_update_branch         = $true
        has_wiki                    = $false
        has_projects                = $false
        has_discussions             = $false
        security_and_analysis       = @{
            secret_scanning                 = @{ status = 'enabled' }
            secret_scanning_push_protection = @{ status = 'enabled' }
        }
    }
    $settings | ConvertTo-Json -Depth 4 | gh api -X PATCH "repos/$Repository" --input - --silent

    @{ properties = @(@{ property_name = 'type'; value = 'action' }) } |
        ConvertTo-Json -Depth 4 |
        gh api -X PATCH "repos/$Repository/properties/values" --input - --silent

    # org security configuration enables default setup, but only with the default query suite
    gh api -X PATCH "repos/$Repository/code-scanning/default-setup" -f state=configured -f query_suite=extended --silent

    $discordUrl = gh api "repos/$DiscordHookSource/hooks" --jq '[.[] | select(.config.url | test("discord.com"))][0].config.url'

    if (-not $discordUrl) {
        throw "$DiscordHookSource has no discord hook to copy"
    }

    $existing = gh api "repos/$Repository/hooks" --jq '[.[] | select(.config.url | test("discord.com"))] | length'

    if ($existing -eq '0') {
        @{
            name   = 'web'
            active = $true
            events = @('release', 'star')
            config = @{ url = $discordUrl; content_type = 'json'; insecure_ssl = '0' }
        } | ConvertTo-Json -Depth 4 | gh api -X POST "repos/$Repository/hooks" --input - --silent
    }

    Remove-Variable discordUrl
    Write-Host "Configured $Repository"
}
