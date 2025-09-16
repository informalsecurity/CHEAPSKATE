# CHEAPSKATE
## Comprehensive Hierarchical Exfiltration Analysis & Pre-Sorting Kit for Affordable Triage Examination

🕵️ **Save $100K-millions on forensic analysis fees by pre-sorting your data breach evidence**

CHEAPSKATE is a PowerShell-based tool that creates interactive HTML directory trees from MFT (Master File Table) files, allowing security teams to quickly identify and categorize exfiltrated data before sending it to expensive forensic vendors.

---

## 🎯 **Use Case: Data Breach Response**

**The Problem:**
- Data exfiltration incident occurs
- Forensic vendors charge $500-2000/hour to analyze directory structures
- You need to report which records were stolen (GDPR, CCPA, etc.)
- Sending entire drives = massive forensic bills

**The Solution:**
- Extract MFT from compromised systems
- Use CHEAPSKATE to create interactive directory tree
- Security team pre-sorts directories into "has sensitive data" vs "irrelevant"
- Send only marked directories to forensic vendor
- **Result: 70-90% reduction in forensic analysis costs**

---

## ✨ **Key Features**

### 🌳 **Interactive Directory Tree**
- Collapsible directory structure with size information
- Click arrows to expand/collapse branches
- Real-time search across all directories
- Professional dark theme optimized for long analysis sessions

### 📊 **Smart Data Tracking**
- **"Has Data" checkboxes** - mark directories containing sensitive information
- **Running totals** - see cumulative size/file count of selected directories
- **Smart parent/child logic** - prevents double-counting when both parent and child are selected
- **Persistent notes** - add investigation notes to directories

### 📈 **Professional Reporting**
- **CSV export** of selected directories with size data
- **JSON export/import** of all analysis data for team collaboration
- **Forensic documentation** ready for legal proceedings
- **Unique per-MFT storage** - no cross-contamination between cases

### ⚡ **Enterprise Performance**
- **Memory optimized** - handles multi-million record MFTs with <2GB RAM
- **Streaming processing** - no more 30GB+ memory usage
- **Batch processing** with progress reporting
- **O(n) algorithms** - linear scaling for massive datasets

---

## 🚀 **Quick Start**

### Prerequisites
- Windows PowerShell 5.1+
- MFT file extracted from compromised system (using tools like FTK Imager, etc.)

### Installation
```powershell
# Clone the repository
git clone https://github.com/yourusername/CHEAPSKATE.git
cd CHEAPSKATE

# Run the tool
.\Generate-MemoryOptimizedTree.ps1 -MFTPath "C:\Evidence\$MFT" -OutputHtmlFile "C:\Analysis\breach_analysis.html"
```

### Basic Usage
```powershell
# Analyze MFT with default settings
.\Generate-MemoryOptimizedTree.ps1 -MFTPath ".\evidence\$MFT" -OutputHtmlFile ".\analysis.html"

# Custom depth limit for faster processing
.\Generate-MemoryOptimizedTree.ps1 -MFTPath ".\evidence\$MFT" -OutputHtmlFile ".\analysis.html" -MaxDepth 8

# Smaller batch size for very large MFTs
.\Generate-MemoryOptimizedTree.ps1 -MFTPath ".\evidence\$MFT" -OutputHtmlFile ".\analysis.html" -BatchSize 5000
```

---

## 📋 **Workflow Example**

### Step 1: Generate Analysis
```powershell
.\Generate-MemoryOptimizedTree.ps1 -MFTPath "C:\Evidence\Suspect_MFT" -OutputHtmlFile "C:\Analysis\breach_triage.html"
```

### Step 2: Security Team Analysis
1. Open `breach_triage.html` in browser
2. Search for sensitive directory names (`Documents`, `Database`, `Confidential`, etc.)
3. Check "has data" boxes for directories containing sensitive information
4. Add investigation notes to key directories
5. Monitor running totals at top of page

### Step 3: Generate Reports
1. **CSV Export**: Click "📊 Export to CSV" for spreadsheet analysis
2. **Team Collaboration**: Export analysis data as JSON to share with team
3. **Forensic Vendor**: Send only marked directories for detailed analysis

### Step 4: Cost Savings
- **Before**: Send entire Drive → $50K-200K forensic bill
- **After**: Send pre-sorted evidence → $5K-20K forensic bill (no need to pay them to scan your ISO's and CAB files)
- **Savings**: 70-90% reduction in vendor costs

---

## 💾 **Performance Specifications**

| MFT Size | Directories | Processing Time | Memory Usage | HTML Generation |
|----------|-------------|-----------------|--------------|-----------------|
| Small    | 10K dirs    | 30-60 seconds   | <500MB       | 10-20 seconds   |
| Medium   | 100K dirs   | 5-10 minutes    | <1GB         | 2-4 minutes     |
| Large    | 500K dirs   | 30-60 minutes   | <2GB         | 10-15 minutes   |
| Enterprise| 1M+ dirs    | 60-120 minutes  | <3GB         | 20-30 minutes   |

**Tested with MFTs up to 2.5 million directory records**

---

## 🎨 **Features Overview**

### Interactive Interface
- **Expand/Collapse All** buttons for quick navigation
- **Real-time search** with instant filtering
- **Bulk operations** - check/uncheck all directories at once
- **Progress tracking** with time estimates during generation

### Data Analysis
- **Directory sizes** calculated recursively (includes all subdirectories/files)
- **File counts** for capacity planning
- **Creation/modification timestamps** for timeline analysis
- **Entry numbers** for advanced forensic correlation

### Professional Output
- **Timestamped CSV exports** with summary totals
- **Legal-ready documentation** format
- **Cross-platform compatibility** (HTML works on any OS)
- **Offline capability** - no internet connection required

---

## 🛠️ **Technical Details**

### Dependencies
- **MFTECmd.exe** - Downloaded automatically from Eric Zimmerman's tools
- **PowerShell 5.1+** - Built-in Windows capability
- **Modern browser** - Chrome, Firefox, Edge for viewing results

### Architecture
- **Streaming CSV processing** - never loads entire dataset in memory
- **Efficient data structures** - HashSets and Dictionaries for O(1) lookups
- **StringBuilder HTML generation** - prevents string fragmentation
- **Garbage collection** - explicit memory management between batches

### Security
- **Local processing only** - no data leaves your environment
- **Browser localStorage** - analysis data stored locally per MFT file
- **No network dependencies** - works in air-gapped environments

---

## 📊 **Return on Investment**

### Typical Data Breach Costs
| Item | Without CHEAPSKATE | With CHEAPSKATE | Savings |
|------|----------------|-------------|---------|
| Forensic Analysis | $150,000 | $25,000 | $125,000 |
| Time to Report | 3-4 weeks | 1-2 weeks | 2-3 weeks |
| Legal Prep Time | 80 hours | 20 hours | 60 hours |
| **Total Savings** | | | **$200K+** |

### Time Savings
- **Directory identification**: Hours instead of weeks
- **Scope definition**: Minutes instead of days  
- **Report generation**: Automated instead of manual
- **Vendor communication**: Precise instead of exploratory

---

## 🤝 **Contributing**

We welcome contributions! Areas for enhancement:
- Additional export formats (XML, database formats)
- Integration with other forensic tools
- Advanced filtering/search capabilities
- Automated sensitive data detection
- API integration for SIEM/SOAR platforms

### Development Setup
```bash
git clone https://github.com/yourusername/CHEAPSKATE.git
cd CHEAPSKATE
# Make your changes
# Test with various MFT sizes
# Submit pull request
```

---


Perfect for:
- Law firms handling data breaches
- Corporate security teams  
- Forensic consultancies
- Incident response teams
- Compliance officers

---

## 🆘 **Support & Issues**

- **Bug Reports**: Use GitHub issues with MFT size and error details
- **Feature Requests**: Tag as enhancement in issues
- **Performance Issues**: Include system specs and MFT characteristics

### Common Issues
- **High memory usage**: Reduce batch size parameter
- **Slow HTML generation**: Use lower MaxDepth setting
- **MFTECmd not found**: Tool downloads automatically on first run
- **CSV export malformed**: Known issue fixed in latest version

---


---

**⭐ If CHEAPSKATE saved your organization money, please star the repo!**

**Built by security professionals, for security professionals fighting the good fight against overpriced forensic vendors.** 🥷
