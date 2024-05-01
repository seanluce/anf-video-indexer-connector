# Azure NetApp Files - Azure AI Video Indexer Connector, created by Sean Luce, Azure NetApp Files PG
# This script is a PowerShell script that allows you to connect Azure NetApp Files to Azure AI Video Indexer.
# The script allows you to search for video files on your local machine, send them to Azure AI Video Indexer for processing, check the status of the processing, and save the JSON data for the processed videos.
# The script uses the Azure AI Video Indexer API to send and retrieve data. You will need an API token to use the script.
# The script is designed to be run in the PowerShell ISE or Visual Studio Code, but can be run in the PowerShell console as well.
# The script is designed to be run on Windows, but can be run on other operating systems with some modifications.

$Global:baseUri = 'https://api.videoindexer.ai/'
$Global:accessToken = ''
$Global:videoIndexerLocation = ''
$Global:videoIndexerAccountId = ''

$Global:prefix = ''

$Global:uploadedVideos = @{}

# Get-VideoIndexerAccounts
function Select-VideoIndexerAccount {}

function Enter-SearchPaths {
    param(
        [string[]]$searchPaths
    )
    while ($searchPathSelection -ne 9) {
        write-host ""
        Write-host "Examples of search paths:"
        write-host ""
        write-host "C:\Users\Alexandria\Downloads (will NOT include subdirectories)"
        write-host "Z:\Videos (will NOT include subdirectories)"
        write-host "Z:\Movies\2024\* (WILL include subdirectories)"
        if ($searchPaths) {
            write-host ""
            write-host "Current search paths:"
            write-host ""
            $searchPaths | ForEach-Object {
                write-host $_
            }
        }
        write-host ""
        write-host "1. Add search path"
        write-host "2. Clear search paths"
        write-host "9. Return to main menu"
        write-host ""
        $searchPathSelection = Read-Host -Prompt "Enter selection"
        switch ($searchPathSelection) {
            1 {
                write-host""
                $searchPaths += Read-Host -Prompt "Enter search path"
            }
            2 {
                $searchPaths = @()
            }
            9 {
                return $searchPaths
            }
            default {
                write-host "Invalid selection"
            }
        }
    }
}

# Search-VideoFiles
function Search-VideoFiles {
    param(
        [string[]]$searchPaths
    )
    #$searchPaths = @("C:\Users\b-sluce\Downloads","C:\Users\b-sluce\Videos")
    $videoFilePaths = @()

    $searchPaths | ForEach-Object {
        $searchPath = $_
        if (-not (Test-Path $searchPath)) {
            write-host "Path" $searchPath "does not exist."
            return $videoFilePaths
        } elseif ($searchPath.EndsWith('*')) {
            Get-ChildItem -Path $searchPath -Recurse -Include *.mp4, *.mov, *.wmv, *.avi -ErrorAction SilentlyContinue | ForEach-Object {
                $videoFilePaths += $_
            }
        } else {
            Get-ChildItem -Path $searchPath -Include *.mp4, *.mov, *.wmv, *.avi -ErrorAction SilentlyContinue | ForEach-Object {
                $videoFilePaths += $_
            }
        }
    }
    return $videoFilePaths
}

function Test-VideoIndexerToken {
    $uri = $baseUri + $videoIndexerLocation + '/Accounts/' + $videoIndexerAccountId + '/Videos?accessToken=' + $accessToken
    try {
        $null = Invoke-RestMethod -Uri $uri -Method Get
    }
    catch {
        if ($_ -like "*TOKEN*") {
            #write-host $_
            write-host ""
            write-host -foreground red "Your Azure AI Video Indexer API token has expired."
            write-host ""
            $Global:accessToken = read-host "Paste new API token here and press enter"
        }
    }
}

function Send-Videos {
    param(
        [array[]]$videoFiles
    )
    Test-VideoIndexerToken
    write-host ""
    $videoFiles | ForEach-Object {
        $newVideoUpload = @{}
        $videoFile = $_
        $encodedFileName = [System.Web.HttpUtility]::UrlEncode($videoFile.Name)
        write-host "Sending" $videoFile.Path "to Azure AI Video Indexer for processing..."
        $uri = $baseUri + $videoIndexerLocation + '/Accounts/' + $videoIndexerAccountId + '/Videos?accessToken=' + $accessToken + '&name=' + $prefix + $encodedFileName + '&privacy=public'
        $body = @{
            "file" = Get-Item -Path $videoFile.Path
        }
        $result = Invoke-RestMethod -Uri $uri -Method Post -ContentType "multipart/form-data" -Form $body
        $newVideoUpload = @{
            id = $result.id
            localPath = $videoFile.Path
            state = "Processing"
            url = ""
        }
        $Global:uploadedVideos.Add($result.id, $newVideoUpload)
    }
}

function Get-VideoIndexProgress {
    param(
        [hashtable[]]$videoIds,
        [bool]$displayResults
    )
    Test-VideoIndexerToken
    foreach ($videoId in $videoIds.Keys) {
        $uri = $baseUri + $videoIndexerLocation + '/Accounts/' + $videoIndexerAccountId + '/Videos/' + $videoId + '/Index?accessToken=' + $accessToken
        $result = Invoke-RestMethod -Uri $uri -Method Get
        if ($result.state -eq "Processing") {
            $progressAsString = ($result.videos[0].processingProgress).Substring(0, ($result.videos[0].processingProgress).Length - 1)
            $progressAsInt = [int]$progressAsString
            if ($progressAsInt -eq 100) {
                $progressAsInt = 99
            }
            $Global:uploadedVideos[$videoId].indexProgress = $progressAsInt
            $Global:uploadedVideos[$videoId].state = "Processing"
        }
        if ($result.state -eq "Processed") {
            $Global:uploadedVideos[$videoId].indexProgress = 100
            $Global:uploadedVideos[$videoId].state = "Processed"
            $Global:uploadedVideos[$videoId].url = $result.videos[0].url
        }
    }
    if ($displayResults) {
        foreach ($videoId in $videoIds.Keys) {
            Write-Host -foreground green $Global:uploadedVideos[$videoId].localPath
            write-host '      Indexing status:'$Global:uploadedVideos[$videoId].state '-'$Global:uploadedVideos[$videoId].indexProgress'% complete' 
            Write-Host ""
        }
    }
}

# Save-VideoIndexJson
function Save-VideoIndexJson {
    param(
        [hashtable[]]$videoIds,
        [string]$includeSummarizedInsights
    )
    Test-VideoIndexerToken
    $readyForDownload = @()
    Get-VideoIndexProgress -videoIds $videoIds -displayResults $false
    write-host $Global:uploadedVideos
    foreach ($videoId in $Global:uploadedVideos.Keys) {
        write-host $videoId ' ' $Global:uploadedVideos[$videoId].state
        if ($Global:uploadedVideos[$videoId].state -eq "Processed") {
            $readyForDownload += $videoId
        }
    }
    if ($readyForDownload.Count -eq 0) {
        write-host ""
        write-host -foreground red "No video JSON files are ready for download."
        write-host ""
        read-host -prompt "Press any key to return to the main menu."
        return
    }
    foreach ($videoId in $readyForDownload) {
        $uri = $baseUri + $videoIndexerLocation + '/Accounts/' + $videoIndexerAccountId + '/Videos/' + $videoId + '/Index?includeSummarizedInsights=' + $includeSummarizedInsights + '&accessToken=' + $accessToken
        $result = Invoke-RestMethod -Uri $uri -Method Get
        $fileName = $result.id + '.json'
        $result | ConvertTo-Json -depth 100 | Out-File -FilePath $fileName
    }
}

function Show-MainMenu {
    #Clear-Host
    while ($selection -ne 9) {
        Clear-Host
        write-host ""
        write-host -foreground blue "     _    _   _ _____    _    ___  __     _____"
        write-host -foreground green "    / \  | \ | |  ___|  / \  |_ _| \ \   / /_ _|"
        write-host -foreground cyan "   / _ \ |  \| | |_    / _ \  | |   \ \ / / | |" 
        write-host -foreground red "  / ___ \| |\  |  _|  / ___ \ | |    \ V /  | |" 
        write-host -foreground magenta " /_/   \_\_| \_|_|   /_/   \_\___|    \_/  |___|"
        # https://www.asciiart.eu/text-to-ascii-art
        write-host ""
        write-host -foreground green "Welcome to the Azure NetApp Files - Azure AI Video Indexer Connector!"
        write-host -foreground darkgray "  created by Sean Luce, Azure NetApp Files PG"
        write-host ""
        write-host " 1. Select Video Indexer account"
        write-host " 2. Add or reset search paths"
        write-host " 3. Search and select video files"
        write-host " 4. Send selected video files to Azure AI Video Indexer"
        write-host " 5. Check status of video files"
        write-host " 6. Save video index JSON data"
        write-host " 9. Exit"
        write-host ""
        write-host " a. Get status by video ID"
        write-host " b. Update Azure Video Indexer token"
        write-host ""
        
        write-host -foreground blue $selectedVideos.count "videos selected for indexing."
        write-host -foreground yellow $uploadedVideos.count "videos sent for indexing."
        write-host -foreground green $completedVideos.count "videos completed indexing and ready for JSON download."
        write-host ""
        $searchPaths = @("C:\users\b-sluce\Downloads\*")
        if ($searchPaths.count -eq 0) {
            write-host -foreground red "No search paths defined."
            write-host ""
            $defineSeachPathsNow = read-host -prompt "Would you like to define search paths now? Y/n"
            if ($defineSeachPathsNow -eq 'y' -or $defineSeachPathsNow -eq 'Y') {
                $searchPaths = Enter-SearchPaths -searchPaths $searchPaths
                Show-MainMenu
            }
        }
        $selection = Read-Host -Prompt "Enter selection"
    
        switch ($selection) {
            1 {
                Select-VideoIndexerAccount
            }
            2 {
                $searchPaths = Enter-SearchPaths -searchPaths $searchPaths
            }
            3 {
                if ($searchPaths) {
                    $foundVideoFiles = Search-VideoFiles -searchPaths $searchPaths
                    if ($foundVideoFiles) {
                        $selectedVideos = $foundVideoFiles | Select-Object -Property Name, @{Name='Path'; Expression={$_.FullName}}, @{Name='Size (MiB)'; Expression={[math]::round($_.Length/1024/1024)}} | out-gridview -PassThru
                    } else {
                        write-host ""
                        write-host -foreground red "No video files found in the following search paths:"
                        foreach($searchPath in $SearchPaths) {
                            write-host ' '$searchPath
                        }
                        break
                    }     
                } else {
                    write-host ""
                    write-host -foreground red "No search paths have been defined. Please add search paths before searching for video files."
                    break
                }
            }
            4 {
                if ($selectedVideos) {
                    write-host ""
                    write-host -foreground green "The following videos will be sent to Azure AI Video Indexer:"
                    write-host ""
                    foreach ($selectedVideo in $selectedVideos) {
                        write-host ' ' $selectedVideo.Name
                    }
                    write-host ""
                    $continue = read-host "Continue? Y/n"
                    if ($continue -eq 'n') {
                        break
                    } elseif ($continue -eq 'y' -or $continue -eq 'Y') {
                        Send-Videos -videoFiles $selectedVideos
                        $selectedVideos = $null
                    }
                    
                } else {
                    write-host ""
                    write-host -foreground red "No video files have been selected. Nothing to index."
                    break
                }
            }
            5 {
                do {
                    Clear-Host
                    Write-Host ""
                    write-host -foreground blue "     _    _   _ _____    _    ___  __     _____"
                    write-host -foreground green "    / \  | \ | |  ___|  / \  |_ _| \ \   / /_ _|"
                    write-host -foreground cyan "   / _ \ |  \| | |_    / _ \  | |   \ \ / / | |" 
                    write-host -foreground red "  / ___ \| |\  |  _|  / ___ \ | |    \ V /  | |" 
                    write-host -foreground magenta " /_/   \_\_| \_|_|   /_/   \_\___|    \_/  |___|"
                    write-host ""
                    Write-Host "Progress will update every 30 seconds. Press any key to return to the main menu."
                    Write-Host ""
                    Get-VideoIndexProgress -videoIds $uploadedVideos -displayResults $true
                    $completedVideos = @()
                    foreach ($videoId in $Global:uploadedVideos.Keys) {
                        if ($uploadedVideos[$videoId].state -eq "Processed") {
                            $completedVideos += $videoId
                        }
                    }
                    if ($completedVideos.Count -eq $Global:uploadedVideos.Count) {
                        write-host ""
                        write-host "Video indexing complete for all videos. Press any key to return to the main menu."
                        read-host
                        break
                    }
                    Start-Sleep -Seconds 30
                    if ([System.Console]::KeyAvailable) {
                        $keyPressed = $true
                        [void][System.Console]::ReadKey($true)
                        break
                    }
                } until ($keyPressed)
                $progressId = 0
                foreach ($videoId in $indexProgress.Keys) {
                    $progressId++
                    $percentAsString = $indexProgress[$videoId].ToString() + "%"
                    write-host "Cleaning up progress bar for video ID" $videoId $progressId
                    Write-Progress -Activity $videoId -PercentComplete $indexProgress[$videoId] -Status $percentAsString -Id $progressId -Completed $true
                }
            }
            6 {
                #$includeSummarizedInsights = Read-Host -Prompt "Include summarized insights? (true/false)"
                $includeSummarizedInsights = "false"
                Save-VideoIndexJson -videoIds $uploadedVideos -includeSummarizedInsights $includeSummarizedInsights
            }
            9 {
                exit
            }
            a {
                $videoId += read-host "Video ID"
                $uri = $baseUri + $videoIndexerLocation + '/Accounts/' + $videoIndexerAccountId + '/Videos/' + $videoId + '/Index?accessToken=' + $accessToken
                $result = Invoke-RestMethod -Uri $uri -Method Get
                write-host $result
                read-host
            }
            b {
                write-host ""
                $Global:accessToken = read-host "Paste new API token here and press enter"
            }
            default {
                write-host "Invalid selection"
            }
        }
    }
}

Clear-Host
Show-MainMenu




# https://api-portal.videoindexer.ai/api-details#api=Operations&operation=Upload-Video
# https://api-portal.videoindexer.ai/api-details#api=Operations&operation=Get-Video-Index