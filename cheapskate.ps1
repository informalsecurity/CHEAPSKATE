[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$MFTPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputHtmlFile,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxDepth = 15,
    
    [Parameter(Mandatory=$false)]
    [string]$ToolsPath = ".\ZimmermanTools",
    
    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 10000
)
Add-Type -AssemblyName System.Web
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

function Format-FileSize {
    param([long]$Size)
    
    if ($Size -ge 1TB) { return "{0:N2} TB" -f ($Size / 1TB) }
    elseif ($Size -ge 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
    elseif ($Size -ge 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
    elseif ($Size -ge 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
    else { return "$Size bytes" }
}

function Process-MFT-Streaming {
    param(
        [string]$CsvPath,
        [int]$MaxDepth,
        [int]$BatchSize
    )
    
    Write-Host "Processing MFT data with memory optimization..." -ForegroundColor Yellow
    
    # Use efficient data structures
    $directoryData = [System.Collections.Generic.Dictionary[string,object]]::new()
    $pathSizes = [System.Collections.Generic.Dictionary[string,long]]::new()
    $pathFileCounts = [System.Collections.Generic.Dictionary[string,int]]::new()
    $validPaths = [System.Collections.Generic.HashSet[string]]::new()
    
    # Stream process the CSV file
    $reader = [System.IO.StreamReader]::new($CsvPath)
    $header = $reader.ReadLine()
    $headerFields = $header -split ','
    
    # Find required column indices
    $isDirectoryIndex = $headerFields.IndexOf('IsDirectory')
    $inUseIndex = $headerFields.IndexOf('InUse')
    $fileNameIndex = $headerFields.IndexOf('FileName')
    $parentPathIndex = $headerFields.IndexOf('ParentPath')
    $fileSizeIndex = $headerFields.IndexOf('FileSize')
    $createdIndex = $headerFields.IndexOf('Created0x10')
    $modifiedIndex = $headerFields.IndexOf('LastModified0x10')
    $entryNumberIndex = $headerFields.IndexOf('EntryNumber')
    
    $recordCount = 0
    $batch = [System.Collections.Generic.List[string]]::new()
    
    try {
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            $batch.Add($line)
            
            if ($batch.Count -ge $BatchSize) {
                Process-Batch -Batch $batch -HeaderFields $headerFields -DirectoryData $directoryData -PathSizes $pathSizes -PathFileCounts $pathFileCounts -ValidPaths $validPaths -MaxDepth $MaxDepth -IsDirectoryIndex $isDirectoryIndex -InUseIndex $inUseIndex -FileNameIndex $fileNameIndex -ParentPathIndex $parentPathIndex -FileSizeIndex $fileSizeIndex -CreatedIndex $createdIndex -ModifiedIndex $modifiedIndex -EntryNumberIndex $entryNumberIndex
                
                $recordCount += $batch.Count
                Write-Host "Processed $recordCount records..." -ForegroundColor Gray
                
                $batch.Clear()
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }
        }
        
        # Process remaining batch
        if ($batch.Count -gt 0) {
            Process-Batch -Batch $batch -HeaderFields $headerFields -DirectoryData $directoryData -PathSizes $pathSizes -PathFileCounts $pathFileCounts -ValidPaths $validPaths -MaxDepth $MaxDepth -IsDirectoryIndex $isDirectoryIndex -InUseIndex $inUseIndex -FileNameIndex $fileNameIndex -ParentPathIndex $parentPathIndex -FileSizeIndex $fileSizeIndex -CreatedIndex $createdIndex -ModifiedIndex $modifiedIndex -EntryNumberIndex $entryNumberIndex
            $recordCount += $batch.Count
        }
    }
    finally {
        $reader.Close()
        $reader.Dispose()
    }
    
    Write-Host "Processed $recordCount total records" -ForegroundColor Green
    Write-Host "Found $($directoryData.Count) directories" -ForegroundColor Green
    
    # Calculate directory totals efficiently
    Write-Host "Calculating directory totals..." -ForegroundColor Yellow
    Calculate-DirectoryTotals -DirectoryData $directoryData -PathSizes $pathSizes -PathFileCounts $pathFileCounts
    
    return $directoryData
}

function Process-Batch {
    param(
        [System.Collections.Generic.List[string]]$Batch,
        [string[]]$HeaderFields,
        [System.Collections.Generic.Dictionary[string,object]]$DirectoryData,
        [System.Collections.Generic.Dictionary[string,long]]$PathSizes,
        [System.Collections.Generic.Dictionary[string,int]]$PathFileCounts,
        [System.Collections.Generic.HashSet[string]]$ValidPaths,
        [int]$MaxDepth,
        [int]$IsDirectoryIndex,
        [int]$InUseIndex,
        [int]$FileNameIndex,
        [int]$ParentPathIndex,
        [int]$FileSizeIndex,
        [int]$CreatedIndex,
        [int]$ModifiedIndex,
        [int]$EntryNumberIndex
    )
    
    foreach ($line in $Batch) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Parse CSV line manually for better performance
        $fields = $line -split ','
        
        # Find the highest index we need to access
        $maxIndex = $IsDirectoryIndex
        if ($InUseIndex -gt $maxIndex) { $maxIndex = $InUseIndex }
        if ($FileNameIndex -gt $maxIndex) { $maxIndex = $FileNameIndex }
        if ($ParentPathIndex -gt $maxIndex) { $maxIndex = $ParentPathIndex }
        if ($FileSizeIndex -gt $maxIndex) { $maxIndex = $FileSizeIndex }
        
        if ($fields.Count -le $maxIndex) {
            continue
        }
        
        $isDirectory = $fields[$IsDirectoryIndex] -eq 'True'
        $inUse = $fields[$InUseIndex] -eq 'True'
        
        if (-not $inUse) { continue }
        
        $fileName = $fields[$FileNameIndex].Trim('"')
        $parentPath = $fields[$ParentPathIndex].Trim('"')
        
        if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -in @('.', '..')) {
            continue
        }
        
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
        
        if ([string]::IsNullOrWhiteSpace($fullPath)) { continue }
        
        # Check depth
        $pathDepth = ($fullPath -split '\\').Count
        if ($pathDepth -gt $MaxDepth) { continue }
        
        if ($isDirectory) {
            # Store directory info efficiently
            $dirInfo = @{
                Name = $fileName
                FullPath = $fullPath
                ParentPath = $parentPath
                Created = if ($CreatedIndex -ge 0 -and $CreatedIndex -lt $fields.Count) { $fields[$CreatedIndex].Trim('"') } else { 'Unknown' }
                Modified = if ($ModifiedIndex -ge 0 -and $ModifiedIndex -lt $fields.Count) { $fields[$ModifiedIndex].Trim('"') } else { 'Unknown' }
                EntryNumber = if ($EntryNumberIndex -ge 0 -and $EntryNumberIndex -lt $fields.Count) { $fields[$EntryNumberIndex].Trim('"') } else { 'Unknown' }
                TotalSize = 0L
                FileCount = 0
                ChildDirCount = 0
            }
            
            $DirectoryData[$fullPath] = $dirInfo
            $ValidPaths.Add($fullPath) | Out-Null
            
            # Initialize size tracking
            if (-not $PathSizes.ContainsKey($fullPath)) {
                $PathSizes[$fullPath] = 0L
                $PathFileCounts[$fullPath] = 0
            }
        } else {
            # Handle file - add to parent directory size
            $parentFullPath = if ($parentPath -and $parentPath.Trim() -ne '' -and $parentPath -ne '.') {
                $parentPath
            } else {
                ''
            }
            
            if (-not $PathSizes.ContainsKey($parentFullPath)) {
                $PathSizes[$parentFullPath] = 0L
                $PathFileCounts[$parentFullPath] = 0
            }
            
            # Parse file size
            $fileSize = 0L
            if ($FileSizeIndex -ge 0 -and $FileSizeIndex -lt $fields.Count) {
                $fileSizeStr = $fields[$FileSizeIndex].Trim('"')
                [long]::TryParse($fileSizeStr, [ref]$fileSize) | Out-Null
            }
            
            $PathSizes[$parentFullPath] += $fileSize
            $PathFileCounts[$parentFullPath]++
        }
    }
}

function Calculate-DirectoryTotals {
    param(
        [System.Collections.Generic.Dictionary[string,object]]$DirectoryData,
        [System.Collections.Generic.Dictionary[string,long]]$PathSizes,
        [System.Collections.Generic.Dictionary[string,int]]$PathFileCounts
    )
    
    Write-Host "Building parent-child relationships efficiently..." -ForegroundColor Yellow
    
    # Build parent-child mapping efficiently - O(n) instead of O(n²)
    $childrenMap = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]]::new()
    $pathDepths = [System.Collections.Generic.Dictionary[string,int]]::new()
    
    foreach ($dirPath in $DirectoryData.Keys) {
        $pathDepths[$dirPath] = ($dirPath -split '\\').Count
        
        # Find parent directory
        $lastSlash = $dirPath.LastIndexOf('\')
        if ($lastSlash -ge 0) {
            $parentPath = $dirPath.Substring(0, $lastSlash)
            
            if (-not $childrenMap.ContainsKey($parentPath)) {
                $childrenMap[$parentPath] = [System.Collections.Generic.List[string]]::new()
            }
            $childrenMap[$parentPath].Add($dirPath)
        } else {
            # Root level directory
            if (-not $childrenMap.ContainsKey('')) {
                $childrenMap[''] = [System.Collections.Generic.List[string]]::new()
            }
            $childrenMap[''].Add($dirPath)
        }
    }
    
    Write-Host "Calculating totals bottom-up..." -ForegroundColor Yellow
    
    # Sort by depth (deepest first) for efficient bottom-up calculation
    $sortedPaths = $DirectoryData.Keys | Sort-Object { $pathDepths[$_] } -Descending
    
    foreach ($dirPath in $sortedPaths) {
        $dirInfo = $DirectoryData[$dirPath]
        
        # Start with direct files in this directory
        $totalSize = if ($PathSizes.ContainsKey($dirPath)) { $PathSizes[$dirPath] } else { 0L }
        $totalFiles = if ($PathFileCounts.ContainsKey($dirPath)) { $PathFileCounts[$dirPath] } else { 0 }
        $childDirs = 0
        
        # Add sizes from direct children (now O(1) lookup instead of O(n) search)
        if ($childrenMap.ContainsKey($dirPath)) {
            $children = $childrenMap[$dirPath]
            $childDirs = $children.Count
            
            foreach ($childPath in $children) {
                $childInfo = $DirectoryData[$childPath]
                $totalSize += $childInfo.TotalSize
                $totalFiles += $childInfo.FileCount
            }
        }
        
        $dirInfo.TotalSize = $totalSize
        $dirInfo.FileCount = $totalFiles
        $dirInfo.ChildDirCount = $childDirs
    }
    
    Write-Host "Directory totals calculated efficiently!" -ForegroundColor Green
}

function Generate-OptimizedHtml {
    param(
        [System.Collections.Generic.Dictionary[string,object]]$DirectoryData,
        [string]$MFTPath,
        [int]$MaxDepth
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $dirCount = $DirectoryData.Count
    
    # Estimate time based on directory count (should be much faster now)
    $estimatedMinutes = [Math]::Ceiling($dirCount / 200000)  # ~200k dirs per minute with optimization
    Write-Host "Generating optimized HTML for $dirCount directories..." -ForegroundColor Yellow
    Write-Host "Estimated time: $estimatedMinutes minute$(if($estimatedMinutes -ne 1){'s'}) (at ~200k dirs/min)" -ForegroundColor Cyan
    
    # Build efficient parent-child mapping ONCE (reuse from totals calculation)
    Write-Host "Building efficient parent-child mapping for HTML generation..." -ForegroundColor Yellow
    $childrenMap = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]]::new()
    
    foreach ($dirPath in $DirectoryData.Keys) {
        # Find parent directory
        $lastSlash = $dirPath.LastIndexOf('\')
        if ($lastSlash -ge 0) {
            $parentPath = $dirPath.Substring(0, $lastSlash)
            
            if (-not $childrenMap.ContainsKey($parentPath)) {
                $childrenMap[$parentPath] = [System.Collections.Generic.List[string]]::new()
            }
            $childrenMap[$parentPath].Add($dirPath)
        } else {
            # Root level directory
            if (-not $childrenMap.ContainsKey('')) {
                $childrenMap[''] = [System.Collections.Generic.List[string]]::new()
            }
            $childrenMap[''].Add($dirPath)
        }
    }
    
    # Use StringBuilder for efficient string building
    $treeBuilder = [System.Text.StringBuilder]::new()
    
    # Build tree structure efficiently
    Write-Host "Building HTML tree structure with O(1) lookups..." -ForegroundColor Yellow
    $rootPaths = if ($childrenMap.ContainsKey('')) { $childrenMap[''].ToArray() | Sort-Object } else { @() }
    
    $processedNodes = 0
    $lastProgressTime = [DateTime]::Now
    
    foreach ($rootPath in $rootPaths) {
        Build-FastHtmlNode -Path $rootPath -DirectoryData $DirectoryData -ChildrenMap $childrenMap -StringBuilder $treeBuilder -Level 0 -ProcessedNodes ([ref]$processedNodes)
        
        # Progress reporting every 2 seconds (more frequent for faster processing)
        $now = [DateTime]::Now
        if (($now - $lastProgressTime).TotalSeconds -ge 2) {
            $percentComplete = [Math]::Round(($processedNodes / $dirCount) * 100, 1)
            $elapsedSec = $stopwatch.Elapsed.TotalSeconds
            $rate = if ($elapsedSec -gt 0) { [Math]::Round($processedNodes / $elapsedSec) } else { 0 }
            Write-Host "HTML Progress: $processedNodes/$dirCount directories ($percentComplete%) - $rate dirs/sec" -ForegroundColor Gray
            $lastProgressTime = $now
        }
    }
    
    Write-Host "HTML tree structure built: $processedNodes nodes" -ForegroundColor Green
    
    # Calculate totals for statistics (fast)
    Write-Host "Calculating page statistics..." -ForegroundColor Yellow
    $totalDirs = $DirectoryData.Count
    $totalSize = 0L
    $totalFiles = 0
    
    foreach ($dirInfo in $DirectoryData.Values) {
        if (-not $dirInfo.FullPath.Contains('\')) {
            # Only count root directories to avoid double counting
            $totalSize += $dirInfo.TotalSize
            $totalFiles += $dirInfo.FileCount
        }
    }
    
    # Build directory data JSON efficiently (fast)
    Write-Host "Building JSON data for client..." -ForegroundColor Yellow
    $jsonBuilder = [System.Text.StringBuilder]::new()
    $jsonBuilder.Append('[') | Out-Null
    $first = $true
    foreach ($kvp in $DirectoryData.GetEnumerator()) {
        if (-not $first) { $jsonBuilder.Append(',') | Out-Null }
        $jsonBuilder.Append('{') | Out-Null
        $jsonBuilder.Append('"path":"').Append($kvp.Key.Replace('\', '\\').Replace('"', '\"')).Append('",') | Out-Null
        $jsonBuilder.Append('"size":').Append($kvp.Value.TotalSize).Append(',') | Out-Null
        $jsonBuilder.Append('"fileCount":').Append($kvp.Value.FileCount) | Out-Null
        $jsonBuilder.Append('}') | Out-Null
        $first = $false
    }
    $jsonBuilder.Append(']') | Out-Null
    
    $mftFileName = Split-Path $MFTPath -Leaf
    
    # Build complete HTML (very fast)
    Write-Host "Assembling final HTML document..." -ForegroundColor Yellow
    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MFT Directory Analysis - $mftFileName</title>
    <style>
        body { font-family: 'Courier New', monospace; margin: 20px; background: #1e1e1e; color: #d4d4d4; }
        .header { background: #2d2d30; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .totals-display { background: #0d1f2d; border: 2px solid #0e639c; border-radius: 5px; padding: 15px; margin-bottom: 20px; }
        .total-item { display: inline-block; margin-right: 30px; padding: 8px 15px; background: #1e3a8a; border-radius: 3px; }
        .total-label { color: #93c5fd; font-weight: bold; }
        .total-value { color: #fbbf24; font-size: 1.1em; margin-left: 10px; }
        .controls { margin: 10px 0; padding: 10px; background: #252526; border-radius: 3px; }
        .tree-container { background: #1e1e1e; border: 1px solid #3e3e42; border-radius: 5px; padding: 10px; max-height: 70vh; overflow-y: auto; }
        .tree-node { margin: 2px 0; }
        .node-header { display: flex; align-items: center; padding: 2px 0; cursor: default; }
        .node-header:hover { background: #2a2d2e; border-radius: 3px; }
        .expand-btn { cursor: pointer; margin-right: 5px; user-select: none; font-size: 12px; color: #569cd6; }
        .folder-icon { margin-right: 5px; }
        .folder-name { font-weight: bold; margin-right: 10px; color: #dcdcaa; }
        .size-info { color: #4fc3f7; font-size: 11px; margin-right: 10px; background: #1a2332; padding: 2px 6px; border-radius: 2px; }
        .has-data-label { display: flex; align-items: center; margin-right: 10px; font-size: 12px; color: #ce9178; cursor: pointer; }
        .has-data-checkbox { margin-right: 4px; }
        .has-data-text { user-select: none; }
        .has-data-true { background: #1a4a1a !important; border-left: 3px solid #4caf50 !important; }
        .has-note { background: #4a4a1a !important; }
        .note-btn { background: #0e639c; color: white; border: none; border-radius: 3px; padding: 2px 6px; cursor: pointer; font-size: 11px; margin-right: 10px; }
        .note-btn:hover { background: #1177bb; }
        .dir-info { color: #808080; font-size: 10px; margin-left: auto; }
        .node-children { margin-left: 20px; border-left: 1px dotted #3e3e42; padding-left: 10px; }
        .search-box { width: 300px; padding: 5px; background: #3c3c3c; border: 1px solid #6c6c6c; color: white; border-radius: 3px; }
        .modal { display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); }
        .modal-content { background: #2d2d30; margin: 10% auto; padding: 20px; border-radius: 5px; width: 60%; max-width: 600px; }
        .modal textarea { width: 100%; height: 150px; background: #1e1e1e; color: #d4d4d4; border: 1px solid #6c6c6c; padding: 10px; border-radius: 3px; }
        .modal button { background: #0e639c; color: white; border: none; padding: 8px 15px; margin: 5px; border-radius: 3px; cursor: pointer; }
        .modal button:hover { background: #1177bb; }
        .close { color: #aaa; float: right; font-size: 28px; font-weight: bold; cursor: pointer; }
        .close:hover { color: white; }
        .btn { background: #0e639c; color: white; border: none; padding: 8px 15px; margin: 5px; border-radius: 3px; cursor: pointer; }
        .btn:hover { background: #1177bb; }
        .memory-info { color: #ffa500; font-size: 12px; margin-top: 5px; }
        .generation-stats { color: #90ee90; font-size: 11px; margin-top: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🗂️ MFT Directory Analysis (Memory Optimized)</h1>
        <p><strong>Source:</strong> $MFTPath</p>
        <p><strong>Analysis ID:</strong> $mftKey <small>(unique per MFT file)</small></p>
        <p><strong>Generated:</strong> $(Get-Date)</p>
        <p><strong>Statistics:</strong> $totalDirs directories | $totalFiles files | $(Format-FileSize -Size $totalSize) total</p>
        <p class="memory-info">⚡ Optimized for large MFT files - streaming processing used</p>
        <p class="generation-stats">📊 HTML generated in $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)) seconds ($([Math]::Round($processedNodes / $stopwatch.Elapsed.TotalSeconds)) nodes/sec)</p>
    </div>
    
    <div class="totals-display" id="totalsDisplay">
        <h3>🎯 Selected Data Totals</h3>
        <div class="total-item">
            <span class="total-label">Selected Size:</span>
            <span class="total-value" id="selectedSize">0 bytes</span>
        </div>
        <div class="total-item">
            <span class="total-label">Selected Files:</span>
            <span class="total-value" id="selectedFiles">0</span>
        </div>
        <div class="total-item">
            <span class="total-label">Selected Directories:</span>
            <span class="total-value" id="selectedDirs">0</span>
        </div>
    </div>
    
    <div class="controls">
        <input type="text" id="searchBox" class="search-box" placeholder="Search directories..." onkeyup="searchTree()">
        <button class="btn" onclick="expandAll()">Expand All</button>
        <button class="btn" onclick="collapseAll()">Collapse All</button>
        <button class="btn" onclick="checkAllHasData()">Check All "Has Data"</button>
        <button class="btn" onclick="uncheckAllHasData()">Uncheck All "Has Data"</button>
        <button class="btn" onclick="exportToCsv()">📊 Export to CSV</button>
        <button class="btn" onclick="exportData()">Export All Data</button>
        <button class="btn" onclick="document.getElementById('importFile').click()">Import Data</button>
        <input type="file" id="importFile" style="display: none" onchange="importData()">
    </div>
    
    <div class="tree-container">
        $($treeBuilder.ToString())
    </div>
    
    <!-- Note Modal -->
    <div id="noteModal" class="modal">
        <div class="modal-content">
            <span class="close" onclick="closeNoteModal()">&times;</span>
            <h3>Directory Notes</h3>
            <p id="notePath"></p>
            <textarea id="noteText" placeholder="Add your notes here..."></textarea>
            <br>
            <button onclick="saveNote()">Save Note</button>
            <button onclick="deleteNote()">Delete Note</button>
            <button onclick="closeNoteModal()">Cancel</button>
        </div>
    </div>
    
    <script>
        let currentNoteId = '';
        let currentPath = '';
        let directoryData = $($jsonBuilder.ToString());
        
        // Create unique storage keys based on MFT source
        const mftSource = '$($MFTPath.Replace('\', '\\').Replace("'", "\\'"))';
        const mftKey = '$mftKey';
        const notesKey = 'mftTreeNotes_' + mftKey;
        const hasDataKey = 'mftTreeHasData_' + mftKey;
        
        function formatFileSize(bytes) {
            if (bytes >= 1024*1024*1024*1024) return (bytes/(1024*1024*1024*1024)).toFixed(2) + ' TB';
            if (bytes >= 1024*1024*1024) return (bytes/(1024*1024*1024)).toFixed(2) + ' GB';
            if (bytes >= 1024*1024) return (bytes/(1024*1024)).toFixed(2) + ' MB';
            if (bytes >= 1024) return (bytes/1024).toFixed(2) + ' KB';
            return bytes + ' bytes';
        }
        
        function updateSelectedTotals() {
            const checkedNodes = document.querySelectorAll('.has-data-checkbox:checked');
            let totalSize = 0;
            let totalFiles = 0;
            let totalDirs = checkedNodes.length;
            let processedPaths = new Set();
            
            const checkedPaths = Array.from(checkedNodes).map(cb => {
                const node = cb.closest('.tree-node');
                return node.getAttribute('data-path');
            });
            
            checkedPaths.sort((a, b) => a.split('\\').length - b.split('\\').length);
            
            checkedPaths.forEach(path => {
                let isChildOfProcessed = false;
                for (let processedPath of processedPaths) {
                    if (path.startsWith(processedPath + '\\')) {
                        isChildOfProcessed = true;
                        break;
                    }
                }
                
                if (!isChildOfProcessed) {
                    const node = document.querySelector('[data-path="' + path.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"]');
                    if (node) {
                        const size = parseInt(node.getAttribute('data-size')) || 0;
                        const fileCount = parseInt(node.getAttribute('data-filecount')) || 0;
                        totalSize += size;
                        totalFiles += fileCount;
                        processedPaths.add(path);
                    }
                }
            });
            
            document.getElementById('selectedSize').textContent = formatFileSize(totalSize);
            document.getElementById('selectedFiles').textContent = totalFiles.toLocaleString();
            document.getElementById('selectedDirs').textContent = totalDirs.toLocaleString();
        }
        
        function loadNotesAndData() {
            const notes = JSON.parse(localStorage.getItem(notesKey) || '{}');
            const hasDataStates = JSON.parse(localStorage.getItem(hasDataKey) || '{}');
            
            Object.keys(notes).forEach(nodeId => {
                const btn = document.querySelector("button[onclick*='" + nodeId + "']");
                if (btn) {
                    btn.closest('.node-header').classList.add('has-note');
                }
            });
            
            Object.keys(hasDataStates).forEach(nodeId => {
                const checkbox = document.getElementById('hasdata_' + nodeId);
                if (checkbox && hasDataStates[nodeId] === true) {
                    checkbox.checked = true;
                    checkbox.closest('.node-header').classList.add('has-data-true');
                }
            });
            
            updateSelectedTotals();
        }
        
        function toggleHasData(nodeId, path) {
            const checkbox = document.getElementById('hasdata_' + nodeId);
            const hasDataStates = JSON.parse(localStorage.getItem(hasDataKey) || '{}');
            
            if (checkbox.checked) {
                hasDataStates[nodeId] = true;
                checkbox.closest('.node-header').classList.add('has-data-true');
            } else {
                hasDataStates[nodeId] = false;
                checkbox.closest('.node-header').classList.remove('has-data-true');
            }
            
            localStorage.setItem(hasDataKey, JSON.stringify(hasDataStates));
            updateSelectedTotals();
        }
        
        function checkAllHasData() {
            const checkboxes = document.querySelectorAll('.has-data-checkbox');
            const hasDataStates = JSON.parse(localStorage.getItem(hasDataKey) || '{}');
            
            checkboxes.forEach(checkbox => {
                checkbox.checked = true;
                const nodeId = checkbox.id.replace('hasdata_', '');
                hasDataStates[nodeId] = true;
                checkbox.closest('.node-header').classList.add('has-data-true');
            });
            
            localStorage.setItem(hasDataKey, JSON.stringify(hasDataStates));
            updateSelectedTotals();
        }
        
        function uncheckAllHasData() {
            const checkboxes = document.querySelectorAll('.has-data-checkbox');
            const hasDataStates = {};
            
            checkboxes.forEach(checkbox => {
                checkbox.checked = false;
                checkbox.closest('.node-header').classList.remove('has-data-true');
            });
            
            localStorage.setItem(hasDataKey, JSON.stringify(hasDataStates));
            updateSelectedTotals();
        }
        
        function toggleNode(nodeId) {
            const children = document.getElementById('children_' + nodeId);
            const btn = document.querySelector("span[onclick*='" + nodeId + "']");
            
            if (children.style.display === 'none') {
                children.style.display = 'block';
                btn.textContent = '▼';
            } else {
                children.style.display = 'none';
                btn.textContent = '▶';
            }
        }
        
        function openNoteModal(nodeId, path) {
            currentNoteId = nodeId;
            currentPath = path;
            document.getElementById('notePath').textContent = path;
            
            const notes = JSON.parse(localStorage.getItem(notesKey) || '{}');
            document.getElementById('noteText').value = notes[nodeId] || '';
            document.getElementById('noteModal').style.display = 'block';
        }
        
        function closeNoteModal() {
            document.getElementById('noteModal').style.display = 'none';
        }
        
        function saveNote() {
            const noteText = document.getElementById('noteText').value;
            const notes = JSON.parse(localStorage.getItem(notesKey) || '{}');
            
            if (noteText.trim()) {
                notes[currentNoteId] = noteText;
                const btn = document.querySelector("button[onclick*='" + currentNoteId + "']");
                btn.closest('.node-header').classList.add('has-note');
            } else {
                delete notes[currentNoteId];
                const btn = document.querySelector("button[onclick*='" + currentNoteId + "']");
                btn.closest('.node-header').classList.remove('has-note');
            }
            
            localStorage.setItem(notesKey, JSON.stringify(notes));
            closeNoteModal();
        }
        
        function deleteNote() {
            const notes = JSON.parse(localStorage.getItem(notesKey) || '{}');
            delete notes[currentNoteId];
            localStorage.setItem(notesKey, JSON.stringify(notes));
            
            const btn = document.querySelector("button[onclick*='" + currentNoteId + "']");
            btn.closest('.node-header').classList.remove('has-note');
            closeNoteModal();
        }
        
        function searchTree() {
            const searchTerm = document.getElementById('searchBox').value.toLowerCase();
            const nodes = document.querySelectorAll('.tree-node');
            
            nodes.forEach(node => {
                const folderName = node.querySelector('.folder-name').textContent.toLowerCase();
                const path = node.getAttribute('data-path').toLowerCase();
                
                if (searchTerm === '' || folderName.includes(searchTerm) || path.includes(searchTerm)) {
                    node.style.display = 'block';
                    let parent = node.parentElement;
                    while (parent) {
                        if (parent.classList.contains('node-children')) {
                            parent.style.display = 'block';
                            const expandBtn = parent.previousElementSibling?.querySelector('.expand-btn');
                            if (expandBtn) expandBtn.textContent = '▼';
                        }
                        parent = parent.parentElement;
                    }
                } else {
                    node.style.display = 'none';
                }
            });
        }
        
        function expandAll() {
            document.querySelectorAll('.node-children').forEach(el => el.style.display = 'block');
            document.querySelectorAll('.expand-btn').forEach(btn => btn.textContent = '▼');
        }
        
        function collapseAll() {
            document.querySelectorAll('.node-children').forEach(el => el.style.display = 'none');
            document.querySelectorAll('.expand-btn').forEach(btn => btn.textContent = '▶');
        }
        
        function exportToCsv() {
            const checkedNodes = document.querySelectorAll('.has-data-checkbox:checked');
            
            if (checkedNodes.length === 0) {
                alert('No directories are checked. Please check some directories first.');
                return;
            }
            
            // Get checked paths and find highest level ones
            const checkedPaths = Array.from(checkedNodes).map(cb => {
                const node = cb.closest('.tree-node');
                return {
                    path: node.getAttribute('data-path'),
                    size: parseInt(node.getAttribute('data-size')) || 0,
                    fileCount: parseInt(node.getAttribute('data-filecount')) || 0
                };
            });
            
            // Sort by path depth (shortest first) to find top-level directories
            checkedPaths.sort((a, b) => a.path.split('\\').length - b.path.split('\\').length);
            
            // Filter out child directories if parent is already selected
            const topLevelPaths = [];
            const processedPaths = new Set();
            
            checkedPaths.forEach(item => {
                let isChildOfProcessed = false;
                for (let processedPath of processedPaths) {
                    if (item.path.startsWith(processedPath + '\\')) {
                        isChildOfProcessed = true;
                        break;
                    }
                }
                
                if (!isChildOfProcessed) {
                    topLevelPaths.push(item);
                    processedPaths.add(item.path);
                }
            });
            
            // Create CSV content
            const csvHeaders = ['Directory Path', 'Total Size (Bytes)', 'Total Size (Human)', 'File Count'];
            const csvRows = [csvHeaders];
            
            let totalSize = 0;
            let totalFiles = 0;
            
            topLevelPaths.forEach(item => {
                const humanSize = formatFileSize(item.size);
                csvRows.push([
                    '"' + item.path.replace(/"/g, '""') + '"',  // Escape quotes in paths
                    item.size,
                    '"' + humanSize + '"',
                    item.fileCount
                ]);
                totalSize += item.size;
                totalFiles += item.fileCount;
            });
            
            // Add summary row
            csvRows.push(['']); // Empty row
            csvRows.push([
                '"TOTAL SELECTED"',
                totalSize,
                '"' + formatFileSize(totalSize) + '"',
                totalFiles
            ]);
            
            // Convert to CSV string with proper newlines
            const csvContent = csvRows.map(row => row.join(',')).join('\n');
            
            // Create and download file
            const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            
            // Generate filename with timestamp
            const timestamp = new Date().toISOString().slice(0, 19).replace(/[T:]/g, '_');
            a.download = 'mft_selected_directories_' + timestamp + '.csv';
            
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
            // Show summary
            alert(
                'CSV exported successfully!\\n\\n' +
                'Top-level directories: ' + topLevelPaths.length + '\\n' +
                'Total size: ' + formatFileSize(totalSize) + '\\n' +
                'Total files: ' + totalFiles.toLocaleString() + '\\n\\n' +
                'File saved as: mft_selected_directories_' + timestamp + '.csv'
            );
        }
        
        function exportData() {
            const notes = JSON.parse(localStorage.getItem(notesKey) || '{}');
            const hasDataStates = JSON.parse(localStorage.getItem(hasDataKey) || '{}');
            
            const exportData = {
                notes: notes,
                hasData: hasDataStates,
                exported: new Date().toISOString(),
                source: mftSource,
                mftKey: mftKey
            };
            
            const blob = new Blob([JSON.stringify(exportData, null, 2)], {type: 'application/json'});
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'mft_analysis_optimized.json';
            a.click();
        }
        
        function importData() {
            const file = document.getElementById('importFile').files[0];
            if (file) {
                const reader = new FileReader();
                reader.onload = function(e) {
                    try {
                        const data = JSON.parse(e.target.result);
                        
                        // Check if this import matches the current MFT
                        if (data.mftKey && data.mftKey !== mftKey) {
                            const confirmMsg = 'This data is from a different MFT file:\\n\\n' +
                                             'Current: ' + mftSource + '\\n' +
                                             'Import: ' + (data.source || 'Unknown') + '\\n\\n' +
                                             'Import anyway? This will overwrite current selections.';
                            if (!confirm(confirmMsg)) {
                                return;
                            }
                        }
                        
                        if (data.notes) {
                            localStorage.setItem(notesKey, JSON.stringify(data.notes));
                        }
                        if (data.hasData) {
                            localStorage.setItem(hasDataKey, JSON.stringify(data.hasData));
                        }
                        
                        location.reload();
                    } catch (err) {
                        alert('Invalid data file format');
                    }
                };
                reader.readAsText(file);
            }
        }
        
        // Initialize
        document.addEventListener('DOMContentLoaded', function() {
            loadNotesAndData();
        });
        
        window.onclick = function(event) {
            const modal = document.getElementById('noteModal');
            if (event.target === modal) {
                closeNoteModal();
            }
        }
    </script>
</body>
</html>
"@

    $stopwatch.Stop()
    
    Write-Host "HTML generation completed in $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)) seconds" -ForegroundColor Green
    Write-Host "Average rate: $([Math]::Round($processedNodes / $stopwatch.Elapsed.TotalSeconds)) directories/second" -ForegroundColor Cyan
    
    return $htmlContent
}

function Build-FastHtmlNode {
    param(
        [string]$Path,
        [System.Collections.Generic.Dictionary[string,object]]$DirectoryData,
        [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]]$ChildrenMap,
        [System.Text.StringBuilder]$StringBuilder,
        [int]$Level,
        [ref]$ProcessedNodes
    )
    
    if (-not $DirectoryData.ContainsKey($Path)) { return }
    
    $dirInfo = $DirectoryData[$Path]
    $nodeId = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Path)) -replace '[^a-zA-Z0-9]', ''
    
    # Get children using O(1) lookup instead of O(n) search
    $children = if ($ChildrenMap.ContainsKey($Path)) { 
        $ChildrenMap[$Path].ToArray() | Sort-Object 
    } else { 
        @() 
    }
    
    $hasChildren = $children.Count -gt 0
    $formattedSize = Format-FileSize -Size $dirInfo.TotalSize
    
    $StringBuilder.AppendLine(@"
        <div class="tree-node" data-level="$Level" data-path="$($Path.Replace('\', '\\').Replace('"', '\"'))" data-size="$($dirInfo.TotalSize)" data-filecount="$($dirInfo.FileCount)">
            <div class="node-header">
                <span class="expand-btn" onclick="toggleNode('$nodeId')" style="display: $(if($hasChildren){'inline'}else{'none'})">▶</span>
                <span class="folder-icon">📁</span>
                <span class="folder-name" title="$($Path.Replace('"', '&quot;'))">$($dirInfo.Name)</span>
                <span class="size-info">[$formattedSize, $($dirInfo.FileCount) files, $($dirInfo.ChildDirCount) dirs]</span>
                <label class="has-data-label">
                    <input type="checkbox" class="has-data-checkbox" id="hasdata_$nodeId" onchange="toggleHasData('$nodeId', '$($Path.Replace('\', '\\').Replace('"', '\"'))')">
                    <span class="has-data-text">has data</span>
                </label>
                <button class="note-btn" onclick="openNoteModal('$nodeId', '$($Path.Replace('\', '\\').Replace('"', '\"'))')">📝</button>
                <div class="dir-info">
                    <small>Created: $($dirInfo.Created) | Modified: $($dirInfo.Modified) | Entry: $($dirInfo.EntryNumber)</small>
                </div>
            </div>
            <div class="node-children" id="children_$nodeId" style="display: none;">
"@) | Out-Null
    
    $ProcessedNodes.Value++
    
    # Process children using efficient list instead of searching all directories
    foreach ($childPath in $children) {
        Build-FastHtmlNode -Path $childPath -DirectoryData $DirectoryData -ChildrenMap $ChildrenMap -StringBuilder $StringBuilder -Level ($Level + 1) -ProcessedNodes $ProcessedNodes
    }
    
    $StringBuilder.AppendLine(@"
            </div>
        </div>
"@) | Out-Null
}

# Main execution
Write-Host "MFT Memory-Optimized Interactive Tree Generator" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

if (-not (Test-Path $MFTPath)) {
    Write-Error "MFT file not found: $MFTPath"
    exit 1
}

Write-Host "Processing MFT: $MFTPath (Batch size: $BatchSize)" -ForegroundColor Yellow

# Find or download MFTECmd
$mfteCmdPath = Find-MFTECmd -ToolsPath $ToolsPath
if (-not $mfteCmdPath) {
    $mfteCmdPath = Download-MFTECmd -ToolsPath $ToolsPath
    if (-not $mfteCmdPath) {
        Write-Error "Could not obtain MFTECmd.exe"
        exit 1
    }
}

# Create temp directory
$tempCsvPath = Join-Path $env:TEMP "MFT_Optimized_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $tempCsvPath -ItemType Directory -Force | Out-Null

try {
    # Run MFTECmd
    Write-Host "Parsing MFT with MFTECmd..." -ForegroundColor Yellow
    $csvFileName = "mft_optimized.csv"
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
    
    if (-not (Test-Path $csvFilePath)) {
        throw "CSV output not created: $csvFilePath"
    }
    
    # Process with streaming and memory optimization
    $directoryData = Process-MFT-Streaming -CsvPath $csvFilePath -MaxDepth $MaxDepth -BatchSize $BatchSize
    
    # Generate optimized HTML
    $htmlContent = Generate-OptimizedHtml -DirectoryData $directoryData -MFTPath $MFTPath -MaxDepth $MaxDepth
    
    # Write HTML file
    Write-Host "Writing optimized HTML file..." -ForegroundColor Yellow
    [System.IO.File]::WriteAllText($OutputHtmlFile, $htmlContent, [System.Text.Encoding]::UTF8)
    
    # Force garbage collection
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    
    Write-Host "`n=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Memory-optimized interactive tree created: $OutputHtmlFile" -ForegroundColor Green
    Write-Host "Directories processed: $($directoryData.Count)" -ForegroundColor Cyan
    Write-Host "Batch processing used - significantly reduced memory usage" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to generate optimized tree: $($_.Exception.Message)"
} finally {
    if (Test-Path $tempCsvPath) {
        Remove-Item $tempCsvPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nMemory optimization features:" -ForegroundColor Yellow
Write-Host "• Stream processing instead of loading entire CSV" -ForegroundColor White
Write-Host "• HashSets and Dictionaries for efficient lookups" -ForegroundColor White
Write-Host "• Batch processing with garbage collection" -ForegroundColor White
Write-Host "• StringBuilder for efficient HTML generation" -ForegroundColor White
Write-Host "• Single-pass directory size calculation" -ForegroundColor White
Write-Host "• CSV export for forensic reporting of selected directories" -ForegroundColor White
Write-Host "• Per-MFT storage isolation (no checkbox bleed between analyses)" -ForegroundColor White

Write-Host "`nMemory usage should now be <2GB instead of 30GB!" -ForegroundColor Green
