<# 
.SYNOPSIS 
   Tracks your most used directories, based on 'frecency'.

.DESCRIPTION 
    After  a  short  learning  phase, z will take you to the most 'frecent'
    directory that matches ALL of the regexes given on the command line.
.NOTES 
	Current PowerShell implementation is very crude and does not yet support all of the options of the original z bash script.
    
	cd around for a while to build up the db.
	
.LINK 
   https://github.com/vincpa/z
   
.EXAMPLE 
    cd foodir1
	cd ..\foodir2
	cd some\really\long\path
	
	z foodir - Takes you to the most frecent directory.
#>

# A wrapper function around the existing Set-Location Cmdlet.
function cdX
{
	[CmdletBinding(DefaultParameterSetName='Path', SupportsTransactions=$true, HelpUri='http://go.microsoft.com/fwlink/?LinkID=113397')]
	param(
	    [Parameter(ParameterSetName='Path', Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
	    [string]
	    ${Path},

	    [Parameter(ParameterSetName='LiteralPath', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
	    [Alias('PSPath')]
	    [string]
	    ${LiteralPath},

	    [switch]
	    ${PassThru},

	    [Parameter(ParameterSetName='Stack', ValueFromPipelineByPropertyName=$true)]
	    [string]
	    ${StackName})

	begin
	{
	    try {
	        $outBuffer = $null
	        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
	        {
	            $PSBoundParameters['OutBuffer'] = 1
	        }
			
			$PSBoundParameters['ErrorAction'] = 'Stop'
			
	        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Set-Location', [System.Management.Automation.CommandTypes]::Cmdlet)
	        $scriptCmd = {& $wrappedCmd @PSBoundParameters }
					
	        $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
	        $steppablePipeline.Begin($PSCmdlet)					
	    } catch {
			throw
	    }
	}

	process
	{
	    try {
	        $steppablePipeline.Process($_)
			
			_z # Build up the DB.
			
	    } catch [System.Management.Automation.ActionPreferenceStopException] {
	        throw
	    }
	}

	end
	{
	    try {
	        $steppablePipeline.End()		
	    } catch {
	        throw
	    }
	}
}

function z {
	param(
	[Parameter(Mandatory=$true)]
	[Alias('PSPath')]
	[string]
	$jumppath)

	[string] $file = "$HOME\.cdhistory"

	if ((Test-Path $file)) {

		$cdHistory = [System.IO.File]::ReadAllLines($file)

		$list = @()

		$cdHistory | _zGetDirectoryEntry | 
			? { 
				[System.Text.RegularExpressions.Regex]::Match($_.Path.Name, $jumppath).Success
			} |
			% {
				$_.Score = frecent $_.Rank $_.Time
				$list += $_
			}

		if ($list.Length -gt 1) {
			
			$list | Sort-Object -Descending { $_.Score } | select -First 1 | % { Set-Location $_.Path.FullName }

		} elseif ($list.Length -eq 0) {
			Write-Host "$jumppath Not found"
		} else {
			Set-Location $list[0].Path
		}
	}
}

function frecent($rank, $time) {

	# Last access date/time
	$dx = (Get-Date).Subtract((New-Object System.DateTime -ArgumentList $time)).TotalSeconds

	if( $dx -lt 3600 ) { return $rank*4 }
    
	if( $dx -lt 86400 ) { return $rank*2 }
    
	if( $dx -lt 604800 ) { return $rank/2 }
	
    return $rank/4
}
			
function _z() {

	$currentDirectory = Get-Location | select -ExpandProperty path
		
	[string] $file = "$HOME\.cdhistory"
	
	$cdHistory = ''
	
	if ((Test-Path $file)) {
		$cdHistory = [System.IO.File]::ReadAllLines($file);
		Remove-Item $file
	}
	
	$foundDirectory = false
	$runningTotal = 0
	
	foreach ($line in $cdHistory) {
				
		if ($line -ne '') {
			$lineObj = _zGetDirectoryEntryObj $line
			if ($lineObj.Path.FullName -eq $currentDirectory) {	
				$lineObj.Rank++
				$foundDirectory = $true
				_zWriteLine $file $lineObj.Rank $currentDirectory
			} else {
				[System.IO.File]::AppendAllText($file, $line + [Environment]::NewLine)
			}
			$runningTotal += $lineObj.Rank
		}
	}
	
	if (-not $foundDirectory) {
		_zWriteLine $file 1 $currentDirectory
		$runningTotal += 1
	}
	
	if ($runningTotal -gt 6) {
		
		$lines = [System.IO.File]::ReadAllLines($file)
		Remove-Item $file
		 $lines | % {
		 	$lineObj = _zGetDirectoryEntryObj $_
			$lineObj.Rank = $lineObj.Rank * 0.99
			
			if ($lineObj.Rank -ge 1 -or $lineObj.Age -lt 86400) {
				_zWriteLine $file $lineObj.Rank $lineObj.Path
			}
		}
	}
}

function _zFormatRank($aging) {
	return $aging.ToString("000#.00");
}

function _zWriteLine($file, $aging, $directory) {
	$newline = [Environment]::NewLine
	[System.IO.File]::AppendAllText($file, (_zFormatRank $aging) + (Get-Date).Ticks + $directory + $newline)	
}

function _zGetDirectoryEntry {
	Param(
		[Parameter(
        Position=0, 
        Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
    	[String]$item
	)
	
	Process {
		_zGetDirectoryEntryObj $item		
	}
}

function _zGetDirectoryEntryObj($line) {
	$matches = [System.Text.RegularExpressions.Regex]::Match($line, '(\d+\.\d{2})(\d+)(.*)');
	
	$dir = (New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $matches.Groups[3].Value);
	
	$obj = @{
	  Rank=[decimal]::Parse($matches.Groups[1].Value);
	  Time=[long]::Parse($matches.Groups[2].Value);
	  Path=$dir;
	  Score=0;
	};
	
	return $obj;
}

<#

.ForwardHelpTargetName Set-Location
.ForwardHelpCategory Cmdlet

#>

#Override the existing CD command with the wrapper in order to log 'cd' commands.
Set-Alias -Name cd -Value cdX -Force -Option AllScope

