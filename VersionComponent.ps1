param (
    [Parameter(Mandatory = $true)]
    [string]$ComponentName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("major", "minor", "patch")]
    [string]$DefaultIncrement = "patch",

    [Parameter(Mandatory = $false)]
    [bool]$CreateTag = $false,

    [Parameter(Mandatory = $false)]
    [bool]$VerboseOutput = $false
)

# Function to parse version increment from a commit message
function Get-VersionIncrement {
    param ($CommitMessage, $DefaultIncrement)
    if ($CommitMessage -match '\+semver:\s*(major|minor|patch)') {
        return $matches[1]
    }
    return $DefaultIncrement
}

# Fetch the latest tags
git fetch --tags

# Get the latest tag for the component
$latestTag = git tag --list "$ComponentName-v*" | Sort-Object -Descending | Select-Object -First 1

if (-not $latestTag) {
    if ($VerboseOutput){
        Write-Host "No existing tags found for $ComponentName. Starting with version 0.0.0."
    }
    $version = [version]"0.0.0"
    # Set baseline to the initial commit
    $baselineCommit = (git rev-list --max-parents=0 HEAD).Trim()
} else {
    # Extract version number from tag
    if ($latestTag -match "$ComponentName-v(\d+\.\d+\.\d+)") {
        $version = [version]$matches[1]
        # Get the commit where the latest tag is pointing
        $baselineCommit = (git rev-list -n 1 $latestTag).Trim()
    } else {
        Write-Error "Failed to parse version from tag: $latestTag"
        exit 1
    }
}

# Get commit messages affecting the component's directory since the baseline commit
$logOutput = git log "$baselineCommit..HEAD" -- $ComponentName --pretty=fuller | Out-String
$commitMessages = $logOutput -split "(?=commit\s[0-9a-f]{40})" | Where-Object { $_ -ne "" }

if (-not $commitMessages) {
    if ($VerboseOutput){
        Write-Host "No new commits affecting $ComponentName since the last tag."
        Write-Host "Current version: $version"
    }
    Write-Output $version
    exit 0
}

# Initialize version components
$newMajor = $version.Major
$newMinor = $version.Minor
$newPatch = $version.Build

# Determine version increments
foreach ($msg in $commitMessages) {
    $increment = Get-VersionIncrement $msg $DefaultIncrement
    switch ($increment) {
        "major" {
            $newMajor++
            $newMinor = 0
            $newPatch = 0
        }
        "minor" {
            $newMinor++
            $newPatch = 0
        }
        "patch" {
            $newPatch++
        }
    }
}

# Create new version object
$newVersion = [version]::new($newMajor, $newMinor, $newPatch)

# Conditionally create and push new tag
if ($CreateTag) {
    $newTag = "$ComponentName-v$newVersion"
    git tag $newTag
    git push origin $newTag
    if ($VerboseOutput){
      Write-Host "Tagged $ComponentName with new version: $newTag"
    }
} else {
    if ($VerboseOutput){
        Write-Host "New version for $($ComponentName): $newVersion (tagging skipped)"
    }
}

Write-Output $newVersion
