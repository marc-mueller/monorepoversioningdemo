param (
    [Parameter(Mandatory = $true)]
    [string]$ComponentName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("major", "minor", "patch")]
    [string]$DefaultIncrement = "patch",

    [Parameter(Mandatory = $false)]
    [bool]$CreateTag = $false,

    [Parameter(Mandatory = $false)]
    [bool]$VerboseOutput = $false,

    [Parameter(Mandatory = $false)]
    [string]$TargetBranch = "HEAD"
)

# Function to parse version increment from a commit message
function Get-VersionIncrement {
    param ($CommitMessage, $DefaultIncrement)
    if ($CommitMessage -match '\+semver:\s*(major|minor|patch)') {
        return $matches[1]
    }
    return $DefaultIncrement
}

# Function to extract and parse version from a tag
function Parse-VersionFromTag {
    param ($Tag)
    if ($Tag -match "$ComponentName-v(\d+)\.(\d+)\.(\d+)") {
        return [version]::new($matches[1], $matches[2], $matches[3])
    } else {
        Write-Error "Failed to parse version from tag: $Tag"
        exit 1
    }
}

# Function to get the branch name
function Get-BranchName {
    $branchName = git rev-parse --abbrev-ref HEAD
    if ($branchName -eq "HEAD") {
        $branchName = git name-rev --name-only HEAD
    }
    return $branchName
}

# Function to get the baseline commit from the main branch
function Get-BaselineCommit {
    $branchName = Get-BranchName
    $mergeBase = git merge-base main $branchName
    return $mergeBase
}

# Function to get the commit count in the branch
function Get-CommitCount {
    $branchName = Get-BranchName
    $commitCount = git rev-list --count $branchName ^main
    return $commitCount
}

# Function to get the highest semver+ increment definition in a branch
function Get-HighestSemverIncrement {
    param ($CommitMessages)
    $increments = $CommitMessages | ForEach-Object { Get-VersionIncrement $_ $null }
    $highestIncrement = $increments | Sort-Object -Property { switch ($_){ "major" {3} "minor" {2} "patch" {1} default {0} } } -Descending | Select-Object -First 1
    return $highestIncrement
}

# Function to get the latest version of the base branch
function Get-LatestBaseBranchVersion {
    $baseBranchTag = git tag --list "main-v*" | 
        ForEach-Object {
            if ($_ -match "main-v(\d+)\.(\d+)\.(\d+)") {
                [PSCustomObject]@{
                    Tag     = $_
                    Major   = [int]$matches[1]
                    Minor   = [int]$matches[2]
                    Patch   = [int]$matches[3]
                }
            }
        } | Sort-Object -Property Major, Minor, Patch -Descending |
        Select-Object -First 1

    if (-not $baseBranchTag) {
        return [version]::new(0, 0, 0)
    } else {
        return Parse-VersionFromTag $baseBranchTag.Tag
    }
}

# Function to get the latest version of a branch
function Get-LatestBranchVersion {
    param ($BranchName)
    $branchTag = git tag --list "$ComponentName-v*" | 
        ForEach-Object {
            if ($_ -match "$ComponentName-v(\d+)\.(\d+)\.(\d+)") {
                [PSCustomObject]@{
                    Tag     = $_
                    Major   = [int]$matches[1]
                    Minor   = [int]$matches[2]
                    Patch   = [int]$matches[3]
                }
            }
        } | Sort-Object -Property Major, Minor, Patch -Descending |
        Select-Object -First 1

    if (-not $branchTag) {
        return [version]::new(0, 0, 0)
    } else {
        return Parse-VersionFromTag $branchTag.Tag
    }
}

# Function to calculate the version for a given branch
function Calculate-Version {
    param (
        [string]$BranchName,
        [string]$ComponentName,
        [string]$DefaultIncrement,
        [bool]$VerboseOutput
    )

    # Fetch the latest tags
    git fetch --tags 2>&1 | Out-Null

    # Get the latest tag for the component
    $latestTag = git tag --list "$ComponentName-v*" | 
        ForEach-Object {
            if ($_ -match "$ComponentName-v(\d+)\.(\d+)\.(\d+)") {
                # Extract the version parts for sorting
                [PSCustomObject]@{
                    Tag     = $_
                    Major   = [int]$matches[1]
                    Minor   = [int]$matches[2]
                    Patch   = [int]$matches[3]
                }
            }
        } | Sort-Object -Property Major, Minor, Patch -Descending |
        Select-Object -First 1

    if (-not $latestTag) {
        if ($VerboseOutput) {
            Write-Host "No existing tags found for $ComponentName. Starting with version 0.0.0."
        }
        $version = [version]::new(0, 0, 0)
        # Set baseline to the initial commit
        $baselineCommit = (git rev-list --max-parents=0 HEAD).Trim()
    } else {
        $version = Parse-VersionFromTag $latestTag
        # Get the commit where the latest tag is pointing
        $baselineCommit = (git rev-list -n 1 $latestTag).Trim()
    }

    # Get commit messages affecting the component's directory since the baseline commit
    $logOutput = git log "$baselineCommit..$BranchName" -- $ComponentName --pretty=format:"%B" | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to retrieve git log. Ensure the component path and git history are valid."
        exit 1
    }

    $commitMessages = @($logOutput -split "(?=commit\s[0-9a-f]{40})" | Where-Object { $_ -ne "" })
    $commitMessages = $commitMessages[-1..-($commitMessages.Count)]

    if (-not $commitMessages) {
        if ($VerboseOutput) {
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
    $highestIncrement = Get-HighestSemverIncrement $commitMessages

    foreach ($msg in $commitMessages) {
        $increment = Get-VersionIncrement $msg $DefaultIncrement
        if ($VerboseOutput) {
            Write-Host "Processing commit for $($ComponentName): $msg"
            Write-Host "Increment parsed: $increment"
        }
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

    # Validate SemVer compliance
    if (-not $newVersion) {
        Write-Error "Invalid version calculated: $newVersion. Aborting."
        exit 1
    }

    Write-Output $newVersion
}

# Main logic
$branchName = Get-BranchName

if ($branchName -match "^(feature|topic|task|hotfix)/") {
    # Calculate the baseline version for the feature branch
    $baseBranchVersion = Calculate-Version -BranchName "main" -ComponentName $ComponentName -DefaultIncrement $DefaultIncrement -VerboseOutput $VerboseOutput

    $newMajor = $baseBranchVersion.Major
    $newMinor = $baseBranchVersion.Minor
    $newPatch = $baseBranchVersion.Build

    $commitCount = Get-CommitCount

    switch ($highestIncrement) {
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

    switch -regex ($branchName) {
        "feature/.*" { $DefaultIncrement = "minor" }
        "topic/.*" { $DefaultIncrement = "minor" }
        "task/.*" { $DefaultIncrement = "minor" }
        "hotfix/.*" { $DefaultIncrement = "patch" }
    }
    $increment = $highestIncrement
    if (-not $increment) {
        $increment = $DefaultIncrement
    }
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
    $branchSuffix = $branchName -replace "^(feature|topic|task|hotfix)/", ""
    $branchSuffix = $branchSuffix.Substring(0, [Math]::Min($branchSuffix.Length, 10))
    $preReleaseVersion = "$newMajor.$newMinor.$newPatch-$branchSuffix$(([int]$commitCount).ToString("D4"))"
    Write-Output $preReleaseVersion
    exit 0
} else {
    $newVersion = Calculate-Version -BranchName $branchName -ComponentName $ComponentName -DefaultIncrement $DefaultIncrement -VerboseOutput $VerboseOutput

    # Conditionally create and push new tag
    if ($CreateTag) {
        $newTag = "$ComponentName-v$newVersion"
        git tag $newTag 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create tag: $newTag. Ensure you have proper permissions."
            exit 1
        }
        git push origin $newTag 2>&1 | Out-Null
        if ($VerboseOutput) {
            Write-Host "Tagged $ComponentName with new version: $newTag"
        }
    } else {
        if ($VerboseOutput) {
            Write-Host "New version for $($ComponentName): $newVersion (tagging skipped)"
        }
    }

    Write-Output $newVersion
}
