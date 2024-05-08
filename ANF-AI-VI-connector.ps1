# Azure NetApp Files - Azure AI Video Indexer Connector, created by Sean Luce, Azure NetApp Files PG
# This script is a PowerShell script that allows you to connect Azure NetApp Files to Azure AI Video Indexer.
# The script allows you to search for video files on your local machine, send them to Azure AI Video Indexer for processing, check the status of the processing, and save the JSON data for the processed videos.
# The script uses the Azure AI Video Indexer API to send and retrieve data. You will need an API token to use the script.
# The script is designed to be run in the PowerShell ISE or Visual Studio Code, but can be run in the PowerShell console as well.
# The script is designed to be run on Windows, but can be run on other operating systems with some modifications.

$Global:baseUri = 'https://api.videoindexer.ai/'
$Global:accessToken = ''
$Global:videoIndexerLocation = ''
$Global:videoIndexerAccountId = $null
$Global:videoIndexerAccountName = $null

$Global:prefix = $null

$Global:uploadedVideos = @{}

# Get-VideoIndexerAccounts
function Select-VideoIndexerAccount {
    Connect-AzAccount -Identity
    $azContext = Get-AzContext
    $subId = $azContext.Subscription.Id
    $accountResponse = Invoke-AzRestMethod -SubscriptionId $subId -ResourceGroupName "contoso.rg" -ResourceProviderName Microsoft.VideoIndexer -ResourceType "accounts" -ApiVersion 2024-01-01 -Method GET
    $videoIndexerAccounts = $accountResponse.Content | ConvertFrom-Json
    if (($videoIndexerAccounts.value).count -gt 0) {
        write-host ""
        write-host -foregroundcolor green "Select one of the following Azure Video Indexer accounts:"
        write-host ""
        $accountNumber = 1
        foreach ($videoIndexerAccount in $videoIndexerAccounts.value) {
            write-host $accountNumber'.' $videoIndexerAccount.name$videoIndexerAccount.properties.accountId '-'$videoIndexerAccount.location
            $accountNumber++
        }
        write-host ""
        $accountSelected = read-host -Prompt "Select an account"
        $Global:videoIndexerAccountId = $videoIndexerAccounts.value[$accountSelected - 1].properties.accountId
        $Global:videoIndexerLocation = $videoIndexerAccounts.value[$accountSelected - 1].location
        $accountName = $videoIndexerAccounts.value[$accountSelected - 1].name
        $Global:videoIndexerAccountName = $videoIndexerAccounts.value[$accountSelected - 1].name
        Get-AzureVideoIndexerToken -subId $subId -accountName $accountName
    } else {
        write-host ""
        write-host -foreground Red "No Azure Video Indexer accounts found. Please create an Azure Video Indexer account using the Azure portal or CLI."
        write-host ""
        read-host -Prompt "Press any key to return to the main menu"
    }
}

function Get-AzureVideoIndexerToken {
    param(
        [string[]]$accountName,
        [string[]]$subId
    )
    $uri = 'https://management.azure.com/subscriptions/' + $subId + '/resourceGroups/contoso.rg/providers/Microsoft.VideoIndexer/accounts/' + $accountName + '/generateAccessToken?api-version=2024-01-01'
    $payload = @{
        permissionType = "Contributor"
        scope = "Account"
    } | ConvertTo-Json -Depth 3
    $token = Invoke-AzRestMethod -Uri $uri -Payload $payload -Method POST
    $tokenObject = $token.Content | ConvertFrom-Json
    $Global:accessToken = $tokenObject.accessToken
}

function Enter-SearchPaths {
    param(
        [string[]]$searchPaths
    )
    while ($searchPathSelection -ne 9) {
        Clear-Host
        Write-Host ""
        write-host -foreground blue "     _    _   _ _____    _    ___  __     _____"
        write-host -foreground green "    / \  | \ | |  ___|  / \  |_ _| \ \   / /_ _|"
        write-host -foreground cyan "   / _ \ |  \| | |_    / _ \  | |   \ \ / / | |" 
        write-host -foreground red "  / ___ \| |\  |  _|  / ___ \ | |    \ V /  | |" 
        write-host -foreground magenta " /_/   \_\_| \_|_|   /_/   \_\___|    \_/  |___|"
        write-host ""
        write-host " 1. Add Azure NetApp Files UNC paths"
        write-host " 2. Add search path manually"
        write-host " 3. Clear search paths"
        write-host " q. Quit and return to main menu"
        write-host ""
        write-host -foregroundcolor blue "Current search paths:"
        if ($searchPaths) {
            write-host ""
            $searchPaths | ForEach-Object {
                write-host -foregroundcolor green $_
            }
        } else {
            write-host ""
            write-host -foregroundcolor red "No search paths defined."
        }
        write-host ""
        $searchPathSelection = read-host -Prompt "Enter selection"
        switch ($searchPathSelection) {
            1 {
                $anfUncPaths = @()
                $netAppVolumes = Get-AzResource | where-object {$_.ResourceType -eq 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes' -and $_.Location -eq 'eastus2'}
                foreach ($volume in $netappVolumes) {
                    $volumeDetails = Get-AzNetAppFilesVolume -ResourceId $volume.Id
                    if ($volumeDetails.protocolTypes -contains 'CIFS') {
                        $uncPath = '\\' + $volumeDetails.MountTargets.smbserverfqdn + '\' + $volumeDetails.CreationToken
                        $anfUncPaths += $uncPath
                    }
                }
                if ($anfUncPaths) {
                    write-host ""
                    write-host -foregroundcolor green "The following Azure NetApp Files SMB volumes were found:"
                    write-host ""
                    $counter = 1
                    foreach ($anfUncPath in $anfUncPaths) {
                        write-host "$counter. $anfUncPath"
                        $counter++
                    }
                    write-host ""
                    do {
                    write-host -foregroundcolor yellow "Enter 'q' to stop adding Azure NetApp Files search paths."
                    write-host ""
                    $uncSelection = read-host -prompt "Which Azure NetApp Files UNC path would you like to add"
                    if ($uncSelection -eq '' -or $unSelection -eq 'q') {
                        break
                    } else {
                        $searchPaths += $anfUncPaths[$uncSelection - 1]
                        write-host ""
                        write-host $anfUncPaths[$uncSelection - 1] 'added to search paths.'
                        write-host ""
                    }
                } until ($uncSelection -eq 'q' -or $uncSelection -eq 'Q' -or $uncSelection -eq '')
                } else {
                    write-host -foregroundcolor red "No Azure NetApp Files SMB volumes were found."
                }
            }
            2 {
                Write-host -foregroundcolor yellow "Examples of search paths:"
                write-host ""
                write-host "     \\anf-1ff1.contoso.com\videos"
                write-host "     C:\Users\Alexandria\Downloads"
                write-host "     Z:\Videos\"
                write-host""
                $searchPaths += read-host -Prompt "Enter search path"
            }
            3 {
                $searchPaths = @()
            }
            q {
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
    $videoFilePaths = @()
    $searchPaths | ForEach-Object {
        $searchPath = $_
        if (-not (Test-Path $searchPath)) {
            write-host "Path" $searchPath "does not exist."
            read-host
            return $videoFilePaths
        } elseif ($searchPath.EndsWith('*')) {
            Get-ChildItem -Path $searchPath -Recurse -Include *.mp4, *.mov, *.wmv, *.avi -ErrorAction SilentlyContinue | ForEach-Object {
                $videoFilePaths += $_
            }
        } else {
            Get-ChildItem -Path $searchPath -Recurse -Include *.mp4, *.mov, *.wmv, *.avi -ErrorAction SilentlyContinue | ForEach-Object {
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
        $uri = $baseUri + $videoIndexerLocation + '/Accounts/' + $Global:videoIndexerAccountId + '/Videos?accessToken=' + $accessToken + '&name=' + $prefix + $encodedFileName + '&privacy=public'
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
    write-host ""
    write-host -foregroundcolor green "All videos sent to Azure Video Indexer for processing."
    write-host ""
    read-host -prompt "Press any key to return to the main menu"
}

function Get-VideoIndexProgress {
    param(
        [hashtable[]]$videoIds,
        [bool]$displayResults
    )
    Test-VideoIndexerToken
    foreach ($videoId in $videoIds.Keys) {
        $uri = $baseUri + $videoIndexerLocation + '/Accounts/' + $Global:videoIndexerAccountId + '/Videos/' + $videoId + '/Index?accessToken=' + $accessToken
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
    foreach ($videoId in $Global:uploadedVideos.Keys) {
        if ($Global:uploadedVideos[$videoId].state -eq "Processed") {
            $readyForDownload += $Global:uploadedVideos[$videoId]
        }
    }
    Clear-Host
        Write-Host ""
        write-host -foreground blue "     _    _   _ _____    _    ___  __     _____"
        write-host -foreground green "    / \  | \ | |  ___|  / \  |_ _| \ \   / /_ _|"
        write-host -foreground cyan "   / _ \ |  \| | |_    / _ \  | |   \ \ / / | |" 
        write-host -foreground red "  / ___ \| |\  |  _|  / ___ \ | |    \ V /  | |" 
        write-host -foreground magenta " /_/   \_\_| \_|_|   /_/   \_\___|    \_/  |___|"
        write-host ""
    if ($readyForDownload.Count -eq 0) {
        write-host ""
        write-host -foreground red "No video JSON files are ready for download."
        write-host ""
        read-host -foreground green -prompt "Press any key to return to the main menu"
        return
    }
    write-host -foreground green "Click the links below to view the results in the Azure Video Indexer portal."
    write-host ""
    foreach ($video in $readyForDownload) {
        $url = 'https://www.videoindexer.ai/accounts/' + $Global:videoIndexerAccountId + '/videos/' + $video.id + '?location=' + $Global:videoIndexerLocation
        write-host -foregroundcolor blue "Original file:"$video.localPath
        write-host -foregroundcolor yellow "     Azure Video Indexer link: $url"
        write-host ""
    }
    $saveJson = read-host -prompt "Save JSON data for completed videos Y/n"
    if ($saveJson -eq 'y' -or $saveJson -eq 'Y') {
        $savePath = (Get-Location).Path
        foreach ($video in $readyForDownload) {
            $uri = $baseUri + $videoIndexerLocation + '/Accounts/' + $Global:videoIndexerAccountId + '/Videos/' + $video.id + '/Index?includeSummarizedInsights=' + $includeSummarizedInsights + '&accessToken=' + $accessToken
            $result = Invoke-RestMethod -Uri $uri -Method Get
            $fileName = $result.id + '.json'
            $result | ConvertTo-Json -depth 100 | Out-File -FilePath $fileName
            write-host ""
            write-host -foregroundcolor green "$filename saved to $savePath"
        }
        write-host ""
    read-host -prompt "Downloading complete. Press any key to continue to return to the main menu"
    } else {
        return
    }
}

function Find-KeywordVideoIndexer {
    param(
        [string[]]$searchTerm
    )
    $jsonFiles = Get-ChildItem -Path .\*.json -ErrorAction SilentlyContinue
    $instanceCount = 0
    $fileCount = 0
    $tableOfLabels = @()
    write-host ""
    write-host -foregroundcolor green "Searching index JSON files for '$searchTerm'..."
    write-host ""
    foreach ($jsonFile in $jsonFiles) {
        $instancesInThisFile = $null
        $rawFileContent = Get-Content $jsonFile
        $objectContent = $rawFileContent | ConvertFrom-Json
        $videos = $objectContent.videos
        $accountId = $objectContent.accountId
        foreach ($video in $videos){
            $videoId = $video.id
            $videoLabels = $video.insights.labels | where-object {$_.name -eq $searchTerm}
            if ($videoLabels.count -gt 0) {
                $fileCount ++
            }
            foreach ($videoLabel in $videoLabels) {# | where-object {$_.name -eq $searchTerm}) {
                $tableOfLabels += $videoLabel
                $instancesInThisFile = $videoLabel.instances
                $totalInstances += $videoLabel.instances
            }
        }
        
        $fileName = $jsonFile.name
        $instanceCount = $instancesInThisFile.count
        $videoName = $objectContent.name
        if ($instanceCount -eq 0) {
            #write-host -foregroundcolor red "No instances of '$searchTerm' were found in $fileName ($videoName)."
            #write-host ""
        }else {
            write-host "----------------------------------------------------------------------------------------------------------------------------"
            write-host -foregroundcolor blue "$fileCount. Found $instanceCount instances of '$searchTerm' in $fileName ($videoName)..."
            write-host "----------------------------------------------------------------------------------------------------------------------------"
            foreach ($instance in $instancesInThisFile) {
                $startTime = ($instance.start).split(":")[2]
                $url = 'https://www.videoindexer.ai/accounts/' + $accountId + '/videos/' + $videoId + '?location=' + $Global:videoIndexerLocation + '&t=' + $startTime.split(".")[0]
                $instance | Add-Member -NotePropertyName Url -NotePropertyValue $url -Force
                write-host ""
                write-host "  confidence   : "$instance.confidence
                write-host "  start        : "$instance.start
                write-host "  end          : "$instance.end
                write-host "  url          : "$instance.url
            }
            write-host ""
            
        }
        
    }
    $totalInstanceCount = $totalInstances.count
    write-host -foregroundcolor green "We found $totalInstanceCount total instance(s) of '$searchTerm'."
    write-host ""
    write-host "Ctrl+Click on the URLs above to see each instance of '$searchTerm'"
    write-host ""
    $jsonSelection = read-host -prompt "Select a number to view the corresponding JSON data or enter to return to main menu"
    if ($jsonSelection -eq ''){
        return
    }
    if ($null -ne $tableOfLabels[[int]$jsonSelection -1]) {
        write-host ""
        $tableOfLabels[[int]$jsonSelection - 1] | convertto-json | Out-HostColored -SimpleMatch $searchTerm
        write-host ""
        read-host "Press any key to return to the search results"
        clear-host
        Write-Host ""
        write-host -foreground blue "     _    _   _ _____    _    ___  __     _____"
        write-host -foreground green "    / \  | \ | |  ___|  / \  |_ _| \ \   / /_ _|"
        write-host -foreground cyan "   / _ \ |  \| | |_    / _ \  | |   \ \ / / | |" 
        write-host -foreground red "  / ___ \| |\  |  _|  / ___ \ | |    \ V /  | |" 
        write-host -foreground magenta " /_/   \_\_| \_|_|   /_/   \_\___|    \_/  |___|"
        write-host ""
        Find-KeywordVideoIndexer -searchTerm $searchTerm
    } else {
        write-host ""
        read-host "Invalid selection. Press any key to return to the search results"
        clear-host
        Write-Host ""
        write-host -foreground blue "     _    _   _ _____    _    ___  __     _____"
        write-host -foreground green "    / \  | \ | |  ___|  / \  |_ _| \ \   / /_ _|"
        write-host -foreground cyan "   / _ \ |  \| | |_    / _ \  | |   \ \ / / | |" 
        write-host -foreground red "  / ___ \| |\  |  _|  / ___ \ | |    \ V /  | |" 
        write-host -foreground magenta " /_/   \_\_| \_|_|   /_/   \_\___|    \_/  |___|"
        write-host ""
        Find-KeywordVideoIndexer -searchTerm $searchTerm
    }
}

Function Out-HostColored {
    # Note: The [CmdletBinding()] and param() block are formatted to be PSv2-compatible.
    [CmdletBinding()]
    param(
      [Parameter(Position = 0, Mandatory = $True)] [string[]] $Pattern,
      [Parameter(Position = 1)] [ConsoleColor] $ForegroundColor = 'Green',
      [Parameter(Position = 2)] [ConsoleColor] $BackgroundColor,
      [switch] $WholeLine,
      [switch] $SimpleMatch,
      [Parameter(Mandatory = $True, ValueFromPipeline = $True)] $InputObject
    )
  
    # Wrap the pattern / literal in an explicit capture group.
    # Fail, if the given regex is syntactically invalid.
    try {
      $re = [regex] ('(?<sep>{0})' -f $(if ($SimpleMatch) { 
            ($Pattern | ForEach-Object { [regex]::Escape($_) }) -join '|'
          } 
          else { 
            ($Pattern | ForEach-Object { '(?:{0})' -f $_ }) -join '|'
          }))
    }
    catch { Throw }
  
    # Build a parameters hashtable specifying the colors, to be use via
    # splatting with Write-Host later.
    $htColors = @{
      ForegroundColor = $ForegroundColor
    }
    if ($BackgroundColor) {
      $htColors.Add('BackgroundColor', $BackgroundColor)
    }
  
    # Use pipeline input, if provided (the typical case).
    if ($MyInvocation.ExpectingInput) { $InputObject = $Input }
  
    # Apply default formatting to each input object, and look for matches to
    # color line by line.
    $InputObject | Out-String -Stream | ForEach-Object {
      $line = $_
      if ($WholeLine) {
        # Color the whole line in case of match.
        if ($line -match $re) {
          Write-Host @htColors $line
        }
        else {
          Write-Host $line
        }
      }
      else {
        # Split the line by the regex and include what the regex matched.
        $segments = $line -split $re, 0, 'ExplicitCapture'
        if ($segments.Count -eq 1) {
          # no matches -> output line as-is
          Write-Host $line
        }
        else {
          # at least 1 match, as a repeating sequence of <pre-match> - <match> pairs
          $i = 0
          foreach ($segment in $segments) {
            if ($i++ % 2) {
              # matching part
              Write-Host -NoNewline @htColors $segment
            }
            else {
              # non-matching part
              Write-Host -NoNewline $segment
            }
          }
          Write-Host '' # Terminate the current output line with a newline.
        }
      }
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
        write-host " 1. Select Azure Video Indexer account"
        write-host " 2. Add or reset search paths"
        if ($prefix) {
            write-host " 3. Set project identifier ($prefix)"    
        } else {
            write-host " 3. Set project identifier"
        }
        if ($searchPaths.count -gt 0 -and $videoIndexerAccountName -and $selectedVideos.count -eq 0 -and $uploadedVideos.count -eq 0) {
            write-host -foregroundcolor yello " 4. Search and select video files"
        } else {
            write-host " 4. Search and select video files"
        }
        if ($selectedVideos.count -gt 0) {
            write-host -foreground yellow " 5. Send selected video files to Azure AI Video Indexer"    
        } else { 
            write-host " 5. Send selected video files to Azure AI Video Indexer"
        }
        
        write-host " 6. Check status of video files"
        write-host " 7. View completed videos and save video index JSON data"
        write-host " 8. Search indexed videos for keyword"
        write-host " q. Quit"
        write-host ""
        if ($Global:videoIndexerAccountId) {
            write-host "Azure Video Indexer account ID:"$Global:videoIndexerAccountId
        } else {
            write-host -NoNewLine "Azure Video Indexer account ID: "
            write-host -ForegroundColor Red "NONE"
        }
        write-host ""
        write-host -foreground blue $selectedVideos.count "videos selected for indexing."
        write-host -foreground yellow $uploadedVideos.count "videos sent for indexing."
        write-host -foreground green $completedVideos.count "videos completed indexing and ready for JSON download."
        write-host ""
        if (-not $videoIndexerAccountName) {

            write-host -foreground red "No Azure Video Indexer account selected."
            write-host ""
            $defineVideoIndexerNow = read-host -prompt "Would you like to select an Azure Video Indexer account now? Y/n"
            if ($defineVideoIndexerNow -eq 'y' -or $defineVideoIndexerNow -eq 'Y' -or $defineVideoIndexerNow -eq '') {
                $videoIndexerAccountId = Select-VideoIndexerAccount
                Show-MainMenu
            }
        }
        if ($searchPaths.count -eq 0) {
            write-host -foreground red "No search paths defined."
            write-host ""
            $defineSearchPathsNow = read-host -prompt "Would you like to define search paths now? Y/n"
            if ($defineSearchPathsNow -eq 'y' -or $defineSearchPathsNow -eq 'Y' -or $defineSearchPathsNow -eq '') {
                $searchPaths = Enter-SearchPaths -searchPaths $searchPaths
                Show-MainMenu
            }
        }
        $selection = read-host -Prompt "Enter selection"
    
        switch ($selection) {
            1 {
                $videoIndexerAccountId = Select-VideoIndexerAccount
            }
            2 {
                $searchPaths = Enter-SearchPaths -searchPaths $searchPaths
            }
            3 {
                write-host ""
                write-host "The project identifier will act as a prefix to the name of the files sent to Azure Video Indexer."
                write-host "This can be useful if you are uploading the same video(s) multiple times as part of a demo or other purpose."
                write-host ""
                $Global:prefix = read-host -prompt "Enter project identifier"
            }
            4 {
                if ($searchPaths) {
                    $foundVideoFiles = Search-VideoFiles -searchPaths $searchPaths
                    if ($foundVideoFiles) {
                        $selectedVideos = $foundVideoFiles | Select-Object -Property Name, @{Name='Path'; Expression={$_.FullName}}, @{Name='Size (MiB)'; Expression={[math]::round($_.Length/1024/1024)}} | out-gridview -Title "Select one or more video files to process with Azure Video Indexer" -PassThru
                    } else {
                        write-host ""
                        write-host -foreground red "No video files found in the following search paths:"
                        foreach($searchPath in $SearchPaths) {
                            write-host ' '$searchPath
                        }
                        read-host
                        break
                    }     
                } else {
                    write-host ""
                    write-host -foreground red "No search paths have been defined. Please add search paths before searching for video files."
                    break
                }
            }
            5 {
                if ($selectedVideos) {
                    write-host ""
                    write-host -foreground green "The following videos will be processed by Azure Video Indexer:"
                    write-host ""
                    foreach ($selectedVideo in $selectedVideos) {
                        write-host ' ' $selectedVideo.Name
                    }
                    write-host ""
                    $continue = read-host -prompt "Continue? Y/n"
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
            6 {
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
                        write-host -foregroundcolor green "Video indexing complete for all videos. Press any key to return to the main menu."
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
            7 {
                #$includeSummarizedInsights = Read-Host -Prompt "Include summarized insights? (true/false)"
                $includeSummarizedInsights = "false"
                Save-VideoIndexJson -videoIds $uploadedVideos -includeSummarizedInsights $includeSummarizedInsights
            }
            8 {
                Clear-Host
                Write-Host ""
                write-host -foreground blue "     _    _   _ _____    _    ___  __     _____"
                write-host -foreground green "    / \  | \ | |  ___|  / \  |_ _| \ \   / /_ _|"
                write-host -foreground cyan "   / _ \ |  \| | |_    / _ \  | |   \ \ / / | |" 
                write-host -foreground red "  / ___ \| |\  |  _|  / ___ \ | |    \ V /  | |" 
                write-host -foreground magenta " /_/   \_\_| \_|_|   /_/   \_\___|    \_/  |___|"
                write-host ""
                $searchTerm = read-host -prompt "What are you looking for"
                if ($searchTerm -eq '') {
                    Clear-Host
                    Show-MainMenu 
                } else {
                    Find-KeywordVideoIndexer -searchTerm $searchTerm
                }
            }
            q {
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