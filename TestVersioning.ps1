# Define the path to the versioning script
$versioningScriptPath = "C:\Temp\MonorepoVersioning\VersionComponent.ps1"

# Initialize a new Git repository
git init TestRepo5
Set-Location TestRepo5

Add-Content -Path ".gitignore" -Value "!.gitignore"
git add .gitignore
git commit -m "Initial commit"

# Create component directories
@("ComponentA", "ComponentB", "ComponentC") | ForEach-Object { New-Item -ItemType Directory -Name $_ }

# Function to perform a commit and run the versioning script
function Commit-And-Version {
    param (
        [string]$Component,
        [string]$Message,
        [string]$ExpectedVersion
    )

    # Create or modify a file in the component directory
    $filePath = Join-Path $Component "file.txt"
    Add-Content -Path $filePath -Value $Message

    # Stage and commit the change
    git add $filePath
    git commit -m "$Message"

    # Run the versioning script
    $version = &$versioningScriptPath -ComponentName $Component -CreateTag $true

    # Retrieve the latest tag for the component
    $latestTag = git tag --list "$Component-v*" | Sort-Object -Descending | Select-Object -First 1

    # Display the current and expected versions
    Write-Host "Component:        $Component"
    Write-Host "Expected Version: $ExpectedVersion"
    Write-Host "Actual Version:   $version"
    Write-Host "Latest tag:       $latestTag"
    Write-Host ""
}

# Test scenarios
Commit-And-Version -Component "ComponentA" -Message "Initial commit for ComponentA +semver: minor" -ExpectedVersion "ComponentA-v0.1.0"
Commit-And-Version -Component "ComponentB" -Message "Initial commit for ComponentB +semver: minor" -ExpectedVersion "ComponentB-v0.1.0"
Commit-And-Version -Component "ComponentC" -Message "Initial commit for ComponentC" -ExpectedVersion "ComponentC-v0.0.1"

Commit-And-Version -Component "ComponentA" -Message "Feature added to ComponentA +semver: minor" -ExpectedVersion "ComponentA-v0.2.0"
Commit-And-Version -Component "ComponentB" -Message "Bug fix in ComponentB +semver: patch" -ExpectedVersion "ComponentB-v0.1.1"

# Commit affecting multiple components
Add-Content -Path "ComponentA\file.txt" -Value "Update affecting ComponentA"
Add-Content -Path "ComponentB\file.txt" -Value "Update affecting ComponentB"
git add ComponentA\file.txt ComponentB\file.txt
git commit -m "Update affecting ComponentA and ComponentB +semver: minor"
$versionComponentA = & $versioningScriptPath -ComponentName "ComponentA" -CreateTag $true
$versionComponentB = & $versioningScriptPath -ComponentName "ComponentB" -CreateTag $true
Write-Host "Component: ComponentA"
Write-Host "Expected Version: ComponentA-v0.3.0"
Write-Host "Actual Version:   $($versionComponentA)"
Write-Host "Latest Tag:       $(git tag --list 'ComponentA-v*' | Sort-Object -Descending | Select-Object -First 1)"
Write-Host ""
Write-Host "Component: ComponentB"
Write-Host "Expected Version: ComponentB-v0.2.1"
Write-Host "Actual Version:   $($versionComponentB)"
Write-Host "Latest Tag:       $(git tag --list 'ComponentB-v*' | Sort-Object -Descending | Select-Object -First 1)"
Write-Host ""

# Commit without version tag
Commit-And-Version -Component "ComponentC" -Message "Non-versioned update to ComponentC" -ExpectedVersion "ComponentC-v0.0.2"

# Commit affecting all components
@("ComponentA", "ComponentB", "ComponentC") | ForEach-Object {
    Add-Content -Path "$_\file.txt" -Value "Global update"
    git add "$_\file.txt"
}
git commit -m "Global update affecting all components +semver: major"
@("ComponentA", "ComponentB", "ComponentC") | ForEach-Object {
    $actualVersion = & $versioningScriptPath -ComponentName $_ -CreateTag $true
    Write-Host "Component:        $_"
    Write-Host "Expected Version: $_-v1.0.0"
    Write-Host "Actual Version:   $($actualVersion)"
    Write-Host "Latest TAg:       $(git tag --list "$_-v*" | Sort-Object -Descending | Select-Object -First 1)"
    Write-Host ""
}
