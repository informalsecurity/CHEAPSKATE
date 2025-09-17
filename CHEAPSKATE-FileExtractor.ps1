[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$MFTPath,
    
    [Parameter(Mandatory=$true)]
    [string]$CheapskateCSV,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceDrive,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputDirectory,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('RoboCopy', 'FileList', 'PowerShell', 'Batch', 'JSON')]
    [string]$OutputFormat = 'RoboCopy',
    
    [Parameter(Mandatory=$false)]
    [string[]]$FileExtensionBlacklist = @(
        # System/Executable Files
        '.exe', '.dll', '.sys', '.bin', '.msi', '.cab', '.msp', '.msu', '.scr', '.com', '.bat', '.cmd', '.iso', '.app', '.dmg', '.so', '.svg', '.css', '.drv', 
        
        # Configuration/System Files  
        '.ini', '.conf', '.cfg', '.config', '.log', '.evt', '.evtx', '.etl', '.dmp', '.mdmp',
        
        # Encrypted/Compressed (can't analyze easily)
        '.7z', '.rar', '.gz', '.tar', '.bz2', '.xz', '.gpg', '.pgp', '.p12', '.pfx', '.cer', '.crt', '.key',
        
        # Media Files (unlikely to contain structured data)
        '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.ico', '.mp3', '.wav', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.swf', '.flac', '.aac', '.fla', 
        
        # Temporary/Cache Files
        '.tmp', '.temp', '.cache', '.bak', '.old', '.swp', '.swo', '.thumbs.db', '.ds_store', '.css', '.js', '.woff', '.woff2', '.ttf', '.otf', '.idx', '.chm', '.hlp', 
        
        # Development/Build Files
        '.obj', '.pdb', '.lib', '.exp', '.ilk', '.pch', '.idb', '.ncb', '.sbr', '.bsc',
        
        # Windows Specific
        '.lnk', '.url', '.manifest', '.mui', '.msp', '.cat', '.inf'
    ),
    
    [Parameter(Mandatory=$false)]
    [string]$ToolsPath = ".\ZimmermanTools"
)

function Download-MFTECmd {
    param([string]$ToolsPath)
    
    Write-Host "MFTECmd not found. Downloading from Eric Zimmerman's site..." -ForegroundColor Yellow
    
    if (-not (Test-Path $ToolsPath)) {
        New-Item -Path $ToolsPath -ItemType Directory -Force | Out-Null
    }
    
    $downloadUrl = "https://download.ericzimmermanstools.com/MFTECmd.zip"
    $zipPath = Join-Path $ToolsPath "MFTECmd.zip"
    
    try {
        Write-Host "Downloading MFTECmd.zip..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        
        Write-Host "Extracting MFTECmd..." -ForegroundColor Yellow
        Expand-Archive -Path $zipPath -DestinationPath $ToolsPath -Force
        
        Remove-Item $zipPath -Force
        
        $mfteCmdPath = Join-Path $ToolsPath "MFTECmd.exe"
        if (Test-Path $mfteCmdPath) {
            Write-Host "MFTECmd downloaded successfully!" -ForegroundColor Green
            return $mfteCmdPath
        } else {
            throw "MFTECmd.exe not found after extraction"
        }
    }
    catch {
        Write-Error "Failed to download MFTECmd: $($_.Exception.Message)"
        return $null
    }
}

function Find-MFTECmd {
    param([string]$ToolsPath)
    
    $possiblePaths = @(
        (Join-Path $ToolsPath "MFTECmd.exe"),
        ".\MFTECmd.exe",
        "MFTECmd.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Host "Found MFTECmd at: $path" -ForegroundColor Green
            return $path
        }
    }
    
    $pathCmd = Get-Command "MFTECmd.exe" -ErrorAction SilentlyContinue
    if ($pathCmd) {
        Write-Host "Found MFTECmd in PATH: $($pathCmd.Source)" -ForegroundColor Green
        return $pathCmd.Source
    }
    
    return $null
}

function Get-FilesInDirectories {
    param(
        [string]$CsvPath,
        [string[]]$TargetDirectories,
        [string[]]$FileExtensionBlacklist
    )
    
    Write-Host "Extracting file listings from MFT for selected directories..." -ForegroundColor Yellow
    
    $targetFiles = @()
    $excludedCount = 0
    $totalCount = 0
    
    # Stream process the CSV file to find files in target directories
    $reader = [System.IO.StreamReader]::new($CsvPath)
    $header = $reader.ReadLine()
    $headerFields = $header -split ','
    
    # Find required column indices
    $isDirectoryIndex = $headerFields.IndexOf('IsDirectory')
    $inUseIndex = $headerFields.IndexOf('InUse')
    $fileNameIndex = $headerFields.IndexOf('FileName')
    $parentPathIndex = $headerFields.IndexOf('ParentPath')
    $fileSizeIndex = $headerFields.IndexOf('FileSize')
    
    try {
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            
            $fields = $line -split ','
            if ($fields.Count -le $parentPathIndex) { continue }
            
            $isDirectory = $fields[$isDirectoryIndex] -eq 'True'
            $inUse = $fields[$inUseIndex] -eq 'True'
            
            # Only process files (not directories) that are in use
            if ($isDirectory -or -not $inUse) { continue }
            
            $fileName = $fields[$fileNameIndex].Trim('"')
            $parentPath = $fields[$parentPathIndex].Trim('"')
            
            if ([string]::IsNullOrWhiteSpace($fileName)) { continue }
            
            # Clean parent path
            if ($parentPath.StartsWith('.\')) {
                $parentPath = $parentPath.Substring(2)
            }
            
            # Build full path
            $fullPath = if ($parentPath -and $parentPath.Trim() -ne '' -and $parentPath -ne '.') {
                "$parentPath\$fileName"
            } else {
                $fileName
            }
            
            $fullPath = $fullPath.Replace('/', '\').TrimStart('\')
            $totalCount++
            
            # Check if this file is in one of our target directories
            $isInTargetDirectory = $false
            foreach ($targetDir in $TargetDirectories) {
                if ($fullPath.StartsWith("$targetDir\") -or $fullPath -eq $targetDir) {
                    $isInTargetDirectory = $true
                    break
                }
            }
            
            if (-not $isInTargetDirectory) { continue }
            
            # Check blacklist
            $fileExtension = [System.IO.Path]::GetExtension($fileName).ToLower()
            if ($FileExtensionBlacklist -contains $fileExtension) {
                $excludedCount++
                continue
            }
            
            # Parse file size
            $fileSize = 0L
            if ($fileSizeIndex -ge 0 -and $fileSizeIndex -lt $fields.Count) {
                $fileSizeStr = $fields[$fileSizeIndex].Trim('"')
                [long]::TryParse($fileSizeStr, [ref]$fileSize) | Out-Null
            }
            
            $targetFiles += [PSCustomObject]@{
                FullPath = $fullPath
                FileName = $fileName
                ParentPath = $parentPath
                FileSize = $fileSize
            }
        }
    }
    finally {
        $reader.Close()
        $reader.Dispose()
    }
    
    Write-Host "Found $($targetFiles.Count) files to extract (excluded $excludedCount blacklisted files)" -ForegroundColor Green
    Write-Host "Total processing: $totalCount files scanned" -ForegroundColor Cyan
    
    return $targetFiles
}

function Generate-RoboCopyScript {
    param([array]$Files, [string]$SourceDrive, [string]$OutputDir)
    
    $script = @"
@echo off
REM CHEAPSKATE File Extraction Script - RoboCopy Version  
REM Generated: $(Get-Date)
REM Source: $SourceDrive
REM Destination: $OutputDir

echo Starting CHEAPSKATE file extraction...
echo.

"@

    # Group files by directory for efficient RoboCopy
    $dirGroups = $Files | Group-Object ParentPath
    
    foreach ($group in $dirGroups) {
        $sourceDir = if ($group.Name) { "$SourceDrive\$($group.Name)" } else { $SourceDrive }
        $destDir = if ($group.Name) { "$OutputDir\$($group.Name)" } else { $OutputDir }
        
        $fileList = ($group.Group | ForEach-Object { "`"$($_.FileName)`"" }) -join ' '
        
        $script += @"
echo Copying from: $sourceDir
robocopy "$sourceDir" "$destDir" $fileList /S /E /COPYALL /R:3 /W:1 /MT:8
echo.

"@
    }
    
    $script += @"
echo CHEAPSKATE extraction completed!
echo Total directories: $($dirGroups.Count)
echo Total files: $($Files.Count)
pause
"@
    
    return $script
}

function Generate-PowerShellScript {
    param([array]$Files, [string]$SourceDrive, [string]$OutputDir)
    
    $script = @"
# CHEAPSKATE File Extraction Script - PowerShell Version
# Generated: $(Get-Date)
# Source: $SourceDrive  
# Destination: $OutputDir

Write-Host "Starting CHEAPSKATE file extraction..." -ForegroundColor Green
Write-Host "Files to copy: $($Files.Count)" -ForegroundColor Cyan
Write-Host ""

`$copied = 0
`$errors = 0

"@

    foreach ($file in $Files) {
        $sourcePath = if ($file.ParentPath) { "$SourceDrive\$($file.FullPath)" } else { "$SourceDrive\$($file.FileName)" }
        $destPath = if ($file.ParentPath) { "$OutputDir\$($file.FullPath)" } else { "$OutputDir\$($file.FileName)" }
        $destDir = Split-Path $destPath -Parent
        
        $script += @"
try {
    if (-not (Test-Path "$destDir")) { New-Item -Path "$destDir" -ItemType Directory -Force | Out-Null }
    Copy-Item -Path "$sourcePath" -Destination "$destPath" -Force
    Write-Host "✓ $($file.FullPath)" -ForegroundColor Gray
    `$copied++
} catch {
    Write-Host "✗ Failed: $($file.FullPath) - `$(`$_.Exception.Message)" -ForegroundColor Red
    `$errors++
}

"@
    }
    
    $script += @"
Write-Host ""
Write-Host "CHEAPSKATE extraction completed!" -ForegroundColor Green
Write-Host "Successfully copied: `$copied files" -ForegroundColor Cyan
Write-Host "Errors: `$errors files" -ForegroundColor Yellow
"@
    
    return $script
}

function Generate-FileList {
    param([array]$Files, [string]$SourceDrive)
    
    $list = @"
# CHEAPSKATE File List - Generated $(Get-Date)
# Source Drive: $SourceDrive
# Total Files: $($Files.Count)
# 
# Format: Full path from source drive root
# Use with your preferred file copy tool
#

"@

    foreach ($file in $Files | Sort-Object FullPath) {
        $sourcePath = if ($file.ParentPath) { "$SourceDrive\$($file.FullPath)" } else { "$SourceDrive\$($file.FileName)" }
        $list += "$sourcePath`n"
    }
    
    return $list
}

function Generate-JSON {
    param([array]$Files, [string]$SourceDrive, [string]$OutputDir)
    
    $jsonData = @{
        metadata = @{
            generated = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            source_drive = $SourceDrive
            output_directory = $OutputDir
            total_files = $Files.Count
            tool = "CHEAPSKATE File Extractor"
        }
        files = $Files | ForEach-Object {
            @{
                source_path = if ($_.ParentPath) { "$SourceDrive\$($_.FullPath)" } else { "$SourceDrive\$($_.FileName)" }
                dest_path = if ($_.ParentPath) { "$OutputDir\$($_.FullPath)" } else { "$OutputDir\$($_.FileName)" }
                filename = $_.FileName
                parent_path = $_.ParentPath
                file_size = $_.FileSize
                relative_path = $_.FullPath
            }
        }
    }
    
    return $jsonData | ConvertTo-Json -Depth 3
}

# Main execution
Write-Host "CHEAPSKATE File Extractor" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

# Validate inputs
if (-not (Test-Path $MFTPath)) {
    Write-Error "MFT file not found: $MFTPath"
    exit 1
}

if (-not (Test-Path $CheapskateCSV)) {
    Write-Error "CHEAPSKATE CSV not found: $CheapskateCSV"
    exit 1
}

if (-not (Test-Path $SourceDrive)) {
    Write-Error "Source drive not found: $SourceDrive"
    exit 1
}

Write-Host "Reading CHEAPSKATE analysis results..." -ForegroundColor Yellow
$csvData = Import-Csv -Path $CheapskateCSV
$selectedDirectories = $csvData | Where-Object { $_."Directory Path" -and $_."Directory Path" -ne "TOTAL SELECTED" } | ForEach-Object { $_."Directory Path".Trim('"') }

Write-Host "Selected directories: $($selectedDirectories.Count)" -ForegroundColor Cyan
foreach ($dir in $selectedDirectories | Sort-Object) {
    Write-Host "  • $dir" -ForegroundColor White
}

# Find MFTECmd
Write-Host "`nLocating MFTECmd..." -ForegroundColor Yellow
$mfteCmdPath = Find-MFTECmd -ToolsPath $ToolsPath
if (-not $mfteCmdPath) {
    $mfteCmdPath = Download-MFTECmd -ToolsPath $ToolsPath
    if (-not $mfteCmdPath) {
        Write-Error "Could not obtain MFTECmd.exe"
        exit 1
    }
}

# Create temp directory for MFT CSV export
$tempCsvPath = Join-Path $env:TEMP "CHEAPSKATE_FileList_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $tempCsvPath -ItemType Directory -Force | Out-Null

try {
    # Export MFT to CSV for file analysis
    Write-Host "Re-parsing MFT for detailed file listings..." -ForegroundColor Yellow
    $csvFileName = "mft_files.csv"
    $csvFilePath = Join-Path $tempCsvPath $csvFileName
    
    $arguments = @(
        "-f", "`"$MFTPath`"",
        "--csv", "`"$tempCsvPath`"",
        "--csvf", "`"$csvFileName`""
    )
    
    $process = Start-Process -FilePath $mfteCmdPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        throw "MFTECmd failed with exit code: $($process.ExitCode)"
    }
    
    # Get file listings for selected directories
    $targetFiles = Get-FilesInDirectories -CsvPath $csvFilePath -TargetDirectories $selectedDirectories -FileExtensionBlacklist $FileExtensionBlacklist
    
    if ($targetFiles.Count -eq 0) {
        Write-Warning "No files found in selected directories (after blacklist filtering)"
        exit 0
    }
    
    # Calculate total size
    $totalSize = ($targetFiles | Measure-Object -Property FileSize -Sum).Sum
    $totalSizeFormatted = if ($totalSize -ge 1TB) { "{0:N2} TB" -f ($totalSize / 1TB) }
        elseif ($totalSize -ge 1GB) { "{0:N2} GB" -f ($totalSize / 1GB) }
        elseif ($totalSize -ge 1MB) { "{0:N2} MB" -f ($totalSize / 1MB) }
        elseif ($totalSize -ge 1KB) { "{0:N2} KB" -f ($totalSize / 1KB) }
        else { "$totalSize bytes" }
    
    Write-Host "`nExtraction Summary:" -ForegroundColor Green
    Write-Host "Files to extract: $($targetFiles.Count)" -ForegroundColor Cyan
    Write-Host "Total size: $totalSizeFormatted" -ForegroundColor Cyan
    Write-Host "Source: $SourceDrive" -ForegroundColor Cyan
    Write-Host "Destination: $OutputDirectory" -ForegroundColor Cyan
    
    # Generate output based on format
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    
    switch ($OutputFormat) {
        'RoboCopy' {
            $outputFile = "CHEAPSKATE_Extract_RoboCopy_$timestamp.bat"
            $content = Generate-RoboCopyScript -Files $targetFiles -SourceDrive $SourceDrive -OutputDir $OutputDirectory
            $content | Out-File -FilePath $outputFile -Encoding ASCII
            Write-Host "`nGenerated RoboCopy batch file: $outputFile" -ForegroundColor Green
            Write-Host "Run this batch file to extract all selected files efficiently" -ForegroundColor Yellow
        }
        
        'PowerShell' {
            $outputFile = "CHEAPSKATE_Extract_PowerShell_$timestamp.ps1"
            $content = Generate-PowerShellScript -Files $targetFiles -SourceDrive $SourceDrive -OutputDir $OutputDirectory
            $content | Out-File -FilePath $outputFile -Encoding UTF8
            Write-Host "`nGenerated PowerShell script: $outputFile" -ForegroundColor Green
            Write-Host "Run this script to extract files with detailed progress" -ForegroundColor Yellow
        }
        
        'FileList' {
            $outputFile = "CHEAPSKATE_FileList_$timestamp.txt"
            $content = Generate-FileList -Files $targetFiles -SourceDrive $SourceDrive
            $content | Out-File -FilePath $outputFile -Encoding UTF8
            Write-Host "`nGenerated file list: $outputFile" -ForegroundColor Green
            Write-Host "Use this list with your preferred file copy tool" -ForegroundColor Yellow
        }
        
        'Batch' {
            $outputFile = "CHEAPSKATE_Extract_Copy_$timestamp.bat"
            $content = "@echo off`nREM CHEAPSKATE Batch Copy Script`n"
            foreach ($file in $targetFiles) {
                $sourcePath = if ($file.ParentPath) { "$SourceDrive\$($file.FullPath)" } else { "$SourceDrive\$($file.FileName)" }
                $destPath = if ($file.ParentPath) { "$OutputDirectory\$($file.FullPath)" } else { "$OutputDirectory\$($file.FileName)" }
                $destDir = Split-Path $destPath -Parent
                $content += "if not exist `"$destDir`" mkdir `"$destDir`"`n"
                $content += "copy `"$sourcePath`" `"$destPath`"`n"
            }
            $content | Out-File -FilePath $outputFile -Encoding ASCII
            Write-Host "`nGenerated batch copy script: $outputFile" -ForegroundColor Green
            Write-Host "Simple batch file with individual copy commands" -ForegroundColor Yellow
        }
        
        'JSON' {
            $outputFile = "CHEAPSKATE_Extract_Manifest_$timestamp.json"
            $content = Generate-JSON -Files $targetFiles -SourceDrive $SourceDrive -OutputDir $OutputDirectory
            $content | Out-File -FilePath $outputFile -Encoding UTF8
            Write-Host "`nGenerated JSON manifest: $outputFile" -ForegroundColor Green
            Write-Host "Use this with custom automation tools or APIs" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n✅ CHEAPSKATE file extraction script generated successfully!" -ForegroundColor Green
    Write-Host "💰 Ready to send only relevant files to forensic vendor" -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to generate extraction script: $($_.Exception.Message)"
} finally {
    # Cleanup
    if (Test-Path $tempCsvPath) {
        Remove-Item $tempCsvPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
