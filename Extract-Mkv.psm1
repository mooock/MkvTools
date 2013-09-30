﻿<#
.SYNOPSIS
Extract-Mkv batch extracts tracks, attachments, chapters and timecodes from Matroska files using the mkvtoolnix command line tools.

.DESCRIPTION

Extract-Mkv accepts a comma-delimited list of input files and/or folders (recursing supported) 
and by default extracts all tracks from each input file using a configurable naming pattern.
It also allows you to specify which track types or track IDs to extract and lets you choose 
a custom output directory if you don't want it to extract into the parent directory of the input files.

Extract-Mkv can extract tracks, attachments, chapters and timecodes in one go, will indicate progress 
using status bars where possible and returns track/attachment tables that highlight what is being extracted. 

The Module acts as a wrapper for the mkvtoolnix command line tools and therefore requires 
your PATH environment variable to point to mkvextract.exe and mkvinfo.exe

.EXAMPLE

Extract-Mkv X:\Videos, Y:\Test.mkv

Extracts all tracks from Y:\Test.mkv aswell as all .mkv/.mka/.mks files found in X:\Videos into the parent folders
of the respective input files using the default naming pattern (e.g. Y:\Test_1.h264)

.EXAMPLE

Extract-Mkv X:\Videos -r -t subtitles,1 -a fonts -c xml -o X:\Videos\Extracted

Extracts from Matroska files found in X:\Videos and subdirectories: 
    all subtitle tracks
    all tracks with Track ID 1
    all attached fonts
    xml chapters for each file
into X:\Videos\Extracted using the default naming pattern 
    
.EXAMPLE
Extract-Mkv X:\Videos -ReturnMkvInfo | Tee-Object -Variable mkvInfo | Format-MkvInfoTable
Simultaneously outputs Get-MkvInfo objects info $mkvInfo for further processing 
and track/attachment tables to the console

.LINK
https://github.com/line0/MkvTools

#>
#requires -version 3

function Extract-Mkv
{
[CmdletBinding()]
param
(
[Parameter(Position=0, Mandatory=$true, HelpMessage='Comma-delimited list of files and/or Directories to process (can take mixed).')]
[alias("i")]
[string[]]$Inputs,
[Parameter(Mandatory=$false, HelpMessage=@'
Comma-delimited list of tracks to extract.
    Track types: none, all, video, audio, subtitles
    Track IDs: 0, 1, 2, 3...
Defaults to: all
'@)]
[alias("t")]
[string[]]$Tracks = @("all"),
[Parameter(Mandatory=$false, HelpMessage=@'
Comma-delimited list of attachments to extract.
    Attachment types: none (Default), all, fonts
'@)]
[alias("a")]
[string[]]$Attachments = @(),
[Parameter(Mandatory=$false, HelpMessage=@'
Comma-delimited list of chapter types to extract.
    Output modes: none, xml, simple
Defaults to: none
'@)]
[alias("c")]
[string[]]$Chapters = @(),
[Parameter(Mandatory=$false, HelpMessage=@'
Comma-delimited list of tracks to extract v2 timecodes from.
    Track types: none, all, video, audio, subtitles
    Track IDs: 0, 1, 2, 3...
'@)]
[alias("tc")]
[string[]]$Timecodes,
[Parameter(Mandatory=$false, HelpMessage=@'
Filename pattern for extracted tracks, not including file extension. File names are relative to the output directory, which defaults to the parent directories of the input files.
Available variables:
    $f : Input filename, without path and extension
    $i : Track ID
    $t : Track Type (audio, video, subtitles)
    $n : Track Name (if present)
    $l : Track Language (if present)
Defaults to: $f_$i
'@)]
[alias("tp")]
[string]$TrackPattern = '$f_$i',
[Parameter(Mandatory=$false, HelpMessage=@'
Filename pattern for extracted attachments, not including file extension. File names are relative to the output directory, which defaults to the parent directories of the input files.
Available variables:
    $f : Input filename, without path and extension
    $i : Attachment UID
    $n : Attachment filename (as stored in the matroska file) without path and extension
Defaults to: $f_Attachments\$n
'@)]
[alias("ap")]
[string]$AttachmentPattern = '$f_Attachments\$n',
[Parameter(Mandatory=$false, HelpMessage=@'
Filename pattern for extracted chapters, not including file extension. File names are relative to the output directory, which defaults to the parent directories of the input files.
Available variables:
    $f : Input filename, without path and extension
    $n : File Title (if present)
Defaults to: $f_Chapters
'@)]
[alias("cp")]
[string]$ChapterPattern = '$f_Chapters',
[Parameter(Mandatory=$false, HelpMessage=@'
Filename pattern for extracted timecodes, not including file extension. File names are relative to the output directory, which defaults to the parent directories of the input files.
Available variables:
    $f : Input filename, without path and extension
    $i : Track ID
    $t : Track Type (audio, video, subtitles)
    $n : Track Name (if present)
    $l : Track Language (if present)
    $v : Timecode Type (currently only v2 available)
Defaults to: $f_$i_Timecodes_$v
'@)]
[alias("tcp")]
[string]$TimecodePattern = '$f_$i_Timecodes_$v',
[Parameter(Mandatory=$false, HelpMessage=@'
Output directory for extracted track, attachments, chapters and timecodes.
Defaults to the parent directories of the input files.
'@)]
[alias("o")]
[string]$OutDir,
[Parameter(Mandatory=$false, HelpMessage=@"
Verbosity level of console output:
    0: Display general extraction status, but don't return track and attachment tables
    1: Also display (and return) tables
    2: Display additional mkvextract output
    3: Pass --verbose to mkvextract (generates lots of output)
Default: 1
"@)]
[alias("v")]
[int]$Verbosity=1,
[Parameter(Mandatory=$false, HelpMessage='Parse the whole file instead of relying on the index (pass to mkvextract).')]
[alias("f")]
[switch]$ParseFully = $false,
[Parameter(Mandatory=$false, HelpMessage="Suppress all console output and don't return anything.")]
[alias("q")]
[switch]$Quiet = $false,
[Parameter(Mandatory=$false, HelpMessage='Recurse subdirectories.')]
[alias("r")]
[switch]$Recurse = $false,
[Parameter(Mandatory=$false, HelpMessage='Also try to extract the CUE sheet from the chapter information and tags for tracks (pass to mkvextract).')]
[switch]$Cuesheet = $false,
[Parameter(Mandatory=$false, HelpMessage='Extract track data to a raw file (pass to mkvextract).')]
[switch]$Raw = $false,
[Parameter(Mandatory=$false, HelpMessage='Extract track data to a raw file including the CodecPrivate as a header (pass to mkvextract).')]
[switch]$FullRaw = $false,
[Parameter(Mandatory=$false, HelpMessage=@'
Return objects generated by Get-MkvInfo instead of table objects. Use this if you need additional information about the source files as well as extracted assets for further processing.
Extract-Mkv adds the following properties to the Get-MkvInfo objects:
    [Tracks] _ExtractStateTrack: Extraction state of the track:
                                 0 or not present: track is not marked for extraction
                                 1: track is marked for extraction
                                 2: track has been successfully extracted
                                -1: track extraction failed
             _ExtractPathTrack: Full path to the extracted track
             _ExtractStateTimecodes: Extraction state of the track timecodes
             _ExtractPathTimecodes Full path to the extracted timecodes
    
    [Attachments] _ExtractState: Extraction state of the attachment
                  _ExtractPath: Full path to the extracted attachment

'@)]
[switch]$ReturnMkvInfo = $false
)

    if ($Quiet) { $Verbosity=-1 }
    elseif($Verbosity -eq 3) { $VerbosePreference = "Continue" }

    Check-CmdInPath mkvinfo.exe -Name mkvtoolnix
    Check-CmdInPath mkvextract.exe -Name mkvtoolnix
   
    try { $mkvs = Get-Files $inputs -match '.mk[v|a|s]$' -matchDesc Matroska -acceptFolders -recurse:$Recurse }
    catch
    {
        if($_.Exception.WasThrownFromThrowStatement -eq $true)
        {
            Write-Host $_.Exception.Message -ForegroundColor Red
            break
        }
        else {throw $_.Exception}
    }

    [PSObject[]]$extractData = @()
    
    $doneCnt = 0
    $activityMsg = "Extracting from $($mkvs.Count) files..."
    Write-Progress -Activity $activityMsg -Id 0 -PercentComplete 0 -Status "File 1/$($mkvs.Count)"

    foreach($mkv in $mkvs)
    {
        $mkvInfo = Get-MkvInfo -file $mkv.FullName
        
        if ($Tracks -contains "all")
        {
            $mkvInfo.tracks | ?{$_} | Add-Member -NotePropertyName _ExtractStateTrack -NotePropertyValue 1 -Force
            # There might be a file without tracks, who knows
        }
        else
        {
            $Tracks | ?{($_ -match '[0-9]+')} | %{$mkvInfo.GetTracksByID($_)} | Add-Member -NotePropertyName _ExtractStateTrack -NotePropertyValue 1 -Force
            $Tracks | ?{($_ -match 'subtitles|audio|video')} | %{$mkvInfo.GetTracksByType($_)} | Add-Member -NotePropertyName _ExtractStateTrack -NotePropertyValue 1 -Force

        }

        if ($Timecodes -contains "all")
        { $mkvInfo.tracks| ?{$_} | Add-Member -NotePropertyName _ExtractStateTimecodes -NotePropertyValue 1 -Force }
        else
        {
            $Timecodes | ?{($_ -match '[0-9]+')} | %{$mkvInfo.GetTracksByID($_) | Add-Member -NotePropertyName _ExtractStateTimecodes -NotePropertyValue 1 -Force }
            $Timecodes | ?{($_ -match 'subtitles|audio|video')} | %{$mkvInfo.GetTracksByType($_) | Add-Member -NotePropertyName _ExtractStateTimecodes -NotePropertyValue 1 -Force }
        }


        if ($Attachments -contains "all")
        { 
            $mkvInfo.Attachments | ?{$_} | Add-Member -NotePropertyName _ExtractState -NotePropertyValue 1 -Force
        }
        else
        {             $Attachments | ?{($_ -eq "fonts")} | %{$mkvInfo.GetAttachmentsByExtension("ttf|ttc|otf|fon")`                         | Add-Member -NotePropertyName _ExtractState -NotePropertyValue 1 -Force }
        }
 
        Write-HostEx "$($mkv.Name)" -ForegroundColor White -NoNewline:($Verbosity -ge 1) -If ($Verbosity -ge 0)

        if($mkvInfo.Title) 
        { 
            Write-HostEx " (Title: $($mkvInfo.Title))" -ForegroundColor Gray -If ($Verbosity -ge 1)
        }
        else { Write-HostEx "`n`n" -If ($Verbosity -ge 1)}

        Write-Verbose "(Tracks marked yellow will be extracted)`n"
        
        if ($ReturnMkvInfo) { $mkvInfo } # stream MkvInfo objects
        elseif($Verbosity -ge 1)
        {
            $mkvInfo | Format-MkvInfoTable
        }
     
        
        $cmnFlags = @{ "vb" = $Verbosity
                       "verbose" = ($Verbosity -ge 3)
                       "parse-fully" = $ParseFully
                     }
        $trackFlags = $cmnFlags + @{ "cuesheet" = $Cuesheet
                                     "raw"      = $Raw
                                     "fullraw"  = $FullRaw 
                                   }

        $mkvInfo = ExtractTracks -MkvInfo $mkvInfo -Pattern $trackPattern -OutDir $OutDir -flags $trackFlags
        $mkvInfo = ExtractAttachments -MkvInfo $mkvInfo -pattern $attachmentPattern -OutDir $OutDir -flags $cmnFlags
        $mkvInfo = ExtractChapters -MkvInfo $mkvInfo -Pattern $ChapterPattern -OutDir $OutDir -vb $Verbosity -types $Chapters
        $mkvInfo = ExtractTimecodes -MkvInfo $mkvInfo -Pattern $TimecodePattern -OutDir $OutDir -vb $Verbosity


        $doneCnt++
        Write-Progress -Activity $activityMsg -Id 0 -PercentComplete (100*$doneCnt/$mkvs.Count) -Status "File $($doneCnt+1)/$($mkvs.Count)"
    }
     Write-Progress -Activity $activityMsg -Id 0 -Completed
}

function ExtractTracks([PSCustomObject]$mkvInfo, [string]$pattern, [string]$outDir, [hashtable]$flags)
{
    if (!$outdir) {$outdir = $mkvInfo.Path | Split-Path -Parent }
    $mkvInfo.Tracks | ?{$_._ExtractStateTrack -eq 1 -and $_.CodecExt} | %{$extArgs=@(); $extCnt=0} {
        $patternVars = @{
        '$f' = [System.IO.Path]::GetFileNameWithoutExtension($mkvInfo.Path)
        '$i' = [string]$_.ID
        '$t' = [string]$_.Type
        '$n' = [string]$_.Name
        '$l' = [string]$_.Language
        } 

        $patternVars.GetEnumerator() | ForEach-Object {$outFile=$pattern} { 
            $outFile = $outFile -replace [regex]::escape($_.Key), $_.Value
        }

        $outFile = "$(Join-Path $outDir $outFile).$($_.CodecExt)"
        $mkvInfo.GetTracksByID($_.ID) | Add-Member -NotePropertyName _ExtractPath -NotePropertyValue $outFile -Force

        $extArgs += "$($_.ID):$outFile "
        $extCnt++
    }

    if($extCnt -gt 0)
    {
        Write-HostEx "Extracting $extCnt tracks..." -If ($flags.vb -ge 0)
        &mkvextract --ui-language en tracks $mkvInfo.Path $extArgs `        ($flags.GetEnumerator()| ?{$_.Value -eq $true -and $_.Key -ne "vb"} | %{"--$($_.Key)"}) `        | Tee-Object -Variable dbgLog | %{             if($_ -match '(?:Progress: )([0-9]{1,2})(?:%)')            {                $extPercent = $matches[1]                Write-Progress -Activity "   $($mkvInfo.Path | Split-Path -Leaf)" -Status "Extracting $extCnt tracks..." -PercentComplete $extPercent -CurrentOperation "$extPercent% complete" -Id 1 -ParentId 0            }            elseif($_ -match 'Error: .*')            {                Write-HostEx $matches[0] -ForegroundColor Red -If ($flags.vb -ge 0)                $mkvInfo.Tracks = $mkvInfo.Tracks | Select-Object * -ExcludeProperty _ExtractPathTrack                $mkvInfo.Tracks | ?{$_._ExtractStateTrack -eq 1} |%{ $_._ExtractStateTrack = -1}            }            elseif($_ -match "^Extracting track ([0-9]+) with the CodecID '(.*?)' to the file '(.*?) '\. Container format: (.*?)$")            {                Write-HostEx "#$($matches[1]): $($matches[3]) ($($matches[4]))" -If ($flags.vb -ge 2) -ForegroundColor Gray            }            elseif($_ -match '(?:Progress: )(100)(?:%)')            {                Write-HostEx "Done.`n" -ForegroundColor Green -If ($flags.vb -ge 0 -and $extPercent -ne 100)                $extPercent = $matches[1]                $mkvInfo.Tracks | ?{$_._ExtractStateTrack -eq 1 -and $_.CodecExt} |%{ $_._ExtractStateTrack = 2}            }            elseif($_ -match '^\(mkvextract\)')            {                Write-Verbose $_            }            elseif($_.Trim())            { Write-HostEx $_ -ForegroundColor Gray -If ($flags.vb -ge 0) }           }
    } else { Write-HostEx "No tracks to extract" -ForegroundColor Gray -If ($flags.vb -ge 2)}
    return $mkvInfo
}

function ExtractAttachments([PSCustomObject]$mkvInfo, [string]$pattern, [string]$outDir, [hashtable]$flags)
{
    if (!$outdir) {$outdir = $mkvInfo.Path | Split-Path -Parent }
    $mkvInfo.Attachments | ?{$_._ExtractState -eq 1} | %{$extArgs=@(); $extCnt=0} {
        $extCnt++
        $patternVars = @{
        '$f' = [System.IO.Path]::GetFileNameWithoutExtension($mkvInfo.Path)
        '$i' = [string]$_.UID
        '$n' = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        } 

        $patternVars.GetEnumerator() | ForEach-Object {$outFile=$pattern} { 
            $outFile = $outFile -replace [regex]::escape($_.Key), $_.Value
        }

        $outFile = "$(Join-Path $outDir $outFile)$([System.IO.Path]::GetExtension($_.Name))"
        $mkvInfo.GetAttachmentsByUID($_.UID) | Add-Member -NotePropertyName _ExtractPath -NotePropertyValue $outFile -Force

        $extArgs += "$extCnt`:$outFile "
    }

    if($extCnt -gt 0)
    {
        Write-HostEx "Extracting $extCnt attachments..." -If ($flags.vb -ge 0)
        &mkvextract --ui-language en attachments $mkvInfo.Path $extArgs `        ($flags.GetEnumerator()| ?{$_.Value -eq $true -and $_.Key -ne "vb"} | %{"--$($_.Key)"}) `        | Tee-Object -Variable dbgLog | %{ $doneCnt=0 } {            if($_ -match "^The attachment (#[0-9]+), ID (?:-)?([0-9]+), MIME type (.*?), size ([0-9]+), is written to '(.*?) '\.$")            {                $doneCnt++                $extPercent = ($doneCnt / $extCnt) * 100                Write-Progress -Activity "   $($mkvInfo.Path | Split-Path -Leaf)" -Status "Extracting $extCnt attachments..." -PercentComplete $extPercent -CurrentOperation ($matches[5] | Split-Path -Leaf) -Id 1 -ParentId 0                $mkvInfo.Attachments | ?{$_.UID -eq [uint64]$matches[2]} | %{$_._ExtractState = 2}                Write-HostEx "$($matches[1]): $($matches[5])" -If ($flags.vb -ge 2) -ForegroundColor Gray            }            elseif($_ -match 'Error: .*')            {                Write-HostEx $matches[0] -ForegroundColor Red -If ($flags.vb -ge 0)                $mkvInfo.Attachments | %{$_._ExtractState = -1}                $err = $true            }            elseif($_ -match '^\(mkvextract\)')            {                Write-Verbose $_            }            elseif($_.Trim())            { Write-HostEx $_ -ForegroundColor Gray -If ($flags.vb -ge 0) }         }

        Write-HostEx "Done.`n" -ForegroundColor Green -If ($flags.vb -ge 0 -and !$err)

    } else { Write-HostEx "No attachments to extract" -ForegroundColor Gray -If ($flags.vb -ge 2) }
    return $mkvInfo
}

function ExtractChapters([PSCustomObject]$mkvInfo, [string]$pattern, [string]$outDir, [string[]]$types, [int]$vb)
{
    if (!$outDir) {$outDir = $mkvInfo.Path | Split-Path -Parent }
    $types | %{
    
        $patternVars = @{
        '$f' = [System.IO.Path]::GetFileNameWithoutExtension($mkvInfo.Path)
        '$n' = [string]$mkvInfo.Title
        }
      
        $patternVars.GetEnumerator() | ForEach-Object {$outFile=$pattern} { 
            $outFile = $outFile -replace [regex]::escape($_.Key), $_.Value
        }

        if($_ -eq "xml" -or $_ -eq "simple")
        {
            $outFile = "$(Join-Path $outDir $outFile).$(if($_ -eq "simple"){"txt"} else {"xml"})"
            Write-HostEx "Extracting $_ chapters into `'$outFile`'" -ForegroundColor Gray -If ($vb -ge 0)
            $out = &mkvextract --ui-language en chapters $mkvInfo.Path $(if($_ -eq "simple") { "--simple" })                if ($out[0] -match "terminate called after throwing an instance")            {                Write-HostEx "Error: mkvextract terminated in an unusual way. Make sure the input file exists and is readable." -ForegroundColor Red -If ($vb -ge 0)                $err = $true            }            elseif ($out[0] -match '\<\?xml version="[0-9].[0-9]"\?\>')            {                ([xml]$out).Save($outFile)            }            elseif ($out[0] -match 'CHAPTER[0-9]+=')            {                    [string[]]$out = $out | ?{$_.Trim()}                    Set-Content -LiteralPath $outFile -Encoding UTF8 $out            }            elseif($out.Trim())            { Write-HostEx $_ -ForegroundColor Gray -If ($vb -ge 0) }            Write-HostEx "Done.`n" -ForegroundColor Green -If ($vb -ge 0 -and !$err)            } elseif ($_ -ne "none") {               Write-HostEx "Error: unsupported chapter type `"$_`"." -ForegroundColor Red -If ($vb -ge 0)        }    }
    return $mkvInfo
}
function ExtractTimecodes([PSCustomObject]$mkvInfo, [string]$pattern, [string]$outDir, [int]$vb)
{
    if (!$outdir) {$outdir = $mkvInfo.Path | Split-Path -Parent }
    $mkvInfo.Tracks | ?{$_._ExtractStateTimecodes -eq 1} | %{$extArgs=@(); $extCnt=0} {
        $patternVars = @{
        '$f' = [System.IO.Path]::GetFileNameWithoutExtension($mkvInfo.Path)
        '$i' = [string]$_.ID
        '$t' = [string]$_.Type
        '$n' = [string]$_.Name
        '$l' = [string]$_.Language
        '$v' = "v2"
        } 

        $patternVars.GetEnumerator() | ForEach-Object {$outFile=$pattern} { 
            $outFile = $outFile -replace [regex]::escape($_.Key), $_.Value
        }

        $outFile = "$(Join-Path $outDir $outFile).txt"
        $mkvInfo.GetTracksByID($_.ID) | Add-Member -NotePropertyName _ExtractPathTimecodes -NotePropertyValue $outFile -Force

        $extArgs += "$($_.ID):$outFile "
        $extCnt++
    }

    if($extCnt -gt 0)
    {
        $extMsg = "Extracting timecodes for $extCnt tracks..."
        Write-HostEx $extMsg -If ($vb -ge 0)
        &mkvextract --ui-language en timecodes_v2 $mkvInfo.Path $extArgs `        $(if($vb -ge 3) { "--verbose" }) `        | Tee-Object -Variable dbgLog | %{             if($_ -match '(?:Progress: )([0-9]{1,2})(?:%)')            {                $extPercent = $matches[1]                Write-Progress -Activity "   $($mkvInfo.Path | Split-Path -Leaf)" -Status $extMsg -PercentComplete $extPercent -CurrentOperation "$extPercent% complete" -Id 1 -ParentId 0            }            elseif($_ -match 'Error: .*')            {                Write-HostEx $matches[0] -ForegroundColor Red -If ($vb -ge 0)                $mkvInfo.Tracks = $mkvInfo.Tracks | Select-Object * -ExcludeProperty _ExtractPathTimecodes                $mkvInfo.Tracks | ?{$_._ExtractStateTimecodes -eq 1} |%{ $_._ExtractStateTimecodes = -1}            }            elseif($_ -match '(?:Progress: )(100)(?:%)')            {                Write-HostEx "Done.`n" -ForegroundColor Green -If ($vb -ge 0 -and $extPercent -ne 100)                $extPercent = $matches[1]                $mkvInfo.Tracks | ?{$_._ExtractStateTimecodes -eq 1 } |%{ $_._ExtractStateTimecodes = 2}            }            elseif($_ -match '^\(mkvextract\)')            {                Write-Verbose $_            }            elseif($_.Trim())            { Write-HostEx $_ -ForegroundColor Gray -If ($vb -ge 0) }           }
    } else { Write-HostEx "No timecodes to extract" -ForegroundColor Gray -If ($vb -ge 2)}
    return $mkvInfo
}

Export-ModuleMember Extract-Mkv