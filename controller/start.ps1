# ==============================================================================
# Alice Project: Windows Runtime Controller
# Copyright (C) 2026 Override Development
# GNU General Public License version 3 or later.
# ==============================================================================

$ErrorActionPreference = "Stop"

# Configuration
$Root = Split-Path -Parent $PSScriptRoot
$ModelRoot = Join-Path $Root "model"
$CorpusRoot = Join-Path $Root "corpus"
$BinRoot = Join-Path $Root "bin"
$LogRoot = Join-Path $Root "logs"

# All runtime services bind to loopback; keep these aligned with each service configuration.
$MemoryHost = "127.0.0.1"
$EvidenceHost = "127.0.0.1"
$InferenceHost = "127.0.0.1"
$AliceHost = "127.0.0.1"

$MemoryPort = 8090
$EvidencePort = 60005
$InferencePort = 50006
$AlicePort = 8080
$CorpusRecordElement = "page"
$InferenceContextSize = 8192
$PollIntervalSeconds = 3
$RunId = Get-Date -Format "yyyyMMdd-HHmmss-fff"

$script:ManagedProcesses = @()
$script:Services = @()
$script:RuntimeReadyAnnounced = $false
$script:EvidenceReadyAnnounced = $false
$script:VmConfig = @{}
$script:VmEnabled = $false
$script:VmStartedByController = $false
$script:VmShutdownOnExit = $true
$script:VmStartOnLaunch = $true
$script:VmName = ""
$script:VmGuestUser = ""
$script:VmGuestPasswordFile = ""
$script:VmVBoxManagePath = ""

function Get-VMSetting {
    param([string]$Name, $Default)

    $environmentValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue
    }
    if ($script:VmConfig.ContainsKey($Name)) {
        return $script:VmConfig[$Name]
    }
    return $Default
}

function ConvertTo-VMBoolean {
    param($Value, [string]$Name)
    if ($Value -is [bool]) { return $Value }
    $text = [string]$Value
    if ($text -match '^(?i:true|1|yes|on)$') { return $true }
    if ($text -match '^(?i:false|0|no|off)$') { return $false }
    throw ("Invalid boolean value for {0}: {1}" -f $Name, $text)
}

function ConvertTo-VMInteger {
    param($Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse([string]$Value, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw ("{0} must be a whole number between {1} and {2}." -f $Name, $Minimum, $Maximum)
    }
    return $number
}

function Invoke-VBoxManage {
    param([string[]]$Arguments)
    $output = & $script:VmVBoxManagePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ("VBoxManage {0} failed with exit code {1}: {2}" -f ($Arguments -join " "), $exitCode, ($output -join " "))
    }
    return $output
}

function Get-VMState {
    $output = Invoke-VBoxManage -Arguments @("showvminfo", $script:VmName, "--machinereadable")
    foreach ($line in $output) {
        if ([string]$line -match '^VMState="([^"]+)"') {
            return $Matches[1]
        }
    }
    throw ("Could not determine the state of VirtualBox VM '{0}'." -f $script:VmName)
}

function Write-Status {
    param(
        [string]$State,
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host ("[{0,-9}] {1}" -f $State, $Message) -ForegroundColor $Color
}

function Get-ApplicationPath {
    param([string]$Name)
    try {
        $command = Get-Command -Name $Name -CommandType Application -ErrorAction Stop
        return $command.Source
    }
    catch {
        return $null
    }
}

function Quote-ProcessArgument {
    param([string]$Value)

    # PowerShell single-quoted strings treat backslashes literally. Use actual
    # double-quote characters so Start-Process receives valid Windows arguments.
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Test-TcpPortInUse {
    param([int]$Port)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(300, $false)) {
            return $false
        }
        $client.EndConnect($pending)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Show-ProcessLogTail {
    param($ManagedProcess)
    foreach ($path in @($ManagedProcess.Stdout, $ManagedProcess.Stderr)) {
        if (Test-Path -LiteralPath $path) {
            Write-Host ("--- Last lines: {0} ---" -f $path) -ForegroundColor DarkYellow
            $logFile = Get-Item -LiteralPath $path
            if ($logFile.Length -eq 0) {
                Write-Host "(empty)"
            }
            else {
                Get-Content -LiteralPath $path -Tail 20
            }
        }
    }
}

function Start-ManagedProcess {
    param(
        [string]$Name,
        [string]$FilePath,
        [string]$Arguments
    )

    $stdout = Join-Path $LogRoot ("{0}-{1}.stdout.log" -f $Name, $RunId)
    $stderr = Join-Path $LogRoot ("{0}-{1}.stderr.log" -f $Name, $RunId)
    Write-Status "STARTING" ("{0}: {1}" -f $Name, $FilePath) Cyan
    Write-Status "COMMAND" $Arguments DarkGray
    
    # handle that luvit does not run if standardoutput and error is redirected, keep this terminal visible
    if ($Arguments -like "*web_server.lua*") {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $Root -PassThru
    } else {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $Root -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    }
    

    $entry = [pscustomobject]@{
        Name = $Name
        Process = $process
        Arguments = $Arguments
        Stdout = $stdout
        Stderr = $stderr
        Status = "STARTING"
        HealthUri = $null
        HealthKind = $null
    }

    $script:ManagedProcesses += $entry
    Write-Status "STARTED" ("{0} process ID {1}; logs: {2}" -f $Name, $process.Id, $stdout) Green
    return $entry
}

function Get-ServiceHealth {
    param($Service)
    try {
        switch ($Service.HealthKind) {
            "memory" {
                $response = Invoke-RestMethod -Uri $Service.HealthUri -TimeoutSec 2
                if ($response.status -eq "ok") { return "READY" }
                return "RESPONDING"
            }
            "inference" {
                $response = Invoke-WebRequest -Uri $Service.HealthUri -TimeoutSec 2 -UseBasicParsing
                if ([int]$response.StatusCode -eq 200) { return "READY" }
                return "RESPONDING"
            }
            "evidence" {
                $response = Invoke-RestMethod -Uri $Service.HealthUri -TimeoutSec 2
                if ($response.prepared -eq $true) { return "READY" }
                return "PREPARING"
            }
            "alice" {
                $response = Invoke-WebRequest -Uri $Service.HealthUri -TimeoutSec 2 -UseBasicParsing
                if ([int]$response.StatusCode -eq 200) { return "READY" }
                return "RESPONDING"
            }
            "virtualbox" {
                if ((Get-VMState) -eq "running") { return "READY" }
                return "FAILED"
            }
        }
    }
    catch {
        if ($Service.HealthKind -eq "evidence") { return "PREPARING" }
        if ($Service.HealthKind -eq "virtualbox") { return "FAILED" }
        return "STARTING"
    }
    return "STARTING"
}

function Get-CorpusCandidates {
    param([string]$Path)
    $candidates = @()

    $xmlFiles = @(
        Get-ChildItem -LiteralPath $Path -File -Recurse |
            Where-Object {
                $_.Name -ne "placeholder.txt" -and
                ($_.Name -match '(?i)\.xml$' -or $_.Name -match '(?i)\.xml\.bz2$')
            }
    )

    foreach ($file in $xmlFiles) {
        $candidates += [pscustomobject]@{ Path = $file.FullName; Kind = "file" }
    }

    # Directory inputs are treated as collections of text files. If a directory
    # contains XML, select the XML file instead of passing that directory.
    foreach ($directory in Get-ChildItem -LiteralPath $Path -Directory) {
        $containsXml = $false
        foreach ($xmlFile in $xmlFiles) {
            if ($xmlFile.FullName.StartsWith(
                $directory.FullName + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                $containsXml = $true
                break
            }
        }
        if ($containsXml) { continue }

        $firstDataFile = Get-ChildItem -LiteralPath $directory.FullName -File -Recurse |
            Where-Object { $_.Name -ne "placeholder.txt" } |
            Select-Object -First 1

        if ($null -ne $firstDataFile) {
            $candidates += [pscustomobject]@{ Path = $directory.FullName; Kind = "directory" }
        }
    }

    return $candidates
}

function Select-CorpusInput {
    param([object[]]$Candidates)

    if ($Candidates.Count -eq 0) {
        Write-Status "WARNING" "No XML corpus file or text-corpus subfolder was found." Yellow
        Write-Host "Place an XML/.xml.bz2 file in corpus\, or put a text collection in its own subfolder."
        $choice = Read-Host "Start Alice without local evidence for this run? (Y/N)"
        if ($choice -match '^(?i)y(es)?$') { return $null }
        throw "Startup cancelled because no corpus input was selected."
    }

    if ($Candidates.Count -eq 1) { return $Candidates[0].Path }

    Write-Host ""
    Write-Host "Multiple corpus inputs were found. Select the one to load:" -ForegroundColor Cyan
    for ($index = 0; $index -lt $Candidates.Count; $index++) {
        Write-Host ("  {0}. [{1}] {2}" -f ($index + 1), $Candidates[$index].Kind, $Candidates[$index].Path)
    }

    while ($true) {
        $answer = Read-Host "Corpus number"
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Candidates.Count) {
            return $Candidates[$number - 1].Path
        }
        Write-Host "Enter one of the listed numbers." -ForegroundColor Yellow
    }
}

function Get-CorpusName {
    param([string]$InputPath)
    $name = Split-Path -Leaf $InputPath

    if (Test-Path -LiteralPath $InputPath -PathType Leaf) {
        $name = $name -replace '(?i)\.xml\.bz2$', ''
        $name = $name -replace '(?i)\.xml$', ''
    }

    if ($name -match '(?i)wiki') { return "wikipedia" }

    $name = $name.ToLowerInvariant() -replace '[^a-z0-9_-]', '_'
    $name = $name.Trim('_')
    if ([string]::IsNullOrWhiteSpace($name)) { return "local_corpus" }
    return $name
}

function Stop-ManagedProcesses {
    if ($script:ManagedProcesses.Count -gt 0) {
        Write-Host ""
        Write-Status "STOPPING" "Stopping processes started by this controller..." Yellow
    }

    foreach ($name in @("Alice", "Inference", "Memory", "Evidence")) {
        foreach ($entry in $script:ManagedProcesses | Where-Object { $_.Name -eq $name }) {
            try {
                $entry.Process.Refresh()
                if (-not $entry.Process.HasExited) {
                    Stop-Process -Id $entry.Process.Id -Force -ErrorAction Stop
                    Write-Status "STOPPED" ("{0} process ID {1}" -f $entry.Name, $entry.Process.Id) Gray
                }
            }
            catch {
                Write-Status "WARNING" ("Could not stop {0} process ID {1}: {2}" -f $entry.Name, $entry.Process.Id, $_.Exception.Message) Yellow
            }
        }
    }

    if ($script:VmEnabled -and $script:VmStartedByController -and $script:VmShutdownOnExit) {
        try {
            $state = Get-VMState
            if ($state -eq "running") {
                Write-Status "STOPPING" ("Requesting graceful shutdown of VM '{0}'..." -f $script:VmName) Yellow
                Invoke-VBoxManage -Arguments @("controlvm", $script:VmName, "acpipowerbutton") | Out-Null
                $deadline = (Get-Date).AddSeconds(30)
                do {
                    Start-Sleep -Seconds 2
                    $state = Get-VMState
                    if ($state -eq "poweroff") { break }
                } while ((Get-Date) -lt $deadline)

                if ($state -eq "poweroff") {
                    Write-Status "STOPPED" ("VM '{0}' shut down gracefully." -f $script:VmName) Gray
                }
                else {
                    Write-Status "WARNING" ("VM '{0}' is still in state '{1}'. It was left running rather than being forcibly powered off." -f $script:VmName, $state) Yellow
                }
            }
        }
        catch {
            Write-Status "WARNING" ("Could not shut down VM '{0}': {1}" -f $script:VmName, $_.Exception.Message) Yellow
        }
    }
}

try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " A L I C E  -  Wonderland Runtime" -ForegroundColor Cyan
    Write-Host " Windows startup controller" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ("Root: {0}" -f $Root)
    Write-Host ""

    foreach ($directory in @($ModelRoot, $CorpusRoot, $BinRoot)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Required directory not found: $directory"
        }
    }

    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

    $vmConfigPath = Join-Path $PSScriptRoot "vm-config.psd1"
    if (Test-Path -LiteralPath $vmConfigPath -PathType Leaf) {
        $script:VmConfig = Import-PowerShellDataFile -LiteralPath $vmConfigPath
        Write-Status "OK" ("Loaded local VM configuration: {0}" -f $vmConfigPath) Green
    }

    $script:VmEnabled = ConvertTo-VMBoolean (Get-VMSetting "ALICE_VM_ENABLED" $false) "ALICE_VM_ENABLED"
    $script:VmName = [string](Get-VMSetting "ALICE_VM_NAME" "AliceDebian")
    $script:VmGuestUser = [string](Get-VMSetting "ALICE_VM_GUEST_USER" "alice-exec")
    $script:VmGuestPasswordFile = [string](Get-VMSetting "ALICE_VM_GUEST_PASSWORD_FILE" "")
    $script:VmVBoxManagePath = [string](Get-VMSetting "ALICE_VM_VBOXMANAGE_PATH" "")
    $script:VmStartOnLaunch = ConvertTo-VMBoolean (Get-VMSetting "ALICE_VM_START_ON_LAUNCH" $true) "ALICE_VM_START_ON_LAUNCH"
    $script:VmShutdownOnExit = ConvertTo-VMBoolean (Get-VMSetting "ALICE_VM_SHUTDOWN_ON_EXIT" $true) "ALICE_VM_SHUTDOWN_ON_EXIT"
    $vmTimeout = ConvertTo-VMInteger (Get-VMSetting "ALICE_VM_TIMEOUT_SECONDS" 30) "ALICE_VM_TIMEOUT_SECONDS" 1 600
    $vmMaxTimeout = ConvertTo-VMInteger (Get-VMSetting "ALICE_VM_MAX_TIMEOUT_SECONDS" 120) "ALICE_VM_MAX_TIMEOUT_SECONDS" 1 600
    $vmMaxOutput = ConvertTo-VMInteger (Get-VMSetting "ALICE_VM_MAX_OUTPUT_BYTES" 32768) "ALICE_VM_MAX_OUTPUT_BYTES" 1024 262144
    if ($vmTimeout -gt $vmMaxTimeout) {
        throw "ALICE_VM_TIMEOUT_SECONDS cannot exceed ALICE_VM_MAX_TIMEOUT_SECONDS."
    }

    $env:ALICE_VM_ENABLED = if ($script:VmEnabled) { "true" } else { "false" }
    $env:ALICE_VM_NAME = $script:VmName
    $env:ALICE_VM_GUEST_USER = $script:VmGuestUser
    $env:ALICE_VM_GUEST_PASSWORD_FILE = $script:VmGuestPasswordFile
    $env:ALICE_VM_TIMEOUT_SECONDS = [string]$vmTimeout
    $env:ALICE_VM_MAX_TIMEOUT_SECONDS = [string]$vmMaxTimeout
    $env:ALICE_VM_MAX_OUTPUT_BYTES = [string]$vmMaxOutput

    if ($script:VmEnabled) {
        if ([string]::IsNullOrWhiteSpace($script:VmVBoxManagePath)) {
            $script:VmVBoxManagePath = Get-ApplicationPath "VBoxManage.exe"
            if (-not $script:VmVBoxManagePath) { $script:VmVBoxManagePath = Get-ApplicationPath "VBoxManage" }
        }
        if (-not $script:VmVBoxManagePath) {
            throw "VM execution is enabled, but VBoxManage was not found. Set ALICE_VM_VBOXMANAGE_PATH."
        }
        if ([string]::IsNullOrWhiteSpace($script:VmName)) {
            throw "ALICE_VM_NAME must name the configured VirtualBox VM."
        }
        if ([string]::IsNullOrWhiteSpace($script:VmGuestUser)) {
            throw "ALICE_VM_GUEST_USER must name the unprivileged guest account."
        }
        if ([string]::IsNullOrWhiteSpace($script:VmGuestPasswordFile) -or
            -not (Test-Path -LiteralPath $script:VmGuestPasswordFile -PathType Leaf)) {
            throw "ALICE_VM_GUEST_PASSWORD_FILE must point to a host-side file containing the guest account password."
        }
        $env:ALICE_VM_VBOXMANAGE_PATH = $script:VmVBoxManagePath
        Write-Status "OK" ("VM execution configured: {0} as {1}" -f $script:VmName, $script:VmGuestUser) Green
    }
    else {
        $env:ALICE_VM_VBOXMANAGE_PATH = $script:VmVBoxManagePath
        Write-Status "SKIPPED" "VM execution is disabled; Alice's other tools are unaffected." Gray
    }

    # Deliberately simple PATH checks for Lua and Luvit.
    $luaPath = Get-ApplicationPath "lua"
    if (-not $luaPath) { throw "Lua was not found in PATH. Make the 'lua' command available." }
    $luvitPath = Get-ApplicationPath "luvit"
    if (-not $luvitPath) { throw "Luvit was not found in PATH. Make the 'luvit' command available." }
    Write-Status "OK" ("Lua: {0}" -f $luaPath) Green
    Write-Status "OK" ("Luvit: {0}" -f $luvitPath) Green

    # Prefer a project virtual environment, otherwise use Python from PATH.
    $venvPython = Join-Path $Root ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython -PathType Leaf) {
        $pythonPath = $venvPython
    }
    else {
        $pythonPath = Get-ApplicationPath "python"
    }
    if (-not $pythonPath) { throw "Python was not found. Install Python or create the repository .venv first." }

    $pythonCheck = & $pythonPath -c "import chromadb" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("The selected Python cannot import chromadb. Install Alice's memory dependencies in that interpreter. Details: {0}" -f ($pythonCheck -join " "))
    }
    Write-Status "OK" ("Python and chromadb: {0}" -f $pythonPath) Green

    $llamaPath = Join-Path $BinRoot "llama-server.exe"
    if (-not (Test-Path -LiteralPath $llamaPath -PathType Leaf)) { $llamaPath = Get-ApplicationPath "llama-server.exe" }
    if (-not $llamaPath) { $llamaPath = Get-ApplicationPath "llama-server" }
    if (-not $llamaPath) {
        throw "llama-server.exe was not found in bin\ or PATH. Install llama.cpp or place its server executable in bin\."
    }

    $models = @(Get-ChildItem -LiteralPath $ModelRoot -File -Filter "*.gguf")
    if ($models.Count -eq 0) { throw "No GGUF model file was found in $ModelRoot. Place one .gguf model there." }
    if ($models.Count -gt 1) {
        $modelNames = ($models | ForEach-Object { $_.Name }) -join ", "
        throw ("Multiple GGUF models were found in model\: {0}. Leave one model in the folder for this startup workflow." -f $modelNames)
    }
    $modelPath = $models[0].FullName
    Write-Status "OK" ("Model: {0}" -f $modelPath) Green
    Write-Status "OK" ("Inference server: {0}" -f $llamaPath) Green

    $corpusCandidates = @(Get-CorpusCandidates -Path $CorpusRoot)
    $corpusInput = Select-CorpusInput -Candidates $corpusCandidates
    $skipEvidence = ($null -eq $corpusInput)
    $corpusName = $null

    if (-not $skipEvidence) {
        $corpusName = Get-CorpusName -InputPath $corpusInput
        Write-Status "OK" ("Corpus input: {0}" -f $corpusInput) Green
        Write-Status "OK" ("Corpus identifier for Alice's evidence tools: {0}" -f $corpusName) Green
    }
    else {
        Write-Status "WARNING" "Local evidence will be unavailable for this run." Yellow
    }

    # Prevent an already-running service from making our health check a false positive.
    foreach ($port in @(
        [pscustomobject]@{ Name = "Memory"; Port = $MemoryPort },
        [pscustomobject]@{ Name = "Evidence"; Port = $EvidencePort },
        [pscustomobject]@{ Name = "Inference"; Port = $InferencePort },
        [pscustomobject]@{ Name = "Alice"; Port = $AlicePort }
    )) {
        if (Test-TcpPortInUse -Port $port.Port) {
            throw ("Port {0} for {1} is already in use. Stop the existing service or change the controller configuration." -f $port.Port, $port.Name)
        }
    }

    Write-Status "OK" "Prerequisite and port checks completed." Green

    $vmService = $null
    if ($script:VmEnabled) {
        $vmState = Get-VMState
        if ($vmState -ne "running") {
            if (-not $script:VmStartOnLaunch) {
                throw ("VM '{0}' is not running (state: {1}) and ALICE_VM_START_ON_LAUNCH is false." -f $script:VmName, $vmState)
            }

            Write-Status "STARTING" ("Starting VirtualBox VM '{0}' headlessly..." -f $script:VmName) Cyan
            Invoke-VBoxManage -Arguments @("startvm", $script:VmName, "--type", "headless") | Out-Null
            $script:VmStartedByController = $true

            $deadline = (Get-Date).AddSeconds(90)
            do {
                Start-Sleep -Seconds 2
                $vmState = Get-VMState
                if ($vmState -eq "running") { break }
            } while ((Get-Date) -lt $deadline)

            if ($vmState -ne "running") {
                throw ("VirtualBox VM '{0}' did not reach running state within 90 seconds (state: {1})." -f $script:VmName, $vmState)
            }
        }
        else {
            Write-Status "OK" ("VirtualBox VM '{0}' is already running; controller will not shut it down on exit." -f $script:VmName) Green
        }

        $vmService = [pscustomobject]@{
            Name = "VM"
            Process = $null
            Arguments = "VBoxManage showvminfo $($script:VmName) --machinereadable"
            Stdout = $null
            Stderr = $null
            Status = "STARTING"
            HealthUri = $null
            HealthKind = "virtualbox"
        }
        Write-Status "OK" ("VirtualBox VM '{0}' is running." -f $script:VmName) Green
    }

    Write-Host ""

    # --prep runs before the Rust API binds its port. Never wait for it here.
    if (-not $skipEvidence) {
        $rustPath = Join-Path $BinRoot "dataset-stream-parser-api.exe"
        if (-not (Test-Path -LiteralPath $rustPath -PathType Leaf)) {
            throw "Bundled Rust Data Engine executable not found: $rustPath"
        }

        $rustArguments = (Quote-ProcessArgument $corpusInput) + " " +
            (Quote-ProcessArgument $corpusName) + " " +
            (Quote-ProcessArgument $CorpusRecordElement) + " " +
            (Quote-ProcessArgument ("{0}:{1}" -f $EvidenceHost, $EvidencePort)) +
            " --prep"

        $evidenceService = Start-ManagedProcess -Name "Evidence" -FilePath $rustPath -Arguments $rustArguments
        $evidenceService.HealthKind = "evidence"
        $evidenceService.HealthUri = "http://$($EvidenceHost):$($EvidencePort)/local_data/status?corpus=$([Uri]::EscapeDataString($corpusName))"
        Write-Status "WAIT" "Evidence preparation runs in the background; startup will continue." Yellow
        Write-Host ("Evidence logs: {0}" -f $evidenceService.Stdout)
    }
    else {
        Write-Status "SKIPPED" "Rust Data Engine (no corpus selected)." Gray
    }

    $memoryScript = Join-Path $Root "memory_service.py"
    if (-not (Test-Path -LiteralPath $memoryScript -PathType Leaf)) {
        throw "Memory service entry point not found: $memoryScript"
    }

    $memoryArguments = "-u " + (Quote-ProcessArgument $memoryScript)
    $memoryService = Start-ManagedProcess -Name "Memory" -FilePath $pythonPath -Arguments $memoryArguments
    $memoryService.HealthKind = "memory"
    $memoryService.HealthUri = "http://$($MemoryHost):$($MemoryPort)/memory/status"

    $llamaArguments = "-m " + (Quote-ProcessArgument $modelPath) + " -c $InferenceContextSize --host $InferenceHost --port $InferencePort"
    $inferenceService = Start-ManagedProcess -Name "Inference" -FilePath $llamaPath -Arguments $llamaArguments
    $inferenceService.HealthKind = "inference"
    $inferenceService.HealthUri = "http://$($InferenceHost):$($InferencePort)/health"

    $webScript = Join-Path $Root "web_server.lua"
    if (-not (Test-Path -LiteralPath $webScript -PathType Leaf)) {
        throw "Alice web server entry point not found: $webScript"
    }

    $aliceArguments = Quote-ProcessArgument $webScript
    $aliceService = Start-ManagedProcess -Name "Alice" -FilePath $luvitPath -Arguments $aliceArguments
    $aliceService.HealthKind = "alice"
    $aliceService.HealthUri = "http://$($AliceHost):$($AlicePort)/"

    $script:Services = @($memoryService, $inferenceService, $aliceService)
    if (-not $skipEvidence) { $script:Services += $evidenceService }
    if ($null -ne $vmService) { $script:Services += $vmService }

    Write-Host ""
    Write-Host "Services launched; readiness is monitored independently." -ForegroundColor Cyan
    Write-Host ("Web interface: http://{0}:{1}/" -f $AliceHost, $AlicePort)
    Write-Host ("Logs: {0}" -f $LogRoot)
    if (-not $skipEvidence) { Write-Host "Evidence readiness will be reported when corpus preparation finishes." }
    Write-Host "Press Ctrl+C in this console to stop processes started by this controller."
    Write-Host ""

    while ($true) {
        foreach ($service in $script:Services) {
            if ($service.HealthKind -ne "virtualbox") {
                $service.Process.Refresh()
            }

            if ($service.HealthKind -ne "virtualbox" -and $service.Process.HasExited) {
                if ($service.Status -ne "FAILED") {
                    $service.Status = "FAILED"
                    $exitCode = "unknown"
                    try {
                        $reportedExitCode = $service.Process.ExitCode
                        if ($null -ne $reportedExitCode) {
                            $exitCode = $reportedExitCode
                        }
                    }
                    catch {
                        # Keep the failure report useful if the exit code is unavailable.
                    }

                    Write-Status "FAILED" ("{0} exited with code {1}." -f $service.Name, $exitCode) Red
                    Write-Host ("Executable: {0}" -f $service.Process.StartInfo.FileName) -ForegroundColor Yellow
                    Write-Host ("Arguments: {0}" -f $service.Arguments) -ForegroundColor Yellow
                    Write-Host ("Working directory: {0}" -f $Root) -ForegroundColor Yellow
                    Write-Host ("Logs: {0} | {1}" -f $service.Stdout, $service.Stderr) -ForegroundColor Yellow
                    Show-ProcessLogTail -ManagedProcess $service
                }
                continue
            }

            $newStatus = Get-ServiceHealth -Service $service
            if ($newStatus -ne $service.Status) {
                $service.Status = $newStatus
                switch ($newStatus) {
                    "READY" { Write-Status "READY" ("{0} is responding." -f $service.Name) Green }
                    "PREPARING" {
                        if ($service.Name -eq "Evidence") {
                            Write-Status "WAIT" "Evidence API is not listening yet; corpus preparation may still be running." Yellow
                        }
                    }
                    "RESPONDING" { Write-Status "WAIT" ("{0} is responding but has not reported ready." -f $service.Name) Yellow }
                    "FAILED" { Write-Status "FAILED" ("{0} is no longer available." -f $service.Name) Red }
                }
            }
        }

        $coreServices = @($script:Services | Where-Object { $_.Name -in @("Memory", "Inference", "Alice") })
        $coreReady = ($coreServices.Count -eq 3) -and (@($coreServices | Where-Object { $_.Status -ne "READY" }).Count -eq 0)

        if ($coreReady -and -not $script:RuntimeReadyAnnounced) {
            $script:RuntimeReadyAnnounced = $true
            Write-Host ""
            Write-Status "READY" "Wonderland runtime operational." Green
            if (-not $skipEvidence -and $evidenceService.Status -ne "READY") {
                Write-Status "WAIT" "Local evidence is still preparing; the rest of Alice is available." Yellow
            }
            elseif ($skipEvidence) {
                Write-Status "INFO" "Local evidence was skipped for this run." Gray
            }
        }

        if (-not $skipEvidence -and $evidenceService.Status -eq "READY" -and -not $script:EvidenceReadyAnnounced) {
            $script:EvidenceReadyAnnounced = $true
            Write-Status "READY" ("Evidence API is ready for corpus '{0}'." -f $corpusName) Green
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
catch {
    Write-Host ""
    Write-Status "FATAL" $_.Exception.Message Red
}
finally {
    Stop-ManagedProcesses
    Write-Host ""
    Write-Host "Alice runtime controller stopped." -ForegroundColor Cyan
}
