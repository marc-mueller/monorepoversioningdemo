# Define the path to the versioning script
$versioningScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "VersionComponent.ps1"

# Initialize a new Git repository
git init TestRepo5
Set-Location TestRepo5

Add-Content -Path ".gitignore" -Value "!.gitignore"
git add .gitignore
git commit -m "Initial commit"

# Create component directories
@("ComponentA", "ComponentB", "ComponentC") | ForEach-Object { New-Item -ItemType Directory -Name $_ }

# Helper method to modify files in a component
function Modify-ComponentFile {
    param (
        [string]$Component,
        [string]$Content
    )
    $filePath = Join-Path $Component "file.txt"
    Add-Content -Path $filePath -Value $Content
    return $filePath
}

# Helper method to commit changes
function Commit-Changes {
    param (
        [array]$FilePaths,
        [string]$CommitMessage
    )
    git add $FilePaths
    git commit -m "$CommitMessage"
}

# Helper method to get the current version of a component
function Get-ComponentVersion {
    param (
        [string]$Component,
        [bool]$CreateTag = $false
    )
    return &$versioningScriptPath -ComponentName $Component -CreateTag $CreateTag
}

# Helper method to report the version of all components
function Report-AllVersions {
    param (
        [array]$Components
    )
    foreach ($component in $Components) {
        $version = Get-ComponentVersion -Component $component
        $latestTag = git tag --list "$component-v*" | Sort-Object -Descending | Select-Object -First 1
        Write-Host "Component:        $component"
        Write-Host "Current Version:  $version"
        Write-Host "Latest Tag:       $latestTag"
        Write-Host ""
    }
}

# Test Case 1: Initial commit for each component
function TestCase-InitialCommits {
    Write-Host "Running Test Case: Initial Commits"
    @(
        @{ Component = "ComponentA"; Message = "Initial commit for ComponentA +semver: minor"; ExpectedVersion = "0.1.0" },
        @{ Component = "ComponentB"; Message = "Initial commit for ComponentB +semver: minor"; ExpectedVersion = "0.1.0" },
        @{ Component = "ComponentC"; Message = "Initial commit for ComponentC"; ExpectedVersion = "0.0.1" }
    ) | ForEach-Object {
        $filePath = Modify-ComponentFile -Component $_.Component -Content $_.Message
        Commit-Changes -FilePaths $filePath -CommitMessage $_.Message
        $version = Get-ComponentVersion -Component $_.Component -CreateTag $false
        Write-Host "Component:        $($_.Component)"
        Write-Host "Expected Version: $($_.ExpectedVersion)"
        Write-Host "Actual Version:   $version"
        Write-Host ""
    }
}

# Test Case 2: Updates with specific version bumps
function TestCase-ComponentUpdates {
    Write-Host "Running Test Case: Component Updates"
    @(
        @{ Component = "ComponentA"; Message = "Feature added to ComponentA +semver: minor"; ExpectedVersion = "0.2.0" },
        @{ Component = "ComponentB"; Message = "Bug fix in ComponentB +semver: patch"; ExpectedVersion = "0.1.1" }
    ) | ForEach-Object {
        $filePath = Modify-ComponentFile -Component $_.Component -Content $_.Message
        Commit-Changes -FilePaths $filePath -CommitMessage $_.Message
        $version = Get-ComponentVersion -Component $_.Component -CreateTag $false
        Write-Host "Component:        $($_.Component)"
        Write-Host "Expected Version: $($_.ExpectedVersion)"
        Write-Host "Actual Version:   $version"
        Write-Host ""
    }
}

# Test Case 3: Shared commit affecting multiple components
function TestCase-MultiComponentCommit {
    Write-Host "Running Test Case: Multi-Component Commit"

    # Modify files for both components and collect their paths
    $fileA = Modify-ComponentFile -Component "ComponentA" -Content "Update affecting ComponentA"
    $fileB = Modify-ComponentFile -Component "ComponentB" -Content "Update affecting ComponentB"
    $filePaths = @($fileA, $fileB)

    # Commit the changes with a shared message
    Commit-Changes -FilePaths $filePaths -CommitMessage "Update affecting ComponentA and ComponentB +semver: minor"

    # Get and display versions for both components
    @("ComponentA", "ComponentB") | ForEach-Object {
        $version = Get-ComponentVersion -Component $_ -CreateTag $false
        Write-Host "Component:        $_"
        Write-Host "Actual Version:   $version"
        Write-Host ""
    }
}


# Test Case 4: Non-versioned update
function TestCase-NonVersionedUpdate {
    Write-Host "Running Test Case: Non-Versioned Update"
    $filePath = Modify-ComponentFile -Component "ComponentC" -Content "Non-versioned update to ComponentC"
    Commit-Changes -FilePaths $filePath -CommitMessage "Non-versioned update to ComponentC"
    $version = Get-ComponentVersion -Component "ComponentC" -CreateTag $true
    Write-Host "Component:        ComponentC"
    Write-Host "Actual Version:   $version"
    Write-Host ""
}

# Test Case 5: Global commit affecting all components
function TestCase-GlobalUpdate {
    Write-Host "Running Test Case: Global Update"
    $filePaths = @("ComponentA", "ComponentB", "ComponentC") | ForEach-Object {
        Modify-ComponentFile -Component $_ -Content "Global update"
    }
    Commit-Changes -FilePaths $filePaths -CommitMessage "Global update affecting all components +semver: major"

    @("ComponentA", "ComponentB", "ComponentC") | ForEach-Object {
        $version = Get-ComponentVersion -Component $_ -CreateTag $false
        Write-Host "Component:        $_"
        Write-Host "Actual Version:   $version"
        Write-Host ""
    }
}

# Run test cases
TestCase-InitialCommits
TestCase-ComponentUpdates
TestCase-MultiComponentCommit
TestCase-NonVersionedUpdate
TestCase-GlobalUpdate

# Report final versions of all components
Write-Host "Final Versions of All Components"
Report-AllVersions -Components @("ComponentA", "ComponentB", "ComponentC")
