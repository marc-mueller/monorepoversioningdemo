# Define the path to the versioning script dynamically based on the script location
$versioningScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "VersionComponent.ps1"

# Initialize a new Git repository
function Initialize-Repository {
    git init TestRepo
    Set-Location TestRepo
    Add-Content -Path ".gitignore" -Value "!.gitignore"
    git add .gitignore
    git commit -m "Initial commit"
    @("ComponentA", "ComponentB", "ComponentC") | ForEach-Object { New-Item -ItemType Directory -Name $_ }
    Write-Host "Repository initialized with components: ComponentA, ComponentB, ComponentC"
}

# Perform a commit affecting a single or multiple components
function Commit-Changes {
    param (
        [string]$CommitMessage,
        [array]$Components
    )

    $filePaths = $Components | ForEach-Object {
        $filePath = Join-Path $_ "file.txt"
        Add-Content -Path $filePath -Value $CommitMessage
        $filePath
    }

    git add $filePaths
    git commit -m "$CommitMessage"
}

# Get the calculated version for a component
function Get-CalculatedVersion {
    param (
        [string]$ComponentName
    )
    return & $versioningScriptPath -ComponentName $ComponentName -CreateTag $false
}

# Validate the calculated version with the expected version
function Validate-Version {
    param (
        [string]$ComponentName,
        [string]$ExpectedVersion
    )

    $calculatedVersion = Get-CalculatedVersion -ComponentName $ComponentName
    if ($calculatedVersion -eq $ExpectedVersion) {
        Write-Host "PASS: $ComponentName expected version $ExpectedVersion matches calculated version $calculatedVersion"
    } else {
        Write-Error "FAIL: $ComponentName expected version $ExpectedVersion does NOT match calculated version $calculatedVersion"
    }
}

# Test steps
function Run-Tests {
    # Step 1: Initial commits for components
    Commit-Changes -CommitMessage "Initial commit for component A +semver: minor" -Components @("ComponentA")
    Commit-Changes -CommitMessage "Initial commit for component B +semver: minor" -Components @("ComponentB")
    Commit-Changes -CommitMessage "Initial commit for component C" -Components @("ComponentC")

    Validate-Version -ComponentName "ComponentA" -ExpectedVersion "0.1.0"
    Validate-Version -ComponentName "ComponentB" -ExpectedVersion "0.1.0"
    Validate-Version -ComponentName "ComponentC" -ExpectedVersion "0.0.1"

    # Step 2: Incremental updates
    Commit-Changes -CommitMessage "Feature added to component A +semver: minor" -Components @("ComponentA")
    Commit-Changes -CommitMessage "Bug fix in component B +semver: patch" -Components @("ComponentB")

    Validate-Version -ComponentName "ComponentA" -ExpectedVersion "0.2.0"
    Validate-Version -ComponentName "ComponentB" -ExpectedVersion "0.1.1"

    # Step 3: Shared commit affecting multiple components
    Commit-Changes -CommitMessage "Update affecting component A and component B +semver: minor" -Components @("ComponentA", "ComponentB")

    Validate-Version -ComponentName "ComponentA" -ExpectedVersion "0.3.0"
    Validate-Version -ComponentName "ComponentB" -ExpectedVersion "0.2.0"

    # Step 4: Non-versioned update
    Commit-Changes -CommitMessage "Non-versioned update to component C" -Components @("ComponentC")

    Validate-Version -ComponentName "ComponentC" -ExpectedVersion "0.0.2"

    # Step 5: Global update affecting all components
    Commit-Changes -CommitMessage "Global update affecting all components +semver: major" -Components @("ComponentA", "ComponentB", "ComponentC")

    Validate-Version -ComponentName "ComponentA" -ExpectedVersion "1.0.0"
    Validate-Version -ComponentName "ComponentB" -ExpectedVersion "1.0.0"
    Validate-Version -ComponentName "ComponentC" -ExpectedVersion "1.0.0"

    # Step 6: Feature branch versioning
    git checkout -b feature/myfeature
    Commit-Changes -CommitMessage "Feature branch commit for component A +semver: minor" -Components @("ComponentA")
    Validate-Version -ComponentName "ComponentA" -ExpectedVersion "1.1.0-feature0001"

    # Step 7: Hotfix branch versioning
    git checkout main
    git checkout -b hotfix/myhotfix
    Commit-Changes -CommitMessage "Hotfix branch commit for component B +semver: patch" -Components @("ComponentB")
    Validate-Version -ComponentName "ComponentB" -ExpectedVersion "1.0.1-hotfix0001"

    # Step 8: Pull request branch versioning
    git checkout main
    git checkout -b pullrequest/mypullrequest
    Commit-Changes -CommitMessage "Pull request branch commit for component C +semver: minor" -Components @("ComponentC")
    Validate-Version -ComponentName "ComponentC" -ExpectedVersion "1.1.0-pullreq0001"
}

# Main execution
Initialize-Repository
Run-Tests
