@ECHO off
SETLOCAL EnableDelayedExpansion

SET "SpamListFile=cssspamiplist.txt"
SET "FileDownloadAddress=https://sub.example.tld/cssspamiplist.txt"
SET "FireWallRuleName=CSS_SpamFilter"
REM blocksize to be 200. Low value for testing
SET /A BlockSize=3

:MAIN
	CALL :ADMINAUTHCHECK
	CALL :DIRECTORYSETCURRENT
	CALL :ARGUMENTCHECK
	REM CALL :DOWNLOADSPAMLIST
	CALL :READFILETOIPBLOCKS
	CALL :DELETEOLDFIREWALLRULES
	CALL :CREATEFIREWALLRULES
	CALL :LISTEXISTINGRULES
	CALL :MESSAGEUPDATED
	PAUSE
GOTO :EOF

:ADMINAUTHCHECK            
	REM Check for permissions  
	FSUTIL dirty query %SystemDrive% >nul 
	
	IF "%errorlevel%" EQU "0" (
		GOTO :EOF
	)
	
	REM If error flag set request admin  
	IF "%errorlevel%" NEQ "0" (
		ECHO Requesting Administrative Privileges...
		CALL :VBSRUNASADMINUAC
	)
GOTO :EOF	

:VBSRUNASADMINUAC
    set _Args = %*:"=""

	REM check if the temp file we are going to make exists
	IF EXIST "%temp%\~ElevateToAdmin.vbs" (
		DEL "%temp%\~ElevateToAdmin.vbs"
	)
	
	REM Write to vbs a file that code to re-launch as admin
	ECHO Set UAC = CreateObject^("Shell.Application"^) > "%temp%\~ElevateToAdmin.vbs"
    ECHO UAC.ShellExecute "cmd.exe", "/c %~s0 %_Args%", "", "runas", 1 >> "%temp%\~ElevateToAdmin.vbs"
	
	REM launch using the vbs script and then delete the vbs script
	CSCRIPT "%temp%\~ElevateToAdmin.vbs"
	DEL "%temp%\~ElevateToAdmin.vbs"
	EXIT
GOTO :EOF

:DIRECTORYSETCURRENT
    PUSHD "%~dp0"
	ECHO Running as Admin
	REM ECHO.
	COLOR 0a
GOTO :EOF

:ARGUMENTCHECK
	IF "%1"=="list" (
		CALL :LISTEXISTINGRULES
		PAUSE
		EXIT /b
	)
GOTO :EOF

:DOWNLOADSPAMLIST
	REM Download new IP's
	IF EXIST %~dp0\%SpamListFile% (
		ECHO %SpamListFile% exists
		ECHO Copying %SpamListFile% to %SpamListFile%_backup.txt
		COPY "%SpamListFile%" "%SpamListFile%_backup.txt"
		ECHO.
	)
	
	ECHO Downloading the current IP list
	powershell -Command "Invoke-WebRequest %FileDownloadAddress% -OutFile %SpamListFile%"
	
	IF NOT EXIST %~dp0\%SpamListFile% (
		CALL :DOWNLOADFAILED
	)
	
GOTO :EOF

:DOWNLOADFAILED
	COLOR 0c
	ECHO.
	ECHO Unable to download %SpamListFile%
	ECHO From %FileDownloadAddress%
	ECHO.
	PAUSE
	EXIT
GOTO :EOF

:READFILETOIPBLOCKS
REM Make IP blocks
	SET "IpAddressBlock="
	SET /A IpCount=0
	SET /A BlockCount=1
	
	FOR /F %%i IN (%SpamListFile%) DO (
		SET /A IpCount+=1

		IF NOT "!IpAddressBlock!" == "" (
			SET IpAddressBlock=!IpAddressBlock!,%%i
		)
		
		IF "!IpAddressBlock!" == "" (  
			SET IpAddressBlock=%%i
		)
		
		SET IpBlock[!BlockCount!]=!IpAddressBlock!
		
		IF !IpCount! == %BlockSize% (
			SET /A BlockCount+=1
			SET /A IpCount=0
			SET "IpAddressBlock="
		)
	)
	
	REM remove empty last block
	IF "!IpAddressBlock!" == "" (  
		SET /A BlockCount-=1
	)
GOTO :EOF

:DELETEOLDFIREWALLRULES
	ECHO Deleting existing old spam block/s of IPs
	
	SET /A RULECOUNT=0
	
	for /f %%i in ('netsh advfirewall firewall show rule name^=all ^| findstr %FireWallRuleName%in') do (
	  SET /A RULECOUNT+=1
	  netsh advfirewall firewall delete rule name="%FireWallRuleName%in[!RULECOUNT!]" >>nul
	)
	
	SET /A RULECOUNT=0
	
	for /f %%i in ('netsh advfirewall firewall show rule name^=all ^| findstr %FireWallRuleName%out') do (
	  SET /A RULECOUNT+=1
	  netsh advfirewall firewall delete rule name="%FireWallRuleName%out[!RULECOUNT!]" >>nul
	)
	
	SET "RULECOUNT="
GOTO :EOF

:CREATEFIREWALLRULES
	ECHO Creating InBound and OutBound Rules
	FOR /L %%G IN (1,1,%BlockCount%) DO (
		netsh advfirewall firewall add rule name="%FireWallRuleName%in[%%G]" protocol=any dir=in action=block remoteip=!IpBlock[%%G]! >>nul
		netsh advfirewall firewall add rule name="%FireWallRuleName%out[%%G]" protocol=any dir=out action=block remoteip=!IpBlock[%%G]! >>nul
	)
GOTO :EOF

:LISTEXISTINGRULES
	SET /A "RULECOUNT=0"
	
	ECHO List InBound Rules:
	FOR /f %%i in ('NETSH advfirewall firewall show rule name^=all ^| FINDSTR %FireWallRuleName%in') do (
		SET /A RULECOUNT+=1
		NETSH advfirewall firewall show rule %FireWallRuleName%in[!RULECOUNT!] | FINDSTR RemoteIP
	)
	
	SET /A "RULECOUNT=0"
	
	ECHO List OutBound Rules:
	FOR /f %%i in ('NETSH advfirewall firewall show rule name^=all ^| FINDSTR %FireWallRuleName%out') do (
		SET /A RULECOUNT+=1
		NETSH advfirewall firewall show rule %FireWallRuleName%out[!RULECOUNT!] | FINDSTR RemoteIP
	)
	SET "RULECOUNT="
GOTO :EOF

:MESSAGEUPDATED
	ECHO Updated with the current IP's and should have less spam once you refresh the server list.
	ECHO Still have spam? Please submit the spam server IP to xxxxxxxxxxx
GOTO :EOF


