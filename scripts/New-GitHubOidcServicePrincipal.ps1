<#
.SYNOPSIS
    Creates the GitHub OIDC deployment service principal for ONE environment.

.DESCRIPTION
    Each environment (dev/test/prod) gets its own app registration + service
    principal, with TWO federated credentials -- one for the "<env>-plan" GitHub
    Environment and one for "<env>-apply". No client secret is ever created:
    GitHub Actions authenticates with a short-lived OIDC token exchanged for an
    Entra token, so there is nothing to rotate or leak.

    Run once per environment. In a real delivery each environment lives in its
    own subscription, which is why -SubscriptionId is a parameter rather than an
    assumption -- Baytex's Global Administrator runs this identical script three
    times with three different subscription IDs.

    Requires Global Administrator (or Application Administrator + User Access
    Administrator) in the tenant.

.PARAMETER Environment
    dev, test or prod. Drives the app name and both federated credential subjects.

.PARAMETER SubscriptionId
    Subscription this environment deploys into, and the scope for role assignments.

.PARAMETER GitHubOrg
    GitHub organisation that owns the repository. Forms part of both federated
    credential subjects, so it must match exactly.

.PARAMETER GitHubRepo
    Repository name. Forms part of both federated credential subjects.

.PARAMETER UseOwnerRole
    Assign Owner instead of Contributor + User Access Administrator. Simpler but
    broader; the default split is the least privilege that still works.

.EXAMPLE
    .\New-GitHubOidcServicePrincipal.ps1 -Environment dev `
        -SubscriptionId 00000000-0000-0000-0000-000000000000 `
        -GitHubOrg <organisation> -GitHubRepo <repository>

.NOTES
    Idempotent: re-running reuses the existing app, service principal, federated
    credentials and role assignments rather than duplicating them.

    Written for Windows PowerShell 5.1 as well as PowerShell 7.x, so it runs on a
    stock Windows admin workstation without installing pwsh.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$GitHubOrg,

    [Parameter(Mandatory)]
    [string]$GitHubRepo,

    [string]$NamePrefix = 'sp-bte-dbx',

    [switch]$UseOwnerRole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppName        = "$NamePrefix-$Environment-github"
$Issuer         = 'https://token.actions.githubusercontent.com'
$Audience       = 'api://AzureADTokenExchange'
$GitHubEnvNames = @("$Environment-plan", "$Environment-apply")
$Scope          = "/subscriptions/$SubscriptionId"

# Windows PowerShell 5.1 turns any stderr output from a native exe into an
# ErrorRecord, which terminates under $ErrorActionPreference='Stop' before the
# real exit code can be inspected. These helpers drop to 'Continue' around the
# az call and branch on $LASTEXITCODE instead.
function Invoke-Az {
    param([string[]]$Arguments, [string]$What, [int]$MaxAttempts = 4)
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $output = & az @Arguments 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $previous

        if ($code -eq 0) { return ($output | Out-String) }

        # ARM and Graph intermittently reset connections and return 429/5xx.
        # Those are worth retrying; a genuine authorisation or validation error
        # is not, so only back off on the transient signatures.
        $text = ($output | Out-String)
        $isTransient = $text -match 'Connection aborted|ConnectionResetError|forcibly closed|timed out|TooManyRequests|429|50[0234]|ServiceUnavailable|BadGateway'

        if (-not $isTransient -or $attempt -eq $MaxAttempts) {
            Write-Host $text -ForegroundColor Red
            throw "FAILED: $What"
        }

        $delay = [Math]::Pow(2, $attempt) * 2
        Write-Host "  transient failure on '$What' (attempt $attempt/$MaxAttempts), retrying in ${delay}s" -ForegroundColor DarkYellow
        Start-Sleep -Seconds $delay
    }
}

function Invoke-AzJson {
    param([string[]]$Arguments, [string]$What)
    $raw = Invoke-Az -Arguments $Arguments -What $What
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

# --- preflight -------------------------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required. Install it and run az login first.'
}

Write-Step "Confirming signed-in context"
$account = Invoke-AzJson @('account', 'show', '--output', 'json') 'read current az account'
Write-Host "  Tenant       : $($account.tenantId)"
Write-Host "  Signed in as : $($account.user.name)"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) 'set subscription' | Out-Null
$target = Invoke-AzJson @('account', 'show', '--output', 'json') 'read target subscription'
Write-Host "  Target sub   : $($target.name) ($SubscriptionId)" -ForegroundColor Green
$TenantId = $target.tenantId

# --- resolve GitHub identifiers -------------------------------------------
# The federated credential only needs the subject string, but recording the
# numeric org/repo IDs makes the credential auditable against a specific repo
# even if it is later renamed.
Write-Step "Resolving GitHub identifiers"
$GitHubOrgId = $null
$GitHubRepoId = $null
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $orgJson = & gh api "orgs/$GitHubOrg" 2>$null
    $repoJson = & gh api "repos/$GitHubOrg/$GitHubRepo" 2>$null
    $ErrorActionPreference = $previous
    if ($orgJson) { $GitHubOrgId = ($orgJson | ConvertFrom-Json).id }
    if ($repoJson) { $GitHubRepoId = ($repoJson | ConvertFrom-Json).id }
}
if (-not $GitHubOrgId) { $GitHubOrgId = '(unresolved - gh CLI not authenticated)' }
if (-not $GitHubRepoId) { $GitHubRepoId = '(unresolved - gh CLI not authenticated)' }

Write-Host "  Organization : $GitHubOrg (id $GitHubOrgId)"
Write-Host "  Repository   : $GitHubOrg/$GitHubRepo (id $GitHubRepoId)"
Write-Host "  Entity type  : Environment"
Write-Host "  Environments : $($GitHubEnvNames -join ', ')"

# --- app registration ------------------------------------------------------
Write-Step "App registration '$AppName'"
$existing = Invoke-AzJson @('ad', 'app', 'list', '--display-name', $AppName, '--output', 'json') 'list app registrations'

if ($existing -and @($existing).Count -gt 0) {
    $app = @($existing)[0]
    Write-Host "  Already exists, reusing. appId $($app.appId)" -ForegroundColor DarkYellow
}
else {
    if (-not $PSCmdlet.ShouldProcess($AppName, 'Create app registration')) { return }
    $app = Invoke-AzJson @('ad', 'app', 'create', '--display-name', $AppName,
        '--sign-in-audience', 'AzureADMyOrg', '--output', 'json') 'create app registration'
    Write-Host "  Created. appId $($app.appId)" -ForegroundColor Green
}
$AppId = $app.appId

# --- service principal -----------------------------------------------------
Write-Step "Service principal"
$spList = Invoke-AzJson @('ad', 'sp', 'list', '--filter', "appId eq '$AppId'", '--output', 'json') 'list service principals'

if ($spList -and @($spList).Count -gt 0) {
    $sp = @($spList)[0]
    Write-Host "  Already exists, reusing. objectId $($sp.id)" -ForegroundColor DarkYellow
}
else {
    $sp = Invoke-AzJson @('ad', 'sp', 'create', '--id', $AppId, '--output', 'json') 'create service principal'
    Write-Host "  Created. objectId $($sp.id)" -ForegroundColor Green
    # Entra needs a moment before the new principal is visible to role assignment.
    Start-Sleep -Seconds 15
}
$SpObjectId = $sp.id

# --- federated credentials -------------------------------------------------
Write-Step "Federated credentials (entity type: Environment)"
$currentCreds = Invoke-AzJson @('ad', 'app', 'federated-credential', 'list', '--id', $AppId, '--output', 'json') 'list federated credentials'
$currentSubjects = @()
if ($currentCreds) { $currentSubjects = @($currentCreds | ForEach-Object { $_.subject }) }

# GitHub emits one of TWO subject formats depending on how the organisation has
# configured its OIDC subject claim:
#
#   classic    repo:<org>/<repo>:environment:<env>
#   immutable  repo:<org>@<orgId>/<repo>@<repoId>:environment:<env>
#
# The second embeds the numeric organisation and repository IDs -- this is what
# the Azure portal's "Organization ID" and "Repository ID" fields are for. Which
# one an org emits is not discoverable ahead of time, and presenting the wrong
# one fails with AADSTS700213 "No matching federated identity record found".
#
# Registering both costs nothing (an unmatched credential is inert, and Entra
# allows up to 20 per app) and means this script works against Baytex's tenant
# without first knowing how their org is configured.
$subjectForms = @()
foreach ($envName in $GitHubEnvNames) {
    $subjectForms += [pscustomobject]@{
        Subject = "repo:$GitHubOrg/$($GitHubRepo):environment:$envName"
        Name    = "github-$GitHubOrg-$GitHubRepo-env-$envName"
        Env     = $envName
        Form    = 'classic'
    }
    if ($GitHubOrgId -notmatch 'unresolved' -and $GitHubRepoId -notmatch 'unresolved') {
        $subjectForms += [pscustomobject]@{
            Subject = "repo:$GitHubOrg@$GitHubOrgId/$GitHubRepo@$($GitHubRepoId):environment:$envName"
            Name    = "github-$GitHubOrg-$GitHubRepo-env-$envName-ids"
            Env     = $envName
            Form    = 'immutable'
        }
    }
}

foreach ($form in $subjectForms) {
    $subject = $form.Subject
    $credName = $form.Name
    $envName = $form.Env

    if ($currentSubjects -contains $subject) {
        Write-Host "  [skip]   ($($form.Form)) $subject" -ForegroundColor DarkYellow
        continue
    }

    $body = [ordered]@{
        name        = $credName
        issuer      = $Issuer
        subject     = $subject
        description = "GitHub Actions OIDC ($($form.Form) subject) for $GitHubOrg/$GitHubRepo environment '$envName' (org id $GitHubOrgId, repo id $GitHubRepoId)"
        audiences   = @($Audience)
    }

    # az on Windows mangles inline JSON, so hand it a file instead.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "fedcred-$credName-$([guid]::NewGuid().ToString('N')).json"
    ($body | ConvertTo-Json -Depth 5) | Set-Content -Path $tmp -Encoding utf8

    try {
        Invoke-Az @('ad', 'app', 'federated-credential', 'create', '--id', $AppId,
            '--parameters', "@$tmp", '--output', 'none') "create federated credential $credName" | Out-Null
        Write-Host "  [create] ($($form.Form)) $subject" -ForegroundColor Green
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# --- role assignments ------------------------------------------------------
Write-Step "Azure role assignments on $Scope"
if ($UseOwnerRole) {
    $roles = @('Owner')
}
else {
    # Contributor builds the platform. User Access Administrator is required
    # specifically for the Storage Blob Data Contributor grant to the Databricks
    # Access Connector -- Contributor alone cannot write role assignments.
    $roles = @('Contributor', 'User Access Administrator')
}

# Storage Blob Data Contributor is a DATA-plane role: neither Owner nor
# Contributor grants access to blob CONTENT. The azurerm backend runs with
# use_azuread_auth = true, so without this the pipeline identity cannot read or
# write its own Terraform state -- "terraform init" fails with 403 on the state
# blob even though the principal can see the storage account itself.
$roles += 'Storage Blob Data Contributor'

$assigned = Invoke-AzJson @('role', 'assignment', 'list', '--assignee', $SpObjectId,
    '--scope', $Scope, '--output', 'json') 'list role assignments'
$assignedRoles = @()
if ($assigned) { $assignedRoles = @($assigned | ForEach-Object { $_.roleDefinitionName }) }

foreach ($role in $roles) {
    if ($assignedRoles -contains $role) {
        Write-Host "  [skip]   $role" -ForegroundColor DarkYellow
        continue
    }
    Invoke-Az @('role', 'assignment', 'create', '--assignee-object-id', $SpObjectId,
        '--assignee-principal-type', 'ServicePrincipal', '--role', $role,
        '--scope', $Scope, '--output', 'none') "assign $role" | Out-Null
    Write-Host "  [create] $role" -ForegroundColor Green
}

# --- summary ---------------------------------------------------------------
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " $Environment -- GitHub Environment variables" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Set these on BOTH '$($GitHubEnvNames[0])' and '$($GitHubEnvNames[1])':"
Write-Host ""
Write-Host "  AZURE_CLIENT_ID        = $AppId"
Write-Host "  AZURE_TENANT_ID        = $TenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID  = $SubscriptionId"
Write-Host ""
Write-Host "App display name : $AppName"
Write-Host "SP object ID     : $SpObjectId"
Write-Host ""
Write-Host "NEXT (manual, cannot be scripted):" -ForegroundColor Yellow
Write-Host "  Add '$AppName' as an ACCOUNT ADMIN in the Azure Databricks account" -ForegroundColor Yellow
Write-Host "  console (accounts.azuredatabricks.net -> User management -> Service" -ForegroundColor Yellow
Write-Host "  principals). Without it, module.ncc fails: creating a Network" -ForegroundColor Yellow
Write-Host "  Connectivity Config requires Databricks account-admin rights." -ForegroundColor Yellow
Write-Host ""
