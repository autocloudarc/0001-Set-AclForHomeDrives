#requires -version 4.0
#requires -RunAsAdministrator
<#
****************************************************************************************************************************************************************************
PROGRAM		: 0001-Set-AclForHomeDrivesFromInputFiles.ps1
DESCIRPTION	: Takes administrative ownership of files and folders from individual users and resets permissions. This script will process all users home folders unless there 
              isn't a corresponding user still in AD (in cases where the user has left the organization, but their home folder remains) 
              #CONFIG tags are used to indicate which variables you will need to change to reflect own environment during script exectuion. 
              Permissions will be set to individual user and user subfolders based on what is confgiured at the \\<server-fqdn\home level.
PARAMETERS	:
INPUTS		: You will be prompted for the home directory share path for the $TargetPath varialbe, as well as the log path for the $LogPath variable. 
OUTPUTS		:
EXAMPLES	: Set-AclForHomeDrivesFromInputFiles.ps1
REQUIREMENTS: PowerShell Version 4.0, Run as administrator
LIMITATIONS	: NA
AUTHOR(S)	: Preston K. Parsard
EDITOR(S)	: 
REFERENCES	: 
1. https://technet.microsoft.com/en-us/magazine/2008.02.powershell.aspx

KEYWORDS	: Directory, files, folders, permissions, Acl, ownership, access

LICENSE:

The MIT License (MIT)
Copyright (c) 2016 Preston K. Parsard

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software. 

DISCLAIMER:

THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, 
INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a nonexclusive, 
royalty-free right to use and modify the Sample Code and to reproduce and distribute the Sample Code, provided that You agree: (i) to not use Our name, 
logo, or trademarks to market Your software product in which the Sample Code is embedded; 
(ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, 
and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys’ fees, 
that arise or result from the use or distribution of the Sample Code.
****************************************************************************************************************************************************************************
#>

<# WORK ITEMS
TASK-INDEX: 
#>

<# 
***************************************************************************************************************************************************************************
REVISION/CHANGE RECORD	
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DATE        VERSION    NAME               CHANGE
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------
10 APR 2016 01.29.0000 Preston K. Parsard Initial publication release
23 APR 2016 00.29.0001 Preston K. Parsard Parameterized inputs for target home directory and script log path variables to make script more portable
23 APR 2016 00.29.0002 Preston K. Parsard Specified green and yellow for original and emphases foreground colors during script execution
01 MAY 2016 00.00.0032 Preston K. Parsard Parameterized batch limit so that user executing script can specify how many folders to process per script execution
01 MAY 2016 00.00.0033 Preston K. Parsard Set log size unit from 1kb to 1mb as default value in comments
11 MAY 2016 00.00.0030 Preston K. Parsard Parameterized inputs for target home directory and script log path variables to make script more portable
11 MAY 2016 00.00.0031 Preston K. Parsard Specified green and yellow for original and emphasis foreground colors during script execution
11 MAY 2016 00.00.0032 Preston K. Parsard Parameterized batch limit so that user executing script can specify how many folders to process per script execution
11 MAY 2016 00.00.0033 Preston K. Parsard Special permissions were being applied, the details of which can only be seen in the advanced permissions setting.
                                          ...updated so that full permissions are explecitly defined in users ACE in basic settings. This will reduce complexity and aid in
					  ...better readability and easier troubleshooting.
11 MAY 2016 00.00.0034 Preston K. Parsard Removed duplicate $Processed++ counter which was providing a false indication of twice the number of users processed
22 MAY 2016  00.00.0009 Preston K. Parsard Updated filename to: 0001-Set-AclForHomeDrivesFromInputFiles.ps1 in order to index and tag as a contributed script
#>

#region INITIALIZE VALUES	

$BeginTimer = Get-Date

# Setup script execution environment
Clear-Host 
# Set foreground color 
$OriginalForeground = "Green"
$EmphasisForeground = "Yellow"
$host.ui.RawUI.ForegroundColor = $OriginalForeground

# Create and populate prompts object with property-value pairs
# PROMPTS (PromptsObj)
$PromptsObj = [PSCustomObject]@{
 pAskToOpenLog = "Would you like to open the log now ? [YES/NO]"
} #end $PromptsObj

# Create and populate responses object with property-value pairs
# RESPONSES (ResponsesObj): Initialize all response variables with null value
$ResponsesObj = [PSCustomObject]@{
 pOpenLogNow = $null
} #end $ResponsesObj

# CONFIG: Change the $TargetPath value below to reflect the home drive path you whish to use in your own environment using the format below
# $TargetPath = "\\FileServer.domain.com\home"
Do
{
 $host.ui.RawUI.ForegroundColor = $EmphasisForeground
 Write-Host("Please enter the target path for your user home folders directory, i.e. \\fs1.litware.lab\home ")
 [string] $TargetPath = Read-Host
 $host.ui.RawUI.ForegroundColor = $OriginalForeground
 Write-Host("")
} #end Do
Until (($TargetPath) -ne $null)

$ColumnWidth = 108
$EmptyString = ""
$DoubleLine = ("=" * $ColumnWidth)
$SingleLine = ("-" * $ColumnWidth)
[int]$l= 0

# CONFIG: Change the the $LogPath value below to reflect the log path you whish to use in your own environment using the format below
# $LogPath = "\\FileServer.domain.com\logs"

Do
{
 $host.ui.RawUI.ForegroundColor = $EmphasisForeground
 Write-Host("Please enter the log path where the output for this script will be saved, i.e. \\fs1.litware.lab\logs ")
 [string] $LogPath = Read-Host
 $host.ui.RawUI.ForegroundColor = $OriginalForeground
} #end Do
Until (($LogPath) -ne $null)

$InputFilePendingFolder = "InputFiles-PENDING"
$InputFilePendingPath = Join-Path $LogPath -ChildPath $InputFilePendingFolder
$InputFileProcessedFolder = "InputFiles-PROCESSED"
$InputFileProcessedPath = Join-Path $LogPath -ChildPath $InputFileProcessedFolder

$StartTime = (((get-date -format u).Substring(0,16)).Replace(" ", "-")).Replace(":","")

Function Script:New-Log
{
  [int]$Script:l++
  # Create log file with a "u" formatted time-date stamp
  $LogFile = "Set-AclForHomeDrives" + "-" + $StartTime + "-" + [int]$Script:l + ".log"
  $Script:Log = Join-Path -Path $LogPath -ChildPath $LogFile
  New-Item -Path $Script:Log -ItemType File -Force
} #end function

New-Log

Function Get-LogSize
{
 $LogObj = Get-ChildItem -Path $Log 
 # CONIFIG: Use 1mb for production, 1kb for testing. Default value will be [1mb]
 $LogSize = ([System.Math]::Round(($LogObj.Length/1mb)))
 If ($LogSize -gt 10)
 {
  ShowAndLog("")
  ShowAndLog("------------------------")
  ShowAndLog("Creating new log file...")
  ShowAndLog("------------------------")
  # Create a new log with new index and timestamp
  $LogSize = 0
  New-Log
 } #end if
} #end function

$DelimDouble = ("=" * 100 )
$Header = "RESET ACL AND OWNERSHIP PERMISSION FOR HOME DIRECTORIES: " + $StartTime

# Index to uniquely identify each line when logging using the LogWithIndex function
$Index = 0
# Number of users to process during task scheduled execution of this script
# Populate Summary Display Object
# Add properties and values
# Make all values upper-case
 $SummObj = [PSCustomObject]@{
  TARGETPATH = $TargetPath.ToUpper()
  LOGFILE = $Log
 } #end $SummObj

# Send output to both the console and log file
Function ShowAndLog
{
[CmdletBinding()] Param([Parameter(Mandatory=$True)]$Output)
$Output | Tee-Object -FilePath $Log -Append
} #end ShowAndLog

# Send output to both the console and log file and include a time-stamp
Function LogWithTime
{
[CmdletBinding()] Param([Parameter(Mandatory=$True)]$LogEntry)
# Construct log time-stamp for indexing log entries
# Get only the time stamp component of the date and time, starting with the "T" at position 10
$TimeIndex = (get-date -format o).ToString().Substring(10)
$TimeIndex = $TimeIndex.Substring(0,17)
"{0}: {1}" -f $TimeIndex,$LogEntry 
} #end LogWithTime

# Send output to both the console and log file and include an index
Function Script:LogWithIndex
{
[CmdletBinding()] Param([Parameter(Mandatory=$True)]$LogEntry)
# Increment QA index counter to uniquely identify this item being inspected
$Script:Index++
"{0}`t{1}" -f $Script:Index,$LogEntry | Tee-Object -FilePath $Log -Append
} #end LogWithIndex

# Send output to log file only
Function LogToFile
{
[CmdletBinding()] Param([Parameter(Mandatory=$True)]$LogData)
$LogData | Out-File -FilePath $Log -Append
} #end LogToFile

#endregion INITIALIZE VALUES


#region MAIN	

# Clear-Host 

# Display header
ShowAndLog($DelimDouble)
ShowAndLog($Header)
ShowAndLog($DelimDouble)

# If the input file path does already exist...
If (Test-Path("$InputFilePendingPath"))
{
 ShowAndLog("Input files directory does exist...")
 # ...and there are no input files in the directory, then we can assume that all files have already been processed
 If ((Get-ChildItem -Path $InputFilePendingPath).Count -eq 0)
 {
  ShowAndLog("No input files are available to process. Exiting script...")
  pause
  exit
 } #end if
} #end if

ShowAndLog("Processing directories...")
# Index for each user
$UserCount = 0
# Number of users processed
$Processed = 0
# Base ACL reference to use for applying to subfolders and files for administrative access
$AclPreSet = Get-Acl $TargetPath
# Specify the number of user home folders that will be processed per script execution
$BatchLimit = $null
Do
{
 $host.ui.RawUI.ForegroundColor = $EmphasisForeground
 Write-Host("Specify the number of user home folders that will be processed per script execution, i.e. 3")
 Write-Host("During testing of less than 20 folders, a batch limit of 3 is recommended, however in production you may increase this limit as appropriate")
 [int]$BatchLimit = Read-Host
 $host.ui.RawUI.ForegroundColor = $OriginalForeground
} #end Do
Until (($BatchLimit) -ne $null)

# Get all user folders
$UserIdFolders = Get-ChildItem -Path $TargetPath
$UserIdFolderPaths = $UserIdFolders.FullName
# Split user folders based on batch limit
ShowAndLog("Creating input files for batch processing of user home folders")
$TotalUserFolders = $UserIdFolderPaths.Length
$TotalInputFiles = [int]($TotalUserFolders / $BatchLimit)
# If there are leftover paths less than the batch limit, add an extra file as the last one
If ($TotalUserFolders % $BatchLimit)
{
 $TotalInputFiles++
} #end 

# If the input path has not yet been created, this must be the first time the script is run, so create the path and populate all input files
If (!(Test-Path("$InputFilePendingPath")))
{
 # Create pending directory
 ShowAndLog("Input files directory to process does not already exists. Creating $InputFilePendingPath ...")
 New-Item -Path $InputFilePendingPath -ItemType Directory -Force 
 # Create all input files
 $BatchIndexStart = 0
 for ($y = 0; $y -lt $TotalInputFiles; $y++)
 {
  $InputFile = "UserFoldersBatch" + "-" + $StartTime + "-" + ($y+1) + ".txt"
  $NewInputFile = Join-Path -Path $InputFilePendingPath -ChildPath $InputFile
  New-Item -Path $NewInputFile -ItemType File -Force
  $BatchIndexStop = $BatchIndexStart + $BatchLimit
  If ($BatchIndexStop -gt $TotalUserFolders)
  { 
   $BatchIndexStop = $TotalUserFolders
  } #end if
  For ($fi = $BatchIndexStart; $fi -lt $BatchIndexStop; $fi++)
  {
   $UserIdFolderPaths[$fi] | Out-File -FilePath $NewInputFile -Append
  } #end for
  $BatchIndexStart = $BatchIndexStart + $BatchLimit
 } #end for
} #end test-path

# Create processed directory if it doesn't already exist
If (!(Test-Path("$InputFileProcessedPath")))
{
 # Create processed directory
 ShowAndLog("Input files which have been processed directory does not already exists. Creating $InputFileProcessedPath ...")
 New-Item -Path $InputFileProcessedPath -ItemType Directory -Force 
} #end if

$TargetAcl = Get-Acl $TargetPath
# Netbios domain name
$Domain = (Get-ADDomain).NetBiosName
# Level of access for each user to their own home folders
$Right = "FullControl"
  
$CurrentInputfile = (Get-ChildItem -Path $InputFilePendingPath | Sort-Object $_ | Select-Object -first 1).FullName
[array]$HomeFolderPaths = Get-Content -Path $CurrentInputfile

$HomeFolderPaths | Select-Object {
 takeown /f $_ /r /a /d y >> $Log
 . Get-LogSize
} #end select-object

. Get-LogSize 

# For netapps CIFS file server objects, the takeown command will be necessary to taking ownership from the root home level and supress prompts
# Fix permissions for administrative access (which temporarily removes user access)
Function FixPermissions
{
 ShowAndLog("Reseting administrative permissions on user files and folders...")
 $FixPermsError = $null
 ForEach ($HomeFolderPath in $HomeFolderPaths)
 {
  Get-ChildItem -Path $HomeFolderPath -Recurse -Force | Set-Acl -AclObject $TargetAcl -Passthru -ErrorVariable $FixPermsError
  While ($FixPermsError) 
   {
    # If the FixPermissions function failed, continue to attempt resetting administrative permissions on user files and folders until succesfull
    ForEach ($HomeFolderPath in $HomeFolderPaths)
    { 
     Get-ChildItem -Path $HomeFolderPath -Recurse -Force | Set-Acl -AclObject $TargetAcl -Passthru
    } #end foreach
   } #end while
  } #end foreach
} #end function

FixPermissions

. Get-LogSize

# Calculate last \ separator in homefolder path to separate just the home folder name
$HomeFolderIndex = (($HomeFolderPaths[0] -split "\\").Count - 1)

# Re-add users to ACL for their home folder and all subfolders
 for ($q = 0; $q -lt $BatchLimit; $q++)
 {
  $FullHomeFolderPath = $HomeFolderPaths[$q]
  $CurrentHomeFolder = $FullHomeFolderPath.Split("\\").Item($HomeFolderIndex)
  $User = Get-ADUser -Filter {sAMAccountName  -eq $CurrentHomeFolder}
  If ($User)
  {
   ShowAndLog($DoubleLine)
   LogWithIndex("Processing ACL for user $CurrentHomeFolder")
   $Principal = "$Domain\$CurrentHomeFolder"
   # Reset user rights as full NTFS permissions recursively to their home folder and all subfolders and files below it, while not modifying any other ACEs
   icacls ("$FullHomeFolderPath") /grant ("$Principal" + ':(OI)(CI)F') /T
   $Processed++
 } #end If
 else
 {
  ShowAndLog("User: $CurrentHomeFolder was not found in AD")
 } #end else
} #end for

. Get-LogSize

ShowAndLog("")
ShowAndLog("Last user processed: $CurrentHomeFolder")
#endregion MAIN

#region FOOTER		

If (Test-Path("$InputFileProcessedPath"))
{
 # Move completed input file from pending to processed folder
 ShowAndLog("Completed input file will now be moved to: $InputFileProcessedPath ...")
 Move-Item -Path $CurrentInputFile -Destination $InputFileProcessedPath -Force
} #end if

# Calculate elapsed time
ShowAndLog("Calculating script execution time...")
$StopTimer = Get-Date
$EndTime = (((Get-Date -format u).Substring(0,16)).Replace(" ", "-")).Replace(":","")
$ExecutionTime = New-TimeSpan -Start $BeginTimer -End $StopTimer

$Footer = "SCRIPT COMPLETED AT: "
[int]$TotalUsers = $Processed

ShowAndLog($DelimDouble)
ShowAndLog($Footer + $EndTime)
ShowandLog("# of users processed: $Processed")
ShowAndLog("Total # of users evaluated: $TotalUsers")
ShowAndLog("TOTAL SCRIPT EXECUTION TIME: $ExecutionTime")
ShowAndLog($DelimDouble)

# Prompt to open log
# CONFIG: Comment out the entire prompt below (Do...Until loop) after testing is completed and you are ready to schedule this script. This is just added as a convenience during testing.

Do 
{
 $ResponsesObj.pOpenLogNow = read-host $PromptsObj.pAskToOpenLog
 $ResponsesObj.pOpenLogNow = $ResponsesObj.pOpenLogNow.ToUpper()
}
Until ($ResponsesObj.pOpenLogNow -eq "Y" -OR $ResponsesObj.pOpenLogNow -eq "YES" -OR $ResponsesObj.pOpenLogNow -eq "N" -OR $ResponsesObj.pOpenLogNow -eq "NO")

# Exit if user does not want to continue
if ($ResponsesObj.pOpenLogNow -eq "Y" -OR $ResponsesObj.pOpenLogNow -eq "YES") 
{
 Start-Process notepad.exe $Log
} #end if


# End of script
LogWithTime("END OF SCRIPT!")

#endregion FOOTER

# CONFIG: Remove pause statement below for production run in your environment. This has only been added as a convenience during testing so that the powershell console isn't lost after the script completes.
Pause
Exit